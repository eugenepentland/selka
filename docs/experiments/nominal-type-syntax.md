# Nominal type template syntax and interfaces

This document describes the syntax and module-interface foundation for
parameterized records and variants. Subsequent [declaration checking](nominal-template-checks.md),
[finite layout checking](nominal-layouts.md), and [concrete specialization](nominal-instances.md)
now let concrete instances execute on the VM. Generic function bodies containing
parameter-dependent nominal applications remain pending. Generic fixed arrays
remain executable as documented in [their contract](generic-arrays.md).

The parser can now retain declarations such as:

```text
struct Pair<T:copy,U:copy> { first: T, second: U }
union Slot<T:copy> { none, some: T }
result Outcome<T:copy,E:copy> { ok: T, err: E }
enum Tag<T:copy> { left, right }
```

Type applications use `Pair<i64,bool>` and `Slot<Pair<i64,bool>>`. A function
call still uses `function::<Type>(arguments)`. Applications are retained in type
annotations, nested array elements, explicit call arguments, record/variant
construction and match-arm type names. All these forms require later semantic
checking; parsing does not establish an application has a valid layout or that a
constructor matches its fields.

Each application retains a complete span, the base declaration-name span and
ordered argument spans. Declaration parameters retain their names and explicit
requirements. `TypeExpressions` groups numeric/enum arrays and nominal
applications separately from declaration categories. Owned AST copies and
project merging recursively preserve this metadata and source locations;
syntax-cache copies do not borrow the lifetime of the original project.

Parameter and argument lists retain the existing 16-entry bound, duplicate
parameter/requirement checks, and 256-level parser nesting bound. The parser can
separate a type-closing `>` from an immediately following assignment `=` in
`let x:Box<i64>=...`; the lexer still treats `x>=y` as a comparison in expression
context. The formatter uses parsed application/declaration positions to distinguish
nominal angle brackets from comparisons, keep argument commas within their list,
and retain comments. It emits a separating space before assignment and remains
idempotent.

Module interface checking resolves the base through its declaration identity and
direct import alias, checks the exact number of type arguments, and recursively
checks exported visibility of concrete arguments. A private generic base or a
private type nested in a public application is rejected. Bare generic type names
require arguments, ordinary types cannot receive arguments, and a type parameter
cannot act as a higher-order type constructor. Nominal parameters cannot shadow
module declarations or imports. Unknown requirement names reject even in private
nominal declarations.

This interface phase does **not** prove field layout, application requirement
satisfaction, recursive-type finiteness, ownership, generic field operations or
exhaustive matching. Those belong to the subsequent semantic stages.
Supporting syntax for result and enum templates does not commit to unchecked
payloads, implicit equality or new ownership rules. Ordinary source compilation
now executes concrete applications and programs with valid unused templates.

`src/nominal_type_syntax_test.zig` exercises nested syntax, constructors/patterns,
source spans, owned copying, allocation failures, formatting/comments/operator
ambiguity, limits, cached module relocation, interface privacy/arity/kind/scope
errors and explicit unsupported symbolic-body diagnostics. `test/integration.zig`
checks the actual formatter, unused declarations and structured CLI diagnostics. This is a foundation checkpoint,
not completion of the parameterized-record/union roadmap item. No guest-native
backend work is included.
