#!/usr/bin/perl
# xnba-undi is built with the HOST's rpmbuild rather than in a mock chroot, so it inherits the
# host's payload compressor. Current rpm writes zstd, and rpm 4.11 -- what the SLE 12 family
# ships -- cannot unpack it. The install dies part way through the transaction with
#
#   error: unpacking of archive failed: cpio: Bad magic
#
# after other packages are already installed, and names compression nowhere. The chroot-built
# packages are unaffected: their chroot's rpm writes lzma, which rpm 4.11 reads.
use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Find;

my $root = dirname(__FILE__) . '/..';

# Any build that shells out to the host's rpmbuild must pin the payload.
my @hostbuilders;
# no_chdir is load-bearing: without it File::Find chdirs into each directory, the relative
# $File::Find::name stops resolving, every open fails, and the search silently finds nothing --
# a test that passes by measuring an empty list.
find({ no_chdir => 1, wanted => sub {
    return unless $File::Find::name =~ m{/mockbuild\.pl$};
    open my $fh, '<', $File::Find::name or die "cannot read $File::Find::name: $!";
    my $t = do { local $/; <$fh> };
    close $fh;
    push @hostbuilders, [$File::Find::name, $t] if $t =~ /'rpmbuild',/;
} }, $root);

ok(scalar(@hostbuilders) >= 1, 'at least one package is built with the host rpmbuild')
    or diag('if this is now zero, the pin below may no longer be needed');

for my $h (@hostbuilders) {
    my ($path, $text) = @{$h};
    (my $rel = $path) =~ s{^\Q$root\E/?}{};
    like($text, qr/_binary_payload w\d+\.xzdio/,
        "$rel pins the payload to xz, which rpm 4.11 can unpack");
    unlike($text, qr/_binary_payload \S*zstdio/,
        "$rel never pins zstd");
}

done_testing();
