# Aliasing model decision (2026-09-17)

The scorecard (`agent-audit-guide-scorecard-2026-09-17.md` §2.1) ranks "decide the
aliasing model" as the first item and calls it "the only item in this scorecard
that needs a language decision rather than tooling". This records the decision.

## Decision

**`class` becomes a GC-managed reference type. `record` stays the explicit value
type.** `class` also carries methods (velocity audit §3.5).

The rule an author has to remember becomes Python's own:

| Spelling | Assignment and call semantics |
| --- | --- |
| scalars, `record` | copied |
| `class`, `list`, `dict`, `str` | shared |

A `class` value is referenced; passing one to a function, storing one in a
collection, or binding one to a second name all refer to the same object, so
`def bump(c: Counter): c.n = c.n + 1` changes the caller's object.

## Why

Today `record` and its alias `class` copy, while `list`, `dict` and `str` share,
and a Python-shaped write through a record parameter compiles, runs and changes
nothing:

```text
# doc: not-mylang
record Counter:
    n: int

def bump(c: Counter):
    c.n = c.n + 1

def main() -> int:
    c = Counter(n=1)
    bump(c)
    return c.n          # prints 1 (probe S03); no warning under run or check
```

Three errors compound here:

1. **Wrong answer, exit 0.** `S01` still exits 0 with the wrong count, so a
   silent wrong answer survives the whole loop.
2. **`class` is the most dangerous spelling in the language.** A Python
   programmer - and every agent trained on Python - reads `class` as a reference
   type. Here it is a compatibility spelling of the value type with the opposite
   behaviour (probe `S04`).
3. **The charter answer is "it depends".** The guide's own question, "what is
   copied, shared or moved at a call?", currently answers "scalars and records
   are copied, collections are shared, and a record holding a collection copies
   the record but shares the collection" - the context-dependent answer the guide
   says to simplify away.

The decision makes `record` the explicit, documented escape hatch for value
semantics, and makes the default spelling behave the way the audience already
expects.

## What has already landed

The interim measure both audits asked for **is implemented** (in
`538c1045`): `W_DEAD_RECORD_WRITE` now covers a field write to a by-value
parameter, not only a loop iteration variable or a collection read. See
`SPEC.md` `[WARNING-DEAD-RECORD-WRITE-1]` and the `parameter` case in
`src/python_core_test.zig`. It remains a **warning**, so the wrong answer above
still exits 0; making it an error is superseded by this decision for `class`
(because the write there will no longer be dead) and remains a candidate for
plain `record`, where a copy is still a copy.

## Scope of the change

Not implemented yet. In dependency order:

1. **Typed model.** `class` must be distinguishable from `record` after parsing.
   Today it is accepted as a compatibility spelling, so the declaration kind and
   the record's `shape` need a reference flag that survives into `typed.zig`
   rather than being flattened at parse time.
2. **Checker/aliasing.** A `class` local holds a reference, so definite
   assignment, the dead-write analysis, and the copy-on-assignment paths must
   branch on the flag. The dead-write analysis should stop firing for `class`
   (the write reaches the original) and keep firing for `record`.
3. **Lowering and codegen.** A `class` construction heap-allocates one object
   with a `RECORD` descriptor, like a managed collection; a `class` local is a
   rooted reference, not a copied buffer. This is the same descriptor machinery
   the runtime already uses for collections, so the work is in the typed-to-IR
   mapping, not the collector.
4. **Identity and fingerprints.** `class` identity becomes reference identity, so
   equality, hashing, interface fingerprints and the semantic cache must agree
   that a `class` is a managed reference. This is the part that can silently
   invalidate cached bodies, so it needs explicit tests.
5. **Docs and contract.** `docs/python-syntax.md`, `docs/managed-memory.md`,
   `docs/statements.md`, `features.json`, and a `SPEC.md` tag per behavioural
   line, plus Guardian's per-line spec contract.

## Migration

`class` today is a compatibility spelling of `record`, so this is a **breaking
semantic change** for existing `class` code and only for `class` code; `record`
users are unaffected. Before the switch lands:

- enumerate every `class` declaration in the corpus, examples and docs and
  classify each as value-semantic (should become `record`) or reference-semantic
  (the intended new behaviour);
- ship the switch behind a release note that names the change as breaking, since
  there is no way to keep both meanings for one spelling without keeping the trap.

## What this unblocks

Scorecard §2.2-§2.4 (the charter answer, showing inferred mutation where an agent
looks first), velocity §1.1's real fix, §3.5 (methods, since methods need a
reference receiver to be useful), and §2.3-§2.4's mutation-overlap diagnostics,
which are currently hard to explain while a record parameter write is silent.

## Deliberately not decided here

- Whether `record` ever gains methods. It keeps value semantics either way.
- Whether `class` supports inheritance, `__init__`, or any other Python class
  furniture. This decision is about aliasing, not about becoming a class system.
- Whether the `record` dead-write warning becomes an error. It is a separate
  call and is no longer on the critical path for `class`.
