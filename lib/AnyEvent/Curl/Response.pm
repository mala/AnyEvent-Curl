package AnyEvent::Curl::Response;

use strict;
use warnings;
use HTTP::Response;
use HTTP::Status ();

my $CRLF = "\015\012";

use HTTP::Headers::Fast;
# HACK HTTP::Headers::Fast;
{
    package HTTP::Headers::Fast;
    my %CACHE;
    sub new_from_string {
        my ($class, $str) = @_;
        return bless {}, $class unless defined $str;
        my (%self, $field, $value, $f);
        for ( split /\r?\n/, $str ) {
            if (defined $field) {
                if ( ord == 9 || ord == 32 ) {
                    $value .= "\n$_";
                    next;
                }
                $f = $CACHE{$field} ||= _standardize_field_name($field);
                if ( defined $self{$f} ) { _header_push_no_return(\%self, $f, $value ) } else { $self{$f} = $value }
            }
            ( $field, $value ) = split /[ \t]*: ?/, $_, 2;
        }
        if (defined $field) {
            $f = $CACHE{$field} ||= _standardize_field_name($field);
            if ( defined $self{$f} ) { _header_push_no_return(\%self, $f, $value ) } else { $self{$f} = $value }
        }
        bless \%self, $class;
    }

    sub new_from_string2 {
        my ($class, $str) = @_;
        return bless {}, $class unless defined $str;
        my (%self, $field, $value, $f);
        for ( split /\r?\n/, $str ) {
            if (defined $field) {
                if ( ord == 9 || ord == 32 ) {
                    $value .= "\n$_";
                    next;
                }
                $f = $CACHE{$field} ||= _standardize_field_name($field);
                if ( defined $self{$f} ) { _header_push_no_return(\%self, $f, $value ) } else { $self{$f} = $value }
            }
            ( $field, $value ) = split /[ \t]*: ?/, $_, 2;
        }
        if (defined $field) {
            $f = $CACHE{$field} ||= _standardize_field_name($field);
            if ( defined $self{$f} ) { _header_push_no_return(\%self, $f, $value ) } else { $self{$f} = $value }
        }
        bless \%self, $class;
    }

}

sub new {
    my ($class, $r) = @_;
    my %r;
    map {
        $r{$_} = $r->{$_};
    } qw(rc body header request redirect);
    return bless \%r, $class;
}

# we know some method
sub code { $_[0]->{rc} }
sub content { ${ $_[0]->{body} } }
sub is_info     { HTTP::Status::is_info     (shift->{'rc'}); }
sub is_success  { HTTP::Status::is_success  (shift->{'rc'}); }
sub is_redirect { HTTP::Status::is_redirect (shift->{'rc'}); }
sub is_error    { HTTP::Status::is_error    (shift->{'rc'}); }

sub http_response {
    my $self = shift;
    $self->{_http_response} ||= $self->to_http_response3;
}

sub to_http_response {
    my $self = shift;
    my $res;

    # if follow redirect, multiple headers
    if ($self->{redirect}) {
        my @headers = reverse split($CRLF x 2, ${ $self->{header} });
        # warn Dumper \@headers;
        my $header = shift @headers;
        $header =~s/\015//g;
        $res = HTTP::Response->parse($header);
        $res->content(${ $self->{body} }); 
        my $current = $res;
        while (my $h = shift @headers) {
            # warn $h;
            $h =~s/\015//g;
            my $pre = HTTP::Response->parse($h);
            $current->previous($pre);
            $current = $pre;
        }
    } else {
        ${ $self->{header} } =~s/\015//g;
        $res = HTTP::Response->parse(${ $self->{header} });
        $res->content(${ $self->{body} });
    }

    if (ref $self->{request}) {
        $res->request($self->{request});
    }

    return $res;
}

# faster
sub to_http_response2 {
    my $self = shift;
    my $res;
    # if follow redirect, multiple headers
    if ($self->{redirect}) {
        my @headers = reverse split($CRLF x 2, ${ $self->{header} });
        my $header = shift @headers;
        $res = _parse(\$header, $self->{body});
        my $current = $res;
        while (my $h = shift @headers) {
            my $pre = _parse(\$h, \"");
            $current->previous($pre, "");
            $current = $pre;
        }
    } else {
        $res = _parse($self->{header}, $self->{body});
    }
    if (ref $self->{request}) {
        $res->request($self->{request});
    }
    return $res;
}

sub to_http_response3 {
    my $self = shift;
    my $res;
    # if follow redirect, multiple headers
    if ($self->{redirect}) {
        my @headers = reverse split($CRLF x 2, ${ $self->{header} });
        my $header = shift @headers;
        $res = _parse(\$header, $self->{body});
        my $current = $res;
        while (my $h = shift @headers) {
            my $pre = _parse(\$h, \"");
            $current->previous($pre, "");
            $current = $pre;
        }
    } else {
        $res = _parse2($self->{header}, $self->{body});
    }
    if (ref $self->{request}) {
        $res->request($self->{request});
    }
    return $res;
}

# create HTTP::Response from (header_ref, body_ref)
sub _parse {
    my %res;
    my ($sl, $str) = split /\r?\n/, ${ $_[0] }, 2;
    if ($sl =~ /^\d{3} /) {
        @res{'_rc','_msg'} = split(' ', $sl, 2);
    } else {
        @res{'_protocol','_rc','_msg'} = split(' ', $sl, 3);
    }
    $res{_headers} = HTTP::Headers::Fast->new_from_string($str || "");
    $res{_content} = ${ $_[1] };
    bless \%res, 'HTTP::Response';
}

sub _parse2 {
    my %res;
    my ($sl, $str) = split /\r?\n/, ${ $_[0] }, 2;
    if ($sl =~ /^\d{3} /) {
        @res{'_rc','_msg'} = split(' ', $sl, 2);
    } else {
        @res{'_protocol','_rc','_msg'} = split(' ', $sl, 3);
    }
    $res{_headers} = HTTP::Headers::Fast->new_from_string2($str);
    $res{_content} = ${ $_[1] };
    bless \%res, 'HTTP::Response';
}


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


