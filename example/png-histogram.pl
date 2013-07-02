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
	'trim=s' => \$opt{trim},
	'help' => sub {
		print "Usage: $0 [--base <1+small o> --floor <nnn>] pic.png\n";
		print "Read numbers from STDIN, output histogram\n";
		print "Number of sections = n (default 20)";
		exit 2;
	},
);

# Where to write the pic
my $out = shift;

defined $out or die "No output file given";
my $fd;
if ($out eq '-') {
	$fd = \*STDOUT;
} else {
	open ($fd, ">", $out) or die "Failed to open $out: $!";
};

my $stat = Statistics::Descriptive::LogScale->new(
	base => $opt{base}, zero_thresh => $opt{zero});

while (<STDIN>) {
	$stat->add_data(/(-?\d+(?:\.\d*)?)/g);
};

my ($width, $height) = @opt{"width", "height"};

my $start = $stat->percentile($opt{trim}) // $stat->_lower($stat->min);
my $end = $stat->percentile(100-$opt{trim});
my $step = ($end - $start) / $width;
my @index = map { $start + $step * $_ } 0..$width;

# warn "Working on $start..$end: @index\n";

# preprocess histogram
my $hist_hash = $stat->frequency_distribution_ref(\@index);

# warn "hist = ".join " ", map { sprintf "%0.2f:%0.1f", $_, $hist_hash->{$_} }
#	sort { $a <=> $b } keys %$hist_hash;

my @hist = map { $hist_hash->{$_} } sort { $a <=> $b } keys %$hist_hash;
shift @hist;

my $trimmer = Statistics::Descriptive::LogScale->new;
$trimmer->add_data(@hist);

my $max = $trimmer->percentile(99)/0.7;
$_ /= $max for @hist;

# warn "hist = @hist\n";
# draw!
my $gd = GD::Simple->new($width, $height);
$gd->bgcolor('white');
$gd->clear;

my $i=0;
foreach (@hist) {
	$gd->fgcolor( $_ > 1 ? 'red' : 'orange');
	$gd->line($i, $height, $i, $height*(1-$_));
	$i++;
};

print $fd $gd->png;

