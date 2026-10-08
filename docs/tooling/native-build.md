# Native builds

`mylang build` turns a checked program into a Linux x86-64 executable. `mylang run`,
`run-project`, `build --run`, `test` and `doctest` are the same build followed by
running the result. The compiler drives every step itself; the only external tool is
the Zig toolchain's bundled clang (`zig cc`), so building and using mylang needs the
pinned Zig and nothing else. For when to build `--release`, what the checks cost and
how to measure, see the [performance page](../performance.md); for the stores a
build keeps, see [the caches](#the-caches) below.

## How a build works

1. **Check.** The front end loads the entry and every module it imports, checks
   them and reuses the checked bodies it already has ([compiler caches](caches.md)).
   An error stops here with status 1.
2. **Core IR.** The checked program becomes Core IR (`src/core/build*.zig`): one
   function per program function, generic instance and generated adapter. A
   construct the front end accepts but the core cannot build yet stops with
   `E_CORE_UNSUPPORTED` naming it.
3. **Passes.** A release build computes facts (integer ranges, lengths, ownership),
   inlines, unswitches and versions loops, and removes the checks the facts prove
   cannot fire. A debug build keeps every check and runs no optimizing pass.
4. **LLVM text.** The IR is emitted as LLVM units (`src/core/emit_*.zig`).
5. **Compile and link.** Each unit the object store does not already hold is
   compiled with `zig cc -c`, in parallel; the objects are linked with the core C
   runtime (`src/core/runtime/*.c`, compiled once per machine at `-O2`) and any
   `--link` C sources into one executable.

There is no interpreter, no bytecode and no second back end. Memory is managed by
one-count reference counting with copy-on-write: collections and records are values,
and nothing is collected or traced.

## Debug and release builds

A build is a **debug** build unless `--release` (or `--mode ReleaseFast`) asks for
the optimized one. The two differ in how the program is cut into units:

- **Debug** emits one unit per source module, plus one per generic instance, one per
  generated adapter and the entry unit. A unit's text depends only on its own
  functions and the facts they consume, so an edit recompiles only the units whose
  text changed, and two modules using one `sort[Record]` share one object. This is
  the edit loop: `run`, `test` and `build` without `--release`.
- **Release** emits the whole program as one unit, so LLVM inlines and optimizes
  across every module boundary. Its object is cached by its text like any unit, so
  an unchanged release build compiles nothing, but any edit recompiles the whole
  program. Use it for a binary you ship or time.

```console
$ mylang build app/main.my -o app --cache-report
mylang-core: cache: 3 units, 1 reused, 2 compiled, 0 verified; program linked; 3 processes
$ mylang build app/main.my -o app-fast --release --cache-report
mylang-core: cache: 1 units, 0 reused, 1 compiled, 0 verified; program linked; 2 processes
```

Both modes keep every check the program can reach (see
[checks in every build](#checks-in-every-build)), report traps identically and give
the same output. `mylang test --release` runs a suite on release builds;
`--verify-facts` (release) also checks at run time every fact the passes relied on
and traps `R_CORE_FACT` if one does not hold, and `--no-facts` turns the fact pass
off to measure what it buys.

## `mylang build`

```bash
mylang build FILE.my -o OUT [--release] [--link FILE.c]... [--emit-llvm PATH]
             [--cache-dir DIR] [--no-cache] [--zig PATH]
             [--report | --cache-report] [--verify-cache] [--stats]
             [--diagnostics=text|json] [--no-facts | --verify-facts]
mylang build FILE.my --run [run options] [-- ARGS...]
```

- **The entry** is a single file or a project entry: a module header or an import
  makes it a project, and the nearest `mylang.json` supplies its import policy,
  limits and roots. `--project` and `--whole-program` are accepted for old scripts
  and ask for nothing more.
- **`-o OUT`** writes the executable. A failed build leaves an existing `OUT`
  untouched.
- **`--run`** replaces `-o`: the program is built into a private directory, run with
  `mylang run`'s options and exit status, and removed afterwards; every value after
  `--` is the program's.
- **`--link FILE.c`** (repeatable) compiles a C source and links it in; see
  [direct C imports](../c-ffi.md).
- **`--emit-llvm PATH`** also writes the emitted LLVM text. Such a build is neither
  replayed nor recorded.
- **`--diagnostics=json`** prints warnings, errors, refusals and (with `--run`) a
  trap as `diagnostic-v1` records on stderr.
- **`--zig PATH`** names the toolchain; see [toolchain](#toolchain).

The status is 0 for a built program, 1 for a check error or an `E_CORE_UNSUPPORTED`
refusal, 2 for a usage, configuration or tool failure, and 3 when the project's
import policy denies an import.

```console
$ mylang build examples/factorial.my -o /tmp/factorial
$ /tmp/factorial; echo $?
120
$ mylang build examples/factorial.my --run; echo $?
120
```

## Running a built program

A built executable hands `main(args)` every argument after `argv[0]` unchanged,
grants every capability, and exits with `main`'s value `& 0xFF` (1 on a trap). Its
runtime options come only from the `MYLANG_OPTIONS` environment variable, spelled
as on the `mylang run` command line and separated by spaces:
`MYLANG_OPTIONS=--restrict ./app` denies every capability, and
`MYLANG_OPTIONS=--print-result ./app` prints `main`'s value at exit. See
[the native backend](../io.md#the-native-backend) for quoting and errors.

`mylang run` builds the same executable with its budgets compiled into `main`:
`--max-steps`, `--max-frames`, `--timeout` and `--max-memory`, described in
[runtime budgets](runtime-budgets.md#instruction-and-frame-budgets). A program
built with `mylang build -o` carries no step, frame or byte budget and pays nothing
for one.

## Checks in every build

Every build keeps the language's value guards: integer overflow on `+`, `-`, `*`
and unary `-`, narrowing integer casts, division by zero, index bounds on lists,
fixed arrays, `bytes`, `str` and dictionary position reads, and `pop()` of an empty
list. That holds for debug and release builds and for `run`, `build --run` and
`test`. A would-be trap is always reported, never undefined behaviour, and
optimization never changes a program's result. A release build leaves a guard out
only where its facts prove it cannot fire, such as a cast whose source range fits
its target or the accesses of a loop whose bounds are known; `--verify-facts` keeps
those guards and checks the facts instead.

The former `--unchecked` policy, which omitted the guards, is refused with a usage
error (exit 2) that says so.

## Trap reports

A trap prints its source position, code, message and call trace, innermost first,
on stderr, and the program exits 1:

```console
$ mylang run trap.my
trap.my:2:12: error[R_LIST_BOUNDS]: native execution failed (index 5, length 3)
  in pick at trap.my:2:12
  in main at trap.my:6:12
```

The text is the same in debug and release builds, including for a function LLVM
inlined. The runtime finds the frames from the program's line tables when the trap
fires; a call does no bookkeeping for it. The runtime also writes one
machine-readable `MYLANG-TRAP` record after the text, which `mylang run` hides and
`--diagnostics=json` turns into the `trap_detail` of a `diagnostic-v1` record
([runtime diagnostics](../io.md#runtime-diagnostics)).

## The caches

A build keeps two kinds of store. Every key is a BLAKE3 digest over the complete
input of what it names, so a hit cannot serve a wrong object, and a damaged entry is
recompiled rather than used.

**The per-user object store** is shared by every project, worktree and temporary
test directory of one user: `MYLANG_CORE_RUNTIME_CACHE`, else
`$XDG_CACHE_HOME/mylang/core-runtime`, else `~/.cache/mylang/core-runtime`.

| Entry | Keyed by |
|---|---|
| `units-v1/<key>.o` and `<key>.sum` | the unit's exact LLVM text, debug or release, target triple and CPU, toolchain identity, runtime source and store format |
| `core_rt-<key>.o` | the runtime's C source, settings and toolchain |
| `core_number_text-<key>.o` | the number-printing runtime, which ships prebuilt inside the compiler |

A hit starts no process and is served only when the object's bytes match its `.sum`
record. A miss compiles beside its entry and is renamed into place. An empty
`MYLANG_CORE_RUNTIME_CACHE`, no usable home directory or an unproved toolchain keeps
the objects in the build's own work directory instead.

**The work directory** is `--cache-dir DIR`, else `.mylang-cache/core` under the
current directory:

| Directory | Holds |
|---|---|
| `frontend/`, `semantic/` | the front end's parsed modules, verdicts and checked bodies ([compiler caches](caches.md)) |
| `programs-v1/` | linked executables, keyed by every linked object's bytes and the link settings; a build whose objects all match copies the program and links nothing |
| `foreign-v1/` | `--link` C objects with the headers their depfile listed; one is served only while the source and every listed header keep their bytes |
| `replay-v1/` | one replay record per entry and settings (below) |
| `tests/receipts-v2/`, `tests/manifests-v2/` | `mylang test` result receipts ([guest tests](guest-tests.md#reusing-unaffected-results)) |

**Replay.** A build records every file it read — each module source, embedded file,
generated interface file, `--link` source and depfile header — with the digest of
the bytes it used, under a key of the compiler's identity, the flags, the working
directory, the entry and its configuration, the toolchain and the environment
(except the shell's `_`, `SHLVL` and `OLDPWD`). The next identical build rereads and
rehashes those files, revalidates the toolchain and copies the recorded program
without checking, lowering or starting a process.

Every `zig` process gets a fresh private cache inside a staging directory that the
build removes, so Zig's own cache keeps no second copy of objects or programs.
`scripts/prune-caches.sh` evicts the per-user store (by last read, then to a size
cap) and each worktree's `programs-v1`, `foreign-v1` and `replay-v1`.

## Reports

- **`--report`** (on `build`, `build --run`, `run` and `run-project`) prints one
  `cache-report-v1` JSON line on stderr: the units linked, served by the object
  store, compiled and verified, the tool processes started, and whether the program
  was `linked`, `reused` from the program store or `replayed` (every count 0).
- **`--cache-report`** prints the same as one `mylang-core: cache:` text line.
- **`--stats`** prints what the release passes did: calls inlined, loops unswitched,
  versioned and vectorized, checks proved, and the ownership plan's in-place
  updates, copies, retains and releases.
- **`--timings`** on `run`, `run-project` and `build --run` prints
  `timings: native_ns=N`, the program's own run time with the build excluded.
- **`mylang dump-ir FILE.my [--facts]`** prints the Core IR (with `--facts`, after
  the release passes, with their intervals); `--emit-llvm PATH` writes the LLVM text.

After a one-line edit to one module of a three-unit program, and again unchanged:

```console
$ mylang build app/main.my -o app --report
{"version":"cache-report-v1","program":"linked","units":3,"reused":2,"compiled":1,"verified":0,"processes":2}
$ mylang build app/main.my -o app --report
{"version":"cache-report-v1","program":"replayed","units":0,"reused":0,"compiled":0,"verified":0,"processes":0}
```

The old back end's `qbe-build-v1` and `work-report-v1` build reports, its
`--timings=json` phase profile and `--explain-invalidation` are refused on `build`,
`run` and `test`. The front-end commands (`check`, `check-project`) still print
`frontend-cache-v1`, `work-report-v1` and `invalidation-report-v1`
([work report](work-report.md#compiler-work-and-reuse-report)).

## `--verify-cache` and `--no-cache`

**`--verify-cache`** recompiles every unit the object store served and fails the
build, naming the unit, when a fresh object's bytes differ from the cached one. It
never replays. Use it when you suspect the store, or after changing the emitter.

**`--no-cache`** (on `build`, `build --run`, `run`, `run-project` and `test`) builds
through an empty private cache that is removed when the command ends: nothing is
read from or published to the replay, program, foreign-object, front-end or
test-receipt stores. The per-user object store is still used. Status, output and
diagnostics are those of the same command with caches.

```console
$ mylang build app/main.my -o app --verify-cache --cache-report
mylang-core: cache: 3 units, 3 reused, 0 compiled, 3 verified; program reused; 3 processes
$ mylang run app/main.my --no-cache
```

## Toolchain

The guest toolchain is `--zig PATH`, else `ZIG`, else `MYLANG_ZIG`, else `zig` on
`PATH`. A build's toolchain identity covers the `zig` executable's content, each
library root's own generation, the runtime and discovery inputs and the native CPU,
and it is part of every key. A library tree is reviewed once against the pinned,
approved Zig distribution and the answer is memoized under
`~/.cache/mylang/core-tools-v1`. A toolchain that cannot be proved to be that
distribution still builds, but its objects stay in the build's private directory and
nothing is cached or replayed. The target is `amd64` Linux (SysV) with the host
CPU's features.

## Where to look when a build is slow

- **Every build compiles.** Run it twice with `--report`. An unchanged build says
  `"program":"replayed"`. If it does not, something the build reads changes between
  runs: a generated file, an embedded asset, the environment, or a `--link` source
  whose header changed while it compiled.
- **An edit compiles many units.** A debug build recompiles each unit whose text
  changed: the edited module's, plus any unit that inlined a changed public helper.
  A release build always recompiles the whole program, so iterate in debug.
- **The first build on a machine.** Zig builds its C library stubs once per toolchain
  and the core runtime object is compiled once per user; later projects reuse both.
  A fresh `MYLANG_CORE_RUNTIME_CACHE` pays this again.
- **Checking dominates.** A large project's check is the front end's cost;
  `mylang check FILE.my --report` shows what it reused ([compiler caches](caches.md)).
- **Tests are slow.** Each test file builds its own program; see
  [guest tests](guest-tests.md#reusing-unaffected-results) for receipts and `--jobs`.

## Retired build controls

The QBE back end, its bytecode IR and the QBE-to-LLVM translator were removed in
stage S5 of the new compiler core (2026-10), with the tracing collector, two-count
reference counting, arenas and host functions. These are refused with status 2 and
a one-line reason: `--backend`, `--llvm-opt`, `--lto`, `--target`, `--keep-symbols`,
`--step-accounting`, `--gc-runtime`, `--gc-stress`, `--rc-runtime`,
`--legacy-sharing`, `--value-semantics`, `--library`, `--provider`,
`--link-library`, `--library-path`, `--explain-ownership` (use `--stats`), and the
commands `emit-qbe`, `emit-project-qbe`, `emit-runtime`, `dump-bytecode` (use
`dump-ir`), `compile-module`, `link-modules` and `invoke`. `--qbe PATH` is accepted
and ignored.
