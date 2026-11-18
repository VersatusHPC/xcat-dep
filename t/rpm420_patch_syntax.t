#!/usr/bin/env perl
# rpm 4.20, on openSUSE Leap 16.0, refuses two forms that older rpm accepts:
#
#   error: %patchN is obsolete, use %patch N (or %patch -P N): %patch1  -p1
#   error: ...spec: line 44: Invalid patch number 0 form is only understood by rpm >= 4.18 ...
#
# The second comes from a comment: rpm expands macros in a spec comment, so "%patch 0" written
# in a comment is parsed as a patch directive. "%patch -P N" works on every rpm the dep build
# targets, 4.11 on Leap 42.3 included.
#
# A spec is a packaging manifest: the text is the contract. Each spec below is one the dep build
# feeds to mock.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

my @specs = qw(
    conserver/conserver.spec
    goconserver/goconserver.spec
    grub2-xcat/grub2-xcat.spec
    ipmitool/ipmitool.spec
    ipxe-xcat/ipxe-xcat.spec
    syslinux/syslinux-xcat.spec
    uftp/uftp.spec
    xnba/xnba-undi.spec
    perl-HTTP-Async/perl-HTTP-Async.spec
    perl-IO-Stty/perl-IO-Stty.spec
    perl-Net-HTTPS-NB/perl-Net-HTTPS-NB.spec
);

for my $spec (@specs) {
    my $path = "$RealBin/../$spec";
    ok(-f $path, "$spec exists") or next;
    open my $fh, '<', $path or die "cannot read $path: $!\n";
    my (@numbered, @in_comment);
    while (my $line = <$fh>) {
        push @numbered,   $. if $line =~ /^\s*%patch\d/;
        push @in_comment, $. if $line =~ /^\s*#.*(?<!%)%patch\b/;
    }
    close $fh;
    is("@numbered",   '', "$spec uses no %patchN directive");
    is("@in_comment", '', "$spec names no unescaped %patch in a comment");
}

done_testing();
