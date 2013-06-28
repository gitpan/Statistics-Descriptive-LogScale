use 5.006;
use strict;
use warnings;

package Statistics::Descriptive::LogScale;

=head1 NAME

Statistics::Descriptive::LogScale - approximate statistical distribution class
using logarithmic buckets to store data.

=head1 VERSION

Version 0.05

=cut

our $VERSION = 0.0503;

=head1 SYNOPSIS

    use Statistics::Descriptive::LogScale;
    my $stat = Statistics::Descriptive::LogScale->new ();

    while(<>) {
        chomp;
        $stat->add_data($_);
    };

    # This can also be done in O(1) memory, precisely
    printf "Mean: %f +- %f\n", $stat->mean, $stat->standard_deviation;
    # This requires storing actual data, or approximating
    printf "Median: %f\n", $stat->median;

=head1 DESCRIPTION

This module aims at providing some advanced statistical functions without
storing all data in memory, at the cost of some precision loss.

Data is represented by a set of logarithmic buckets only storing counters.
Data with absolute value below certain threshold ("floor") is stored in a
special zero counter.
All operations are performed on the buckets, introducing relative error
which does not however exceed the buckets' width ("base").

=head1 METHODS

=cut

########################################################################
#  == HOW IT WORKS ==
#  Buckets are stored in a hash: { $value => $count, ... }
#  {base} is bucket width, {logbase} == log {base} (cache)
#  {zero_thresh} is absolute value below which everything is zero
#  {floor} is lower bound of bucket whose center is 1. {logfloor} = log {floor}
#  Nearly all meaningful subs have to scan all the buckets, which is bad,
#     but anyway better than scanning full sample.

use Carp;
use POSIX qw(floor);

use fields qw(
	data
	base logbase floor zero_thresh logfloor
	count
	cache
);

=head2 new( %options )

%options may include:

=over

=item * base - ratio of adjacent buckets. Default is 10^(1/48), which gives
5% precision and exact decimal powers.

=item * zero_thresh - absolute value threshold below which everything is
considered zero.

=back

=cut

sub new {
	my $class = shift;
	my %opt = @_;

	# Sane default: about 5% precision + exact powers of 10
	$opt{base} ||= 10**(1/48);
	$opt{base} > 1 or croak __PACKAGE__.": new(): base must be >1";
	$opt{zero_thresh} ||= 0;
	$opt{zero_thresh} >= 0
		or croak __PACKAGE__.": new(): zero_thresh must be >= 0";

	my $self = fields::new($class);

	$self->{base} = $opt{base};
	$self->{logbase} = log $opt{base};
	# floor = lower limit of bucket whose center is 1.
	$self->{floor} = 2/(1+$opt{base});
	$self->{logfloor} = log $self->{floor};

	# bootstrap zero_thresh - make it fit bin edge
	$self->{zero_thresh} = 0;
	$self->{zero_thresh} = $self->_lower($opt{zero_thresh});

	$self->clear;
	return $self;
};

=head2 bucket_width()

Get bucket width (relative to center of bucket). Percentiles are off
by no more than half of this.

=cut

sub bucket_width {
	my $self = shift;
	return $self->{base} - 1;
};

=head2 zero_threshold()

Get zero threshold. Numbers with absolute value below this are considered
zeroes.

=cut

sub zero_threshold {
	my $self = shift;
	return $self->{zero_thresh};
};

=head2 clear()

Destroy all stored data.

=cut

sub clear {
	my $self = shift;
	$self->{data} = {};
	$self->{count} = 0;
	delete $self->{cache};
	return $self;
};

=head2 add_data( @data )

Add numbers to the data pool.

=cut

sub add_data {
	my $self = shift;
	return unless @_;

	delete $self->{cache};
	foreach (@_) {
		$self->{count}++;
		$self->{data}{ $self->_round($_) }++;
	};
};

=head2 add_data_hash ( { value => count, ... } )

Add values with counts.

=cut

sub add_data_hash {
	my $self = shift;
	my $hash = shift;

	delete $self->{cache};
	foreach (keys %$hash) {
		$self->{count} += $hash->{$_};
		$self->{data}{ $self->_round($_) } += $hash->{$_};
	};
};

=head2 get_data_hash()

Return distribution hashref {value => number of occurances}.

This is inverse of add_data_hash.

=cut

sub get_data_hash {
	my $self = shift;

	# shallow copy of data
	my $hash = {%{ $self->{data} }};
	return $hash;

};

=head2 count

Return number of data points.

=cut

sub count {
	my $self = shift;
	return $self->{count};
};

=head2 sum()

Return sum of all data points.

=cut

sub sum {
	my $self = shift;
	return $self->sum_of(sub { $_[0] });
};

=head2 sumsq()

Return sum of squares of all datapoints.

=cut

sub sumsq {
	my $self = shift;
	return $self->sum_of(sub { $_[0] * $_[0] });
};

=head2 mean()

Return mean, which is sum()/count().

=cut

sub mean {
	my $self = shift;
	return $self->{count} ? $self->sum / $self->{count} : undef;
};

=head2 variance()

Return data variance, i.e. E((x - E(x)) ** 2).

=cut

sub variance {
	my $self = shift;

	# This part is stolen from Statistics::Descriptive
	my $div = @_ ? 0 : 1;
	if ($self->{count} < 1 + $div) {
		return 0;
	}

	my $var = $self->sumsq - $self->sum**2 / $self->{count};
	return $var <= 0 ? 0 : $var / ( $self->{count} - $div );
};

=head2 standard_deviation()

=head2 std_dev()

Return standard deviation (square root of variance).

=cut

sub standard_deviation {
	# This part is stolen from Statistics::Descriptive
	my $self = shift;
	return if (!$self->count());
	return sqrt($self->variance());
};

=head2 min()

=head2 max()

Values of minimal and maximal buckets.

=cut

sub min {
	my $self = shift;
	return $self->_sort->[0];
};

sub max {
	my $self = shift;
	return $self->_sort->[-1];
};

=head2 sample_range()

Return sample range of the dataset, i.e. max() - min().

=cut

sub sample_range {
	my $self = shift;
	return $self->max - $self->min;
};

=head2 percentile( $n )

Find $n-th percentile, i.e. a value below which lies $n % of the data.

0-th percentile is by definition -inf and is returned as undef
(see Statistics::Descriptive).

$n is a real number, not necessarily integer.
=cut

sub percentile {
	my $self = shift;
	my $x = shift;

	# assert 0<=$x<=100
	croak __PACKAGE__.": percentile() argument must be between 0 and 100"
		unless 0<= $x and $x <= 100;

	my $need = $x * $self->{count} / 100;
	return if $need < 1;

	# dichotomize
	# $i is lowest value >= needed
	# $need doesnt exceed last bucket!
	my $i = _bin_search_ge( $self->_probability, $need );
	return $self->_sort->[ $i ];
};

=head2 quantile( 0..4 )

From Statistics::Descriptive manual:

  0 => zero quartile (Q0) : minimal value
  1 => first quartile (Q1) : lower quartile = lowest cut off (25%) of data = 25th percentile
  2 => second quartile (Q2) : median = it cuts data set in half = 50th percentile
  3 => third quartile (Q3) : upper quartile = highest cut off (25%) of data, or lowest 75% = 75th percentile
  4 => fourth quartile (Q4) : maximal value

=cut

sub quantile {
	my $self = shift;
	my $t = shift;

	croak (__PACKAGE__.": quantile() argument must be one of 0..4")
		unless $t =~ /^[0-4]$/;

	$t or return $self->min;
	return $self->percentile($t * 100 / 4);
};

=head2 median()

Return median of data, a value that divides the sample in half.
Same as percentile(50).

=cut

sub median {
	my $self = shift;
	return $self->percentile(50);
};

=head2 harmonic_mean()

Return harmonic mean of the data, i.e. 1/E(1/x).

Return undef if division by zero occurs (see Statistics::Descriptive).

=cut

sub harmonic_mean {
	my $self = shift;

	my $ret;
	eval {
		$ret = $self->count / $self->sum_of(sub { 1/$_[0] });
	};
	if ($@ and $@ !~ /division.*zero/) {
		die $@; # rethrow ALL BUT 1/0 which yields undef
	};
	return $ret;
};

=head2 geometric_mean()

Return geometric mean of the data, that is, exp(E(log x)).

Dies unless all data points are of the same sign.

=cut

sub geometric_mean {
	my $self = shift;

	croak __PACKAGE__.": geometric_mean() called on mixed sign sample"
		if $self->min * $self->max < 0;

	return 0 if $self->{data}{0};
	# this must be dog slow, but we already log() too much at this point.
	my $ret = exp( $self->sum_of( sub { log abs $_[0] } ) / $self->{count} );
	return $self->min < 0 ? -$ret : $ret;
};

=head2 skewness()

Return skewness of the distribution, calculated as
n/(n-1)(n-2) * E((x-E(x))**3)/std_dev**3 (this is consistent with Excel).

=cut

sub skewness {
	my $self = shift;

	my $n = $self->{count};
	return unless $n > 2;

	# code stolen from Statistics::Descriptive
	my $skew = $n * $self->std_moment(3);
	my $correction = $n / ( ($n-1) * ($n-2) );
	return $correction * $skew;
};

=head2 kurtosis()

Return kurtosis of the distribution, that is 4-th standardized moment - 3.
The exact formula used here is consistent with that of Excel and
Statistics::Descriptive.

=cut

sub kurtosis {
	my $self = shift;

	my $n = $self->{count};
	return unless $n > 3;

	# code stolen from Statistics::Descriptive
	my $kurt = $n * $self->std_moment(4);
	my $correction1 = ( $n * ($n+1) ) / ( ($n-1) * ($n-2) * ($n-3) );
	my $correction2 = ( 3  * ($n-1) ** 2) / ( ($n-2) * ($n-3) );

	return $correction1 * $kurt - $correction2;
};

=head2 trimmed_mean( $ltrim, [ $utrim ] )

Return mean of sample with $ltrim and $utrim fraction of data points
remover from lower and upper ends respectively.

ltrim defaults to 0, and rtrim to ltrim.

=cut

sub trimmed_mean {
	my $self = shift;
	my ($lower, $upper) = @_;
	$lower ||= 0;
	$upper = $lower unless defined $upper;

	my $min = $self->percentile($lower * 100);
	my $max = $self->percentile(100 - $upper * 100);

	return unless $min < $max;

	return $self->mean_of(sub{$_[0]}, $min, $max);
};

=head2 central_moment( $n )

Return $n-th central moment, that is, E((x - E(x))^$n).

=cut

sub central_moment {
	my $self = shift;
	my $n = shift;

	my $mean = $self->mean;
	return $self->sum_of(sub{ ($_[0] - $mean) ** $n }) / $self->{count};
};

=head2 std_moment( $n )

Return $n-th standardized moment, that is,
E((x - E(x))**$n) / std_dev(x)**$n.

=cut

sub std_moment {
	my $self = shift;
	my $n = shift;

	my $mean = $self->mean;
	my $dev = $self->std_dev;
	return $self->sum_of(sub{ ($_[0] - $mean) ** $n })
		/ ( $dev**$n * $self->{count} );
};

=head2 mode

Mode of a distribution is the most common value for a discrete distribution,
or maximum of probability density for continuous one. We assume the
distribution IS continuous, as we're already approximating.

So we count probability density by smoothing hit counts in nearest nonempty
intervals to stabilize it a little.

NOTE A better algorithm is wanted. Experimental.

NOTE Testing shows mode fairly unstable around zero, e.g.
normal distribution (10,10) returns mode close to 0.

=cut

sub mode {
	my $self = shift;

	my $index = $self->_sort;
	return if (!@$index);
	return $index->[0] if @$index == 1;

	my @mode = (0, undef); # [ max_density, bucket_index ]
	my $density = $self->_probability_density;

	die "Uhhuh" unless @$index == @$density;

	for my $i (0..@$index-1) {
		$density->[$i] > $mode[0] or next;
		$mode[0] = $density->[$i];
		$mode[1] = $index->[$i]
	};

	return $mode[1];
};

sub _probability_density {
	my $self = shift;

	my $index = $self->_sort;
	return [] unless @$index >= 2;

	# FIXME AWFUL
	# We cannot calculate mode by comparing bucket counts:
	#   buckets differ in size, and wide ones would naturally
	#   contain more hits.
	# However, simple division by bucket size would result in instability
	#   around zero. Besides, zeroth bucket may have zero width.
	# So, we add up adjacent nonempty buckets to stabilize the
	#   damned thing a little.
	#                   C[prev] + 2 * C[this] + C[next]
	# As in, density = ---------------------------------
	#                          2 * |next - prev|
	# The egde buckets get zero instead of right/left partner,
	#   because life's so unfair.
	# Still I fear it's hacky. I wish I knew better.
	# Mode was a hell to implement.

	my $bin = $self->{data};
	my @density;

	for (my $i = 1; $i < @$index-1; $i++ ) {
		my $count = $bin->{ $index->[$i] }
			+ ($bin->{ $index->[$i-1] }+$bin->{ $index->[$i+1] })/2;
		$density[$i] = $count / ($index->[$i+1] - $index->[$i-1]);
	};
	# special cases
	my $count = 0 + $bin->{ $index->[0] } + $bin->{ $index->[1] } / 2;
	$density[0] = $count / (($index->[1] - $index->[0]) * 2);

	$count = $bin->{ $index->[-2] } / 2 + $bin->{ $index->[-1] } + 0;
	push @density, $count / (($index->[-1] - $index->[-2]) * 2);

	return \@density;
};

=head2 frequency_distribution_ref( \@index )

=head2 frequency_distribution_ref( $n )

=head2 frequency_distribution_ref

Return numbers of data point counts below each number in @index as hashref.

If a number is given instead of arrayref, @index is created
by dividing [min, max] into $n intervals.

If no parameters are given, return previous result, if any.

=cut

sub frequency_distribution_ref {
	my $self = shift;
	my $index = shift;

	# ah, compatibility - return last value
	return $self->{cache}{frequency_distribution_ref}
		unless defined $index;
	# make index if number given
	if (!ref $index) {
		croak __PACKAGE__.": frequency_distribution_ref(): ".
			"argument must be array, of number > 2, not $index"
			unless $index > 2;
		my $min = $self->_lower($self->min);
		my $max = $self->_upper($self->max);
		my $step = ($max - $min) / $index;
		$index = [ map { $min + $_ * $step } 1..$index ];
	};

	@$index = ("-inf", sort { $a <=> $b } @$index);

	my @count;
	for (my $i = 0; $i<@$index-1; $i++) {
		push @count, $self->sum_of( sub{1},
			$index->[$i], $index->[$i+1] );
	};
	shift $index; # remove -inf

	my %hash;
	@hash{@$index} = @count;
	$self->{cache}{frequency_distribution_ref} = \%hash;
	return \%hash;
};

=head2 mean_of( $code, [$min, $max] )

Return expectation of $code over sample within given range.

$code is expected to be a pure function (i.e. depending only on its input
value, and having no side effects).

The underlying integration mechanism only calculates $code once per bucket,
so $code should be stable as in not vary wildly over small intervals.

=cut

sub mean_of {
	my $self = shift;
	my ($code, $min, $max) = @_;

	my $weight = $self->sum_of( sub {1}, $min, $max );
	return unless $weight;
	return $self->sum_of($code, $min, $max) / $weight;
};

# We'll keep methods' returned values under {cache}.
# All setters destroy said cache altogether.
# PLEASE replace this with a ready-made module if there's one.

# Sorry for this black magic, but it's too hard to write //= in EVERY method
# Long story short
# The next sub replaces $self->foo() with
# sub { $self->{cache}{foo} //= $self->originnal_foo }
# All setter methods are EXPECTED to destroy {cache} altogether.

# NOTE if you plan subclassing the method, re-memoize methods you change.
sub _memoize_method {
	my ($class, $name, $arg) = @_;

	my $orig_code = $class->can($name);
	die "Error in memoizer section ($name)"
		unless ref $orig_code eq 'CODE';

	# begin long conditional
	my $cached_code = !$arg
	? sub {
		if (!exists $_[0]->{cache}{$name}) {
			$_[0]->{cache}{$name} = $orig_code->($_[0]);
		};
		return $_[0]->{cache}{$name};
	}
	: sub {
		my $self = shift;
		my $arg = shift;
		$arg = '' unless defined $arg;

		if (!exists $self->{cache}{"$name:$arg"}) {
			$self->{cache}{"$name:$arg"} = $orig_code->($self, $arg);
		};
		return $self->{cache}{"$name:$arg"};
	};
	# conditional ends here

	no strict 'refs'; ## no critic
	no warnings 'redefine'; ## no critic
	*{$class."::".$name} = $cached_code;
}; # end of _memoize_method

# Memoize all the methods w/o arguments
foreach ( qw(sum sumsq mean min max variance standard_deviation mode) ) {
	__PACKAGE__->_memoize_method($_);
};

# Memoize methods with 1 argument
foreach ( qw(quantile central_moment std_moment) ) {
	__PACKAGE__->_memoize_method($_, 1);
};

# add shorter alias of standard_deviation (this must happen AFTER memoization)
{
	no warnings 'once'; ## no critic
	*std_dev = \&standard_deviation;
};

=head2 sum_of ( $code, [ $min, $max ] )

Integrate arbitrary function over the sample within the [ $min, $max ] interval.
Default values for both limits are infinities of appropriate sign.

Values in the edge buckets are cut using interpolation if needed.

NOTE: sum_of(sub{1}, $a, $b) would return rough nubmer of data points
 between $a and $b.

EXPERIMENTAL. The method name may change in the future.

=cut

sub sum_of {
	my $self = shift;
	my ($code, $realmin, $realmax) = @_;

	# Just app up stuff
	if (!defined $realmin and !defined $realmax) {
		my $sum = 0;
		while (my ($val, $count) = each %{ $self->{data} }) {
			$sum += $count * $code->( $val );
		};
		return $sum;
	};

	$realmin = "-inf" unless defined $realmin;
	$realmax =  "inf" unless defined $realmax;
	return 0 if( $realmin >= $realmax );

	# correct limits. $min, $max are indices; $left, $right are limits
	my $min   = $self->_round($realmin);
	my $max   = $self->_round($realmax);
	my $left  = $self->_lower($realmin);
	my $right = $self->_upper($realmax);

	# find first bucket that's above $left
	my $keys = $self->_sort;
	my $i = _bin_search_ge($keys, $left);

	# warn "sum_of [$min, $max]";
	# add up buckets
	my $sum = 0;
	for (; $i < @$keys; $i++) {
		my $val = $keys->[$i];
		last if $val > $right;
		$sum += $self->{data}{$val} * $code->( $val );
	};

	# cut edges: the hard part
	# min and max are now used as indices
	# if min or max hits 0, we cut it in half (i.e. into equal 0+ and 0-)
	# warn "Add up, sum_of = $sum";
	if ($self->{data}{$max}) {
		my $width = $self->_upper($max) - $self->_lower($max);
		my $part = $width
			? ($self->_upper($max) - $realmax) / $width
			: 0.5;
		$sum -= $self->{data}{$max} * $code->($max) * $part;
	};
	# warn "Cut R,  sum_of = $sum";
	if ($self->{data}{$min}) {
		my $width = $self->_upper($min) - $self->_lower($min);
		my $part = $width
			? ($realmin - $self->_lower($min)) / $width
			: 0.5;
		$sum -= $self->{data}{$min} * $code->($min) * $part;
	};
	# warn "Cut L,  sum_of = $sum";

	return $sum;
}; # end sum_of


# BINARY SEARCH
# Not a method, just a function
# Takes sorted \@array and a $num
# Return lowest $i such that $array[$i] >= $num
# Return (scalar @array) if no such $i exists
sub _bin_search_ge {
	my ($array, $x) = @_;

	return 0 unless @$array and $array->[0] < $x;
	my $l = 0;
	my $r = @$array;
	while ($l+1 < $r) {
		my $m = int( ($l + $r) /2);
		$array->[$m] < $x ? $l = $m : $r = $m;
	};
	return $l+1;
};

sub _round {
	my $self = shift;
	my $x = shift;

	if (abs($x) <= $self->{zero_thresh}) {
		return 0;
	};
	my $i = floor (((log abs $x) - $self->{logfloor})/ $self->{logbase});
	my $value = $self->{base} ** $i;
	return $x < 0 ? -$value : $value;
};

# lower, upper limits of $i-th bucket
sub _upper {
	my $self = shift;
	my $x = shift;

	if (abs($x) <= $self->{zero_thresh}) {
		return $self->{zero_thresh};
	};
	my $i = floor (((log abs $x) - $self->{logfloor} )/ $self->{logbase});
	if ($x > 0) {
		return $self->{floor} * $self->{base}**($i+1);
	} else {
		return -$self->{floor} * $self->{base}**($i);
	};
};

sub _lower {
	return -$_[0]->_upper(-$_[1]);
};

sub _sort {
	my $self = shift;
	return $self->{cache}{sorted}
		||= [ sort { $a <=> $b } keys %{ $self->{data} } ];
};

sub _probability {
	my $self = shift;
	return $self->{cache}{probability} ||= do {
		my @array;
		my $sum = 0;
		foreach (@{ $self->_sort }) {
			$sum += $self->{data}{$_};
			push @array, $sum;
		};
		\@array;
	};
};

=head1 AUTHOR

Konstantin S. Uvarin, C<< <khedin at gmail.com> >>

=head1 BUGS

The module is currently in alpha stage. There may be bugs.

mode() is unstable around zero, better algorithm wanted.

sum_of() requires more extensive unit testing.

Adding linear interpolation could result in precision gains at a little
performance cost.

Please report any bugs or feature requests to C<bug-statistics-descriptive-logscale at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Statistics-Descriptive-LogScale>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Statistics::Descriptive::LogScale


You can also look for information at:

=over 4

=item * GitHub:

L<https://github.com/dallaylaen/perl-Statistics-Descriptive-LogScale>

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Statistics-Descriptive-LogScale>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Statistics-Descriptive-LogScale>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Statistics-Descriptive-LogScale>

=item * Search CPAN

L<http://search.cpan.org/dist/Statistics-Descriptive-LogScale/>

=back


=head1 ACKNOWLEDGEMENTS

This module was inspired by a talk that Andrew Aksyonoff, author of
L<Sphinx search software|http://sphinxsearch.com/>,
has given at HighLoad++ conference in Moscow, 2012.

L<Statistics::Descriptive> was and is used as reference when in doubt.
Several code snippets were shamelessly stolen from there.

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Konstantin S. Uvarin.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Statistics::Descriptive::LogScale
