#!/usr/bin/env perl
# The powerpc-ieee1275 network loader grub2-xcat hands a ppc64le node as boot/grub2/grub2.ppc.
#
# That loader was never built by this package. grub2-res.tar.gz is the output of grub2-mknetdir
# from a RHEL7 POWER node and every file in it is dated 2014-05-21; %install only untarred it and
# %post copied powerpc-ieee1275/core.elf to grub2.ppc. The 2014 image registers net_bootp and not
# net_bootp6, so it carries no DHCPv6 client: a ppc64le node that leases over DHCPv6 reaches the
# loader and the loader cannot configure a network at all.
#
# The image is therefore generated in %build with grub2-mkimage, as the arm64-efi image is.
# grub2-ppc64le-modules is noarch, so every EL build host can produce it. The module list must be
# complete, because a self-contained image fetches no .mod at run time: a 2.12 core.elf cannot
# load a 2014 .mod, and that mismatch produces the failure being fixed.
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use Test::More;

my $spec_file = "$RealBin/../grub2-xcat/grub2-xcat.spec";
plan skip_all => "grub2-xcat packaging not found" unless -f $spec_file;

sub slurp {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "read $path: $!";
    local $/;
    return scalar <$fh>;
}

# The body of one spec section (%build, %install, %post, ...), up to the next section.
sub section {
    my ($spec, $name) = @_;
    my ($body) = $spec =~ /^%\Q$name\E[ \t]*\n(.*?)(?=^%(?:prep|build|install|check|clean|files|pre|post|preun|postun|changelog|description|package)\b|\z)/ms;
    return $body // '';
}

# The grub2-mkimage invocation for one platform, joined across its continuation lines. %build
# holds one call per platform, so the call is selected by its -O argument and not by position.
sub mkimage_command {
    my ($text, $target) = @_;
    my ($cmd) = $text =~ /^(grub2-mkimage\s+-O\s+\Q$target\E\b(?:[^\n]*\\\n)*[^\n]*)$/m;
    return unless defined $cmd;
    $cmd =~ s/\\\n/ /g;
    return $cmd;
}

# The module names of a joined grub2-mkimage call: every word that is not an option, an option
# value or an rpm macro standing in for an option (as %{grub2_ppc_moddir} does for the module
# directory openSUSE uses).
sub mkimage_modules {
    my ($cmd) = @_;
    my @words = split ' ', $cmd;
    shift @words;    # grub2-mkimage
    my @mods;
    while (@words) {
        my $word = shift @words;
        next if $word =~ /^%\{/;
        if ($word =~ /^-/) { shift @words unless $word eq '--'; next; }
        push @mods, $word;
    }
    return @mods;
}

# rpmspec -P of the spec under extra macro definitions, or undef when rpmspec is unavailable.
my $have_rpmspec = system('command -v rpmspec >/dev/null 2>&1') == 0;

sub parsed_spec {
    my (%define) = @_;
    return unless $have_rpmspec;
    my @args = map { ('--define', "$_ $define{$_}") } sort keys %define;
    # rpmspec warns about the specs' old %patchN and macros in comments; keep that out of TAP.
    open(my $save, '>&', \*STDERR) or die "dup STDERR: $!";
    open(STDERR, '>', '/dev/null') or die "mute STDERR: $!";
    my $out;
    if (open(my $fh, '-|', 'rpmspec', '-P', @args, $spec_file)) {
        local $/;
        $out = <$fh>;
        $out = undef unless close($fh);
    }
    open(STDERR, '>&', $save) or die "restore STDERR: $!";
    return $out;
}

my $spec = slurp($spec_file);

# ---- the build dependency ------------------------------------------------------------------------
like($spec, qr/^BuildRequires:\s*grub2-ppc64le-modules\s*$/m,
    'grub2-xcat BuildRequires the noarch powerpc-ieee1275 grub modules');
like($spec, qr/^BuildRequires:\s*grub2-tools\s*$/m, 'and grub2-tools, which provides grub2-mkimage');

# ---- %build generates the image ------------------------------------------------------------------
my $cmd = mkimage_command(section($spec, 'build'), 'powerpc-ieee1275');
ok(defined $cmd, '%build runs grub2-mkimage for the powerpc-ieee1275 platform') or $cmd = '';
like($cmd, qr{(?:^|\s)-p\s+/boot/grub2(?:\s|$)},
    '... with the /boot/grub2 prefix, where nodeset writes grub.cfg-01-<mac>');
like($cmd, qr{(?:^|\s)-o\s+\S*core\.elf(?:\s|$)}, '... into core.elf');

my @modules = mkimage_modules($cmd);
# net and ofnet are the network stack and the Open Firmware driver; tftp and http fetch the
# kernel; normal, configfile and search read the configuration nodeset writes; linux and elf
# boot it. Without them the image cannot do its job, whatever else it carries.
for my $mod (qw(net ofnet tftp http normal linux elf configfile search)) {
    ok((grep { $_ eq $mod } @modules), "... with the $mod module");
}
cmp_ok(scalar(@modules), '>=', 20,
    '... and a module list large enough for a self-contained image') or diag("modules: @modules");

# ---- the built image is what the package ships ---------------------------------------------------
like(section($spec, 'install'),
    qr{^install -m 0644 \S*core\.elf \$RPM_BUILD_ROOT/%\{prefix\}/powerpc-ieee1275/core\.elf$}m,
    '%install ships the built image as powerpc-ieee1275/core.elf');
like(section($spec, 'files'), qr{^%\{prefix\}/powerpc-ieee1275/$}m,
    '%files owns powerpc-ieee1275/');
like(section($spec, 'post'),
    qr{^\s*cp\s+%\{prefix\}/powerpc-ieee1275/core\.elf %\{prefix\}/grub2\.ppc$}m,
    '%post installs it as grub2.ppc');
like(section($spec, 'postun'), qr{^\s*rm %\{prefix\}/grub2\.ppc$}m, '%postun removes grub2.ppc');

# ---- the 2014 payload is retired where the image is built ----------------------------------------
# The tarball holds powerpc-ieee1275/ and nothing else, so untarring it beside a freshly built
# core.elf would put a 2.12 image next to 2014 modules. Only the targets that cannot build the
# image keep it: openSUSE packages the modules as grub2-powerpc-ieee1275, and Leap 42.3 has no
# such package at all.
SKIP: {
    skip 'rpmspec not available', 5 unless $have_rpmspec;

    my $el = parsed_spec(rhel => 10);
    ok(defined $el, 'rpmspec parses grub2-xcat.spec for EL') or $el = '';
    # rpmspec keeps the comments of the script sections, and %prep carries two commented-out
    # tar lines from the AIX era: the check has to be anchored or it matches those.
    unlike($el, qr/^\s*tar\s+(?:zxf|-xf)\s/m,
        '... and the EL build does not untar grub2-res.tar.gz');
    like($el, qr/grub2-mkimage -O powerpc-ieee1275/, '... it builds the image instead');

    my $suse = parsed_spec(suse_version => 1500);
    like($suse // '', qr/^\s*tar\s+zxf\s/m,
        'openSUSE keeps grub2-res.tar.gz: it names the module package differently');
    unlike($suse // '', qr/grub2-mkimage -O powerpc-ieee1275/,
        '... and does not build the powerpc-ieee1275 image');
}

# ---- run the spec's own command where the modules are installed ----------------------------------
# A module the grub build does not carry makes grub2-mkimage fail, so this is where the module
# list is measured rather than described.
SKIP: {
    my ($mkimage) = grep { system("command -v $_ >/dev/null 2>&1") == 0 }
                    qw(grub2-mkimage grub-mkimage);
    my ($moddir) = grep { -f "$_/moddep.lst" }
                   qw(/usr/lib/grub/powerpc-ieee1275 /usr/share/grub2/powerpc-ieee1275);
    skip 'no grub2-mkimage, or the powerpc-ieee1275 grub modules are not installed', 4
        unless $mkimage && $moddir;
    skip 'no powerpc-ieee1275 grub2-mkimage command in the spec', 4 if $cmd eq '';

    my $tmp = tempdir(CLEANUP => 1);
    my $run = $cmd;
    $run =~ s/\Agrub2-mkimage\b/$mkimage/;
    $run =~ s/(?<=\s-o\s)\S+/$tmp\/core.elf/;
    is(system("$run >/dev/null 2>&1"), 0, "the spec's grub2-mkimage command succeeds");

    my $image = '';
    if (open(my $fh, '<:raw', "$tmp/core.elf")) { local $/; $image = <$fh> // ''; }
    # grub's powerpc-ieee1275 platform is 32-bit big-endian PowerPC, at 2.12 as in 2014: ELF
    # class 1, data encoding 2, e_machine 20 (EM_PPC).
    my @ident = length($image) >= 20 ? unpack('x4 C C x12 n', $image) : (0, 0, 0);
    is_deeply(\@ident, [1, 2, 20], '... and writes a 32-bit big-endian PowerPC ELF image');
    like($image, qr{/boot/grub2\0}, '... whose embedded prefix is /boot/grub2');
    # The one string that tells a 2.12 image from the 2014 payload: DHCPv6 reached grub after it.
    like($image, qr/net_bootp6/, '... and which carries a DHCPv6 client');
}

done_testing;
