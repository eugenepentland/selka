# Module interfaces

A module interface is everything another module's check may read about one
module, written down per module with two hashes. It was the first stage of
compiling each module on its own (the plan is in
[the compilation-model audit](../audits/compilation-model-2026-09-24.md), §11
item 1). No build or check reads interfaces: `mylang interfaces` emits them
from the whole-program check, checks a module against them, and proves that
such a check reports what the whole program reports.

```console
$ mylang interfaces emit main.my --out=.mylang-cache/interfaces
{"version":"module-interface-index-v1","entry":"main","modules":[{"module":"lib","interface_hash":"ab02…","implementation_hash":"7c73…",…}]}
$ mylang interfaces show .mylang-cache/interfaces/lib.myi
module-interface-v5 lib
interface-hash ab02…
…
$ mylang interfaces check main.my --module=main --from=.mylang-cache/interfaces
{"version":"module-interface-check-v1","module":"main","status":0,"stood_in":9,"declared_only":true,…}
$ mylang interfaces oracle main.my
{"version":"module-interface-oracle-v1","entry":"main","equal":true,"modules":6,…}
```

## What an interface holds

`emit` writes one `module-interface-v5` artifact per module, `<module>.myi`, and
an `index.json` with each module's hashes and counts. The default directory is
`<cache-dir>/interfaces`, with `.mylang-cache` as the cache directory. An
artifact is a versioned binary serialization with no pointers, paths or times;
`show` prints it as canonical text.

- **Declaration text.** The module's `module` line, the import lines that text
  uses, and every exported declaration plus, transitively, every declaration of
  the same module those name, copied verbatim from the source. A domain keeps
  all its members. Private declarations nothing exported reaches, comments
  between declarations and the module docstring are left out.
- **Bodies only where a dependent reads them.** A function body stays in the
  text when its role says a dependent reads it: a generic template (the user
  instantiates it), a constant (the user evaluates it), a function a constant's
  value calls (`evaluated`), a conversion, an `extern func`, and a small leaf
  the interface lowering's inliner may splice into a caller (`inlined`, in a
  lowering with or without `debug` statements). Every other body is replaced by
  `pass` (`declared`).
- **Facts.** Each function carries its whole-program facts: the propagated
  effect mask, the mutation summary, the return origin and the write facts. A
  dependent's check stands a declared function in with them, exactly as a
  [check summary](caches.md#check-summaries) stands in for an unchanged body.
- **Fingerprints and shapes.** Each declaration has an interface fingerprint:
  its declaration digest (the one dependency contexts fold), its role, its facts
  and its kept body, folded over every declaration those name, in any module,
  in an order-independent way. A facade's re-exported names carry the
  fingerprints of the declarations they name. The CHECK-SHAPES-1 digest of
  every catalog record the interface's declarations reach is listed too,
  including another module's record reached only through `list[T]`,
  `dict[K, V]`, `Option[T]` or a union payload.
- **Emission.** The `emission` section held the facts a per-module native
  compile wrote for its dependents. Nothing writes it since those compiles were
  retired (S5), so `show` prints `emission none`.
- **Positions.** Where each verbatim stretch of the text came from (offset,
  line and column). Each kept item is followed by the gap to the source's next
  top-level item with everything but its newlines blanked, so a position past
  the item's last token (the dedent that closes a `match`, say) maps back to
  the same place a whole-program build reports. A dependent needs positions
  only inside a body it instantiated or inlined, so they sit outside the
  interface hash, and so do the gaps.

## Interface and implementation hashes

The **interface hash** covers the artifact except the positions. It changes
when anything a dependent can observe changes: a signature, visibility or
deprecation, a type declaration or record shape (also through a composite type
of another module), a fact, or a template, constant, evaluated or inlined body.
It does not change for an edit to a body the interface replaces by `pass` that
leaves the module's exported facts alone, for comments and blank lines, for a
declaration moved within the file, or for a private declaration nothing
exported reaches. That is the early cutoff a per-module build would key on.

The **implementation hash** is the module's name and source bytes and the
interface hash of each direct import. A body edit changes only its own
module's implementation hash; an interface edit also changes its direct
importers'.

## Checking a module against interfaces

`mylang interfaces check ENTRY.my --module=NAME --from=DIR` reads the module's
own source and, for every other module it loads, only that module's artifact
in `DIR`, decoded when the loader first asks for it. Each declared function
stands in by its stable key with its interface facts; the abstract template
checker takes their effect masks instead of walking bodies it does not have.
The standard library is read from the compiler itself, never from an
interface. A module other than the entry is checked as an import of a
synthetic entry. The result is JSON with the module's diagnostics, the number
of functions stood in, and `declared_only`, which is false if the check fell
back to a full check.

`mylang interfaces oracle ENTRY.my [--module=NAME] [--from=DIR]` does this for
every module (the standard library excepted) and compares each result with the
whole-program check:

- every function the module's check produced has the same checked contract and
  signature types;
- every declaration of the module has the same dependency context;
- every body the module's check lowered and inlined is the whole program's,
  instruction for instruction, with types and callees by name and positions in
  their own module's source (a stood-in function is not lowered: it keeps only
  its signature, or the inliner would splice its `pass`);
- every diagnostic it reports is one the whole program reports, with positions
  in interface text mapped back, and together the modules report every
  whole-program diagnostic.

Without `--from` the interfaces are encoded and decoded first, so the checks
read exactly what an artifact holds. Any difference exits 1.

`zig build test-interfaces` runs both halves in the gate: a seeded mutation
walk over `tests/fixtures/interfaces/` and `tests/fixtures/interfaces_generic/`
(`tests/interface_diff.py`) asserts which edits keep each hash and which change
it, and runs the oracle after every step; `tests/interface_oracle.py` runs the
oracle over every entry of `tests/lang` and the fixtures. A module reaching a
record of another module only through `list[...]`, `dict[...]`, `Option[...]`
or a union payload is part of the walk: such an edit must change
that module's hash too.

## What is still whole-program

Everything that builds or checks a project works on the merged program;
interfaces are an analysis tool, not a build input.

- **`mylang check`** of a project entry checks the merged program with the
  front end's caches: the semantic cache replays unchanged function bodies and
  the verdict cache an unchanged project (NEW-CORE-S5-CHECK-1). It reads and
  writes no per-module records, and its diagnostics are the whole-program
  check's ([caches](caches.md)).
- **`mylang build`, `run` and `test`** check the merged program, build its Core
  IR and emit LLVM text. A debug build splits that text into one unit per source
  module plus generic-instance, adapter and entry units, and compiles each unit
  through a per-user object store keyed by the unit's complete input, so an edit
  recompiles only the units whose text changed. `--release` emits the whole
  program as one optimized unit. `--report` prints the units linked, reused and
  compiled ([native builds](native-build.md)).

```console
$ mylang build main.my -o app --report
{"version":"cache-report-v1","program":"linked","units":3,"reused":1,"compiled":2,"verified":0,"processes":3}
$ # a body edit in module lib
$ mylang build main.my -o app --report
{"version":"cache-report-v1","program":"linked","units":3,"reused":2,"compiled":1,"verified":0,"processes":2}
```
