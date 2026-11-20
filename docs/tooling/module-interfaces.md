# Module interfaces

A module interface is everything another module's check may read about one
module, written down per module with two hashes. It was the first stage of
compiling each module on its own (the plan is in
[the compilation-model audit](../audits/compilation-model-2026-09-24.md), §11
item 1). No build or check reads interfaces: `selka interfaces` emits them
from the whole-program check, checks a module against them, and proves that
such a check reports what the whole program reports.

```console
$ selka interfaces emit main.selka --out=.selka-cache/interfaces
{"version":"module-interface-index-v1","entry":"main","modules":[{"module":"lib","interface_hash":"ab02…","implementation_hash":"7c73…",…}]}
$ selka interfaces show .selka-cache/interfaces/lib.selkai
module-interface-v15 lib
interface-hash ab02…
…
$ selka interfaces check main.selka --module=main --from=.selka-cache/interfaces
{"version":"module-interface-check-v1","module":"main","status":0,"stood_in":9,"declared_only":true,…}
$ selka interfaces oracle main.selka
{"version":"module-interface-oracle-v1","entry":"main","equal":true,"modules":6,…}
```

## What an interface holds

`emit` writes one `module-interface-v15` artifact per module, `<module>.selkai`, and
an `index.json` with each module's hashes and counts. The default directory is
`<cache-dir>/interfaces`, with `.selka-cache` as the cache directory. An
artifact is a versioned binary serialization with no pointers, paths or times;
`show` prints it as canonical text.

- **Declaration text.** The module's `module` line, the import lines that text
  uses, and every exported declaration plus, transitively, every declaration of
  the same module those name, copied verbatim from the source. Private declarations nothing exported reaches, comments
  between declarations and the module docstring are left out.
- **Bodies only where a dependent reads them.** A function body stays in the
  text when its role says a dependent reads it: a generic template (the user
  instantiates it), a constant (the user evaluates it), a function a constant's
  value calls (`evaluated`), a conversion, or a foreign declaration. Every
  ordinary body is replaced by `pass` (`declared`).
- **Declared contracts.** Each function carries its sorted declared mutation
  positions and return-origin contract: fresh when `from` is absent, or the
  sorted parameter positions named by `from`. These position lists have no
  64-parameter limit. Body-derived view sources, borrow masks and write facts
  are not interface contracts. Dependents read the signature in declaration
  text; an implementation stand-in cannot override it.
- **Fingerprints and shapes.** Each declaration has an interface fingerprint:
  its declaration digest (the one dependency contexts fold), its role, its facts
  and its kept body, folded over every declaration those name, in any module,
  in an order-independent way. A facade's re-exported names carry the
  fingerprints of the declarations they name. The CHECK-SHAPES-1 digest of
  every catalog record the interface's declarations reach is listed too,
  including another module's record reached only through `list[T]`,
  `dict[K, V]`, `Option[T]` or a union payload.
- **Positions.** Where each verbatim stretch of the text came from (offset,
  line and column). Each kept item is followed by the gap to the source's next
  top-level item with everything but its newlines blanked, so a position past
  the item's last token (the dedent that closes a `match`, say) maps back to
  the same place a whole-program build reports. A dependent needs positions
  only inside a body it instantiated, so they sit outside the interface hash,
  and so do the gaps. Raw `from` clauses are represented in the hash by their
  normalized source positions, making source-list order neutral.

### The roles are a closed list

`Role` in `src/module_interface.zig` has six values, and they are every reason
a dependent module may read another module's function body: `declared` (the
body is `pass`; the signature is all a caller gets), `template`, `constant`,
`conversion`, `foreign` (a declaration with no guest body) and `evaluated`.
Five keep a body; only `declared` does not. The list is closed: a seventh
role, a role removed or renamed, or a role that starts or stops keeping its
body is a decision for the user under goal G7 of [the goals register](../goals.md)
(a caller is judged from signatures alone), and the test `W9 the interface
roles are a closed list` in `src/module_interface_test.zig` fails until the
decision is recorded there. `W9 roleOf by example` pins the rule that picks a
role: a `from` result, a `mut` or `own` parameter, `@requires`, `@noalloc`, a
`fails` clause or a call to a private helper leaves a function `declared`. A
standard-library `builtin func` is `declared` too, generic or not
(`W10 a builtin func takes the declared role`): it has no body for a dependent to
read, and its calls are the compiler's operation.

## Interface and implementation hashes

The **interface hash** covers the artifact except the positions. It changes
when anything a dependent can observe changes: a signature, visibility or
deprecation, a type declaration or record shape (also through a composite type
of another module), a declared mutation or return-source contract, or a kept
body. It does not change for an edit to an ordinary body replaced by `pass`,
even when its actual return origins change within the declared bound, for a
reordered `from` list, for comments and blank lines, for a
declaration moved within the file, or for a private declaration nothing
exported reaches. That is the early cutoff a per-module build would key on.

The **implementation hash** is the module's name and source bytes and the
interface hash of each direct import. A body edit changes only its own
module's implementation hash; an interface edit also changes its direct
importers'.

## Checking a module against interfaces

`selka interfaces check ENTRY.selka --module=NAME --from=DIR` reads the module's
own source and, for every other module it loads, only that module's artifact
in `DIR`, decoded when the loader first asks for it. Each declared function
stands in by its stable key with declaration-derived facts. Caller ownership
and borrowed-result representation come from the declared signature, without
walking a body it does not have.
The standard library is read from the compiler itself, never from an
interface. A module other than the entry is checked as an import of a
synthetic entry. The result is JSON with the module's diagnostics, the number
of functions stood in, and `declared_only`, which is false if the check fell
back to a full check.

`selka interfaces oracle ENTRY.selka [--module=NAME] [--from=DIR]` does this for
every module (the standard library excepted) and compares each result with the
whole-program check:

- every function the module's check produced has the same checked contract and
  signature types;
- every declaration of the module has the same dependency context;
- every body the module's check kept has the same checked tree
  (`trees_compared`): a digest of the function's name, signature, locals and
  every node and statement of its body, with callees and types by name and no
  source span, so a different numbering of the program's functions, records
  and nodes does not show;
- every body the module's check lowered and inlined is the whole program's,
  instruction for instruction, with types and callees by name and positions in
  their own module's source (a stood-in function is not lowered: it keeps only
  its signature, or the inliner would splice its `pass`);
- every diagnostic it reports is one the whole program reports, with positions
  in interface text mapped back, and together the modules report every
  whole-program diagnostic;
- Core's refusals agree (W9, goal G7): the refusals of the ownership pass
  (`single_owner`, what `check` and `build` report) and of the `@noalloc`
  promises (what `build` reports) over the bodies the module's check judged,
  located in their modules' sources, are ones the whole program makes, and
  together the modules make every whole-program refusal
  (`refusals_compared`, `whole_program_refusals`, `missing_refusals`). A
  stood-in declaration has no body, so it is not judged, and neither is the
  standard library, which both checks read from source.

Core itself never reads an interface: every command checks the merged program
of full sources. The interface-only side of this comparison is the oracle's own
per-module check, whose program the oracle hands to Core
(`src/core/interface_ownership.zig`, in the core because the front end may not
import it). A difference that goal G7 already lists as an exception is reported
under `known_differences` with the exception it is, and does not fail the
oracle: a `@noalloc` refusal (G8-X1, W14: the promise is judged over the bodies
it calls), or a refusal inside a generic template (W3) or inside a constant or
a function a constant evaluates. Any other difference is a new finding about
goal G7.

Without `--from` the interfaces are encoded and decoded first, so the checks
read exactly what an artifact holds. Any difference exits 1.

`zig build test-interfaces` runs both halves in the gate: a seeded mutation
walk over `tests/fixtures/interfaces/` and `tests/fixtures/interfaces_generic/`
(`tests/interface_diff.py`) asserts which edits keep each hash and which change
it, and runs the oracle after every step; `tests/interface_oracle.py` runs the
oracle over every entry of `tests/lang` and the fixtures, among them
`tests/fixtures/interfaces_ownership/`, whose entries call another module's
functions in the shapes Core refuses (an inner block, a `match mut` arm, a
field, a generic, a `from` contract two modules away, a `fails` function, a
moved argument, a loan passed back to a `mut` parameter, a record built from
two sources, a borrowing list, a function value) and in two it accepts. A module reaching a
record of another module only through `list[...]`, `dict[...]`, `Option[...]`
or a union payload is part of the walk: such an edit must change
that module's hash too.

## What is still whole-program

Everything that builds or checks a project works on the merged program;
interfaces are an analysis tool, not a build input.

- **`selka check`** of a project entry checks the merged program with the
  front end's caches: the semantic cache replays unchanged function bodies and
  the verdict cache an unchanged project (NEW-CORE-S5-CHECK-1). It reads and
  writes no per-module records, and its diagnostics are the whole-program
  check's ([caches](caches.md)).
- **`selka build`, `run` and `test`** check the merged program, build its Core
  IR and emit LLVM text. A debug build splits that text into one unit per source
  module plus generic-instance, adapter and entry units, and compiles each unit
  through a per-user object store keyed by the unit's complete input, so an edit
  recompiles only the units whose text changed. `--release` emits the whole
  program as one optimized unit. `--report` prints the units linked, reused and
  compiled ([native builds](native-build.md)).

```console
$ selka build main.selka -o app --report
{"version":"cache-report-v1","program":"linked","units":3,"reused":1,"compiled":2,"verified":0,"processes":3}
$ # a body edit in module lib
$ selka build main.selka -o app --report
{"version":"cache-report-v1","program":"linked","units":3,"reused":2,"compiled":1,"verified":0,"processes":2}
```
