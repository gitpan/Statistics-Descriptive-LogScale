#!/usr/bin/perl -w

use strict;
use GD::Simple;
use Getopt::Long;

# always prefer local version of module
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Statistics::Descriptive::LogScale;

my %opt = (width => 600, height => 200, trim => 0);

# Don't require module just in case
GetOptions (
	'base=s' => \$opt{base},
	'floor=s' => \$opt{zero},
	'width=s' => \$opt{width},
	'height=s' => \$opt{height},
	'ltrim=s' => \$opt{ltrim},
	'utrim=s' => \$opt{utrim},
	'min=s' => \$opt{min},
	'max=s' => \$opt{max},
	'help' => \&usage,
) or usage();

sub usage {
	print STDERR <<"EOF";
Usage: $0 [options] pic.png
Read numbers from STDIN, output histogram as a png file.
Options may include:
  --width <nnn>
  --height <nnn> - size of picture
  --base <1 + small o> - relative precision of underlying engine
  --floor <positive number> - count all below this as zero
  --ltrim <0..100> - cut that % off from the left
  --utrim <0..100> - cut that % off from the right
  --min <xxx> - strip data below this value
  --max <xxx> - strip data above this value
  --help - this message
EOF
	exit 2;
};

# Where to write the pic
my $out = shift;

defined $out or die "No output file given";
my $fd;
if ($out eq '-') {
	$fd = \*STDOUT;
} else {
	open ($fd, ">", $out) or die "Failed to open $out: $!";
};

# sane default for precision = 1 pixel at right/left side
$opt{base} = 1+1/$opt{width} unless defined $opt{base};

my $stat = Statistics::Descriptive::LogScale->new(
	base => $opt{base}, zero_thresh => $opt{zero});

while (<STDIN>) {
	$stat->add_data(/(-?\d+(?:\.\d*)?)/g);
};

my ($width, $height) = @opt{"width", "height"};

my $hist = $stat->histogram( %opt, count => $width);

my $trimmer = Statistics::Descriptive::LogScale->new;
$trimmer->add_data(map { $_->[0]} @$hist);

my $max_val = $trimmer->percentile(99)/0.7;
$_->[0] /= $max_val for @$hist;

# warn "hist = @hist\n";
# draw!
my $gd = GD::Simple->new($width, $height);
$gd->bgcolor('white');
$gd->clear;

my $scale = 10;

foreach (1 .. ($scale-1)) {
	$gd->fgcolor( 'blue' );
	$gd->line( $width * ($_/$scale), 0, $width * ($_/$scale), $height );
};

my $i=0;
foreach (@$hist) {
	$gd->fgcolor( $_->[0] > 1 ? 'red' : 'orange');
	$gd->line($i, $height, $i, $height*(1-$_->[0]));
	$i++;
};

my $min = $hist->[0][1];
my $max = $hist->[-1][2];
my $range = $max - $min;

foreach (0 .. ($scale-1)) {
	$gd->fgcolor( 'blue' );
	$gd->moveTo( $width * ($_/$scale) + 2, 10 );
	$gd->fontsize( 8 );
	$gd->font( "Times" );
	$gd->string( sprintf("%0.1f", $min + $range*$_/$scale) );
};

print $fd $gd->png;
