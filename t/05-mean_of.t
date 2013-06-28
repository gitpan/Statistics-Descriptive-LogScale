#!/usr/bin/perl -w

use strict;
use Test::More tests => 7;
use Data::Dumper;

use Statistics::Descriptive::LogScale;

my $PRECISION = 10**(1/10) - 1;

my $stat =  Statistics::Descriptive::LogScale->new(
	floor => 0.01, base => 1 + $PRECISION);

my @data;
foreach (1..100) {
	push @data, (-$_..$_);
};

$stat->add_data(@data);

near_zero ($stat->mean_of(sub { $_[0]}, -exp 3, exp 3),
	"mean of odd function over symmetric interval == 0");
near_zero ($stat->mean_of(sub { $_[0]*$_[0]*$_[0]}, -exp 3, exp 3),
	"mean of LARGE odd function over symmetric interval == 0");
cmp_ok ($stat->mean_of(sub { $_[0]}, 0, exp 3), ">", 0,
	"biased to the right => positive");

cmp_mean( sub { $_[0]**3 } , 0, 30, "cube 0..30" );
cmp_mean( sub { $_[0]**4 } , 0, 30, "cube 0..30" );
cmp_mean( sub { 1 } , 0, 30, "cube 0..30" );

near_zero ($stat->sum_of(sub{ 1 }, undef, 0)
	-  $stat->sum_of(sub{ 1 }, 0, undef), "integrate up to zero = ok");

#######
my $total_off;
END { $total_off ||= 0; note "Total off by $total_off" };
sub about {
	my ($got, $exp, $msg) = @_;
	my $off = eval {
		2 * abs ( $got - $exp ) / (abs($got) + abs($exp) )
	} || 0;
	$total_off += $off;
	my $ret = ok ( $off < $PRECISION , $msg . " (exp = $exp, got = $got)");
	return $ret;
};

sub near_zero {
	my ($number, $msg) = @_;
	return ok (abs($number) < 1E-6, "$msg ($number ~~ 0)");
};

sub naive_mean_of {
	my ($data, $code, $min, $max) = @_;
	$min = "-inf" unless defined $min;
	$max = "-max" unless defined $max;
	my $sum = 0;
	my $count = 0;
	foreach (@$data) {
		$_ >= $min and $_ <= $max or next;
		$sum += $code->($_);
		$count++;
	};
	return $count ? $sum / $count : 0;
};

sub cmp_mean {
	my ($code, $min, $max, $msg) = @_;
	return about (
		$stat->mean_of($code, $min, $max),
		naive_mean_of(\@data, $code, $min, $max),
		$msg
	);
};
