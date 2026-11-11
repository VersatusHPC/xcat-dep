#!/usr/bin/perl
# A native prerequisite rebuilds a distro source RPM only as a build input. Its own %check suite
# measures nothing of xcat-dep, and the ksh timing tests in it fail at random on xcat-master-ppc.
# xcat-dep's own packages keep their %check.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/..";
use MockBuildUtils qw(source_rpm_mock_argv);

my @native = source_rpm_mock_argv('/work/mock.cfg', 'u1',
    {name => 'ksh', native_prerequisite => 1});
is(scalar(grep { $_ eq '--nocheck' } @native), 1, 'a native prerequisite build passes --nocheck to mock');

my @own = source_rpm_mock_argv('/work/mock.cfg', 'u2', {name => 'elilo-xcat', srpm => '/x.src.rpm'});
is(scalar(grep { $_ eq '--nocheck' } @own), 0, 'an xcat-dep package build keeps its %check');

my @defined = source_rpm_mock_argv('/work/mock.cfg', 'u3',
    {name => 'ksh', native_prerequisite => 1, defines => ['dist .oe2403']});
is_deeply([@defined[-2, -1]], ['--define', 'dist .oe2403'], 'builder defines still reach mock');

done_testing();
