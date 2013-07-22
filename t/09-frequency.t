#!/usr/bin/perl -w

use strict;
use Test::More tests => 9;

use Statistics::Descriptive::LogScale;

my $stat = Statistics::Descriptive::LogScale->new;
# let's do some ad-hoc statistics =)
my ($n, $sum, $sum2);

$stat->add_data(1..10);

note "Histogram test - 5 intervals";
my $hist = $stat->frequency_distribution_ref(5);
note explain $hist;

($n, $sum, $sum2) = (0,0,0);
for (values %$hist) {
	$n++;
	$sum  += $_;
	$sum2 += $_*$_;
};
is ($n, 5, "Number of intervals as expected");
is ($sum, $stat->count, "histogram sum == count");
my $std_dev = sqrt( $sum2 / $n - ($sum / $n)**2 );
cmp_ok( $std_dev, "<", 0.1, "Histogram is level");

# check newer histogram interface
my $hist2 = $stat->histogram(count => 5);
my %hist2pp = map { $_->[2] => $_->[0] } @$hist2;
is_deeply ( \%hist2pp, $hist, "histogram == freq_distr_ref");


note "arbitrary cut: (-inf, 3, 6, 9, 12)";
$hist  = $stat->frequency_distribution_ref([3, 6, 9, 12]);
note explain $stat->{data};
note explain $hist;

($n, $sum, $sum2) = (0,0,0);
for (values %$hist) {
	$n++;
	$sum  += $_;
	$sum2 += $_*$_;
};

is ($n, 4, "Number of intervals as expected");
is ($sum, $stat->count, "histogram sum == count");

# check newer histogram interface
$hist2 = $stat->histogram(index => [ -9**9, 3, 6, 9, 12 ]);
%hist2pp = map { $_->[2] => $_->[0] } @$hist2;
is_deeply ( \%hist2pp, $hist, "histogram == freq_distr_ref");

$hist2 = $stat->histogram( count =>4, min => 0, max => 12 );
note explain $hist2;
%hist2pp = map { $_->[2] => $_->[0] } @$hist2;
is_deeply ( \%hist2pp, $hist, "histogram == freq_distr_ref");

# check hist2 chaining
my @upper = map { $_->[2] } @$hist2;
my @lower = map { $_->[1] } @$hist2;
shift @lower;
pop @upper;
is_deeply( \@upper, \@lower, "upper == lower");

