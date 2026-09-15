use strict;
use warnings;
use Package::Prototype;

my $parent = Package::Prototype->create(
    properties => {count => {value => 0, writer => 'set_count'}},
    methods => {increment => sub { $_[0]->set_count($_[0]->count + 1) }},
);
my $child = Package::Prototype->derive(parent => $parent);
$child->increment;
print "parent=", $parent->count, " child=", $child->count, "\n";

$parent->prototype(label => sub { 'counter' });
print $child->label, "\n";
my $members = Package::Prototype->describe($child)->{members};
for my $name (sort keys %$members) {
    print "$name: $members->{$name}{kind}, depth=$members->{$name}{depth}\n";
}
