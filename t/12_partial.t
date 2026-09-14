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
    print {$fh} <<'PRELUDE', $source;
use strict;
use warnings;
use Types::Standard qw(Int Str ArrayRef Dict Tuple Optional Slurpy);
use Package::Prototype::Checked { mode => 'always' },
    ints => ArrayRef[Int],
    record => Dict[id => Int, name => Str],
    pair => Tuple[Int, Str],
    nested => Dict[rows => ArrayRef[Tuple[Int, Str]]],
    opt_record => Dict[id => Int, name => Optional[Str]],
    opt_pair => Tuple[Int, Optional[Str]],
    union => (ArrayRef[Int] | ArrayRef[Str]),
    slurpy => Tuple[Int, Slurpy[ArrayRef[Str]]];
my $x = 1;
my $name = 'Alice';
PRELUDE
    close $fh;
    my $err = gensym;
    my $pid = open3(undef, my $out, $err, $^X,
        '-I'.abs_path('blib/lib'), '-I'.abs_path('blib/arch'), @switches, $file);
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    waitpid($pid, 0);
    return ($?, $stdout . $stderr);
}

for my $source (
    'ints([$x, "bad"]);',
    'record({id => "bad", name => $name});',
    'pair(["bad", $name]);',
    'nested({rows => [[$x, $name], ["bad", $name]]});',
    'opt_record({id => "bad", name => $name});',
    'opt_pair(["bad", $name]);',
    'record({name => $name});',
    'record({id => $x, name => $name, extra => 1});',
    'pair([$x]);',
    'pair([$x, $name, 3]);',
    'record({id => $x, name => $name, id => "bad"});',
) {
    my ($status, $output) = compile_only($source);
    isnt($status, 0, "compile rejects: $source");
    like($output, qr/Compile-time type error at .*\.pl line 15/, 'call site diagnostic');
}
for my $source (
    'ints([$x, 2]);',
    'record({id => $x, name => "Alice"});',
    'pair([$x, "Alice"]);',
    'nested({rows => [[$x, $name], [2, $name]]});',
    'opt_record({id => $x});',
    'opt_pair([$x]);',
    'record({id => "bad", name => $name, id => $x});',
) {
    my ($status, $output) = compile_only($source);
    is($status, 0, "compile accepts: $source");
    ($status, $output) = execute_program($source);
    is($status, 0, 'same expression is valid at runtime');
}
for my $source (
    'my @v = ($x); ints([@v, "bad"]);',
    'my $key = "id"; record({id => "bad", name => $name, $key => 2});',
    'sub value { die "BODY EXECUTED" }; ints([value(), "bad"]);',
    'union([$x, "bad"]);',
    'slurpy([$x, "Alice"]);',
) {
    my ($status, $output) = compile_only($source);
    is($status, 0, "deferred without evaluation: $source");
    unlike($output, qr/BODY EXECUTED/, 'no argument evaluation');
}
my ($status, $output) = execute_program('my @v = ($x); ints([@v, "bad"]);');
isnt($status, 0, 'deferred array expansion still checked at runtime');
($status, $output) = execute_program('my $key = "id"; record({id => "bad", name => $name, $key => 2});');
is($status, 0, 'unknown later key can overwrite known invalid value');
($status, $output) = compile_only('record({id => "bad", name => $name}); die "BODY EXECUTED";');
isnt($status, 0, 'partial error occurs during compilation');
unlike($output, qr/BODY EXECUTED/, 'program body never ran');
($status, $output) = compile_only(<<'SOURCE');
BEGIN { package Custom; sub assert_valid { die 'PARTIAL VALUE PASSED' } }
use Package::Prototype::Checked { mode => 'always' }, custom => bless({}, 'Custom');
custom([$x, 'bad']);
SOURCE
is($status, 0, 'custom whole-value constraint deferred');
unlike($output, qr/PARTIAL VALUE PASSED/, 'no dummy value passed to custom constraint');
SKIP: {
    skip 'Shape requires Perl 5.22', 2 if $] < 5.022;
    ($status, $output) = compile_only(<<'SOURCE');
use Package::Prototype::Shape { mode => 'always' }, Records => { save => [Dict[id => Int, name => Str]] };
my Records $records;
$records->save({id => 'bad', name => $name});
SOURCE
    isnt($status, 0, 'typed method uses partial validator');
    like($output, qr/Type check Records::save failed/, 'method diagnostic');
}
($status, $output) = compile_only(<<'SOURCE');
use Type::Tiny;
use Package::Prototype::Checked { mode => 'always' }, custom_array => Type::Tiny->new(
    parent => ArrayRef, parameters => [Int], constraint => sub { 1 });
custom_array(['bad', $x]);
SOURCE
is($status, 0, 'custom parameter metadata does not imply standard semantics');
($status, $output) = execute_program(<<'SOURCE');
use Type::Tiny;
use Package::Prototype::Checked { mode => 'always' }, custom_array => Type::Tiny->new(
    parent => ArrayRef, parameters => [Int], constraint => sub { 1 });
custom_array(['bad', $x]);
SOURCE
is($status, 0, 'custom constraint really accepts that value');
for my $expression ('Tuple[Int, (Optional[Str])->create_child_type(constraint => sub {1})]',
                    'Dict[id => Int, name => (Optional[Str])->create_child_type(constraint => sub {1})]') {
    my $source = 'use Package::Prototype::Checked { mode => "always" }, derived => ' . $expression . ';'
        . ($expression =~ /^Tuple/ ? 'derived([$x]);' : 'derived({id => $x});');
    ($status, $output) = compile_only($source);
    is($status, 0, 'derived optional slot conservatively deferred');
    ($status, $output) = execute_program($source);
    is($status, 0, 'omitted derived optional accepted at runtime');
}
done_testing;
