[![Actions Status](https://github.com/Code-Hex/p5-Package-Prototype/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/Code-Hex/p5-Package-Prototype/actions?workflow=test)
# NAME

Package::Prototype - Create objects with JavaScript-style prototypes

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
            # Keys starting with '_' do not create methods.
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

Package::Prototype creates objects with JavaScript-style prototypes. You can
define methods and properties on individual objects and derive new objects
that delegate to a parent.

Each object has its own anonymous package. An optional class name labels the
package; objects with the same label still have independent method definitions.

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

    Creates an object in a new anonymous package. The optional `$classname`
    argument sets its label and defaults to `__ANON__`.

    Keys that do not start with `_` become methods. Code references are installed
    as methods; other values get a getter with the same name as the key.

        my $obj = Package::Prototype->bless({
            foo => 10,
            bar => sub { say $_[1] },

            # Keys starting with '_' do not create methods.
            _data => "internal data"
        });

        say $obj->foo; # 10
        say $obj->bar("Hello");

        # $obj->_data is not provided

- `prototype($key :Str => $val :Any, ...)`

    Adds or replaces methods on an object. Code references become methods; other
    values become getters.

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
no arguments. Writers accept one value and return the assigned value.

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
`value`, or `property`), `own`, and `depth`.

An own member has `own` true and `depth` zero. An inherited member has `own`
false; `depth` counts the parent links to the object that defines it.

Writing an inherited property stores a value on the child. Its reader and writer
remain inherited, so their `own` and `depth` fields do not change.

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

# EXTRACTING VALUES

    my $data = Package::Prototype->to_hashref($object);
    my $selected = Package::Prototype->to_hashref($object,
        fields => { total => 'get_count' },
    );

`to_hashref` returns a new, unblessed hash reference. By default, it includes
explicit properties under their logical property names and legacy value
getters under their callable names. It excludes ordinary methods, writers,
private hash storage, and prototype metadata. Inherited readers are called on
the supplied object, so the result contains that object's current values.
Two readers producing the same output key cause an exception.

Optional `fields` maps output keys to callable reader names. It selects and
renames values, and can resolve ambiguous property names. An empty hash selects
no values. Every selected name must be an existing property reader or legacy
value getter; ordinary methods and writers are rejected. All selections are
validated before any values are read. Readers are called in scalar context.

Replacing a reader with an ordinary method removes it from automatic output.
Explicitly selecting that replaced reader raises an exception. Replacing a
writer does not remove its reader. Use `fields` for a fixed output schema.

This is a shallow extraction: referenced arrays, hashes, objects, and code
remain shared. `undef` and boolean values are preserved. Changing a top-level
entry in the result does not assign a property, but mutating a shared reference
can affect the original object. Cycles are not traversed or rejected.

Unlike `describe`, extraction invokes readers. It is not an atomic snapshot
and does not promise side-effect-free reads of magical values. Reader exceptions
propagate. The result is not guaranteed to be accepted by a serializer; callers
must handle unsupported values for their chosen format. No class, methods, or
parent relationships are reconstructed from the result.

# SEE ALSO

[Package::Anon](https://metacpan.org/pod/Package%3A%3AAnon)

[Plack::Util::Prototype](https://metacpan.org/pod/Plack%3A%3AUtil%3A%3APrototype)

# LICENSE

Copyright (C) K.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

K <perl@codehex.dev>
