package GD::Thumbnail;
use strict;
use vars qw($VERSION %TMP);

$VERSION = '1.35'; # GD version check below breaks ExtUtils::MM

use GD;
use Carp qw( croak );

use constant GIF_OK       => $GD::VERSION >= 2.15 || $GD::VERSION <= 1.19;
use constant DEFAULT_MIME => 'png';
use constant BUFFER       => 2; # y-buffer for info strips in pixels
use constant BLACK        => [  0,   0,   0];
use constant WHITE        => [255, 255, 255];
use constant IMG_X        => 0;
use constant IMG_Y        => 1;
use constant ALL_MIME     => qw(gif png jpeg gd gd2 wbmp);

%TMP = ( # global template. so that one can change the text
   GB   => '%.2f GB',
   MB   => '%.2f MB',
   KB   => '%.2f KB',
   BY   => '%s bytes',
   TEXT => '<WIDTH>x<HEIGHT> <MIME>',
);

my %KNOWN = map {$_, $_} ALL_MIME;
   $KNOWN{'jpg'} = 'jpeg';
   $KNOWN{'jpe'} = 'jpeg';

my %IS_GD_FONT = map {lc($_), $_ } qw(Small Large MediumBold Tiny Giant);
my %SIZE; # see _size()

GD::Image->trueColor(1) if GD::Image->can('trueColor');

sub new {
   my $class = shift;
   my %o     = scalar(@_) % 2 ? () : (@_);
   my $self  = {
      DIMENSION   => [0, 0], # Thumbnail dimension
      GD_FONT     => 'Tiny', # info text color
      OVERLAY     => 0,      # bool: overlay info strips?
      STRIP_COLOR => BLACK,
      INFO_COLOR  => WHITE,
      SQUARE      => 0,      # bool: make square thumb?
      FRAME_COLOR => BLACK,
      FRAME       => 0,      # bool: add frame?
      FORCE_MIME  => '',     # force output type?
      MIME        => '',
   };
   $self->{FRAME}      = $o{frame}  ? 1          : 0;
   $self->{SQUARE}     = $o{square} ? $o{square} : 0;
   $self->{OVERLAY}    = ($o{overlay}   || $self->{SQUARE}) ? 1 : 0;
   $self->{FORCE_MIME} = $o{force_mime} || '';
   if ($o{font} and my $font = $IS_GD_FONT{ lc( $o{font} ) }) {
      $self->{GD_FONT} = $font;
   }
   my $color;
   for my $id (qw[STRIP_COLOR INFO_COLOR FRAME_COLOR]) {
      if (my $color = $o{ lc $id }) {
         if(ref $color && ref $color eq 'ARRAY' && $#{$color} == 2) {
            $self->{$id} = $color;
         }
      }
   }
   bless  $self, $class;
   return $self;
}

sub create {
   my $self  = shift;
   my $image = shift || die "image parameter is missing!";
   my $max   = shift || 50;
   my $info  = shift ||  0;
   my $info2 = $info && $info == 2;
   my $type;

   if(length($image) <= 300 && $image =~ m{\.(png|gif|jpg|jpe|jpeg)}i) {
      $type = $KNOWN{lc $1};
      if($type eq 'gif' && !GIF_OK) {
         # code will probably die at $gd assignment below
         warn "GIF format is not supported by this version ($GD::VERSION) of GD";
         $type = DEFAULT_MIME;
      }
   }

   $type         = DEFAULT_MIME unless $type;
   my $o         = $self->{OVERLAY};
   my $size      = $info2 ? $self->_image_size($image) : 0;
   my $gd        = GD::Image->new($image) or die "GD::Image->new error: $!";
   my($w, $h)    = $gd->getBounds         or die "getBounds() failed: $!";
   my $ratio     = $max =~ m{(\d+)(?:\s+|)%} ? $1
                 :                             sprintf('%.1f', $max * 100 / $w)
                 ;

   die "Can not determine thumbnail ratio" if ! $ratio;

   my $square    = $self->{SQUARE} || 0;
   my $crop      = $square && lc($square) eq 'crop';

   my $x         = sprintf '%.0f', $w * $ratio / 100;
   my $def_y     = sprintf '%.0f', $h * $ratio / 100;
   my $y         = $square ? $x : $def_y;
   my $yy        = 0; # yy & yy2 has the same value
   my $yy2       = 0;

  ($info , $yy ) = $self->_strip($self->_text($w,$h,$type), $x) if $info;
  ($info2, $yy2) = $self->_strip($self->_size($size)      , $x) if $info2;

   my $ty        = $yy + $yy2;
   my $new_y     = $o ? $y : $y + $ty;
   my $thumb     = GD::Image->new($x, $new_y);

   # RT#49353 | Alexander Vonk: prefill Thumbnail with strip color, as promised
   $thumb->fill( 0, 0, $thumb->colorAllocate( @{ $self->{STRIP_COLOR} } ) );

   $thumb->colorAllocate(@{ +WHITE }) if ! $info;

   my $iy = 0;
   if ($info) {
      $iy = $o     ? $y - $yy
          : $info2 ? $y + $yy + BUFFER/2
          :          $y       + BUFFER/2
          ;
   }

   my @strips;
   push @strips, [$info , 0, $iy, 0, 0, $x, $y , 100] if $info;
   push @strips, [$info2, 0,   0, 0, 0, $x, $yy, 100] if $info2;

   my $dx     = 0;
   my $dy     = $yy2 || 0;
   my $xsmall = $x < $def_y;

   if ( $square ) {
      my $rx = ($w < $h) ? $w/$h :     1;
      my $ry = ($w < $h) ? 1     : $h/$w;
      my $d;
      if($xsmall) { $d = $x * $rx; $dx = ($x - $d) / 2; $x = $d; }
      else        { $d = $y * $ry; $dy = ($y - $d) / 2; $y = $d; }
   }

   if (not $square or $square && $xsmall) {
      # does not work if square & y_is_small, 
      # since we may have info bars which eat y space
      $ty = 0; # TODO. test this more and remove from below
      $y = $y - $ty - BUFFER/2 if $o;
   }

   if ( $crop ) {
      if ( $xsmall ) {
         my $diff = ($y - $x) / $x;
         $x += $x * $diff;
         $y += $y * $diff;
         $dy = -$dx * (2 - $x / $y)**2;
         $dx = 0;
      }
      else {
         my $diff = ($x - $y) / $y;
         $x += $x * $diff;
         $y += $y * $diff;
         $dx = -$dy * (2-$y/$x)**2;
         $dy = 0;
      }
   }

   my $resize = $thumb->can('copyResampled') ? 'copyResampled' : 'copyResized';

   $thumb->$resize($gd, $dx, $dy, 0, 0, $x, $y, $w, $h);
   $thumb->copyMerge(@{$_}) for @strips;

   my @dim = $thumb->getBounds;

   $self->{DIMENSION}[IMG_X] = $dim[IMG_X];
   $self->{DIMENSION}[IMG_Y] = $dim[IMG_Y];

   if ($self->{FRAME}) {
      my $color = $thumb->colorAllocate(@{ $self->{FRAME_COLOR} });
      $thumb->rectangle(0, 0, $dim[IMG_X]-1, $dim[IMG_Y]-1, $color);
   }

   my $mime = $self->_force_mime($thumb);
      $type = $mime if $mime;
   $self->{MIME} = $type;
   my @iopt;
   push @iopt, 100 if $type eq 'jpeg';
   push @iopt,   9 if $type eq 'png';
   return $thumb->$type(@iopt);
}

sub width  { shift->{DIMENSION}[IMG_X] }
sub height { shift->{DIMENSION}[IMG_Y] }
sub mime   { shift->{MIME}             }

sub _force_mime {
   my $self = shift;
   my $gd   = shift || return;
   return unless $self->{FORCE_MIME};
   my %mime = map {$_, $_} ALL_MIME;
   my $type = $mime{ lc $self->{FORCE_MIME} } || return;
   return unless $gd->can($type);
   return $type;
}

sub _text {
   my $self = shift;
   my($w, $h, $type) = @_;
   $type = uc $type;
   my $tmp = $TMP{TEXT} || die "TEXT template is not set";
   $tmp =~ s{<WIDTH>}{$w}xmsg;
   $tmp =~ s{<HEIGHT>}{$h}xmsg;
   $tmp =~ s{<MIME>}{$type}xmsg;
   return $tmp;
}

sub _image_size {
   my $self     = shift;
   my $image    = shift;
   my $img_size = 0;
   # don't do that at home. very dangerous :p
   if(defined &GD::Image::_image_type && GD::Image::_image_type($image)) {
      $img_size = length($image);
   } elsif (defined(fileno $image)) {
      local $/;
      binmode $image;
      use bytes;
      $img_size = length <$image>;
   } else {
      if(-e $image && !-d _) {
         $img_size = (stat $image)[7];
      }
   }
   return $img_size;
}

sub _strip {
   my $self   = shift;
   my $string = shift;
   my $x      = shift;
   my $type   = $self->{GD_FONT};
   my $font   = GD::Font->$type();
   my $sw     = $font->width * length($string);
   my $sh     = $font->height;
   warn "Thumbnail width ($x) is too small for an info text" if $x < $sw;
   my $info   = GD::Image->new($x, $sh+BUFFER);
   my $color = $info->colorAllocate(@{ $self->{STRIP_COLOR} });
   $info->filledRectangle(0,0,$x,$sh+BUFFER,$color);
   $info->string($font, ($x - $sw)/2, 0, $string, $info->colorAllocate(@{ $self->{INFO_COLOR} }));
   return $info, $sh + BUFFER;
}

sub _size {
   my $self = shift;
   my $size = shift || return "0 byte";
   unless (%SIZE) {
      eval q~
         %SIZE = (
            GB => 1024 * 1024 * 1024,
            MB => 1024 * 1024,
            KB => 1024,
         );
      ~;
   }
   return sprintf($TMP{GB}, $size / $SIZE{GB}) if($size >= $SIZE{GB});
   return sprintf($TMP{MB}, $size / $SIZE{MB}) if($size >= $SIZE{MB});
   return sprintf($TMP{KB}, $size / $SIZE{KB}) if($size >= $SIZE{KB});
   return sprintf($TMP{BY}, $size);
}

1;

__END__

=head1 NAME

GD::Thumbnail - Thumbnail maker for GD

=head1 SYNOPSIS

   use GD::Thumbnail;
   my $thumb = GD::Thumbnail->new;
   my $raw   = $thumb->create('test.jpg', 80, 2);
   my $mime  = $thumb->mime;
   warn sprintf "Dimension: %sx%s\n", $thumb->width, $thumb->height;
   open    IMG, ">thumb.$mime" or die "Error: $!";
   binmode IMG;
   print   IMG $raw;
   close   IMG;

or

   use CGI qw(:standard);
   use GD::Thumbnail;
   my $thumb = GD::Thumbnail->new;
   my $raw   = $thumb->create('test.jpg', 80, 2);
   my $mime  = $thumb->mime;
   binmode STDOUT;
   print header(-type => "image/$mime");
   print $raw;

=head1 DESCRIPTION

This document describes version C<1.35> of C<GD::Thumbnail>
released on C<4 September 2009>.

This is a thumbnail maker. Thumbnails are smaller versions of the
original image/graphic/picture and are used for preview purposes,
where bigger images can take a long time to load. They are also 
used in image galleries to preview a lot of images at a time.

This module also has the capability to add information strips
about the original image. Original image's size (in bytes)
and resolution & mime type can be added to the thumbnail's
upper and lower parts. This feature can be useful for web
software (image galleries or forums).

This is a I<Yet Another> type of module. There are several 
other thumbnail modules on CPAN, but they simply don't have 
the features I need, so this module is written to increase
the thumbnail generator population on CPAN.

The module can raise an exception if something goes wrong.
So, you may have to use an C<eval block> to catch them. 

=head1 METHODS

All color parameters must be passed as a three element 
array reference:

   $color = [$RED, $GREEN, $BLUE];
   $black = [   0,      0,     0];

=head2 new

Object constructor. Accepts arguments in C<< key => value >> 
format.

   my $thumb = GD::Thumbnail->new(%args);

=head3 overlay

If you want information strips (see L</create>), but you don't
want to get a longer image, set this to a true value, and
the information strips will not affect the image height
(but the actual thumbnail image will be smaller).

=head3 font

Alters the information text font. You can set this to  C<Small>, 
C<Large>, C<MediumBold>, C<Tiny> or C<Giant> (all are case-insensitive). 
Default value is C<Tiny>, which is best for smaller images. If you 
want to use bigger thumbnails, you can alter the used font via this 
argument. It may also be useful for adding size & resolution 
information to existing images. But beware that GD output size may 
be smaller than the actual image and image quality may also differ.

=head3 square

You'll get a square thumbnail, if this is set to true. If the 
original image is not a square, the empty parts will be filled 
with blank (color is the same as C<strip_color>) instead of
streching the image in C<x> or C<y> dimension or clipping
it. If, however, C<square> is set to C<crop>, you'll get a
cropped square thumbnail.

Beware that enabling this option will also B<auto-enable> the 
C<overlay> option, since it is needed for a square image.

=head3 frame

If set to true, a 1x1 pixel border will be added to the final
image.

=head3 frame_color

Controls the C<frame> color. Default is black.

=head3 strip_color

Sets the info strip background color. Default is black.
You must pass it as a three element arayref containing
the red, green, blue values:

   $thumb = GD::Thumbnail->new(
      strip_color => [255, 0, 0]
   );

=head3 info_color

Sets the info strip text color. Default is white.
You must pass it as a three element arayref containing
the red, green, blue values:

   $thumb = GD::Thumbnail->new(
      info_color => [255, 255, 255]
   );

=head3 force_mime

You can alter the thumbnail mime with this parameter. 
Can be set to: C<png>, C<jpeg> or C<gif>.

=head2 create

Creates the thumbnail and returns the raw image data.
C<create()> accepts three arguments:

   my $raw = $thumb->create($image    , $max, $info);
   my $raw = $thumb->create('test.jpg',   80, 1    );

=head3 image

Can be a file path, a filehandle or raw binary data.

=head3 max

Defines the maximum width of the thumbnail either in pixels or 
percentage. You'll get a warning, if C<info> parameter is set 
and your C<max> value is to small to fit an info text.

=head3 info

If info parameter is not set, or it has a false value, you'll get
a normal thumbnail image:

    _____________
   | ........... |
   | ........... |
   | ...IMAGE... |
   | ........... |
   | ........... |
   |_____________|

If you set it to C<1>, original image's dimensions and mime will be
added below the thumbnail:

    _____________
   | ........... |
   | ........... |
   | ...IMAGE... |
   | ........... |
   | ........... |
   |_____________|
   | 20x20 JPEG  |
    -------------

If you set it to C<2>, the byte size of the image will be added
to the top of the thumbnail:

    _____________
   |    25 KB    |
   |-------------|
   | ........... |
   | ........... |
   | ...IMAGE... |
   | ........... |
   | ........... |
   |_____________|
   | 20x20 JPEG  |
    -------------

As you can see from the schemas above, with the default options,
thumbnail image dimension is constant when adding information strips 
(ie: strips don't overlay, but attached to upper and lower parts of 
thumbnail). Each info strip increases thumbnail height by 8 pixels 
(if the default tiny gd font C<Tiny> is used).

But see the C<overlay> and C<square> options in L</new> to alter this
behaviour. You may also need to increase C<max> value if C<square> is
enabled.

=head2 mime

Returns the thumbnail mime. 
Must be called after L</create>.

=head2 width

Returns the thumbnail width in pixels. 
Must be called after L</create>.

=head2 height

Returns the thumbnail height in pixels. 
Must be called after L</create>.

=head1 WARNINGS

You may get a warning, if there is something odd.

=over 4

=item *

B<I<"GIF format is not supported by this version (%f) of GD">>

You have an old version of GD and your original image is a GIF
image. Also, the code may die after this warning.

=item *

B<I<"Thumbnail width (%d) is too small for an info text">>

C<max> argument to C<create> is too small to fit information.
Either disable C<info> parameter or increase C<max> value.

=back

=head1 EXAMPLES

You can reverse the strip and info colors and then add a frame
to the thumbnail to create a picture frame effect:

   my $thumb = GD::Thumbnail->new(
      strip_color => [255, 255, 255],
      info_color  => [  0,   0,   0],
      square      => 1,
      frame       => 1,
   );
   my $raw = $thumb->create('test.jpg', 100, 2);

If you have a set of images with the same dimensions, 
you may use a percentage instead of a constant value:

   my $raw = $thumb->create('test.jpg', '10%', 2);

Resulting thumbnail will be 90% smaller (x-y dimensions)
than the original image.

=head1 CAVEATS

Supported image types are limited with GD types, which include
png, jpeg and gif and some others. See L<GD> for more information.
Usage of any other image type will be resulted with a fatal
error.

=head1 SEE ALSO

L<GD>, L<Image::Thumbnail>, L<GD::Image::Thumbnail>, L<Image::GD::Thumbnail>
L<Image::Magick::Thumbnail>, L<Image::Magick::Thumbnail::Fixed>.

=head1 AUTHOR

Burak Gursoy <burak@cpan.org>.

=head1 COPYRIGHT

Copyright 2006 - 2009 Burak Gursoy. All rights reserved.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify 
it under the same terms as Perl itself, either Perl version 5.10.0 or, 
at your option, any later version of Perl 5 you may have available.

=cut
