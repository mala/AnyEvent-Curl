use Test::More;
use t::Test;

use Data::Dumper;
use HTTP::Request::Common;
use Plack::Request;

test_psgi(
app => sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    sleep 2;
    return [ 200, [ 'Content-Type' => 'text/plain' ], ["Hellow World after 2 sec"] ];
},
client => sub {
    my $cb  = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/hello");
    my $cv  = $cb->($req, sub{}, {timeout => 1});
    my $res = $cv->recv;
    ok( !$res->is_success, "fail by timeouot" );
}
);

test_psgi(
app => sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    sleep 2;
    return [ 200, [ 'Content-Type' => 'text/plain' ], ["Hellow World after 2 sec"] ];
},
client => sub {
    my $cb  = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/hello");
    my $cv  = $cb->($req, sub{}, {timeout => 10});
    my $res = $cv->recv;
    ok( $res->is_success, "check status code" );
    like( $res->content, qr/Hellow World/, "content");
    isa_ok( $res->http_response, "HTTP::Response", "generate http response" );
    warn "done client";
}
);




done_testing;

