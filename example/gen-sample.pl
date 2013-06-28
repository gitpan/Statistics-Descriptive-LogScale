#!/usr/bin/perl -w

# This is NOT an example.
# It is a script for generating random samples of needed shape
# See $0 --help

use strict;

# Known distributions and arg counts
my %dist;
for (qw(normal bernoulli uniform const)) {
	no strict 'refs';
	$dist{$_} = \&$_;
};
$dist{exp} = \&exponential; # won't name function exp!
my %nargs = (
	normal => 2,
	uniform => 2,
);

# Usage
if (!@ARGV or grep { $_ eq '--help' } @ARGV) {
	my @dist = sort keys %dist;
	print "Usage: $0 <n><distr>=<param>,<param2>,... ...\n";
	print "Output n random numbers distributed as <distr>(params)\n";
	print "Currently supported: @dist\n";
	exit 1;
};

# Analyze arguments
my $n;
my @todo;
foreach (@ARGV) {
	if (!$n) {
		s/^(\d*)\s*// or die "Usage: $0 <n> <distr=param,param>";
		$n = $1 || 1;
	};
	/\S/ or next;

	/(\w+)=(.*)/ or die "Usage: $0 <n> <distr=param,param>";
	my $name = $1;
	my @arg = split /,/, $2;

	$dist{$name} or die "Unknown distribution $name";
	(($nargs{$name} || 1) <= @arg)
		or die "Distribution $name wrong param '@arg'";
	push @todo, [ $n, $name, @arg ];
	$n = 0;
};

# generate sample
foreach (@todo) {
	my ($n, $name, @arg) = @$_;
	print $dist{$name}->(@arg), "\n" for 1..$n;
};

#########

# TODO could cache one more point, see Box-Muller transform
sub normal {
	return $_[0] + $_[1] * sin(2*3.1415926539*rand()) * sqrt(-2*log(rand));
};

# toss coin
sub bernoulli {
	return rand() < $_[0] ? 1 : 0;
};

sub const {
	return $_[0];
};

sub uniform {
	return $_[0] + rand() * ($_[1] - $_[0]);
};

sub exponential {
	return ($_[1] || 0) - $_[0] * log rand();
};
