# A2: closed enums, tagged unions, and exhaustive matching

Status: implemented. Together with nominal domains/private construction, this
completes the variant and matching portions of A2. Complete enum-indexed tables
remain pending; numeric fixed arrays are not a substitute for that contract.

## Declarations and construction

```text
enum Color { red, green, blue }
struct Point { x: i64, y: i64 }
union Shape { point: Point, radius: i64, empty }

fn score(shape: Shape) -> i64 {
    match shape {
        Shape.empty => { return 0; },
        Shape.radius(r) => { return r * r; },
        Shape.point(p) => { return p.x + p.y; }
    }
}

fn main() -> i64 {
    return score(new Shape.point(new Point { x: 2, y: 3 }));
}
```

Enums contain named, payload-free variants. Tagged unions contain named variants
with either one declared payload type or no payload. Payloads can be scalar,
domain, record, array, enum, or another finite union type. Forward declarations
are resolved before bodies. All types are nominal; identical names/layouts in
different type declarations do not make their values interchangeable.

Both declarations require at least one variant. Duplicate names, unknown payload
types, and recursive by-value layouts are rejected. Recursive unions through
records or arrays are also rejected under the initial acyclic type policy.
Declaration and arm lists use commas without trailing commas. `enum`, `union`,
and `match` are reserved keywords.

`new Type.variant` constructs a payload-free variant. `new Type.variant(value)`
constructs a variant with exactly the declared payload type. A payload cannot be
omitted, supplied to an empty variant, or implicitly coerced. Construction evaluates
the payload once and preserves its errors. Tags have no user-selected integer
values or integer casts. The declaration order is an implementation detail, not
a serialized ABI or external ordinal contract.

Enums support `==` and `!=` with the same nominal enum type, comparing the active
variant. Numeric arithmetic/ordering is not defined. Tagged union equality is
not implicit; use matching to express the intended comparison.

## Exhaustive match statements

`match expression { Type.variant => { statements }, ... }` evaluates its
scrutinee exactly once and executes exactly one arm. It requires the scrutinee
to be an enum or union, and every variant must appear exactly once with the same
nominal type. There are no wildcard, default, guard, or multi-variant arms in this
initial form. Adding a variant breaks every old match until an explicit arm is
added, even when the matched expression happens to construct a known variant.
Missing-variant diagnostics name the variant and point to its declaration;
duplicate arms point to the earlier arm.

A payload arm must use `Type.variant(name)` to introduce an immutable binding,
or `Type.variant(discard)` to ignore the payload explicitly. Empty variants take
neither. Bindings have the exact payload type, cannot shadow an active binding or
top-level name, and exist only inside their arm. Sibling arms can reuse a name.
Unused bindings receive the ordinary warning; `_` remains an ordinary identifier.
Payload access through a raw field, numeric index, or cast is not allowed.

Bindings are immutable values. Retaining a payload lets it survive replacement
of the original union binding. An explicit discard still evaluates construction
and releases the payload; it never erases a trap. Unselected arm bodies do not
execute, but all arms are type-checked, including unreachable-in-practice cases.

A match structurally terminates only if every arm terminates. Otherwise it joins
the following statement. Empty arm blocks, mutation of outer mutable bindings,
loops, and nested matches work with the existing control-flow rules. There is no
match expression yet; use a helper function returning from every arm to produce
a value. The declarative `conversion fn` body restriction is unchanged; ordinary
helpers can use matches to transform explicitly selected source fields.

## Runtime, validation, and analysis

Variants use immutable retained storage with a checked active tag and zero or one
payload. The VM uses `MAKE_VARIANT`, `SWITCH_VARIANT`, and `CMP_ENUM` instructions.
Dispatch checks the type/tag, retains the selected payload into its resolved local
slot when needed, releases the scrutinee, and jumps directly to the selected arm.
Construction, dispatch, copies, calls, and traps use the established ownership
paths. Variant values currently allocate host storage, including empty variants.

The emitter resolves all arm labels and validates tags, exhaustive dispatch-table
lengths, branch targets, stack heights at joins, and payload destination types.
Ordinary record construction/update and field projection cannot forge or expose
variant representation. There is no untrusted bytecode loader or guest pointer
interface. The existing local-slot policy retains values until overwrite or
function exit; later resource lifetimes remain a separate roadmap contract.

Exact duplicate discovery `exact-v6` preserves nominal types, variant names,
constructor payloads, arm order/mappings, and resolved payload binding slots.
Renaming local payload bindings still permits an exact match. Arm reordering
remains a meaningful structural difference in this initial exact analysis.

## Evidence

- `src/variants_test.zig` verifies constructor/nominal errors, enum comparisons,
  exhaustive added-variant failures, payload binding/discard, scoping, mutation
  rejection, warning identity, source evaluation, return analysis, joins, loops,
  nested matches, recursive schema rejection, and bytecode validation.
- A payload remains usable after overwriting its parent union. Nested record/array
  payloads survive copies and calls. Allocation-failure sweeps cover schemas,
  construction, dispatch fixups, binding, disassembly, and duplicate discovery.
- A 10,000-update state-machine loop fits a 4 KiB live runtime budget. Instruction
  traps at every executed boundary of a nested-payload program release all runtime
  storage; successful executions also finish with zero outstanding bytes.
- Actual CLI tests run `examples/variants.my` (24), inspect enum/union/dispatch
  dumps, and reject newly incomplete matches across all four commands.
- The complete suite passes 112/112 tests in Debug and ReleaseFast (94 core,
  18 actual CLI), on Guardian's `0.17.0-dev.1683+5ceec001b` snapshot.
