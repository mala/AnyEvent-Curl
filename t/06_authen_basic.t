use Test::More;
use t::Test;

use Data::Dumper;
use HTTP::Request::Common;
use Plack::Request;
use HTTP::Date;

use Plack::Builder;
my $app = sub {
    [200, ['Content-Type' => 'text/plain'], ["Hello"]]
};

$app = builder {
    enable "Auth::Basic", authenticator => sub { $_[0] eq 'user' && $_[1] eq 'password' };
    $app;
};

test_psgi(
app => $app,
client => sub {
    my $cb  = shift;

    {
    my $req = HTTP::Request->new(GET => "http://localhost/hello");
    my $res  = $cb->($req, sub{})->recv;
    is( $res->code, 401, "auth needed");
    ok( $res->is_error, "done" );
    }

    {
    my $req = HTTP::Request->new(GET => 'http://user:password@localhost/hello');
    my $res  = $cb->($req, sub{})->recv;
    is( $res->code, 200, "OK, password in URL");
    like( $res->content, qr/Hello/, "OK");
    ok( $res->is_success, "done" );
    }

    {
    my $req = HTTP::Request->new(GET => 'http://localhost/hello');
    my $res  = $cb->($req, sub{}, {userpwd => "user:password"})->recv;
    is( $res->code, 200, "OK, CURLOPT_USERPWD");
    like( $res->content, qr/Hello/, "OK");
    ok( $res->is_success, "done" );
    }


}
);

done_testing(8);

