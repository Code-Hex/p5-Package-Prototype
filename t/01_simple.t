use strict;
use Test2::V0;

use Package::Prototype;

my %orig = (hello => 20, world => "codehex");
my @orig = (1..10);

my $proto = Package::Prototype->bless({
    foo => 10,
    bar => "Hello",
    baz => sub {
        my ($self, $arg) = @_;
        return "$arg, World";
    },
    hoge => \%orig,
    fuga => \@orig
});

is $proto->foo, 10;
is $proto->bar, "Hello";
is $proto->baz($proto->bar), "Hello, World"; # scalar wantarray

# reference
my $href = $proto->hoge;
my $aref = $proto->fuga;
is $href, \%orig;
is $aref, \@orig;

# wantarray
my %h = $proto->hoge;
my @a = $proto->fuga;
is \%h, \%orig;
is \@a, \@orig;

done_testing;