#!/usr/bin/perl
# debs-manifest.conf pins the FULL Debian version -- [epoch:]upstream[-revision] -- so a
# debian/changelog bump that only moves the revision makes every pin for that package stale.
# sbuild-all.pl reports that at the END of a build, after every chroot has run. This test compares
# the two files in the checkout, so a pull request shows the mismatch before a build starts.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/..";
use BuildUtils qw(read_manifest version_matches);

my $root     = "$RealBin/..";
my $manifest = "$root/debs-manifest.conf";

# Binary package name -> the source directory whose debian/changelog sets its version. sbuild builds
# each source once and takes the version from the top changelog entry, unchanged.
my %CHANGELOG_OF = (
    'conserver-xcat' => 'conserver',
    'elilo-xcat'     => 'elilo',
    'grub2-xcat'     => 'grub2-xcat',
    'ipmitool-xcat'  => 'ipmitool',
    'syslinux-xcat'  => 'syslinux',
    'xnba-undi'      => 'xnba',
);

# Every xcat-genesis-* package is converted from an xcat-core artifact, so its version walks with
# the paired core and no file in this checkout states it. Their pins are globs by design.
my $NOT_OWNED_HERE = qr/\Axcat-genesis-/;

# top_changelog_version: the version dpkg-buildpackage takes from a debian/changelog.
sub top_changelog_version {
    my ($dir) = @_;
    my $path = "$root/$dir/debian/changelog";
    open my $fh, '<', $path or BAIL_OUT("cannot read $path: $!");
    my $first = <$fh>;
    close $fh;
    BAIL_OUT("$path does not start with a changelog entry")
      unless defined $first && $first =~ /^\S+\s+\(([^)]+)\)/;
    return $1;
}

# goconserver_build_version: goconserver/sbuild.pl stamps the revision with the run timestamp
# (snap<YYYYMMDDHHMM>), so the upstream half is the only part a pin can fix. Read it from the
# builder and give it a stamp, then check that against the pin the way sbuild-all.pl would.
sub goconserver_build_version {
    my $path = "$root/goconserver/sbuild.pl";
    open my $fh, '<', $path or BAIL_OUT("cannot read $path: $!");
    my $text = do { local $/; <$fh> };
    close $fh;
    BAIL_OUT("goconserver/sbuild.pl no longer sets VERSION=<upstream>; update this test")
      unless $text =~ /^VERSION=(\S+)$/m;
    return "$1-snap202601010000";
}

my %manifest = read_manifest($manifest);
BAIL_OUT("$manifest has no sections") unless keys %manifest;

my %checked;
for my $target (sort keys %manifest) {
    for my $pkg (sort keys %{ $manifest{$target} }) {
        my $pin = $manifest{$target}{$pkg};
        next if $pkg =~ $NOT_OWNED_HERE;
        my $built =
            $pkg eq 'goconserver'         ? goconserver_build_version()
          : $CHANGELOG_OF{$pkg}           ? top_changelog_version($CHANGELOG_OF{$pkg})
          :                                 undef;
        if (!defined $built) {
            fail("[$target] $pkg: no source of truth known for its version -- add it to "
                  . '%CHANGELOG_OF in t/manifest_pins.t, or to the not-owned-here list');
            next;
        }
        $checked{$pkg} = 1;
        ok(version_matches($built, $pin),
            "[$target] $pkg: source builds $built, manifest pins $pin");
    }
}

# The pins are worth nothing if a package quietly stops being compared. Name what was covered.
is_deeply(
    [sort keys %checked],
    [sort ('goconserver', keys %CHANGELOG_OF)],
    'every package whose version this checkout owns was compared against its pin');

done_testing();
