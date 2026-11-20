# Declared structural generic contracts

Function templates can declare copied record fields and public domain operations.
The compiler checks their bodies before any concrete call, checks every concrete
argument, and checks implication when a type parameter is forwarded to a helper.
No representative record or guessed method is substituted during universal checking.

```my
func value[T: copy + field(value: i64)](item: T) -> i64:
    return item.value


func selected[T: copy + field(value: U), U](item: T) -> U:
    return item.value


func score[T: copy + op(score(item: T) -> i64 effects())](item: T) -> i64 effects():
    return T.score(item)
```

`field` names a required field and its exact type. Different record declarations
may satisfy the same contract, and extra fields are retained by a record update. Nominal
type identity is never erased: equally shaped domain IDs or unrelated type
parameters remain different types. Field requirements require `copy`, and each
promised field must also be copyable without result obligations. Consequently
unknown extra fields cannot hide owned values or unhandled results. A domain's
private representation never satisfies a structural field requirement.

Declared fields support ordinary projection and record updates.
The contract is a minimum field inventory, so it cannot justify `new T { ... }`:
construction requires knowledge of every field and rejects even in an uncalled
template. Undeclared fields are also rejected before instantiation.

`op` describes a type-owned domain method: named arguments, exact value/reference
types, a value result, and an explicit effect ceiling. Invocation is `T.score(v)`;
there is no implicit free-function search or runtime method lookup. A concrete
method must be public, nongeneric, non-conversion, and explicitly effect-bounded.
Its declared effects may be a subset of the required ceiling. Its body remains
subject to ordinary effect checking. The generic caller conservatively receives
the full operation ceiling, independent of which implementation is later chosen.

Operation arguments are ordinary values. Result-obligation rules apply to calls:
returned checked results must be handled or transferred as usual. Required
operations cannot grant access to private domain representation or private methods.

Forwarding checks field names and substituted field types, and checks operation
names, argument/result types and effect ceilings. A helper's
stronger requirements cannot be inferred from its current body or from one concrete
call. Missing declarations reject the forwarding template even when it is unused.

Current deliberate limits:

- Structural requirements belong to function templates. Declaring them on nominal
  type parameters rejects explicitly; ordinary existing nominal constraints remain.
- Signature types are named concrete types or type parameters, including qualified
  module names. Inline arrays and generic applications in structural contracts
  reject explicitly.
- Fields describe records; operations describe domains. This does not introduce
  methods on records, arbitrary operator overloading or implicit duck typing.
- The existing limits of sixteen type parameters and sixteen total requirements
  per parameter apply. Each operation has at most sixteen arguments. Generic body,
  shape and specialization budgets remain active.

Malformed declarations report `E_GENERIC_REQUIREMENT`. Unsatisfied concrete or
forwarded operation contracts report `E_GENERIC_ARGUMENT`; symbolic field/type
mismatches retain `E_UNKNOWN_FIELD`, `E_GENERIC_TYPE` or the existing unsupported
shape diagnostic. Effect violations retain their ordinary stable codes.
Source spans survive module linking, syntax copies and formatting.

Use the installed compiler with `examples/structural-constraints.my`:

```sh
zig-out/bin/mylang run examples/structural-constraints.my --print-result
# 12
zig-out/bin/mylang fmt --check examples/structural-constraints.my
```

`src/structural_constraints_test.zig` covers independent record shapes, cross-parameter
field types, updates, universal failures, forwarding, private/missing/wrong methods,
effect ceilings, mutable references and alias rejection, imported dispatch,
formatter idempotence and cleanup under allocation failure. Source JSON's separate
`codec` requirement is implemented by the serialization work; it does not imply
`copy`, structural field visibility or access to a domain's backing representation.

## Composite signatures

Contracts accept fixed arrays and nominal applications, including parameterized
fields such as `T:copy+field(items:[2]U)+field(box:Box<U>)`. Signature substitution
uses the same array and nominal identities as ordinary function specialization;
array lengths and nested nominal arguments must match exactly. Contracts may
borrow slices and whole owners, for example `op(fill(b:&mut Buffer<i64>)->Status
 effects())`. A borrowed result obligation remains invalid, and field contracts
still require copyable records and fields. Returned-reference operation contracts
and structural requirements on nominal declarations remain separate work.
