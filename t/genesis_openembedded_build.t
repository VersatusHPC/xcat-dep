use strict;
use warnings;

# xcat-dep builds every package it publishes, except one. The OpenEmbedded Genesis packages had no
# build path in mockbuild-all.pl: the script took --genesis-release, a directory somebody had
# already built, and published it. So the only copies that ever existed were hand-built on
# 2026-08-25, from an xcat-core commit a month old, covering seven architectures.
#
# The second half of the same bug is that nothing noticed. common_repository_requirements() -- the
# [common] completeness gate -- was called from inside `if ($genesis_release ne '')`, so it fired
# only when the run was handed a release. Every production run has that parameter empty, which
# means a dep build that produced no OpenEmbedded packages at all passed its own completeness gate.
# A requirement conditional on the thing it requires observes nothing.
#
# Both halves are driven here for real. Only the OpenEmbedded layer is replaced: the fake xcat-core
# carries an oe/build that makes the deploy directory and an oe/export that writes the export
# layout, so genesis-openembedded/build, package, verify-release --complete, the manifest read and
# the repository gate all run as themselves, over all eight architectures.

use Cwd qw(abs_path);
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use FindBin;
use POSIX ();
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";
use XCAT::BuildUtils qw(command_exists write_binary);
use XCAT::GenesisRelease qw(architectures rpm_package_name);
use XCAT::GenesisReleaseTest qw(run_capture write_forkmanager_stub);

my $repo_root = abs_path("$FindBin::Bin/..");
my $mockbuild = "$repo_root/mockbuild-all.pl";
my $version   = '2.19.0';
my $epoch     = 1787293573;
my $release   = 'snap' . POSIX::strftime('%Y%m%d%H%M', gmtime($epoch));

plan skip_all => 'no rpmbuild' unless command_exists('rpmbuild');
plan skip_all => 'no rpm'      unless command_exists('rpm');
plan skip_all => 'no git'      unless command_exists('git');
plan skip_all => 'not root'    unless $> == 0;

my $tmp = tempdir(CLEANUP => 1);
my @arches = architectures();

#-----------------------------------------------------------------------------------------------
=head3 fake_xcat_source

Descriptions:
    An xcat-core checkout whose OpenEmbedded layer is two stand-ins: oe/build makes the deploy
    directory bitbake would leave, oe/export writes one architecture's export. Everything
    downstream of them is the real code.
Arguments:
    $directory - where to build it
Returns:
    The checkout path.
=cut
#-----------------------------------------------------------------------------------------------
sub fake_xcat_source {
    my ($directory) = @_;
    make_path("$directory/xCAT-genesis-builder/oe");
    write_binary("$directory/Version", "$version\n");
    write_binary("$directory/xCAT-genesis-builder/oe/build", <<'SH');
#!/bin/bash
set -eu
# genesis-openembedded/build asks the source which architectures it can make before it trusts a
# request for s390x, so the stand-in has to answer that too.
if [ "${1:-}" = --list-architectures ]; then
    echo "x86 x86_64 ppc64 ppc64le armv7hf aarch64 riscv64 s390x"
    exit 0
fi
mkdir -p "${XCAT_GENESIS_WORK_DIR}/build/tmp/deploy"
printf '%s\n' "$@" > "${XCAT_GENESIS_WORK_DIR}/build/tmp/deploy/.architectures"
SH
    write_binary("$directory/xCAT-genesis-builder/oe/export", <<'SH');
#!/bin/bash
set -eu
architecture=$1
output=$3
mkdir -p "$output"
printf 'kernel' > "$output/kernel"
printf 'initramfs' > "$output/initramfs.cpio.gz"
printf 'packages' > "$output/image.manifest"
printf '{}' > "$output/image.spdx.json"
printf '{}' > "$output/image.vex.json"
printf 'licenses' > "$output/license.manifest"
printf 'format=xcat-genesis\nversion=1\narchitecture=%s\n' "$architecture" \
    > "$output/xcat-genesis.manifest"
if [ "$architecture" = riscv64 ]; then printf 'firmware' > "$output/fw_jump.elf"; fi
( cd "$output" && find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort \
    | xargs -r sha256sum > SHA256SUMS )
SH
    chmod(0755, "$directory/xCAT-genesis-builder/oe/build",
                "$directory/xCAT-genesis-builder/oe/export");
    # genesis-openembedded/build reads the revision and the commit time from git and refuses a
    # checkout with local modifications, so this is a real repository.
    my $env = "GIT_AUTHOR_DATE='$epoch +0000' GIT_COMMITTER_DATE='$epoch +0000'"
            . " GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t\@t"
            . " GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t\@t";
    for my $step ("init -q -b master", "add -A", "commit -q -m seed") {
        system("$env git -C '$directory' $step >/dev/null 2>&1") == 0
          or die "git $step failed in $directory";
    }
    return $directory;
}

#-----------------------------------------------------------------------------------------------
=head3 filler_rpm

Descriptions:
    Build one trivial noarch rpm into $directory. mockbuild-all.pl refuses a run that collects
    nothing ("No binary RPMs were collected"), which is a guard about the dep packages and not
    about Genesis, so a --skip-build run needs something to collect.
Arguments:
    $directory - a collection directory to create
Returns:
    The directory.
=cut
#-----------------------------------------------------------------------------------------------
sub filler_rpm {
    my ($directory) = @_;
    my $top = "$directory/.rpmbuild";
    make_path("$top/SPECS", $directory);
    write_binary("$top/SPECS/filler.spec", <<'SPEC');
Name:       xcat-dep-test-filler
Version:    1
Release:    1
Summary:    fixture
License:    EPL-1.0
BuildArch:  noarch
%description
fixture
%install
mkdir -p %{buildroot}/usr/share/xcat-dep-test-filler
%files
/usr/share/xcat-dep-test-filler
SPEC
    my $rc = system("rpmbuild -bb --define '_topdir $top' --define '_rpmdir $directory'"
                  . " '$top/SPECS/filler.spec' >/dev/null 2>&1");
    die "cannot build the filler rpm" unless $rc == 0;
    return $directory;
}

#-----------------------------------------------------------------------------------------------
=head3 scratch_manifest

Descriptions:
    A packages-manifest.conf for the scratch repo root: one satisfiable target section naming the
    filler package, and the real [common] section. --no-verify-repo would switch off the [common]
    gate along with the per-target one, so the target section is made satisfiable instead.
Arguments:
    $root   - the scratch repo root
    $target - the target section to write
Returns:
    The repo root.
=cut
#-----------------------------------------------------------------------------------------------
sub scratch_manifest {
    my ($root, $target) = @_;
    make_path($root);
    my $text = "[$target]\nxcat-dep-test-filler=>= 1\n\n[common]\n";
    $text .= rpm_package_name($_) . "=>= 2.18.0\n" for architectures();
    write_binary("$root/packages-manifest.conf", $text);
    return $root;
}

sub slurp {
    my ($path) = @_;
    return '(no log)' unless -f $path;
    open(my $fh, '<', $path) or return "(unreadable)";
    my $c = do { local $/; <$fh> }; close($fh); return $c;
}

#-----------------------------------------------------------------------------------------------
=head3 run_mockbuild

Descriptions:
    Run mockbuild-all.pl over a scratch tree. The skip flags reduce it to the collect, deploy and
    gate path -- the OpenEmbedded work is the subject, the rest is not.
Arguments:
    $log, $repo_dep, @extra
Returns:
    The exit status.
=cut
#-----------------------------------------------------------------------------------------------
sub run_mockbuild {
    my ($log, $repo_dep, @extra) = @_;
    our ($FILLER, $ROOT);
    return run_capture(
        $log,
        $^X, $mockbuild,
        '--output', "$tmp/output",
        '--repo-dep', $repo_dep,
        '--target', 'alma+epel-10-x86_64',
        '--run-id', 'genesis-build',
        '--build-timestamp', $epoch,
        '--skip-build', '--skip-genesis', '--skip-xcat-dep', '--skip-perl',
        '--skip-createrepo', '--skip-tarball', '--force-unlock',
        '--repo-root', $ROOT,
        '--collect-dir', $FILLER,
        @extra,
    );
}

my @perl_lib;
push(@perl_lib, write_forkmanager_stub("$tmp/perl-stub"))
  unless eval { require Parallel::ForkManager; 1 };
push(@perl_lib, $ENV{PERL5LIB}) if defined($ENV{PERL5LIB}) && $ENV{PERL5LIB} ne '';
local $ENV{PERL5LIB} = join(':', @perl_lib);

our $FILLER = filler_rpm("$tmp/filler");
our $ROOT = scratch_manifest("$tmp/repo-root", 'alma+epel-10-x86_64');
my $source = fake_xcat_source("$tmp/xcat-core");
cmp_ok(scalar(@arches), '>=', 8, 'a complete release covers at least eight architectures');

# 1. The tooling must be able to BUILD the packages, not only publish someone else's.
my $built = "$tmp/release";
{
    my $log = "$tmp/build.log";
    my $status = run_mockbuild(
        $log, "$tmp/repo-dep-build",
        '--xcat-source', $source,
        '--build-genesis',
        '--genesis-release', $built,
        '--genesis-work-dir', "$tmp/oe-work",
    );
    is($status, 0, 'mockbuild-all.pl can build the OpenEmbedded Genesis packages')
        or diag(slurp($log));
    for my $architecture (@arches) {
        my $name = rpm_package_name($architecture);
        ok(-f "$built/rpm/$name-$version-$release.noarch.rpm",
           "it built the $architecture package");
    }
    my $verified = run_capture(
        "$tmp/verify.log",
        "$repo_root/genesis-openembedded/verify-release",
        '--complete', '--format', 'rpm', $built,
    );
    is($verified, 0, 'the release it built is complete by verify-release')
        or diag(slurp("$tmp/verify.log"));
}

# 2. A build that publishes a dep tree with no OpenEmbedded packages must FAIL. This is the half
#    that passed before: the [common] requirement was reached only when --genesis-release was set.
{
    my $repo_dep = "$tmp/repo-dep-empty";
    make_path($repo_dep);
    my $log = "$tmp/empty.log";
    my $status = run_mockbuild($log, $repo_dep);
    isnt($status, 0, 'a dep build with no OpenEmbedded packages fails its completeness gate');
    like(slurp($log), qr/MISSING xCAT-genesis-openembedded-/,
         'and names the packages it is missing');
}

# 3. With the release published into the shared repository, the same build passes.
{
    my $repo_dep = "$tmp/repo-dep-full";
    make_path($repo_dep);
    my $log = "$tmp/full.log";
    my $status = run_mockbuild(
        $log, $repo_dep,
        '--xcat-source', $source,
        '--genesis-release', $built,
    );
    is($status, 0, 'the same build passes once the release is published into common')
        or diag(slurp($log));
    ok(-d "$repo_dep/common", 'and the shared Genesis repository exists');

    # 4. Removal proof. Take one architecture back out and the gate must fail, naming it. A gate
    #    that has never been shown to fail is not a gate.
    my $victim = rpm_package_name($arches[-1]);
    my @gone = glob("$repo_dep/common/$victim-*.rpm");
    ok(scalar(@gone) > 0, "the published repository carries $victim to remove");
    unlink(@gone);
    my $after = run_mockbuild("$tmp/removed.log", $repo_dep);
    isnt($after, 0, "removing $victim fails the next build");
    like(slurp("$tmp/removed.log"), qr/MISSING \Q$victim\E/,
         'and the failure names the architecture that went missing');
}

done_testing();
