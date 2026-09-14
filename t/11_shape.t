use strict;
use warnings;
use Test2::V0;
BEGIN { plan skip_all => 'Shape requires Perl 5.22' if $] < 5.022 }
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
    print {$fh} <<'PRELUDE', $source;
use strict;
use warnings;
use Types::Standard qw(Int ArrayRef);
use Package::Prototype::Shape { mode => 'checked' }, Counter => {
    count     => [],
    set_count => [Int],
    values    => [ArrayRef[Int]],
};
my $value = 0;
my Counter $counter = Counter->create(
    count     => sub { $value },
    set_count => sub { $value = $_[1] },
    values    => sub { $_[1] },
);
PRELUDE
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
for my $source ('$counter->set_count("bad");', '$counter->set_count(undef);',
                '$counter->values([1,"bad"]);', '$counter->set_count();',
                '$counter->count(1);', 'sub later { $counter->set_count("bad") }') {
    my ($status, $output) = compile_only($source);
    isnt($status, 0, 'annotated receiver rejects bad literal or arity');
    like($output, qr/Compile-time (?:type|arity) error.*\.pl line 15/s, 'diagnostic has source');
}
for my $source ('$counter->set_count(1);', '$counter->values([1,2]);',
                'my $v = "bad"; $counter->set_count($v);',
                'my @v = (1); $counter->set_count(@v);',
                'my $alias = $counter; $alias->set_count("bad");',
                'my $method = "set_count"; $counter->$method("bad");',
                '{ my $counter; $counter->set_count("bad"); }',
                '$counter->other_method("anything");') {
    my ($status, $output) = compile_only($source);
    is($status, 0, 'accept valid or explicitly deferred call');
}
for my $source ('my $v = "bad"; $counter->set_count($v);',
                'my @v = ("bad"); $counter->set_count(@v);',
                'my @v = (1,2); $counter->set_count(@v);',
                'my $alias = $counter; $alias->set_count("bad");',
                'my $method = "set_count"; $counter->$method("bad");') {
    my ($status, $output) = execute_program($source);
    isnt($status, 0, 'runtime wrapper checks deferred call');
}
my ($status, $output) = execute_program('my $v = "bad"; eval { $counter->set_count($v) }; print $counter->count;');
is($status, 0, 'failed validation caught');
is($output, '0', 'method body did not mutate value');
($status, $output) = execute_program('$counter->set_count(42); print $counter->count;');
is($status, 0, 'valid runtime call');
is($output, '42', 'method returns original result');
($status, $output) = compile_only('die "BODY EXECUTED";');
is($status, 0, 'no runtime execution under perl -c');
unlike($output, qr/BODY EXECUTED/, 'no body side effect');
($status, $output) = execute_program(<<'SOURCE');
use Package::Prototype::Shape { mode => 'checked' }, Context => { result => [] };
my Context $c = Context->create(
    result => sub {
        if (!defined wantarray) {
            print 'V';
            return;
        }
        return wantarray ? (1, 2) : 'S';
    }
);
print scalar($c->result);
print join('', $c->result);
$c->result;
SOURCE
is($status, 0, 'context wrapper runs');
is($output, 'S12V', 'scalar list and void context preserved');
($status, $output) = execute_program(<<'SOURCE');
use feature 'signatures';
no warnings 'experimental::signatures';
use Package::Prototype::Shape { mode => 'checked' }, Pair => { sum => [Int, Int] };
my Pair $p = Pair->create(sum => sub ($self, $x, $y) { $x + $y });
use constant TWO => (1, 2);
print $p->sum(TWO);
SOURCE
is($status, 0, 'native signatures and constant list expansion');
is($output, '3', 'arguments preserved through wrapper');
($status, $output) = compile_only(<<'SOURCE');
package Outer;
use Types::Standard qw(Int);
use Package::Prototype::Shape { mode => 'checked' }, Local => { value => [Int] };
my Outer::Local $local;
$local->value("bad");
SOURCE
isnt($status, 0, 'qualified shape annotation checked');
like($output, qr/Type check Outer::Local::value failed/, 'qualified diagnostic');
done_testing;
