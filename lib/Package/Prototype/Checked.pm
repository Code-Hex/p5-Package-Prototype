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
    require Package::Prototype::_Validation if $compile;
    die "Expected name/type pairs" if @_ % 2;
    while (@_) {
        my ($name, $type) = splice @_, 0, 2;
        die "Invalid checker name" unless defined($name) && $name =~ /\A[A-Za-z_]\w*\z/;
        die "Expected a type object providing assert_valid"
            unless blessed($type) && $type->can('assert_valid');
        my $validate = $compile ? Package::Prototype::_Validation::validator($type, $name) : undef;
        my $code = $runtime ? sub ($) {
            die "$name expects one argument" unless @_ == 1;
            $validate->($_[0]);
            return $_[0];
        } : sub ($) {
            die "$name expects one argument" unless @_ == 1;
            return $_[0];
        };
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

Unknown values are checked at runtime only in C<checked> mode. List expansion, subroutine calls inside
constructors, and dynamic hash keys defer the containing structure. Union types,
custom structural types, Slurpy slots, and derived Optional slots are deferred
when the value is partial. Structures nested beyond 64 levels are also deferred.
Duplicate literal keys adhere to perl's last-key-wins rule.
No argument expressions are executed speculatively during compilation.

In C<checked> mode, every call is also checked at runtime. Passing C<perl -c> does not guarantee
that dynamic values satisfy their types. Constraints execute on
reconstructed copies of literal data, so type objects must be deterministic and
free of side effects. Type coercion is not performed. Indirect calls and
subroutines invoked with C<&> bypass compile-time checking and are validated
exclusively at runtime in C<checked> mode.

Requires Perl 5.16 or later. Loading Package::Prototype alone does not enable
these checks. Functions are installed package-wide into the
calling namespace.

=head1 CHECK MODES

The optional first argument selects a mode for the definitions in that import.
The default is C<syntax>: checks run only under C<perl -c> or another
compile-only invocation. Enable both compile-time and runtime checks explicitly:

    use Package::Prototype::Checked { mode => 'checked' }, integer => Int;

This changes the earlier experimental default. Applications relying on runtime
validation must add C<< { mode => 'checked' } >> to their imports.

    use Types::Standard qw(Int);
    use Package::Prototype::Checked { mode => 'syntax' }, integer => Int;
    integer('oops');

C<perl -c> rejects this literal. Ordinary execution returns C<'oops'> without
checking its type. The exported function retains its scalar prototype and
one-argument contract; the function call itself is not removed.

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
