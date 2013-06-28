#!/usr/bin/perl -w

# This is a simple script that reads numbers from STDIN
# and prints out a summary using both
# Statistics::Descriptive{::LogScale, ::Full}

use strict;
use Statistics::Descriptive;
# always prefer local version of module
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Statistics::Descriptive::LogScale;

my $base;
my $floor;

# Don't require module just in case
if ( eval { require Getopt::Long; 1; } ) {
	Getopt::Long->import;
	GetOptions (
		'base=s' => \$base,
		'floor=s' => \$floor,
		'help' => sub {
			print "Usage: $0 [--base <1+small o> --floor <nnn>]\n";
			print "Read numbers from STDIN, output stat summary\n";
			exit 2;
		},
	);
} else {
	@ARGV and die "Options given, but no Getopt::Long support";
};

my $stat_l = Statistics::Descriptive::LogScale->new(
	base => $base, zero_thresh => $floor);
my $stat_f = Statistics::Descriptive::Full->new();

while (<STDIN>) {
	my @num = /(-?\d+(?:\.\d*)?)/g;
	$stat_l->add_data(@num);
	$stat_f->add_data(@num);
#	warn "count = ".$stat_f->count;
};

print_result();

sub print_result {
	printf "%20s: %20s %20s\n", "method", "LogScale", "Full";
	for (qw(count mean standard_deviation skewness kurtosis mode)) {
		print side_by_side($_);
	};
	for (0.5, 1, 5, 10, 25, 50, 75, 90, 95, 99, 99.5) {
		print side_by_side("percentile", $_);
	};
};

sub side_by_side {
	my ($method, @arg) = @_;
	my $label = defined $arg[0] ? "$method(@arg)" : $method;

	my $val_l = $stat_l->$method(@arg) // "-inf";
	my $val_f = $stat_f->$method(@arg) // "-inf";

	sprintf "%20s: %20.3f %20.3f\n", $label, $val_l, $val_f;
};
