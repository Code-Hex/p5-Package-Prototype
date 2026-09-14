package Package::Prototype::Checked;
use 5.016;
use strict;
use warnings;
use Package::Prototype ();
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
        my $validate = sub {
            my $ok = eval { $type->assert_valid($_[0]); 1 };
            die "Type check $name failed: $@" unless $ok;
            return;
        };
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

Exports named scalar identity functions backed by type objects providing
C<assert_valid>. Direct calls with literal scalar arguments are checked while
compiling. Every call is also checked at runtime. Requires Perl 5.16 or later;
loading the main Package::Prototype module does not enable this feature.

Type constraints are executed during compilation on copies of known values.
Use deterministic, side-effect-free constraints. No coercion is performed.
An accepted C<perl -c> run does not prove that dynamic values satisfy their types.
Indirect calls and calls marked with C<&> receive runtime checks only.
Names are installed in the caller's package, not lexically scoped.

=cut
