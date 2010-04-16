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

sub new {
    my $class = shift;
    my $curlm = WWW::Curl::Multi->new;
    my $self = {
        req_id => 1,
        active => 0,
        curlm  => $curlm,
        result => {},
        read_io => {},
        write_io => {},
        options => $class->default_options,
    };
    # $self->{w} = AE::timer 0, 1, sub { warn Dumper $self->{watch} };
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
    $self->{options}->{$key} = $value;
}

sub default_options {
    +{
        CURLOPT_FOLLOWLOCATION() => 1,
        CURLOPT_MAXREDIRS()      => 7, 
    }
}

sub add {
    my $self = shift;
    my ($req, $cb) = @_;

    my $id = $self->gen_id;
    my $curl = WWW::Curl::Easy->new;

    my $url;
    if (ref $req && $req->isa('HTTP::Request')) {
        $url = $req->uri;
        my $head = $req->headers->as_string;
        $curl->setopt( CURLOPT_HTTPHEADER, [$head]);
    } else {
        $url = $req;
    }
    
    $curl->setopt( CURLOPT_URL, $url );
    $curl->setopt( CURLOPT_PRIVATE, $id );

    my $body = "";
    my $head = "";

    # use PerlIO
    if (open my $fh, ">", \$body) { $curl->setopt(CURLOPT_WRITEDATA, $fh) }
    if (open my $fh, ">", \$head) { $curl->setopt(CURLOPT_WRITEHEADER, $fh) }
    
    my $options = $self->{options};
    for (keys %{ $options }) {
        $curl->setopt($_ => $options->{$_});
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
    $self->{active}++;
    $self->{curlm}->add_handle($curl);
    return $cv;
}

sub start {
    my $self = shift;
    my $cv = $self->{cv} = AE::cv;
    $self->check_fh;
    $cv;
}

sub wait {
    my $self = shift;
    $self->start unless $self->{cv};
    $self->{cv}->wait;
}

sub check_fh {
    my $self = shift;
    my $curlm = $self->{curlm};
    $curlm->perform;

    # warn Dumper $curlm->fdset;
    my ($rio, $wio, $eio) = $curlm->fdset;
   
    $self->_watch($rio, "read");
    $self->_watch($wio, "write");

    if (@{$rio} == 0 && @{$wio} == 0) {
        my $remain = $self->on_progress;
        $self->{cv}->send;
    }
}

sub _watch {
    my ($self, $fd_ref, $type) = @_;

    my %exists = map { ($_ => 1) } @{$fd_ref};
    my $w = $self->{$type . "_io"};
    my $rw = ($type eq "read") ? 0 : 1;

    # unwatch finished io
    for (keys %{$w}){ $exists{$_} or delete $w->{$_} }

    # watch io by AE
    for (@{$fd_ref}) {
        $w->{$_} ||= AE::io $_, $rw, sub {
            my $remain = $self->on_progress;
            $self->{cv}->send unless $remain;
        };
    }
}

sub on_progress {
    my $self = shift;
    my $curlm = $self->{curlm};
    my $active = $curlm->perform;
    if ( $active != $self->{active} ) {
        while ( my ( $id, $rval ) = $curlm->info_read ) {
            $self->_complete($id) if ($id);
        }
        $self->check_fh;
    }
    $active;
}

sub _complete {
    my ($self, $id) = @_;
    $self->{active}--;
    my $res = $self->{result}->{$id};
    $res->{rc} = $res->{curl}->getinfo(CURLINFO_HTTP_CODE);
    
    my $response = AnyEvent::Curl::Response->new($res);
    $res->{cb}->($response);
    $res->{cv}->send($response);
    delete $self->{result}->{$id};
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
      # $cv->callback(sub { ... });
  }
  warn $curl->active; # check active
  $cv->wait; # wait all request

=head1 DESCRIPTION

AnyEvent::Curl is wrapper for WWW::Curl using AnyEvent.

5x faster than LWP. Just a primitive interface for speed.

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
