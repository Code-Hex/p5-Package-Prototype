use strict;
use warnings;
use Test2::V0;
use Test::LeakTrace;
use Package::Prototype;

my $object = Package::Prototype->create(
    classname => 'Counter',
    properties => { count => {value => 0, reader => 'get_count', writer => 'set_count'} },
    methods => { explode => sub { die 'must not run' } },
);
my $description = Package::Prototype->describe($object);
is $description, {
    classname => 'Counter',
    members => {
        explode => {kind => 'method', own => 1, depth => 0},
        get_count => {kind => 'property', property => 'count', access => 'read',
            reader => 'get_count', writer => 'set_count', own => 1, depth => 0},
        set_count => {kind => 'property', property => 'count', access => 'write',
            reader => 'get_count', writer => 'set_count', own => 1, depth => 0},
    },
}, 'describe exposes declarations without calling user code';
$description->{members}{get_count}{kind} = 'corrupted';
is(Package::Prototype->describe($object)->{members}{get_count}{kind}, 'property', 'detached metadata');
$object->prototype(get_count => sub { 99 });
is(Package::Prototype->describe($object)->{members}{get_count},
    {kind => 'method', own => 1, depth => 0}, 'replacement removes stale property metadata');
is(Package::Prototype->describe($object)->{members}{set_count}{access}, 'write', 'paired accessor stays independent');

my $legacy = Package::Prototype->bless({value => [1,2], run => sub { 3 }, _private => 'hidden'});
is(Package::Prototype->describe($legacy)->{members}, {
    value => {kind => 'value', own => 1, depth => 0},
    run => {kind => 'method', own => 1, depth => 0},
}, 'legacy values and methods are described, private storage excluded');
$legacy->prototype(value => sub { 4 }, new_value => undef);
is(Package::Prototype->describe($legacy)->{members}{value}{kind}, 'method', 'value replaced by method');
is(Package::Prototype->describe($legacy)->{members}{new_value}{kind}, 'value', 'undef is a value');
my $named = Package::Prototype->bless({prototype => sub { 5 }});
is(Package::Prototype->describe($named)->{members}{prototype}{kind}, 'method', 'user prototype method included');
my $same_label = Package::Prototype->bless({}, 'Counter');
is(Package::Prototype->describe($same_label)->{members}, {}, 'same classname does not share metadata');
for my $invalid (undef, {}, bless({}, 'Counter')) {
    like dies { Package::Prototype->describe($invalid) }, qr/Expected a Package::Prototype object/, 'foreign object rejected';
}
like dies { Package::Prototype->describe() }, qr/expects one object/, 'missing argument';

SKIP: {
    skip 'Unicode names require Perl 5.36', 1 if $] < 5.036;
    my $ok = eval q{
        use utf8;
        my $o = Package::Prototype->create(properties => {'名前' => {value => '日本語'}});
        is(Package::Prototype->describe($o)->{members}{'名前'}{property}, '名前', 'Unicode metadata');
        1;
    };
    die $@ unless $ok;
}
no_leaks_ok {
    my $o = Package::Prototype->create(properties => {count => {value => 0, writer => 'set_count'}});
    my $info = Package::Prototype->describe($o);
    $o->prototype(count => sub { 1 });
} 'metadata and escaped descriptions release cleanly';
done_testing;
