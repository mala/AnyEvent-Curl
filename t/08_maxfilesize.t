use Test::More;
use t::Test;
use Time::HiRes qw(sleep);
use Data::Dumper;

test_psgi(
    app => sub {
        my $env = shift;
        return [ 200, [ 'Content-Type' => 'text/plain' ], ["Hello World" x 1000] ];
    },
    client => sub {
        my $cb  = shift;
        my $req = HTTP::Request->new( GET => "http://localhost/hello" );
        my $i;
        my $cv  = $cb->($req, undef, { maxfilesize => 1200 });
        my $res = $cv->recv;
        is( $res->content, "", "skip body by maxfilesize");
        ok( $res->is_success, "check status code" );
        isa_ok( $res->http_response, "HTTP::Response", "generate http response" );
        warn "done client";
    }
);

test_psgi(
    app => sub {
        my $env = shift;
        my $streaming = sub {
            my $respond = shift;
            my $writer = $respond->( [200, ['Content-Type' => 'text/plain']] );
            for(1..100) {
                $writer->write(time . "\n");
                sleep 0.01;
            }
            $writer->close;
        };
        $streaming;
    },
    client => sub {
        my $cb  = shift;
        my $req = HTTP::Request->new( GET => "http://localhost/hello" );
        my $i;
        my $maxsize = 20;
        my $cv  = $cb->($req, undef, { maxfilesize => $maxsize, noprogress => 0, progressfunction => sub { 
            $_[2] > $maxsize ? 1 : 0
        }});
        my $res = $cv->recv;
        ok( length $res->content < 100, "abort by progressfunction");
        ok( $res->is_success, "check status code" );
        isa_ok( $res->http_response, "HTTP::Response", "generate http response" );
        warn "done client";
    }
);
done_testing(6);

