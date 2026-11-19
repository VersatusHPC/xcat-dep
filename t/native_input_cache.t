use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use Test::More;

use lib "$RealBin/../lib";
use XCAT::NativeInputs qw(input_cache_dir fetch_input keep_input prune_input_cache);

my $tmp = tempdir(CLEANUP => 1);
my $cache = "$tmp/cache";
my $bytes = "signed source rpm bytes\n";
my $node = {name => 'postgresql', sha256 => sha256_hex($bytes),
    url => 'https://repo.openeuler.org/openEuler-24.03-LTS/source/Packages/postgresql-15.6-1.oe2403.src.rpm'};
my $entry = "$cache/$node->{sha256}-postgresql-15.6-1.oe2403.src.rpm";

my @wget;
no warnings 'redefine';
local *XCAT::NativeInputs::run = sub {
    my @args = @_;
    die "unexpected command: @args\n" unless $args[0] eq 'wget';
    push @wget, $args[-1];
    my ($i) = grep { $args[$_] eq '-O' } 0 .. $#args;
    write_binary($args[$i + 1], $ENV{WGET_BYTES} // $bytes);
};
use warnings 'redefine';

{
    local $ENV{XCAT_NATIVE_INPUT_CACHE} = '';
    is(input_cache_dir(), undef, 'an empty XCAT_NATIVE_INPUT_CACHE turns the cache off');
}
{
    local $ENV{XCAT_NATIVE_INPUT_CACHE} = $cache;
    is(input_cache_dir(), $cache, 'XCAT_NATIVE_INPUT_CACHE names the cache');
}

is(fetch_input($node, "$tmp/a.part", $cache), 'download', 'an empty cache downloads');
is(scalar @wget, 1, 'the first build runs wget once');
keep_input($node, "$tmp/a.part", $cache);
is(read_binary($entry), $bytes, 'verified bytes are kept under their pinned SHA256');

@wget = ();
is(fetch_input($node, "$tmp/b.part", $cache), 'cache', 'the next build reads the cache');
is(read_binary("$tmp/b.part"), $bytes, 'the cached copy has the pinned bytes');
is(scalar @wget, 0, 'the next build does not contact the mirror');

write_binary($entry, "truncated");
@wget = ();
is(fetch_input($node, "$tmp/c.part", $cache), 'download', 'a corrupt cache entry is downloaded again');
ok(!-e $entry, 'the corrupt cache entry is deleted');
is(read_binary("$tmp/c.part"), $bytes, 'the build gets the downloaded bytes');

@wget = ();
is(fetch_input($node, "$tmp/d.part", undef), 'download', 'no cache always downloads');
is(scalar @wget, 1, 'no cache runs wget');

keep_input($node, "$tmp/c.part", $cache);
my $old = "$cache/" . ('0' x 64) . '-retired-1.0-1.oe2403.src.rpm';
my $part = "$entry.4242.part";
write_binary($_, 'x') for $old, $part;
my $past = time - 40 * 86400;
utime($past, $past, $old, $part);
my $recent = time - 2 * 86400;
utime($recent, $recent, $entry);
is_deeply([sort(prune_input_cache($cache, 30))], [sort($old, $part)], 'prune deletes unused entries and stale partial copies');
ok(-f $entry, 'prune keeps an entry used within the limit');

done_testing();
