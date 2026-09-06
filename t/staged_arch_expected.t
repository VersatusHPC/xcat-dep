#!/usr/bin/perl
# assemble_into fills the pool from glob("<staging>/<codename>/*/*.deb") -- every architecture cell it
# finds. The completeness gate reads only the published binary-<arch>/Packages indexes, and
# assemble_into writes an index only for an architecture in the expected set. An architecture staged
# outside that set therefore reaches pool/main/<codename>, the flat <version>/ directory and the
# offline tarball with nothing having verified it.
#
# The expected set has two sources and both let that happen:
#   * inferred (no --expect-arch): resolve_expect_arches filtered the staged set through a hardcoded
#     architecture pair, so a third staged architecture was dropped from the set that gets an index.
#   * explicit (--expect-arch, which the CD pipeline passes): the claim wins and staging is never
#     compared against it.
#
# These tests drive the real sbuild-all.pl publish path over a hand-made staging tree.
use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use FindBin;
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);

my $repo_root = abs_path("$FindBin::Bin/..");
my $SCRIPT    = "$repo_root/sbuild-all.pl";
plan skip_all => "sbuild-all.pl not found at $SCRIPT" unless -f $SCRIPT;
plan skip_all => 'dpkg-deb and apt-ftparchive are required'
    unless $^O eq 'linux'
    && !system('sh', '-c', 'command -v dpkg-deb >/dev/null 2>&1')
    && !system('sh', '-c', 'command -v apt-ftparchive >/dev/null 2>&1');

my $tmp = tempdir(CLEANUP => 1);

# One package per cell: what is under test is which cells the publish covers, not the manifest
# comparison. riscv64 has its own section, so an expected riscv64 cell is verifiable -- the gate
# reporting NO-MANIFEST would prove nothing about the architecture set.
my $manifest = "$tmp/debs-manifest.conf";
write_file($manifest, <<'MAN');
[noble-amd64]
ipmitool-xcat=1

[noble-ppc64el]
ipmitool-xcat=1

[noble-riscv64]
ipmitool-xcat=1
MAN

# ---------------------------------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------------------------------
sub write_file {
    my ($path, $body) = @_;
    make_path($path =~ m{^(.*)/[^/]+$} ? $1 : '.');
    open my $fh, '>', $path or die "write $path: $!";
    print $fh $body;
    close $fh;
}

# make_deb($dst_dir, $name, $arch): a real .deb, because the publish phase reads its control fields
# with dpkg-deb and indexes stanzas by their Architecture field.
sub make_deb {
    my ($dst, $name, $arch) = @_;
    my $root = "$tmp/deb-$name-$arch-$$-" . int(rand(1e6));
    write_file("$root/DEBIAN/control",
        "Package: $name\nVersion: 1\nArchitecture: $arch\n"
      . "Maintainer: xCAT <xcat-user\@lists.sourceforge.net>\n"
      . "Description: staged architecture fixture\n");
    make_path($dst);
    my $file = "$dst/${name}_1_${arch}.deb";
    system('dpkg-deb', '--root-owner-group', '--build', $root, $file) == 0
        or die "cannot build the fixture deb $file\n";
    return $file;
}

# run_sbuild(@argv) -> ($exit_code, $combined_output)
sub run_sbuild {
    my (@extra) = @_;
    my @cmd = ($^X, $SCRIPT, '--repo-root', $repo_root, '--manifest', $manifest,
               '--dists', 'noble', '--skip-build', '--skip-genesis', '--skip-tarball', @extra);
    my $line = join(' ', map { my $x = $_; $x =~ s/'/'"'"'/g; "'$x'" } @cmd) . ' 2>&1';
    open my $ph, '-|', $line or die "cannot run: $line: $!";
    my $out = do { local $/; <$ph> };
    close $ph;
    return ($? >> 8, defined $out ? $out : '');
}

# stage_validated($out, $arch): stage the cell's manifest package, then let a staging run validate it,
# exactly as the per-arch build stage does before it stops.
sub stage_validated {
    my ($out, $arch, $label) = @_;
    make_deb("$out/staging/noble/$arch", 'ipmitool-xcat', $arch);
    my ($rc, $log) = run_sbuild('--output-root', $out, '--apt-dir', "$out/apt",
                                '--arch', $arch, '--no-publish');
    is($rc, 0, "$label: the $arch staging run validates its cell") or diag($log);
    return;
}

# stage_validated_like($out, $arch, $model): the same, for an architecture sbuild-all.pl does not
# accept on --arch yet. Copy every non-deb file the validated $model cell carries, so the cell looks
# to the publish phase exactly like one a staging run validated. Copying rather than naming the
# marker keeps this test independent of what that marker is called.
sub stage_validated_like {
    my ($out, $arch, $model) = @_;
    my $dst = "$out/staging/noble/$arch";
    make_deb($dst, 'ipmitool-xcat', $arch);
    my $src = "$out/staging/noble/$model";
    my @marks = grep { -f $_ && !/\.deb$/ } (glob("$src/*"), glob("$src/.*"));
    ok(scalar(@marks), "the $model cell carries a validation mark to copy to $arch");
    copy($_, "$dst/" . basename($_)) or die "cannot copy $_: $!" for @marks;
    return;
}

sub publish {
    my ($out, @expect) = @_;
    return run_sbuild('--output-root', $out, '--apt-dir', "$out/apt", '--arch', 'amd64',
                      '--publish', map { ('--expect-arch', $_) } @expect);
}

sub slurp {
    my ($p) = @_;
    open my $fh, '<', $p or return '';
    local $/; my $t = <$fh>; close $fh;
    return $t;
}

my $tree_seq = 0;
sub new_out { return "$tmp/out" . (++$tree_seq); }

# ---- an explicit --expect-arch that omits a staged architecture must stop the publish -------------
# The CD pipeline always passes --expect-arch, so this is the path a stale or unwanted staged cell
# actually takes today. Publishing debs the gate never reads is worse than refusing to publish.
{
    my $out = new_out();
    stage_validated($out, 'amd64',   'explicit');
    stage_validated($out, 'ppc64el', 'explicit');
    my ($rc, $log) = publish($out, 'amd64');
    isnt($rc, 0, 'a staged architecture outside --expect-arch stops the publish');
    like($log, qr{staging/noble/ppc64el},
        '... and the message names the cell that is not expected');
    ok(!-e "$out/apt/pool/main/noble/ipmitool-xcat_1_ppc64el.deb",
        '... so the unexpected architecture never reaches the published pool');
    ok(!-d "$out/apt", '... and the publish leaves no repository behind');
}

# ---- an inferred expected set must cover every staged architecture -------------------------------
# With no --expect-arch the expected set is inferred from staging. Every staged architecture
# contributes its debs to the pool, so every one of them must get an index and be verified.
{
    my $out = new_out();
    stage_validated($out, 'amd64', 'inferred');
    stage_validated_like($out, 'riscv64', 'amd64');
    my ($rc, $log) = publish($out);
    is($rc, 0, 'a publish that infers its expected set from staging succeeds') or diag($log);
    ok(-e "$out/apt/pool/main/noble/ipmitool-xcat_1_riscv64.deb",
        '... the staged riscv64 package reaches the pool');
    my $idx = "$out/apt/dists/noble/main/binary-riscv64/Packages";
    ok(-f $idx, '... an index is written for it, so the gate can read it');
    like(slurp($idx), qr/^Architecture:[ \t]*riscv64$/m,
        '... and that index carries the native riscv64 package');
    like(slurp("$out/apt/dists/noble/Release"), qr/^Architectures:.*\briscv64\b/m,
        '... and Release advertises riscv64 to apt clients');
}

done_testing();
