#!/usr/bin/perl
# sign_and_index_repo on the published openEuler POWER cell: a publisher RPM keeps its pinned bytes
# up to the signing step, and then carries the build key, because the deploy gate accepts only
# that key. The private prerequisite repository keeps the publisher signature.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/..", "$RealBin/../lib";
use File::Temp qw(tempdir);
use File::Basename qw(basename);
use File::Slurper qw(write_text);
use MockBuildUtils qw(sign_and_index_repo);
use XCAT::NativeInputs;
use XCAT::BuildUtils;

my $publisher_base = 'perl-CGI-4.57-1.oe2403.noarch.rpm';
my $built_base     = 'perl-IO-Tty-1.20-1.oe2403.ppc64le.rpm';
my %name_of = ($publisher_base => 'perl-CGI', $built_base => 'perl-IO-Tty');
my $plan = {
    publisher_key => '/catalog/openEuler.asc',
    outputs => {'perl-CGI' => 'perl-CGI', 'perl-IO-Tty' => 'perl-IO-Tty'},
    nodes => {
        'perl-CGI'    => {type => 'publisher', sha256 => 'pinned-publisher-digest'},
        'perl-IO-Tty' => {type => 'srpm'},
    },
};

sub fixture {
    my $dir = tempdir(CLEANUP => 1);
    write_text("$dir/$_", '') for ($publisher_base, $built_base);
    return $dir;
}

# Return the run commands of one sign_and_index_repo call, or the error it died with.
sub sign_commands {
    my ($dir, $digest, %extra) = @_;
    my @commands;
    no warnings 'redefine';
    local *XCAT::NativeInputs::rpm_identity = sub { return {name => $name_of{basename($_[0])}} };
    local *XCAT::BuildUtils::digest_file = sub { return $digest };
    my $ok = eval {
        sign_and_index_repo($dir, $plan, gpg_sign => 1, gpg_key_name => 'xCAT Signing Key',
            gpg_program => '/usr/bin/gpg', run => sub { push @commands, $_[0] }, %extra);
        1;
    };
    return $ok ? (\@commands, '') : (\@commands, $@);
}

sub index_of {
    my ($commands, $re) = @_;
    for my $i (0 .. $#$commands) { return $i if $commands->[$i] =~ $re }
    return -1;
}

{
    my $dir = fixture();
    my ($commands, $error) = sign_commands($dir, 'pinned-publisher-digest', resign_publishers => 1);
    is($error, '', 'the published cell signs an unchanged publisher RPM');
    my $resign = index_of($commands, qr/^rpmsign .*--resign .*\Q$publisher_base\E/);
    ok($resign >= 0, 'the publisher RPM is re-signed with the build key, which replaces its distro signature');
    like($commands->[$resign] // '', qr/%_gpg_name xCAT Signing Key/, 'the re-sign uses the configured build key');
    unlike($commands->[$resign] // '', qr/\Q$built_base\E/, 'the re-sign names only the publisher RPM');
    my $index = index_of($commands, qr/^createrepo_c /);
    ok($resign >= 0 && $index > $resign, 'the publisher RPM is re-signed before createrepo_c indexes it');
    ok(index_of($commands, qr/^rpmsign .*--addsign .*\Q$built_base\E/) >= 0, 'the built RPM is still signed');
    is(index_of($commands, qr/openEuler\.asc/), -1,
        'repomd.xml.key does not export the distro key when no RPM carries its signature');
}

{
    my $dir = fixture();
    my ($commands, $error) = sign_commands($dir, 'changed', resign_publishers => 1);
    like($error, qr/\APublisher input changed before signing: .*\Q$publisher_base\E\n\z/,
        'a publisher RPM that differs from its pinned digest stops the re-sign');
    is_deeply($commands, [], 'a changed publisher RPM stops before any signing or index command');
}

{
    my $dir = fixture();
    my ($commands, $error) = sign_commands($dir, 'pinned-publisher-digest');
    is($error, '', 'the private prerequisite repository signs with the default options');
    is(index_of($commands, qr/^rpmsign .*\Q$publisher_base\E/), -1,
        'the private prerequisite repository keeps the publisher signature');
    ok(index_of($commands, qr/^cat .*openEuler\.asc.*repomd\.xml\.key/) >= 0,
        'the private prerequisite repository exports the distro key for the publisher RPMs');
}

done_testing();
