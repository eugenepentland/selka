# Abstract calls between generic templates

The symbolic body checker now supports calls between templates in its pure subset.
This extends abstract validation; executable specialization is still unfinished.

```text
fn identity<U: copy>(value: U) -> U { return value; }
fn forward<T: integer>(value: T) -> T {
    return identity::<T>(value);
}
```

The call is valid because `integer` implies `copy`. Reversing that relationship
fails with `E_GENERIC_ARGUMENT`: knowing that a value is copyable does not promise
integer operations. Concrete builtin type arguments are checked by the same
requirement matcher; for example, `bool` cannot satisfy `integer`.

## Identity and substitution

A compilation-local index maps resolved function declarations to their AST
signatures. Module-qualified identities keep same-named functions distinct.
Domain member spelling is shared with concrete checking. Existing module export
and domain-private rules apply before a call is accepted.

Every generic call requires an explicit type argument for each type parameter.
Type-argument count and value-argument count are checked separately. The callee's
parameter and result types are substituted with the caller's symbolic identities
or concrete builtin types. Reordering parameters does not merge identities:
`T` and `U` stay distinct even when they declare identical requirements.

Requirement failures retain the argument span and a related callee declaration
span, including when those locations belong to different modules. Unknown calls,
private access, and signature mismatches remain normal located diagnostics.

Self-recursive and mutually recursive calls check signatures without recursively
checking or expanding callee bodies. The outer pass checks every generic body
once against its own declaration. This avoids inferring a stronger promise from
one caller and does not create an unbounded specialization tree. Actual instance
interning and its resource limits remain separate unfinished work.

## Explicit boundaries

Calls to nongeneric helpers still require concrete type/effect summaries and are
rejected with `E_GENERIC_BODY_UNSUPPORTED`. Reference arguments/results,
conversions, and nominal/composite type substitution remain unsupported here.
Effectful operations in a called template are still rejected by that template's
body check. Acceptance of a call does not bypass checking its callee or establish
an effect summary for an unchecked foreign/concrete function.

Ordinary entry functions do not yet receive executable generic-call lowering.
A valid abstract call graph still ends with `E_GENERIC_UNSUPPORTED` from overall
semantic checking. No VM/native executable or binding support is claimed.

## Acceptance and next work

Fixtures cover stronger-to-weaker requirement forwarding, invalid forwarding,
concrete builtin rejection, type-parameter permutation, identity mismatches,
missing/extra type and value arguments, recursion, private methods, imported
public domain methods, same-named functions in different modules, related source
locations, and allocation failures in local and module-backed call checking.

Next: bounded concrete instance interning, discovery from entry/exports,
substitution while retaining module/source provenance, integration with ordinary
semantic/effect checks and VM/C lowering, and the remaining abstract body forms.
Generics and the full roadmap remain active work.

Validation: the full core suites passed 559 tests in Debug and ReleaseFast, all 60
CLI tests passed, and final generic-focused acceptance passed 25 tests. The build
gate passed all 88 Guardian checks without baselines. This validates abstract
calls and ordinary-language regressions; executable generic specialization and
completion of the broader roadmap remain unproven and unfinished.
