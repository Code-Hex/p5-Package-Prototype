package Package::Prototype::_Validation;
use 5.016;
use strict;
use warnings;

sub validator {
    my ($type, $label) = @_;
    return sub {
        my ($value, $static) = @_;
        my $ok = eval {
            $static ? _partial($type, $value) : $type->assert_valid($value);
            1;
        };
        die "Type check $label failed: $@" unless $ok;
        return;
    };
}

# Node kinds: 0 = known literal, 1 = unknown/deferred, 2 = array, 3 = hash.
# Defer unknown expressions; never pass incomplete data to whole-value constraints.
sub _partial {
    my ($type, $node) = @_;
    my ($kind, $value) = @$node;
    return $type->assert_valid($value) if $kind == 0;
    return if $kind == 1;
    return unless ref($type) eq 'Type::Tiny' && $type->is_parameterized;

    require Types::Standard;
    my $parent = $type->parent;
    my $parameters = $type->parameters;
    return unless $parent->strictly_equals(Types::Standard::ArrayRef())
        || $parent->strictly_equals(Types::Standard::Tuple())
        || $parent->strictly_equals(Types::Standard::Dict());
    return unless _canonical($type);

    if ($kind == 2 && $parent->strictly_equals(Types::Standard::ArrayRef())) {
        _partial($parameters->[0], $_) for @$value;
    }
    elsif ($kind == 2 && $parent->strictly_equals(Types::Standard::Tuple())) {
        return if grep { _unsupported_slot($_) } @$parameters;
        die "Too many Tuple elements\n" if @$value > @$parameters;
        for my $i (0 .. $#$parameters) {
            my $slot = $parameters->[$i];
            my $optional = _slot_is($slot, Types::Standard::Optional());
            if ($i > $#$value) {
                die "Missing Tuple element $i\n" unless $optional;
                next;
            }
            _partial($optional ? $slot->parameters->[0] : $slot, $value->[$i]);
        }
    }
    elsif ($kind == 3 && $parent->strictly_equals(Types::Standard::Dict())) {
        return if @$parameters % 2; # A trailing slurpy specification.
        my %fields = @$parameters;
        return if grep { _unsupported_slot($_) } values %fields;
        for my $key (sort keys %fields) {
            my $slot = $fields{$key};
            my $optional = _slot_is($slot, Types::Standard::Optional());
            if (!exists $value->{$key}) {
                die "Missing Dict field $key\n" unless $optional;
                next;
            }
            _partial($optional ? $slot->parameters->[0] : $slot, $value->{$key});
        }
        for my $key (sort keys %$value) {
            die "Unexpected Dict field $key\n" unless exists $fields{$key};
        }
    }
    return;
}

# Ensure the type is an uncustomized instance of the parent's parameterized type.
# User-defined subtypes can share parents and parameters but implement different constraints.
sub _canonical {
    my ($type) = @_;
    return 0 unless ref($type) eq 'Type::Tiny' && $type->is_parameterized;
    my $canonical = eval { $type->parent->parameterize(@{$type->parameters}) };
    return $canonical && $type->strictly_equals($canonical);
}

sub _unsupported_slot {
    my ($type) = @_;
    return 1 if $type->is_strictly_a_type_of(Types::Standard::Slurpy());
    return 0 unless $type->is_strictly_a_type_of(Types::Standard::Optional());
    return !_slot_is($type, Types::Standard::Optional()) || !_canonical($type);
}

sub _slot_is {
    my ($type, $parent) = @_;
    return ref($type) eq 'Type::Tiny'
        && $type->has_parent
        && $type->is_parameterized
        && $type->parent->strictly_equals($parent);
}

1;
