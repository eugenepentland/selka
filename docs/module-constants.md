# Immutable scalar constants

Declare a module constant with an explicit scalar type:

```my
const SCALE: i64 = 6;
public const ANSWER: i64 = SCALE * FACTOR;
const FACTOR: i64 = 7;
const MASK: u8 = u8(255);
```

Integer widths and `bool` are supported. Initializers may contain scalar
literals, other visible constants, casts, and unary/binary operators. Forward
references work; dependency cycles reject even in a short-circuited operand.
Bounded calls to scalar source functions are supported as described in
[source-evaluation.md](source-evaluation.md). Allocation, aggregate construction
and external effects are excluded throughout a scalar initializer. Every constant is checked even when unused. Overflow, invalid
casts, and evaluated division by zero are compilation errors.

Short-circuit operators retain their normal runtime semantics: `false &&
(1 / 0 == 0)` is a valid false constant. Its unevaluated operand is still checked
for legal syntax, dependencies, and type correctness.

Constants use the existing module export/privacy rules:

```my
module settings;
public const ANSWER: i64 = 42;
```

Importers read `settings::ANSWER`. Generic functions may read concrete constants;
there are no generic constants yet. Constants cannot be assigned or mutably
reassigned, and they cannot replace the required `def main` entry point.

Checking folds scalar initializers before executable publication. The current typed
program represents a scalar constant as a pure zero-argument getter containing its
literal value; uses retain resolved call identities, and exported schema clients
can invoke that getter. Reading a constant therefore has normal call/frame/step
accounting, but there is no dynamic initializer, initialization order, or mutable
storage. A later optimizer can inline this representation.

Dependency/expression nesting is bounded at 256 and validation/evaluation work
at 65,536 expression, statement and name-lookup work units per evaluation.
Scalar constants are cached within one evaluation; no generated results persist
across compilation snapshots.

## String and byte literal constants

`str` and `bytes` constants require a literal of the matching type. Empty literals,
Unicode text and ordinary literal escapes work. Transparent type aliases also work.

```mylang
# doc: expect 42
const LABEL: str = "hé🙂"
const HEADER: bytes = b"\x00\x27"
const EMPTY: bytes = b""

def main() -> int effects(managed_allocation):
    return len(LABEL) + HEADER[1] + len(EMPTY)
```

The initializer must be exactly a text or byte literal: calls, concatenation,
casts, indexing, interpolation and references to other constants are rejected,
even for an unused declaration. Scalar constants retain their existing rules.

A constant may instead be initialized from `embed_bytes("path")` or
`embed_str("path")`, which reads a project file at compile time; see
[embedding a file](bytes.md#embedding-a-file-at-compile-time). Such a constant is
static data: reading it allocates nothing and contributes no effect, so it is
legal under `noalloc`.

These constants use the same export/privacy rules and can be read by generic
functions. Each getter evaluates its ordinary checked literal, allocating a
managed value; reads therefore contribute `managed_allocation` and are rejected
in `noalloc` or `effects()` functions. There is no module initialization order
or shared mutable storage. Ordinary garbage collection and allocation budgets apply.

`check`, `run`, `build --run` and installed programs use the same checked getter.
Function-body semantic caching remains disabled for programs with constants;
native object cache keys include emitted IL, so editing a literal changes its
getter object even when all callers remain unchanged. See SPEC.md `CONSTANT-2`.
