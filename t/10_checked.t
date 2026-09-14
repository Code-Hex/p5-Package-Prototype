use strict;
use warnings;
use Test::More;
BEGIN { plan skip_all => 'Checked requires Perl 5.16' if $] < 5.016 }
use File::Temp qw(tempfile);
use IPC::Open3;
use Symbol qw(gensym);
use Cwd qw(abs_path);

sub run_perl {
    my ($source, $compile) = @_;
    my ($fh, $file) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$fh} "use strict; use warnings;\nuse Types::Standard qw(Int Str);\nuse Package::Prototype::Checked integer => Int, text => Str;\n", $source;
    close $fh;
    my $err = gensym;
    my $pid = open3(undef, my $out, $err, $^X,
        '-I'.abs_path('blib/lib'), '-I'.abs_path('blib/arch'),
        ($compile ? '-c' : ()), $file);
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    waitpid($pid, 0);
    return ($?, $stdout . $stderr);
}

for my $expression ('42', '"42"', '-3', '"bad"', '3.5') {
    my ($status, $output) = run_perl("integer($expression);", 1);
    if ($expression =~ /bad|3\.5/) {
        isnt($status, 0, "reject $expression at compile time");
        like($output, qr/Compile-time type error at .*\.pl line 4/, 'source location');
    } else {
        is($status, 0, "accept $expression");
    }
}
my ($status, $output) = run_perl('my $v = "bad"; integer($v);', 1);
is($status, 0, 'unknown variable deferred');
($status, $output) = run_perl('my $v = "bad"; integer($v);', 0);
isnt($status, 0, 'unknown variable rejected at runtime');
like($output, qr/Type check integer failed/, 'runtime diagnostic');
($status, $output) = run_perl('integer(1); die "BODY EXECUTED";', 1);
is($status, 0, 'compilation does not execute body');
unlike($output, qr/BODY EXECUTED/, 'body untouched');
for my $source ('integer()', 'integer(1, 2)') {
    ($status, $output) = run_perl($source, 1);
    isnt($status, 0, 'static arity violation');
}
($status, $output) = run_perl('my $f = \&integer; $f->("bad");', 1);
is($status, 0, 'indirect call deferred');
($status, $output) = run_perl('my $f = \&integer; $f->("bad");', 0);
isnt($status, 0, 'indirect call runtime checked');
($status, $output) = run_perl('&integer("bad");', 0);
isnt($status, 0, 'ampersand call runtime checked');
($status, $output) = run_perl('print integer(42), text("hello");', 0);
is($status, 0, 'runtime success');
is($output, '42hello', 'identity functions preserve values');
done_testing;
