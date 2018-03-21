use strict;
use Test::More;

use_ok 'Package::Prototype';

sub __ANON__::foo { die "DIED" }

my $obj1 = Package::Prototype->bless({ foo => 10 });
ok $obj1->isa('__ANON__');
is ref $obj1, '__ANON__';
can_ok $obj1, 'foo';
is $obj1->foo, 10;

my $obj2 = Package::Prototype->bless({ bar => 10 }, 'CLASS');
ok $obj2->isa('CLASS');
is ref $obj2, 'CLASS';
can_ok $obj2, 'bar';
is $obj2->bar, 10;

my $obj3 = Package::Prototype->bless({ VERSION => $Package::Prototype::VERSION });
can_ok $obj3, 'VERSION';
is $obj3->VERSION, $Package::Prototype::VERSION;

my $obj4 = Package::Prototype->bless({ AUTOLOAD => sub { our $AUTOLOAD } });
is $obj4->moo, '__ANON__::moo';

my $obj5 = Package::Prototype->bless({});
ok !$obj5->can('foo');

done_testing;