#!/usr/bin/env perl
# mockbuild-all.pl removes the work directory, and with it each mock --resultdir, when the target
# ends. The package log directory is the only copy of mock's build.log and root.log that survives,
# so a FAILED build must copy them there too.
use strict;
use warnings;

use FindBin qw($RealBin);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;

use lib $RealBin, "$RealBin/..", "$RealBin/lib";
use MockBuildUtils qw(record_package_result);

sub mock_tree {
    my ($root) = @_;
    my %dirs = map { $_ => "$root/work/$_" } qw(rpm srpm restamp-srpm);
    make_path(values %dirs, "$root/log");
    write_text("$dirs{rpm}/build.log", "t/basic.t .. Failed 1/9\n");
    write_text("$dirs{rpm}/root.log",  "buildroot installed\n");
    write_text("$dirs{srpm}/build.log", "Wrote: perl-Expect.src.rpm\n");
    return ("$root/log",
            [[$dirs{rpm}, ''], [$dirs{srpm}, 'srpm-'], [$dirs{'restamp-srpm'}, 'restamp-']]);
}

{
    my ($log, $dirs) = mock_tree(tempdir(CLEANUP => 1));
    my $status = record_package_result(ok => 0, summary => 'perl-Expect FAIL mock rc=1',
        error => 'mock rc=1', log_dir => $log, result_dirs => $dirs);
    is($status, 'FAIL', 'a failed build records FAIL');
    is(read_text("$log/status.txt"), "FAIL\tperl-Expect FAIL mock rc=1\n", 'status.txt names the failure');
    is(read_text("$log/error.txt"), "mock rc=1\n", 'error.txt holds the error');
    ok(-f "$log/build.log" && read_text("$log/build.log") =~ /Failed 1\/9/,
        'a failed build keeps the --rebuild build.log');
    ok(-f "$log/root.log", 'a failed build keeps the --rebuild root.log');
    ok(-f "$log/srpm-build.log", 'a failed build keeps the --buildsrpm build.log');
    ok(!-e "$log/restamp-build.log", 'a log mock did not write is not invented');
}

{
    my ($log, $dirs) = mock_tree(tempdir(CLEANUP => 1));
    my $status = record_package_result(ok => 1, summary => 'perl-Expect PASS main_rpm=x.rpm',
        error => '', log_dir => $log, result_dirs => $dirs);
    is($status, 'PASS', 'a passing build records PASS');
    ok(!-e "$log/error.txt", 'a passing build writes no error.txt');
}

done_testing;
