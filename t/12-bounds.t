#!/usr/bin/perl -w

use strict;
use Test::More tests => 8;

use Statistics::Descriptive::LogScale;

my $stat = Statistics::Descriptive::LogScale->new;

$stat->add_data( 1..10 );

my @bound;

@bound = $stat->find_boundaries;
is (scalar @bound, 2, "2 values");
cmp_ok( $bound[0], "<=", 1, "bound < sample" );
cmp_ok( $bound[1], ">=", 10, "bound > sample" );

@bound = $stat->find_boundaries( ltrim => 11, utrim => 11 );
is (scalar @bound, 2, "2 values");
cmp_ok( $bound[0], "<=", 2, "bound < sample" );
cmp_ok( $bound[1], ">=", 9, "bound > sample" );
cmp_ok( $bound[0], ">=", 1, "bound > outliers" );
cmp_ok( $bound[1], "<=", 10, "bound < outliers" );


