#!/usr/bin/perl
# The publisher-RPM payload scan: what it accepts, and what it refuses.
#
# reject_elf_payload used to treat the exit status of rpm2cpio as the verdict on the payload. On
# rpm 4.19 rpm2cpio writes the whole payload and still exits 1, with nothing on stderr, for a
# package whose sha256, every digest and the publisher signature all verify. Measured on
# openEuler 24.03's perl-CGI-4.57-1.oe2403.noarch.rpm: 413728 bytes of valid cpio on stdout, exit 1,
# empty stderr, while rpm2archive exits 0 on the same file. So openeuler-24.03-ppc64le failed with
# "rpm2cpio failed" on an input it had just read correctly.
#
# The decision now lives in scan_cpio_for_elf, which reads a stream and answers. The streams here
# are built in Perl, so this runs no rpm2cpio and no rpm.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use XCAT::NativeInputs qw(scan_cpio_for_elf);

# One newc cpio member. The field order is the one scan_cpio_for_elf reads: filesize is field 7 and
# namesize is field 12 after the 6-byte magic.
sub member {
    my ($name, $data) = @_;
    my $n = length($name) + 1;
    my $rec = '070701'
            . join('', map { sprintf '%08X', $_ }
                   (1, 0100644, 0, 0, 1, 0, length($data), 0, 0, 0, 0, $n, 0))
            . "$name\0";
    $rec .= "\0" x ((4 - (110 + $n) % 4) % 4);
    $rec .= $data;
    $rec .= "\0" x ((4 - length($data) % 4) % 4);
    return $rec;
}
sub trailer {
    my $n = length('TRAILER!!!') + 1;
    my $rec = '070701' . join('', map { sprintf '%08X', $_ } (0) x 13);
    substr($rec, 6 + 11 * 8, 8) = sprintf '%08X', $n;
    $rec .= "TRAILER!!!\0";
    $rec .= "\0" x ((4 - (110 + $n) % 4) % 4);
    return $rec;
}
sub scan {
    my ($bytes) = @_;
    open my $fh, '<', \$bytes or die "in-memory open: $!";
    binmode $fh;
    my $r = eval { scan_cpio_for_elf($fh) };
    # Distinguish a TRUE verdict from a falsy one. A helper that answered "OK" for any defined
    # return would pass for a scan that reached the trailer and then reported it had not.
    return $@ unless defined $r;
    return $r ? 'OK' : "FALSY VERDICT: '$r'";
}

# A positive control. If the stream builder above does not produce something the scanner accepts,
# every refusal below would pass for the wrong reason.
is(scan(member('./usr/share/perl5/CGI.pm', "package CGI;\n1;\n") . trailer()), 'OK',
   'a noarch payload of plain files is accepted');

# The exit status is gone, so the thing that must still fail is a payload that really is wrong.
like(scan(member('./usr/bin/thing', "\x7fELF\x02\x01\x01\x00") . trailer()),
     qr/ELF payload in publisher noarch RPM: \.\/usr\/bin\/thing/,
     'an ELF member is refused, and the message names the file');

# A stream that stops before its trailer is what a genuinely truncated download looks like. This is
# the case the exit status was standing in for.
like(scan(substr(member('./usr/share/doc/README', 'x' x 4096) . trailer(), 0, 200)),
     qr/Truncated RPM payload/, 'a stream that ends before its trailer is refused');

like(scan(member('./a', 'x') . trailer() . 'trailing junk'),
     qr/Unexpected data after RPM cpio trailer/, 'data after the trailer is refused');

# At least 110 bytes, or the scanner reports truncation before it can judge the magic.
like(scan('N' x 200), qr/Invalid RPM cpio header/, 'a stream that is not cpio is refused');

done_testing();
