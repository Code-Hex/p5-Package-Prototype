use v5.22;
use warnings;
use Types::Standard qw(Int);
use Package::Prototype::Checked count_value => Int;
use Package::Prototype::Shape Counter => {
    count => [],
    set_count => [Int],
};

my $value = count_value(0);
my Counter $counter = Counter->create(
    count => sub { $value },
    set_count => sub { $value = $_[1] },
);
$counter->set_count(42);
print $counter->count, "\n";

# Unknown input is validated before the method body can change state.
my $input = 'bad';
eval { $counter->set_count($input) };
die 'Expected a type error' unless $@;
print $counter->count, "\n"; # Still 42.
