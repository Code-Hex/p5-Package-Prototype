use Test::More;
use Test::LeakTrace;

use_ok 'Package::Prototype';

my @types = (
    120,
    1234.56,
    0x7f,
    [ 1..10 ],
    { map { $_ => int rand 10 } 'a'..'f' },
    "string!!",
    bless({}, 'test'),
    sub { "Hello!!" },
);

my $types_num = @types;

for my $i (1..10) {
    my %data = map { string_random() => $types[int(rand $types_num)] } 1..$i;
    leaks_cmp_ok {
        Package::Prototype->bless({ %data });
    } '==', $i;
}

sub string_random { join '', map { ('a'..'z', 'A'..'Z')[int rand 52] } 1..10 }

done_testing;