use strict;
use Test::More;
use Data::Dumper;

use_ok 'Package::Prototype';

my $proto = Package::Prototype->bless({
    foo => 10,
    bar => "Hello",
    baz => sub {
        my ($self, $arg) = @_;
        return "$arg, World";
    }
});

is $proto->foo, 10;
is $proto->bar, "Hello";
is $proto->baz($proto->bar), "Hello, World";

done_testing;