# Nominal template declaration checking

Parameterized records and variants now have declaration-scoped semantic metadata.
The checker validates their fields and payloads even when no function uses them.
**Concrete layout specialization and execution are still pending.** The subsequent
[layout-checking stage](nominal-layouts.md) now verifies finite storage dependencies. A valid
nominal template still ends with `E_GENERIC_TYPE_UNSUPPORTED`; malformed
metadata reports the specific error first. No typed IR or bytecode is emitted.

For example, this unused declaration now reports `E_GENERIC_REQUIREMENT` on `U`,
with a related location pointing to `Key`'s requirement:

```text
struct Key<T:equality> { value: T }
struct Bad<U:copy> { key: Key<U> }
fn main() -> i64 { return 0; }
```

Changing `U:copy` to `U:equality` satisfies that declaration constraint. It does
not yet make the program executable: the remaining specialization boundary is
reported afterward.

## Identities and expressions

`src/nominal_templates.zig` collects records, variants and the ordinary named
types their fields can reference. Module-aware names resolve to declaration
ordinals, so identically spelled and shaped types in different modules remain
distinct. Repeated references to one imported declaration retain one identity.
Parameters are local ordinals in their enclosing declaration, not guessed
concrete types. Fields retain recursive arrays and nominal applications with
ordered argument expressions and original source spans.

The collector rejects unknown field/payload types, parameter shadowing of types,
functions or imports, duplicate fields/cases/types, empty variants, malformed
result schemas, bare templates, wrong argument counts and use of a parameter as
a type constructor. It resolves references using existing module privacy rules.
Result declarations still require exactly the payload-bearing `ok` and `err`
cases. Numeric array lengths and enum key categories are checked; arrays depending
on type parameters still require numeric lengths.

## Requirement checking

Argument validation uses declared `copy`, `equality` and `integer` guarantees,
including their existing implications. It checks nested applications and enum
key applications as well as direct fields. An integer-backed domain supports
equality but does not satisfy `integer`. Records and tagged unions do not gain
implicit equality from their fields. Closed enums and pool handles keep their
existing equality guarantees.

Copy guarantees propagate through forward-declared records and unions. Owners
and pending results remove copy from their containing types, including generic
types with concrete owned fields. A zero-length array contributes no value or
result obligation, but its element type and any nested argument requirements
must still be valid. Nominal argument requirements apply even to phantom
parameters. All currently supported parameter requirements imply copy.

Propagation uses a reverse dependency worklist; each declaration loses its copy
guarantee at most once. It does not expand layouts or recurse along declaration
chains. Recursive expression processing is bounded at 256 levels and 100,000
visits per collector. All metadata uses the compilation arena, and allocation
failure propagates without leaving an executable program. Metadata uses the
explicit compilation allocator even when the diagnostic sink has a separate
allocator; tests sweep that ownership boundary as well.

These guarantees are conditional on a valid finite type layout. This metadata collector
does not itself prove by-value finiteness; [the layout graph](nominal-layouts.md)
now supplies that separate check. It does not allocate executable instance IDs, check
function-body uses of parameterized fields/payloads, or establish borrowing and
arena behavior for those operations. It cannot be used as a full program
acceptance verdict. The existing lowering boundary remains in place until those
rules are implemented.

## Evidence and next work

Ten new core tests cover metadata identity, parameter scope, malformed unused
declarations, nested requirement implication, transitive ownership/results,
array boundaries, exact checking-work exhaustion, imported identities and
cross-module diagnostic locations. They include allocation-failure sweeps and a
1,200-record reverse-ordered dependency chain. An actual CLI test checks structured
requirement and unknown-type errors from unused templates.

Next: concrete catalog specialization using the finite layout graph, followed by
symbolic record/variant operations and the board trial's shared `Slot<T>` types.
This checkpoint does not complete the nominal-type roadmap item or the measured
agent-repair study. Native guest compilation remains outside the active goal.
