#!/usr/bin/perl
# goconserver/goconserver.service is the unit that every rpm target ships. The oldest target
# systemd is 228 (openSUSE Leap 42.3). It logs "Unknown lvalue" for a key it does not know and
# ignores the key, so a newer key silently stops doing its work there.
use strict;
use warnings;
use Test::More;
use File::Slurper qw(read_lines);
use FindBin qw($RealBin);

my $unit = "$RealBin/../goconserver/goconserver.service";

# Keys that systemd 228 accepts in each section of a service unit (systemd.unit(5),
# systemd.service(5), systemd.exec(5) of v228). Only the keys a goconserver unit could use.
my %known = (
    Unit => { map { $_ => 1 } qw(Description Documentation After Before Wants Requires
                                 Conflicts BindsTo PartOf ConditionPathExists) },
    Service => { map { $_ => 1 } qw(Type ExecStart ExecStartPre ExecStartPost ExecStop
                                    ExecReload Restart RestartSec TimeoutStartSec
                                    TimeoutStopSec KillMode User Group Environment
                                    EnvironmentFile WorkingDirectory RuntimeDirectory
                                    LimitNOFILE PIDFile SuccessExitStatus) },
    Install => { map { $_ => 1 } qw(WantedBy RequiredBy Alias Also) },
);

my ($section, %seen);
for my $line (read_lines($unit)) {
    next if $line =~ /^\s*(#|;|$)/;
    if ($line =~ /^\[(\w+)\]$/) { $section = $1; next; }
    my ($key, $value) = $line =~ /^(\w+)=(.*)$/ or die "$unit: cannot parse '$line'\n";
    die "$unit: '$key' is outside a section\n" unless defined $section;
    ok($known{$section} && $known{$section}{$key}, "[$section] $key is known to systemd 228");
    push @{ $seen{$key} }, $value;
}

is_deeply($seen{ExecStart}, ['/usr/bin/goconserver'], 'the unit starts /usr/bin/goconserver');

# server.conf names /var/lib/goconserver as the console datadir. goconserver does not create it.
ok(grep({ m{^\S*mkdir -p /var/lib/goconserver$} } @{ $seen{ExecStartPre} || [] }),
   'the unit creates the goconserver datadir before the start');

done_testing();
