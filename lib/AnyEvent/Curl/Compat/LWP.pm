package AnyEvent::Curl::Compat::LWP;

use strict;
use warnings;
use Guard;
use AnyEvent::Curl;
use base qw(LWP::UserAgent);
use Data::Dumper;

our $RUN_HANDLER = 1;

sub request {
    my($self, $request, $arg, $size, $previous) = @_;
    warn "use Curl";
    my $ua = $self;
    # set headers, useragent etc. 
    $ua->prepare_request($request);
    $ua->timeout;
    warn Dumper $self;
    warn Dumper $request;
    
    my $curl = AnyEvent::Curl->new;
    $curl->setopt(timeout => $self->timeout);

    my $cv = $curl->add($request);
    $curl->start;
    my $res = $cv->recv;

    if ($RUN_HANDLER) {
        my %skip_h;
        my $response = $res->http_response;
        $ua->run_handlers( "response_header", $response );

        for my $h ( $ua->handlers( "response_data", $response ) ) {
            next if $skip_h{$h};
            unless (
                $h->{callback}->( $response, $ua, $h, $response->content ) )
            {
                $skip_h{$h}++;
            }
        }
        delete $response->{handlers}{response_data};
        delete $response->{handlers} unless %{ $response->{handlers} };

        $ua->run_handlers( "response_done", $response );
        return $response;
    }
    else {
        return $res;
    }
}

sub replace_original {
    no warnings 'redefine';
    my $orig = LWP::UserAgent->can('request');
    *LWP::UserAgent::request = __PACKAGE__->can("request");
    if (defined wantarray) {
        return guard {
            *LWP::UserAgent::request = $orig
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

=head1 AUTHOR

mala E<lt>cpan@ma.laE<gt>

=head1 SEE ALSO

L<AnyEvent::Curl>, L<Coro::LWP>, L<Coro::AnyEvent>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

