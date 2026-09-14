package Package::Prototype::Checked;
use 5.016;
use strict;
use warnings;
use Package::Prototype ();
use Package::Prototype::_Mode ();
use Scalar::Util qw(blessed);

sub import {
    my $class = shift;
    my $caller = caller;
    my ($runtime, $compile) = Package::Prototype::_Mode::checks(\@_);
    die "Expected name/type pairs" if @_ % 2;
    return unless @_;
    require Package::Prototype::_Validation if $compile;
    while (@_) {
        my ($name, $type) = splice @_, 0, 2;
        die "Invalid checker name" unless defined($name) && $name =~ /\A[A-Za-z_]\w*\z/;
        die "Expected a type object providing assert_valid"
            unless blessed($type) && $type->can('assert_valid');
        my $validate = $compile ? Package::Prototype::_Validation::validator($type, $name) : undef;
        my $code;
        if ($runtime) {
            $code = sub ($) {
                die "$name expects one argument" unless @_ == 1;
                $validate->($_[0]);
                return $_[0];
            };
        } else {
            $code = sub ($) {
                die "$name expects one argument" unless @_ == 1;
                return $_[0];
            };
        }
        no strict 'refs';
        die "Refusing to replace ${caller}::$name" if defined &{"${caller}::$name"};
        Package::Prototype::_install_checker($code, $validate) if $compile;
        *{"${caller}::$name"} = $code;
    }
}

1;

=head1 NAME

Package::Prototype::Checked - Experimental compile-only checks with optional runtime validation

=head1 SYNOPSIS

    use Types::Standard qw(Int);
    use Package::Prototype::Checked count_value => Int;

    my $value = count_value(42);
    # count_value('oops') fails under perl -c.
    # Ordinary execution does not check the value.

=head1 DESCRIPTION

Exports named scalar identity functions backed by type objects implementing
C<assert_valid>. Direct calls with literal scalars, C<undef>, constant array or
hash references, and expressions folded to constants by perl are verified at
compile time when checks are enabled (by default, under C<perl -c>).

For canonical Type::Tiny C<ArrayRef>, C<Tuple>, and C<Dict> constraints, known
elements within partially dynamic structures are checked at compile time.
Standard C<Optional> elements may be omitted, and unexpected extra keys or
elements are flagged.

Unknown values are checked at runtime only in C<always> mode. List expansion, subroutine calls inside
constructors, and dynamic hash keys defer the containing structure. Union types,
custom structural types, Slurpy slots, and derived Optional slots are deferred
when the value is partial. Structures nested beyond 64 levels are also deferred.
Duplicate literal keys adhere to perl's last-key-wins rule.
No argument expressions are executed speculatively during compilation.

In C<always> mode, every call is also checked at runtime. Passing C<perl -c> does not guarantee
that dynamic values satisfy their types. Constraints execute on
reconstructed copies of literal data, so type objects must be deterministic and
free of side effects. Type coercion is not performed. Indirect calls and
subroutines invoked with C<&> bypass compile-time checking and are validated
exclusively at runtime in C<always> mode.

Requires Perl 5.16 or later. Loading Package::Prototype alone does not enable
these checks. Functions are installed package-wide into the
calling namespace.

=head1 CHECK MODES

The modes differ as follows. C<syntax> is the default.

    Type check                         syntax          always
    ---------------------------------  --------------  ----------------
    Known values under perl -c         Yes             Yes
    Known values at ordinary startup   No              Yes
    Actual values when called          No              Yes
    Unknown variable values            Not checked     Checked on call

The mode is selected at import time using C<$^C>. C<syntax> enables checks
only for compile-only invocations such as C<perl -c>. Calls executed in C<BEGIN>
blocks have no runtime validation in this mode. Definitions using different
modes can coexist; each keeps the mode selected at its import.

During ordinary execution, C<syntax> functions return their argument without
validating it. They retain their scalar prototype and one-argument contract.

To validate values during ordinary compilation and execution, use C<always>:

    use Types::Standard qw(Int);
    use Package::Prototype::Checked { mode => 'always' }, integer => Int;

Existing code relying on runtime validation must add this option.

C<perl -c> does not run the main program body or determine unknown variable
values. Runtime C<require> and string C<eval> may load code it never sees;
check those files separately. Type libraries and type objects are still loaded
and constructed during ordinary startup in both modes.

=cut
