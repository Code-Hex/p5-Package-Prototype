package Package::Prototype::Checked;
use 5.016;
use strict;
use warnings;
use Package::Prototype ();
use Package::Prototype::_Validation ();
use Scalar::Util qw(blessed);

sub import {
    my $class = shift;
    my $caller = caller;
    die "Expected name/type pairs" if @_ % 2;
    while (@_) {
        my ($name, $type) = splice @_, 0, 2;
        die "Invalid checker name" unless defined($name) && $name =~ /\A[A-Za-z_]\w*\z/;
        die "Expected a type object providing assert_valid"
            unless blessed($type) && $type->can('assert_valid');
        my $validate = Package::Prototype::_Validation::validator($type, $name);
        my $code = sub ($) {
            die "$name expects one argument" unless @_ == 1;
            $validate->($_[0]);
            return $_[0];
        };
        no strict 'refs';
        die "Refusing to replace ${caller}::$name" if defined &{"${caller}::$name"};
        Package::Prototype::_install_checker($code, $validate);
        *{"${caller}::$name"} = $code;
    }
}

1;

=head1 NAME

Package::Prototype::Checked - Experimental compile-time checks with runtime fallback

=head1 SYNOPSIS

    use Types::Standard qw(Int);
    use Package::Prototype::Checked count_value => Int;

    my $value = count_value(42);
    # count_value('oops') fails during compilation, including perl -c.
    # count_value($input) checks the actual value at runtime.

=head1 DESCRIPTION

Exports named scalar identity functions backed by type objects implementing
C<assert_valid>. Direct calls with literal scalars, C<undef>, constant array or
hash references, and expressions folded to constants by perl are verified at
compile time (including during C<perl -c>).

For canonical Type::Tiny C<ArrayRef>, C<Tuple>, and C<Dict> constraints, known
elements within partially dynamic structures are checked at compile time.
Standard C<Optional> elements may be omitted, and unexpected extra keys or
elements are flagged.

Unknown values are checked at runtime. List expansion, subroutine calls inside
constructors, and dynamic hash keys defer the containing structure. Union types,
custom structural types, Slurpy slots, and derived Optional slots are deferred
when the value is partial. Structures nested beyond 64 levels are also deferred.
Duplicate literal keys adhere to perl's last-key-wins rule.
No argument expressions are executed speculatively during compilation.

Every call is also checked at runtime. Passing C<perl -c> does not guarantee
that dynamic values satisfy their types. Constraints execute on
reconstructed copies of literal data, so type objects must be deterministic and
free of side effects. Type coercion is not performed. Indirect calls and
subroutines invoked with C<&> bypass compile-time checking and are validated
exclusively at runtime.

Requires Perl 5.16 or later. Loading Package::Prototype alone does not enable
these checks. Functions are installed package-wide into the
calling namespace.

=cut
