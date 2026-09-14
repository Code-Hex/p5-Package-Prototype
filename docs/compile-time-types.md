# Experimental compile-time type checks

These opt-in modules catch known type mismatches during compilation while
checking unknown values at runtime. Existing `bless`, `create`,
and `prototype` behavior remains unchanged. Type::Tiny is used in the examples
and test suite, but any type object implementing `assert_valid` is supported.

```perl
use Types::Standard qw(Int);
use Package::Prototype::Shape Counter => { count => [], set_count => [Int] };

my $value = 0;
my Counter $counter = Counter->create(
    count => sub { $value },
    set_count => sub { $value = $_[1] },
);
$counter->set_count(42);      # Compiles and runs.
$counter->set_count('bad');   # Rejected during compilation.
```

The generated factory accepts method/code pairs and wraps each declared method.
Argument validation runs before its body, so a failing setter cannot change the
captured value through that body. Wrappers preserve scalar, list and void context,
and work with native-signature bodies. Return values are not type checked.
The runtime object has an independent Package::Prototype stash; the shape label
is not an `isa` relationship to the factory package.

`Package::Prototype::Checked` (Perl 5.16+) provides named scalar identity functions:

```perl
use Types::Standard qw(Int ArrayRef);
use Package::Prototype::Checked
    integer => Int,
    integers => ArrayRef[Int];

my $n = integer(42);
my $list = integers([1, 2]);
# integers([1, 'bad']); # Compile-time error.
```

Names and shape declarations are package-scoped. Declare them with `use` before
the calls to inspect. `Shape` requires Perl 5.22; its native annotation must be
fully qualified outside `main`, e.g. `my App::Counter $obj` for a shape declared
in package `App`. The main module retains its existing minimum Perl version.

## Reproduce

After `perl Build.PL && ./Build`:

```sh
perl -Iblib/lib -Iblib/arch -c examples/checked/counter.pl
perl -Iblib/lib -Iblib/arch examples/checked/counter.pl
# Prints 42 twice; dynamic invalid input is rejected before assignment.
perl -Iblib/lib -Iblib/arch -c examples/checked/rejected.pl
# Deliberately exits nonzero, reporting rejected.pl line 7.
./Build test
```

## What is checked

| Pattern | Compile time | Runtime |
|---|---|---|
| Direct Checked function, scalar literal or undef | Validate copy | Validate actual value |
| Partial standard ArrayRef/Tuple/Dict with fixed positions/keys | Check known elements and fixed shape; defer unknown values | Validate whole value |
| Constant nested array/hash reference | Validate reconstructed copy | Validate actual value |
| Expression already folded by Perl | Validate resulting constant | Validate actual value |
| Direct named method on annotated lexical | Check declared arity and known literal arguments | Factory wrapper validates arguments |
| Lexical captured by a closure | Uses its own pad type annotation | Factory wrapper |
| Scalar variable argument | Value unknown; method arity can be checked | Validate actual value |
| Array/list expansion in method arguments | Defer the entire call | Factory wrapper |
| Function calls inside reference constructors | Defer, never execute speculatively | Validate actual value |
| Indirect or ampersand Checked call | Deferred | Identity function still validates |
| Unannotated alias or dynamic method name | Deferred | Factory wrapper, if still installed |
| Reassignment, prototype replacement, return types | Not inferred | No receiver/return-type guarantee |

Passing `perl -c` does not guarantee full type safety, as unverified dynamic
values can still fail at runtime. The `my Counter` annotation is a compile-time
declaration rather than a runtime type cast: reassigning the variable or
dynamically replacing a method can invalidate it. Replacing a method via
`prototype` bypasses the factory's runtime wrapper while leaving compile-time
declarations unchanged. Unlisted method names remain dynamic, meaning misspelled
method calls are not caught during compilation.

Compile-time checks evaluate the type constraint directly. For instance,
Type::Tiny's `Int` accepts numeric strings like `"42"`. Because constraints run
at compile time on reconstructed sample data—even inside unexecuted branches—they
must be deterministic and free of side effects. Constraints that depend on
environment variables, object identity, or external state are unsuitable. No type
coercion is performed. Reference contents may change after validation.
Structures nested beyond 64 levels are deferred to runtime.

## Partial structures

```perl
use Types::Standard qw(Int Str Dict);
use Package::Prototype::Checked record => Dict[id => Int, name => Str];
my $name = 'Alice';
record({id => 'bad', name => $name}); # perl -c rejects the known invalid id.
```

The compiler AST separates known constants, unknown expressions, array elements,
and hash entries. It never passes dummy or placeholder values to whole-value
constraints. Only canonical `Types::Standard` parameterizations of `ArrayRef`,
`Tuple`, and `Dict` (verified via `strictly_equals`) are decomposed for partial
checking. Custom type objects and subtypes with custom constraints are checked
only when fully known or at runtime.

Static validation requires literal keys and fixed-width scalar elements. The
checker rejects missing required fields/elements as well as undeclared extra
entries. Standard `Optional` slots may be omitted. Duplicate literal keys follow
Perl's last-write-wins semantics, even if the final value is unknown. Dynamic
keys or list-expanding expressions defer validation of the containing structure.
A nested unknown structure does not stop checks on other fields in its parent.
Union types, Slurpy slots, and derived `Optional` types are conservatively deferred when partially populated.

## Design notes

1. **Function call checking:** In `Perl_ck_entersub`, Perl resolves a target CV
   before running its call checker. Using `cv_set_call_checker` allows
   `Package::Prototype::Checked` to validate arguments on specific identity
   functions without registering a global hook for subroutine calls.
2. **Literal reconstruction:** The checker recognizes literals and reference
   constructors (`OP_CONST`, `OP_UNDEF`, `OP_ANONLIST`, and `OP_ANONHASH`).
   It builds private copies of known values without executing argument OPs.
3. **Lexical type pad metadata:** Core Perl verifies typed hash fields via
   `PadnameTYPE` (`Perl_check_hash_fields_and_hekify`). `Shape` uses this same
   pad metadata to bind annotated lexicals (`my Counter $obj`) to declared
   method signatures.
4. **Method dispatch hook:** Because dynamic method calls bypass CV checkers,
   `Shape` wraps `OP_ENTERSUB` with `wrap_op_checker`. Signature metadata remains
   stored in Perl package stashes rather than C-level interpreter pointers.
5. **Compile-time rejection vs. runtime checks:** Unlike tools that compile
   type-assertion wrappers into function preludes for runtime execution, this
   checker rejects invalid literal arguments during `perl -c`. Runtime wrappers
   act as fallback for deferred dynamic values.

### References

- [Perl op.c](https://github.com/Perl/perl5/blob/v5.44.0/op.c)
- [Perl pad.h](https://github.com/Perl/perl5/blob/v5.44.0/pad.h)
- [Call-checker API](https://perldoc.perl.org/5.44.0/perlapi#cv_set_call_checker)
- [OP-checker API](https://perldoc.perl.org/5.44.0/perlapi#wrap_op_checker)
- [Function::Parameters source](https://github.com/mauke/Function-Parameters/blob/master/Parameters.xs)

### Scope and limitations

Flow-sensitive type inference, branch merging, return-type analysis, and automatic
shape transitions are outside the scope of this experiment. Thread cloning has
not been verified.
