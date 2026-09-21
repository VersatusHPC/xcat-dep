#!/usr/bin/env perl
use strict;
use warnings;

use FindBin qw($RealBin);
use File::Temp qw(tempdir);
use Test::More;

# xCAT carries "Requires: xcat-console-backend" because it cannot name one backend: goconserver
# needs a Go toolchain the SLE 12 family does not have, that family builds conserver-xcat instead,
# and rpm 4.11 there rejects a boolean dependency ("Dependency tokens must begin with alpha-numeric,
# '_' or '/'"). Both backends must declare the capability.
#
# The release number carries as much weight as the Provides. dnf resolves on the capability and
# cannot tell two builds of one NVRA apart, so the build that declares the capability must sort
# above the build that was published without it.
#
# goconserver/goconserver.spec is a placeholder. The spec that reaches rpmbuild is written by
# goconserver/mockbuild.pl, in one heredoc per build path, so this test renders those and reads
# what rpm makes of them. rpmspec is the parser rpm itself uses, which a match against the text
# of the spec is not.

# The release each package was published under before it declared the capability.
my %published_without_capability = (
    'conserver-xcat' => 1,
    'goconserver'    => 4,
);

my $root = "$RealBin/..";
my $tmp  = tempdir(CLEANUP => 1);

sub rpmspec_query {
    my ($spec, @args) = @_;
    open my $fh, '-|', 'rpmspec', '-q', @args, $spec
        or die "cannot run rpmspec on $spec: $!\n";
    my @out = <$fh>;
    close $fh or die "rpmspec failed to parse $spec\n";
    chomp @out;
    return @out;
}

sub check_backend {
    my ($label, $spec, $pkg) = @_;

    my @provides = rpmspec_query($spec, '--provides');
    ok( scalar(grep { /^xcat-console-backend\b/ } @provides),
        "$label provides xcat-console-backend" )
        or diag("provides: " . join(', ', @provides));

    my ($release) = map { (split ' ', $_)[1] }
                    grep { (split ' ', $_)[0] eq $pkg }
                    rpmspec_query($spec, '--qf', '%{name} %{release}\n');
    ok( defined $release, "$label builds $pkg" ) or return;

    my ($number) = $release =~ /^(\d+)/;
    cmp_ok( $number, '>', $published_without_capability{$pkg},
        "$label release $release sorts above the $pkg published without the capability" );
}

check_backend('conserver.spec', "$root/conserver/conserver.spec", 'conserver-xcat');

my $generator = "$root/goconserver/mockbuild.pl";
open my $src_fh, '<', $generator or die "cannot read $generator: $!\n";
my $source = do { local $/; <$src_fh> };
close $src_fh;

my @specs = $source =~ /write_file\(\s*\$spec_file\s*,\s*<<"SPEC"\);\n(.*?)\nSPEC\n/gs;
die "the spec heredocs in goconserver/mockbuild.pl no longer match -- has it been rewritten?\n"
    if @specs < 2;

foreach my $i (0 .. $#specs) {
    my $text = $specs[$i];
    $text =~ s/\$release_suffix//g;
    $text =~ s/\$version/0.3.3/g;
    $text =~ s/\$rel\b/10/g;
    $text =~ s/\$arch\b/x86_64/g;

    my $path = "$tmp/goconserver-$i.spec";
    open my $out, '>', $path or die "cannot write $path: $!\n";
    print {$out} $text;
    close $out;

    check_backend("mockbuild.pl spec $i", $path, 'goconserver');
}

done_testing;
