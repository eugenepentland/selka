# Module interfaces

A module interface is everything another module's check may read about one
module, written down per module with two hashes. It is the first stage of
compiling each module on its own (the plan is in
[the compilation-model audit](../audits/compilation-model-2026-09-24.md), §11
item 1). At this stage no build reads interfaces: `mylang interfaces` emits
them from today's whole-program check, checks a module against them, and
proves that such a check reports what the whole program reports.

```console
$ mylang interfaces emit main.my --out=.mylang-cache/interfaces
{"version":"module-interface-index-v1","entry":"main","modules":[{"module":"lib","interface_hash":"ab02…","implementation_hash":"7c73…",…}]}
$ mylang interfaces show .mylang-cache/interfaces/lib.myi
module-interface-v2 lib
interface-hash ab02…
…
$ mylang interfaces check main.my --module=main --from=.mylang-cache/interfaces
{"version":"module-interface-check-v1","module":"main","status":0,"stood_in":9,"declared_only":true,…}
$ mylang interfaces oracle main.my
{"version":"module-interface-oracle-v1","entry":"main","equal":true,"modules":6,…}
```

## What an interface holds

`emit` writes one `module-interface-v2` artifact per module, `<module>.myi`, and
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
  value calls (`evaluated`), a conversion, a `host def` or `extern def`, and a
  small leaf the bytecode inliner may splice into a caller (`inlined`, in a
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
  `dict[K, V]`, `Option[T]`, a class field or a union payload.
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
exported reaches. That is the early cutoff a per-module build keys on.

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
  its signature, as it must in a per-module build, or the inliner would splice
  its `pass`);
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
record of another module only through `list[...]`, `dict[...]`, `Option[...]`,
a class field or a union payload is part of the walk: such an edit must change
that module's hash too.

## Compiling a module on its own

`mylang compile-module` compiles one module from its own source and the
interfaces of the modules it imports; `mylang link-modules` links a program
from its modules' outputs. `mylang build` of a project runs `compile-module`
itself, one child per stale module (see
[building a project module by module](#building-a-project-module-by-module));
the two commands are what it is built from, and what the harnesses drive
directly.

```console
$ mylang compile-module main.my --module=lib --interfaces=if --out=out --arenas=off --objects
{"version":"module-compile-v1","module":"lib","hashes":{"interface":"…","implementation":"…","emission":"…","positions":"…","inputs":[…]},"counts":{…}}
$ mylang compile-module main.my --module=main --interfaces=if --out=out --arenas=off --objects
$ mylang link-modules main.my --units=out -o program
```

Modules compile in import order: each reads the interfaces its imports'
compiles wrote into `--interfaces`, and writes its own there.

- **Check.** The module is checked against its imports' interfaces exactly as
  `interfaces check` checks it.
- **Lower.** A declared function of another module is lowered signature only,
  so the inliner never splices its `pass` body. Everything else the check
  produced is lowered with its body: the module's own functions, the bodies
  interfaces keep (inlined, evaluated, conversion and host declarations), the
  standard library and every specialization.
- **Emit.** What a unit reads about a function it does not have the body of
  comes from that function's interface: whether a call to it may allocate
  (transitively; the root protection around the call depends on it) and which
  parameters it writes (whether a borrowed element may stay live across the
  call). A position inside an instantiated or inlined body from another
  module's interface is reported at its place in that module's real source.
  The module emits its own functions, its lambdas (named
  `lambda@<module>::<offset>`, so a lambda's symbol never depends on what else
  the program merges), the entry adapter when it is the entry, and every
  specialization its units reach.
- **Outputs.** `--interfaces/NAME.myi` gets an `emission` section with the
  facts its dependents read and the configuration they hold for;
  `--out/NAME.units.json` holds its units (with their fragment keys), its share
  of the runtime data as mergeable blocks, and the hashes of every interface it
  read. With `--objects` its batch and metadata objects are compiled into the
  build cache.
- **The arena switch.** Whether any function of the program opens an arena
  changes the code of every allocating unit, and no one module can know it, so
  `--arenas=on|off` is required; each module's interface records whether its
  own units open one.

`link-modules` merges every `*.units.json` into one manifest: each unit once (a
specialization several modules emitted must be the same unit), the union of
the modules' descriptors and renderers in symbol order, the entry module's
entry. The ordinary build driver then finds every guest object in the cache
the module compiles filled. Specializations are compiled alone, so every
module that emits one produces the same object, and the literal pool of the
shared unit is written in symbol order; the linked executable is the
whole-program build's, byte for byte.

`zig build test-module-compile` proves it in the gate:

- `tests/module_compile_oracle.py` builds every program of `tests/lang` and
  the fixtures both ways. Every unit's fragment key and text and metadata
  digests, and every function's emission facts, must equal the whole-program
  emission's (`emit-project-qbe --emission-report`). Each module's interface
  and positions hashes must equal `interfaces emit`'s. The link must compile
  no guest object, and the two executables must be identical and run
  identically. `--release` compares the ReleaseFast switches too.
- `tests/module_build_oracle.py` builds the same programs with the default
  `mylang build` (module by module) and with `--whole-program`. The two
  executables must be identical and run identically, and an unchanged rebuild
  must compile no module.
- `tests/module_build_diff.py` applies seeded edits and rebuilds with the
  default build over one cache, which compiles only what is stale. It must
  build what a clean `--whole-program` build builds, byte for byte.

## Building a project module by module

`mylang build`, `build --run` and `run` of a project entry compile it one
module at a time. `--whole-program` asks for the whole-program build instead.

```console
$ mylang build main.my -o app --report | grep -o '"module_build":{[^}]*}'
"module_build":{"modules":26,"compiled":26,"reused":0,"arenas":false}
$ # a body edit in one module
$ mylang build main.my -o app --report | grep -o '"module_build":{[^}]*}'
"module_build":{"modules":26,"compiled":1,"reused":25,"arenas":false}
$ mylang build main.my -o app-whole --whole-program
$ cmp app app-whole && echo identical
identical
```

- **Discovery.** Each module's imports come from its header. A module whose
  source bytes are unchanged keeps the imports its last build read, so an
  unchanged project reads no source past its digest.
- **Staleness.** A module is compiled again when its source or the program's
  arena switch changed, when one of its objects left the cache, or when an
  interface its last compile read changed its interface or emission hash. The
  positions hash counts only when that compile emitted an instruction whose
  span fell in the interface's text. A body edit compiles one module. An
  interface edit compiles the modules that read the changed interface, and
  stops at any of them whose own interface and emission facts held (early
  cutoff).
- **Parallelism.** Compiles run as child processes (`compile-module
  --ready`), as many at once as the cores and `MemAvailable` allow
  (`MYLANG_JOBS` caps it). A module starts once every module it imports has
  *published* its interface. A compile publishes its interface as soon as its
  allocation analysis is done, before it emits a unit, so a dependent's check
  and lowering overlap its imports' code generation.
- **The standard library** is compiled once per cache, compiler and set of
  emission switches, into a variant every program shares
  (`<cache>/modules/standard-<hash>`). Every compile reads those interfaces
  (`--standard-interfaces`).
- **The link** reads one record per module: its objects in link order, the
  digest of its share of the program-wide metadata unit, its entry and its
  warnings. It never reads a unit. Objects are ordered as a whole-program
  build orders them, a specialization several modules emitted is linked once,
  and the metadata unit is keyed by the modules' shares and rendered only when
  no object has that key. The executable is the whole-program build's, byte
  for byte.
- **What still goes whole-program:** a library, a provider, the LLVM backend
  or `--release`, `--no-cache`, a checked manifest, a project with a
  `mylang.json`, an entry without `main`, an import cycle or header problem,
  a module with a `host def` (the copied host bridge orders its rows by the
  whole program's tables), and any program a module compile rejects. The whole-program build then
  reports it exactly as before. `run` also takes that path for `--restrict`,
  `--report`, timings and JSON diagnostics.

The per-variant state lives in `<cache>/modules/<variant>/state.json`, and a
build holds the variant's lock, so two builds of one program wait for each
other rather than interleave.

## What is still whole-program

- **Emission facts are per configuration.** Whether a function allocates
  depends on the `debug` policy and the arena switch, so an interface's
  emission section names its configuration and a compile refuses facts for
  another one.
- **The arena switch** is one program-wide input (see above); flipping it
  recompiles every module.
- **The function-value target set** is read by no emitted text. Only a
  library's test-dependency facts list it, so an executable emission keys on a
  fixed marker instead (EMIT-VALUE-TARGETS-1), and each interface lists its
  module's share for a later whole-program merge.
- **The runtime data** (descriptors, renderers, host bridges, literals) is
  one C unit per program, merged from per-module blocks at link and keyed by
  its text.

The reports for stages 1b and 1c,
[devspeed-module-compile-2026-09-24](../audits/devspeed-module-compile-2026-09-24.md)
and [devspeed-module-schedule-2026-09-24](../audits/devspeed-module-schedule-2026-09-24.md),
hold the measurements and what is left.
