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
    map {
        $r{$_} = $r->{$_};
    } qw(rc body header request redirect error);
    return bless \%r, $class;
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


