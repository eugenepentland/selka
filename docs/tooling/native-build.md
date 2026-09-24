# Native builds

`mylang build` turns a checked guest program into a Linux x86-64 executable or
shared library. The compiler drives the whole pipeline itself: it lowers the
checked program to bytecode, renders that as QBE intermediate code, runs QBE,
assembles and links, and bundles the native runtime sources it needs. There is no
installer script, no `make`, and no compiler source checkout in the loop. The
design record is
[incremental QBE native compilation](../experiments/incremental-qbe.md). For
when to reach for a native build, what the optimize mode costs, and how to
measure the result, see the [performance page](../performance.md).

Bytecode is still part of the compiler, but only as that internal IR. Nothing
executes it: there is no interpreter. QBE is the default backend in every mode,
because an edit-build loop wants the compile that takes a second; `--release`
asks for the qualified LLVM backend at `-O3` with full LTO. `mylang run` is this
same pipeline followed by running the result, and `dump-bytecode` disassembles
the IR for inspection rather than for execution.

## Backends

A native build that names no backend uses QBE, in `--mode ReleaseFast` (the
default for `mylang build` and `mylang run`) and in `--mode Debug` alike. The
optimized build is asked for by name, the way `cargo build --release` is:

- **`--release`** is the shorthand for `--mode ReleaseFast --backend llvm
  --llvm-opt 3 --lto`: the qualified LLVM backend at `-O3` with full LTO. It
  works on `build`, `build --run`, `run`, `run-project` and `test`.
  Written beside `--mode`, `--backend`, `--qbe`, `--llvm-opt` or `--lto` it is
  a usage error, because it already names them.
- **`--backend llvm [--llvm-opt 0|1|2|3|s|z] [--lto[=full|thin]]`** picks the
  LLVM backend with any other optimization level, with full LTO (`--lto`,
  `--lto=full`), with ThinLTO (`--lto=thin`, see
  [ThinLTO](#thinlto)) or without LTO.

An explicit choice is never changed. `--backend qbe` and `--qbe PATH` select
QBE whatever the mode, and the LLVM-only controls (`--llvm-opt`, `--lto`) are
rejected until `--backend llvm` or `--release` names that backend. `--report`
states the resolved `backend`, `optimization`, `lto` and `thin_lto` for every
build. `mylang test` follows the same policy through the child
build it spawns: its builds are QBE in either mode (`Debug` by default), and
`mylang test --release` builds the LLVM release path.

The price of each, on the 4,200-line Lox interpreter port with a ReleaseFast
compiler and a warm object cache: after a one-function edit the QBE build takes
0.7–0.9 s and the `--release` build 2.4–3.5 s, almost all of it the LTO link it
pays on every rebuild that changes anything, a comment included (2.6–3.0 s). A
cold `--release` build takes 4 s. Build with QBE while editing and testing, and
with `--release` for the executable you ship or time. The measurements are in
[the defaults report](../audits/devspeed-defaults-and-docs-2026-09-23.md) and
[the LLVM port report](../audits/devspeed-llvm-zig-2026-09-24.md).

The LLVM backend is built into the compiler (`LLVM-ZIG-1`). It translates each
guest unit's QBE IL into a textual LLVM module in process
(`src/qbe_build_llvm*.zig`) and compiles it with the clang that Zig bundles, so
it needs nothing beside the compiler but Zig: no Python, no adapter and no
per-unit translator process. Guest units are content-addressed and cached per
function, so only a unit whose IL actually changed is translated and compiled
again (see *Concurrent code generation* below). The translator used to be a
Python program, `experiments/llvm-backend/qbe_llvm.py`; it is kept there as the
equivalence oracle the Zig translator was checked against byte for byte, and
nothing in the build, the install or the compiler reaches it. `--llvm-adapter`
and `MYLANG_LLVM_ADAPTER` are gone. The old `--qbe PATH/qbe_llvm.py` spelling
still selects the built-in backend, at `-O2` without LTO (`MYLANG_QBE_LLVM_OPT`
changes the level); the file is never read.

Three switches turn one of the translator's rewrites off for an A/B run, and
each one keys the objects apart from a build that keeps it:
`MYLANG_QBE_LLVM_ALIAS=0` (the scoped alias metadata),
`MYLANG_QBE_LLVM_ELEMENT_GEP=0` (element GEPs) and `MYLANG_QBE_LLVM_STICKY=0`
(loop versioning). `MYLANG_LLVM_DUMP=DIR` writes every unit the build
translates as `DIR/SYMBOL.ssa` (its IL), `DIR/SYMBOL.ll` (its LLVM IR) and
`DIR/SYMBOL.sigs.json` (the call-site signatures it read); a warm cache
translates nothing, so pair it with a fresh `--cache-dir`.
`experiments/llvm-zig-20260924/equivalence.py` replays such a dump through the
retired adapter and requires identical IR.

```console
$ mylang build examples/factorial.my -o /tmp/factorial --cache-dir /tmp/cache --report
{"version":"qbe-build-v1",...,"mode":"ReleaseFast",...,"backend":"qbe","optimization":"default","lto":false,"thin_lto":false}
$ mylang build examples/factorial.my --release -o /tmp/factorial-release --cache-dir /tmp/cache --report
{"version":"qbe-build-v1",...,"mode":"ReleaseFast",...,"backend":"llvm","optimization":"3","lto":true,"thin_lto":false}
$ mylang build examples/factorial.my --mode Debug -o /tmp/factorial-debug --cache-dir /tmp/cache
$ mylang run examples/factorial.my --release
```

### Very large functions

QBE keeps one bit set of every temporary per block, so its memory grows with the
square of a function's size: about 1.6 bytes per block x temporary pair. A
straight-line function of 2 000 checked statements (12 000 bytecode
instructions, 8 000 QBE blocks, 76 000 temporaries) takes about 1 GB and 9 s;
4 000 statements take 3.7 GB and 72 s, and 8 000 would need about 14 GiB.
Before QBE starts, a function whose estimate exceeds three quarters of the
address-space ceiling QBE inherits from
the compiler (`MYLANG_HOST_MEMORY_LIMIT`, 8 GiB by default) is refused with a
message that names it and the two ways out — split the function, or build it
with `--backend llvm` — instead of failing minutes later inside QBE's `emalloc`.
The LLVM backend's dominator analysis is linear, so it builds a
120 000-instruction function (20 000 statements): with a Debug compiler in
about 4.5 minutes, nearly all of it clang optimizing the one function, with
3.0 GB in the largest process.

### What the LLVM backend is allowed to assume

The translator states no fact that a check the frontend emitted is about to
establish. It emits no `nsw`/`nuw`/`exact`/fast-math flag, no `inbounds`, no
TBAA and no `noalias` pointer attribute, because every overflow, bounds, cast
and allocation check is explicit code in the IL: the emitted sequence computes
the wrapped result and *then* tests it, so an arithmetic flag would make the
test that follows dead.

It does state one aliasing fact, and that fact never depends on a check having
run. Memory an emitted unit touches falls into two classes the translator can
place without looking at a guard:

- **frame** — storage this activation itself obtained: every `alloc4/8/16` of
  the unit (the local slots, the operand scratch, the aggregate scratch, the root
  records and the frame record), the private copy an aggregate parameter arrives
  in, and, for a unit whose frame is too large for the stack, the block
  `myl_qbe_frame_allocate` freshly allocates on entry and releases on exit;
- **foreign** — storage some other allocation owns: a value the caller computed
  (a scalar parameter such as `%ctx`), a global's address, the context's embedded
  heap record that `myl_qbe_heap` answers, and every address the emitter marked
  `# myl-obj %temp` — a managed container's header and the element storage that
  header points at, both from `myl_native_heap_alloc`.

The two are disjoint because everything in **frame** is an allocation this
activation made after it was entered: no value that existed before the call can
point into it, no managed object is allocated inside it, and it is released
before the activation returns. So the translator gives each placed access
`!alias.scope`/`!noalias` saying the two classes never meet. It carries a class
through `copy` and offsetting `add`, and through a stack slot whose address
never leaves the unit by a forward must-analysis: a load answers the class the
last store put in the slot on every path that reaches it, and nothing when two
paths disagree or a path reaches it before any store. Everything else is left
unplaced and carries no metadata, which keeps it aliasing both classes the way
every access behaved before. This is what lets a loop keep a container's length
and storage pointer in registers instead of reloading the header on every
element; `MYLANG_QBE_LLVM_ALIAS=0` turns the metadata off for an A/B run.

Foreign memory is placed more finely where the emitter says what it is
(`LLVM-ELEMENT-CLASS-1`). The storage word of a managed container — the start of
its element storage block — is marked `# myl-elem %temp KIND`, where KIND is the
element size and `r` for GC references or `v` for plain values, and every other
marked address is an **object** (a header or an allocation's payload). An
object access and an element access never alias, and neither do element
accesses of two kinds: each storage block is an allocation of its own that no
object overlaps and that only ever holds elements of its kind. A plain foreign
access still aliases all of them, and a copy between two classes carries both
classes' scopes and only the scopes neither end can alias. This is what keeps a
list's length and storage word, and a list of lists' row pointers, in registers
across a loop that stores into element storage (`matmul`, `nbody`).

A load or store whose address is an element address computed earlier in the
same block — the marked storage word or object plus at least one variable term
— is given that address as a plain `getelementptr i8` from the marked base
instead of an `inttoptr` of the integer sum (`LLVM-ELEMENT-GEP-1`). The bits
are the same; LLVM's scalar evolution does not look through `inttoptr`, so only
this form lets it see `data[i]` advance by one element per iteration, load a
whole vector instead of gathering one element at a time, and compute
dependence distances.

The `# myl-obj` and `# myl-elem` markers are comment lines of their own. QBE's
lexer drops a `#` comment to end of line, so the QBE backend's assembly is
byte-identical with and without them.

The translator does lower one kind of check differently, without assuming anything
about it: a checked 64-bit `+`, `-` or `*` becomes
`llvm.{s,u}{add,sub,mul}.with.overflow.i64`, so it reaches the machine as the
operation and one flag branch (`add; jo`, `sub; jb`, `imul; jo`) rather than the
frontend's xor/and sign test or its four-limb high product. The translator evaluates
each block symbolically and replaces a flag only when its value is *exactly* one
of the frontend's overflow formulas over an `add`, `sub` or `mul` earlier in the
block. Each formula equals the intrinsic's overflow bit for every pair of 64-bit
operands, so this is a change of spelling, not a new fact: the branch, the cold
block and its `myl_qbe_fail_overflow_op` call (same operands, width and
position) are untouched, and a trap reports exactly what it did before. A
narrower width's range test and the single compare against a literal operand
are already one compare and stay as they are. `LLVM-OVERFLOW-INTRINSIC-1` in
`SPEC.md` states the rule; `OverflowChecks` in
`src/qbe_build_llvm_classes.zig` implements it.

It also versions a loop whose overflow checks decide nothing but the trap
(`LLVM-STICKY-REDUCTION-1`, `src/qbe_build_llvm_sticky.zig`). The
loop's entry goes to a fast copy in which the check of a *reduction* — a frame
cell the loop changes only by adding or subtracting a 64-bit signed value to a
value it held — is dropped while the copy sums the magnitudes of what it adds,
and any other overflow check is *sticky*: its flag is OR-ed into one word and the
copy continues with the wrapped value. Bounds, cast, division and iteration
checks stay branches, to a fallback. Each exit of the fast copy verifies that the
sticky word is zero and that `|entry value| + sum |added| <= 2^63 - 1` for every
reduction, which bounds every intermediate value; then the fast copy computed
exactly what the checked loop would have. Otherwise, and on every would-be trap,
the fallback restores each frame cell the loop wrote and runs the original loop
from the same state, so a trap reports the same code, operands, position and
trace as before. The rewrite requires a loop with no call, `blit` or phi, whose
stores all land in this activation's own cells, and in which no value that may
have wrapped reaches a non-check branch, an address, a shift amount, a divisor, a
float-to-integer conversion or a cell whose address escapes; a check whose value
would is kept as a branch. The fast copy of `count += 1` or `total += x` is
branch-free and LLVM vectorizes it. `MYLANG_QBE_LLVM_STICKY=0` turns it off.

## `mylang build`

`mylang build <file.my> -o <output>` checks the program, lowers it, compiles its
guest functions into independently cached objects — one per module batch on
QBE, one per function on LLVM (see *Concurrent code generation*) — and links
those objects with the bundled runtime. `--run` replaces `-o`: it executes a temporary binary with
inherited stdin, stdout, stderr and working directory, returns that program's
exit status, and removes the binary afterwards while keeping the cached objects;
runtime options go before `--` — the same `--restrict` and `--allow-*`
capability options, budgets, `--gc-stress` and `--print-result` that `mylang
run` takes — and the values after `--` are the program's arguments. A native
executable grants every capability by default. It hands `main(args)` every
argument after `argv[0]` unchanged and reads its runtime options only from the
`MYLANG_OPTIONS` environment variable, spelled as on the `mylang run` command
line and separated by spaces, so `MYLANG_OPTIONS=--restrict ./app` denies every
capability and `./app --gc-stress` passes `--gc-stress` to the program. See
[the native backend](../io.md#the-native-backend) for quoting and errors. Build tools resolve from `--qbe`/`--zig` first,
then from executables sitting beside the running `mylang`, then from `PATH`, and
never from the working directory. `amd64_sysv` is the only supported target, a
module entry needs `--project`, `--library` produces a shared library, and a
program using a construct the native backend does not implement fails with
`E_QBE_UNSUPPORTED` before any output is written. `--report` adds one
`qbe-build-v1` JSON line naming every compiled function, its own cache key, the
cached object that holds it, whether that object was reused, how many distinct
objects hold the guest functions (`function_objects`) and how many of them this
build compiled (`compiled_function_objects`), and the resolved `backend`,
`optimization` and `lto` (and `thin_lto` for a ThinLTO build); `zig build
test-qbe-build` repeats the builds through a relocated compiler with no Python
on `PATH` using the Zig-native build driver tests, and neither backend needs
one.

```console
$ mylang build examples/factorial.my -o /tmp/factorial --cache-dir /tmp/qbe-cache
$ /tmp/factorial
120
$ mylang build examples/factorial.my --run --cache-dir /tmp/qbe-cache
120
```

An instruction step ceiling is compile-time policy. A `Debug` build, a shared
library, and a `run` that named `--max-steps=N` carry exact per-instruction
accounting, so the ceiling stops the program at the instruction it names. A
`ReleaseFast` executable that was never asked for a ceiling carries none: it
emits no step check, which is what makes the default `mylang run` and
`mylang build --mode ReleaseFast` output small and fast. It links no frame
record either: see [trap traces without a frame record](#trap-traces-without-a-frame-record).
Because such a binary cannot honor a ceiling, giving it `--max-steps=` at runtime (or in `MYLANG_OPTIONS`)
reports `R_NO_STEP_ACCOUNTING` and names how to get a bounded run, rather than
silently ignoring the flag; `--max-frames=` likewise reports
`R_NO_FRAME_ACCOUNTING`. `--timeout` and `--max-memory` are enforced by the
runtime and are unaffected.

## Trap traces without a frame record

A build with step or frame accounting — `Debug`, a library, the guest-test
runner, a run or build given `--max-steps` or `--max-frames` — links a 32-byte
frame record into `ctx->active_frame` on every call and stores the current
instruction's position into it, and a trap's `in f at file:line` trace is that
chain. A checked `ReleaseFast` executable and `mylang run` without a ceiling do
neither (`QBE-FRAMEMAP-1`): no guest call loads, stores or links anything for
the trace, and positions are recovered from return addresses only when a trap
fires.

- **In the IL.** Each unit starts with `dbgfile "SYMBOL"` and every call is
  preceded by `dbgloc PC+1`, the bytecode instruction the call belongs to. The
  prologue keeps only the execution-stack floor test; its `myl_qbe_fail_frame`
  call is `dbgloc 1, 1`, the entry-guard mark.
- **QBE** prints each `dbgloc` as a `.loc` line. QBE never inlines, so a call's
  `.loc` is its whole position.
- **LLVM.** The translator gives each call a debug location whose line is the
  position and whose discriminator is a pseudo-probe call index equal to it,
  and names every unit in `llvm.pseudo_probe_desc`. LLVM prints
  `.pseudoprobe GUID INDEX … @ CALLER_GUID:INDEX …` right before each call, the
  `@` list naming every guest function the call was inlined through — so LLVM
  keeps inlining guest code freely and the trace still names each logical frame
  at its own call site. A runtime helper LLVM inlines has no debug information,
  so its calls carry the probe of the call it replaced: a trap inside the helper
  reports the helper's call site, exactly as the record's position did. Calls
  are `nomerge` (two call sites never fold into one position),
  `"disable-tail-calls"` keeps a call from replacing its caller's frame, and
  `uwtable` gives every such function unwind tables, so guest code keeps no
  frame pointer. A position past the 16-bit probe index is `noinline` at its
  call and on its function.
- **The table.** Before an object is assembled — per unit for QBE and LLVM
  without LTO, for full LTO on the assembly LLD produces for the whole
  program (`--lto-emit-asm`, then an ordinary native link), and for ThinLTO on
  the assembly LLD produces for each module —
  `src/qbe_frame_map.zig` puts a label after every positioned call, removes the
  `.file`/`.loc`/`.pseudoprobe` directives and probe descriptors (no DWARF
  reaches the object), and appends a retained `mylang_frame_map` section with
  one entry per logical frame of each call site, innermost first: the return
  address, the position with an entry-guard and an inlined-caller bit, and the
  unit's metadata, each as a 32-bit self-relative offset; an entry from
  assembly that carries call-frame information (LLVM's) also has an unwind bit.
- **At a trap.** The runtime (`fail` in `src/qbe_runtime.c`) sorts the table
  once, walks the guest stack from its own frame, reports every return address
  found in the table (skipping an entry guard's frame, which was never
  entered) and expands bytecode-inliner splices as before. An LLVM program is
  unwound by its call-frame information: the executable links Zig's libunwind
  statically and the runtime calls `_Unwind_Backtrace`. A QBE program follows
  the frame-pointer chain: QBE keeps a frame pointer in every function that
  calls, and so do the generated C and every runtime unit that can reach
  `fail`; the heap, collector and container units, which only return a status,
  keep every register.

A trap's code, message, trace, `MYLANG-TRAP` record, `assert` message and exit
status are byte-identical to the linked-record protocol, including for a callee
LLVM inlined, a trap inside an inlined runtime helper, a callback, deep
recursion and a stack-floor failure.

## Checks in every build

Every build keeps the language's value guards: integer overflow on `+`, `-`,
`*` and unary `-`, narrowing integer casts, index bounds on lists, fixed arrays,
`bytes`, `str`, dictionary position reads and `pop()`, and the frame protocol
that gives a trap its source location and call trace. That holds in `--mode
Debug` and `ReleaseFast`, under `--release`, on both backends, and for `run`,
`run-project`, `build --run` and `test`. A would-be trap is therefore always
reported, never undefined behaviour, and optimization never changes a program's
result. A guard is left out only where the compiler proved it cannot fire, such
as a cast whose source range fits its target or the accesses and arithmetic of
a versioned loop whose guard held.

The former `--unchecked` policy, which omitted those guards, was removed.
Naming it is a usage error (exit 2) that says so, for example
`mylang build: --unchecked was removed: every build keeps overflow, cast and
bounds checks so optimization never changes a program's result`. The same
spelling after `--` still reaches the guest.

## Incremental frontend

A project build no longer lowers and renders the whole program when little
changed. These mechanisms stack; each is a cache the next build consults before
doing the work.

- **Unchanged build (`BUILD-NOOP-1`).** Beside the output the driver records a
  receipt: a key over the frontend's manifest, the build environment and every
  flag, plus the output file's inode, size and modification time. A build whose
  key matches and whose output is untouched returns before parsing the manifest,
  staging objects or linking. `--run`, `--report`, a provider and explicit link
  inputs never take this shortcut.
- **Unchanged project (`EMIT-REPLAY-1`).** The frontend child remembers its last
  manifest and warnings per entry and configuration. An identical project replays
  them after loading its sources, with nothing checked, lowered or emitted.
- **Unchanged functions (`QBE-FRAGMENT-REUSE-1`).** Each function's QBE unit is
  keyed by what its text depends on: its own lowered body, the signature and
  policy of every function it names, the schema of every record it reaches, the
  whole-program switches, and whether each callee can allocate. Records and
  functions enter the key by name, and source positions not at all, so an edit
  that shifts ids or lines elsewhere leaves the key alone. An unchanged key
  answers from the fragment store under the frontend cache
  (`<cache>/frontend/fragments`) without lowering the unit to QBE. The emitted
  manifest is byte-identical to a fresh emission.
- **Unchanged functions are not even lowered (`EMIT-STANDIN-1`).** An
  executable's emission (`build`, `run`, `run-project`) keys each declared
  function by its source identity: the checker's stable declaration key, its
  dependency context and the digest and length of its declaration region. Every
  function it lowers leaves a *record* under that identity: its stored unit and
  metadata digest, the facts other units read about it (its inline key, whether
  it allocates, what it calls and writes), and a snapshot digest of everything
  its unit read (each named function's interface, the schemas it reaches, the
  sources its positions fall in). The next emission lowers only the functions
  with no current record, plus the ones a caller may inline and the few that
  are always lowered (the entry, printers, specializations, lambdas). If a
  record turns out stale once the program-wide facts are recomputed, that
  function is lowered too, until nothing is stale. The manifest still names
  exactly the texts, facts and metadata a full emission names.
- **Metadata by digest (`EMIT-META-1`).** A lean unit names its location,
  message and inline tables by the digest of their stored text, keyed by the
  unit and the digest of every source its positions fall in. Only a unit whose
  function or sources changed computes them again; a just-computed record rides
  inline in the manifest so the driver does not read it back.
- **Lean manifests.** `build --project`, `run`, `run-project` and `mylang test`
  hand the driver each unit's digest and stored path instead of its text, and
  its source positions as one compact string (`BUILD-POSITIONS-1`). Objects are
  named by that digest, so the driver reads a unit's text only to build an
  object that is missing, one member at a time (`BUILD-MEMORY-1`).

The fragment store and the replay slots are partitioned by compiler identity
and are removed with the rest of the cache; `--no-cache` bypasses all of them.
`work-report-v1` counts a unit answered from the store, or taken from a record,
as a reused, not an emitted, fragment.

The store does not grow without bound (`FRAGMENT-SWEEP-1`). Each entry point
keeps one pack of entries, holding what its last build used plus a bounded
number of older entries. A stored text that no pack and no replay names is
deleted by an occasional sweep, which a build runs only while it holds the
store's lease exclusively, so a text another build is still reading is never
removed underneath it.

```console
$ mylang build main.my --project -o app --timings=json
{"version":"phase-timings-v1",...,"name":"frontend","duration_ns":95000000,...}
{"version":"phase-timings-v1",...,"name":"codegen","duration_ns":0,...}
{"version":"phase-timings-v1",...,"name":"link","duration_ns":0,...}
```

On the generated 50,000-line ladder project (120 modules, 4,681 functions), an
unchanged build takes 0.04 s and a one-line body edit 0.38 s, of which 0.11 s
is the edited project's check (`mylang check`). At 204,000 lines the edit
takes 1.48 s against a 0.43 s check, and a cold build finishes in 26 s at a
2 GB peak. The measurements are in
`docs/audits/devspeed-build-residue-2026-09-24.md`.

## Object cache and link

For project entries, `mylang run` also caches the emitted manifest after validating
the current source graph and policy. An unchanged run reuses it before lowering or
QBE emission; the native executable cache then verifies its own runtime, backend,
toolchain and build settings. Source changes, emission controls and compiler identity
invalidate the manifest, damaged entries are misses, and `--no-cache` bypasses it.
`--timings=json` reports the actual lowering and emission work, including zero work
on a warm hit. Runtime arguments and capability grants are still applied each run.
An explicit `--explain-invalidation` still lowers to construct its detailed
fragment receipt; that diagnostic work is reported rather than hidden.

Everything a build compiles is content addressed under `--cache-dir`
(`.mylang-cache/qbe` by default): on QBE one object per batch of guest
functions and one for that batch's function metadata, on LLVM one object per
guest function, and on both one for the generated typed-metadata unit and one
for the generated entry adapter. Their
keys cover the *native driver* identity, the runtime content hash, the codegen
tool stamp (QBE's stamp, or the LLVM translator identity), the
optimization level, which LTO (none, full or thin), and the target, so a changed tool, mode,
optimization or backend never reuses an object built by another one. The native driver identity is a
build-time digest over only the sources that decide how already-emitted QBE IL
becomes an object or an executable — the build driver (`src/qbe_build*.zig`),
the link-argument policy (`src/native_link*.zig`) and the frame-map annotator
that rewrites every unit's assembly (`src/qbe_frame_map.zig`) — plus the Zig
version and the optimize mode. Everything else is keyed separately: the IL text names the object,
the bundled runtime sources are covered by the runtime content hash, and the
tools by their stamps. An edit to the parser, the checker or the lowering
therefore changes the IL of the functions it affects and nothing else; guest
objects and executables whose IL did not move stay reusable, instead of the whole
cache being evicted on every compiler rebuild.

Objects live in one *generation* directory, `objects/<hash>`, named by the native
driver identity and the runtime the compiler bundles. Opening a generation evicts
every sibling generation: the keys a new driver asks for can no longer match the
old entries, so nothing is lost by removing them, and the cache never accumulates
one set of objects per build driver. Tool stamps, mode and target stay in each
object's key but not in the generation, so every process of one compiler build
shares one generation — whichever path it resolved its tools from, whichever mode
it asked for — and concurrent builds never evict each other. `mylang run` keeps
its programs the same way under `run/<hash>`, and the Zig test suites keep the
guest executables they build under `exe/<hash>`. Eviction is best effort: a cache
that cannot be swept still serves the generation it keeps.

Generations are leased, because one cache root is shared by processes whose
driver identities differ — the compiler and the host applications each open their
own generation, concurrently, during a single `zig build test`. A process that
opens a generation for use creates `.lease` inside it and holds a *shared*
advisory lock on that file for the rest of its life; a sweeper takes a
*non-blocking exclusive* lock on each sibling's lease before evicting it and
skips every generation it cannot lock. A generation another process is still
compiling or linking into is therefore never deleted underneath it, which is what
used to surface as `ld.lld: error: cannot open .../<obj>.o: No such file or
directory` or a `FileNotFound` while publishing. Leasing is advisory and needs no
clock: an entry with no lease file is swept as before, a filesystem that cannot
lock behaves exactly as it did, and the kernel drops a dead process's lease, so an
interrupted build never pins a generation.

Publication heals a lost race rather than failing the build. A rename into a
generation directory that reports the destination missing recreates and re-leases
that directory and retries once, and a link whose cached input objects are gone
from disk rebuilds them into the restored generation and retries the link once. A
link that fails with every input still present is the program's own link error
and is reported unchanged.

Every object, archive and executable is built without debug information: C and
assembly compiles pass `-g0`, the Zig runtime unit is built with `-fstrip`, and
the link strips the symbol table. Native traps, their frames and their
structured detail come from the runtime's own tables rather than from DWARF, so
a program reports the same diagnostics with none of the weight; a `mylang run`
executable is tens of kilobytes rather than over a megabyte.

The fixed runtime translation units are not linked as loose objects. A single
`zig build-obj` compiles all of them in one process into one relocatable object —
a cold build pays one toolchain start rather than one per unit — and that object
becomes the single member of an archive published beside the objects. The link
places the archive after every object that can reference it. Because the merge
keeps every unit's function and data sections and the link collects unreferenced
ones, a program that never prints still carries no printing runtime. A build that
changes nothing relinks nothing observable: when every object the link names was
reused, the candidate and the published executable are compared by length and
then by bytes, and an identical result keeps its inode and modification time,
which `--report` shows as `"output_changed": false`. A link over any object the
build compiled makes a new program, so it is published without reading either
file (at 200,000 lines that comparison read two 130 MB executables).

An unchanged build goes one step further and **skips the link itself**. The
sidecar beside the executable records a link identity over the object set, the
runtime archive, the artifact kind, the mode, the target and the symbol policy;
when the executable is still present and executable, every cached object and the
runtime archive are still on disk, and the identity matches, the build reuses
the published file without running the linker. The check is deliberately
conservative: a `--provider` or any explicit native link input (`--link`,
`--link-library`, `--library-path`) disables reuse, because such an input can
change without changing a guest object. This is what keeps an unchanged
`--release` rebuild from paying the LTO link again.

A link that does run skips the `zig cc` driver (`BUILD-LINK-1`). Before it
starts `ld.lld`, `zig cc` probes the host C compiler (`cc -E -Wp,-v`,
`cc -print-file-name=crt1.o`) and resolves the archives it bundles, and it
gives the same answer every time for the same flags on the same host. So the
first link of a given shape runs `zig cc -###`, which links and prints the
linker command, and the build keeps that command beside the objects with the
object list and the output replaced by markers. Every later link of that shape
runs `zig ld.lld` with the recorded arguments and its own objects and output.
The template is keyed by the build environment, the variables the probe reads
(`PATH`, `ZIG_LIBC`, `LIBRARY_PATH`, …) and every other argument. It is not used
when a path it names has disappeared, and a direct link that fails goes through
`zig cc` again. `--report` names the route as `link_route` (`recorded`,
`direct` or `driver`).

Every link command passes its arguments through a response file (`@link.rsp`
beside the output, `BUILD-LINK-RSP-1`), because a link names every object: a
million-line program's 19,007 objects are 4.66 MB of arguments, past what the
kernel accepts for one `execve`. `zig cc` still starts `ld.lld` with every
object named, which the kernel refuses past about 6 MB; when that recording run
fails having printed its command, the build links directly from the printed
command, through a response file, and keeps it as the template. A tool the
kernel refuses to start reports why: `host failure: ArgumentListTooLong` rather
than `Unexpected`.

A cached object or archive is accepted only when a fingerprint over its length
and contents matches the one stored beside it in a `.digest` file. Damaged bytes
and a damaged fingerprint are both misses, so a corrupt cache repairs the one
entry it lost rather than failing the build or silently linking rubble. The
`.digest` file also records the published file's inode, size and modification
time, and an object that still has exactly that identity is accepted without
reading it; anything that wrote, truncated or replaced it changes the identity,
and then the bytes are fingerprinted again. Cache keys are BLAKE3 over the
framed environment, contract, kind and input: a warm build keys every unit and
batch, and the pinned toolchain's SHA-256 runs at about 14 MB/s on some hosts.

```console
$ mylang build examples/factorial.my -o /tmp/factorial --cache-dir /tmp/qbe-cache --report
{"version":"qbe-build-v1","output":"/tmp/factorial","output_changed":true,...}
$ mylang build examples/factorial.my -o /tmp/factorial --cache-dir /tmp/qbe-cache --report
{"version":"qbe-build-v1","output":"/tmp/factorial","output_changed":false,...}
```

## Prebuilt runtime archive

Compiling the runtime is the only real work a cold build does — everything else
is codegen and a link measured in tens of milliseconds. So `zig build` does that
work once, when it builds the compiler: it prebuilds the runtime archive and the
text-formatter object and installs them beside the compiler under
`zig-out/lib/mylang-runtime/`, each named by a portable hash of the runtime
content hash, the pinned Zig version, the optimize mode, the target and the
**backend flavor**. There are five flavors:

| mode | flavor | codegen |
|---|---|---|
| `Debug` | `qbe` | QBE, `-O0` |
| `ReleaseFast` | `qbe` | QBE, `-O2` |
| `ReleaseFast` | `llvm` | LLVM `-O3` |
| `ReleaseFast` | `llvm-lto` | LLVM `-O3` with `-flto`, so the link sees bitcode |
| `ReleaseFast` | `llvm-thinlto` | LLVM `-O3` with `-flto=thin`, ThinLTO bitcode |

The flavor is part of the hash, so a QBE archive can never be linked into an
LLVM build, an `-O3` archive can never be linked into an LTO one, and full and
thin bitcode never stand in for each other. `mylang` finds the directory
relative to its own executable, the same way it finds the sibling `qbe`. Every
flavor needs only Zig, so `emit-runtime` always publishes all five.

A cold `mylang build` computes the hash its runtime needs and, if a matching
archive is installed, links it directly and skips compiling the runtime from
source — `--report` shows `"runtime_installed": true`. This is what makes a
`--release` build affordable: it links the `llvm-lto` bitcode archive instead of
compiling twenty runtime translation units with LTO itself. The
prebuilt hash excludes the Zig and QBE tool file stamps that object-cache keys
carry, so an installed archive still matches a build that resolved those tools
from a different path. A missing archive (a cross-target build, or a relocated
compiler with no `lib` beside it), a mode with no matching install, or a
corrupted file whose fingerprint no longer matches the `.digest` published
beside it all fall back cleanly to compiling the runtime from source.

## Concurrent code generation

On LLVM each guest unit is its own content-addressed object, and a cache hit
translates and compiles nothing. The units that missed are built on worker
threads, as many as the cores this process may use and the free memory allow
(`src/qbe_build_llvm_compile.zig`). A worker translates its unit in process,
writes the module to a private scratch directory and starts one clang for it:
the `-cc1` command `zig cc -###` reports once per build for the same flags, so
a unit pays one clang start and not a `zig cc` driver with its host probes.
Under LTO clang writes the unit's bitcode object; without LTO it writes
assembly, which is frame-map annotated and assembled.

A call site declares its callee from the callee's own IL header. Before the
workers start, the build reads the header of every unit that missed and of
every unit a miss names by `$symbol`, so the table is complete whatever order
the workers finish in, and every unit declares its callees exactly as a
sequential build would. After the first failure no worker takes a new unit;
every failure is reported, in unit order, once all workers have stopped.

Before this, the translator was a Python process per unit, and a 50,000-line
`--release` build took 369 s cold; a 200,000-line one did not finish in 30
minutes. The numbers after the change are in
[the lane report](../audits/devspeed-llvm-zig-2026-09-24.md).

### QBE batches

The QBE arm used to start QBE and then the assembler once per guest function,
which was most of a cold build: 36 s for a 10,000-line project and 510 s for a
50,000-line one, about 110 ms per function. Two things made each start that
expensive, and both are gone.

- **Starting a tool no longer copies the build.** The driver holds the whole
  emitted program — close to a gigabyte at 50,000 lines — and `fork` copied its
  page tables for every tool it started. Every tool (QBE, the assembler, the C
  compiler, the linker, clang for an LLVM unit) now starts with
  `clone(CLONE_VM | CLONE_VFORK)`, the way `posix_spawn` does, so a start costs
  the same whatever the driver holds (`src/qbe_build_spawn.zig`).
- **Functions compile in batches.** Units are ordered by module, then symbol. A
  batch never spans two modules; a new one starts at every symbol whose hash
  marks a boundary (one in 8 on average, so a body edit recompiles about eight
  functions) and after 128 functions. A unit that
  defines data compiles alone. One QBE run takes each member's IL as its own
  input file (QBE forgets aggregate types between files, so members' types never
  collide) with every function in its own `.text.<symbol>` section, so
  `--gc-sections` still drops a function nothing calls. The assembly is
  frame-map annotated and assembled once, by Zig's LLVM assembler called
  directly (`zig clang -cc1as`), skipping the host C library probe and the
  relocatable relink `zig cc` adds to every assembly.

A batch's object is keyed by the ordered cache keys of its members, each still
the function's IL under the build environment, so a changed function, driver,
runtime, tool, mode or target misses exactly as a per-function object did. The
boundaries depend on symbols, never on bodies: a body edit rebuilds one batch,
and adding a function disturbs only the batch it lands in. Each batch's function
metadata — the location, message and inline tables a trap trace reads — is a
second small object assembled from generated assembly, so an edit that moves one
module's lines recompiles that module's tables and not the whole program's; the
program-wide metadata and entry C units compile in the same pool. Missing
objects build concurrently, as many at once as the cores this process may use
and the free memory (256 MiB per tool) allow. After the first failure nothing new
starts, every running tool is reaped and every scratch directory removed.

`MYLANG_QBE_BATCH=N` caps a batch at `N` functions; `MYLANG_QBE_BATCH=1`
compiles every function alone, which `zig build test-qbe-build` uses to check
that a batched and an unbatched build of one program print the same output,
exit the same way and report the same trap trace.

```console
$ mylang build main.my --project -o app --report
{"version":"qbe-build-v1",...,"compiled_functions":4681,"function_objects":279,"compiled_function_objects":279,...}
$ MYLANG_QBE_BATCH=1 mylang build main.my --project -o app-unbatched --cache-dir /tmp/unbatched
```

Measured on the [S-expression parser](../../experiments/sexpr-port/main.my)
(101 functions, 1 MiB input), cold wall clock before this work was 12.7 s for
LLVM against 3.2 s for QBE; it is now about equal: roughly 4.1 s each, with
QBE's time unchanged. An unchanged rebuild is about 1.0 s on either arm: the
per-function object cache makes codegen a hit, and an unchanged build whose
published executable still matches every input **reuses it without relinking**
(see *Object cache and link*). Relinking after a one-function edit costs the
LTO link, about a second on the LLVM arm and milliseconds on QBE.

## ThinLTO

Full LTO, the `--release` link, merges every bitcode module into one and
optimizes it on a single thread, so its link grows with the whole program and
uses no more than one core: about 60 s of a 50,000-line build and 250 s of a
200,000-line one, and it pays that again after any edit. `--lto=thin` (with
`--backend llvm`) is the parallel alternative (`LLVM-THINLTO-1`). Every guest
unit and the runtime become ThinLTO bitcode, LLD reads their summaries, decides
what each module imports from the others, and optimizes and compiles the
modules on as many threads as the cores and free memory allow, each to its own
assembly file. Each file gets its frame-map table and is assembled on worker
threads, and the objects are linked natively as under full LTO.

```console
$ mylang build main.my --project -o app --mode ReleaseFast --backend llvm --llvm-opt 3 --lto=thin
```

Traces, trap records and exit statuses are those of the full-LTO build: a
callee inlined from another module is named through every unit's probe GUID,
the generated entry and metadata C stay machine code so no module without
probe descriptors imports guest code, and the link keeps LLVM from folding
copies of a callee inlined at different call sites into one block whose call
site is lost (sinking common instructions and merging block tails are off).

The trade, measured with a ReleaseFast compiler on a shared 20-thread machine
(load 4 to 22, `taskset -c 0-11`):

| program | full LTO cold / edit → build | ThinLTO cold / edit → build |
| --- | ---: | ---: |
| Lox port, 4,200 lines | 4.0 s / 2.5 s | 2.5 s / 1.7 s |
| 50,000-line ladder | 91 s / 61 s, 1.9 GB | 68 s / 38 s, 1.1 GB |
| 200,000-line ladder | 398 s / 256 s, 7.1 GB | 207 s / 132 s, 3.5 GB |

ThinLTO sees less of the program at once, and the code is slower where full
LTO inlines runtime helpers across the whole program: on bench-parity it is
1.7% slower in the geometric mean and up to 26%
slower on single programs (`knucleotide`, `dict_count`, `fannkuch_redux`). So `--release` keeps full
LTO, and ThinLTO is the choice for a large program whose release build full
LTO makes too slow, or too big: the 200,000-line full-LTO link peaks at 6.5 GB,
close to the compiler's 8 GiB ceiling that its tools inherit. LLD's ThinLTO
cache cannot be used here, because a cache hit writes an empty assembly file
under `--lto-emit-asm`; an edit therefore recompiles every module. The numbers
are in [the LLVM port report](../audits/devspeed-llvm-zig-2026-09-24.md).

## Runtime source tree and shared caches

The build also needs the runtime C sources and headers on disk, because the
generated entry and metadata objects `#include` them. That tree materializes once
per content hash, and where it lands follows the cache selection:

- **`--cache-dir DIR`** keeps everything hermetically under `DIR`: objects in
  `DIR/objects/<generation>`, the runtime tree in `DIR/runtime/<hash>`. Nothing
  outside `DIR` is read or written, which is what the test suite relies on for
  isolation.
- **The default (no `--cache-dir`)** keeps the per-project object cache at
  `.mylang-cache/qbe` but shares the runtime tree at a user-level location —
  `$XDG_CACHE_HOME/mylang/runtime/<hash>`, falling back to
  `$HOME/.cache/mylang/runtime/<hash>`, and to the per-project cache only when
  neither variable names an absolute home. A brand-new project therefore reuses a
  runtime tree another project already derived, and the installed archive means it
  compiles no runtime at all on its first build.

Concurrent builds sharing either location stage the tree into a private directory
and rename it into place, so no build ever observes a partial tree.

### Where the content hash comes from

Every shared runtime tree and installed archive is named by `content_hash`, so the
hash must describe the bytes the compiler bundles. A build that finds
`runtime/<hash>` already present reuses it without looking inside. If the hash
names other bytes, the build silently links a stale runtime.

`zig build` computes the hash in its make phase. `build_qbe_assets.zig` is
compiled into a small host tool, and one run of it does all of the following:

- walks `src`;
- selects the runtime closure (every top-level `.c`/`.h` file plus what
  `native_format.zig` imports or embeds);
- copies that closure beside a generated `assets.zig`;
- writes `content_hash`, `compiler_identity` and `driver_identity` from the bytes
  it just copied;
- writes a depfile naming every production source it read.

The run's cache key covers its absolute `src` argument and the contents of every
file in that depfile. So an edit to any production source re-runs it, and two
source trees never share its output.

The digests used to be computed in `build.zig`'s configure phase. Zig caches that
phase under a key that ignores the build root, and it records each
`dependOnFileContents` input by absolute path. A second tree built with the same
`ZIG_LOCAL_CACHE_DIR` therefore reused the first tree's configuration. It
embedded the first tree's `content_hash` beside its own runtime bytes, and none
of its own later edits invalidated that, because the recorded inputs were the
first tree's files. Benchmarks then measured the first tree's runtime from the
shared `~/.cache/mylang/runtime`.

The configure phase still holds absolute paths, for example the `qbe` location
handed to tests and to `emit-runtime`. So a reused configuration
is still wrong, even though the hash no longer comes from it. The asset tool
compares the configured build root with the tree it is building, and fails when
they differ:

```console
qbe-build-assets: this build configuration belongs to /path/to/other-tree, not /path/to/this-tree.
```

Give every source tree its own `ZIG_LOCAL_CACHE_DIR` (or `--cache-dir`). The
default, `.zig-cache` inside the tree, already is.

Three checks guard this:

- `zig build test-runtime-identity`, also part of `zig build test`, runs
  `tests/runtime_identity_cache.py`. It builds throwaway trees with the real
  `build_qbe_assets.zig`: two trees sharing one Zig cache, then in-place
  edits to a runtime C unit, an imported Zig runtime unit, a frontend source, a
  driver source and a test-only file. After every build it checks that the
  embedded hash is the digest of the embedded bytes, and that those bytes are
  the tree's sources.
- In `src/qbe_build_test.zig`, one test recomputes `content_hash` from the
  bundled bytes.
- A second test there compares every bundled file with `src/<path>` on disk.
