use strict;
use warnings;
use Test2::V0;
use Test::LeakTrace;
use Scalar::Util qw(weaken);
use Package::Prototype;

my $parent = Package::Prototype->create(
    classname => 'Counter',
    properties => {count => {value => 0, writer => 'set_count'}},
    methods => {increment => sub { $_[0]->set_count($_[0]->count + 1) },
        receiver => sub { $_[0] }},
);
my $child = Package::Prototype->derive(parent => $parent, classname => 'Counter');
my $sibling = Package::Prototype->derive(parent => $parent);
ref_is $child->receiver, $child, 'inherited methods receive the child';
is $child->count, 0, 'inherited property value';
$parent->set_count(2);
is $child->count, 2, 'parent writes visible until shadowed';
is $child->increment, 3, 'inherited setter writes to child';
is $parent->count, 2, 'parent unchanged by child write';
is $sibling->count, 2, 'sibling unchanged by child write';
$parent->set_count(9);
is $child->count, 3, 'child own value survives later parent writes';
is $sibling->count, 9, 'unmodified sibling sees new parent value';
my $grandchild = Package::Prototype->derive(parent => $child);
is $grandchild->count, 3, 'grandchild reads nearest value';
$grandchild->set_count(4);
is $grandchild->count, 4, 'grandchild stores its own value';
is $child->count, 3, 'intermediate parent unchanged';
$child->set_count(undef);
ok !defined($child->count), 'undef is an own value';
is $grandchild->count, 4, 'grandchild retains its shadow';

$parent->prototype(late => sub { 'old' });
is $grandchild->late, 'old', 'late method reaches descendants';
my $saved = $child->can('late');
$parent->prototype(late => sub { 'new' });
is $child->late, 'new', 'cached method lookup invalidated';
is $grandchild->late, 'new', 'replacement reaches grandchildren';
is $saved->($child), 'old', 'saved can retains the old code';
$child->prototype(late => sub { 'child' });
$parent->prototype(late => sub { 'parent' });
is $child->late, 'child', 'own method shields child';
is $grandchild->late, 'child', 'own method shields subtree';
is $sibling->late, 'parent', 'other subtree receives update';
is(Package::Prototype->describe($child)->{members}{late}{own}, 1, 'own definition reported');
is(Package::Prototype->describe($grandchild)->{members}{late}{depth}, 1, 'nearest defining ancestor reported');
is(Package::Prototype->describe($grandchild)->{members}{receiver}{depth}, 2, 'deeper inheritance reported');
is(Package::Prototype->describe($child)->{members}{count}{own}, 0, 'value shadow does not redefine accessor');

my $custom = Package::Prototype->derive(parent => $parent,
    properties => {count => {value => 20, reader => 'custom_count', writer => 'custom_set'}});
$custom->custom_set(21);
is $custom->count, 9, 'same logical property name with different accessors has distinct storage';
is $custom->custom_count, 21, 'own declaration stores independently';
$custom->set_count(30);
is $custom->count, 30, 'inherited accessor shadows its own token';
is $custom->custom_count, 21, 'other property token is unaffected';
my $override = Package::Prototype->derive(parent => $parent,
    methods => {receiver => sub { 'override' }});
is $override->receiver, 'override', 'constructor methods shadow parent';

my $legacy = Package::Prototype->bless({value => [1,2]});
my $legacy_child = Package::Prototype->derive(parent => $legacy);
is [$legacy_child->value], [1,2], 'legacy getter keeps list behavior';
$legacy->prototype(value => 5);
is $legacy_child->value, 5, 'legacy value replacement propagates';
$legacy_child->prototype(value => 6);
is $legacy->value, 5, 'child legacy value override leaves parent unchanged';
my $context = Package::Prototype->create(methods => {
    result => sub { return wantarray ? (1,2) : defined(wantarray) ? 'scalar' : () },
});
my $context_child = Package::Prototype->derive(parent => $context);
is [$context_child->result], [1,2], 'inherited list context';
is scalar($context_child->result), 'scalar', 'inherited scalar context';
$context_child->result;
my $error = bless {}, 'Failure';
$context->prototype(fail => sub { die $error });
eval { $context_child->fail };
ref_is $@, $error, 'exception identity retained';

my ($weak_parent, $last_child);
{
    my $p = Package::Prototype->create(methods => {value => sub {7}});
    $weak_parent = $p;
    weaken($weak_parent);
    $last_child = Package::Prototype->derive(parent => $p);
}
ok defined($weak_parent), 'child retains parent';
undef $last_child;
ok !defined($weak_parent), 'parent released with last child';
no_leaks_ok {
    my $p = Package::Prototype->create(properties => {x => {value => [], writer => 'set_x'}});
    for (1..10) {
        my $c = Package::Prototype->derive(parent => $p);
        my $g = Package::Prototype->derive(parent => $c);
        $g->set_x([1]);
        $p->prototype(method => sub {2});
        my $info = Package::Prototype->describe($g);
    }
} 'parent links, values, inherited CVs, and metadata release';
for my $args ([], [parent => {}], [parent => undef], [parent => $parent, typo => 1], ['parent']) {
    ok dies { Package::Prototype->derive(@$args) }, 'invalid derivation rejected';
}
SKIP: {
    skip 'native signatures require Perl 5.36', 2 if $] < 5.036;
    my $ok = eval q{
        use v5.36;
        my $p = Package::Prototype->create(methods => {add => sub ($self, $x) { $x + 1 }});
        my $c = Package::Prototype->derive(parent => $p);
        is $c->add(2), 3, 'native signature inherited';
        like dies { $c->add() }, qr/Too few arguments/, 'native signature still enforces arity';
        1;
    };
    die $@ unless $ok;
}
{
    package Other;
    sub x { 3 }
}
my $rebless_parent = Package::Prototype->create(methods => {x => sub {1}});
my $reblessed = Package::Prototype->derive(parent => $rebless_parent);
bless $reblessed, 'Other';
$rebless_parent->prototype(x => sub {2}, added => sub {4});
is $reblessed->x, 3, 'reblessed child keeps its new class methods';
ok !$reblessed->can('added'), 'parent updates do not mutate unrelated classes';

my $cache_parent = Package::Prototype->create();
$cache_parent->isa('UNIVERSAL');
my $cache_child = Package::Prototype->derive(parent => $cache_parent);
ok !exists(Package::Prototype->describe($cache_child)->{members}{isa}), 'cached parent methods are not inherited members';
$cache_child->isa('UNIVERSAL');
$cache_parent->prototype(isa => sub { 'custom' });
is $cache_child->isa('anything'), 'custom', 'late parent member replaces a child lookup cache';

my $deep = Package::Prototype->create();
for (1..256) { $deep = Package::Prototype->derive(parent => $deep) }
like dies { Package::Prototype->derive(parent => $deep) }, qr/256 parent links/, 'chain limit counts parent links';
my $invalid_parent = Package::Prototype->create(methods => {value => sub {1}});
my $orphan = Package::Prototype->derive(parent => $invalid_parent);
bless $invalid_parent, 'Other';
like dies { Package::Prototype->describe($orphan) }, qr/parent has been reblessed/, 'invalid parent ancestry raises an exception';

SKIP: {
    skip 'Unicode methods require Perl 5.36', 2 if $] < 5.036;
    my $ok = eval q{
        use utf8;
        my $p = Package::Prototype->bless({'名前' => 'before'});
        my $c = Package::Prototype->derive(parent => $p);
        is $c->名前, 'before', 'Unicode member inherited';
        $p->prototype('名前' => 'after');
        is $c->名前, 'after', 'Unicode update propagated';
        1;
    };
    die $@ unless $ok;
}
SKIP: {
    skip 'Shape requires Perl 5.22', 2 if $] < 5.022;
    my $ok = eval q{
        use Types::Standard qw(Int);
        use Package::Prototype::Shape {mode => 'always'}, Number => {value => [Int]};
        my $p = Number->create(value => sub {$_[1]});
        my $c = Package::Prototype->derive(parent => $p);
        is $c->value(3), 3, 'Shape runtime wrapper inherited';
        like dies { $c->value('bad') }, qr/Type check/, 'inherited wrapper validates runtime inputs';
        1;
    };
    die $@ unless $ok;
}
{
    package CountingValue;
    sub TIESCALAR { bless {value => 0}, shift }
    sub FETCH { ++$_[0]{value} }
}
tie my $changing_value, 'CountingValue';
is $parent->set_count($changing_value), 1, 'writer returns the stored snapshot of a magical argument';
is $parent->count, 1, 'stored value matches writer result';
is $child->set_count($changing_value), 2, 'inherited writer fetches a magical argument once';
is $child->count, 2, 'child stores the returned value';
done_testing;
