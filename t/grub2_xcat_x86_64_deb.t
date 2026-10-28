#!/usr/bin/perl
# The apt package of grub2-xcat must ship the x86_64 network loader, as the rpm does.
#
# DHCPv6 names boot/grub2/grub2.x86_64 as the boot file of a grub2 node, and a bootfile-url is
# written only for a grub2 node, so without this file an x86_64 node on an Ubuntu management node
# cannot network boot over IPv6 at all. The firmware takes its reserved address, finds no boot
# file and reports "PXE-E21: Remote boot cancelled".
#
# The module list is held equal to the one in grub2-xcat.spec: the two packagings build the same
# image from the same modules, and a module added to one and not the other is a drift this catches.
use strict;
use warnings;
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use Test::More;

my $pkg = "$RealBin/../grub2-xcat";
plan skip_all => "grub2-xcat packaging not found" unless -d "$pkg/debian";

# The modules of a grub-mkimage call, in the order the file names them.
sub mkimage_modules {
    my ($path, $target) = @_;
    open(my $fh, '<', $path) or die "Cannot read $path: $!";
    local $/;
    my $text = <$fh>;
    close($fh);
    # The invocation runs to the first semicolon or blank line; line continuations are joined.
    return unless $text =~ /grub2?-mkimage\s+-O\s+\Q$target\E\b(.*?)(?:;|\n\s*\n)/s;
    my $args = $1;
    $args =~ s/\\\n/ /g;
    $args =~ s/#[^\n]*//g;
    # Drop the options and their values, leaving the module names.
    my @words = split ' ', $args;
    my @mods;
    while (@words) {
        my $word = shift @words;
        # An rpm macro stands in for an option and its value, as %{grub2_x64_moddir} does
        # for the openSUSE module directory. It names no module.
        next if $word =~ /^%\{/;
        if ($word =~ /^-/) { shift @words unless $word eq '--'; next; }
        push @mods, $word;
    }
    return @mods;
}

my @deb_modules  = mkimage_modules("$pkg/debian/rules",      'x86_64-efi');
my @spec_modules = mkimage_modules("$pkg/grub2-xcat.spec",   'x86_64-efi');

ok( scalar(@spec_modules) > 10, 'the spec builds the x86_64 image from a module list' )
  or diag("spec modules: @spec_modules");
ok( scalar(@deb_modules) > 10, 'debian/rules builds the x86_64 image from a module list' )
  or diag("deb modules: @deb_modules");
is_deeply( \@deb_modules, \@spec_modules,
    'the apt and rpm packagings build the x86_64 image from the same modules' );

# The prefix is what makes the image find the configuration nodeset writes. The distro image
# carries the distro prefix and never looks in boot/grub2.
my $rules = do { open(my $fh, '<', "$pkg/debian/rules") or die $!; local $/; <$fh> };
like( $rules, qr{grub-mkimage\s+-O\s+x86_64-efi[^;]*-p\s+/boot/grub2},
    'the apt image carries the /boot/grub2 prefix' );

# Build dependencies: the tool and the module tree it reads.
my $control = do { open(my $fh, '<', "$pkg/debian/control") or die $!; local $/; <$fh> };
my ($builddeps) = $control =~ /^Build-Depends:\s*(.*)$/m;
like( $builddeps, qr/\bgrub-common\b/,   'grub-common provides grub-mkimage' );
like( $builddeps, qr/\bgrub-efi-amd64-bin\b/, 'grub-efi-amd64-bin provides the x86_64-efi modules' );

# The name the firmware asks for.
my $postinst = do { open(my $fh, '<', "$pkg/debian/postinst") or die $!; local $/; <$fh> };
like( $postinst, qr{x86_64-efi/grubx64\.efi\s+/tftpboot/boot/grub2/grub2\.x86_64},
    'postinst installs the image as grub2.x86_64' );

# The modules must actually produce an image. Either spelling of the tool will do; the module
# names are the same for both, which is why one list can serve both packagings.
my ($mkimage) = grep { my $t = $_; grep { -x "$_/$t" } split /:/, ( $ENV{PATH} || '' ) }
  qw(grub2-mkimage grub-mkimage);
my ($moddir) = grep { -f "$_/moddep.lst" }
  qw(/usr/lib/grub/x86_64-efi /usr/share/grub2/x86_64-efi);
if ( $mkimage && $moddir && @deb_modules ) {
    my $out = tempdir( CLEANUP => 1 ) . '/grubx64.efi';
    my $rc  = system( $mkimage, '-O', 'x86_64-efi', '-p', '/boot/grub2', '-o', $out, @deb_modules );
    if ( $rc == 0 && -s $out ) {
        open( my $fh, '<', $out ) or die $!;
        binmode($fh);
        read( $fh, my $head, 2 );
        close($fh);
        is( $head, 'MZ', "$mkimage builds a PE image from the module list" );
    } else {
        fail("$mkimage could not build an image from the module list");
        diag("exit $rc");
    }
} else {
    diag( 'no x86_64-efi module tree on this host, so the module list was checked but not built' );
}

done_testing();
