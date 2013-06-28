#!/usr/bin/perl -w

use strict;
use Test::More tests => 7;

use Statistics::Descriptive::LogScale;

my $stat = Statistics::Descriptive::LogScale->new;

$stat->add_data(1) for 1..5;
is ($stat->mode, 1, "mode(1)");

$stat->clear;
$stat->add_data(0) for 1..5;
is ($stat->mode, 0, "mode(0)");

$stat->clear;
$stat->add_data(1,0) for 1..5;
is ($stat->mode, 0, "mode(0,1)");
my $density = $stat->_probability_density;
is ($density->[0], $density->[1], "uniform density");

note "Add up two variables, i.e. triangle => mode == mean";
$stat->clear;
foreach my $i (0..10) {
	foreach my $j (0..10) {
		$stat->add_data($i + $j);
	};
};
is ($stat->count, 121, "self-test: count == 121");
note "expected mode = 10, real mode = " . $stat->mode
	. ", mean = ", $stat->mean;
my @dens_show = map { sprintf "%0.2f", $_ } @{ $stat->_probability_density };
note "probability = @dens_show";
cmp_ok( $stat->mode, "<", $stat->mean+1, "mode ~ mean");
cmp_ok( $stat->mode, ">", $stat->mean-1, "mode ~ mean");

# TODO more tests!
