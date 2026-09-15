package Package::Prototype;
use 5.008001;
use strict;
use warnings;

our $VERSION = "0.02";

use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

sub create {
    my $class = shift;
    die "create expects named options" if @_ % 2;
    my %options = @_;
    for my $key (keys %options) {
        die "Unknown create option: $key"
            unless $key eq 'properties' || $key eq 'methods' || $key eq 'classname';
    }
    my $properties = exists $options{properties} ? $options{properties} : {};
    my $methods = exists $options{methods} ? $options{methods} : {};
    die "properties must be a hash reference" unless ref($properties) eq 'HASH';
    die "methods must be a hash reference" unless ref($methods) eq 'HASH';

    my %installed;
    my $install = sub {
        my ($name, $code) = @_;
        die "Method name must be a nonempty string"
            if !defined($name) || ref($name) || !length($name);
        die "Method name prototype is reserved by create" if $name eq 'prototype';
        die "Duplicate method name: $name" if exists $installed{$name};
        $installed{$name} = $code;
    };
    for my $name (sort keys %$methods) {
        die "Method $name must be a code reference" unless ref($methods->{$name}) eq 'CODE';
        $install->($name, $methods->{$name});
    }
    for my $name (sort keys %$properties) {
        my $spec = $properties->{$name};
        die "Property $name must be a hash reference" unless ref($spec) eq 'HASH';
        for my $key (keys %$spec) {
            die "Unknown property option: $key"
                unless $key eq 'value' || $key eq 'reader' || $key eq 'writer';
        }
        die "Property $name requires value" unless exists $spec->{value};
        my $value = $spec->{value};
        my $reader = exists $spec->{reader} ? $spec->{reader} : $name;
        my $reader_code = sub {
            die "Reader $reader expects no arguments" unless @_ == 1;
            return $value;
        };
        my %info = (kind => 'property', property => $name, reader => $reader);
        $info{writer} = $spec->{writer} if exists $spec->{writer};
        _annotate_accessor($reader_code, { %info, access => 'read' });
        $install->($reader, $reader_code);
        if (exists $spec->{writer}) {
            my $writer = $spec->{writer};
            my $writer_code = sub {
                die "Writer $writer expects one argument" unless @_ == 2;
                $value = $_[1];
                return $value;
            };
            _annotate_accessor($writer_code, { %info, access => 'write' });
            $install->($writer, $writer_code);
        }
    }
    my $obj = exists $options{classname}
        ? Package::Prototype::bless($class, {}, $options{classname})
        : Package::Prototype::bless($class, {});
    $obj->prototype(%installed);
    return $obj;
}

sub describe {
    my ($class, $object) = @_;
    die "describe expects one object" unless @_ == 2;
    return { classname => ref($object), members => _members($object) };
}

1;
__END__

=encoding utf-8

=head1 NAME

Package::Prototype - Super easily to create prototype object

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Data::Dumper;
    use feature 'say';
    use Package::Prototype;

    my $obj = Package::Prototype->bless({
            foo => 10,
            bar => "Hello",
            baz => sub {
                my ($self, $arg) = @_;
                say "$arg, World";
            },
            # It do not create a method if key is started at '_'
            _data => "internal data"
        });

    say "\$obj classname: " . ref $obj;
    say Dumper $obj;
    say $obj->foo;        # 10
    say $obj->bar;        # "Hello"
    $obj->baz($obj->bar); # "Hello, World"

    my $obj2 = Package::Prototype->bless({
            hoge => [1..10],
            fuga => {abc => "def"}
        }, 'CLASS');

    say "\$obj2 classname: " . ref $obj2;

    # reference
    my $a = $obj2->hoge;
    my $h = $obj2->fuga;

    # wantarray
    my @a = $obj2->hoge;
    my %h = $obj2->fuga;

    $obj2->prototype(bow => sub { say "Bow!!" }, nyao => sub { say "Nyao!!" });
    $obj2->prototype(baw => 10, nyan => "nyan");
    $obj2->nyao(); # "Nyao!!"
    $obj2->bow();  # "Bow!!"
    say "bow: " . $obj2->baw . " nyan: " . $obj2->nyan;

=head1 DESCRIPTION

Package::Prototype can create prototype object like javascript.

This module can provide anonymous packages which are independent of the main namespace if not 
specified by classname. Also, available as an object instance.

=head1 EXPERIMENTAL COMPILE-TIME CHECKING

L<Package::Prototype::Typed> provides opt-in typed identity functions with
checks for known constants under C<perl -c>. Opt into C<always> mode
to also validate dynamic values at runtime.
L<Package::Prototype::Shape> checks method arguments on native typed lexicals
such as C<my Counter $obj>. Its factory adds runtime wrappers only in
C<always> mode.
These are partial checks, not whole-program type inference. Existing APIs are
unchanged. See C<docs/compile-time-types.md> and C<examples/typed/> in the
source distribution for executable examples and the guarantee boundaries.

=head1 METHODS

=over 2

=item C<< bless($ref :HashRef[, $classname :Str]) >>

Create a new anonymous package and an instance. The optional C<$clasname> argument sets the
stash's name. C<$classname> default is C<__ANON__>.

That instance also provide a method that will return values corresponding to keys that do not
start with '_'.

    my $obj = Package::Prototype->bless({
        foo => 10,
        bar => sub { say $_[1] },

        # It do not create a method if key is started at '_'
        _data => "internal data"
    });

    say $obj->foo; # 10
    say $obj->bar("Hello");

    # $obj->_data is not provided

=item C<< prototype($key :Str => $val :Any, ...) >>

This method can be used from the generated instance. By using this, it is possible to add new methods easily.

    $obj->prototype(add => sub {
        my $self = shift;
        return $_[0] + $_[1];
    });

    $obj->add(3, 5); # 8

=back

=head1 EXPLICIT PROPERTIES

C<create> separates stored values from executable methods:

    my $obj = Package::Prototype->create(
        properties => {
            count => { value => 0, writer => 'set_count' },
            callback => { value => sub { "done" } },
        },
        methods => {
            increment => sub {
                my $self = shift;
                $self->set_count($self->count + 1);
            },
        },
    );
    $obj->increment;
    my $callback = $obj->callback;
    print $callback->();

Each property requires C<value>, which may be C<undef> or any reference.
C<reader> defaults to the property name. Supplying C<writer> creates an
explicitly named setter; otherwise the property has no setter. Readers accept
no arguments, writers accept one value and return the assigned value.

Readers and writers share one private scalar per property per object. Values
are shallowly copied: referenced arrays, hashes and objects remain shared.
Readers always return that value, including in list context. In contrast,
legacy C<bless> getters expand array and hash references in list context.
A read-only property can still contain a mutable reference.

C<methods> contains code references. Optional C<classname> labels the anonymous
stash as with C<bless>. Input hashes are not modified. Duplicate method names,
unknown options and the method name C<prototype> are rejected by C<create>.
The existing C<bless> API still allows overriding C<prototype>.

The resulting object supports C<prototype> for subsequent method replacement.
Replacing a reader or writer replaces only that method, not its paired accessor.

=head1 MODERN PERL

On Perl 5.36 and later, methods may use subroutine signatures. The first
parameter is the invocant, just as with a normal Perl method:

    use v5.36;
    my $obj = Package::Prototype->bless({
        add => sub ($self, $x, $y = 2) { $x + $y },
    });
    say $obj->add(4); # 6

Code references are installed directly. Perl handles argument validation,
calling context, and exceptions. The module does not enable language features
in the caller or require a newer Perl merely to use its existing API.

Perl 5.44 also supports experimental named parameters in signatures:

    use v5.44;
    no warnings 'experimental::signature_named_parameters';
    my $obj = Package::Prototype->bless({
        greet => sub ($self, :$name, :$suffix = '!') { "$name$suffix" },
    });
    say $obj->greet(name => 'Perl');

This works with C<bless>, C<prototype>, and C<create> methods. It requires
Perl 5.44; the module does not emulate named signatures on earlier releases.

On Perl 5.36 and later, Unicode property and method names are supported,
including dynamic replacement. Earlier Perls are only tested with ASCII names.
Use C<use utf8> when writing non-ASCII names in source. On Perl 5.36 and later,
getters preserve the boolean identity of C<builtin::true> and C<builtin::false>.

=head1 SEE ALSO

L<Package::Anon>

L<Plack::Util::Prototype>

=head1 LICENSE

Copyright (C) K.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 OBJECT DESCRIPTION

    my $description = Package::Prototype->describe($object);
    my $members = $description->{members};
    print $members->{count}{kind}; # property

C<describe> returns a fresh hash containing C<classname> and C<members>.
Members are keyed by their callable names. Each entry has C<kind> (C<method>,
C<value>, or C<property>), C<own>, and C<depth>. Own entries have depth zero.
Explicit property accessors also report C<property> (the logical property name),
C<access> (C<read> or C<write>), C<reader>, and C<writer> when declared.
Reader/writer names describe the original declaration; either accessor can
subsequently be replaced independently.

Inspection never calls methods or getters and does not return stored values or
code references. Editing the returned hashes cannot change the object.
C<prototype> replacements are reflected immediately. The built-in mutation
method is omitted, but a user-defined method named C<prototype> is included.
Private hash storage and UNIVERSAL methods are not members. Only objects made
by this module are supported. Type constraints are not inferred or exposed.

=head1 AUTHOR

K E<lt>perl@codehex.devE<gt>

=cut

