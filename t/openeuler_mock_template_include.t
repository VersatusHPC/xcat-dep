#!/usr/bin/perl
# A mock configuration that includes a template mock cannot find builds nothing.
#
# mock-core-configs names its openEuler templates by release only -- openeuler-20.03.tpl,
# openeuler-22.03.tpl, openeuler-24.03.tpl -- and each one already carries the releasever of the
# newest service pack. A cfg that spells the service pack into the template name asks for a file
# that exists in no mock package, and `mock --print-root-path` answers
# "Could not find included config file" before a single package is built.
#
# openeuler-20.03sp4-x86_64.cfg and openeuler-22.03sp4-x86_64.cfg both did that, so every build step
# of both targets failed at the mock config check.
#
# The rule is checked from the repository alone: a base template name carries the release and never
# the service pack, and it agrees with the release the cfg declares.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Basename qw(basename);
use File::Slurper qw(read_text);

my @cfg = sort glob("$RealBin/../mock-configs/openeuler-*.cfg");

# A positive control. An empty glob -- a renamed directory, a moved file -- would make every loop
# below vacuous and this file would pass having read nothing.
cmp_ok(scalar @cfg, '>=', 2, 'mock-configs/ carries openEuler configurations')
    or die "no mock-configs/openeuler-*.cfg under $RealBin/.. -- this test reads nothing\n";

# The templates this repository ships. Anything else must come from mock-core-configs.
my %shipped = map { basename($_) => 1 } glob("$RealBin/../mock-configs/templates/*.tpl");
ok($shipped{'openeuler-lts-xcat.tpl'}, 'the xCAT openEuler template is shipped here');

for my $path (@cfg) {
    my $name = basename($path);
    my $text = read_text($path);

    my ($release) = $text =~ /openeuler_repository_release'\]\s*=\s*'([^']+)'/;
    ok(defined $release, "$name: declares openeuler_repository_release") or next;

    my @inc = $text =~ /include\('templates\/([^']+)'\)/g;
    cmp_ok(scalar @inc, '>=', 1, "$name: includes at least one template");

    # The release as mock spells a template name: the major and minor, never the service pack.
    my ($majmin) = $release =~ /\A(\d+\.\d+)/;
    ok(defined $majmin, "$name: its release starts with a major.minor ($release)") or next;

    for my $t (@inc) {
        next if $shipped{$t};          # shipped beside the cfg, so it always resolves
        is($t, "openeuler-$majmin.tpl",
           "$name: its mock-core-configs template is openeuler-$majmin.tpl, not '$t'");
    }
}

done_testing();
