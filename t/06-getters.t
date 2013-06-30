#!/usr/bin/perl -w

use strict;
use Test::More tests => 4;
use Test::Number::Delta within => 1e-12;

use Statistics::Descriptive::LogScale;

my $stat = Statistics::Descriptive::LogScale->new(
	zero_thresh => 0.125, base => 1.01
);

cmp_ok ($stat->zero_threshold, "<=", 0.125, "floor");
cmp_ok ($stat->zero_threshold, ">", 0, "floor");
delta_ok ($stat->bucket_width, 0.01, "Bucket width as expected");

$stat->add_data($stat->zero_threshold / 2);
$stat->add_data(-$stat->zero_threshold / 2);
my $raw = $stat->get_data_hash;
is_deeply ($raw, { 0 => 2 }, "2 subzero values => 0,0")
	or diag "Returned raw data = ".explain($raw);

