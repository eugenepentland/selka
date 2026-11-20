# Local-reasoning syntax: implementation plan for items 1–6

Status: plan, 21 September 2026. Nothing below is implemented. This document
takes the six proposals selected for implementation from
[the audit](local-reasoning-syntax-audit-2026-09-21.md) and states each one as a
rule the compiler enforces, with the decisions an implementer would otherwise
have to make, the code it touches, the tests and documents Guardian will demand,
and a check that says when it is done. Items 7–10 of the audit are out of scope
here and stay where they are.

Every "today" example was run against the installed compiler on 2026-09-21;
every "after" example and every diagnostic text is proposed wording. File and
line references are to the working tree at `dcbcc2fd`.

| # | Item | Kind of change | Depends on |
| --- | --- | --- | --- |
| 1 | `mut` on parameters and at call sites | semantics (mutation contract) | — |
| 2 | Effects derived from the signature; unused capability is an error | semantics (effect contract) | 1 |
| 3 | `Option` methods `unwrap_or`, `is_none`, `is_some`; sentinel lint | intrinsic methods + lint | — |
| 4 | Tuples | new value shape | — |
| 5 | Keyword-only parameters; positional-literal lint | parser + arity rule + lint | — |
| 6 | Conditional expression | parser + one typed node | — |

## Rules that apply to every item

These come from `CLAUDE.md`, `guardian.toml` and the documentation gate; none
is optional, and each one blocks `zig build` or `zig build test`.

- **Spec tag per behavioural line.** Every added behavioural line under `src/`
  needs a test carrying `// spec: TAG` and a matching `- [TAG] …` bullet in
  `SPEC.md`; extra tests for the same bullet use `// spec-case:`. Tags proposed
  below follow the existing style (`MUTATION-MARKER-1`, `OPTION-FLOW-1`).
- **A feature slug with a runnable example.** Each item adds an entry to
  `src/features.json` under `implemented` with `{kind, summary, doc}`, and the
  `doc` anchor must resolve to a section whose fenced `mylang` block runs under
  `mylang doctest`. `mylang doc-coverage .` names anything missing.
- **Tests in the language where the behaviour is guest-visible.** A
  `public def test_*() -> bool` in `tests/lang/<area>.my`, run by `zig build
  test-lang`; diagnostics and formatter behaviour stay Zig tests in
  `src/root_test.zig`; CLI behaviour in `test/integration.zig`.
- **Every rejection carries its fix.** The evidence in the audit record is
  that a rejection that names the paste costs an agent 0 turns and one that
  does not costs 1. Each diagnostic below is written with the paste in it.
- **Formatter round-trip.** New syntax must survive `fmt` unchanged
  (`zig build fmt-check` and the `python_format_test.zig` cases).
- **Interface surfaces agree.** `list-interfaces`, `context`, `schema-project`,
  `index-project` and `api-diff` render the new signature elements, and the
  interface fingerprint (`interface_sha256`) includes them.
- **Removed spellings say what replaced them.** A construct this plan retires
  reports `E_REMOVED_SPELLING` naming the replacement and gets a row in
  `docs/legacy/README.md`.
- **The full gate before merging:** `zig build test --summary all`,
  `zig build test-qbe --summary all`, `zig build test-qbe-build --summary all`,
  `zig build fmt-check`.

## Suggested order

Items 5, 6 and 3 are independent and small; 4 is independent and medium; 1 and
2 are one semantic change in two steps and the largest. Three parallel lanes
work: **(5, 6)**, **(3, 4)** and **(1 then 2)**, with the corpus migration for 1
and 2 done last by script. Items 1 and 2 touch `sema.zig`, `origins.zig` and
`effects.zig`; the other lanes should stay out of those files to keep merges
mechanical.

---

## 1. A call changes exactly its receiver and its `mut` arguments

### Rule

A parameter the function writes through is declared `name: mut T`. An argument
passed to such a parameter is written `mut argument`. A method call may change
its receiver and nothing else. The marker is required exactly where the
compiler infers a write, in both directions: a write through an unmarked
parameter is an error, and a `mut` parameter that is never written is an error.
`mut` supplies the `mutation` effect and the mutation footprint, so the
`mutates(...)` clause and the opt-in `&` marker are retired.

### Today

```text
# doc: not-mylang
record Item:
    name: str
    count: int

class Inventory:
    items: list[Item]
    total: int

def restock(inv: Inventory, name: str, amount: int) -> None:
    inv.items.append(Item(name=name, count=amount))
    inv.total = inv.total + amount

def report(inv: Inventory, out: Stream) -> None:
    out.print(inv.total, len(inv.items))

def main(out: Stream) -> int:
    inv = Inventory(items=[], total=0)
    restock(inv, "bolt", 5)      # changes inv — no diagnostic, nothing at the call
    report(inv, out)             # does not — indistinguishable from the line above
    return 0
```

This runs and prints `5 1`. `restock` gets no diagnostic because `Inventory`
is a `class` and `origins.zig:621` (`isClassParameter`) exempts reference
parameters from `W_MUTATES_MISSING`. Had `inv` been a `list`, the author would
have been warned (`W_MUTATES_MISSING`, `origins.zig:673`) and the call line
would still be unmarked. The opt-in `--mutation-markers` flag
(`[MUTATION-MARKER-1]`, `sema.zig:3597`) requires `&` only for positions in a
*declared* `mutates(...)` clause, so it inherits both gaps.

### After

```text
# doc: not-mylang
def restock(inv: mut Inventory, name: str, amount: int) -> None:
    inv.items.append(Item(name=name, count=amount))
    inv.total = inv.total + amount

def report(inv: Inventory, out: Stream) -> None:
    out.print(inv.total, len(inv.items))

def main(out: Stream) -> int:
    inv = Inventory(items=[], total=0)
    restock(mut inv, "bolt", 5)
    report(inv, out)
    return 0
```

Receivers stay unmarked:

```text
# doc: not-mylang
inv.items.append(item)      # receiver: may change, no marker
counts.sort()               # receiver: may change, no marker
restock(mut inv, "nut", 2)  # argument: marker required
```

A list parameter reads the same way, and the trailing clause disappears:

```text
# doc: not-mylang
# before
public def normalize(host: Host, parts: list[Part], pins: list[Pin]) effects(host, managed_allocation, mutation) mutates(parts, pins):
circuit.normalize(host, parts, pins)
# after
public def normalize(host: Host, parts: mut list[Part], pins: mut list[Pin]) -> None:
circuit.normalize(host, mut parts, mut pins)
```

### Diagnostics

```text
main.my:17:13: error[E_MUTATION_MARKER]: `restock` writes `inv`; write `restock(mut inv, "bolt", 5)`
main.my:9:5: error[E_MUTATION_MARKER]: this function writes `inv` (parameter 1); declare it `inv: mut Inventory`
main.my:13:12: error[E_MUTATION_MARKER]: `inv` is declared `mut` but never written; remove `mut`
main.my:17:13: error[E_MUTATION_MARKER]: `report` does not write `inv`; remove `mut`
main.my:17:13: error[E_MUTATION_MARKER]: `mut` requires an assignable argument (a variable, field or list slot); assign it to a local first
main.my:5:22: error[E_MUTATION_MARKER]: `mut` on `int` has nothing to write; only a list, dict, class, Cell, array, byte buffer or a record holding one can be `mut`
main.my:9:56: error[E_REMOVED_SPELLING]: `mutates(...)` was removed; mark each written parameter `name: mut T`
main.my:17:13: error[E_REMOVED_SPELLING]: `&` was removed; write `mut inv`
```

The "never written" case includes forwarding: a parameter passed as `mut` to
another call counts as written, so a wrapper that only forwards is correctly
`mut`.

### Decisions

| Decision | Choice | Alternative considered |
| --- | --- | --- |
| Spelling | `mut` (a word, matches the declaration side, visibly not Python). | Keep `&`: reuses `E_MUTATION_MARKER` unchanged; cosmetic, do not let it block. |
| What may be `mut` | Any *managed-bearing* parameter type, the same definition arenas use (`docs/arenas.md`): `list`, `dict`, `class`, `Cell`, `[N]T`, `byte_buffer`, and a `record`/union/option/result holding one. Scalars, `str`, `bytes` and scalar-only records are rejected. | Records with managed fields excluded: no — a write to `rec.items` through a by-value record reaches the caller and must be visible. |
| Unused `mut` | Error under `check`. | Warning: rejected, because a stale `mut` is exactly the lie the marker exists to prevent. |
| Class exemption | Removed. `bump(mut counter)` is required. | Keep it: rejected, it is the case with no diagnostic at all today (probe q5). |
| `mutates(...)` clause | Removed spelling naming `mut`. | Keep as an accepted synonym: rejected, two spellings for one fact. |
| `--mutation-markers` flag | Removed; the rule is always on. | — |
| Locals | No `mut` on locals; function-scoped mutable locals are unchanged. | — |
| Callback types | `def(values: mut list[int]) -> None` replaces the `mutates(values)` binder; a callback implementation may write fewer positions than the destination permits, as today. | — |
| Overlap proof | Unchanged: a `mut` argument that may alias a non-`mut` argument of the same call is `E_MUTATION_OVERLAP`, exactly as a declared footprint is today. | — |
| Permission chain | Unchanged: passing `mut x` where `x` is the caller's own parameter requires that parameter to be `mut` (`E_MUTATION_PERMISSION`). | — |
| Effect | A `mut` parameter contributes `mutation` to the derived ceiling (item 2). Until item 2 lands, it contributes `mutation` to the declared ceiling check exactly as `mutates(...)` does today. | — |

### Implementation

- **Lexer / parser.** Add `mut` as a keyword in parameter position (after the
  colon, before the type) and in argument position (`parser.zig`, parameter
  parsing and `call_arguments.zig`). Retire the `mutates` clause parse at
  `parser.zig:1098` with a removed-spelling hint; retire the `&` marker lexing
  (`lexer.lexWithMarkers`, `compiler.zig:121-146`, `incremental.zig:478-986`,
  `interfaces.zig:1336`) and the `mutation_markers` option
  (`native_test_options.zig:17,131`, `sema.zig:283`, `compiler.zig`).
- **Typed model.** `typed.Function.signature.declared_mutates` becomes the set of
  `mut` positions; callable types (`callables.zig:38-59`) carry `mut` per
  parameter instead of a binder footprint.
- **Checker.** In `sema.zig` the marker check at `:3597-3611` runs
  unconditionally and keys on the callee's `mut` positions; `markerTarget`
  (`:3611`) is reused for the assignability rule. In `origins.zig`,
  `checkDeclaredBound` (`:635`) turns the `W_MUTATES_MISSING` path into
  `E_MUTATION_MARKER` with the declaration paste, deletes `isClassParameter`
  (`:621`), and adds the "declared `mut`, never written" check from the same
  summary (`summary.mutates` per position, with forwarded `mut` arguments
  counted as writes).
- **Interfaces and fingerprints.** `interfaces.zig` renders `mut` in the
  signature text and drops the separate `mutates(...)` column; `navigation.zig`
  and `api_diff.zig` publish `mut` positions under the existing `mutates` field
  name so consumers keep working; `interface_sha256` includes `mut` because it
  is part of the rendered signature.
- **Formatter.** `formatter.zig` prints `name: mut T` and `mut argument`.

### Tests

- `tests/lang/mutation_markers.my`: list, dict, class, `Cell`, array, record
  holding a list; marker at declaration and call; forwarding wrapper;
  callback with a `mut` binder; receiver calls unmarked.
- `src/root_test.zig`: each diagnostic above with its exact paste
  (`// spec: MUT-PARAM-1` … `MUT-PARAM-6`); `fmt` round-trip; `list-interfaces`
  and `api-diff` rendering; the removed spellings.
- `SPEC.md`: replace `[MUTATION-MARKER-1]` with the `MUT-PARAM-*` bullets and
  retire the `W_MUTATES_MISSING` bullet.

### Migration

32 `mutates(...)` declarations and ~60 call sites in the corpus
(`src/schematic/guest`, `src/stdlib`, `examples`, `experiments/cascade/designs`,
`tests/lang`), plus the docs examples in `docs/effects.md` and
`docs/functions.md`. The compiler already computes the exact set; a
`fmt --fix` pass that applies the paste from `E_MUTATION_MARKER` migrates
everything mechanically. Class-parameter writers are the ones no clause names
today; the "declare it `mut`" error finds them.

### Done when

`probe q5` (a class written through an unmarked parameter) is rejected with
the declaration paste; the `Inventory` program above is rejected at both the
declaration and the call, accepted with both markers, and `report(mut inv, out)`
is rejected as an unneeded marker; `mylang context --symbol` on `restock` shows
`mut` in the signature; the full gate is green.

---

## 2. The signature is the whole contract; an unused capability is an error

### Rule

A function's effect ceiling is derived from its parameter list: a `Stream`
permits `output`, a `Filesystem` permits `filesystem`, `Network` permits
`network`, `Clock` permits `clock`, `Entropy` permits `random`, `Environment`
permits `environment`, `Host` permits `host`, a `mut` parameter permits
`mutation`, a callback parameter permits its declared ceiling, and allocation is
always permitted. A body that exceeds the derived ceiling is rejected in that
body. `noalloc`, `noio` and `effects(...)` survive only as narrowings; a clause
that restates the derived set is a warning and a clause that names an effect no
parameter can supply is an error. A capability parameter the body never uses is
an error.

### Today

```text
# doc: not-mylang
# src/schematic/guest/text.my — host is never used; the signature claims C access
public def equal(host: Host, a: Span, b: Span) -> bool effects():
# src/schematic/guest/layout_graph.my — the clause restates the parameters
public def rail(host: Host, span: text.Span) -> bool effects(host, managed_allocation):
```

`list-interfaces src/schematic/guest/main.my` shows 20 of 41 `host` parameters
whose checked effect set lacks `host`. An unused parameter is only
`W_UNUSED_BINDING` today (probe r2). Exported functions publish the *inferred*
mask as their ceiling (`effects.zig:406-414`), so a body edit that adds an
effect changes the callee's `interface_sha256` and rechecks every caller.

### After

```text
# doc: not-mylang
public def equal(a: Span, b: Span) -> bool:
public def rail(host: Host, span: text.Span) -> bool:
```

One rule reads every signature:

```text
# doc: not-mylang
def area(width: int, height: int) -> int
    # no capability, no mut: a value computed from its arguments; may allocate

def render(out: Stream, shape: Shape) -> None
    # may print; cannot change `shape`

def load(fs: Filesystem, path: str) -> Result[Doc, str]
    # may read files; may fail

def place(rows: mut list[Row], width: int) -> None
    # changes `rows`; nothing else

def checksum(data: bytes) -> int noalloc
    # as `area`, and additionally promises not to allocate
```

### Diagnostics

```text
text.my:12:18: error[E_UNUSED_CAPABILITY]: `host` is never used, so this signature claims an effect the body cannot have; remove the parameter or use it
graph.my:8:47: warning[W_DERIVED_EFFECTS]: `effects(host, managed_allocation)` is exactly what the parameters imply; remove it
graph.my:8:47: error[E_DERIVED_EFFECTS]: `effects(output)` names an effect no parameter supplies; add `out: Stream` or drop `output`
graph.my:14:5: error[E_EFFECT_BOUND]: `out.print` needs `output`, which this signature does not permit; add `out: Stream` to the parameters
```

The last one replaces today's `E_EFFECT_BOUND` reported at a *caller's*
annotation ("count -> labels"): with a derived ceiling on every function, the
violation is always in the body that exceeds its own signature, and the
path-to-origin diagnostic is only needed for an explicit narrowing.

### Decisions

| Decision | Choice | Alternative considered |
| --- | --- | --- |
| Allocation | Ambient (D7 of the effects-as-arguments plan); `noalloc` and `effects()` still forbid it. | — |
| Restating clause | Warning under `check`, blocking under `lint --profile=strict`. | Error: rejected, too much churn during migration. |
| Clause naming an unsupplied effect | Error. | Warning: rejected, it can never be satisfied. |
| Unused capability | Error, including `Host` and `Stream`. A parameter counts as used when it is read at all, including being passed on. | Keep `W_UNUSED_BINDING`: rejected, the over-claim is what the audit measured. |
| Unused `mut` | Covered by item 1. | — |
| Callback parameters | Contribute their declared ceiling to the derived set (calling through the value uses the destination ceiling, as today). | — |
| Published `effects` | Still published as a checked body fact (`docs/reference.md`, fact status); the published `ceiling` becomes the derived set. | — |
| Interface fingerprint | Signature text only. The inferred mask leaves the fingerprint, because a body can no longer exceed its signature. | — |
| Generic templates | Derived from the template's parameter list; specializations are checked against it. | — |
| `main` | Unchanged: its capabilities are its parameters already. | — |

### Implementation

- **`effects.zig`.** Replace the freeze at `:406-414` with: compute the derived
  ceiling from `function.signature` (capability types via
  `runtime_values.Type.capabilityIndex`, `mut` positions from item 1, callback
  ceilings from `callables.zig`); set `policy.effect_bound` to the derived set
  when no explicit clause is present, or to the intersection when one is; run
  the existing bound loop (`:417-430`). Add the restating-clause warning and the
  unsupplied-effect error where explicit clauses are resolved in `sema.zig`.
- **Unused capability.** In the pass at `sema.zig:5535-5556`, a local whose
  `origin` is a parameter, whose type has a `capabilityIndex`, and whose
  `usage.reads == 0` reports `E_UNUSED_CAPABILITY` instead of
  `W_UNUSED_BINDING`.
- **Interfaces.** `interfaces.zig` publishes `ceiling` as the derived set;
  `project_dependencies` and `navigation.zig` drop the inferred mask from
  `interface_sha256`; `docs/reference.md` fact-status table updated.
- **Diagnostic.** The bound violation message at the operation names the
  parameter to add (the capability type ↔ effect table is small and fixed).

### Tests

- `tests/lang/derived_effects.my`: pure-by-signature helper; a `Stream`
  helper; a callback-carrying helper; narrowing with `noalloc` still enforced.
- `src/root_test.zig`: each diagnostic (`// spec: DERIVED-EFFECTS-1` …
  `-4`, `UNUSED-CAPABILITY-1`); an incremental test that a body edit adding an
  allocation does not change `interface_sha256` and rechecks no caller
  (extends the wave-3 incremental tests).
- `SPEC.md`: bullets for the derived ceiling, the two clause diagnostics, the
  unused-capability error, and the fingerprint change; retire the "exported
  functions freeze the inferred mask" wording in `docs/effects.md`.

### Migration

Counted in the levers proposal: 93 of 185 effect clauses in the corpus restate
the derived set and are deleted (the warning lists them; `fmt --fix` removes
them); 80 narrowings stay. ~20 unused `host` parameters in the schematic guest
and their call sites lose an argument. Any function that today prints or
reaches C without the corresponding parameter is already impossible (D1, D6
landed), so no body needs a new parameter except through item 1's `mut`.

### Done when

`text.equal(host, a, b)` is rejected until `host` is removed; `rail`'s clause
warns and, once removed, `list-interfaces` prints
`ceiling(host, managed_allocation)` for it from the signature alone with
`analysis: declaration-only`; a body-only edit that adds an allocation to a
callee leaves every caller's checked body cached; the full gate is green.

---

## 3. `Option` methods and the sentinel lint

### Rule

`Option[T]` answers three intrinsic methods: `unwrap_or(default: T) -> T`,
`is_none() -> bool` and `is_some() -> bool`. They are pure, allocate nothing,
and are allowed in generic bodies. An `agent`-profile lint reports an `int`
that is used as a sentinel — returned as a negative literal on one path and
tested against a negative literal at a use — and names the `Option[int]`
rewrite.

### Today

```text
# doc: not-mylang
def find_pin(pins: list[Pin], name: str) -> int:
    for index, pin in enumerate(pins):
        if pin.name == name:
            return index
    return -1

def wire(pins: list[Pin], name: str) -> int:
    index = find_pin(pins, name)
    if index < 0:              # the reader needs find_pin's convention
        return 0
    return pins[index].net
```

The `Option` form already works today (this runs and prints `1 0`), because
`is None` narrowing landed as `[OPTION-FLOW-1]` and an `Option` field may
default to `None` (probe r1):

```text
# doc: not-mylang
def find_pin(pins: list[Pin], name: str) -> Option[int]:
    for index, pin in enumerate(pins):
        if pin.name == name:
            return Some(index)
    return None

def wire(pins: list[Pin], name: str) -> int:
    index = find_pin(pins, name)
    if index is None:          # the signature said it could be absent
        return 0
    return pins[index].net

record Part:
    ref: str
    pin1: Option[int] = None   # instead of `pin1: int` meaning -1
```

What is missing is the one-line "absent means default" form; today
`int("x").unwrap_or(7)` is `E_COLLECTION_METHOD` (probe p6).

### After

```text
# doc: not-mylang
width = parse_width(text).unwrap_or(80)
if part.pin1.is_none():
    return 0
count = counts.get(name).unwrap_or(0)      # dict.get(key) -> Option is unchanged
```

### Diagnostics

```text
layout.my:31:8: warning[L_SENTINEL_INT]: `find_pin` returns -1 on one path and its result is tested against a negative literal here; return `Option[int]` and test `is None` or use `unwrap_or`
main.my:4:22: error[E_TYPE]: `unwrap_or` default must be `int` (the Option's payload), found str
```

### Decisions

| Decision | Choice | Alternative considered |
| --- | --- | --- |
| Method set | `unwrap_or`, `is_none`, `is_some` on `Option` only. | `Result.unwrap_or`: deferred; a `Result` carries a reason that should be matched or propagated. `x or default`: rejected, it would give `or` a second typing rule against the strict-`bool` condition rule. |
| Laziness | `unwrap_or(default)` evaluates its argument eagerly, like a call. | `unwrap_or_else(callback)`: deferred. |
| Lint scope | Report-only under `agent`; blocking under `strict`. Trigger: a function with an `int` result that returns a negative integer literal on some path, whose result is compared against a negative literal (`< 0`, `== -1`, `>= 0` as a guard) at a call site. Fields and parameters compared against `-1` in two or more places also trigger. | — |

### Implementation

- **Checker.** `sema.zig` method dispatch: the `E_COLLECTION_METHOD` path
  (`sema.zig:100`) gains an `Option` receiver arm with the three methods and
  their signatures; `unwrap_or`'s default is checked against the payload type
  with the expected-type rule for literals.
- **Lowering.** `option_flow.zig` already lowers `is None` "through existing
  exhaustive variant dispatch"; `unwrap_or` lowers to the same two-arm match
  with a fresh temporary, `is_none`/`is_some` to the tag test.
- **Effects.** No effect; `noalloc` accepts all three.
- **Lint.** A new rule in the lint module (`docs/tooling/lint.md` lists the
  existing `L_*` rules and profiles) over the checked program: collect
  functions returning `int` with a negative-literal return, then their call
  sites' comparisons.

### Tests

- `tests/lang/option_methods.my`: each method on `Some`/`None`, in a generic
  body, under `noalloc`, with a literal default adopting the payload type.
- `src/root_test.zig`: the type error above (`// spec: OPTION-METHODS-1`,
  `-2`); the lint firing on the `find_pin` shape and staying quiet on
  `text.find` (Python's `-1` is that method's contract and is exempt by
  name).
- `SPEC.md` bullets; `docs/results-and-options.md` section with a runnable
  example; `features.json` slug `option-methods`.

### Done when

Probe p6 prints `7`; the `find_pin`/`wire` pair above gets the lint under
`--profile=agent`; the full gate is green.

---

## 4. Tuples

### Rule

`tuple[T1, …, Tn]` (2 ≤ n ≤ 8) is an immutable, fixed-arity value with no
fields, no indexing, no methods and no `len`. It is written `(a, b)`; `return
a, b` and `x, y = a, b` accept the bare form. It is taken apart only by
destructuring: `x, y = expr`, `for x, y in items`, with `_` for a value not
needed. It compares structurally, prints as `(1, 'a')`, may be stored in
lists, dictionaries (as values), records, `Option` and `Result`, and is
managed-bearing when any element is.

### Today

```text
# doc: not-mylang
record Split:                    # exists for one function
    head: str
    rest: str

def split_first(text: str, sep: str) -> Split:
    at = text.find(sep)
    if at < 0:
        return Split(head=text, rest="")
    return Split(head=text[0:at], rest=text[at + 1:len(text)])

def main(out: Stream) -> int:
    parts = split_first("key=value", "=")
    out.print(parts.head, parts.rest)   # what fields does Split have?
    return 0
```

This runs and prints `key value`. `pairs = [(1, "a")]` is `E_SYNTAX` (probe r3);
`return a // b, a % b` is `E_SYNTAX` with a hint naming a record (probe p4).

### After

```text
# doc: not-mylang
def split_first(text: str, sep: str) -> tuple[str, str]:
    at = text.find(sep)
    if at < 0:
        return text, ""
    return text[0:at], text[at + 1:len(text)]

def main(out: Stream) -> int:
    head, rest = split_first("key=value", "=")
    out.print(head, rest)
    a = 1
    b = 2
    a, b = b, a                             # the swap idiom
    pairs: list[tuple[int, str]] = [(1, "a"), (2, "b")]
    for number, letter in pairs:
        out.print(number, letter)
    return 0
```

### Diagnostics

```text
main.my:9:5: error[E_TUPLE_ARITY]: `split_first` returns 2 values; bind 2 names, or `_` for one you do not need
main.my:9:12: error[E_TUPLE_INDEX]: a tuple has no elements to index; bind its values with `head, rest = ...`
main.my:3:24: error[E_TYPE]: expected tuple[str, str], found tuple[str, int]
main.my:12:9: error[E_TUPLE_ARITY]: a tuple has between 2 and 8 elements; declare a record for a larger group
```

### Decisions

| Decision | Choice | Alternative considered |
| --- | --- | --- |
| Arity | 2..8. | Unbounded: rejected, a large tuple is an undeclared record. |
| Access | Destructuring only. | Indexing `t[0]`: rejected for v1; it makes a tuple a positional record and undoes the local-reasoning point. |
| Bare form | Allowed in `return` and on both sides of a multi-target assignment; parentheses elsewhere. | Python's bare tuple anywhere: rejected, it is the source of most Python tuple confusion. |
| `match` patterns | None in v1. | — |
| Dictionary keys | No (`int`/`str` keys unchanged). | — |
| `DictItem`, `zip`, `enumerate` | Unchanged in v1; `for k, v in mapping.items()` keeps destructuring the `DictItem` record. A later change may make them tuples. | — |
| Identity across modules | Structural: `tuple[int, str]` is one type everywhere, like `Result` and `Option`. | — |
| Host/JSON boundary | Rejected like managed graphs (`E_*` at the boundary), or rendered as a JSON array; choose the reject-first path and revisit. | — |
| Generic element types | Allowed (`tuple[T, int]` in a template). | — |

### Implementation

- **Parser.** Tuple type in `parseType`; parenthesized tuple expression (a
  parenthesized expression followed by a comma); bare tuple after `return` and
  in the multi-target assignment statement; retire the hint at
  `parser.zig:254` (tuple return) and the `HintForm.tuple` entries for the
  cases that are now accepted (the `a, b = b, a` swap and `return q, r`).
- **Typed model.** An anonymous value-record type keyed by its element types
  (`typed.zig`, `record_layouts.zig`); fields named by position, never
  nameable from source.
- **Checker.** Construction with the expected-type rule for literals;
  destructuring assignment binds `n` names with the arity check; `for`
  destructuring over a list of tuples reuses the existing two-binding path
  used for `DictItem`.
- **Lowering.** Construct = record construct; destructure = positional field
  reads (`lower.zig`, `collection_lower.zig`).
- **Printing and equality.** `native_format.zig` renders `(1, 'a')`;
  structural `==` follows the aggregate rule.
- **Formatter, interfaces, api-diff.** `tuple[int, str]` spelling everywhere.

### Tests

- `tests/lang/tuples.my`: return and destructure; swap; nested in a list and
  a record; `Option[tuple[...]]`; equality; printing; arena confinement when
  an element is managed; a generic function over `tuple[T, int]`.
- `src/root_test.zig`: the four diagnostics (`// spec: TUPLE-1` … `-5`),
  `fmt` round-trip, `list-interfaces` rendering.
- `SPEC.md` bullets; a `docs/records-and-unions.md` (or new
  `docs/tuples.md`) section with a runnable example; `features.json` slug
  `tuples`; `docs/python-syntax.md` table rows for `a, b = b, a` and
  `return q, r` move from "rejected" to accepted.

### Done when

Probes p4 and r3 run; the `split_first` program above prints `key value`,
`1 a`, `2 b`; `Split` and `Step` (cascade parser) can be deleted in a
migration commit; the full gate is green.

---

## 5. Keyword-only parameters, and a lint on positional literals

### Rule

A bare `*` in a parameter list makes every following parameter keyword-only,
with Python's meaning: they must be passed by name, may appear in any order,
and required and defaulted keyword-only parameters may be mixed. A call that
supplies a keyword-only parameter positionally is rejected with the rewritten
call. An `agent`-profile lint reports a positional `bool`, integer or `None`
literal in a call with three or more arguments and names the parameter.

### Today

```text
# doc: not-mylang
def issue(host: Host, code: int, file: int, position: int) -> int:
    ...

_ = io.issue(host, 13, 0, span.start)     # which is the code, which the file?
```

`def issue(code: int, *, file: int)` is `E_SYNTAX: expected a name` (probe q2).

### After

```text
# doc: not-mylang
def issue(host: Host, *, code: int, file: int, position: int) -> None:
    ...

io.issue(host, code=13, file=0, position=span.start)
```

### Diagnostics

```text
circuit.my:89:24: error[E_KEYWORD_ONLY]: `code` is keyword-only; write `io.issue(host, code=13, file=0, position=span.start)`
io.my:12:24: error[E_SYNTAX]: `*` must be followed by at least one parameter
io.my:12:24: error[E_SYNTAX]: `*` may appear once in a parameter list
draw.my:40:5: warning[L_POSITIONAL_LITERAL]: `True` is passed positionally to `draw`'s 4th parameter `filled`; name it: `draw(canvas, x=10, y=20, filled=True)`
```

### Decisions

| Decision | Choice | Alternative considered |
| --- | --- | --- |
| Where `*` is accepted | Declared functions only. Records use field lists (unchanged); callback types and intrinsics are positional-only today and stay so, so `*` in a callback type is `E_SYNTAX`. | — |
| Ordering among keyword-only parameters | Python's: free. The existing required-before-defaulted rule applies to the positional group only. | — |
| `/` positional-only marker | Not added. | — |
| Lint trigger | A call with ≥3 arguments passing a `bool`, integer or `None` literal positionally to a declared function or record constructor; intrinsics and callback calls exempt. Report-only under `agent`. | — |

### Implementation

- **Parser.** Accept a `star` token as a parameter separator in the parameter
  list parser (`parser.zig`, near the `mutates` parse at `:1098`); record the
  keyword-only boundary on the declaration.
- **Arity.** `call_arguments.zig` binds positionals only up to the boundary
  and reports `E_KEYWORD_ONLY` with the call rewritten using the parameter
  names; the existing keyword-binding path handles the rest. The signature
  renderer shared by the call-site rejections (D1 of the agent-usefulness
  plan) prints `*`.
- **Interfaces / fingerprint / formatter.** `*` is part of the signature text.
- **Lint.** New rule next to the existing report rules; uses resolved call
  identities from the checked program.

### Tests

- `tests/lang/keyword_only.my`: required and defaulted keyword-only
  parameters, any order, mixed with positionals.
- `src/root_test.zig`: the diagnostics (`// spec: KEYWORD-ONLY-1` … `-3`),
  `fmt` round-trip, interfaces rendering, the lint on a 4-argument call.
- `SPEC.md` bullets; `docs/functions.md` section under "Keyword arguments and
  defaults" with a runnable example; `features.json` slug `keyword-only-parameters`.

### Done when

Probe q2 runs and prints `6`; a positional call to it is rejected with the
rewritten call; the schematic guest's `io.issue` can be migrated in one commit;
the full gate is green.

---

## 6. Conditional expression

### Rule

`value_if_true if condition else value_if_false` is an expression with
Python's precedence (below `or`, right-associative). The condition is `bool`;
both arms have one type, taken from the expected type when there is one and
otherwise from the arms, with integer literals adopting the expected width as
they do elsewhere. Only the chosen arm is evaluated; both arms count for
effects and for the `E_UNBOUND` analysis.

### Today

```text
# doc: not-mylang
edge = 352                      # is 352 meaningful, or a placeholder?
if row.side == 1:
    edge = 532

point = Point(x=-1, y=-1)       # -1 is not a coordinate; it is "not yet"
if row.side == 1:
    point = Point(x=532, y=row.y)
else:
    point = Point(x=352, y=row.y)
```

`y = 42 if x > 0 else 0` is `E_SYNTAX` with a hint naming if/else
(probe q3; `parser.zig:91, :243, :279`).

### After

```text
# doc: not-mylang
edge = 532 if row.side == 1 else 352
point = Point(x=532 if row.side == 1 else 352, y=row.y)
label = f"{count} item{'' if count == 1 else 's'}"
return Some(index) if found else None
```

### Diagnostics

```text
layout.my:20:12: error[E_TYPE]: conditional arms must agree: `int` here, `str` in the else arm
layout.my:21:15: error[E_TYPE]: expected bool, found int
layout.my:22:5: error[E_EXPLICIT_DISCARD_REQUIRED]: a standalone non-unit value requires `_ =` or result handling
```

### Decisions

| Decision | Choice | Alternative considered |
| --- | --- | --- |
| Precedence | Python's. | — |
| Arm typing | Expected type first, then the arms must match exactly; no numeric widening between arms. | — |
| Nesting | Allowed (`a if p else b if q else c`), formatted as written. | Reject nesting: unnecessary. |
| Evaluation | Lazy per arm; `a if p else f()` never calls `f` when `p` holds, so a guard on the left genuinely prevents a trap on the right, as `and`/`or` do. | — |
| Result/Option arms | `Some(x) if p else None` and `Ok(x) if p else Err(e)` work through the expected type, like any other contextual construction. | — |

### Implementation

- **Parser.** Parse in the expression parser at the lowest precedence, above
  the assignment/return sites; remove the `.ternary` hint entries
  (`parser.zig:64, :91, :243, :279`) and the corresponding
  `declaration_hints_test.zig` cases.
- **Typed model.** One node `conditional {condition, then, else}` in
  `typed.zig`, or a desugaring in `sema.zig` to an if/else that assigns a
  fresh temporary; the desugaring reuses the existing definite-assignment and
  effect machinery unchanged and is the smaller change.
- **Lowering.** If desugared, nothing; otherwise a two-block branch in
  `lower.zig`.
- **Formatter.** One line; no parentheses added.

### Tests

- `tests/lang/conditional_expression.my`: scalar arms, record arms, `Option`
  arms by expected type, laziness (the unchosen arm would trap), nesting, in
  an f-string hole and a call argument.
- `src/root_test.zig`: the two type errors (`// spec: CONDITIONAL-EXPR-1`,
  `-2`), `fmt` round-trip.
- `SPEC.md` bullets; `docs/statements.md` or `docs/python-syntax.md` section
  with a runnable example; `features.json` slug `conditional-expression`;
  the `docs/python-syntax.md` "rejected spelling" table row for
  `y = 42 if x > 0 else 0` is removed.

### Done when

Probe q3 prints `42`; `layout.placeRows`'s `side = -1 / if … side = 1` can be
written as one line; the full gate is green.

---

## What the six add up to

With all six in place, `layout.placeRows` reads like this, and everything a
reader needs is on the signature and the call line:

```text
# doc: not-mylang
def placeRows(rows: mut list[Row]) -> None:          # writes rows; nothing else; cannot fail or print
    total = 0
    for row in rows:
        total += row.height
        ...
    for i, row in enumerate(rows):
        rows[i].side = 1 if i >= split else -1
        rows[i].y = y + offset
        y += row.height

placeRows(mut ordered)                               # the only value this line can change
```

The measurement that says whether it worked is the one the levers proposal
names: bytes read before the first edit and failed checks on changed source, on
the cascade pack, arm B rewritten by script with these six applied. The
prediction is a fall in bytes read on the tasks that touch a mutating helper
(T2, T3, T5), no rise in failed checks once every rejection carries its paste,
and no change on the printer task T4.
