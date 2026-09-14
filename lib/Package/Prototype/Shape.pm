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
    require Package::Prototype::_Validation if $compile;
    die "Expected shape name/signature pairs" if @_ % 2;
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
            $validators{$method} = [map {
                my $type = $_;
                die "Expected a type object providing assert_valid"
                    unless blessed($type) && $type->can('assert_valid');
                $compile ? Package::Prototype::_Validation::validator($type, "${package}::$method") : ();
            } @{$spec->{$method}}];
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
compile time. Method calls made directly on typed lexical variables (for example,
C<my Counter $counter>) are inspected for valid arity and literal arguments
during compilation. Outside C<main>, the shape name must be fully qualified
in annotations and constructor calls (e.g. C<my App::Counter $counter>).

Known arguments—including partial standard C<ArrayRef>, C<Tuple>, and C<Dict>
structures—are validated as described in L<Package::Prototype::Checked>.
Calls with potential list expansion are deferred to runtime. Method names not
declared in the shape, dynamic method dispatch, unannotated aliases, and return values are not checked at compile time.
Reassignments are not tracked: later calls still use the declared signature.
The annotation does not prove that the runtime receiver has that shape.

C<< Counter->create(name => CODE, ...) >> requires exactly the declared methods
and, in the default C<checked> mode, creates an object with runtime wrappers
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

The optional first argument selects a mode for the definitions in that import.
Omitting it is equivalent to C<< { mode => 'checked' } >> and retains both
compile-time and runtime checks.

    use Types::Standard qw(Int);
    use Package::Prototype::Shape { mode => 'syntax' }, Counter => {
        set_count => [Int],
    };
    my Counter $counter = Counter->create(set_count => sub { $_[1] });
    $counter->set_count('oops');

C<perl -c> rejects this literal. Ordinary execution calls the original method
without a type or arity wrapper. The constructor still requires exactly the
declared methods, each supplied as CODE. Native subroutine signatures and errors
from the method body remain effective.

C<syntax> selects compile-time checks only when C<$^C> is true at import time
(C<perl -c>, or another compile-only invocation). Ordinary execution installs
no type checker for these definitions. Calls executed in C<BEGIN> blocks also
have no runtime validation in this mode. Other definitions imported in
C<checked> mode retain their checks.

Unknown values remain unchecked: passing C<perl -c> does not establish runtime
type safety. Runtime C<require> and string C<eval> may load code that C<perl -c>
never sees. Check those files separately when applicable.

Type libraries and type objects in the import arguments are still loaded and
constructed during ordinary startup. This mode removes validation, not all
costs associated with type declarations. Constraints must still be deterministic
and free of side effects when used during compilation.

=cut
