package AnyEvent::Curl;

use strict;
use warnings;
our $VERSION = '0.01';

use Carp;
use AnyEvent;
use WWW::Curl::Easy;
use WWW::Curl::Multi;
use AnyEvent::Curl::Response;
use Data::Dumper;
# use Time::HiRes qw(gettimeofday tv_interval);

sub new {
    my $class = shift;
    my %config = @_;
    my $curlm = WWW::Curl::Multi->new;
    my $self = {
        req_id => 1,
        active => 0,
        curlm  => $curlm,
        result => {},
        read_io => {},
        write_io => {},
        # curl options
        options => $class->default_options,
    };
    # $self->{w} = AE::timer 0, 1, sub { warn Dumper $self->{watch} };
    $self->{queue} = []; 
    $self->{config} = {};
    $self->{config}->{max_parallel} = delete $config{max_parallel} || 1000;
    bless $self, $class;
}

sub gen_id {
    my $self = shift;
    $self->{req_id}++;
}

sub active { shift->{active} }

sub setopt {
    my $self = shift;
    my ($key, $value) = @_;
    $key = "CURLOPT_" . uc $key;
    croak "Unknown option: $key" unless WWW::Curl::Easy->can($key);
    $self->{options}->{WWW::Curl::Easy->$key} = $value;
}

sub default_options {
    +{
        CURLOPT_FOLLOWLOCATION() => 1,
        CURLOPT_MAXREDIRS()      => 7, 
    }
}

my %CONST_CACHE;

sub c($) {
    my $key = shift;
    $CONST_CACHE{$key} ||= WWW::Curl::Easy->$key;
}

sub _setopt {
    my $curl = shift;
    my ($key, $value) = @_;
    $key = "CURLOPT_" . uc $key;
    croak "Unknown option: $key" unless WWW::Curl::Easy->can($key);
    $curl->setopt(c($key), $value);
}

sub add {
    my $self = shift;
    my ($req, $cb, $opt) = @_;

    my $id = $self->gen_id;
    my $curl = WWW::Curl::Easy->new;

    my $url;
    if (ref $req && $req->isa('HTTP::Request')) {
        $url = $req->uri;
        my $head = [ split "\n", $req->headers->as_string ];
        # warn Dumper $head;
        $curl->setopt( c("CURLOPT_CUSTOMREQUEST"), $req->method);
        $curl->setopt( c("CURLOPT_HTTPHEADER"), $head);
        if ($req->content){
            my $post = $req->content;
            # warn length $post;
            _setopt($curl, postfields => $post);
            _setopt($curl, postfieldsize => length $post);
        }
    } else {
        $url = $req;
    }
    
    $curl->setopt(c("CURLOPT_URL"), $url );
    $curl->setopt(c("CURLOPT_PRIVATE"), $id );

    my $body = "";
    my $head = "";

    # use PerlIO
    if (open my $fh, ">", \$body) { $curl->setopt(c("CURLOPT_WRITEDATA"), $fh) }
    if (open my $fh, ">", \$head) { $curl->setopt(c("CURLOPT_WRITEHEADER"), $fh) }
    # $curl->setopt(c("CURLOPT_HEADERFUNCTION"), sub { $head .= $_[0]; 1 }); # Slow

    # setup common options 
    my $options = $self->{options};
    for (keys %{ $options }) {
        $curl->setopt($_ => $options->{$_});
    }
    # setup request options
    if ($opt && ref $opt) {
        for (keys %{$opt}) {
            _setopt($curl, $_, $opt->{$_})
        }
    }

    my $cv = AE::cv;
    $cb = sub {} unless $cb; 
    $self->{result}->{$id} = +{
        curl   => $curl,
        request => $req,
        body   => \$body,
        header => \$head,
        cb     => $cb,
        cv     => $cv,
    };

    if ($self->active >= $self->{config}->{max_parallel}) {
        push @{$self->{queue}}, $curl;
    } else {
        $self->{active}++;
        $self->{curlm}->add_handle($curl);
    }

    if ($self->{start}) {
        $self->start
    }
    return $cv;
}

sub dequeue {
    my $self = shift;
    if (my $curl = shift @{$self->{queue}}) {
        # warn "dequeue";
        $self->{active}++;
        $self->{curlm}->add_handle($curl);
    }
}

sub start {
    my $self = shift;
    $self->{start} = 1;
    $self->{check_fh_timer} = AE::timer 0, 0.5, sub { $self->check_fh(1) };
    if (!$self->{cv}) {
        my $cv = $self->{cv} = AE::cv;
        return $cv;
    }
    $self->{cv};
}

sub wait {
    my $self = shift;
    $self->start unless $self->{start};
    $self->{cv}->wait;
    delete $self->{cv};
    1;
}

sub check_fh {
    my $self = shift;
    my $perform = shift;
    my $curlm = $self->{curlm};
    $curlm->perform if $perform;
    my ($rio, $wio, $eio) = $curlm->fdset;
    
    $self->_watch($rio, "read");
    $self->_watch($wio, "write");

    if (@{$rio} == 0 && @{$wio} == 0) {
        # read last response
        if ($perform) { $self->on_progress }
        # there is active request, but no fdset alivable, set wait timer
        if ($self->{active}) {
            # warn "add wait";
            $self->{check_fh_timer2} = AE::timer 0, 0, sub {
                $self->on_progress;
            };
        } else {
            # complete all request
            $self->_all_task_done;
        }
    }
}

sub _watch {
    my ($self, $fd_ref, $type) = @_;
    my $new_io = {};
    my $key = $type . "_io";
    my $w = $self->{$key};
    my $rw = ($type eq "read") ? 0 : 1;
    # watch io by AE
    my $cb = $self->{__io_cb} ||=  sub {
        my $remain = $self->on_progress;
        $self->_all_task_done unless $remain;
    };
    for (@{$fd_ref}) {
        $new_io->{$_} = $w->{$_} || AE::io $_, $rw, $cb;
    }
    $self->{$key} = $new_io;
}

sub on_progress {
    my $self = shift;
    # warn "progress";
    my $curlm = $self->{curlm};
    my $active = $curlm->perform;

    # warn "perform";
    if ( $active != $self->{active} ) {
        while ( my ( $id, $rval ) = $curlm->info_read ) {
            $self->_complete($id, $rval) if ($id);
        }
        $self->check_fh;
    }
    $self->{active};
}

sub _complete {
    my ($self, $id, $rval) = @_;
    $self->{active}--;
    my $res = $self->{result}->{$id};
    my $curl = $res->{curl};
    $res->{rc} = $curl->getinfo(c("CURLINFO_HTTP_CODE"));
    $res->{redirect} = $curl->getinfo(c("CURLINFO_REDIRECT_COUNT"));
    $res->{error} = $curl->strerror($rval) if $rval;
    my $response = AnyEvent::Curl::Response->new($res);
    $res->{cb}->($response);
    $res->{cv}->send($response);
    delete $self->{result}->{$id};
    $self->dequeue;
}

sub _all_task_done {
    my $self = shift;
    if ($self->{cv}) {
        $self->{cv}->send(1);
        delete $self->{cv};
    }
}

sub clone {
    my $self = shift;
    my $class = ref $self;
    my $clone = $class->new;
    $clone->{options} = +{ %{$self->{options}} };
    $clone;
}

sub STORABLE_freeze {
    my $self = shift;
    my $class = ref $self;
    my $clone = $self->clone;
    delete $clone->{curlm};
    return ($class, +{ %{$clone} });
}

sub STORABLE_thaw {
    my ($self, $clone, $string, $refs) = @_;
    for (keys %{$refs}) {
        $self->{$_} = $refs->{$_}
    }
    $self->{curlm} = WWW::Curl::Multi->new;
}

1;

__END__

=head1 NAME

AnyEvent::Curl - faster non-blocking http client

=head1 SYNOPSIS

  use AnyEvent::Curl;
  my $curl = AnyEvent::Curl->new;
  my $cv = $curl->start; # start event loop of Curl
  for (1..10) {
      my $cv = $curl->add($request, $callback); # $request is URL or HTTP::Request object
      # my $res = $cv->recv; # wait one request
      # $cv->callback(sub { ... }); # use AE::cv 
  }
  warn $curl->active; # check active
  $cv->wait; # wait all request

=head1 DESCRIPTION

AnyEvent::Curl is wrapper for WWW::Curl using AnyEvent.

5-10x faster than LWP. Just a primitive interface for speed.

=head1 METHODS

=head2 add($req, $callback )

    # basic
    $curl->add("http://example.com/", sub {
        my $res = shift; # AnyEvent::Curl::Response object
        $res->code;
        $res->is_success;
        $res->content;
        $res->http_response; # get HTTP::Response object
    });

    # using AE::cv
    $cv = $curl->add("http://example.com/");
    $cv->callback(sub { my $res = shift; ... });

=head2 setopt(key, value)

    # other option here 
    # http://curl.haxx.se/libcurl/c/curl_easy_setopt.html

    $curl->setupt(useragent => "custom UA name"); # UserAgent

    $curl->setopt(followlocation => 1); # 0 to disable redirects
    $curl->setopt(maxredirs => 7); # max redirect
    $curl->setopt(autoreferer => 1); # set referer on redirect

    $curl->setopt(tcp_nodelay => 1); # for fast response, but throughput
    $curl->setopt(encoding => ""); # gzip etc. "" to auto.

    $curl->setopt(verbose => 1); # debug
    $curl->setopt(header  => 1); # write header to body.
 
    # you can register callback function
    $curl->setopt(headerfunction => sub { $head .= $_[0]; length $_[0] } ); 
    $curl->setopt(writefunction  => sub { $body .= $_[0]; length $_[0] } );

    $curl->setopt(interface => "127.0.0.1"); # interface name or IP to use.

    $curl->setopt(noprogress => 0); # show progress bar

=head2 active

    return active handle num
    
=head1 AUTHOR

mala E<lt>cpan@ma.laE<gt>

=head1 SEE ALSO

L<WWW::Curl>, L<AnyEvent::HTTP>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
