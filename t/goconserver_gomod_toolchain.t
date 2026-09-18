#!/usr/bin/perl
# The pinned goconserver module graph must compile with the OLDEST Go any xcat-dep target ships.
# Leap 15.6 resolves BuildRequires: golang to go1.25-1.25.8, and goconserver/mockbuild.pl builds
# with GOTOOLCHAIN=local, so a go.mod directive above that Go stops the SUSE build before the
# compiler starts.
#
# This drives the build the SUSE target performs: clone the pinned goconserver ref, remove the etcd
# backend, overlay goconserver/gomod/go.{mod,sum}, then run the two go build commands of the spec
# with GOTOOLCHAIN=local. It asserts on the artifacts -- both binaries exist, are ELF, and run --
# not on the text of go.mod.
#
# GOCONSERVER_MIN_GO names that oldest Go. The workflow sets it and installs exactly that toolchain.
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use File::Path qw(make_path);

my $min_go = $ENV{GOCONSERVER_MIN_GO};
plan skip_all => 'GOCONSERVER_MIN_GO is unset: this test needs the oldest target toolchain installed'
    if !defined $min_go || $min_go eq '';

my $repo = "$RealBin/..";

# The toolchain must BE the floor. A newer Go satisfies any directive, so it would pass with or
# without the fix and measure nothing.
my $reported = `go version 2>&1` || '';
BAIL_OUT("go is not on PATH: $reported") if $? != 0;
my ($have) = $reported =~ /\bgo(\d+\.\d+(?:\.\d+)?)\b/;
BAIL_OUT("cannot read a version out of: $reported") if !defined $have;
BAIL_OUT("GOCONSERVER_MIN_GO is $min_go but go reports $have; the test would not measure the pin")
    if $have ne $min_go;

# One pin, one place. mockbuild-all.pl holds the canonical ref the builders pass to mockbuild.pl.
my $mba = do { local (@ARGV, $/) = ("$repo/mockbuild-all.pl"); <> };
my ($ref) = $mba =~ /\$GOCONSERVER_REF\s*=\s*'([0-9a-f]{40})'/;
BAIL_OUT('mockbuild-all.pl no longer defines $GOCONSERVER_REF as a 40-char sha') if !defined $ref;

my $tmp = tempdir(CLEANUP => 1);
my $src = "$tmp/src";
make_path($src);

# Everything Go writes stays under the scratch tree.
local $ENV{GOPATH}       = "$tmp/gopath";
local $ENV{GOCACHE}      = "$tmp/gocache";
local $ENV{GOMODCACHE}   = "$tmp/gomodcache";
local $ENV{GOFLAGS}      = '-mod=mod';
local $ENV{GOTOOLCHAIN}  = 'local';
local $ENV{CGO_ENABLED}  = '0';

my $clone_log = "$tmp/clone.log";
for my $cmd ("git init -q '$src'",
             "git -C '$src' remote add origin https://github.com/xcat2/goconserver.git",
             "git -C '$src' fetch -q --depth 1 origin '$ref'",
             "git -C '$src' checkout -q FETCH_HEAD") {
    system("$cmd >>'$clone_log' 2>&1") == 0
        or BAIL_OUT("cannot stage the pinned goconserver source ($cmd): " . slurp($clone_log));
}

# The builders drop the etcd storage backend; its coreos/bbolt dependency is not in the pinned graph.
system("rm -rf '$src/storage/etcd.go' '$src/storage/etcd'");

for my $f (qw(go.mod go.sum)) {
    copy("$repo/goconserver/gomod/$f", "$src/$f")
        or BAIL_OUT("cannot overlay goconserver/gomod/$f: $!");
}

# The two go build commands of the %build section of goconserver/mockbuild.pl.
my %built;
for my $t (['goconserver', 'goconserver.go'], ['congo', 'cmd/congo.go']) {
    my ($out, $main) = @{$t};
    my $log = "$tmp/build-$out.log";
    my $rc  = system("cd '$src' && go build -trimpath -buildvcs=false " .
                     "-ldflags '-X main.Version=0.3.3' -o '$tmp/$out' '$main' >'$log' 2>&1");
    ok($rc == 0, "go $min_go builds $out from the pinned go.mod")
        or diag(slurp($log));
    $built{$out} = ($rc == 0);
}

# The artifact, not the exit status alone: an ELF that the kernel actually runs.
for my $out (qw(goconserver congo)) {
  SKIP: {
        skip "$out was not built", 3 if !$built{$out};
        ok(-s "$tmp/$out" > 1_000_000, "$out is a linked binary, not a stub");
        open(my $fh, '<:raw', "$tmp/$out") or die "open $out: $!";
        read($fh, my $magic, 4);
        close $fh;
        is($magic, "\x7fELF", "$out is an ELF executable");
        is(system("'$tmp/$out' --help >/dev/null 2>&1"), 0, "$out --help runs and exits 0");
    }
}

done_testing();

sub slurp {
    my ($p) = @_;
    open(my $fh, '<', $p) or return "(no $p)";
    local $/;
    my $c = <$fh>;
    close $fh;
    return $c;
}
