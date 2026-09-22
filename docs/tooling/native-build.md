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
executes it: there is no interpreter. QBE is the inner-loop backend and the
`Debug` default; the `ReleaseFast` default is the qualified LLVM backend at
`-O3` with full LTO. `mylang run` is this same pipeline followed by running the
result, and `dump-bytecode` disassembles the IR for inspection rather than for
execution.

## Backends

A native build names no backend by default, and the optimize mode decides:

- **`--mode ReleaseFast`** (the default for `mylang build` and `mylang run`)
  uses the qualified LLVM backend at `-O3` with full LTO — exactly
  `--backend llvm --llvm-opt 3 --lto`.
- **`--mode Debug`** keeps QBE, because unoptimized LLVM buys nothing over it,
  and `mylang test` keeps its own `Debug` default for the same reason.

An explicit choice is never upgraded. `--backend qbe` and `--qbe PATH` select
QBE whatever the mode, and the LLVM-only controls (`--llvm-adapter`,
`--llvm-opt 0|1|2|3|s|z`, `--lto`) are rejected until `--backend llvm` names
that backend. `--report` states the resolved `backend`, `optimization` and
`lto` for every build. `mylang test` follows the same policy through the child
build it spawns: a `ReleaseFast` test run uses the LLVM release path, a `Debug`
run uses QBE, and `--qbe PATH` forces QBE.

The LLVM backend is the Python adapter installed beside the compiler at
`lib/mylang-llvm/qbe_llvm.py` (its helpers `llvm_emit.py`,
`runtime_signatures.py` and `amd64_sysv.py` sit in the same directory).
`--llvm-adapter PATH` overrides it, `MYLANG_LLVM_ADAPTER` names it for a
compiler that runs from a directory with no install beside it (the build's own
test drivers set it), and `MYLANG_QBE_LLVM_*` variables select the
optimization, Zig driver, runtime sources and target CPU policy. A ReleaseFast
build that names the LLVM backend and cannot resolve the adapter **fails with a
tool error**; it never silently falls back to QBE. The adapter needs a
`python3` interpreter at build time. Guest units are content-addressed and
cached per function, so a Python process runs only for a unit whose IL actually
changed (see *Concurrent code generation* below).

```console
$ mylang build examples/factorial.my -o /tmp/factorial --cache-dir /tmp/cache --report
{"version":"qbe-build-v1",...,"backend":"llvm","optimization":"3","lto":true,...}
$ mylang build examples/factorial.my --mode Debug -o /tmp/factorial-debug --cache-dir /tmp/cache
$ mylang build examples/factorial.my --backend qbe -o /tmp/factorial-qbe --cache-dir /tmp/cache
```

### What the LLVM backend is allowed to assume

The adapter states no fact that a check the frontend emitted is about to
establish. It emits no `nsw`/`nuw`/`exact`/fast-math flag, no `inbounds`, no
TBAA and no `noalias` pointer attribute, because every overflow, bounds, cast
and allocation check is explicit code in the IL: the emitted sequence computes
the wrapped result and *then* tests it, so an arithmetic flag would make the
test that follows dead.

It does state one aliasing fact, and that fact never depends on a check having
run. Memory an emitted unit touches falls into two classes the adapter can place
without looking at a guard:

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
before the activation returns. So the adapter gives each placed access
`!alias.scope`/`!noalias` saying the two classes never meet. It carries a class
through `copy` and offsetting `add`, and
through a stack slot whose address never leaves the unit — either because every
store to it agrees on one class and one of those stores dominates every load, or,
inside one block, from the last value stored above the load. Everything else is
left unplaced and carries no metadata, which keeps it aliasing both classes the
way every access behaved before. This is what lets a loop keep a container's
length and storage pointer in registers instead of reloading the header on every
element; `MYLANG_QBE_LLVM_ALIAS=0` turns the metadata off for an A/B run.

The `# myl-obj` markers are comment lines of their own. QBE's lexer drops a `#`
comment to end of line, so the QBE backend's assembly is byte-identical with and
without them.

## `mylang build`

`mylang build <file.my> -o <output>` checks the program, lowers it, compiles one
independently cached object per guest function and links those objects with the
bundled runtime. `--run` replaces `-o`: it executes a temporary binary with
inherited stdin, stdout, stderr and working directory, returns that program's
exit status, and removes the binary afterwards while keeping the cached objects;
runtime options go after `--`, including the same `--restrict` and `--allow-*`
capability options `mylang run` takes: a native executable grants every
capability by default and `--restrict` denies them. Build tools resolve from `--qbe`/`--zig` first,
then from executables sitting beside the running `mylang`, then from `PATH`, and
never from the working directory. `amd64_sysv` is the only supported target, a
module entry needs `--project`, `--library` produces a shared library, and a
program using a construct the native backend does not implement fails with
`E_QBE_UNSUPPORTED` before any output is written. `--report` adds one
`qbe-build-v1` JSON line naming every compiled function, its cached object,
whether that object was reused, and the resolved `backend`, `optimization` and
`lto`; `zig build test-qbe-build` repeats the **QBE** builds through a relocated
compiler with no Python on `PATH` using the Zig-native build driver tests (the
driver in those tests passes `--qbe` explicitly, so the release-path adapter is
neither resolved nor needed).

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
`mylang build --mode ReleaseFast` output small and fast. The per-instruction
position marker is kept only where a diagnostic can read it — an instruction that
can fail, an `assert`, or a call site — because that is what trap traces and
`assert` messages read.
Because such a binary cannot honor a ceiling, giving it `--max-steps=` at runtime
reports `R_NO_STEP_ACCOUNTING` and names how to get a bounded run, rather than
silently ignoring the flag. `--max-frames`, `--timeout` and `--max-memory` are
enforced by the runtime and are unaffected.

## Unchecked release builds

`--unchecked` is a release policy for a program already known to be correct: it
tells the emitter to leave out the code that turns an invalid value into a named
trap. On the schematic renderer it is worth about 13% of the render
([the parity audit's strip ladder](../audits/schematic-parity-gap-2026-09-22.md#2-what-safety-costs-the-strip-ladder)
priced the same omissions at 15%), and the program's output is byte-identical.

```console
$ mylang build examples/factorial.my -o /tmp/factorial-unchecked --unchecked --cache-dir /tmp/qbe-cache
$ /tmp/factorial-unchecked
120
```

**What it omits.** Integer-overflow guards on `+`, `-`, `*`, unary `-`;
narrowing integer casts (`u8(...)`, `i32(...)` and friends); index-bounds guards
on lists, fixed arrays, `bytes`, `str` and dictionary position reads
(`key_at`/`value_at`), and the empty-container guard on `pop()`. When the build
also carries no ceiling — the default for a `ReleaseFast` executable — it
additionally omits the per-call frame record, the stack-floor test, the function
metadata store and every instruction-position store.

**What it keeps.** Allocation failure (out of memory still exits 1 with
`R_MEMORY_BUDGET` or `R_ALLOCATION`), the memory budget itself, GC roots and
everything else the collector traces, host-call and capability validation,
`assert`, division by zero and signed `MIN // -1` (both fault the hardware
divider, so removing them would trade a named trap for `SIGFPE`), shift-count
range tests, arena escape checks, dictionary missing-key and list
concurrent-modification errors.

**What is no longer detected.** Under `--unchecked` each of the following is
undefined behaviour rather than a trap, and the program may produce wrong values,
corrupt memory or crash:

| was reported | now |
|---|---|
| `R_INT_OVERFLOW` on add, subtract, multiply, negate | the wrapped or out-of-range 64-bit result is used |
| `R_INT_CAST` narrowing out of range | the un-narrowed value is used |
| `R_LIST_BOUNDS`, `R_ARRAY_BOUNDS`, `R_TEXT_BOUNDS` | memory next to the container is read or written |
| `R_LIST_BOUNDS` from `pop()` on an empty list | an undefined element is produced |
| `R_FRAME_LIMIT` from runaway recursion | the process overruns its stack and takes `SIGSEGV` |
| a trap's source location and call trace | a trap that still fires (out of memory, division by zero) reports no frames and no `assert` message text |

**Where it is refused.** `mylang test --unchecked` is refused by name: a test
asserts that invalid input traps, so there would be nothing left to assert.
`--mode Debug` and `--library` are refused too — a Debug build exists to report
failures, and a library is embedded by hosts (the embed API, the guest-test
runner) that always run their guest under a finite budget.

**What it composes with.** A build that also asked for `--max-steps=N`,
`--max-frames=N` or `--step-accounting` keeps the frame protocol and the
accounting that enforces the ceiling, and gives up only the value guards; that
combination is supported and measured. A build with neither ceiling is the one
that also drops the frame record, and giving such a binary `--max-steps=` at
runtime still reports `R_NO_STEP_ACCOUNTING` rather than ignoring it.

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
(`.mylang-cache/qbe` by default): one object per guest function, one for the
generated typed-metadata unit, and one for the generated entry adapter. Their
keys cover the *native driver* identity, the runtime content hash, the codegen
tool stamp (QBE's stamp, or a content hash of the LLVM adapter package), the
optimization level, whether LTO is on, and the target, so a changed tool, mode,
optimization or backend never reuses an object built by another one. The native driver identity is a
build-time digest over only the sources that decide how already-emitted QBE IL
becomes an object or an executable — the build driver (`src/qbe_build*.zig`) and
the link-argument policy (`src/native_link*.zig`) — plus the Zig version and the
optimize mode. Everything else is keyed separately: the IL text names the object,
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
changes nothing relinks nothing observable: the candidate
and the published executable are compared by length and then by bytes, and an
identical result keeps its inode and modification time, which `--report` shows as
`"output_changed": false`.

An unchanged build goes one step further and **skips the link itself**. The
sidecar beside the executable records a link identity over the object set, the
runtime archive, the artifact kind, the mode, the target and the symbol policy;
when the executable is still present and executable, every cached object and the
runtime archive are still on disk, and the identity matches, the build reuses
the published file without running the linker. The check is deliberately
conservative: a `--provider` or any explicit native link input (`--link`,
`--link-library`, `--library-path`) disables reuse, because such an input can
change without changing a guest object. This is what keeps an unchanged
ReleaseFast rebuild from paying the LTO link again.

A cached object or archive is accepted only when a fingerprint over its length
and contents matches the one stored beside it in a `.digest` file. Damaged bytes
and a damaged fingerprint are both misses, so a corrupt cache repairs the one
entry it lost rather than failing the build or silently linking rubble. Cache
keys stay on SHA-256 because they name small inputs; verification uses the
cheaper fingerprint because a warm build re-reads megabytes of stored objects and
a cryptographic pass over them costs more than the link it protects.

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
**backend flavor**. There are four flavors:

| mode | flavor | codegen |
|---|---|---|
| `Debug` | `qbe` | QBE, `-O0` |
| `ReleaseFast` | `qbe` | QBE, `-O2` |
| `ReleaseFast` | `llvm` | LLVM `-O3` |
| `ReleaseFast` | `llvm-lto` | LLVM `-O3` with `-flto`, so the link sees bitcode |

The flavor is part of the hash, so a QBE archive can never be linked into an
LLVM build and an `-O3` archive can never be linked into an LTO one. `mylang`
finds the directory relative to its own executable, the same way it finds the
sibling `qbe`. The LLVM flavors need the adapter, so `zig build` passes
`--llvm-adapter` to `emit-runtime`; without that flag `emit-runtime` publishes
only the QBE flavors, which keeps a Python-less prebuild working.

A cold `mylang build` computes the hash its runtime needs and, if a matching
archive is installed, links it directly and skips compiling the runtime from
source — `--report` shows `"runtime_installed": true`. This is what makes a
plain `ReleaseFast` build affordable: it links the `llvm-lto` bitcode archive
instead of compiling twenty runtime translation units with LTO itself. The
prebuilt hash excludes the Zig and QBE tool file stamps that object-cache keys
carry, so an installed archive still matches a build that resolved those tools
from a different path. A missing archive (a cross-target build, or a relocated
compiler with no `lib` beside it), a mode with no matching install, or a
corrupted file whose fingerprint no longer matches the `.digest` published
beside it all fall back cleanly to compiling the runtime from source.

## Concurrent code generation

The LLVM adapter is one Python process per guest unit, and on a closure of a
hundred functions that process start-up and translation dominated a cold build.
Each unit is still its own content-addressed object and a cache hit still runs
no tool, but the driver now stages every missing unit first, starts them in
**concurrent waves** (up to eight, or the machine's core count), and publishes
each object as its wave finishes. Before the waves it makes one
`--signatures-only` adapter pass over the whole closure, which fills the
per-build call-site signature sidecar: a unit translated concurrently cannot
rely on its callees having run first, so the table is made complete up front and
every unit declares its callees exactly as a sequential build would. The native
QBE arm keeps its sequential loop. A wave reports the first tool failure only
after reaping every child it started, so a failed build leaves no process
behind.

Measured on the [S-expression parser](../../experiments/sexpr-port/main.my)
(101 functions, 1 MiB input), cold wall clock before this work was 12.7 s for
LLVM against 3.2 s for QBE; it is now about equal: roughly 4.1 s each, with
QBE's time unchanged. An unchanged rebuild is about 1.0 s on either arm: the
per-function object cache makes codegen a hit, and an unchanged build whose
published executable still matches every input **reuses it without relinking**
(see *Object cache and link*). Relinking after a one-function edit costs the
LTO link, about a second on the LLVM arm and milliseconds on QBE.

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
