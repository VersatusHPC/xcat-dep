#!/usr/bin/perl
# A build that is stopped mid-flight leaves staging/<codename>/<arch> half-populated. The publish
# phase collects debs with glob("<staging>/<codename>/*/*.deb"), across EVERY architecture directory
# it finds, so the next publish run copies that partial set into the pool. The published-repo gate
# does not see it: an architecture outside --expect-arch gets no binary-<arch> index, and the gate
# only reads indexes.
#
# These tests drive the real sbuild-all.pl publish path over a hand-made staging tree. A cell that
# no run validated must stop the publish; a cell that a staging run validated must publish.
use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use FindBin;
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

# The manifest is the source of truth for a complete cell. One package per cell keeps the fixture
# small: what is under test is the treatment of a cell, not the manifest comparison itself.
my $manifest = "$tmp/debs-manifest.conf";
write_file($manifest, <<'MAN');
[noble-amd64]
ipmitool-xcat=1

[noble-ppc64el]
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
# with dpkg-deb.
sub make_deb {
    my ($dst, $name, $arch) = @_;
    my $root = "$tmp/deb-$name-$arch-$$-" . int(rand(1e6));
    write_file("$root/DEBIAN/control",
        "Package: $name\nVersion: 1\nArchitecture: $arch\n"
      . "Maintainer: xCAT <xcat-user\@lists.sourceforge.net>\n"
      . "Description: staging cell fixture\n");
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

# make_tree($tag, %o): an output root whose noble cells are staged but not published. The amd64 cell
# always carries its manifest package. The ppc64el cell carries its own, and $o{validate} decides
# whether a staging run (the run that a stopped build never finishes) validated it.
my $tree_seq = 0;
sub make_tree {
    my (%o) = @_;
    my $out = "$tmp/out" . (++$tree_seq);
    make_deb("$out/staging/noble/amd64",   'ipmitool-xcat', 'amd64');
    make_deb("$out/staging/noble/ppc64el", 'ipmitool-xcat', 'ppc64el');
    if ($o{validate}) {
        # --no-publish: --skip-build alone means "finalization run" and would publish. This stands
        # in for the per-arch stage that builds and validates, then stops.
        my ($rc, $log) = run_sbuild('--output-root', $out, '--apt-dir', "$out/apt",
                                    '--arch', 'ppc64el', '--no-publish');
        is($rc, 0, "$o{name}: the ppc64el staging run validates its cell")
            or diag($log);
    }
    return $out;
}

# publish($out): the finalization run. --expect-arch names amd64 only, which is the case the gate
# cannot cover: no binary-ppc64el index is written, so no index check ever reads that architecture.
sub publish {
    my ($out) = @_;
    return run_sbuild('--output-root', $out, '--apt-dir', "$out/apt", '--arch', 'amd64',
                      '--publish', '--expect-arch', 'amd64');
}

my $POOLED = 'pool/main/noble/ipmitool-xcat_1_ppc64el.deb';

# ---- a cell no run validated must stop the publish ----------------------------------------------
{
    my $out = make_tree(name => 'unvalidated');
    my ($rc, $log) = publish($out);
    isnt($rc, 0, 'a staged cell that no run validated stops the publish');
    like($log, qr{staging/noble/ppc64el},
        '... and the message names the cell to remove or rebuild');
    ok(!-e "$out/apt/$POOLED",
        '... so the unvalidated cell never reaches the published pool');
    ok(!-d "$out/apt", '... and the publish leaves no repository behind');
}

# ---- a cell a staging run validated publishes ----------------------------------------------------
{
    my $out = make_tree(name => 'validated', validate => 1);
    my ($rc, $log) = publish($out);
    is($rc, 0, 'a validated cell publishes') or diag($log);
    ok(-e "$out/apt/$POOLED",
        '... and its package reaches the published pool');
}

done_testing();
