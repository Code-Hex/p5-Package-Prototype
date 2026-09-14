use strict;
use Test2::V0;

is dies { require Package::Prototype }, undef, 'Package::Prototype loads';

done_testing;

