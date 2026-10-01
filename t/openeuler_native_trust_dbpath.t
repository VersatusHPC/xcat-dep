#!/usr/bin/perl
# The publisher keyring rpm database must never sit in the native-input staging tree.
#
# rpm takes an fcntl transaction lock on <dbpath>/.rpm.lock. mockbuild-all.pl stages the openEuler
# ppc64le native inputs under its output root, which in CI is NFS mounted with local_lock=none.
# There the lock answers errno 524 and rpmkeys prints
#
#   error: can't create transaction lock on .../native-inputs/trust/.rpm.lock (Unknown error 524)
#   error: .../RPM-GPG-KEY-openEuler-24.03-LTS: key 1 import failed.
#
# and the target fails before a package is built. Measured on xcat-master-ppc: the same rpmkeys
# command succeeds against a dbpath on local storage.
#
# verify_rpms_checksig already passed publisher_trust a File::Temp directory, which is local, so
# only the staging call site was affected -- and only the one target that has native inputs.
#
# trust_dbpath is pure, so this runs no rpmkeys and needs no NFS.
use strict;
use warnings;
use Test::More;
use File::Spec ();
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use XCAT::NativeInputs qw(trust_dbpath);

my $root = File::Spec->catdir(File::Spec->rootdir, 'local-scratch');
local $ENV{XCAT_DEP_TRUST_TMP} = $root;

my $staging = File::Spec->catdir(File::Spec->rootdir, qw(opt xcat-ci-shared builds oe262 2 native-inputs));
my $db = trust_dbpath($staging);

ok(defined $db && length $db, 'trust_dbpath answers for a staging directory') or done_testing, exit;

unlike($db, qr/\Q$staging\E/,
       'the keyring is not inside the staging tree, where the rpm lock answers errno 524');
like($db, qr/^\Q$root\E\b/, 'the keyring goes under the local root');

# Two targets of one run stage side by side. A shared database would let one target's rpm
# transaction block the other's.
my $other = File::Spec->catdir(File::Spec->rootdir, qw(opt xcat-ci-shared builds oe262 3 native-inputs));
isnt(trust_dbpath($other), $db, 'two staging directories get two databases');

# A retry of the same target must reuse its own, or every attempt leaves another keyring behind.
is(trust_dbpath($staging), $db, 'the same staging directory always gets the same database');

done_testing();
