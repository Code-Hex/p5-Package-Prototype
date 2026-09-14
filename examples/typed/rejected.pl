# This example deliberately fails under perl -c; the body never executes.
use v5.22;
use warnings;
use Types::Standard qw(Int);
use Package::Prototype::Shape Counter => { set_count => [Int] };
my Counter $counter;
$counter->set_count('bad');
