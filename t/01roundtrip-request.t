#!perl -w

use strict;
use Test::More tests => 5;
use HTTP::Request;
use HTTP::Request::Multi;

my %in      = get_requests();
ok(my $req  = HTTP::Request::Multi->create_request("http://example.com", undef, \%in), "Created request");
is($req->content_type, "multipart/parallel",                                           "Got the correct mime type");
is($req->method,       "POST",                                                         "Got the correct method");
ok(my %out  = HTTP::Request::Multi->parse_request($req),                               "Parsed request back in");
is_deeply(\%in, \%out,                                                                 "Structures are the same");


sub get_requests {
    return (
        1 => HTTP::Request->new(GET  => "http://example.com/1.html"),
        2 => HTTP::Request->new(GET  => "http://example.com/2.html"),
        3 => HTTP::Request->new(POST => "http://example.com/upload.cgi", undef, "Testing\n"),
    );

}

