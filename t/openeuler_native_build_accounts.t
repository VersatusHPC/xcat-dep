#!/usr/bin/env perl
# Which host accounts the native openEuler builds need, derived from the catalogs that declare them.
#
# mock resolves chrootuid on the HOST before it touches the chroot, so a uid the host does not have
# fails with KeyError: 'getpwuid(): uid not found: 1000' in mockbuild/uid.py. The native overlays pin
# chrootuid to the catalog's build_uid, and nothing in this repository created that account:
# xcatnative uid 1000 gid 1000 on xcat-master-ppc was made by hand, so a fresh ppc64le builder could
# not build a native target.
#
# native_build_accounts answers which accounts the catalogs require. mockbuild-all.pl --install-deps
# creates them; this test only reads the catalogs and calls the function, so it runs no useradd.
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/..";
use Test::More;
use File::Temp qw(tempdir);
use File::Slurper qw(write_text);
use JSON::PP ();
use MockBuildUtils ();

my @catalogs = sort glob("$RealBin/../openeuler/*.inputs.json");

# A positive control. An empty glob -- a renamed directory, a moved catalog -- would make every
# assertion below read an empty list and pass having measured nothing.
cmp_ok(scalar @catalogs, '>=', 1, 'openeuler/ ships at least one native input catalog')
    or die "no openeuler/*.inputs.json under $RealBin/.. -- this test reads nothing\n";

# The expectation is derived here from the catalogs themselves, not copied from the function.
my %declared;
for my $path (@catalogs) {
    my $catalog = JSON::PP->new->decode(do { open my $fh, '<', $path or die "$path: $!"; local $/; <$fh> });
    for my $node (@{ $catalog->{inputs} || [] }) {
        $declared{ $node->{build_uid} } = 1 if defined $node->{build_uid};
    }
}

# Both halves must be present, or the exclusion of root below is vacuous.
ok($declared{0}, 'the catalogs declare build_uid 0, which is root and always exists');
my @nonroot = sort { $a <=> $b } grep { $_ != 0 } keys %declared;
is(scalar @nonroot, 1, 'the catalogs declare exactly one non-root build uid')
    or diag 'non-root build uids declared: ' . join(', ', @nonroot);

my @got = eval { MockBuildUtils::native_build_accounts(@catalogs) };
my $error = $@;

is_deeply(\@got, [{ name => 'xcatnative', uid => $nonroot[0], gid => $nonroot[0] }],
    "the catalogs require one account, xcatnative uid $nonroot[0] gid $nonroot[0]")
    or diag($error ? "native_build_accounts died: $error" : 'answered: ' . explain(\@got));

is_deeply([grep { $_->{uid} == 0 } @got], [],
    'root is never asked for, because build_uid 0 needs no account created');

my $scratch = tempdir('native-accounts-XXXXXX', TMPDIR => 1, CLEANUP => 1);

sub catalog_of {
    my ($name, @uids) = @_;
    my $path = "$scratch/$name.inputs.json";
    write_text($path, JSON::PP->new->canonical->encode(
        { version => 1, inputs => [map { { name => "pkg$_", build_uid => $uids[$_] } } 0 .. $#uids] }));
    return $path;
}

is_deeply([eval { MockBuildUtils::native_build_accounts(catalog_of('all-root', 0, 0)) }], [],
    'a catalog that builds everything as root requires no account');

# A second non-root uid has no account name, so answering one would invent it.
my $two = catalog_of('two-uids', 0, 1000, 1001);
my @answer = eval { MockBuildUtils::native_build_accounts($two) };
my $refusal = $@;
like($refusal, qr/1000.*1001|1001.*1000/s,
    'more than one non-root build uid is refused, and the refusal names both')
    or diag(@answer ? 'answered instead: ' . explain(\@answer) : "died with: $refusal");

like($refusal, qr/build uid/i, 'the refusal says which kind of value it could not reconcile');

done_testing();
