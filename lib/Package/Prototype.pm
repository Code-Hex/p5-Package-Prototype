package Package::Prototype;
use strict;
use warnings;

our $VERSION = "0.01";

sub generate {
    my ($class, $refs, $klass) = @_;
    $klass //= '__ANON__';
    my $obj = bless $refs, $klass;
    {
        no strict 'refs';
        for my $method (keys %$refs) {
            if ($method !~ /\A_/) {
                if (ref($refs->{$method}) =~ /CODE/) {
                    # Create some methods
                    *{"$klass::$method"} = delete $refs->{$method};
                } else {
                    # Create some attributes
                    my $ref = delete $refs->{$method};
                    *{"$klass::$method"} = sub { $ref };
                }
            }
        }
    }
    return $obj;
}

1;
__END__

=encoding utf-8

=head1 NAME

Package::Prototype - It's new $module

=head1 SYNOPSIS

    use Package::Prototype;

=head1 DESCRIPTION

Package::Prototype is ...

=head1 LICENSE

Copyright (C) K.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

K E<lt>x00.x7f@gmail.comE<gt>

=cut

