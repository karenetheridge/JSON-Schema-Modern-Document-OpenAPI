# vim: set ts=8 sts=2 sw=2 tw=100 et :
use strictures 2;
use 5.020;
use stable 0.031 'postderef';
use experimental 'signatures';
use if "$]" >= 5.022, experimental => 're_strict';
no if "$]" >= 5.031009, feature => 'indirect';
no if "$]" >= 5.033001, feature => 'multidimensional';
no if "$]" >= 5.033006, feature => 'bareword_filehandles';
use utf8;
use open ':std', ':encoding(UTF-8)'; # force stdin, stdout, stderr into utf8

use JSON::Schema::Modern::Utilities 'jsonp';
use Test::Warnings 0.033 qw(:no_end_test allow_patterns);

use lib 't/lib';
use Helper;

my $openapi_preamble = <<'YAML';
---
openapi: 3.1.0
info:
  title: Test API
  version: 1.2.3
YAML

my $doc_uri = Mojo::URL->new('http://example.com/api');
my $yamlpp = YAML::PP->new(boolean => 'JSON::PP');

my $type_index = 0;

START:
$::TYPE = $::TYPES[$type_index];
note 'REQUEST/RESPONSE TYPE: '.$::TYPE;

subtest 'validation errors, request uri paths' => sub {
  my $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    get:
      parameters:
      - name: foo_id
        in: path
        required: true
        schema:
          pattern: ^[0-9]+\$
YAML

  cmp_result(
    (my $result = $openapi->validate_request(request('GET', 'http://example.com/foo/bar'), { path_template => '/foo/baz', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/path',
          keywordLocation => '/paths',
          absoluteKeywordLocation => $doc_uri->clone->fragment('/paths')->to_string,
          error => 'missing path-item "/foo/baz"',
        },
      ],
    },
    'error in find_path',
  );

  cmp_result(
    ($result = $openapi->validate_request(request('GET', 'http://example.com/foo'), { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/path/foo_id',
          keywordLocation => jsonp(qw(/paths /foo get parameters 0 required)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo get parameters 0 required)))->to_string,
          error => 'missing path parameter: foo_id',
        },
      ],
    },
    'path parameter is missing',
  );

  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo/{foo_id}:
    get:
      parameters:
      - name: foo_id
        in: path
        required: true
        schema:
          pattern: ^[0-9]+\$
YAML

  cmp_result(
    ($result = $openapi->validate_request(request('GET', 'http://example.com/foo/bar'), { path_template => '/foo/{foo_id}', path_captures => { foo_id => 'bar' } }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/path/foo_id',
          keywordLocation => jsonp(qw(/paths /foo/{foo_id} get parameters 0 schema pattern)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo/{foo_id} get parameters 0 schema pattern)))->to_string,
          error => 'pattern does not match',
        },
      ],
    },
    'path parameters are evaluated against their schemas',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo/{foo_id}:
    get:
      parameters:
      - name: foo_id
        in: path
        required: true
        content:
          application/json: {}
      - name: Bar
        in: header
        required: false
        content:
          electric/boogaloo: {}
YAML

  cmp_result(
    ($result = $openapi->validate_request(request('GET', 'http://example.com/foo/corrupt_json'),
      { path_template => '/foo/{foo_id}', path_captures => { foo_id => 'corrupt_json' } }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/path/foo_id',
          keywordLocation => jsonp(qw(/paths /foo/{foo_id} get parameters 0 content application/json)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo/{foo_id} get parameters 0 content application/json)))->to_string,
          error => re(qr/^could not decode content as application\/json: malformed JSON string/),
        },
      ],
    },
    'corrupt data is detected, even when there is no schema',
  );

  cmp_result(
    ($result = $openapi->validate_request(request('GET', 'http://example.com/foo/{}', [ Bar => 1 ]),
      { path_template => '/foo/{foo_id}', path_captures => { foo_id => '{}' } }))->TO_JSON,
    { valid => true },
    'valid encoded content is always valid when there is no schema, and unknown media types are okay',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo/{foo_id}:
    get:
      parameters:
      - name: foo_id
        in: path
        required: true
        content:
          application/json:
            schema:
              required: ['key']
YAML

  cmp_result(
    ($result = $openapi->validate_request(request('GET', 'http://example.com/foo/corrupt_json'),
      { path_template => '/foo/{foo_id}', path_captures => { foo_id => 'corrupt_json' } }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/path/foo_id',
          keywordLocation => jsonp(qw(/paths /foo/{foo_id} get parameters 0 content application/json)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo/{foo_id} get parameters 0 content application/json)))->to_string,
          error => re(qr/^could not decode content as application\/json: malformed JSON string/),
        },
      ],
    },
    'errors during media-type decoding are detected',
  );

  cmp_result(
    ($result = $openapi->validate_request(request('GET', 'http://example.com/foo/{"hello":"there"}'),
      { path_template => '/foo/{foo_id}', path_captures => { foo_id => '{"hello":"there"}'}}))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/path/foo_id',
          keywordLocation => jsonp(qw(/paths /foo/{foo_id} get parameters 0 content application/json schema required)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo/{foo_id} get parameters 0 content application/json schema required)))->to_string,
          error => 'object is missing property: key',
        },
      ],
    },
    'parameters are decoded using the indicated media type and then validated against the content schema',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
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
    get:
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

  cmp_result(
    ($result = $openapi->validate_request(request('GET', 'http://example.com/foo/foo/bar/bar'),
      { path_template => '/foo/{foo_id}/bar/{bar_id}', path_captures => { foo_id => 'foo', bar_id => 'bar' } }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/path/foo_id',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(get parameters 0 schema maxLength)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(get parameters 0 schema maxLength)))->to_string,
          error => 'length is greater than 1',
        },
        {
          instanceLocation => '/request/uri/path/bar_id',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(parameters 1 schema pattern)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}/bar/{bar_id}', qw(parameters 1 schema pattern)))->to_string,
          error => 'pattern does not match',
        },
      ],
    },
    'path parameters: operation overshadows path-item',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => do {
      YAML::PP->new( boolean => 'JSON::PP' )->load_string(<<YAML);
$openapi_preamble
paths:
  /foo/{foo_id}:
    get: {}
YAML
      },
  );

  cmp_result(
    ($result = $openapi->validate_request(request('GET', 'http://example.com/foo/foo'),
      { path_template => '/foo/{foo_id}', path_captures => { foo_id => 'foo' } }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/path/foo_id',
          keywordLocation => jsonp(qw(/paths /foo/{foo_id})),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo/{foo_id})))->to_string,
          error => 'missing path parameter specification for "foo_id"',
        },
      ],
    },
    'a specification must exist for every templated path value',
  );
};

subtest 'validation errors in requests' => sub {
  my $request = request('POST', 'http://example.com/foo');
  my $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    post: {}
YAML

  cmp_result(
    (my $result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'operation can be empty',
  );

  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    post:
      parameters:
      - \$ref: '#/i_do_not_exist'
YAML

  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request',
          keywordLocation => jsonp(qw(/paths /foo post parameters 0 $ref)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post parameters 0 $ref)))->to_string,
          error => 'EXCEPTION: unable to find resource /api#/i_do_not_exist',
        },
      ],
    },
    'bad $ref in operation parameters',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    parameters:
    - \$ref: '#/i_do_not_exist'
    post: {}
YAML

  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request',
          keywordLocation => jsonp(qw(/paths /foo parameters 0 $ref)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo parameters 0 $ref)))->to_string,
          error => 'EXCEPTION: unable to find resource /api#/i_do_not_exist',
        },
      ],
    },
    'bad $ref in path-item parameters',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
components:
  parameters:
    foo:
      \$ref: '#/i_do_not_exist'
paths:
  /foo:
    post:
      parameters:
      - \$ref: '#/components/parameters/foo'
YAML

  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request',
          keywordLocation => jsonp(qw(/paths /foo post parameters 0 $ref $ref)),
          absoluteKeywordLocation => $doc_uri->clone->fragment('/components/parameters/foo/$ref')->to_string,
          error => 'EXCEPTION: unable to find resource /api#/i_do_not_exist',
        },
      ],
    },
    'bad $ref to $ref in operation parameters',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    post:
      parameters:
      - name: yum
        in: cookie
        required: false
        schema:
          type: string
YAML

  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/cookie/yum',
          keywordLocation => jsonp(qw(/paths /foo post parameters 0)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post parameters 0)))->to_string,
          error => 'cookie parameters not yet supported',
        },
      ],
    },
    'cookies are not yet supported',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
components:
  parameters:
    foo-header:
      name: Alpha
      in: header
      required: true
      schema:
        pattern: ^[0-9]+\$
    bar-header-ref:
      \$ref: '#/components/parameters/bar-header'
    bar-header:
      name: Beta
      in: header
      required: true
      schema:
        pattern: ^[0-9]+\$
paths:
  /foo:
    parameters:
    - name: ALPHA   # different case, but should still be overridden by the operation parameter
      in: header
      required: true
      schema: true
    post:
      parameters:
      - name: alpha
        in: query
        required: true
        schema:
          pattern: ^[0-9]+\$
      - \$ref: '#/components/parameters/foo-header'
      - name: beta
        in: query
        required: false
        schema:
          not: true
      - name: gamma
        in: query
        required: false
        content:
          unknown/encodingtype:
            schema: true
      - name: delta
        in: query
        required: false
        content:
          unknown/encodingtype:
            schema:
              not: true
      - name: epsilon
        in: query
        required: false
        content:
          apPlicATion/jsON:
            schema:
              not: true
      - name: zeta
        in: query
        required: false
        content:
          iMAgE/*:
            schema:
              not: true
      - \$ref: '#/components/parameters/bar-header-ref'
YAML
  # note that bar_id is not listed as a path parameter

  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/query/alpha',
          keywordLocation => jsonp(qw(/paths /foo post parameters 0 required)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post parameters 0 required)))->to_string,
          error => 'missing query parameter: alpha',
        },
        {
          instanceLocation => '/request/header/Alpha',
          keywordLocation => jsonp(qw(/paths /foo post parameters 1 $ref required)),
          absoluteKeywordLocation => $doc_uri->clone->fragment('/components/parameters/foo-header/required')->to_string,
          error => 'missing header: Alpha',
        },
        {
          instanceLocation => '/request/header/Beta',
          keywordLocation => jsonp(qw(/paths /foo post parameters 7 $ref $ref required)),
          absoluteKeywordLocation => $doc_uri->clone->fragment('/components/parameters/bar-header/required')->to_string,
          error => 'missing header: Beta',
        },
      ],
    },
    'query and header parameters are missing; header names are case-insensitive',
  );

  $request = request('POST', 'http://example.com/foo?alpha=1&gamma=foo&delta=bar', [ Alpha => 1, Beta => 1 ]);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/query/delta',
          keywordLocation => jsonp(qw(/paths /foo post parameters 4 content unknown/encodingtype)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post parameters 4 content unknown/encodingtype)))->to_string,
          error => 'EXCEPTION: unsupported media type "unknown/encodingtype": add support with $openapi->add_media_type(...)',
        },
      ],
    },
    'a missing media-type is not an error if the schema is a no-op true schema',
  );

  $openapi->add_media_type('unknown/*' => sub ($value) { $value });

  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/query/delta',
          keywordLocation => jsonp(qw(/paths /foo post parameters 4 content unknown/encodingtype schema not)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post parameters 4 content unknown/encodingtype schema not)))->to_string,
          error => 'subschema is valid',
        },
      ],
    },
    'after adding wildcard support, this parameter can be parsed',
  );

  $request = request('POST', 'http://example.com/foo', [ Alpha => 1, Beta => 1 ]);
  query_params($request, [alpha => 1, epsilon => '{"foo":42}']);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/query/epsilon',
          keywordLocation => jsonp(qw(/paths /foo post parameters 5 content apPlicATion/jsON schema not)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post parameters 5 content apPlicATion/jsON schema not)))->to_string,
          error => 'subschema is valid',
        },
      ],
    },
    'media-types in the openapi document are looked up case-insensitively',
  );

  $openapi->add_media_type('image/*' => sub ($value) { $value });

  $request = request('POST', 'http://example.com/foo?alpha=1&zeta=binary', [ Alpha => 1, Beta => 1 ]);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/query/zeta',
          keywordLocation => jsonp(qw(/paths /foo post parameters 6 content iMAgE/* schema not)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post parameters 6 content iMAgE/* schema not)))->to_string,
          error => 'subschema is valid',
        },
      ],
    },
    'wildcard media-types in the openapi document are looked up case-insensitively too',
  );

  $request = request('POST', 'http://example.com/foo?alpha=hello&beta=3.1415',
    [ 'alpha' => 'header value', Beta => 1 ]);    # exactly matches query parameter
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/query/alpha',
          keywordLocation => jsonp(qw(/paths /foo post parameters 0 schema pattern)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post parameters 0 schema pattern)))->to_string,
          error => 'pattern does not match',
        },
        {
          instanceLocation => '/request/header/Alpha',
          keywordLocation => jsonp(qw(/paths /foo post parameters 1 $ref schema pattern)),
          absoluteKeywordLocation => $doc_uri->clone->fragment('/components/parameters/foo-header/schema/pattern')->to_string,
          error => 'pattern does not match',
        },
        {
          instanceLocation => '/request/uri/query/beta',
          keywordLocation => jsonp(qw(/paths /foo post parameters 2 schema not)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post parameters 2 schema not)))->to_string,
          error => 'subschema is valid',
        },
      ],
    },
    'query and header parameters are evaluated against their schemas',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    get:
      parameters:
      - name: query1
        in: query
        required: true
        content:
          application/json:
            schema:
              required: ['key']
      - name: Header1
        in: header
        required: true
        content:
          application/json:
            schema:
              required: ['key']
YAML

  $request = request('GET', 'http://example.com/foo', [ 'Header1' => '{corrupt json' ]); # } for vim
  query_params($request, [query1 => '{corrupt json']); # } for vim
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/query/query1',
          keywordLocation => jsonp(qw(/paths /foo get parameters 0 content application/json)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo get parameters 0 content application/json)))->to_string,
          error => re(qr/^could not decode content as application\/json: /),
        },
        {
          instanceLocation => '/request/header/Header1',
          keywordLocation => jsonp(qw(/paths /foo get parameters 1 content application/json)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo get parameters 1 content application/json)))->to_string,
          error => re(qr/^could not decode content as application\/json: /),
        },
      ],
    },
    'errors during media-type decoding are detected',
  );

  $request = request('GET', 'http://example.com/foo', [ 'Header1' => '{"hello":"there"}' ]);
  query_params($request, [query1 => '{"hello":"there"}']);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/query/query1',
          keywordLocation => jsonp(qw(/paths /foo get parameters 0 content application/json schema required)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo get parameters 0 content application/json schema required)))->to_string,
          error => 'object is missing property: key',
        },
        {
          instanceLocation => '/request/header/Header1',
          keywordLocation => jsonp(qw(/paths /foo get parameters 1 content application/json schema required)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo get parameters 1 content application/json schema required)))->to_string,
          error => 'object is missing property: key',
        },
      ],
    },
    'parameters are decoded using the indicated media type and then validated against the content schema',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    parameters:
    - name: alpha
      in: query
      required: true
      schema:
        pattern: ^[0-9]+\$
    - name: beta
      in: query
      required: true
      schema:
        pattern: ^[0-9]+\$
    - name: alpha
      in: header
      required: true
      schema:
        pattern: ^[0-9]+\$
    - name: beta
      in: header
      required: true
      schema:
        pattern: ^[0-9]+\$
    get:
      parameters:
      - name: alpha
        in: query
        required: true
        schema:
          maxLength: 1
      - name: alpha
        in: header
        required: true
        schema:
          maxLength: 1
YAML

  $request = request('GET', 'http://example.com/foo?alpha=hihihi&beta=hihihi', [ Alpha => 'hihihi', Beta => 'hihihi' ]);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/query/alpha',
          keywordLocation => jsonp(qw(/paths /foo get parameters 0 schema maxLength)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo get parameters 0 schema maxLength)))->to_string,
          error => 'length is greater than 1',
        },
        {
          instanceLocation => '/request/header/alpha',
          keywordLocation => jsonp(qw(/paths /foo get parameters 1 schema maxLength)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo get parameters 1 schema maxLength)))->to_string,
          error => 'length is greater than 1',
        },
        {
          instanceLocation => '/request/uri/query/beta',
          keywordLocation => jsonp(qw(/paths /foo parameters 1 schema pattern)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo parameters 1 schema pattern)))->to_string,
          error => 'pattern does not match',
        },
        {
          instanceLocation => '/request/header/beta',
          keywordLocation => jsonp(qw(/paths /foo parameters 3 schema pattern)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo parameters 3 schema pattern)))->to_string,
          error => 'pattern does not match',
        },
      ],
    },
    'query, header parameters: operation overshadows path-item',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    get:
      requestBody:
        \$ref: '#/i_do_not_exist'
YAML

  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo get requestBody $ref)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo get requestBody $ref)))->to_string,
          error => 'EXCEPTION: unable to find resource /api#/i_do_not_exist',
        },
      ],
    },
    'bad $ref in requestBody',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
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
          blOOp/HTml:
            schema:
              not: true
          text/plain:
            schema:
              const: éclair
          unknown/encodingtype:
            schema:
              not: true
          iMAgE/*:
            schema:
              not: true
YAML

  # note: no content!
  $request = request('POST', 'http://example.com/foo');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody required)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody required)))->to_string,
          error => 'request body is required but missing',
        },
      ],
    },
    'request body is missing',
  );

  TODO: {
    local $TODO = 'mojo will strip the content body when parsing a stringified request that lacks Content-Length'
      if $::TYPE eq 'lwp' or $::TYPE eq 'plack' or $::TYPE eq 'catalyst';

    $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'text/plain' ], 'éclair');
    remove_header($request, 'Content-Length');

    cmp_result(
      ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
      {
        valid => false,
        errors => [
          {
            instanceLocation => '/request/header',
            keywordLocation => jsonp(qw(/paths /foo post)),
            absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post)))->to_string,
            error => 'missing header: Content-Length',
          },
        ],
      },
      'Content-Length is required in requests with a message body',
    );
  }

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'text/bloop' ], 'plain text');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content)))->to_string,
          error => 'incorrect Content-Type "text/bloop"',
        },
      ],
    },
    'Content-Type not allowed by the schema',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'text/plain; charset=us-ascii' ], 'ascii plain text');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content text/plain schema const)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content text/plain schema const)))->to_string,
          error => 'value does not match',
        },
      ],
    },
    'us-ascii text can be decoded and matched',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'blOOp/HTML' ], 'html text (bloop style)');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content blOOp/HTml)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content blOOp/HTml)))->to_string,
          error => 'EXCEPTION: unsupported media type "blOOp/HTml": add support with $openapi->add_media_type(...)',
        },
      ],
    },
    'unsupported Content-Type - but matched against the document case-insensitively',
  );


  # we have to add media-types in foldcased format
  $openapi->add_media_type('bloop/html' => sub ($content_ref) { $content_ref });

  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content blOOp/HTml schema not)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content blOOp/HTml schema not)))->to_string,
          error => 'subschema is valid',
        },
      ],
    },
    'Content-Type looked up case-insensitively and matched in the document case-insensitively too',
  );


  $openapi->add_media_type('unknown/*' => sub ($value) { $value });

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'unknown/encodingtype' ], 'binary');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content unknown/encodingtype schema not)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content unknown/encodingtype schema not)))->to_string,
          error => 'subschema is valid',
        },
      ],
    },
    'wildcard support in the media type registry is used to handle an otherwise-unknown content type',
  );


  # this will match against the document at image/*
  # but we have no media-type registry for image/*, only image/jpeg
  $openapi->add_media_type('image/jpeg' => sub ($value) { $value });
  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'image/jpeg' ], 'binary');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content iMAgE/* schema not)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content iMAgE/* schema not)))->to_string,
          error => 'subschema is valid',
        },
      ],
    },
    'Content-Type header is matched to a wildcard entry in the document, then matched to a media-type implementation',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'text/plain; charset=UTF-8' ],
    chr(0xe9).'clair"}');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content text/plain)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content text/plain)))->to_string,
          error => re(qr/^could not decode content as UTF-8: UTF-8 "\\xE9" does not map to Unicode/),
        },
      ],
    },
    'errors during charset decoding are detected',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'text/plain; charset=ISO-8859-1' ],
    chr(0xe9).'clair');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'latin1 content can be successfully decoded',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'text/plain; charset=UTF-8' ],
    chr(0xe9).'clair');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content text/plain)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content text/plain)))->to_string,
          error => re(qr/^could not decode content as UTF-8: UTF-8 "\\xE9" does not map to Unicode/),
        },
      ],
    },
    'errors during charset decoding are detected',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'application/json; charset=UTF-8' ],
    '{"alpha": "123", "beta": "'.chr(0xe9).'clair"}');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content application/json)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content application/json)))->to_string,
          error => re(qr/^could not decode content as application\/json: malformed UTF-8 character in JSON string/),
        },
      ],
    },
    'charset encoding errors in json are decoded in the main decoding step',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'application/json; charset=UTF-8' ],
    '{corrupt json'); # } to mollify vim
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content application/json)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content application/json)))->to_string,
          error => re(qr/^could not decode content as application\/json: /),
        },
      ],
    },
    'errors during media-type decoding are detected',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'application/json' ],
    '{"alpha": "123", "beta": "'."\x{c3}\x{a9}".'clair"}');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'application/json is utf-8 encoded',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'application/json; charset=UTF-8' ],
    '{"alpha": "123", "beta": "'."\x{c3}\x{a9}".'clair"}');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'charset is ignored for application/json',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'application/json; charset=UTF-8' ],
    '{"alpha": "foo", "gamma": "o.o"}');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body/alpha',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content application/json schema properties alpha pattern)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content application/json schema properties alpha pattern)))->to_string,
          error => 'pattern does not match',
        },
        {
          instanceLocation => '/request/body/gamma',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content application/json schema properties gamma const)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content application/json schema properties gamma const)))->to_string,
          error => 'value does not match',
        },
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content application/json schema properties)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content application/json schema properties)))->to_string,
          error => 'not all properties are valid',
        },
      ],
    },
    'decoded content does not match the schema',
  );


  my $disapprove = v224.178.160.95.224.178.160; # utf-8-encoded "ಠ_ಠ"
  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'application/json; charset=UTF-8' ],
    '{"alpha": "123", "gamma": "'.$disapprove.'"}');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'decoded content matches the schema',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    post:
      requestBody:
        required: true
        content:
          '*/*':
            schema:
              minLength: 10
YAML
  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'unsupported/unsupported' ], '!!!');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content */* schema minLength)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content */* schema minLength)))->to_string,
          error => 'length is less than 10',
        },
      ],
    },
    'unknown content type can still be evaluated if */* is an acceptable media-type',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'a/b' ], '0');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content */* schema minLength)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content */* schema minLength)))->to_string,
          error => 'length is less than 10',
        },
      ],
    },
    '"false" body is still seen',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    post:
      requestBody:
        required: true
        content:
          application/json: {}
          electric/boogaloo: {}
YAML

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'application/json' ], 'corrupt_json');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content application/json)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content application/json)))->to_string,
          error => re(qr/^could not decode content as application\/json: malformed JSON string/),
        },
      ],
    },
    'corrupt data is detected, even when there is no schema',
  );

  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'application/json' ], '{}');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'valid encoded content is always valid when there is no schema',
  );

  cmp_result(
    ($result = $openapi->validate_request(request('POST', 'http://example.com/foo', [ 'Content-Type' => 'electric/boogaloo' ], 'blah'), { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    '..even when the media-type is unknown',
  );
};

subtest 'document errors' => sub {
  my $request = request('GET', 'http://example.com/foo?alpha=1');
  my $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
components:
  parameters:
    alpha:
      name: alpha
      in: query
      required: true
      schema: {}
paths:
  /foo:
    parameters:
    - \$ref: '#/components/parameters/alpha'
    - \$ref: '#/components/parameters/alpha'
    get: {}
YAML

  cmp_result(
    (my $result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request',
          keywordLocation => jsonp(qw(/paths /foo parameters 1 $ref)),
          absoluteKeywordLocation => $doc_uri->clone->fragment('/components/parameters/alpha')->to_string,
          error => 'duplicate query parameter "alpha"',
        },
      ],
    },
    'duplicate query parameters in path-item section',
  );

  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
components:
  parameters:
    alpha:
      name: alpha
      in: query
      required: true
      schema: {}
paths:
  /foo:
    get:
      parameters:
      - \$ref: '#/components/parameters/alpha'
      - \$ref: '#/components/parameters/alpha'
YAML

  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request',
          keywordLocation => jsonp(qw(/paths /foo get parameters 1 $ref)),
          absoluteKeywordLocation => $doc_uri->clone->fragment('/components/parameters/alpha')->to_string,
          error => 'duplicate query parameter "alpha"',
        },
      ],
    },
    'duplicate query parameters in operation section',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    post:
      requestBody:
        required: false
        content:
          text/plain:
            schema:
              minLength: 10
YAML

  # bypass auto-initialization of Content-Length, Content-Type
  $request = request('POST', 'http://example.com/foo', [ 'Content-Length' => 1 ], '!');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/header/Content-Type',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content)))->to_string,
          error => 'missing header: Content-Type',
        },
      ],
    },
    'missing Content-Type is an error, not an exception',
  );

  # bypass auto-initialization of Content-Length, Content-Type; leave Content-Length empty
  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'text/plain' ], '!');
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content text/plain schema minLength)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content text/plain schema minLength)))->to_string,
          error => 'length is less than 10',
        },
      ],
    },
    'missing Content-Length does not prevent the request body from being checked',
  );


  $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'text/plain' ]);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'request body is missing but not required',
  );
};

subtest 'type handling of values for evaluation' => sub {
  my $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo/{foo_id}:
    parameters:
    - name: foo_id
      in: path
      required: true
      schema:
        pattern: ^[a-z]\$
    post:
      parameters:
      - name: bar
        in: query
        required: false
        schema:
          pattern: ^[a-z]\$
      - name: Foo-Bar
        in: header
        required: false
        schema:
          pattern: ^[a-z]\$
      requestBody:
        required: true
        content:
          text/plain:
            schema:
              pattern: ^[a-z]\$
YAML

  my $request = request('POST', 'http://example.com/foo/123?bar=456',
    [ 'Foo-Bar' => 789, 'Content-Type' => 'text/plain' ], 666);
  cmp_result(
    (my $result = $openapi->validate_request($request,
      { path_template => '/foo/{foo_id}', path_captures => { foo_id => 123 } }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/query/bar',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}', qw(post parameters 0 schema pattern)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}', qw(post parameters 0 schema pattern)))->to_string,
          error => 'pattern does not match',
        },
        {
          instanceLocation => '/request/header/Foo-Bar',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}', qw(post parameters 1 schema pattern)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}', qw(post parameters 1 schema pattern)))->to_string,
          error => 'pattern does not match',
        },
        {
          instanceLocation => '/request/uri/path/foo_id',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}', qw(parameters 0 schema pattern)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}', qw(parameters 0 schema pattern)))->to_string,
          error => 'pattern does not match',
        },
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp('/paths', '/foo/{foo_id}', qw(post requestBody content text/plain schema pattern)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{foo_id}', qw(post requestBody content text/plain schema pattern)))->to_string,
          error => 'pattern does not match',
        },
      ],
    },
    'numeric values are treated as strings by default',
  );


  $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo/{path_plain}/bar/{path_encoded}:
    parameters:
    - name: path_plain
      in: path
      required: true
      schema:
        type: integer
        maximum: 10
    - name: path_encoded
      in: path
      required: true
      content:
        text/plain:
          schema:
            type: integer
            maximum: 10
    post:
      parameters:
      - name: query_plain
        in: query
        required: false
        schema:
          type: integer
          maximum: 10
      - name: query_encoded
        in: query
        required: false
        content:
          text/plain:
            schema:
              type: integer
              maximum: 10
      - name: Header-Plain
        in: header
        required: false
        schema:
          type: integer
          maximum: 10
      - name: Header-Encoded
        in: header
        required: false
        content:
          text/plain:
            schema:
              type: integer
              maximum: 10
      requestBody:
        required: true
        content:
          text/plain:
            schema:
              type: integer
              maximum: 10
YAML

  $request = request('POST', 'http://example.com/foo/11/bar/12?query_plain=13&query_encoded=14',
    [ 'Header-Plain' => 15, 'Header-Encoded' => 16, 'Content-Type' => 'text/plain' ], 17);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo/{path_plain}/bar/{path_encoded}', path_captures => { path_plain => 11, path_encoded => 12 } }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/query/query_plain',
          keywordLocation => jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post parameters 0 schema maximum)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post parameters 0 schema maximum)))->to_string,
          error => 'value is larger than 10',
        },
        {
          instanceLocation => '/request/uri/query/query_encoded',
          keywordLocation => jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post parameters 1 content text/plain schema type)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post parameters 1 content text/plain schema type)))->to_string,
          error => 'got string, not integer',
        },
        {
          instanceLocation => '/request/header/Header-Plain',
          keywordLocation => jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post parameters 2 schema maximum)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post parameters 2 schema maximum)))->to_string,
          error => 'value is larger than 10',
        },
        {
          instanceLocation => '/request/header/Header-Encoded',
          keywordLocation => jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post parameters 3 content text/plain schema type)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post parameters 3 content text/plain schema type)))->to_string,
          error => 'got string, not integer',
        },
        {
          instanceLocation => '/request/uri/path/path_plain',
          keywordLocation => jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(parameters 0 schema maximum)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(parameters 0 schema maximum)))->to_string,
          error => 'value is larger than 10',
        },
        {
          instanceLocation => '/request/uri/path/path_encoded',
          keywordLocation => jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(parameters 1 content text/plain schema type)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(parameters 1 content text/plain schema type)))->to_string,
          error => 'got string, not integer',
        },
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post requestBody content text/plain schema type)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post requestBody content text/plain schema type)))->to_string,
          error => 'got string, not integer',
        },
      ],
    },
    'numeric values are treated as numbers when explicitly type-checked as numbers, but only when not encoded',
  );


  my $val = 20; my $str = sprintf("%s\n", $val);
  $request = request('POST', 'http://example.com/foo/20/bar/hi', [ 'Content-Type' => 'text/plain' ], $val);
  cmp_result(
    ($result = $openapi->validate_request($request,
      { path_template => '/foo/{path_plain}/bar/{path_encoded}', path_captures => { path_plain => $val, path_encoded => 'hi' } }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/uri/path/path_plain',
          keywordLocation => jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(parameters 0 schema maximum)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(parameters 0 schema maximum)))->to_string,
          error => 'value is larger than 10',
        },
        {
          instanceLocation => '/request/uri/path/path_encoded',
          keywordLocation => jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(parameters 1 content text/plain schema type)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(parameters 1 content text/plain schema type)))->to_string,
          error => 'got string, not integer',
        },
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post requestBody content text/plain schema type)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo/{path_plain}/bar/{path_encoded}', qw(post requestBody content text/plain schema type)))->to_string,
          error => 'got string, not integer',
        },
      ],
    },
    'ambiguously-typed numbers are still handled gracefully',
  );
};

subtest 'parameter parsing' => sub {
  my $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    get:
      parameters:
      - name: SingleValue
        in: header
        schema:
          const: mystring
      - name: MultipleValuesAsString
        in: header
        schema:
          const: 'one, two, three'
      - name: MultipleValuesAsArray
        in: header
        schema:
          type: array
          uniqueItems: true
          minItems: 3
          maxItems: 3
          items:
            enum: [one, two, three]
      - name: MultipleValuesAsObjectExplodeFalse
        in: header
        schema:
          type: object
          minProperties: 3
          maxProperties: 3
          properties:
            R:
              const: '100'
            G:
              type: integer
            B:
              maximum: 300
              minimum: 300
      - name: MultipleValuesAsObjectExplodeTrue
        in: header
        explode: true
        schema:
          type: object
          minProperties: 3
          maxProperties: 3
          properties:
            R:
              const: '100'
            G:
              type: integer
            B:
              maximum: 300
              minimum: 300
      - name: ArrayWithRef
        in: header
        schema:
          \$ref: '#/paths/~1foo/get/parameters/2/schema'
      - name: ArrayWithRefAndOtherKeywords
        in: header
        schema:
          \$ref: '#/paths/~1foo/get/parameters/2/schema'
          not: true
      - name: ArrayWithBrokenRef
        in: header
        schema:
          \$ref: '#/components/schemas/i_do_not_exist'
      - name: MultipleValuesAsRawString
        in: header
        schema:
          const: 'one , two  , three'
YAML

  my $request = request('GET', 'http://example.com/foo', [ SingleValue => '  mystring  ']);
  cmp_result(
    (my $result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'a single header value has its leading and trailing whitespace stripped',
  );

  $request = request('GET', 'http://example.com/foo', [ MultipleValuesAsRawString => '  one , two  , three  ']);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'multiple values in a single header are validated as a string, with only leading and trailing whitespace stripped',
  );

  TODO: {
  $request = request('GET', 'http://example.com/foo', [
      MultipleValuesAsString => '  one ',
      MultipleValuesAsString => ' two  ',
      MultipleValuesAsString => 'three  ',
    ]);
  local $TODO = 'HTTP::Message::to_psgi fetches all headers as a single concatenated string'
    if $::TYPE eq 'plack' or $::TYPE eq 'catalyst';
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'multiple headers on separate lines are validated as a string, with leading and trailing whitespace stripped',
  );
  }

  $request = request('GET', 'http://example.com/foo', [ MultipleValuesAsArray => '  one, two, three  ']);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'headers can be parsed into an array in order to test multiple values without sorting',
  );

  $request = request('GET', 'http://example.com/foo', [
    MultipleValuesAsArray => '  one',
    MultipleValuesAsArray => ' one ',
    MultipleValuesAsArray => ' three ',
  ]);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/header/MultipleValuesAsArray',
          keywordLocation => jsonp('/paths', '/foo', qw(get parameters 2 schema uniqueItems)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo', qw(get parameters 2 schema uniqueItems)))->to_string,
          error => 'items at indices 0 and 1 are not unique',
        },
      ],
    },
    'headers that appear more than once are parsed into an array',
  );


  $request = request('GET', 'http://example.com/foo', [
      MultipleValuesAsObjectExplodeFalse => ' R, 100 ',
      MultipleValuesAsObjectExplodeFalse => ' B, 300,  G , 200 ',
      MultipleValuesAsObjectExplodeTrue => ' R=100  , B=300 ',
      MultipleValuesAsObjectExplodeTrue => '  G=200 ',
    ]);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    { valid => true },
    'headers can be parsed into an object, represented in two ways depending on explode value',
  );

  $request = request('GET', 'http://example.com/foo', [
      ArrayWithRef => 'one, one, three',
      ArrayWithRefAndOtherKeywords => 'one, one, three',
      ArrayWithBrokenRef => 'hi',
    ]);
  cmp_result(
    ($result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/header/ArrayWithRef',
          keywordLocation => jsonp('/paths', '/foo', qw(get parameters 5 schema $ref uniqueItems)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo', qw(get parameters 2 schema uniqueItems)))->to_string,
          error => 'items at indices 0 and 1 are not unique',
        },
        {
          instanceLocation => '/request/header/ArrayWithRefAndOtherKeywords',
          keywordLocation => jsonp('/paths', '/foo', qw(get parameters 6 schema $ref uniqueItems)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo', qw(get parameters 2 schema uniqueItems)))->to_string,
          error => 'items at indices 0 and 1 are not unique',
        },
        {
          instanceLocation => '/request/header/ArrayWithRefAndOtherKeywords',
          keywordLocation => jsonp('/paths', '/foo', qw(get parameters 6 schema not)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo', qw(get parameters 6 schema not)))->to_string,
          error => 'subschema is valid',
        },
        {
          instanceLocation => '/request/header/ArrayWithBrokenRef',
          keywordLocation => jsonp('/paths', '/foo', qw(get parameters 7 schema $ref)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp('/paths', '/foo', qw(get parameters 7 schema $ref)))->to_string,
          error => 'EXCEPTION: unable to find resource /api#/components/schemas/i_do_not_exist',
        },
      ],
    },
    'header schemas can use a $ref and we follow it correctly, updating locations, and respect adjacent keywords',
  );
};

subtest 'max_depth' => sub {
  my $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    evaluator => JSON::Schema::Modern->new(max_traversal_depth => 15, validate_formats => 1),
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
components:
  parameters:
    foo:
      \$ref: '#/components/parameters/bar'
    bar:
      \$ref: '#/components/parameters/foo'
paths:
  /foo:
    post:
      parameters:
      - \$ref: '#/components/parameters/foo'
YAML

  my $request = request('POST', 'http://example.com/foo');
  cmp_result(
    (my $result = $openapi->validate_request($request, { path_template => '/foo', path_captures => {} }))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request',
          keywordLocation => jsonp(qw(/paths /foo post parameters 0), ('$ref')x17),
          absoluteKeywordLocation => $doc_uri->clone->fragment('/components/parameters/bar/$ref')->to_string,
          error => 'EXCEPTION: maximum evaluation depth exceeded',
        },
      ],
    },
    'bad $ref in operation parameters',
  );
};

subtest 'unevaluatedProperties and annotations' => sub {
  my $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    evaluator => JSON::Schema::Modern->new(validate_formats => 1),
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    post:
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                bar: true
              unevaluatedProperties: false
YAML

  my $request = request('POST', 'http://example.com/foo', [ 'Content-Type' => 'application/json' ], '{"foo":1}');
  cmp_result(
    (my $result = $openapi->validate_request($request))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body/foo',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content application/json schema unevaluatedProperties)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content application/json schema unevaluatedProperties)))->to_string,
          error => 'additional property not permitted',
        },
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo post requestBody content application/json schema unevaluatedProperties)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo post requestBody content application/json schema unevaluatedProperties)))->to_string,
          error => 'not all additional properties are valid',
        },
      ],
    },
    'unevaluatedProperties can be used in schemas',
  );
};

subtest 'readOnly' => sub {
  my $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    evaluator => JSON::Schema::Modern->new(validate_formats => 1),
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    post:
      parameters:
      - name: a
        in: query
        schema:
          readOnly: true
          writeOnly: true
      - name: b
        in: query
        schema:
          readOnly: false
          writeOnly: false
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                c:
                  readOnly: true
                  writeOnly: true
                d:
                  readOnly: false
                  writeOnly: false
          text/plain:
            schema: {}
YAML

  my $request = request('POST', 'http://example.com/foo?a=1&b=2',
    [ 'Content-Type' => 'application/json' ], '{"c":1,"d":2}');
  cmp_result(
    (my $result = $openapi->validate_request($request))->TO_JSON,
    { valid => true },
    'readOnly values are still valid in a request',
  );

  cmp_result(
    ($result = $openapi->validate_request(request('POST', 'http://example.com/foo', [ 'Content-Type' => 'text/plain' ], 'hi')))->TO_JSON,
    { valid => true },
    'no errors when processing an empty body schema',
  );
};

subtest 'no bodies in GET or HEAD requests without requestBody' => sub {
  my $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    evaluator => JSON::Schema::Modern->new(validate_formats => 1),
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo:
    head: {}
    get: {}
    post: {}
YAML

  my $result;
  cmp_result(
    ($result = $openapi->validate_request(request($_, 'http://example.com/foo', [], 'content')))->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo), lc),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo), lc))->to_string,
          error => 'unspecified body is present in '.$_.' request',
        },
      ],
    },
    'no body permitted for '.$_,
  ) foreach qw(GET HEAD);

  cmp_result(
    ($result = $openapi->validate_request(request('POST', 'http://example.com/foo', [], 'content')))->TO_JSON,
    { valid => true },
    'no errors from POST with body',
  );

SKIP: {
  # "Bad Content-Length: maybe client disconnect? (1 bytes remaining)"
  skip 'plack dies on this input', 3 if $::TYPE eq 'plack' or $::TYPE eq 'catalyst';
  cmp_result(
    ($result = do {
      my $x = allow_patterns(qr/^parse error when converting HTTP::Request/) if $::TYPE eq 'lwp';
      $openapi->validate_request(request($_, 'http://example.com/foo', [ 'Content-Length' => 1]));
    })->TO_JSON,
    {
      valid => false,
      errors => [
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo), lc),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo), lc))->to_string,
          error => 'unspecified body is present in '.$_.' request',
        },
      ],
    },
    'non-zero Content-Length not permitted for '.$_,
  ) foreach qw(GET HEAD);

  cmp_result(
    ($result = do {
      my $x = allow_patterns(qr/^parse error when converting HTTP::Request/) if $::TYPE eq 'lwp';
      $openapi->validate_request(request('POST', 'http://example.com/foo', [ 'Content-Length' => 1]));
    })->TO_JSON,
    { valid => true },
    'no errors from POST with Content-Length',
  );
} # end SKIP
};

subtest 'custom error messages for false schemas' => sub {
  my $openapi = OpenAPI::Modern->new(
    openapi_uri => '/api',
    evaluator => JSON::Schema::Modern->new(validate_formats => 1),
    openapi_schema => $yamlpp->load_string(<<YAML));
$openapi_preamble
paths:
  /foo/{foo_id}:
    post:
      parameters:
      - name: foo_id
        in: path
        required: true
        schema: false
      - name: Foo
        in: header
        schema: false
      - name: foo
        in: query
        schema: false
      requestBody:
        content:
          '*/*':
            schema: false
YAML

  cmp_result(
    (my $result = $openapi->validate_request(request('POST', 'http://example.com/foo/1?foo=1',
          [ Foo => 1, 'Content-Type' => 'text/plain' ], 'hi')))->TO_JSON,
    {
      valid => false,
      errors => [
        # this is paradoxical, but we'll test it anyway
        {
          instanceLocation => '/request/uri/path/foo_id',
          keywordLocation => jsonp(qw(/paths /foo/{foo_id} post parameters 0 schema)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo/{foo_id} post parameters 0 schema)))->to_string,
          error => 'path parameter not permitted',
        },
        {
          instanceLocation => '/request/header/Foo',
          keywordLocation => jsonp(qw(/paths /foo/{foo_id} post parameters 1 schema)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo/{foo_id} post parameters 1 schema)))->to_string,
          error => 'request header not permitted',
        },
        {
          instanceLocation => '/request/uri/query/foo',
          keywordLocation => jsonp(qw(/paths /foo/{foo_id} post parameters 2 schema)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo/{foo_id} post parameters 2 schema)))->to_string,
          error => 'query parameter not permitted',
        },
        {
          instanceLocation => '/request/body',
          keywordLocation => jsonp(qw(/paths /foo/{foo_id} post requestBody content */* schema)),
          absoluteKeywordLocation => $doc_uri->clone->fragment(jsonp(qw(/paths /foo/{foo_id} post requestBody content */* schema)))->to_string,
          error => 'request body not permitted',
        },
      ],
    },
    'custom error message when the entity is not permitted',
  );
};

goto START if ++$type_index < @::TYPES;

done_testing;
