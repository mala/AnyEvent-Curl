use Test::More;
use t::Test;

use Data::Dumper;
    test_psgi(
        app => sub {
            my $env = shift;
            return [ 200, [ 'Content-Type' => 'text/plain' ], ["Hello World"] ];
        },
        client => sub {
            my $cb  = shift;
            my $req = HTTP::Request->new( GET => "http://localhost/hello" );
            my $cv  = $cb->($req);
            my $res = $cv->recv;
            like $res->content, qr/Hello World/, "simple get";
            ok( $res->is_success, "check status code" );
            isa_ok( $res->http_response, "HTTP::Response",
                "generate http response" );
            warn "done client";
        }
    );
    done_testing(3);

=pod
subtest "500 ERROR" => sub {
    test_psgi(
        app => sub {
            my $env = shift;
            return [ 500, [ 'Content-Type' => 'text/plain' ], ["Hello World"] ];
        },
        client => sub {
            my $cb  = shift;
            my $req = HTTP::Request->new( GET => "http://localhost/hello" );
            my $cv  = $cb->($req);
            my $res = $cv->recv;
            like $res->content, qr/Hello World/, "simple get";
            ok( $res->is_error, "check status code" );
            isa_ok( $res->http_response, "HTTP::Response",
                "generate http response" );
        }
    );
    done_testing(3);
};

done_testing;
=cut
