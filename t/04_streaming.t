use Test::More;
use t::Test;

use Data::Dumper;
use HTTP::Request::Common;
use Plack::Request;
use Time::HiRes qw(time sleep);

test_psgi(
app => sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $streaming = sub {
        my $respond = shift;
        my $writer = $respond->( [200, ['Content-Type' => 'text/plain']] );
        warn Dumper $writer;
        for(1..10) {
            $writer->write(time . "\n");
            sleep 0.1;
        }
        $writer->close;
    };
    $streaming;
},
client => sub {
    my $cb  = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/hello");
    my $cv  = $cb->($req, sub{}, {
        writefunction  => sub { 
            like $_[0], qr/^[\d\.]+\n$/, "streaming output";
            length $_[0]; 
        }
    });
    my $res = $cv->recv;
    is( $res->content, "", "no content, caused by writefunction");
    ok( $res->is_success, "streaming done" );
}
);

done_testing(12);

