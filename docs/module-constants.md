# Immutable scalar constants

Declare a module constant with an explicit scalar type:

```my
const SCALE: i64 = 6;
const ANSWER: i64 = SCALE * FACTOR;
const FACTOR: i64 = 7;
const MASK: u8 = cast<u8>(255);
```

Integer widths and `bool` are supported. Initializers may contain scalar
literals, other visible constants, casts, and unary/binary operators. Forward
references work; dependency cycles reject even in a short-circuited operand.
Calls, allocation and aggregate construction are excluded throughout an
initializer. Every constant is checked even when unused. Overflow, invalid
casts, and evaluated division by zero are compilation errors.

Short-circuit operators retain their normal runtime semantics: `false &&
(1 / 0 == 0)` is a valid false constant. Its unevaluated operand is still checked
for legal syntax, dependencies, and type correctness.

Constants use the existing module export/privacy rules:

```my
module settings;
export ANSWER;
const ANSWER: i64 = 42;
```

Importers read `settings::ANSWER`. Generic functions may read concrete constants;
there are no generic constants yet. Constants cannot be assigned or mutably
borrowed, and they cannot replace the required `fn main` entry point.

Checking folds initializers before executable publication. The current typed
program represents a constant as a pure zero-argument getter containing its
literal value; uses retain resolved call identities, and exported schema clients
can invoke that getter. Reading a constant therefore has normal call/frame/step
accounting, but there is no dynamic initializer, initialization order, or mutable
storage. A later optimizer can inline this representation.

Dependency/expression nesting is bounded at 256 and validation/evaluation work
at 65,536 visited nodes per evaluation. Scalar values are cached within an
evaluation; this is not a general compile-time guest execution facility.
