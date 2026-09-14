use strict;
use warnings;
use Test::More;
use Test::LeakTrace;
use Package::Prototype;

my $obj = Package::Prototype->bless({});
{
    my $value = 'original';
    $obj->prototype(value => $value);
    $value = 'changed';
}
is $obj->value, 'original', 'getter owns a snapshot of the scalar';
$obj->prototype(value => join('', 'temporary', '-value'));
is $obj->value, 'temporary-value', 'temporary survives the statement';
my $saved = $obj->can('value');
for (1..10) { $obj->value }
$obj->prototype(value => sub { 'code' });
is $obj->value, 'code', 'cached getter replaced with code';
$obj->prototype(value => 42);
is $obj->value, 42, 'cached code replaced with getter';
is $saved->($obj), 'temporary-value', 'saved getter retains its own value';
undef $obj;
is $saved->(), 'temporary-value', 'saved getter survives object destruction';

my $adder;
{
    my $original = Package::Prototype->bless({});
    $adder = $original->can('prototype');
}
my $other = Package::Prototype->bless({});
$adder->($other, added => 'alive');
is $other->added, 'alive', 'saved prototype uses the receiver stash';
eval { $adder->('not an object', added => 1) };
like $@, qr/object invocant/, 'invalid receiver rejected';

no_leaks_ok {
    my $o = Package::Prototype->bless({ value => [1,2], method => sub { 1 } });
    my $getter = $o->can('value');
    $o->prototype(value => { key => 3 });
    $o->prototype(method => sub { 2 });
    undef $o;
    my $value = $getter->();
} 'creation, replacement, and escaped getters release their values';

done_testing;
