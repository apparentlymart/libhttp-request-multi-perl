package HTTP::Request::Multi;

use strict;
use MIME::Entity;
use MIME::Parser;
use HTTP::Request;
use HTTP::Response;
use constant ID_FIELD => 'Multipart-Request-ID';

our $VERSION = '0.5';
our $TMP_DIR = undef;

=head1 NAME

HTTP::Request::Multi - send multiple HTTP requests in parallel

=head1 SYNOPIS

    my %requests = (
        1 => HTTP::Request->new(GET  => "http://example.com"),
        2 => HTTP::Request->new(POST => "http://example.com/upload.cgi, "Testing"),
    );
    # NOTE: what method is worked out automatically
    my $req = HTTP::Request::Multi->create_request("http://example.com/multi", \%requests);
    my $res = $ua->request($req);

    # parse the response 
    if ($res->is_success) {
        my %map =  HTTP::Request::Multi->parse_response($res);
        # 1 will be a response to the GET, 2 will be the response to the POST
    }

=head1 DESCRIPTION

C<HTTP::Request::Multi> allows you to send multiple HTTP requests in
parallel by using mime encoding (with the mime type C<multipart/parallel>).

This is useful for pipelining several REST API calls together to avoid latency.

You will, however, need a server capable of understanding the request or a 
proxy that can split and recombine the requests. This code, or similar, should 
work.

    my $request    = shift;
    my %map        = HTTP::Request::Multi->parse_request($request);
    my $pua        = LWP::Parallel::UserAgent->new();

    $pua->redirect(1);
    $pua->register($_) for values %map;

    my $entries    = $pua->wait;
    my %responses;
    foreach my $key (keys %$entries) {
        my $id = $entries->{$key}->request->header( HTTP::Request::Multi::ID_FIELD() );
        $responses{$id} = $entries->{$key}->response;
    }
    my $response   = HTTP::Request::Multi->create_response(undef, \%responses);
    $response->protocol($request->protocol) if defined $request->protocol;
    print $response->as_string;

=head1 SPECIFICATION

If you want to implement the protocol in a different language this is a more formal specification:

=head2 Request

The request must be an HTTP C<POST> request. The C<Content-Type> must be C<multipart/parallel> and 
must have a single MIME C<boundary> parameter as per the MIME specification.

    http://www.w3.org/Protocols/rfc1341/7_2_Multipart.html#z1
 
The body of the Request must contain one or more MIME parts. Each part must 
have a C<Content-Type> of C<message/http-request>. It must also have a C<Multipart-Request-ID> 
header which is unique to the whole Request. The ID need not be sequential. 

The body of each part contains a serialisation of the sub-request as per the HTTP specification.

And example request is shown below.

    POST http://example.com
    Content-Type: multipart/parallel; boundary="----------=_1236704275-16351-0"

    This is a multi-part message in MIME format...

    ------------=_1236704275-16351-0
    Content-Type: message/http-request
    Content-Disposition: inline
    Content-Transfer-Encoding: binary
    MIME-Version: 1.0
    Multipart-Request-ID: 1

    GET http://example.com/1.cgi HTTP/1.0
    Accept: application/json

    ------------=_1236704275-16351-0
    Content-Type: message/http-request
    Content-Disposition: inline
    Content-Transfer-Encoding: binary
    MIME-Version: 1.0
    Multipart-Request-ID: 3

    POST http://example.com/upload.cgi HTTP/1.0
    Content-Type: text/plain

    Testing

    ------------=_1236704275-16351-0
    Content-Type: message/http-request
    Content-Disposition: inline
    Content-Transfer-Encoding: binary
    MIME-Version: 1.0
    Multipart-Request-ID: 2

    GET http://example.com/2.html HTTP/1.0
    Accept: text/html
    If-Modified-Since: Sat, 29 Oct 1994 19:43:31 GMT


    ------------=_1236704275-16351-0--

=head2 Response

In the event of success the status of a the response must be 207 (Multi-status).
The C<Content-Type> of the response must be C<multipart/parallel> and
must have a single MIME C<boundary> parameter as per the MIME specification.

The body of the Response must contain one or more MIME parts. There must be a part corresponding
to each sub-request made. 

Each part must have a C<Content-Type> of C<message/http-response>. It must also have a 
C<Multipart-Request-ID> header which is unique to the whole Response and refers to the sub-request 
that this sub-response refers to. The responses need not be returned in the same order that they 
were requested.

The body of each part contains a serialisation of the sub-response as per the HTTP specification.

And example response is shown below.


    HTTP/1.0 207 Multi-Status
    Date: Tue, 10 Mar 2009 18:52:12 GMT
    Content-Type: multipart/parallel; boundary="----------=_1236711133-3134-3"

    This is a multi-part message in MIME format...

    ------------=_1236711133-3134-3
    Content-Type: message/http-response
    Content-Disposition: inline
    Content-Transfer-Encoding: binary
    MIME-Version: 1.0
    Multipart-Request-ID: 1

    500 (Internal Server Error)
    Content-Length: 0
    Content-Type: text/plain


    ------------=_1236711133-3134-3
    Content-Type: message/http-response
    Content-Disposition: inline
    Content-Transfer-Encoding: binary
    MIME-Version: 1.0
    Multipart-Request-ID: 3

    200 (Ok)
    Content-Type: text/html
    ETag: 7d19575d56b4df91085839f5a9925753d91d8cb2    

    <html>
        <head>
            <title>Hello World</title>
        </head>
        <body>
            <p>Bonjour! Nihau! Guten Morgen!</p>
        </body>
    </html>

    ------------=_1236711133-3134-3
    Content-Type: message/http-response
    Content-Disposition: inline
    Content-Transfer-Encoding: binary
    MIME-Version: 1.0
    Multipart-Request-ID: 2

    404 (Not Found)
    Content-Type: text/plain

    http://example.com/upload.cgi not found


------------=_1236711133-3134-3--




=head1 METHODS

=cut

=head2 create_request <url> [requests]

=head2 create_request <url> [header] [requests]

Create a new multi requests object.

=cut
sub create_request {
    my $class = shift;
    my $url   = shift || die "You must pass in a uri";
    my ($headers, $requests) = @_;

    if (!defined $requests) {
        $requests = $headers;
        $headers  = undef;
    }

    # If all requests are gets then this is a GET
    # otherwise make it a POST by default
    # TODO: allow force override of this
    my $meth = "POST"; #(scalar(grep { 'GET' ne $_->method } values %$requests))? "POST" : "GET";
    my $msg  = $class->_create_msg('message/http-request', %$requests);

    # Create the request
    my $req = HTTP::Request->new($meth => $url, $headers, join("", @{$msg->body}));
    $req->header('Content-Type' => $msg->head->get('Content-Type'));
    return $req;
}

sub _create_msg {
    my $class = shift;
    my $type  = shift;
    my %parts = @_;
    my $msg  = MIME::Entity->build( Type => 'multipart/parallel', 'X-Mailer' => undef );
    foreach my $key (keys %parts) {
        my $part = $parts{$key};
        # Add the key as a header and then create a new part for the message
        my $tmp  = MIME::Entity->build( 
                      'Type'     => $type, 
                      'Data'     => $part->as_string, 
                      'X-Mailer' => undef, 
        );
        $tmp->head->replace( ID_FIELD() => $key );
        $msg->add_part($tmp);

    }
    return $msg;

}

=head2 create_response [responses]

=head2 create_response [header] [responses]

Create a new multi-part HTTP::Response object.

=cut
sub create_response {
    my $class     = shift;
    my ($headers, $responses) = @_;
    if (!defined $responses) {
        $responses = $headers;
        $headers   = undef;
    }
    my $msg  = $class->_create_msg('message/http-response', %$responses);
    # Create the response
    # TODO allow passing in of code and message
    my $code = 207;
    my $res  = HTTP::Response->new($code => 'Multi-Status', $headers, join("", @{$msg->body}));
    $res->header('Content-Type' => $msg->head->get('Content-Type'));
    $res->protocol('HTTP/1.0');
    unless (defined $res->content_length) {
        use bytes;
        $res->content_length(length $res->content);
    }
    return $res;
}

=head2 parse_request <HTTP::Request>

Returns a hash of Request-IDs to HTTP::Requests.

=cut 
sub parse_request {
    my $class   = shift;
    my $request = shift;
    return $class->_parse_message($request, 'HTTP::Request');
}

=head2 parse_response <HTTP::Response>

Returns a hash of Request-IDs to HTTP::Responses

Assumes that the response was a success.

=cut
sub parse_response {
    my $class    = shift;
    my $response = shift;
    return $class->_parse_message($response, 'HTTP::Response');
}

sub _parse_message {
    my $class     = shift;
    my $message   = shift;
    my $ret_class = shift; 

    my $tmp       = "Content-Type: ".$message->header('Content-Type')."\n";
    # Create a new MIME parser with the content of the response
    # TODO some sort of verification?
    my $mime      = $class->_parser->parse_data($tmp.$message->content);


    # Now extract the response from each part 
    # and map it to the Request-ID
    my %map;
    foreach my $part ($mime->parts) {
        my $res = $ret_class->parse($part->bodyhandle->as_string);
        my $id  = $part->head->get(ID_FIELD()); chomp($id);
        $map{$id} = $res;
    }
    return %map;
}

=head1 TEMP FILES

By default C<HTTP::Request::Multi> does not use tmp files.

However, if dealing with large responses, doing so may be faster.

To use a tmp directory set C<$HTTP::Request::Multi::TMP_DIR> to a path.

For example:

    use File::Spec;
    $HTTP::Request::Multi::TMP_DIR = File::Spec->tmpdir;

or

    use File::Temp qw(tempdir);
    $HTTP::Request::Multi::TMP_DIR = tempdir(undef, CLEANUP => 1);

which will clean up after itself.

=cut
our $parser;
sub _parser {
    unless ($parser) {
        $parser = MIME::Parser->new;
        if ($TMP_DIR) {
            $parser->tmp_dir($TMP_DIR);
        } else {
            $parser->output_to_core(1);
        }
    }
    return $parser;
}

=head1 AUTHOR

Simon Wistow <swistow@sixapart.com>

=head1 LICENSE 

HTTP::Request::Multi is free software; you may redistribute it and/or modify 
it under the same terms as Perl itself.

=head1 AUTHOR & COPYRIGHT 

Except where otherwise noted, HTTP::Request::Multi is Copyright 2009 Six Apart, cpan@sixapart.com. 

All rights reserved.

=head1 SUBVERSION 

The latest version of HTTP::Request::Multi can be found at

    http://code.sixapart.com/svn/HTTP-Request-Multi/trunk/

=cut
1;
