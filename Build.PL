use strict;
use Module::Build;

Module::Build->new(
   module_name => 'GD::Thumbnail',
   license     => 'perl',
   requires    => { 'GD' => 0 },
   recommends  => {},
   dist_author => 'Burak Gursoy <burak@cpan.org>',
)->create_build_script;
