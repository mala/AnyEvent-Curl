use inc::Module::Install;
name 'AnyEvent-Curl';
all_from 'lib/AnyEvent/Curl.pm';

requires 'AnyEvent';
requires 'WWW::Curl';
requires 'HTTP::Response::Parser';

tests 't/*.t';
# author_tests 'xt';

build_requires 'Test::More';

test_requires 'Test::TCP';
test_requires 'Plack';

repository 'git://github.com/mala/AnyEvent-Curl.git';

use_test_base;
auto_include;
WriteAll;
