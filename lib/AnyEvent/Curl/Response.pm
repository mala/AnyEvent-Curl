package AnyEvent::Curl::Response;

use strict;
use warnings;
use HTTP::Response;
use HTTP::Status ();
use HTTP::Response::Parser;

my $CRLF = "\015\012";

sub new {
    my ($class, $r) = @_;
    my %r;
    map { $r{$_} = $r->{$_} } qw(rc body header request redirect error);
    bless \%r, $class;
}

# we know some method
sub code { $_[0]->{rc} }
sub content { ${ $_[0]->{body} } }
sub is_info     { HTTP::Status::is_info     (shift->{'rc'}) }
sub is_success  { HTTP::Status::is_success  (shift->{'rc'}) }
sub is_redirect { HTTP::Status::is_redirect (shift->{'rc'}) }
sub is_error    { HTTP::Status::is_error    (shift->{'rc'}) }

sub http_response {
    my $self = shift;
    $self->{_http_response} ||= $self->to_http_response;
}

# faster
sub to_http_response {
    my $self = shift;
    my $res;
    # if follow redirect, multiple headers
    if ($self->{redirect}) {
        my @headers = reverse split($CRLF x 2, ${ $self->{header} });
        if ($self->{error}) {
            $res = _parse("HTTP/1.0 500 INTERNAL ERROR\r\n\r\n", $self->{error});
        } else {
            my $header = shift @headers;
            $res = _parse($header . $CRLF x 2, ${$self->{body}});
        }
        my $current = $res;
        while (my $h = shift @headers) {
            my $pre = _parse($h . $CRLF x 2, "");
            $current->previous($pre, "");
            $current = $pre;
        }
    } else {
        if ($self->{error}) {
            $res = _parse("HTTP/1.0 500 INTERNAL ERROR\r\n\r\n", $self->{error});
        } else {
            $res = _parse(${$self->{header}}, ${$self->{body}});
        }
    }
    if (ref $self->{request}) {
        $res->request($self->{request});
    }
    return $res;
}

# create HTTP::Response from (header, body)
sub _parse { HTTP::Response::Parser::parse(@_) }

# delegate to HTTP::Response
sub AUTOLOAD {
    my $self   = shift;
    my $method = our $AUTOLOAD;
    # warn $method;
    $method =~ s/.*:://o;
    return $self->http_response->$method(@_);
}

sub DESTROY {}

1;

=head1 NAME

AnyEvent::Curl::Response - response object for AnyEvent::Curl

=head1 SYNOPSIS

 use AnyEvent::Curl;
 my $curl = AnyEvent::Curl->new;
 my $cv = $curl->add($request, $callback);
 $curl->start;
 my $res = $cv->recv; # wait one request
 if ($r->is_success) {
     # Get HTTP::Response
     my $res = $r->http_response;
     $res->content_type;
     $res->last_modified;
 } else {
     warn $r->code;
 }

=head1 DESCRIPTION

AnyEvent::Curl::Response is response object for AnyEvent::Curl. 

It has a minimum function, less memory usage. 

=head1 METHODS

=head2 code

Return status code. If client caught some error, return 500.

=head2 content

Return content body. Read only.

=head2 is_info, is_success, is_redirect, is_error

Return true if status code is 1xx, 2xx, 3xx, 4xx or 5xx.

=head2 http_response

Create HTTP::Response object by L<HTTP::Response::Parser>.

If you want just a content body or status code, you shoud not call this method.

=head2 other method

Create HTTP::Response object and delegate to it. $r->header() means $r->http_response->header().

=head1 AUTHOR

mala E<lt>cpan@ma.laE<gt>

=head1 SEE ALSO

L<WWW::Curl>, L<HTTP::Response>, L<HTTP::Response::Parser>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

