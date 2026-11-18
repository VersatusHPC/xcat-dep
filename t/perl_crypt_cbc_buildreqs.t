#!/usr/bin/env perl
# openSUSE Leap 16.0 ships no Crypt::Blowfish and no Crypt::Blowfish_PP, and the perl-Crypt-CBC
# build stops on "No matching package to install: 'perl(Crypt::Blowfish)'". Both modules serve
# the test suite only, so a Leap 16 build does not ask for them. Fedora already drops them on EL.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

my $rpmspec = qx(command -v rpmspec 2>/dev/null);
chomp($rpmspec);
plan skip_all => 'rpmspec is required' unless $rpmspec && -x $rpmspec;

my $spec = "$RealBin/../perl-Crypt-CBC/perl-Crypt-CBC.spec";
for my $build (['Leap 16', 'suse_version 1600', 0], ['Leap 15', 'suse_version 1500', 1]) {
    my ($name, $define, $want) = @$build;
    my @br = qx($rpmspec -q --buildrequires --undefine rhel --undefine suse_version --define '$define' $spec 2>/dev/null);
    ok(scalar @br, "rpmspec reads perl-Crypt-CBC.spec for $name");
    is(scalar(grep { /^perl\(Crypt::Blowfish(?:_PP)?\)/ } @br), $want ? 2 : 0,
        "perl-Crypt-CBC built for $name " . ($want ? 'asks' : 'does not ask') . ' for the Blowfish test modules');
}

done_testing();
