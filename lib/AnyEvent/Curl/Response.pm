package AnyEvent::Curl::Response;

use strict;
use warnings;
use HTTP::Response;
use HTTP::Status ();

my $CRLF = "\015\012";

sub new {
    my ($class, $r) = @_;
    my %r;
    map {
        $r{$_} = $r->{$_};
    } qw(rc body header request);
    return bless \%r, $class;
}

# we know some method
sub code { $_[0]->{rc} }
sub content { $_[0]->{body} }
sub is_info     { HTTP::Status::is_info     (shift->{'rc'}); }
sub is_success  { HTTP::Status::is_success  (shift->{'rc'}); }
sub is_redirect { HTTP::Status::is_redirect (shift->{'rc'}); }
sub is_error    { HTTP::Status::is_error    (shift->{'rc'}); }

sub http_response {
    my $self = shift;
    $self->{_http_response} ||= $self->to_http_response;
}

sub to_http_response {
    my $self = shift;
    my $res;

    # if follow redirect, multiple headers
    my @headers = reverse split($CRLF x 2, ${ $self->{header} });
    if (@headers > 1) {
        # warn Dumper \@headers;
        my $header = shift @headers;
        $header =~s/\015//g;
        $res = HTTP::Response->parse($header);
        $res->content(${ $self->{body} }); 
        my $current = $res;
        while (my $h = shift @headers) {
            warn $h;
            $h =~s/\015//g;
            my $pre = HTTP::Response->parse($h);
            $current->previous($pre);
            $current = $pre;
        }
    } else {
        ${ $self->{header} } =~s/\015//g;
        $res = HTTP::Response->parse(${ $self->{header} } . ${ $self->{body} });
    }

    if (ref $self->{request}) {
        $res->request($self->{request});
    }

    return $res;
}

# delegate to HTTP::Response
sub AUTOLOAD {
    my $self   = shift;
    my $method = our $AUTOLOAD;
    warn $method;
    $method =~ s/.*:://o;
    return $self->http_response->$method(@_);
}

sub DESTROY {}

1;


