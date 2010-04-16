use strict;
use warnings;

use lib "../lib";

use AnyEvent;
use AnyEvent::Curl;
use Time::HiRes qw(tv_interval gettimeofday);
use Benchmark qw(timethese);

my $url = shift @ARGV;
die "$0 <URL>" unless $url;

use WWW::Curl;
use WWW::Curl::Easy;
use AnyEvent::HTTP;
use LWP::Simple qw(get);
use Data::Dumper;

sub stopwatch(&){ my $start = [gettimeofday]; shift->(); tv_interval($start, [gettimeofday]) }
sub curl_multi {
   my $req = AnyEvent::Curl->new;
    for ( 1 .. 50 ) {
       $req->add(
            $url,
            sub {
                my $res = shift;
            }
        );
    }
    my $cv = $req->start;
    $cv->wait;
}

sub curl_multi2 {
    my $req = AnyEvent::Curl->new;
    for ( 1 .. 50 ) {
       $req->add(
            $url,
            sub {
                my $res = shift;
                $res->http_response;
            }
        );
    }
    my $cv = $req->start;
    $cv->wait;
}

sub lwp { get $url for 1..50 }

sub anyevent_http {
    my $cv = AE::cv;
    for (1..50) {
        $cv->begin;
        http_get($url, sub { $cv->end });
    }
    $cv->recv;
}


my $time = {};
sub rec($$) {
    $time->{$_[0]} ||= [];
    push @{ $time->{$_[0]} }, $_[1];
}

timethese 5, {
    curl     => sub { rec "curl" => stopwatch { curl_multi() } },
    curl_http_response => sub { rec "curl_http_response" => stopwatch { curl_multi2() } },
    anyevent => sub { rec anyevent => stopwatch { anyevent_http() } },
    lwp      => sub { rec lwp => stopwatch { lwp() }; },
};

warn Dumper $time;


