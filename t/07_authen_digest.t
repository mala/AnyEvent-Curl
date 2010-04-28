use Test::More;
use t::Test;

use Data::Dumper;
use HTTP::Request::Common;
use Plack::Request;
use HTTP::Date;

eval { require Plack::Middleware::Auth::Digest };
if ($@) {
    plan skip_all => "Plack::Middleware::Auth::Digest not installed.";
}

unless (WWW::Curl::Easy->CURLAUTH_ANY) {
    plan skip_all => "WWW::Curl not support CURLAUTH_*";
}

use Plack::Builder;
my $app = sub {
    # warn Dumper $_[0];
    [200, ['Content-Type' => 'text/plain'], ["Hello"]]
};

$app = builder {
    enable "Auth::Digest", realm => "Secured", secret => "blahblahblah",
         authenticator => sub { warn @_; return "password"; };
    $app;
};

test_psgi(
app => $app,
client => sub {
    my $cb  = shift;

    {
    my $req = HTTP::Request->new(GET => "http://localhost/hello");
    my $res  = $cb->($req, sub{})->recv;
    # warn Dumper $res;
    is( $res->code, 401, "auth needed");
    ok( $res->is_error, "done" );
    }

    {
    my $req = HTTP::Request->new(GET => 'http://user:password@localhost/hello');
    my $res  = $cb->($req, sub{})->recv;
    is( $res->code, 401, "auth needed");
    ok( $res->is_error, "done" );
    }

    {
    my $req = HTTP::Request->new(GET => 'http://localhost/hello');
    my $res  = $cb->($req, sub{}, {httpauth => WWW::Curl::Easy->CURLAUTH_ANY, userpwd => "user:password"})->recv;
    is( $res->code, 200, "OK");
    like( $res->content, qr/Hello/, "OK");
    ok( $res->is_success, "done" );
    }

}
);

done_testing(7);
