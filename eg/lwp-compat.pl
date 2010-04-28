
use strict;
use warnings;
use lib qw(../lib);

use Coro;
use Coro::AnyEvent;
use AnyEvent::Curl::Compat::LWP;
use LWP::Simple qw(get);

# globally override
my $guard = AnyEvent::Curl::Compat::LWP->replace_original;
# undef $guard; # restore original LWP

my $wakeme = $Coro::current;
my $done = 0;

for my $i (1..10) {
    async { 
        warn "$i : " . length get "http://localhost/";
        $done++;
        $wakeme->ready if $done == 10;
    }
}

schedule;
