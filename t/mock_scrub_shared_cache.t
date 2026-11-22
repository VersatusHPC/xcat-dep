#!/usr/bin/env perl
# xcat-dep-build-el10-x86_64 failed on conserver-xcat with mock rc=32:
#
#   /bin/mount -n -o bind /var/cache/mock/alma+epel-10-x86_64-bootstrap/dnf_cache .../root/var/cache/dnf
#
# mock --scrub=bootstrap deletes <cache_topdir>/<cfg>-bootstrap as well as the build's own
# bootstrap chroot. That cache is keyed by the configuration name, not by --uniqueext, so the
# el9 build's goconserver scrub of alma+epel-10-x86_64 deleted the cache that the concurrent el10
# build was binding. The scrub must name the same chroots and leave the shared cache alone.
use strict;
use warnings;

use FindBin qw($RealBin);
use File::Temp qw(tempdir);
use File::Slurper qw(read_text);
use Text::ParseWords qw(shellwords);
use Test::More;

use lib $RealBin, "$RealBin/..", "$RealBin/../lib";
use MockBuildUtils ();

my $scratch = tempdir(CLEANUP => 1);

sub plan_for {
    my (%args) = @_;
    my @argv = shellwords(MockBuildUtils::mock_scrub_command(%args, scratch => $scratch));
    my %opt;
    for my $i (0 .. $#argv - 1) {
        $opt{ $argv[$i] } = $argv[ $i + 1 ] if $argv[$i] =~ /\A-(?:r|-uniqueext)\z/;
    }
    my $text = (-f ($opt{'-r'} // '')) ? read_text($opt{'-r'}) : '';
    my ($topdir) = $text =~ /config_opts\[['"]cache_topdir['"]\]\s*=\s*['"]([^'"]+)['"]/;
    return { argv => \@argv, cfg => $opt{'-r'}, uniqueext => $opt{'--uniqueext'},
             text => $text, cache_topdir => $topdir };
}

my $p = plan_for(cfg => 'alma+epel-10-x86_64', uniqueext => 'goconserver-180');

is($p->{argv}[0], 'mock', 'the scrub is a mock command');
ok((grep { $_ eq '--scrub=chroot' } @{ $p->{argv} }), 'the build chroot is removed');
ok((grep { $_ eq '--scrub=bootstrap' } @{ $p->{argv} }),
    'the per-uniqueext bootstrap chroot is removed, so /var/lib/mock does not leak');
is($p->{uniqueext}, 'goconserver-180', 'the scrub names the build uniqueext');

like($p->{cfg} // '', qr{\A\Q$scratch\E/.+\.cfg\z},
    'mock reads a configuration file in the build scratch directory, not the shared one');
like($p->{text}, qr{include\(['"]/etc/mock/alma\+epel-10-x86_64\.cfg['"]\)},
    'that configuration includes the real one, so mock resolves the same root names');
ok(defined $p->{cache_topdir}, 'that configuration sets cache_topdir');
like($p->{cache_topdir} // '', qr{\A\Q$scratch\E/},
    'the cache mock deletes for --scrub=bootstrap is in the scratch directory');
isnt($p->{cache_topdir} // '/var/cache/mock', '/var/cache/mock', 'the shared cache is not the one deleted');

my $q = plan_for(cfg => 'alma+epel-10-x86_64', uniqueext => 'conserver-xcat-186');
isnt($q->{cache_topdir} // '', $p->{cache_topdir} // '',
    'two builds of one configuration delete two different private caches');

my $g = plan_for(cfg => 'xCAT-genesis-base-alma+epel-9-x86_64');
is($g->{uniqueext}, undef, 'a build with no uniqueext scrubs with none');
like($g->{text}, qr{include\(['"]/etc/mock/xCAT-genesis-base-alma\+epel-9-x86_64\.cfg['"]\)},
    'a configuration name resolves to /etc/mock');

my $f = plan_for(cfg => "$scratch/mock-deterministic.cfg", uniqueext => 'x');
like($f->{text}, qr{include\(['"]\Q$scratch\E/mock-deterministic\.cfg['"]\)},
    'a configuration path is included as it is');

done_testing();
