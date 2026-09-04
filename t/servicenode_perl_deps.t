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
# This test asserts two things the build needs to be true together:
#   1. packages-manifest.conf lists that set for every EL target, so mockbuild-all.pl builds it
#      into the per-EL xcat-dep repository;
#   2. mockbuild-perl-packages.pl knows how to build each listed name -- it dies with
#      "Unknown package in --packages" otherwise, and its %meta table is the only place that
#      maps a name to a spec or a source rpm in this tree.
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
BAIL_OUT('packages-manifest.conf holds no EL target sections') if !@el_targets;

for my $target (@el_targets) {
    my ($release) = $target =~ /-(\d+)-/;
    my $want = $SN_PERL_DEPS{$release};
  SKIP: {
        skip "no service node perl set recorded for el$release", 1 if !$want;
        my @missing = grep { !exists $manifest{$target}{$_} } @$want;
        is_deeply(\@missing, [],
            "$target: manifest lists every perl package a service node cannot reach");
    }
}

# Every perl package a service node needs, and every one a target already asks for, must be
# buildable from this tree.
my %asked;
for my $target (@el_targets) {
    $asked{$_} = 1 for grep { /^perl-/ } keys %{ $manifest{$target} };
}
for my $set (values %SN_PERL_DEPS) {
    $asked{$_} = 1 for @$set;
}
for my $pkg (sort keys %asked) {
    ok(exists $meta{$pkg}, "$pkg: mockbuild-perl-packages.pl can build it")
        or next;
    my $entry = $meta{$pkg};
    ok(-d $entry->{pkg_dir}, "$pkg: its source directory exists");
    if (($entry->{mode} || '') eq 'spec') {
        ok(-f $entry->{spec}, "$pkg: its spec file exists");
    }
    else {
        my @srpms = grep { -f $_ } map { glob $_ } @{ $entry->{srpm_globs} || [] };
        ok(scalar(@srpms), "$pkg: a source rpm to rebuild exists");
    }
}

done_testing();
