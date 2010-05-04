package AnyEvent::Curl::Compat::LWP;

use strict;
use warnings;
use Guard;
use AnyEvent::Curl;
use base qw(LWP::UserAgent);
use Data::Dumper;

our $RUN_HANDLERS = 1;
our $CURL;

sub new {
    my $class = shift;
    my %options = @_;
    my $self = $class->SUPER::new(@_);
    $self->{run_handlers} = delete $options{run_handlers} || $RUN_HANDLERS;
    $self;
}

# send_request
sub __curl_send_request {
    my ( $self, $request, $opt ) = @_;
    my $curl = $CURL ||= AnyEvent::Curl->new;
    my $cv = $curl->add(
        $request, undef,
        {
            timeout        => $self->timeout,
            followlocation => 0, # redirect handling by LWP
            %{$opt}
        }
    );

    $curl->start;
    my $res = $cv->recv;
}

sub simple_request {
    my($self, $request, $arg, $size) = @_;
    my $ua = $self;

    my $run_handler = (exists $self->{run_handlers}) ? $self->{run_handlers} : $RUN_HANDLERS;

    if ($run_handler) {
        $ua->prepare_request($request);
    } else {
        if ( my $def_headers = $self->{def_headers} ) {
            for my $h ( $def_headers->header_field_names ) {
                $request->init_header( $h => [ $def_headers->header($h) ] );
            }
        }
    }

    # run request_send handler
    if ($run_handler && defined (my $res = $ua->run_handlers("request_send", $request))) {
        $ua->run_handlers("response_done", $res);
        return $res;
    }

    my %options;
    my $res;
    if ($run_handler) {
        my $header = "";
        $options{headerfunction} = sub {
            $header .= $_[0];
            if ($_[0] =~/^\r?\n$/) {
                $res = HTTP::Response->parse($header);
            }
            length $_[0];
        };
    }
    my $ae_res = __curl_send_request($self, $request, \%options);
    return $ae_res unless $run_handler;

    # run response_header response_data
    my $called = 0;
    LWP::Protocol::create("http", $ua)->collect($arg, $res, sub {
        ($called++) ? \"" : $ae_res->{body}
    });
    $res->request($request);  # record request for reference
    $res->header("Client-Date" => HTTP::Date::time2str(time));
    $ua->run_handlers( "response_done", $res );
    return $res;
}

sub replace_original {
    my $class = shift;
    no warnings 'redefine';

    my $orig = LWP::UserAgent->can('simple_request');
    my $new  = $class->can("simple_request");
    if ($orig == $new) {
        warn "Already replaced!";
        return;
    }

    *LWP::UserAgent::simple_request = $class->can("simple_request");
    if (defined wantarray) {
        return guard {
            *LWP::UserAgent::simple_request = $orig
        };
    }
}

1;


=head1 NAME

AnyEvent::Curl::Compat::LWP

=head1 SYNOPSIS

 use Coro;
 use Coro::AnyEvent;
 use AnyEvent::Curl::Compat::LWP;
 use LWP::Simple qw(get);

 # globally override
 my $guard = AnyEvent::Curl::Compat::LWP->replace_original;

 # undef $guard; # restore original LWP

 # with Coro::AnyEvent, you can parallel request simply
 for (1..10) {
     async { get "http://example.com" }
 }

 schedule;

=head1 DESCRIPTION

AnyEvent::Curl::Compat::LWP is LWP::UserAgent compatible interface for AnyEvent::Curl.

You can use L<AnyEvent:::Curl> for any L<LWP::UserAgent> based module by replace_original(), see also L<Coro::LWP>.

This module is experimental, maybe there is lots of incompatibility.

=head1 METHODS

=head2 new

Create L<LWP::UserAgent> compatible object.

=head2 replace_original

replace LWP::UserAvent::request globally. it returns L<Guard> object for restore original.

 my $guard = AnyEvent::Curl::Compat::LWP->replace_original; # undef $guard, then restore original LWP
 AnyEvent::Curl::Compat::LWP->replace_original; # no way for restore

=head1 OPTIONS

=head2 $RUN_HANDLERS

 $AnyEvent::Curl::Compat::LWP::RUN_HANDLERS = 0 | 1; # DEFAULT is 1
  or
 AnyEvent::Curl::Compat::LWP->new(run_handlers => 0);

If you don't need LWP's callback mechanism such as "Parse meta/title/link tags in HTML", ":content_cb argument" etc, set 0 to speed up.
 
=head1 AUTHOR

mala E<lt>cpan@ma.laE<gt>

=head1 SEE ALSO

L<AnyEvent::Curl>, L<Coro::LWP>, L<Coro::AnyEvent>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

