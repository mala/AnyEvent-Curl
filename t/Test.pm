package t::Test;

use strict;
use warnings;
use Carp;
use HTTP::Request;
use HTTP::Response;

use AnyEvent::Curl;
use parent qw(Exporter);
our @EXPORT = qw(test_psgi);

$ENV{PLACK_SERVER} = "Standalone";
# $ENV{PLACK_SERVER} = "AnyEvent";

use Test::TCP;
use Plack::Loader;

sub test_psgi {
    if ( ref $_[0] && @_ == 2 ) {
        @_ = ( app => $_[0], client => $_[1] );
    }
    my %args = @_;
    my $client = delete $args{client} or croak "client test code needed";
    my $app    = delete $args{app}    or croak "app needed";
    my $ua = delete $args{ua} || AnyEvent::Curl->new;
    test_tcp(
        client => sub {
            my $port = shift;
            $ua->start;
            my $cb   = sub {
                my $req = shift;
                $req->uri->scheme('http');
                $req->uri->host( $args{host} || '127.0.0.1' );
                $req->uri->port($port);
                return $ua->add($req);
            };
            $client->($cb);
        },
        server => $args{server} || sub {
            my $port   = shift;
            my $server = Plack::Loader->auto(
                port => $port,
                host => ( $args{host} || '127.0.0.1' )
            );
            $server->run($app);
        },
    );
}

1;
