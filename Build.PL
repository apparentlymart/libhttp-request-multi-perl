use Module::Build;

my $build = Module::Build
  ->new( module_name   => "HTTP::Request::Multi",
         dist_abstract => "Parallel pipelined HTTP Requests", 
         license       => 'perl',
         script_files  => [ ],
         requires      => {
                          'HTTP::Request'              => 0,
                          'HTTP::Response'             => 0,
                          'MIME::Tools'                => 0,
                          'Test::More'                 => 0,
                        },
         create_makefile_pl => 'traditional',
       );

$build->create_build_script;


