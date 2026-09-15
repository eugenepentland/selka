# Named constraints: review of the fixes

Reviewed 2026-09-15. Target: `1cb0621` plus the documentation follow-up
`89198ff` (current `main`). Earlier behavior was compared with the installed
compiler from `da3aabf` where indicated.

**The original 18 probes now have the correct outcomes. Four further issues
remain: valid callback contracts fail, schema expansion rewrites concrete type
names, ordinary generic parameters lose their default schema requirement, and
standalone constraint subjects bypass shadowing validation.**

No compiler source was changed in this review. Full reproducer sources, commands,
diagnostics, schema output, executable hashes, and compiler identities are saved
in [the probe results](named-constraints-rereview-2026-09-15-probes.json).
The earlier [review](named-constraints-review-2026-09-15.md) remains a historical
record; its original failures are fixed in the rerun.

## Findings

### 1. P2: normalization rejects valid generic callback signatures

Location: [symbolic_shapes.zig](../../src/symbolic_shapes.zig#L399), lines 399–404;
the missing type case is in `Context.sourceType`, lines 83–111.

The new `canonicalOperation` resolves every operation parameter and result with
`sourceType`. That resolver handles subject parameters, nominal applications, and
arrays, but does not construct symbolic callback signatures containing generic
parameters. It falls through to concrete catalog resolution, which reports
`E_UNKNOWN_TYPE` for `def(P) -> int effects()`.

Repro `callback_inline`:

```mylang notest
def use[P: copy + op(run(p: P, fn: def(P) -> int effects()) -> int effects())](p: P) -> int:
    return 0
def main() -> int:
    return 0
```

The earlier compiler accepts this with `check --no-cache`; the reviewed compiler
rejects it. `callback_named` fails with the equivalent named contract too.
This affects existing inline constraints even when no named declaration exists.

`callback_native` is a stronger control: a concrete `Worker` domain implements
an operation taking `def(Worker) -> int effects()`. A generic consumer invokes
that operation through its structural bound, and `main` asserts the answer is
42. The earlier compiler builds and runs it successfully; the reviewed compiler
rejects its generic signature before execution.

**Fix direction:** resolve callback parameter types, result types, and effect
ceilings recursively using the same scoped substitutions as generic body
checking. Prefer sharing that resolver. Add inline and named callback cases,
including callback results and equivalent overlapping contracts.

### 2. P2: schema substitution rewrites qualified concrete types

Location: [generic_api.zig](../../src/generic_api.zig#L169), lines 169–175;
`replaceIdentifier` implements the replacement at lines 275–311.

`typeText` replaces every identifier token equal to the subject's spelling.
A qualified member with that spelling is a concrete type, not the subject.
Consequently the checked schema can publish a type that does not exist.

Repro `schema_qualified_subject` uses three files:

```mylang notest
# types.my
module types
export T
record T:
    value: int
```

```mylang notest
# contracts.my
module contracts
import types
export C
constraint C[T] = copy + op(use(subject: T, value: types.T) -> int effects())
```

```mylang notest
# main.my
module main
import contracts
export use
def use[P: contracts.C](p: P) -> int:
    return 0
def main() -> int:
    return 0
```

`schema-project main.my --schema-report --no-cache` succeeds. The exported
`contracts::C` correctly reports `value: types.T`. However, both expanded copies
under `main::use` report `value: types.P`. Only `subject: T` should become
`subject: P`; `types.T` must keep its concrete identity.

This makes the public contract unreliable for an agent generating an
implementation or a mock without reading all implementation sources.

**Fix direction:** render resolved type expressions and substitute only the
subject reference, preserving qualified names and defining scopes. Add a test
where the qualified concrete member has the same spelling as the subject.
The related `schema_foreign_scope` probe also records that top-level expanded
members retain a bare foreign `ID` while the consumer advertises
`declaration-module-scope`; preserve the member's origin when making that
expanded contract independently interpretable.

### 3. P2: ordinary generic parameters lose default `copy` in the schema

Location: [generic_api.zig](../../src/generic_api.zig#L126), lines 126–130.

`Context.parameters` builds the builtin requirement list from explicit source
requirements and named bounds, but omits `parameter.default_copy`. The previous
schema implementation included that flag. Computing `resolved` above this loop
does not help because its builtin guarantees are not used to fill this list.

Repro `schema_default_copy`:

```mylang notest
module main
export identity
def identity[T](x: T) -> T:
    return x
def main() -> int:
    return 0
```

The earlier schema reports `requirements: ["copy"]` for `T`; the reviewed schema
reports `requirements: []`. The language still gives an ordinary `[T]` the
default `copy` requirement. Tools now see a weaker contract than the compiler
enforces, even in programs that do not use named constraints.

**Fix direction:** retain the parameter's default builtin requirement, as
`explicitBuiltins` already does elsewhere in this file. Test plain `[T]`, named
bounds, and generic nominal templates; ensure explicit non-copy bounds do not
accidentally gain `copy`.

### 4. P2: standalone constraint subjects bypass shadowing checks

Location: [generic_bodies.zig](../../src/generic_bodies.zig#L1619), lines 1619–1622.

The new loop validates unused declarations by constructing a `Checker` and
calling only `validateStructural`. Subject shadow checks run in `checkFunction`
and the module interface checker, so this standalone path skips them. The
standalone namespace pre-pass checks the outer constraint declaration name,
not the subject binder.

Repro `subject_shadow_unused`:

```mylang notest
record Item:
    value: int
constraint C[Item] = copy
def main() -> int:
    return 0
```

Standalone `check --no-cache` accepts this. Adding only `module main` and using
`check-project --no-cache` rejects it with `E_SHADOWING`: the type parameter
shadows the record. This is a remaining gap rather than a new regression in
the fix commit. The [brief](../named-constraints-proposal.md)
requires illegal subject shadowing to follow the existing rules.

**Fix direction:** share subject-name validation between module and standalone
declarations, and invoke it even for unused constraints. Test collisions with
top-level types and functions in both paths, plus builtin and import-name rules
where applicable.

## Verification

The final run used pinned copies of both installed compiler executables. This
avoided changes to the shared installed binary during the review. The probe JSON
records both executable hashes and the compilers' reported build identities.
Current source `HEAD` remained `89198ff` and tracked files were clean.

| Check | Independently observed result |
| --- | --- |
| Original review probes, fresh directories and no cache | 18/18 corrected outcomes |
| Existing inline callback contract | Earlier compiler accepts; reviewed compiler rejects |
| Named callback contract | Reviewed compiler rejects |
| Native callback implementation and assertion | Earlier compiler runs successfully; reviewed compiler rejects |
| Alias-equivalent overlapping operations | Accepted |
| Qualified subject and default-copy schema probes | Both incorrect outputs reproduced |
| Standalone/module subject shadowing pair | Standalone accepts; module rejects |
| Production named-constraints example | Native run succeeds |
| Fake-only acceptance test, forced execution | 1 passed, 0 cached, 0 failed |

These are focused review checks. The reported full unit, CLI, documentation,
formatting, and Guardian totals were not independently rerun in this review.

## Cache follow-up

The reported successful-verdict reuse across a compiler rebuild was **not
reproduced** in the tested cross-version scenario:

1. The earlier compiler incorrectly accepts `nominal_distinct_coalesce` and
   stores a successful verdict in a fresh shared cache.
2. Repeating with that compiler gives one verdict hit and succeeds.
3. The reviewed compiler, using exactly the same source files and cache, gives
   zero verdict hits, one miss, and rejects the conflicting requirements.
4. The reviewed compiler with `--no-cache` rejects the same conflict.

The two executables report different compiler identities. This verifies that
case; it does not establish that every rebuild path refreshes the identity or
the installed executable correctly. Keep the original cache note open until a
specific rebuild sequence reproduces it. Repeated schema members acknowledged
in the handoff are secondary to the incorrect schema contents above.
