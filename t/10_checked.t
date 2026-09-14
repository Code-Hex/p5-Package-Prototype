use strict;
use warnings;
use Test2::V0;
BEGIN { plan skip_all => 'Checked requires Perl 5.16' if $] < 5.016 }
use File::Temp qw(tempfile);
use IPC::Open3;
use Symbol qw(gensym);
use Cwd qw(abs_path);

# perl -c runs compilation hooks but does not execute the program body.
sub compile_only {
    my ($source) = @_;
    return _invoke_perl($source, '-c');
}

# Run the body as well, to exercise validation deferred until runtime.
sub execute_program {
    my ($source) = @_;
    return _invoke_perl($source);
}

sub _invoke_perl {
    my ($source, @switches) = @_;
    my ($fh, $file) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$fh} "use strict; use warnings;\nuse Types::Standard qw(Int Str ArrayRef HashRef);\nuse Package::Prototype::Checked integer => Int, text => Str, integers => ArrayRef[Int], table => HashRef[ArrayRef[Int]];\n", $source;
    close $fh;
    my $err = gensym;
    my $pid = open3(undef, my $out, $err, $^X,
        '-I'.abs_path('blib/lib'), '-I'.abs_path('blib/arch'),
        @switches, $file);
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    waitpid($pid, 0);
    return ($?, $stdout . $stderr);
}

for my $expression ('42', '"42"', '-3', '"bad"', '3.5') {
    my ($status, $output) = compile_only("integer($expression);");
    if ($expression =~ /bad|3\.5/) {
        isnt($status, 0, "reject $expression at compile time");
        like($output, qr/Compile-time type error at .*\.pl line 4/, 'source location');
    } else {
        is($status, 0, "accept $expression");
    }
}
my ($status, $output) = compile_only('my $v = "bad"; integer($v);');
is($status, 0, 'unknown variable deferred');
($status, $output) = execute_program('my $v = "bad"; integer($v);');
isnt($status, 0, 'unknown variable rejected at runtime');
like($output, qr/Type check integer failed/, 'runtime diagnostic');
($status, $output) = compile_only('integer(1); die "BODY EXECUTED";');
is($status, 0, 'compilation does not execute body');
unlike($output, qr/BODY EXECUTED/, 'body untouched');
for my $source ('integer()', 'integer(1, 2)') {
    ($status, $output) = compile_only($source);
    isnt($status, 0, 'static arity violation');
}
($status, $output) = compile_only('my $f = \&integer; $f->("bad");');
is($status, 0, 'indirect call deferred');
($status, $output) = execute_program('my $f = \&integer; $f->("bad");');
isnt($status, 0, 'indirect call runtime checked');
($status, $output) = execute_program('&integer("bad");');
isnt($status, 0, 'ampersand call runtime checked');
($status, $output) = execute_program('print integer(42), text("hello");');
is($status, 0, 'runtime success');
is($output, '42hello', 'identity functions preserve values');
for my $source ('integer(undef)', 'integers([1, "bad"])',
                'table({a => [1, "bad"]})') {
    ($status, $output) = compile_only($source);
    isnt($status, 0, 'reject constant structure');
    like($output, qr/Compile-time type error/, 'static diagnostic');
}
for my $source ('integer(1 + 2)', 'integers([])', 'integers([1, 2])',
                'table({a => [1, 2]})') {
    ($status, $output) = compile_only($source);
    is($status, 0, 'accept constant structure or folded expression');
}
for my $source ('my $v = "bad"; integers([1, $v]);',
                'sub input { die "BODY EXECUTED" }; integers([input()]);',
                'my @v = ("bad"); integers([@v]);') {
    ($status, $output) = compile_only($source);
    is($status, 0, 'dynamic structures deferred');
    unlike($output, qr/BODY EXECUTED/, 'no speculative evaluation');
    ($status, $output) = execute_program($source);
    isnt($status, 0, 'dynamic structure fails at runtime');
}
done_testing;
