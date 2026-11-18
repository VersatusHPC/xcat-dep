#!/usr/bin/env perl
# GCC 15, on openSUSE Leap 16.0, compiles C as C23 by default, where true is a keyword.
# conserver 8.2.1 declares a variable named true, so its build stops with
#
#   group.c:5039:9: error: expected identifier or '(' before 'true'
#
# The spec pins the language to gnu11, which every targeted GCC knows (4.8 on Leap 42.3 included).
# A spec is a packaging manifest: the text is the contract.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

my $path = "$RealBin/../conserver/conserver.spec";
open my $fh, '<', $path or die "cannot read $path: $!\n";
my $spec = do { local $/; <$fh> };
close $fh;

my ($build) = $spec =~ /^%build\n(.*?)^%install/ms;
ok(defined $build, 'conserver.spec has a %build section') or done_testing(), exit;
like($build, qr/^export CFLAGS="\$\{?RPM_OPT_FLAGS\}? -std=gnu11"$/m,
    'conserver is compiled as gnu11, not the C23 default of GCC 15');
like($build, qr/export CFLAGS.*\n(?:.*\n)*?%configure/,
    '... before %configure reads CFLAGS');

done_testing();
