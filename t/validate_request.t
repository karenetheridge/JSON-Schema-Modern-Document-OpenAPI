# vim: set ts=8 sts=2 sw=2 tw=100 et :
use strict;
use warnings;
use 5.020;
use experimental qw(signatures postderef);
use if "$]" >= 5.022, experimental => 're_strict';
no if "$]" >= 5.031009, feature => 'indirect';
no if "$]" >= 5.033001, feature => 'multidimensional';
no if "$]" >= 5.033006, feature => 'bareword_filehandles';
use utf8;
use open ':std', ':encoding(UTF-8)'; # force stdin, stdout, stderr into utf8

use Test::More;
use Test::Deep;
use OpenAPI::Modern;
use JSON::Schema::Modern::Utilities 'jsonp';
use constant { true => JSON::PP::true, false => JSON::PP::false };
use HTTP::Request;
use YAML::PP;

my $path_template = '/foo/{foo_id}/bar/{bar_id}';

my $openapi_preamble = <<'YAML';
---
openapi: 3.1.0
info:
  title: Test API
  version: 1.2.3
YAML

my $doc_uri = Mojo::URL->new('openapi.yaml');

subtest 'validation errors' => sub {
  my $request = HTTP::Request->new(
    POST => 'http://example.com/some/path',
  );
  my $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths: {}
YAML
    },
  );
  cmp_deeply(
    my $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {} })->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}'),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}'))),
          error => 'missing path-item "/foo/{foo_id}/bar/{bar_id}"',
        },
      ],
    },
    'path template does not exist under /paths',
  );

  $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths:
  /foo/{foo_id}/bar/{bar_id}: {}
YAML
    },
  );
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {}})->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', 'post'),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', 'post'))),
          error => 'missing operation',
        },
      ],
    },
    'operation does not exist under /paths/<path-template>',
  );

  $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths:
  /foo/{foo_id}/bar/{bar_id}:
    post: {}
YAML
    },
  );
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {}})->TO_JSON,
    { valid => true },
    'operation can be empty',
  );

  $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths:
  /foo/{foo_id}/bar/{bar_id}:
    post:
      parameters:
      - \$ref: '#/i_do_not_exist'
YAML
    },
  );
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {}})->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0 $ref)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0 $ref)))),
          error => 'EXCEPTION: unable to find resource openapi.yaml#/i_do_not_exist',
        },
      ],
    },
    'bad $ref in operation parameters',
  );

  $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths:
  /foo/{foo_id}/bar/{bar_id}:
    parameters:
    - \$ref: '#/i_do_not_exist'
    post: {}
YAML
    },
  );
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {}})->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(parameters 0 $ref)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(parameters 0 $ref)))),
          error => 'EXCEPTION: unable to find resource openapi.yaml#/i_do_not_exist',
        },
      ],
    },
    'bad $ref in path-item parameters',
  );

  $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
components:
  parameters:
    foo:
      \$ref: '#/i_do_not_exist'
paths:
  /foo/{foo_id}/bar/{bar_id}:
    post:
      parameters:
      - \$ref: '#/components/parameters/foo'
YAML
      },
  );
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {}})->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0 $ref $ref)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment('/components/parameters/foo/$ref')),
          error => 'EXCEPTION: unable to find resource openapi.yaml#/i_do_not_exist',
        },
      ],
    },
    'bad $ref to $ref in operation parameters',
  );

  $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths:
  /foo/{foo_id}/bar/{bar_id}:
    post:
      parameters:
      - name: yum
        in: cookie
        required: false
        schema:
          type: string
YAML
    },
  );
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {}})->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/cookie/yum',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0)))),
          error => 'cookie parameters not yet supported',
        },
      ],
    },
    'cookies are not yet supported',
  );

  $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths:
  /foo/{foo_id}/bar/{bar_id}:
    post:
      parameters:
      - name: foo_id
        in: path
        required: true
        content:
          application/json:
            schema: {}
      - name: query1
        in: query
        required: true
        content:
          application/json:
            schema: {}
      - name: Header1
        in: header
        required: true
        content:
          application/json:
            schema: {}
YAML
      },
  );
  $request->uri($request->uri . '?query1=value');
  $request->header('Header1' => 'header value');
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {}})->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/path/foo_id',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0 content)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0 content)))),
          error => 'content not yet supported',
        },
        {
          instanceLocation => '/request/query/query1',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 1 content)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 1 content)))),
          error => 'content not yet supported',
        },
        {
          instanceLocation => '/request/header/Header1',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 2 content)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 2 content)))),
          error => 'content not yet supported',
        },
      ],
    },
    'parameters contain unsupported "content"',
  );

  $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths:
  /foo/{foo_id}/bar/{bar_id}:
    parameters:
    - name: FOO-BAR   # different case, but should still be overridden by the operation parameter
      in: header
      required: true
      schema: false
    post:
      parameters:
      - name: foo_id
        in: path
        required: true
        schema:
          pattern: ^[0-9]+\$
      - name: alpha
        in: query
        required: true
        schema:
          pattern: ^[0-9]+\$
      - name: Foo-Bar
        in: header
        required: true
        schema:
          pattern: ^[0-9]+\$
YAML
    },
    # note that bar_id is not listed as a path parameter
  );
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => { bar_id => 'bar' } })->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/path/foo_id',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0 required)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0 required)))),
          error => 'missing path parameter: foo_id',
        },
        {
          instanceLocation => '/request/query/alpha',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 1 required)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 1 required)))),
          error => 'missing query parameter: alpha',
        },
        {
          instanceLocation => '/request/header/Foo-Bar',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 2 required)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 2 required)))),
          error => 'missing header: Foo-Bar',
        },
      ],
    },
    'path, query and header parameters are missing; header names are case-insensitive',
  );


  $request->uri('http://example.com/some/path?alpha=hello');
  $request->headers->header('FOO-BAR' => 'header value');    # exactly matches path parameter
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => { foo_id => 'foo', bar_id => 'bar' } })->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/path/foo_id',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0 schema pattern)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0 schema pattern)))),
          error => 'pattern does not match',
        },
        {
          instanceLocation => '/request/query/alpha',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 1 schema pattern)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 1 schema pattern)))),
          error => 'pattern does not match',
        },
        {
          instanceLocation => '/request/header/Foo-Bar',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 2 schema pattern)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 2 schema pattern)))),
          error => 'pattern does not match',
        },
      ],
    },
    'path, query and header parameters are evaluated against their schemas',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths:
  /foo/{foo_id}/bar/{bar_id}:
    parameters:
    - name: foo_id
      in: path
      required: true
      schema:
        pattern: ^[0-9]+\$
    - name: bar_id
      in: path
      required: true
      schema:
        pattern: ^[0-9]+\$
    post:
      parameters:
      - name: foo_id
        in: path
        required: true
        schema:
          maxLength: 1
      - name: bar_id
        in: query
        required: false
        schema:
          maxLength: 1
YAML
      },
  );

  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => { foo_id => 'foo', bar_id => 'bar' } })->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/path/foo_id',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0 schema maxLength)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post parameters 0 schema maxLength)))),
          error => 'length is greater than 1',
        },
        {
          instanceLocation => '/request/path/bar_id',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(parameters 1 schema pattern)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(parameters 1 schema pattern)))),
          error => 'pattern does not match',
        },
      ],
    },
    'path parameters: operation overshadows path-item',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths:
  /foo/{foo_id}/bar/{bar_id}:
    post:
      requestBody:
        \$ref: '#/i_do_not_exist'
YAML
    },
  );

  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {} })->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody $ref)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody $ref)))),
          error => 'EXCEPTION: unable to find resource openapi.yaml#/i_do_not_exist',
        },
      ],
    },
    'bad $ref in requestBody',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => 'openapi.yaml',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths:
  /foo/{foo_id}/bar/{bar_id}:
    post:
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                alpha:
                  type: string
                  pattern: ^[0-9]+\$
                beta:
                  type: string
                  const: éclair
                gamma:
                  type: string
                  const: ಠ_ಠ
              additionalProperties: false
          text/html:
            schema: false
YAML
    },
  );

  # TODO: combine this test with an earlier one, e.g. testing required parameters.
  # note: no content!
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {} })->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody required)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody required)))),
          error => 'request body is required but missing',
        },
      ],
    },
    'request body is missing',
  );


  $request->content_type('text/plain');
  $request->content('plain text');
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {} })->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody content)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody content)))),
          error => 'incorrect Content-Type "text/plain"',
        },
      ],
    },
    'wrong Content-Type',
  );


  $request->content_type('text/html');
  $request->content('html text');
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {} })->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody content text/html)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody content text/html)))),
          error => 'EXCEPTION: unsupported Content-Type "text/html": add support with $openapi->add_media_type(...)',
        },
      ],
    },
    'unsupported Content-Type',
  );


  $request->content_type('application/json; charset=ISO-8859-1');
  $request->content('{"alpha": "123", "beta": "'.chr(0xe9).'clair"}');
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {} })->TO_JSON,
    { valid => true },
    'content matches',
  );


  $request->content_type('application/json; charset=UTF-8');
  $request->content('{"alpha": "foo", "gamma": "o.o"}');
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {} })->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body/alpha',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody content application/json schema properties alpha pattern)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody content application/json schema properties alpha pattern)))),
          error => 'pattern does not match',
        },
        {
          instanceLocation => '/request/body/gamma',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody content application/json schema properties gamma const)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody content application/json schema properties gamma const)))),
          error => 'value does not match',
        },
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody content application/json schema properties)),
          absoluteKeywordLocation => str($doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(post requestBody content application/json schema properties)))),
          error => 'not all properties are valid',
        },
      ],
    },
    'decoded content does not match the schema',
  );


  my $disapprove = v224.178.160.95.224.178.160; # utf-8-encoded "ಠ_ಠ"
  $request->content('{"alpha": "123", "gamma": "'.$disapprove.'"}');
  cmp_deeply(
    $result = $openapi->validate_request($request,
      { path_template => $path_template, path_captures => {} })->TO_JSON,
    { valid => true },
    'decoded content matches the schema',
  );
};

done_testing;
