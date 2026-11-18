use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";
use XCAT::BuildUtils qw(run_with_work_dir target_run_id work_dir_path write_binary);

my $tmp = tempdir(CLEANUP => 1);

is(target_run_id('alma+epel-10-x86_64', '20261118-1052'), 'alma+epel-10-x86_64-20261118-1052',
    'the target is folded into the run id');
is(target_run_id('alma+epel-10-x86_64', 'alma+epel-10-x86_64-7'), 'alma+epel-10-x86_64-7',
    'a run id that already names the target is kept');
is(work_dir_path('alma+epel-10-x86_64-7'), '/tmp/mockbuild-all-alma+epel-10-x86_64-7',
    'the work dir is under /tmp by default');
is(work_dir_path('r1', $tmp), "$tmp/mockbuild-all-r1", 'the work dir follows the given tmp root');

# A build fills the work dir and writes its tarball under the output root.
sub fake_build {
    my ($work, $output, $fail) = @_;
    return sub {
        make_path("$work/perl-list6", "$work/genesis-home/rpmbuild/SOURCES", $output);
        write_binary("$work/perl-list6/status.txt", "ok\n");
        write_binary("$output/mockbuild-all-t-r.tar.gz", "tar");
        die "build failed\n" if $fail;
        return 'info';
    };
}

{
    my $work   = work_dir_path('ok', $tmp);
    my $output = "$tmp/out-ok";
    my $ret = run_with_work_dir(dir => $work, keep => 0, run => fake_build($work, $output, 0));
    is($ret, 'info', 'the build result is returned');
    ok(!-e $work, 'a successful build removes its work dir');
    ok(-f "$output/mockbuild-all-t-r.tar.gz", 'the output tarball stays');
}

{
    my $work   = work_dir_path('fail', $tmp);
    my $output = "$tmp/out-fail";
    my $ok = eval { run_with_work_dir(dir => $work, keep => 0, run => fake_build($work, $output, 1)); 1 };
    ok(!$ok, 'a failed build still fails');
    is($@, "build failed\n", 'the build error reaches the caller unchanged');
    ok(!-e $work, 'a failed build removes its work dir');
    ok(-f "$output/mockbuild-all-t-r.tar.gz", 'the output tarball stays after a failure');
}

{
    my $work   = work_dir_path('keep', $tmp);
    my $output = "$tmp/out-keep";
    run_with_work_dir(dir => $work, keep => 1, run => fake_build($work, $output, 0));
    ok(-f "$work/perl-list6/status.txt", 'keep leaves the work dir in place');
    my $ok = eval { run_with_work_dir(dir => $work, keep => 1, run => fake_build($work, $output, 1)); 1 };
    ok(!$ok && -d "$work/genesis-home", 'keep leaves the work dir in place after a failure');
}

{
    my $work = work_dir_path('none', $tmp);
    my $ret  = run_with_work_dir(dir => $work, keep => 0, run => sub { 'dry' });
    is($ret, 'dry', 'a build that writes no work dir succeeds');
    ok(!-e $work, 'no work dir is created');
}

done_testing();
