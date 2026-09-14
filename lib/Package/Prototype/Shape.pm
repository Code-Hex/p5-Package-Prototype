package Package::Prototype::Shape;
use 5.022;
use strict;
use warnings;
use Package::Prototype ();
use Package::Prototype::_Mode ();
use Scalar::Util qw(blessed);

sub import {
    my $class = shift;
    my $caller = caller;
    my ($runtime, $compile) = Package::Prototype::_Mode::checks(\@_);
    die "Expected shape name/signature pairs" if @_ % 2;
    return unless @_;
    require Package::Prototype::_Validation if $compile;
    while (@_) {
        my ($name, $spec) = splice @_, 0, 2;
        die "Invalid shape name" unless defined($name) && $name =~ /\A[A-Za-z_]\w*\z/;
        my $package = $caller eq 'main' ? $name : "${caller}::$name";
        die "Shape specification must be a hash reference" unless ref($spec) eq 'HASH';
        my %validators;
        my @methods = sort keys %$spec;
        for my $method (@methods) {
            die "Invalid shape method" unless $method =~ /\A[A-Za-z_]\w*\z/;
            die "prototype is reserved" if $method eq 'prototype';
            die "Method signature must be an array reference" unless ref($spec->{$method}) eq 'ARRAY';
            for my $type (@{$spec->{$method}}) {
                die "Expected a type object providing assert_valid"
                    unless blessed($type) && $type->can('assert_valid');
            }
            if ($compile) {
                $validators{$method} = [map {
                    Package::Prototype::_Validation::validator($_, "${package}::$method")
                } @{$spec->{$method}}];
            }
        }
        no strict 'refs';
        die "Shape package $package is already in use" if keys %{"${package}::"};
        %{"${package}::__PACKAGE_PROTOTYPE_METHODS"} = %validators if $compile;
        *{"${package}::create"} = sub {
            my $invocant = shift;
            die "Expected method/code pairs" if @_ % 2;
            my %methods = @_;
            die "Expected shape class $package" unless !ref($invocant) && $invocant eq $package;
            my %installed;
            for my $method (@methods) {
                my $body = delete $methods{$method};
                die "Missing code for $method" unless ref($body) eq 'CODE';
                unless ($runtime) {
                    $installed{$method} = $body;
                    next;
                }
                my $checks = $validators{$method};
                $installed{$method} = sub {
                    die "$method expects " . @$checks . " arguments"
                        unless @_ == @$checks + 1;
                    for my $i (0 .. $#$checks) {
                        $checks->[$i]->($_[$i + 1]);
                    }
                    goto &$body;
                };
            }
            die "Unspecified shape methods: " . join(', ', sort keys %methods) if keys %methods;
            return Package::Prototype->create(classname => $package, methods => \%installed);
        };
    }
    Package::Prototype::_enable_shape_checker() if $compile;
}
1;

=encoding UTF-8

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

Requires Perl 5.22 or later. Registers method signatures in package scope at
compile time when checks are enabled (by default, under C<perl -c>).
Method calls made directly on typed lexical variables (for example,
C<my Counter $counter>) are inspected for valid arity and literal arguments
during compilation. Outside C<main>, the shape name must be fully qualified
in annotations and constructor calls (e.g. C<my App::Counter $counter>).

Known arguments—including partial standard C<ArrayRef>, C<Tuple>, and C<Dict>
structures—are validated as described in L<Package::Prototype::Typed>.
Calls with potential list expansion are checked only at runtime in C<always> mode. Method names not
declared in the shape, dynamic method dispatch, unannotated aliases, and return values are not checked at compile time.
Reassignments are not tracked: later calls still use the declared signature.
The annotation does not prove that the runtime receiver has that shape.

C<< Counter->create(name => CODE, ...) >> requires exactly the declared methods
and, in C<always> mode, creates an object with runtime wrappers
enforcing method arity and argument types while preserving caller context
(scalar, list, void) and supporting native subroutine signatures. The returned
instance is a Package::Prototype object; shape names do not imply an inheritance
relationship. Modifying methods later via C<prototype> replaces runtime wrappers
without modifying compile-time signatures.

Type objects must implement C<assert_valid>. Constraints execute during
compilation on literal copies and must be deterministic and side-effect-free.
Coercion is not performed. Passing C<perl -c> checks literal arguments but does
not guarantee runtime type safety for dynamic inputs.

=head1 CHECK MODES

The modes differ as follows. C<syntax> is the default.

    Type check                         syntax          always
    ---------------------------------  --------------  ----------------
    Known values under perl -c         Yes             Yes
    Known values at ordinary startup   No              Yes
    Actual values when called          No              Yes
    Unknown variable values            Not validated   Validated on call

The mode is selected at import time using C<$^C>. C<syntax> enables checks
only for compile-only invocations such as C<perl -c>. Calls executed in C<BEGIN>
blocks have no runtime validation in this mode. Definitions using different
modes can coexist; each keeps the mode selected at its import.

During ordinary execution, C<syntax> installs the original method CODE without
a type or arity wrapper. The constructor still requires the declared methods,
and native subroutine signatures keep their own argument checks.

To add compile-time checks and runtime validation wrappers, use C<always>:

    use Types::Standard qw(Int);
    use Package::Prototype::Shape { mode => 'always' }, Counter => {
        set_count => [Int],
    };

Existing code relying on runtime validation must add this option.
See L<Package::Prototype::Typed/CHECK MODES> for the limits of C<perl -c>
and the startup costs that remain in both modes.

=cut
