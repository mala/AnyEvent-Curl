use Test::More;
use t::Test;

use Data::Dumper;
use HTTP::Request::Common;
use Plack::Request;
use HTTP::Date;

my $time = time;

test_psgi(
app => sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $since = $req->header("if-modified-since");
    if (str2time($since) == $time) {
        return [304, ['Content-Type' => 'text/plain'], [""]];
    } else {
        return [200, ['Content-Type' => 'text/plain'], ["Hello"]]
    }
},
client => sub {
    my $cb  = shift;

    {
    my $req = HTTP::Request->new(GET => "http://localhost/hello");
    $req->if_modified_since($time);
    my $res  = $cb->($req, sub{})->recv;
    is( $res->code, 304, "not modified");
    ok( $res->is_redirect, "done" );
    }

    {
    my $req = HTTP::Request->new(GET => "http://localhost/hello");
    $req->if_modified_since($time - 1);
    my $res  = $cb->($req, sub{})->recv;
    is( $res->code, 200, "modified");
    ok( $res->is_success, "done" );
    }
}
);

done_testing(4);

