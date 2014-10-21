#!/usr/bin/perl -w

use strict;
use Test::More;
use Data::Dumper;

use Statistics::Descriptive::LogScale;

my $PRECISION = 10**(1/10) - 1;

my @samples = ([1..100], [-100..-1], [-10..12],
	[map { $_ / 10 } -15..35 ]);
plan tests => 18 * @samples;

foreach (@samples) {
	my @data = @$_;
	note "### Testing @data...";
	my $stat =  Statistics::Descriptive::LogScale->new(
		floor => 1, base => 1 + $PRECISION);
	$stat->add_data(@data);
	note ( Dumper( $stat ));

	is ($stat->percentile(0), undef, "0th % = -inf");
	about ($stat->percentile(100/@data), $data[0],
		"first finite centile = 1st val");
	about ($stat->percentile(50), $data[@data/2], "Median = middle");
	about ($stat->percentile(100), $data[-1], "100th centile = last value");
	is ($stat->max, $stat->percentile(100),
		"max value = 100th centile (exact)");
	about ($stat->min, $data[0], "min = data[0]");
	about ($stat->sample_range, $data[-1] - $data[0], "sample range");

	about ($stat->central_moment(2), $stat->variance, "2nd moment = variance");
	about ($stat->std_moment(2), 1, "2nd normalized = 1");

	# ad-hoc basic statistics
	my $n;  $n  += 1     for @data;
	my $s;  $s  += $_    for @data;
	my $s2; $s2 += $_*$_ for @data;

	my $mean = $s / $n;
	my $std_dev = sqrt( $s2 / $n - $mean*$mean );

	is ($stat->count, $n, "count OK");
	about ($stat->sum, $s, "sum");
	about ($stat->sumsq, $s2, "sumsq");
	about ($stat->mean, $mean, "mean");
	about ($stat->std_dev, $std_dev, "std_dev");

	# mean_of advanced integral properties
	about ($stat->mean_of(sub{1}), 1, "Expectation of 1 == 1");
	about ($stat->mean_of(sub{$_[0]}), $mean, "Expectation of x == mean");
	about ($stat->mean_of(sub{$_[0]*$_[0]}), $s2/$n, "Expectation of x**2");
	about ($stat->mean_of(sub{($_[0]-$mean)**2}), $std_dev**2, "Yet another sigma");
};

#######
my $total_off;
END { note "Total off by $total_off" };
sub about {
	my ($got, $exp, $msg) = @_;
	my $off = eval {
		2 * abs ( $got - $exp ) / (abs($got) + abs($exp) )
	} || 0;
	$total_off += $off;
	my $ret = ok ( $off < $PRECISION , $msg . " (exp = $exp, got = $got)");
	return $ret;
};
