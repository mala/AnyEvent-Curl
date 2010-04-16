use inc::Module::Install;
name 'AnyEvent-Curl';
all_from 'lib/AnyEvent/Curl.pm';

requires 'AnyEvent';
requires 'WWW::Curl';

tests 't/*.t';
author_tests 'xt';

build_requires 'Test::More';
use_test_base;
auto_include;
WriteAll;
