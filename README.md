[![Build Status](https://travis-ci.org/Code-Hex/p5-Package-Prototype.svg?branch=master)](https://travis-ci.org/Code-Hex/p5-Package-Prototype)
# NAME

Package::Prototype - Super easily to create prototype object

# SYNOPSIS

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

# DESCRIPTION

Package::Prototype can create prototype object like javascript.

This module can provide anonymous packages which are independent of the main namespace if not 
specified by classname. Also, available as an object instance.

# EXPERIMENTAL COMPILE-TIME CHECKING

[Package::Prototype::Typed](https://metacpan.org/pod/Package%3A%3APrototype%3A%3ATyped) provides opt-in typed identity functions with
checks for known constants under `perl -c`. Opt into `always` mode
to also validate dynamic values at runtime.
[Package::Prototype::Shape](https://metacpan.org/pod/Package%3A%3APrototype%3A%3AShape) checks method arguments on native typed lexicals
such as `my Counter $obj`. Its factory adds runtime wrappers only in
`always` mode.
These are partial checks, not whole-program type inference. Existing APIs are
unchanged. See `docs/compile-time-types.md` and `examples/typed/` in the
source distribution for executable examples and the guarantee boundaries.

# METHODS

- `bless($ref :HashRef[, $classname :Str])`

    Create a new anonymous package and an instance. The optional `$clasname` argument sets the
    stash's name. `$classname` default is `__ANON__`.

    That instance also provide a method that will return values corresponding to keys that do not
    start with '\_'.

        my $obj = Package::Prototype->bless({
            foo => 10,
            bar => sub { say $_[1] },

            # It do not create a method if key is started at '_'
            _data => "internal data"
        });

        say $obj->foo; # 10
        say $obj->bar("Hello");

        # $obj->_data is not provided

- `prototype($key :Str => $val :Any, ...)`

    This method can be used from the generated instance. By using this, it is possible to add new methods easily.

        $obj->prototype(add => sub {
            my $self = shift;
            return $_[0] + $_[1];
        });

        $obj->add(3, 5); # 8

# EXPLICIT PROPERTIES

`create` separates stored values from executable methods:

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

Each property requires `value`, which may be `undef` or any reference.
`reader` defaults to the property name. Supplying `writer` creates an
explicitly named setter; otherwise the property has no setter. Readers accept
no arguments, writers accept one value and return the assigned value.

Readers and writers share one private scalar per property per object. Values
are shallowly copied: referenced arrays, hashes and objects remain shared.
Readers always return that value, including in list context. In contrast,
legacy `bless` getters expand array and hash references in list context.
A read-only property can still contain a mutable reference.

`methods` contains code references. Optional `classname` labels the anonymous
stash as with `bless`. Input hashes are not modified. Duplicate method names,
unknown options and the method name `prototype` are rejected by `create`.
The existing `bless` API still allows overriding `prototype`.

The resulting object supports `prototype` for subsequent method replacement.
Replacing a reader or writer replaces only that method, not its paired accessor.

# MODERN PERL

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

This works with `bless`, `prototype`, and `create` methods. It requires
Perl 5.44; the module does not emulate named signatures on earlier releases.

On Perl 5.36 and later, Unicode property and method names are supported,
including dynamic replacement. Earlier Perls are only tested with ASCII names.
Use `use utf8` when writing non-ASCII names in source. On Perl 5.36 and later,
getters preserve the boolean identity of `builtin::true` and `builtin::false`.

# SEE ALSO

[Package::Anon](https://metacpan.org/pod/Package%3A%3AAnon)

[Plack::Util::Prototype](https://metacpan.org/pod/Plack%3A%3AUtil%3A%3APrototype)

# LICENSE

Copyright (C) K.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# DERIVING AN OBJECT

    my $parent = Package::Prototype->create(
        properties => { count => { value => 0, writer => 'set_count' } },
        methods => { increment => sub { $_[0]->set_count($_[0]->count + 1) } },
    );
    my $child = Package::Prototype->derive(parent => $parent);
    $child->increment;
    print $child->count;  # 1
    print $parent->count; # 0

`derive` accepts `parent` plus the same options as `create`. The parent must
be an object made by this module. The child has its own anonymous stash; its
optional `classname` is a label, not an inheritance relationship. The parent
is fixed at creation. Chains are limited to 256 parent links.

Own members take precedence over inherited members. Adding or replacing a
parent member with `prototype` updates descendants until an own definition
shadows that name. Inherited methods receive the child as `$self`. Normal
method dispatch, `can`, caller context, exceptions, and native signatures are
preserved. A saved `can` reference retains the code it originally returned.
Each child keeps its own built-in `prototype` mutation method.

Explicit property readers initially use the nearest ancestor's value. Writing
through an inherited writer stores a value on the receiver; it does not change
the parent or siblings. Later parent writes remain visible only to descendants
that have not stored their own value. Each reader/writer pair has separate
storage, even if another declaration uses the same logical property name.
Replacing one accessor does not redefine its partner.

Values are not deep-copied. Mutating an array or hash reference returned by a
reader can affect other objects sharing that reference. Assign a new reference
through the writer to give a child a separate value. User methods that capture
external lexical state still share that state; delegation cannot isolate it.
Legacy `bless` value getters retain their existing scalar/list behavior.

The implementation registers inherited CVs in each child and propagates updates
at mutation time. Calls use Perl's normal dispatch; mutation cost grows with
the number of affected descendants. Children retain their parents. Parent links
to children are weak, so an otherwise unreachable child can be collected.
Objects that store themselves in user values can still form reference cycles.
Direct stash manipulation is unsupported; use `prototype` for updates.
Reblessing an object breaks its prototype relationships. Reblessed children
stop receiving updates; ancestry inspection rejects a reblessed parent.

Derivation does not create a new Shape declaration or infer types. Existing
`always` wrappers are inherited like other methods; replacing them bypasses
those wrappers, as it does on the parent.

# OBJECT DESCRIPTION

    my $description = Package::Prototype->describe($object);
    my $members = $description->{members};
    print $members->{count}{kind}; # property

`describe` returns a fresh hash containing `classname` and `members`.
Members are keyed by their callable names. Each entry has `kind` (`method`,
`value`, or `property`), `own`, and `depth`. Own entries have depth zero. Inherited entries have `own` false and the
number of parent links to the defining object in `depth`. These fields describe
method/accessor ownership; writing an inherited property does not make its
accessor an own definition.
Explicit property accessors also report `property` (the logical property name),
`access` (`read` or `write`), `reader`, and `writer` when declared.
Reader/writer names describe the original declaration; either accessor can
subsequently be replaced independently.

Inspection never calls methods or getters and does not return stored values or
code references. Editing the returned hashes cannot change the object.
`prototype` replacements are reflected immediately. The built-in mutation
method is omitted, but a user-defined method named `prototype` is included.
Private hash storage and UNIVERSAL methods are not members. Only objects made
by this module are supported. Type constraints are not inferred or exposed.

# AUTHOR

K <perl@codehex.dev>
