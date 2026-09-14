use strict;
use warnings;
use Test2::V0;
BEGIN { plan skip_all => 'Typed requires Perl 5.16' if $] < 5.016 }
use File::Temp qw(tempfile);
use IPC::Open3;
use Symbol qw(gensym);
use Cwd qw(abs_path);

sub compile_only { return _invoke_perl($_[0], '-c') }
sub execute_program { return _invoke_perl($_[0]) }

sub _invoke_perl {
    my ($source, @switches) = @_;
    my ($fh, $file) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$fh} "use strict; use warnings;\n", $source;
    close $fh;
    my $err = gensym;
    my $pid = open3(undef, my $out, $err, $^X,
        '-I'.abs_path('blib/lib'), '-I'.abs_path('blib/arch'), @switches, $file);
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    waitpid($pid, 0);
    return ($?, $stdout . $stderr);
}

my $typed_source = <<'SOURCE';
use Types::Standard qw(Int ArrayRef Dict Tuple);
use Package::Prototype::Typed
    integer => Int, ints => ArrayRef[Int], record => Dict[id => Int], pair => Tuple[Int, Int];
my $input = 'bad';
SOURCE
for my $call ('integer("bad")', 'ints([$input, "bad"])',
              'record({id => "bad"})', 'pair([$input, "bad"])') {
    my ($status, $output) = compile_only($typed_source . "$call;");
    isnt $status, 0, "$call rejected by perl -c";
    like $output, qr/Compile-time type error/, 'type diagnostic';
    ($status, $output) = execute_program($typed_source . "$call; print qq(reached\\n);");
    is $status, 0, "$call runs without validation";
    like $output, qr/reached/, 'body executes';
}
my ($status, $output) = compile_only($typed_source . 'integer($input);');
is $status, 0, 'unknown scalar remains unchecked';

my $counted = <<'SOURCE';
BEGIN {
    package CountingType;
    our $calls = 0;
    sub assert_valid { ++$calls }
}
use Package::Prototype::Typed {}, value => bless({}, 'CountingType');
BEGIN { my $x = 'dynamic'; value($x) }
CHECK { print "checks=$CountingType::calls\n" }
value(42);
for (1..100) { value($_) }
die 'validation module loaded' if exists $INC{'Package/Prototype/_Validation.pm'};
print "runtime=$CountingType::calls\n";
SOURCE
($status, $output) = execute_program($counted);
is $status, 0, 'ordinary execution does not load validation module';
like $output, qr/checks=0\nruntime=0/, 'no validation during startup, BEGIN, or repeated calls';
($status, $output) = compile_only($counted);
is $status, 0, 'counting type accepts literal during perl -c';
like $output, qr/checks=1/, 'only the known literal is validated';

for my $options ('{mode => "typo"}', '{mode => "checked"}', '{mode => undef}', '{other => 1}') {
    ($status, $output) = compile_only("use Package::Prototype::Typed $options;");
    isnt $status, 0, "invalid options rejected: $options";
    like $output, qr/(?:Expected mode|Unknown check option)/, 'option diagnostic';
}
for my $reverse (0, 1) {
    my @imports = (
        'use Package::Prototype::Typed {mode => "syntax"}, loose => Int;',
        'use Package::Prototype::Typed {mode => "always"}, strict_value => Int;',
    );
    @imports = reverse @imports if $reverse;
    my $source = "use Types::Standard qw(Int);\n" . join("\n", @imports);
    ($status, $output) = execute_program($source . 'loose("bad"); my $x = "bad"; strict_value($x);');
    isnt $status, 0, 'always runtime validation survives mixed imports';
    like $output, qr/Type check strict_value failed/, 'only always definition validates';
    ($status, $output) = execute_program($source . 'strict_value("bad");');
    like $output, qr/Compile-time type error/, 'always compilation remains active';
}

SKIP: {
    skip 'Shape requires Perl 5.22', 20 if $] < 5.022;
    my $shape = <<'SOURCE';
use Types::Standard qw(Int);
use Package::Prototype::Shape Loose => {set => [Int]};
my Loose $obj = Loose->create(set => sub { print "body=$_[1]\n"; return $_[1] });
SOURCE
    ($status, $output) = compile_only($shape . '$obj->set("bad");');
    isnt $status, 0, 'syntax shape literal rejected during perl -c';
    like $output, qr/Compile-time type error/, 'shape type diagnostic';
    ($status, $output) = execute_program($shape . '$obj->set("bad");');
    is $status, 0, 'syntax shape executes invalid literal';
    like $output, qr/body=bad/, 'original body reached';
    ($status, $output) = compile_only($shape . '$obj->set(1, 2);');
    like $output, qr/Compile-time arity error/, 'arity checked during perl -c';
    ($status, $output) = execute_program($shape . '$obj->set(1, 2);');
    is $status, 0, 'no runtime arity wrapper';
    for my $reverse (0, 1) {
        my @imports = (
            'use Package::Prototype::Shape {mode => "syntax"}, Loose => {set => [Int]};',
            'use Package::Prototype::Shape {mode => "always"}, Strict => {set => [Int]};',
        );
        @imports = reverse @imports if $reverse;
        my $source = 'use Types::Standard qw(Int);' . join("\n", @imports);
        ($status, $output) = execute_program($source . 'my Loose $o = Loose->create(set => sub {}); $o->set("bad");');
        is $status, 0, 'global always hook does not inspect syntax shape';
        ($status, $output) = execute_program($source . 'my Strict $o; $o->set("bad");');
        like $output, qr/Compile-time type error/, 'always shape still inspected';
    }
    ($status, $output) = execute_program(<<'SOURCE');
BEGIN { package CountingType; sub assert_valid { die 'VALIDATED' } }
use Package::Prototype::Shape {}, Loose => {set => [bless({}, 'CountingType')]};
my $body = sub { return wantarray ? (1, 2) : defined(wantarray) ? 'scalar' : () };
my Loose $obj = Loose->create(set => $body);
die 'wrapped' unless $obj->can('set') == $body;
die 'scalar context' unless $obj->set('bad') eq 'scalar';
my @values = $obj->set('bad');
die 'list context' unless "@values" eq '1 2';
$obj->set('bad');
die 'validation module loaded' if exists $INC{'Package/Prototype/_Validation.pm'};
print "unwrapped\n";
SOURCE
    is $status, 0, 'original CODE and caller context retained without validation';
    like $output, qr/unwrapped/, 'no validator or wrapper installed';
    for my $call ('Loose->create()', 'Loose->create(set => 1)', 'Loose->create(set => sub {}, extra => sub {})') {
        ($status, $output) = execute_program($shape . "$call;");
        isnt $status, 0, 'constructor contract retained';
        like $output, qr/(?:Missing code|Unspecified shape methods)/, 'constructor diagnostic';
    }
    ($status, $output) = compile_only('use Package::Prototype::Shape {mode => "typo"};');
    isnt $status, 0, 'shape rejects invalid mode';
    like $output, qr/Expected mode/, 'shape option diagnostic';
}
SKIP: {
    skip 'Shape requires Perl 5.22', 2 if $] < 5.022;
    ($status, $output) = execute_program(<<'SOURCE');
use Test2::V0;
use Test::LeakTrace;
use Types::Standard qw(Int);
use Package::Prototype::Shape Loose => {set => [Int]};
my $error = bless {}, 'Failure';
my Loose $obj = Loose->create(set => sub { die $error });
eval { $obj->set(1) };
ref_is $@, $error, 'exception identity';
no_leaks_ok {
    my Loose $temporary = Loose->create(set => sub { $_[1] });
    $temporary->set('bad');
} 'syntax object released';
done_testing;
SOURCE
    is $status, 0, 'syntax mode preserves exceptions and releases objects';
    like $output, qr/syntax object released/, 'leak assertion ran';
}
SKIP: {
    skip 'native signatures require Perl 5.36', 1 if $] < 5.036;
    ($status, $output) = execute_program(<<'SOURCE');
use v5.36;
use Types::Standard qw(Int);
use Package::Prototype::Shape Loose => {set => [Int]};
my Loose $obj = Loose->create(set => sub ($self, $value) { $value });
eval { $obj->set() };
die 'native signature lost' unless $@ =~ /Too few arguments/;
SOURCE
    is $status, 0, 'native signatures still enforce their own contract';
}
for my $module ('Typed', 'Shape') {
    SKIP: {
        skip 'Shape requires Perl 5.22', 2 if $module eq 'Shape' && $] < 5.022;
        for my $arguments ("{mode => 'always'}", "{mode => 'always'}, 'unpaired'") {
            my $source = "use Package::Prototype::$module ();\n" . <<'SOURCE';
BEGIN {
    no warnings 'redefine';
    *Package::Prototype::_enable_shape_checker = sub { die 'unexpected hook' };
}
SOURCE
            $source .= "BEGIN { eval { Package::Prototype::${module}->import($arguments) };"
                . ($arguments =~ /unpaired/ ? 'die "missing pair error" unless $@ =~ /Expected .* pairs/;' : 'die $@ if $@;')
                . " }\n";
            $source .= <<'SOURCE';
CHECK { die 'validation loaded' if exists $INC{'Package/Prototype/_Validation.pm'} }
SOURCE
            ($status, $output) = compile_only($source);
            is $status, 0, "$module does not prepare validation without valid pairs";
        }
    }
}
done_testing;
