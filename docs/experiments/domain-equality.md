# Scalar domain equality

Scalar domains support `==` and `!=` when both operands have the same resolved
nominal type. Integer backings compare mathematical values at their declared
width, and boolean backings compare booleans. Independently constructed values
can be equal; allocation identity is irrelevant.

```text
domain ComponentId: u64 {
    fn make(raw: u64) -> ComponentId { return wrap<ComponentId>(raw); }
}
fn sameComponent(a: ComponentId, b: ComponentId) -> bool { return a == b; }
```

No extra opt-in or user-defined operator is required. These domains already
contain exactly one builtin integer or boolean value. Equality returns only a
boolean: construction and unwrapping retain their lexical owner restrictions.
A domain does not gain arithmetic, ordering, integer casts or interchangeability
with its backing type. Two separately declared domains with identical backing
types remain incompatible, including same-spelled declarations in other modules.
Different import aliases for the same declaration preserve identity.

Scalar domains satisfy `T:equality` and `T:copy`, but not `T:integer`. Ordinary
records, arrays and unions do not acquire structural equality from this change.
Nested or aggregate domain backings remain unsupported. If domain backings are
extended later, equality for those types needs an explicit design decision.

The typed IR retains the ordinary binary expression with its nominal operand
type. Lowering emits `CMP_DOMAIN`, rather than synthesizing privileged unwrap
instructions in an unprivileged caller. Bytecode validation requires a scalar
domain schema and two stack operands. The VM checks exact operand identities,
single-field shape and backing types, releases both operands, and returns one
boolean. It evaluates left before right and preserves execution limits and traps.
The historical C emitter rejects this instruction with `E_NATIVE_FEATURE`;
implementing a guest-native backend remains outside the active roadmap.

The board trial now compares IDs directly in its component/net membership loops,
removing both `same` helpers from its ID definitions. Parameterized composite
types remain a separate open abstraction problem.

`src/domain_equality_test.zig` covers all eight integer widths, signed minima,
maximum unsigned values, booleans, generic requirements, cross-module identity,
forbidden operations, malformed instruction types and runtime operand mismatch,
allocation-failure cleanup, bounded loops, step limits and trap evaluation order.
The existing board oracle checks unchanged outcomes and geometry callback counts.
These are development regressions, not measured agent repair outcomes.
