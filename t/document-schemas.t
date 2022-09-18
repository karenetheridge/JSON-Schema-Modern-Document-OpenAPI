use strictures 2;
use experimental qw(signatures postderef);
use if "$]" >= 5.022, experimental => 're_strict';
no if "$]" >= 5.031009, feature => 'indirect';
no if "$]" >= 5.033001, feature => 'multidimensional';
no if "$]" >= 5.033006, feature => 'bareword_filehandles';
use open ':std', ':encoding(UTF-8)'; # force stdin, stdout, stderr into utf8

use Test::More 0.96;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::Deep;
use JSON::Schema::Modern;
use JSON::Schema::Modern::Document::OpenAPI;
use Test::File::ShareDir -share => { -dist => { 'OpenAPI-Modern' => 'share' } };

my $preamble = {
  openapi => '3.1.0',
  info => {
    title => 'my title',
    version => '1.2.3',
  },
};

subtest 'bad subschemas' => sub {
  my $doc = JSON::Schema::Modern::Document::OpenAPI->new(
    canonical_uri => 'http://localhost:1234/api',
    evaluator => my $js = JSON::Schema::Modern->new,
    schema => {
      %$preamble,
      jsonSchemaDialect => JSON::Schema::Modern::Document::OpenAPI->DEFAULT_DIALECT,
      components => {
        schemas => {
          alpha_schema => {
            '$id' => 'alpha',
            not => {
              minimum => 'not a number',
            },
          },
        },
      },
    },
  );

  cmp_deeply(
    ($doc->errors)[0],
    methods(
      instance_location => '/components/schemas/alpha_schema/not/minimum',
      keyword_location => re(qr{/\$ref/properties/minimum/type$}),
      absolute_keyword_location => str('https://json-schema.org/draft/2020-12/meta/validation#/properties/minimum/type'),
      error => 'got string, not number',
      mode => 'evaluate',
    ),
    'subschemas identified, and error found',
  );

  my $serialized = JSON::Schema::Modern::Result->new(
    valid => 0,
    errors => [ $doc->errors ],
    exception => 1,
  );

  is(
    index($serialized, "'/components/schemas/alpha_schema/not/minimum': got string, not number\n"), 0,
    'errors serialize using the instance locations within the document',
  );
};

subtest 'identify subschemas' => sub {
  my $doc = JSON::Schema::Modern::Document::OpenAPI->new(
    canonical_uri => 'http://localhost:1234/api',
    metaschema_uri => 'https://spec.openapis.org/oas/3.1/schema',
    evaluator => my $js = JSON::Schema::Modern->new,
    schema => {
      %$preamble,
      components => {
        schemas => {
          beta_schema => {
            '$id' => 'beta',
            not => {
              '$id' => 'gamma',
              '$schema' => 'https://json-schema.org/draft/2019-09/schema',
            },
          },
        },
        parameters => {
          my_param1 => {
            name => 'param1',
            in => 'query',
            schema => {
              '$id' => 'parameter1_id',
            },
          },
          my_param2 => {
            name => 'param2',
            in => 'query',
            content => {
              media_type_0 => {
                schema => {
                  '$id' => 'parameter2_id',
                },
              },
            },
          },
        },
        pathItems => {
          path0 => {
            parameters => [
              {
                name => 'param0',
                in => 'query',
                schema => {
                  '$id' => 'pathItem0_param_id',
                },
              },
              # TODO param2 with content/media_type_0
            ],
            get => {
              parameters => [
                {
                  name => 'param1',
                  in => 'query',
                  schema => {
                    '$id' => 'pathItem0_get_param_id',
                  },
                },
              ],
              requestBody => {
                content => {
                  media_type_1 => {
                    schema => {
                      '$id' => 'pathItem0_get_requestBody_id',
                    },
                  },
                },
              },
              responses => {
                200 => {
                  description => 'normal response',
                  content => {
                    media_type_2 => {
                      schema => {
                        '$id' => 'pathItem0_get_responses2_id',
                      },
                    },
                    media_type_3 => {
                      schema => {
                        '$id' => 'pathItem0_get_responses3_id',
                      },
                    },
                  },
                },
              },
            },
          }
        }
      },
    },
  );

  is($doc->errors, 0, 'no errors during traversal');
  cmp_deeply(
    my $index = { $doc->resource_index },
    {
      'http://localhost:1234/api' => {
        path => '',
        canonical_uri => str('http://localhost:1234/api'),
        specification_version => 'draft2020-12',
        vocabularies => [ map 'JSON::Schema::Modern::Vocabulary::'.$_,
          qw(Core Applicator Validation FormatAnnotation Content MetaData Unevaluated OpenAPI) ],
        configs => {},
      },
      'http://localhost:1234/beta' => {
        path => '/components/schemas/beta_schema',
        canonical_uri => str('http://localhost:1234/beta'),
        specification_version => 'draft2020-12',
        vocabularies => [ map 'JSON::Schema::Modern::Vocabulary::'.$_,
          qw(Core Applicator Validation FormatAnnotation Content MetaData Unevaluated OpenAPI) ],
        configs => {},
      },
      'http://localhost:1234/gamma' => {
        path => '/components/schemas/beta_schema/not',
        canonical_uri => str('http://localhost:1234/gamma'),
        specification_version => 'draft2019-09',
        vocabularies => [ map 'JSON::Schema::Modern::Vocabulary::'.$_,
          qw(Core Applicator Validation FormatAnnotation Content MetaData) ], # overridden "$schema" keyword
        configs => {},
      },
      'http://localhost:1234/parameter1_id' => {
        path => '/components/parameters/my_param1/schema',
        canonical_uri => str('http://localhost:1234/parameter1_id'),
        specification_version => 'draft2020-12',
        vocabularies => [ map 'JSON::Schema::Modern::Vocabulary::'.$_,
          qw(Core Applicator Validation FormatAnnotation Content MetaData Unevaluated OpenAPI) ],
        configs => {},
      },
      'http://localhost:1234/parameter2_id' => {
        path => '/components/parameters/my_param2/content/media_type_0/schema',
        canonical_uri => str('http://localhost:1234/parameter2_id'),
        specification_version => 'draft2020-12',
        vocabularies => [ map 'JSON::Schema::Modern::Vocabulary::'.$_,
          qw(Core Applicator Validation FormatAnnotation Content MetaData Unevaluated OpenAPI) ],
        configs => {},
      },
      'http://localhost:1234/pathItem0_param_id' => {
        path => '/components/pathItems/path0/parameters/0/schema',
        canonical_uri => str('http://localhost:1234/pathItem0_param_id'),
        specification_version => 'draft2020-12',
        vocabularies => [ map 'JSON::Schema::Modern::Vocabulary::'.$_,
          qw(Core Applicator Validation FormatAnnotation Content MetaData Unevaluated OpenAPI) ],
        configs => {},
      },
      'http://localhost:1234/pathItem0_get_param_id' => {
        path => '/components/pathItems/path0/get/parameters/0/schema',
        canonical_uri => str('http://localhost:1234/pathItem0_get_param_id'),
        specification_version => 'draft2020-12',
        vocabularies => [ map 'JSON::Schema::Modern::Vocabulary::'.$_,
          qw(Core Applicator Validation FormatAnnotation Content MetaData Unevaluated OpenAPI) ],
        configs => {},
      },
      'http://localhost:1234/pathItem0_get_requestBody_id' => {
        path => '/components/pathItems/path0/get/requestBody/content/media_type_1/schema',
        canonical_uri => str('http://localhost:1234/pathItem0_get_requestBody_id'),
        specification_version => 'draft2020-12',
        vocabularies => [ map 'JSON::Schema::Modern::Vocabulary::'.$_,
          qw(Core Applicator Validation FormatAnnotation Content MetaData Unevaluated OpenAPI) ],
        configs => {},
      },
      map +('http://localhost:1234/pathItem0_get_responses'.$_.'_id' => {
        path => '/components/pathItems/path0/get/responses/200/content/media_type_'.$_.'/schema',
        canonical_uri => str('http://localhost:1234/pathItem0_get_responses'.$_.'_id'),
        specification_version => 'draft2020-12',
        vocabularies => [ map 'JSON::Schema::Modern::Vocabulary::'.$_,
          qw(Core Applicator Validation FormatAnnotation Content MetaData Unevaluated OpenAPI) ],
        configs => {},
      }), 2..3,
    },
    'subschema resources are correctly identified in the document',
  );
};

done_testing;
