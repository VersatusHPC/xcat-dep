#!/usr/bin/env perl
# mockbuild-all.pl cannot build the openSUSE dep cell at all:
#
#   Could not parse EL release from target 'opensuse-leap-15.6-x86_64'
#
# target_profile tries openEuler, then the forcearch table, then falls through to /epel-(\d+)-/ and
# dies. a1ab393 removed target_osdir, which had mapped opensuse-leap-15.6-* to sles15, while the
# pipeline still runs mockbuild-all.pl --target opensuse-leap-15.6-x86_64. So
# xcat-dep-build-opensuse15-x86_64 has never completed a real build: the one SUCCESS in its history
# was a MOCK run, which stubs the build and publishes a passing junit.
#
# target_profile is pure, so this runs no mock and installs no /etc/mock configuration.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..", "$RealBin/../lib";
use MockBuildUtils qw(target_profile dep_repo_baseurl dep_repo_label);

# The cell is sles<MAJOR>/<arch>: every 15.x publishes under sles15, which is the directory
# xcat.org serves and the one a SUSE conf's DEP_REPO points at.
my %cell = (
    'opensuse-leap-15.6-x86_64'  => 'sles15/x86_64',
    'opensuse-leap-15.6-ppc64le' => 'sles15/ppc64le',
    'opensuse-leap-16.0-x86_64'  => 'sles16/x86_64',
    'opensuse-leap-42.3-x86_64'  => 'sles42/x86_64',
);
for my $t (sort keys %cell) {
    my ($arch) = $t =~ /-([^-]+)\z/;
    my $p = eval { target_profile($t, $arch) };
    ok($p, "$t yields a profile") or do { diag($@); next };
    is($p->{cell}, $cell{$t},   "$t publishes into $cell{$t}");
    is($p->{arch}, $arch,       "$t builds for $arch");
    is($p->{epel}, 0,           "$t does not look for EPEL, which Leap has none of");
    is($p->{forcearch}, 0,      "$t builds natively, not through qemu-user-static");
    ok(scalar @{$p->{dep_builders}}, "$t has something to build");
    ok(scalar @{$p->{required}},     "$t asserts a required set");
}

# The EL and openEuler answers must not move.
my $el = target_profile('alma+epel-10-x86_64', 'x86_64');
is($el->{cell}, 'rh10/x86_64', 'an EL target still publishes into rh<N>/<arch>');
is($el->{rel}, '10', '... and still parses its release');
is($el->{epel}, 1, '... and still looks for EPEL');

my $oe = target_profile('openeuler-24.03sp4-x86_64', 'x86_64');
is($oe->{cell}, 'openeuler24.03sp4/x86_64', 'an openEuler target keeps its own layout');

my $fa = target_profile('rocky-10-riscv64-xcat', 'x86_64');
is($fa->{cell}, 'rh10/riscv64', 'a forcearch target publishes into the arch it cross-builds');
is($fa->{forcearch}, 1, '... and is marked forcearch');

# A target that belongs to no family is still refused, rather than silently publishing somewhere.
for my $bad ('opensuse-tumbleweed-x86_64', 'opensuse-leap-15-x86_64', 'debian-12-amd64') {
    my $p = eval { target_profile($bad, 'x86_64') };
    ok(!$p, "$bad is refused");
    like($@, qr/Could not parse EL release/, "... and says which parse failed for $bad");
}

# xcat.org serves Leap from the sles channel. A cell that advertised the yum channel would hand
# every client a baseurl that does not hold it. 94daf29 had this and a1ab393 took it out with the
# rest of the SUSE support.
is(dep_repo_baseurl('sles15/x86_64'),
   'https://xcat.org/files/xcat/repos/sles/devel/xcat-dep/sles15/x86_64',
   'a Leap cell advertises the sles channel');
is(dep_repo_baseurl('rh10/x86_64'),
   'https://xcat.org/files/xcat/repos/yum/devel/xcat-dep/rh10/x86_64',
   'an EL cell advertises the yum channel');
is(dep_repo_baseurl('openeuler24.03sp4/x86_64'),
   'https://xcat.org/files/xcat/repos/yum/devel/xcat-dep/openeuler24.03sp4/x86_64',
   'an openEuler cell advertises the yum channel');
is(dep_repo_label('sles15/x86_64'), 'sles15 x86_64', 'a Leap cell names itself sles15, not rh15');
is(dep_repo_label('rh10/x86_64'), 'rh10 x86_64', 'an EL cell is unchanged');

done_testing();
