use ExtUtils::MakeMaker;

WriteMakefile(
   NAME         => 'GD::Thumbnail',
   VERSION_FROM => 'lib/GD/Thumbnail.pm',
   PREREQ_PM    => { 'GD' => 0 },
   ($] >= 5.005 ? (
   AUTHOR       => 'Burak Gursoy <burak@cpan.org>',
   ABSTRACT     => 'Thumbnail maker for GD',
   ) : ()),
   PL_FILES     => {},
);
