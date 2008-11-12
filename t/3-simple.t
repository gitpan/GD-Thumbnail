#!/usr/bin/env perl -w
use strict;
use Test;
use GD::Thumbnail;
use File::Spec;
use Cwd;
use IO::File;

sub save;

BEGIN {
   plan tests => 128;
}

my $COUNTER = 1;

my $foriginal   = File::Spec->catfile(getcwd, 'cpan.jpg');
my $foriginal90 = File::Spec->catfile(getcwd, 'cpan90.jpg');

ok(-e $foriginal   && ! -d _);
ok(-e $foriginal90 && ! -d _);

my($original, $original90);

DUMB_GD_DIES_ON_WINDOWS_PATHS_SO_WE_NEED_SCALARS: {
   my $o   = IO::File->new;
   my $o90 = IO::File->new;

   $o->open("$foriginal")     or die "Can not open $foriginal   : $!";
   $o90->open("$foriginal90") or die "Can not open $foriginal90 : $!";
   binmode $o;
   binmode $o90;

   local $/;
   $original   = <$o>;
   $original90 = <$o90>;
   $o->close;
   $o90->close;
}

my %opt = (
   strip_color => [255, 255, 255],
   info_color  => [  0,   0,   0],
   square      => 1,
   frame       => 1,
);

run();

$opt{square}  = "crop";
$opt{overlay} = 1;
run();

delete @opt{qw/ strip_color info_color square overlay /};
run();

sub run { # x42 tests
   test(GD::Thumbnail->new(%opt), $original  );
   test(GD::Thumbnail->new(%opt), $original90);

   test($_, $original) for
      GD::Thumbnail->new(%opt, force_mime  => 'gif' ),
      GD::Thumbnail->new(%opt, force_mime  => 'png' ),
      GD::Thumbnail->new(%opt, force_mime  => 'jpeg'),
      GD::Thumbnail->new(%opt, force_mime  => 'gd'  ),
      GD::Thumbnail->new(%opt, force_mime  => 'gd2' ),
   ;
}

sub test { # x6 tests
   my $gd  = shift;
   my $img = shift;
   #seek $img, 0, 0;
   ok( save $gd->create($img, 100, 2), $gd->mime );
   ok( save $gd->create($img, 100, 1), $gd->mime );
   ok( save $gd->create($img, 100, 0), $gd->mime );
   $gd->{FRAME}  = 0;
   $gd->{SQUARE} = 0;
   $gd->{OVERLAY}= 0;
   ok( save $gd->create($img, 100, 2), $gd->mime );
   ok( save $gd->create($img, 100, 1), $gd->mime );
   ok( save $gd->create($img, 100, 0), $gd->mime );
}

sub save {
   my($raw, $mime) = @_;
   my $id = sprintf '%04d.%s', $COUNTER++, $mime;
   local  *IMG;
   open    IMG, '>'.$id or die "save error: $!";
   binmode IMG;
   print   IMG $raw;
   close   IMG;
   return  1;
}

exit;
