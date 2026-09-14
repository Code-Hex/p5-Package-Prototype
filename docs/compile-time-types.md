# Experimental compile-time type checks

The opt-in modules combine compile-time rejection of known invalid arguments
with runtime checks for unknown values. They do not change `bless`, `create`, or
`prototype` in existing applications. Type::Tiny is used in the examples and
required for this distribution's tests, but is not a mandatory runtime dependency
of Package::Prototype. Type objects must implement `assert_valid`.

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

Unknown is not the same as valid. `perl -c` succeeding is not a certificate of
type safety. `my Counter` is a declaration used for checking, not a runtime cast.
Reassigning the variable or replacing a method can invalidate that declaration.
Replacing a method with `prototype` bypasses the factory's original runtime
wrapper and leaves the declaration unchanged. Unlisted method names are left
dynamic, so method-name typos are not rejected by this checker.

Checks have runtime constraints' semantics: for example Type::Tiny `Int` accepts
numeric strings such as `"42"`; it is not a JavaScript/TypeScript `number` type.
Constraints must be deterministic and side-effect-free. They execute during
compilation on private samples, including when a branch will not execute. Custom
constraints that depend on environment, identity or changing state are unsuitable.
There is no coercion. Mutable reference contents can change after validation.
Nesting deeper than 64 levels is conservatively deferred.

## Source investigation and design decisions

1. **Specific call checker.** Perl's `Perl_ck_entersub` resolves a CV before
   invoking its call checker. `cv_set_call_checker` lets Checked attach validation
   without installing a global hook for ordinary function calls. Normal dynamic
   method dispatch does not reach that CV checker, so this alone was insufficient.
2. **Literal OP inspection.** `B::Concise` exposed OP_CONST, OP_UNDEF, OP_ANONLIST
   and OP_ANONHASH. A recursive allowlist reconstructs only literal data. Unknown
   OPs are deferred; no source-string eval or execution of argument OPs is used.
3. **Native typed pad names.** Core `Perl_check_hash_fields_and_hekify` uses
   `PadnameTYPE` to check fields on annotated lexicals. Shape uses the same pad
   metadata to select a declared method signature. This avoids guessing object
   identity from preceding assignments or variable spelling.
4. **Method hook.** Shape chains OP_ENTERSUB through `wrap_op_checker`. The previous
   C hook pointer is process-global, following core's contract; signature values
   remain Perl-owned in package hashes, without raw cross-interpreter SV pointers.
5. **Runtime checks generated during compilation are different.**
   Function::Parameters' `mktypecheckv` and function-prelude construction insert
   checks executed when a function runs. This informed runtime fallback, but does
   not by itself reject bad call sites under `perl -c`.

Sources inspected: Perl 5.44.0 `op.c` (Perl_ck_entersub,
Perl_check_hash_fields_and_hekify, Perl_wrap_op_checker), `pad.h`, and
Function::Parameters `Parameters.xs` (mktypecheckv and function prelude).

- [Perl op.c](https://github.com/Perl/perl5/blob/v5.44.0/op.c)
- [Perl pad.h](https://github.com/Perl/perl5/blob/v5.44.0/pad.h)
- [Call-checker API](https://perldoc.perl.org/5.44.0/perlapi#cv_set_call_checker)
- [OP-checker API](https://perldoc.perl.org/5.44.0/perlapi#wrap_op_checker)
- [Function::Parameters source](https://github.com/mauke/Function-Parameters/blob/master/Parameters.xs)

Assignment-flow inference, branch merging, method-return inference and automatic
prototype-shape evolution are intentionally outside this experiment. Thread
cloning has not been exercised by the current runtime tests.
