use strict;
use warnings;
use Package::Prototype;

my $parent = Package::Prototype->create(properties => {
    count => {value => 1, reader => 'get_count', writer => 'set_count'},
});
my $child = Package::Prototype->derive(parent => $parent);
$child->set_count(3);
my $data = Package::Prototype->to_hashref($child);
my $renamed = Package::Prototype->to_hashref($child,
    fields => {total => 'get_count'},
);
die 'Unexpected extracted values' unless $data->{count} == 3 && $renamed->{total} == 3;
die 'Parent was changed' unless $parent->get_count == 1;
print "child=$data->{count}, total=$renamed->{total}, parent=", $parent->get_count, "\n";
