package Package::Prototype::Shape;
use 5.022;
use strict;
use warnings;
use Package::Prototype ();
use Scalar::Util qw(blessed);

sub import {
    my $class = shift;
    my $caller = caller;
    die "Expected shape name/signature pairs" if @_ % 2;
    while (@_) {
        my ($name, $spec) = splice @_, 0, 2;
        die "Invalid shape name" unless defined($name) && $name =~ /\A[A-Za-z_]\w*\z/;
        my $package = $caller eq 'main' ? $name : "${caller}::$name";
        die "Shape specification must be a hash reference" unless ref($spec) eq 'HASH';
        my %validators;
        for my $method (sort keys %$spec) {
            die "Invalid shape method" unless $method =~ /\A[A-Za-z_]\w*\z/;
            die "prototype is reserved" if $method eq 'prototype';
            die "Method signature must be an array reference" unless ref($spec->{$method}) eq 'ARRAY';
            $validators{$method} = [map {
                my $type = $_;
                die "Expected a type object providing assert_valid"
                    unless blessed($type) && $type->can('assert_valid');
                sub {
                    my $ok = eval { $type->assert_valid($_[0]); 1 };
                    die "Type check ${package}::$method failed: $@" unless $ok;
                    return;
                };
            } @{$spec->{$method}}];
        }
        no strict 'refs';
        die "Shape package $package is already in use" if keys %{"${package}::"};
        %{"${package}::__PACKAGE_PROTOTYPE_METHODS"} = %validators;
        *{"${package}::create"} = sub {
            my $invocant = shift;
            die "Expected method/code pairs" if @_ % 2;
            my %methods = @_;
            die "Expected shape class $package" unless !ref($invocant) && $invocant eq $package;
            my %wrapped;
            for my $method (keys %validators) {
                my $body = delete $methods{$method};
                die "Missing code for $method" unless ref($body) eq 'CODE';
                my $checks = $validators{$method};
                $wrapped{$method} = sub {
                    die "$method expects " . @$checks . " arguments" unless @_ == @$checks + 1;
                    for my $i (0 .. $#$checks) { $checks->[$i]->($_[$i + 1]) }
                    goto &$body;
                };
            }
            die "Unspecified shape methods: " . join(', ', sort keys %methods) if keys %methods;
            return Package::Prototype->create(classname => $package, methods => \%wrapped);
        };
    }
    Package::Prototype::_enable_shape_checker();
}
1;

=head1 NAME

Package::Prototype::Shape - Experimental typed lexical method checks

=head1 SYNOPSIS

    use Types::Standard qw(Int);
    use Package::Prototype::Shape Counter => {
        count => [], set_count => [Int],
    };
    my $value = 0;
    my Counter $counter = Counter->create(
        count => sub { $value },
        set_count => sub { $value = $_[1] },
    );
    $counter->set_count(42);
    # $counter->set_count('oops'); # rejected by perl -c

=head1 CONTRACT

Requires Perl 5.22. Registers package-scoped signatures before subsequent code
is compiled. Native C<my Counter> annotations select the signature; they do not
prove the runtime receiver has that shape. In a named package use the fully
qualified generated name in the annotation and constructor.

Named calls on directly annotated lexical receivers check known literal
arguments and arity. Calls with potential list expansion are entirely deferred.
Unknown method names, dynamic names, aliases without annotations, reassignment,
and return types are not analyzed. This is declaration-based checking, not
whole-program inference. Scalar variables are not assumed to retain an earlier
value. A successful C<perl -c> does not certify the program type-safe.

C<Counter-E<gt>create(name =E<gt> CODE, ...)> requires exactly the declared methods
and adds runtime arity and argument checks, preserving caller context. The
result is a Package::Prototype object; the shape name is not an inheritance
relationship. C<prototype> may add or replace methods. Replacement bypasses the
original runtime wrappers and does not update compile-time signatures.

Type objects must provide C<assert_valid>. Constraints run on copied constants
during compilation and on actual values at runtime; use deterministic,
side-effect-free constraints. No coercion is applied. Compile-time registration
and checks execute under C<perl -c> like other C<use>/C<BEGIN> code.

=cut
