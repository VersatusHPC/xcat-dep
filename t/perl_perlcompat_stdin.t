#!/usr/bin/env perl
# EPEL 8 perl-generators-epel ships perlcompat.req, a dependency generator that never reads its
# stdin. rpm 4.14 runs it once per perl file, writes the file name to its stdin and does not ignore
# SIGPIPE, so rpmbuild dies by SIGPIPE when the generator exits before that write.
# The perl mock configuration for an EL8 target replaces the generator with one that reads its
# stdin to EOF first. EL9 and later define the generator as a Lua macro, with no child process.
use strict;
use warnings;

use FindBin qw($RealBin);
use Test::More;

use lib $RealBin, "$RealBin/..", "$RealBin/../lib";
use MockBuildUtils ();

my $text = MockBuildUtils->can('perl_mock_cfg_text')
    or die "MockBuildUtils has no perl_mock_cfg_text\n";

my $macro = qr/^config_opts\['macros'\]\['%__perlcompat_requires'\] = (.+)$/m;

for my $cfg (qw(alma+epel-8-ppc64le alma+epel-8-x86_64 rocky+epel-8-x86_64)) {
    my $out = $text->($cfg, '1700000000', undef);
    my ($value) = $out =~ $macro;
    ok(defined $value, "$cfg redefines the perlcompat generator");
    next unless defined $value;
    like($value, qr/cat >\/dev\/null;/, '... which reads its stdin to EOF');
    like($value, qr/cat >\/dev\/null;.*\bexec "\$0" "\$\@"/,
        '... before it starts the packaged generator');
    like($value, qr/%\{_rpmconfigdir\}\/perlcompat\.req %\{perl_version\}/,
        '... with the arguments the EPEL macro gives it');
    like($out, qr{^include\('/etc/mock/\Q$cfg\E\.cfg'\)$}m, '... and still includes its base');
}

for my $cfg (qw(alma+epel-9-x86_64 alma+epel-10-ppc64le rocky+epel-10-x86_64
                openeuler-24.03-ppc64le)) {
    unlike($text->($cfg, '1700000000', undef), $macro,
        "$cfg keeps its own perlcompat generator");
}
unlike($text->('opensuse-leap-15.6-x86_64', '1700000000', '/work/compat/repo'), $macro,
    'opensuse-leap-15.6-x86_64 keeps its own perlcompat generator');

done_testing();
