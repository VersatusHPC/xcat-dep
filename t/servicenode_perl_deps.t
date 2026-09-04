#!/usr/bin/perl
# A service node reaches only the OS install tree (BaseOS + AppStream, from copycds) plus the
# xcat-core and xcat-dep repositories. It never reaches CRB or EPEL. xCAT-server -- which xCATsn
# requires -- declares perl dependencies that EL keeps in CRB or in EPEL, so `dnf install xCATsn`
# on a service node cannot resolve unless xcat-dep carries them.
#
# The %SN_PERL_DEPS set below is the list of those packages, per EL release. It was derived on
# 2026-09-04 by resolving xCATsn against a service node repo set:
#   dnf --releasever=<el> --installroot=<empty> install xCATsn \
#       --repofrompath=baseos,<alma>/<el>/BaseOS/<arch>/os/ \
#       --repofrompath=appstream,<alma>/<el>/AppStream/<arch>/os/ \
#       --repofrompath=core,<xcat-core repo> --repofrompath=dep,<xcat-dep repo>
# and reading the "nothing provides" lines. x86_64 and ppc64le give the same set on every release.
#
# This test asserts three things the build needs to be true together:
#   1. packages-manifest.conf carries every EL target section, and each one lists exactly the perl
#      packages recorded here. mockbuild-all.pl builds ONLY what a section names, so a name
#      dropped from a section is a package the repository stops carrying.
#   2. every section covers the service node set for its release;
#   3. mockbuild-perl-packages.pl knows how to build each listed name -- it dies with
#      "Unknown package in --packages" otherwise, and its %meta table is the only place that
#      maps a name to a spec or a source rpm in this tree.
#
# The two expected tables below are deliberate second copies of the manifest. The plan is counted
# from them, not from the manifest, so a deleted section or a deleted package makes this file run
# fewer tests than it planned and go red, instead of asserting less and staying green.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/..";
use MockBuildUtils qw(read_manifest);

my $repo_root = "$RealBin/..";

# Per EL release: the perl packages a service node cannot get from BaseOS + AppStream.
my %SN_PERL_DEPS = (
    8 => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Crypt-SSLeay perl-Digest-SHA1
             perl-Expect perl-HTML-Form perl-IO-Tty perl-Net-Telnet)],
    9 => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Crypt-SSLeay
             perl-Expect perl-HTML-Form perl-IO-Tty perl-Net-Telnet)],
    10 => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Digest-SHA1
              perl-Expect perl-HTML-Form perl-IO-Tty perl-Net-DNS)],
);

# The EL target sections, and the perl packages each one must list. riscv64 has no EPEL, so it
# also builds what the other EL10 targets take from EPEL at build time.
my %EXPECTED_PERL = (
    'alma+epel-8-x86_64'    => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Crypt-SSLeay
                                   perl-Digest-SHA1 perl-Expect perl-HTML-Form perl-HTTP-Async
                                   perl-IO-Stty perl-IO-Tty perl-Net-HTTPS-NB perl-Net-Telnet)],
    'alma+epel-8-ppc64le'   => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Crypt-SSLeay
                                   perl-Digest-SHA1 perl-Expect perl-HTML-Form perl-HTTP-Async
                                   perl-IO-Stty perl-IO-Tty perl-Net-HTTPS-NB perl-Net-Telnet)],
    'alma+epel-9-x86_64'    => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Crypt-SSLeay
                                   perl-Expect perl-HTML-Form perl-HTTP-Async perl-IO-Stty
                                   perl-IO-Tty perl-Net-HTTPS-NB perl-Net-Telnet perl-Sys-Virt)],
    'alma+epel-9-ppc64le'   => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Crypt-SSLeay
                                   perl-Expect perl-HTML-Form perl-HTTP-Async perl-IO-Stty
                                   perl-IO-Tty perl-Net-HTTPS-NB perl-Net-Telnet perl-Sys-Virt)],
    'alma+epel-10-x86_64'   => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Crypt-SSLeay
                                   perl-Digest-SHA1 perl-Expect perl-HTML-Form perl-HTTP-Async
                                   perl-IO-Stty perl-IO-Tty perl-Net-DNS perl-Net-HTTPS-NB
                                   perl-Net-Telnet perl-Sys-Virt)],
    'alma+epel-10-ppc64le'  => [qw(perl-Crypt-CBC perl-Crypt-Rijndael perl-Crypt-SSLeay
                                   perl-Digest-SHA1 perl-Expect perl-HTML-Form perl-HTTP-Async
                                   perl-IO-Stty perl-IO-Tty perl-Net-DNS perl-Net-HTTPS-NB
                                   perl-Net-Telnet perl-Sys-Virt)],
    'rocky-10-riscv64-xcat' => [qw(perl-Crypt-Blowfish perl-Crypt-CBC perl-Crypt-Rijndael
                                   perl-Crypt-SSLeay perl-Digest-SHA1 perl-Expect perl-HTML-Form
                                   perl-HTTP-Async perl-IO-Stty perl-IO-Tty perl-Mail-Sender
                                   perl-Net-DNS perl-Net-HTTPS-NB perl-Net-IP perl-Net-Telnet
                                   perl-Path-Class perl-Sys-Virt)],
);

my @EXPECTED_TARGETS = sort keys %EXPECTED_PERL;
my %EXPECTED_PKGS    = map { $_ => 1 } map { @$_ } values %EXPECTED_PERL;

# Counted from the tables above, never from the file under test: 1 section-list assertion,
# 2 per target, 3 per distinct perl package.
plan tests => 1 + 2 * scalar(@EXPECTED_TARGETS) + 3 * scalar(keys %EXPECTED_PKGS);

my %manifest = read_manifest("$repo_root/packages-manifest.conf");
BAIL_OUT('packages-manifest.conf holds no sections') if !keys %manifest;

# The builder's package table is a lexical in a script that refuses to run as non-root, so lift
# the literal out and evaluate it. A changed shape must fail here, not silently test nothing.
sub builder_meta {
    my ($path) = @_;
    open my $fh, '<', $path or BAIL_OUT("cannot read $path: $!");
    my $src = do { local $/; <$fh> };
    close $fh;
    my ($literal) = $src =~ /^my \s+ %meta \s* = \s* \( (.*?) ^\); $/msx;
    BAIL_OUT("cannot extract %meta from $path") if !defined $literal;
    my %meta = eval "($literal)";    ## no critic (ProhibitStringyEval)
    BAIL_OUT("cannot evaluate %meta from $path: $@") if $@;
    BAIL_OUT("%meta from $path is empty") if !keys %meta;
    return %meta;
}

my %meta = builder_meta("$repo_root/mockbuild-perl-packages.pl");

my @el_targets = sort grep { /-(\d+)-/ } keys %manifest;
is_deeply(\@el_targets, \@EXPECTED_TARGETS,
    'packages-manifest.conf carries exactly the expected EL target sections');

for my $target (@EXPECTED_TARGETS) {
    my @listed = sort grep { /^perl-/ } keys %{ $manifest{$target} || {} };
    is_deeply(\@listed, $EXPECTED_PERL{$target},
        "$target: lists exactly the expected perl packages");

    my ($release) = $target =~ /-(\d+)-/;
    my @missing = grep { !exists $manifest{$target}{$_} } @{ $SN_PERL_DEPS{$release} };
    is_deeply(\@missing, [],
        "$target: covers every perl package a service node cannot reach");
}

# Every perl package a target asks for must be buildable from this tree.
for my $pkg (sort keys %EXPECTED_PKGS) {
    my $entry = $meta{$pkg};
    ok(defined $entry, "$pkg: mockbuild-perl-packages.pl can build it");
    ok(($entry && -d $entry->{pkg_dir}) ? 1 : 0, "$pkg: its source directory exists");
    if ($entry && ($entry->{mode} || '') eq 'spec') {
        ok(-f $entry->{spec}, "$pkg: its spec file exists");
    }
    else {
        my @srpms = grep { -f $_ } map { glob $_ } @{ ($entry || {})->{srpm_globs} || [] };
        ok(scalar(@srpms), "$pkg: a source rpm to rebuild exists");
    }
}
