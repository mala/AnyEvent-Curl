use Test::More;
use t::Test;

use Data::Dumper;
use HTTP::Request::Common;
use Plack::Request;

test_psgi(
app => sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    return [ 200, [ 'Content-Type' => 'text/plain' ], [$req->method, " key=".$req->param("key")] ];
},
client => sub {
    my $cb  = shift;
    my $req = HTTP::Request::Common::POST("http://localhost/hello", {key => "value", key2 => "value2", "key3" => '%$!&?'} );
    my $cv  = $cb->($req);
    my $res = $cv->recv;
    like $res->content, qr/POST/, "simple post";
    like $res->content, qr/key=value/, "simple post";
    ok( $res->is_success, "check status code" );
    isa_ok( $res->http_response, "HTTP::Response", "generate http response" );
    warn "done client";
}
);
done_testing(4);

