#!/usr/bin/env perl
# zypper 1.13 on openSUSE Leap 42.3 has no zstd reader. createrepo_c on the build host writes
# primary.xml.zst by default, so Leap 42.3 refuses the published sles12 cell with
# "Failed to cache repo (4)". The openSUSE cells must be indexed with gzip metadata.
#
# createrepo_c_cmd and sign_and_index_repo are pure: the command runner is a stub, so no
# createrepo_c, rpmsign or gpg runs here.
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..", "$RealBin/../lib";
use MockBuildUtils ();

my $gz = qr/--compress-type gz\b.*--general-compress-type gz\b/;

like(MockBuildUtils::createrepo_c_cmd('/r', 1700000000, 'opensuse-leap-42.3-x86_64'), $gz,
    'the Leap 42.3 cell is indexed with gzip metadata');
like(MockBuildUtils::createrepo_c_cmd('/r', 1700000000, 'opensuse-leap-15.6-x86_64'), $gz,
    'the Leap 15.6 cell is indexed with gzip metadata');
unlike(MockBuildUtils::createrepo_c_cmd('/r', 1700000000, 'alma+epel-10-x86_64'), qr/--compress-type/,
    'an EL cell keeps the createrepo_c default');
unlike(MockBuildUtils::createrepo_c_cmd('/r', 1700000000), qr/--compress-type/,
    'an index with no target keeps the createrepo_c default');
like(MockBuildUtils::createrepo_c_cmd('/r', 1700000000, 'opensuse-leap-42.3-x86_64'),
    qr/--revision '?1700000000'? --set-timestamp-to-revision/,
    'the gzip index still pins its revision to SOURCE_DATE_EPOCH');

my $dir = tempdir(CLEANUP => 1);
my @ran;
MockBuildUtils::sign_and_index_repo($dir, undef,
    run => sub { push @ran, $_[0] }, source_date_epoch => 1700000000,
    target => 'opensuse-leap-42.3-x86_64');
my @index = grep { /\Acreaterepo_c / } @ran;
is(scalar @index, 1, 'deploying a cell indexes it once');
like($index[0] // '', $gz, 'deploying the Leap 42.3 cell writes gzip metadata');

done_testing();
