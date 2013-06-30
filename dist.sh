#!/bin/sh

PERLS="5.6.0 5.8.8 5.18.0"

die () {
	echo "FATAL:" $1 >&2
	exit 1
}

# only can make dist on commit border
[ `git symbolic-ref HEAD | sed 's#^.*/##'` = "master" ] ||\
	die "Must be on master for dist"
[ -z "`git status -s`" ] || die "Uncommitted changes present"

perlbrew switch-off
perl --version | grep "^This is"

perl Makefile.PL || die "perl makefile fails"
make || die "make fails"
VER=`perl -MYAML=LoadFile -we 'print LoadFile(shift)->{version}' MYMETA.yml`
[ -z "$VER" ] && die "No version found" 
grep "^[ \t]*$VER" Changes || die "Version $VER not present in Changes"

echo "Version $VER..."

USED=`grep -hiro '^use *[a-z][a-z0-9:_]*' lib t bin 2>/dev/null | awk '{print $2}' | sort -u `

echo "Use:" $USED

USED=`perl -MYAML=LoadFile -wle '$c=LoadFile("MYMETA.yml"); 
	for(@ARGV) { exists $c->{requires}{$_} || exists $c->{build_requires}{$_} 
	|| /^(strict|warnings|fields)$/ || print $_ }' $USED`

USED=`perl -wle 'for(@ARGV) { $m=$_; s#::#/#g; -f "lib/$_.pm" or print $m }' $USED`

[ -z "$USED" ] || die "Used modules not in prereq: $USED"

# check make test on several perls
FAILS=
for i in $PERLS; do
	perlbrew switch "perl-$i" || continue
	prove -I lib t/ || FAILS="$FAILS $i"
done

# perlbrew switch-off
prove -I lib t/ || FAILS="$FAILS system-perl"

[ \! -z "$FAILS" ] && die "Tests failed under perls $FAILS"

# OK, now tag && make dist

git tag "v.$VER" -m "Version $VER released"
make dist
