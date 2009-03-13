#!perl -w

use strict;
use Test::More tests => 5;
use HTTP::Request;
use HTTP::Request::Multi;

my %in      = get_responses();
ok(my $res  = HTTP::Request::Multi->create_response(\%in), "Created request");
is($res->code, 207,                                        "Got the correct HTTP status");
is($res->content_type, "multipart/parallel",               "Got the correct mime type");
ok(my %out  = HTTP::Request::Multi->parse_response($res),  "Parsed request back in");
is_deeply(\%in, \%out,                                     "Structures are the same");


sub get_responses {
    return (
        1 => HTTP::Response->new(200  => "Hello"),
        2 => HTTP::Response->new(404  => "Not Found"),
        3 => HTTP::Response->new(500  => "Internal Server Error"),
    );

}

