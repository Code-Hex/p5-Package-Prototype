use strict;
use warnings;
use Test2::V0;
use Test::LeakTrace;
use Scalar::Util qw(refaddr blessed);
use Package::Prototype;

my $array = [1, 2];
my $hash = {nested => 3};
my $code = sub { die 'data callback must not run' };
my $foreign = bless {}, 'Foreign';
my $object = Package::Prototype->create(properties => {
    count => {value => 4, reader => 'get_count', writer => 'set_count'},
    items => {value => $array},
    details => {value => $hash},
    callback => {value => $code},
    object => {value => $foreign},
    missing => {value => undef},
}, methods => {
    explode => sub { die 'method must not run' },
    can => sub { die 'custom can must not run' },
});
$object->{_private} = 'hidden';
my $data = Package::Prototype->to_hash_ref($object);
is $data, {count => 4, items => $array, details => $hash,
    callback => $code, object => $foreign, missing => undef}, 'only readable data';
ok !blessed($data), 'plain hash reference';
for my $pair ([items => $array], [details => $hash], [callback => $code], [object => $foreign]) {
    is refaddr($data->{$pair->[0]}), refaddr($pair->[1]), 'reference identity retained';
}
my $again = Package::Prototype->to_hash_ref($object);
isnt refaddr($again), refaddr($data), 'fresh result for each call';
$data->{count} = 99;
is $object->get_count, 4, 'result assignment does not write property';
push @{$data->{items}}, 3;
is $object->items, [1, 2, 3], 'nested references remain shared';
my @result = Package::Prototype->to_hash_ref($object);
is scalar(@result), 1, 'list context returns one hash reference';

my $fields = {total => 'get_count', second => 'get_count', '' => 'missing'};
is(Package::Prototype->to_hash_ref($object, fields => $fields),
    {total => 4, second => 4, '' => undef}, 'explicit selection, aliases and empty output key');
is $fields, {total => 'get_count', second => 'get_count', '' => 'missing'}, 'fields unchanged';
is(Package::Prototype->to_hash_ref($object, fields => {}), {}, 'empty selection');
is(Package::Prototype->to_hash_ref(Package::Prototype->create()), {}, 'empty object');

my $legacy = Package::Prototype->bless({a => [1,2], h => {x => 3},
    u => undef, _hidden => 7, run => sub {die 'must not run'}});
is(Package::Prototype->to_hash_ref($legacy), {a => [1,2], h => {x => 3}, u => undef},
    'legacy getters use scalar context and exclude private storage');
$legacy->prototype(new_value => 5);
is(Package::Prototype->to_hash_ref($legacy, fields => {n => 'new_value'}), {n => 5},
    'dynamic value getter');

my $parent = Package::Prototype->create(properties => {
    count => {value => 1, writer => 'set_count'},
});
my $child = Package::Prototype->derive(parent => $parent);
my $sibling = Package::Prototype->derive(parent => $parent);
my $grandchild = Package::Prototype->derive(parent => $child);
$parent->set_count(2);
is(Package::Prototype->to_hash_ref($child), {count => 2}, 'live parent value');
$child->set_count(3);
$parent->set_count(4);
is(Package::Prototype->to_hash_ref($child), {count => 3}, 'child override');
is(Package::Prototype->to_hash_ref($grandchild), {count => 3}, 'nearest ancestor value');
is(Package::Prototype->to_hash_ref($sibling), {count => 4}, 'sibling follows parent');
is(Package::Prototype->to_hash_ref($parent), {count => 4}, 'parent unaffected');

my $collision = Package::Prototype->derive(parent => $parent, properties => {
    count => {value => 8, reader => 'other_count'},
});
like dies { Package::Prototype->to_hash_ref($collision) }, qr/Duplicate output key: count/,
    'different declarations cannot silently overwrite';
is(Package::Prototype->to_hash_ref($collision, fields => {old => 'count', new => 'other_count'}),
    {old => 4, new => 8}, 'explicit fields resolve collision');
my $mixed = Package::Prototype->create(properties => {count => {value => 1, reader => 'read_count'}});
$mixed->prototype(count => 2);
like dies { Package::Prototype->to_hash_ref($mixed) }, qr/Duplicate output key: count/,
    'legacy and property collision';

my $shadow = Package::Prototype->derive(parent => $parent, properties => {
    count => {value => 10},
});
$shadow->set_count(20);
is(Package::Prototype->to_hash_ref($shadow), {count => 10},
    'own reader retains its value when an inherited writer belongs to another declaration');
my $reserved = Package::Prototype->bless({to_hash_ref => 6, prototype => 7, '0' => 8});
is(Package::Prototype->to_hash_ref($reserved), {to_hash_ref => 6, prototype => 7, '0' => 8},
    'class API does not reserve object member names');
is(Package::Prototype->to_hash_ref($reserved, fields => {zero => '0'}), {zero => 8},
    'zero is a valid reader name');
my $escaped;
{
    my $temporary = Package::Prototype->create(properties => {items => {value => [9]}});
    $escaped = Package::Prototype->to_hash_ref($temporary);
}
is $escaped, {items => [9]}, 'extracted values outlive the source object';

$object->prototype(set_count => sub { die 'writer replacement must not run' });
is(Package::Prototype->to_hash_ref($object, fields => {n => 'get_count'}), {n => 4},
    'writer replacement preserves reader');
$object->prototype(get_count => sub { die 'reader replacement must not run' });
ok !exists(Package::Prototype->to_hash_ref($object)->{count}), 'replaced reader omitted';
like dies { Package::Prototype->to_hash_ref($object, fields => {n => 'get_count'}) },
    qr/does not name a property reader or value getter/, 'explicit replaced reader rejected';
$parent->prototype(count => sub { die 'inherited replacement must not run' });
is(Package::Prototype->to_hash_ref($child), {}, 'inherited replacement reflected');

for my $name ('explode', 'set_count', '_private', 'absent', 'prototype') {
    like dies { Package::Prototype->to_hash_ref($object, fields => {x => $name}) },
        qr/does not name a property reader or value getter/, "reject non-reader $name";
}
for my $invalid (undef, '', [], {}) {
    like dies { Package::Prototype->to_hash_ref($object, fields => {x => $invalid}) },
        qr/requires a nonempty reader name/, 'invalid reader name';
}
for my $invalid (undef, [], 'count', bless({}, 'Fields')) {
    like dies { Package::Prototype->to_hash_ref($object, fields => $invalid) },
        qr/fields must be a hash reference/, 'invalid fields';
}
for my $invalid (undef, {}, bless({}, 'Counter')) {
    like dies { Package::Prototype->to_hash_ref($invalid) },
        qr/Expected a Package::Prototype object/, 'invalid object';
}
like dies { Package::Prototype->to_hash_ref() }, qr/expects an object and named options/, 'missing object';
like dies { Package::Prototype->to_hash_ref($object, 'fields') }, qr/expects an object and named options/, 'odd options';
like dies { Package::Prototype->to_hash_ref($object, unknown => 1) }, qr/Unknown to_hash_ref option/, 'unknown option';

my $broken_parent = Package::Prototype->create(properties => {x => {value => 1}});
my $orphan = Package::Prototype->derive(parent => $broken_parent);
bless $broken_parent, 'Foreign';
like dies { Package::Prototype->to_hash_ref($orphan) }, qr/parent has been reblessed/,
    'invalid ancestry raises an exception';

my $cycle = [];
push @$cycle, $cycle;
my $cyclic = Package::Prototype->create(properties => {cycle => {value => $cycle}});
is refaddr(Package::Prototype->to_hash_ref($cyclic)->{cycle}), refaddr($cycle), 'cycles are not traversed';
pop @$cycle;

SKIP: {
    skip 'Unicode and native booleans require Perl 5.36', 4 if $] < 5.036;
    my $ok = eval q{
        use utf8;
        use builtin qw(true false is_bool);
        no warnings 'experimental::builtin';
        my $o = Package::Prototype->create(properties => {
            '名前' => {value => '日本語', reader => '読む'},
            yes => {value => true}, no => {value => false},
        });
        my $d = Package::Prototype->to_hash_ref($o);
        is $d->{'名前'}, '日本語', 'Unicode names and values';
        is(Package::Prototype->to_hash_ref($o, fields => {'表示名' => '読む'}),
            {'表示名' => '日本語'}, 'Unicode selection and renaming');
        ok is_bool($d->{yes}) && $d->{yes}, 'true identity';
        ok is_bool($d->{no}) && !$d->{no}, 'false identity';
        1;
    };
    die $@ unless $ok;
}
no_leaks_ok {
    my $o = Package::Prototype->create(properties => {x => {value => []}});
    my $c = Package::Prototype->derive(parent => $o);
    my $d = Package::Prototype->to_hash_ref($c);
    eval { Package::Prototype->to_hash_ref($c, fields => {x => 'absent'}) };
} 'success and validation failure release temporaries';
done_testing;
