use strict;
use warnings;

use lib "../lib";

use AnyEvent;
use AnyEvent::Curl;
use AnyEvent::Curl::Compat::LWP;
use Time::HiRes qw(tv_interval gettimeofday);
use Benchmark qw(timethese);

my $url = shift @ARGV;
die "$0 <URL>" unless $url;

use WWW::Curl;
use WWW::Curl::Easy;
use AnyEvent::HTTP;
use LWP::UserAgent;
use HTTP::Request::Common;
use HTTP::Request;
use HTTP::Response;
use LWP::Simple qw(get);
use Data::Dumper;

use Coro;
use Coro::AnyEvent;

my $num = 50;
my $loop = 50;

$AnyEvent::HTTP::MAX_PER_HOST = 100;

BEGIN {
    # $ENV{HTTP_PROXY} = "http://127.0.0.1:3306/";
};

sub stopwatch(&){ my $start = [gettimeofday]; shift->(); tv_interval($start, [gettimeofday]) }

sub curl_easy {
    my $curl = new WWW::Curl::Easy;
    for(1..$num) {
        my $response_body;
        my $header;
        $curl->setopt(CURLOPT_URL, $url);
        open (my $fileb, ">", \$response_body);
        $curl->setopt(CURLOPT_WRITEDATA, $fileb);
        open (my $fileh, ">", \$header);
        $curl->setopt(CURLOPT_WRITEHEADER, $fileh);

        my $retcode = $curl->perform;
        if ($retcode == 0) {
            # print("Transfer went ok\n");
            my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
            # print("Received response: $response_body\n");
        } else {
            print("An error happened: ".$curl->strerror($retcode)." ($retcode)\n");
        }
    }
}

sub curl_easy_gfx {
    my $curl = new WWW::Curl::Easy;
    for(1..$num) {
        my $response_body = "";
        my $header = "";
        $curl->setopt(CURLOPT_URL, $url);
        $curl->setopt(CURLOPT_WRITEDATA,  \$response_body);
        $curl->setopt(CURLOPT_WRITEHEADER, \$header);

        my $retcode = $curl->perform;
        if ($retcode == 0) {
            # print("Transfer went ok\n");
            my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
            # print("Received response: $response_body\n");
        } else {
            print("An error happened: ".$curl->strerror($retcode)." ($retcode)\n");
        }
    }
}




my $CURL = AnyEvent::Curl->new;
sub curl_multi {
    my $req = $CURL;
    for ( 1 .. $num ) {
       $req->add(
            $url,
            sub {
                my $res = shift;
            }, 
        );
    }
    my $cv = $req->start;
    $cv->wait;
}

sub curl_multi_gfx {
    my $req = $CURL;
    $AnyEvent::Curl::GFX = 1;
    my $i;
    for ( 1 .. $num ) {
       $req->add(
            $url,
            sub {
                my $res = shift;
                $i++;
                $i == $num;
            }, 
        );
    }
    my $cv = $req->start;
    $cv->wait;
}




sub task{
    my $cv = $_[0]->add( $_[1], undef );
    $cv->recv;
    # $wakeme->ready if $i == $num;
};

sub curl_multi_coro {
    my $req = $CURL;
    my $i;
    #  my $wakeme = $Coro::current;
    for ( 1 .. $num ) {
        async \&task, $req, $url;
    }
    $req->start->wait;
    
    # schedule;
}



sub curl_multi_limit {
    my $req = AnyEvent::Curl->new(max_parallel => 50);
    my $i = 0;
    for ( 1 .. $num ) {
       $req->add(
            $url,
            sub {
                my $res = shift;
                $i++;
            }
        );
    }
    my $cv = $req->start;
    $cv->wait;
    warn $i;
}

# abort ex) if code == 304
sub curl_multi_abort {
    my $req = AnyEvent::Curl->new(max_parallel => 50);
    my $i = 0;
    for ( 1 .. $num ) {
       $req->add(
            $url,
            sub {
                my $res = shift;
                $i++;
            },
            {
                headerfunction => sub {
                    my ($proto, $code, $msg) = split " ", $_[0], 3;
                    return -1;
                }
            }
        );
    }
    my $cv = $req->start;
    $cv->wait;
    warn $i;
}



sub curl_proxy {
    my $req = AnyEvent::Curl->new;
    $req->setopt(proxy => "http://127.0.0.1:3128");
    for ( 1 .. $num ) {
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

# with HTTP::Request
sub curl_multi2 {
    my $req = AnyEvent::Curl->new;
    my $r = HTTP::Request->new(GET => $url);
    $req->setopt(proxy => "");
    for ( 1 .. $num ) {
       $req->add(
            $r,
            sub {
                my $res = shift;
            }
        );
    }
    my $cv = $req->start;
    $cv->wait;
}

my $g = 1;
# with HTTP::Response
sub curl_multi3 {
    my $req = AnyEvent::Curl->new;
    for my $c ( 1 .. $num ) {
       $req->add(
            $url,
            sub {
                my $res = shift;
                warn $c;
                warn $g++;
                my $r = $res->http_response;
                # warn ${ $res->{header} };
                warn $res->{error} unless $r->is_success; 
            }
        );
    }
    my $cv = $req->start;
    $cv->wait;
}

sub lwp { get $url for 1..$num }

# use Coro::LWP;

sub lwp2 { 
    my $g = AnyEvent::Curl::Compat::LWP->replace_original;
    my $done;
    my $wakeme = $Coro::current;
    my $ua = LWP::UserAgent->new(parse_head => 0);
    my $req = HTTP::Request->new(GET => $url);
    for (1..$num) {
       async { 
           $ua->request($req);
           $done++;
           $wakeme->ready if $done == $num;
       };
    }
    schedule;
}

sub lwp3 { 
    my $g = AnyEvent::Curl::Compat::LWP->replace_original;
    local $AnyEvent::Curl::Compat::LWP::RUN_HANDLERS = 0;
    my $done;
    my $wakeme = $Coro::current;
    my $ua = LWP::UserAgent->new(parse_head => 0);
    my $req = HTTP::Request->new(GET => $url);
    for (1..$num) {
       async { 
           $ua->request($req);
           $done++;
           $wakeme->ready if $done == $num;
       };
    }
    schedule;
}



sub anyevent_http {
    my $cv = AE::cv;
    for (1..$num) {
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

curl_multi();
# for 1..2;

timethese $loop, {
    # curl_easy     => sub { rec "curl_easy" => stopwatch { curl_easy() } },
    # curl_easy_gfx     => sub { rec "curl_easy_gfx" => stopwatch { curl_easy_gfx() } },
    # ae_curl        => sub { rec "ae_curl" => stopwatch { curl_multi() } },
    # ae_curl2        => sub { rec "ae_curl" => stopwatch { curl_multi() } },
    # ae_curl_gfx        => sub { rec "ae_curl_gfx" => stopwatch { curl_multi_gfx() } },
    # ae_curl_gfx2        => sub { rec "ae_curl_gfx" => stopwatch { curl_multi_gfx() } },
    # curl_coro   => sub { rec "curl_coro" => stopwatch { curl_multi_coro() } },
    # curl_limit  => sub { rec "curl_limit" => stopwatch { curl_multi_limit() } },
    # curl_abort  => sub { rec "curl_abort" => stopwatch { curl_multi_abort() } },
    # curl_proxy => sub { rec "curl_proxy" => stopwatch { curl_proxy() } },
    # curl_http_request  => sub { rec "curl_http_request" => stopwatch { curl_multi2() } },
    curl_http_response => sub { rec "curl_http_response" => stopwatch { curl_multi3() } },
    # anyevent => sub { rec anyevent => stopwatch { anyevent_http() } },
    # lwp      => sub { rec lwp => stopwatch { lwp() }; },
    # lwp_compat => sub { rec lwp2 => stopwatch { lwp2() }; },
    # lwp_compat_nohandler => sub { rec lwp2_nohandler => stopwatch { lwp3() }; },
};

# warn Dumper $time;


