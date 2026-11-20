# Native builds: how it works

Implementation detail and measurements moved out of the user guide, [docs/tooling/native-build.md](../tooling/native-build.md). Each section keeps the heading of the guide section it came from.

## How a build works

1. **Check.** The front end loads the entry and every module it imports, checks
   them and reuses the checked bodies it already has (compiler caches).
   An error stops here with status 1.
2. **Core IR.** The checked program becomes Core IR (`src/core/build*.zig`): one
   function per program function, generic instance and generated adapter. A
   construct the front end accepts but the core cannot build yet stops with
   `E_CORE_UNSUPPORTED` naming it.
3. **Passes.** The debug builds other than `--unoptimized`, and release, compute facts (integer ranges, lengths, ownership),
   inlines, unswitches and versions loops, and removes the checks the facts prove
   cannot fire. An `--unoptimized` build keeps every check and runs no optimizing pass.
4. **LLVM text.** The IR is emitted as LLVM units (`src/core/emit_*.zig`).
5. **Compile and link.** Each unit the object store does not already hold is
   compiled with `zig cc -c`, in parallel; the objects are linked with the core C
   runtime (`src/core/runtime/*.c`, compiled once per machine at `-O2`) and any
   `--link` C sources into one executable.

## Debug and release builds

- **Lean debug** (the default for `run`, `run-project`, `build` and `build --run`) runs
  the Core optimization passes, then compiles each module unit with LLVM's IR passes off
  (on for a unit of at most 50,000 bytes of LLVM text) and its code generation at `-O2`,
  less six switches that cost compile time and no run
  time (see [debug code generation](../tooling/native-build.md#debug-code-generation)). It keeps module units, so
  an edit recompiles the units whose emitted text changed, and it retains `debug(...)`
  output and source locations in trap traces. Generic instances, generated adapters and
  the entry have their own units. The program runs 1.2 to 1.3 times as long as the same
  program built with `--release` (an `-O0` build takes 1.7 to 2.8 times), for 1.0 to
  1.6 times the compile CPU of an `-O0` build.

The debug builds keep the always-inline helpers ordinary (LLVM decides where they
inline, and the lean build's LLVM does not inline at all); release keeps `alwaysinline`.
The unit and program keys carry the mode's name and the whole `zig cc` argument list it
compiles with, so the modes never share an object, and a change to the lean list
(`src/core/build_mode.zig`) moves every key made under it.

### Debug code generation

The lean build is the only change to what `zig cc` is asked for: each LLVM unit is compiled with

```text
-O2 -Xclang -disable-llvm-passes
-mllvm -experimental-debug-variable-locations=false
-mllvm -enable-misched=false -mllvm -disable-copyprop -mllvm -disable-lsr
-mllvm -disable-machine-cse -mllvm -disable-machine-licm
-mllvm -enable-ipra
```

in place of `-O0`. `-Xclang -disable-llvm-passes` keeps LLVM's IR passes off, so a unit keeps the shape
Core's passes gave it and its trap sites keep their lines; `-O2` then runs the instruction selector, the
optimizing register allocator and the machine passes, which is where `-O0` loses most of its speed. The six
switches turn off the passes that cost compile time and bought no run time on the measured programs: the
instruction-reference variable-location analysis (every function has a line-table subprogram, although the IR
has no variable debug info), the machine instruction scheduler, copy propagation, loop strength reduction,
machine CSE and machine LICM. The seventh switch, `-enable-ipra` (interprocedural register allocation, off by
default in LLVM), lets a caller keep values in the registers a callee in the same unit does not touch, instead of
saving them around the call: on the EDA port it ran 3.5% fewer instructions and about 2% fewer cycles at the same
LLVM compile work (lane DBG-IPRA, 18 November 2026). A bare target (`--target thumbv6m-none`) compiles with its own
flags and never gets it. No function is marked `optnone`. The link, the `--link` C sources and the runtime
are compiled as before. The emitted LLVM text is the `-O0` build's, byte for byte, and a trap reports the same
text and source lines in both.

**Small units get LLVM's passes.** A unit whose LLVM text is at most 50,000 bytes is compiled with the same list
without `-Xclang -disable-llvm-passes`: LLVM's own `-O2` pipeline (inlining, SROA, GVN, the loop and vector passes) runs
on it first, then the machine switches above. A larger unit keeps the list above. The cut is the unit's text, so
a module that grows past 50,000 bytes changes its list, and the units of the EDA port that stay below it are 374
of 535 and 8.3% of its 69.7 MB of LLVM text. It is the plain debug build's rule (and `--debug-lean`'s) and has no
option: `--debug-o0`, `--optimize-debug`, `--unoptimized`, `--release`, `selka test`'s default and a bare target compile as
before. Lane DBG-CAP measured caps of 50, 100, 200 and 400 KB (18 November 2026); 50 KB is the one where a point of build
time buys three or more points of run time on edits and on programs of small units (the port's cold build gets less than
that). Together with `-enable-ipra`, against the lean build before both: the benchmark programs of `bench/parity`
(29 programs, all with small units) run 17.6% less CPU time and the port's own cases 3.9% less (`-enable-ipra` alone: 1.2% and
1.8%); a cold build of the port costs
2.9% more CPU time (every unit is compiled once, and the big ones are not touched), and an edit, which recompiles one unit, 0
to 1.2% more instructions. A cap of 100 KB bought 0.4% more run time for 3% more cold build, and 200 KB costs 24% more cold
build for 8%. The debug line table keeps 96.6% of the (file, line) pairs the `--debug-o0` build has on the port, against
97.3% without them: inlined code and merged blocks lose rows, and a trap's text, exit status and call chain are unchanged
(they come from the trap site's own record). When the build, or the lines of a debugger, matter more than the run, `--debug-o0`
is the way back. Every lean store key spells both lists and the cap, so objects compiled before the rule are never served to it.

`--debug-o0` and `--debug-lean` are build modes like `--release`: two different modes on one command line are
refused, in either order, and a repeat is allowed. A build in one mode never serves or replays another mode's
objects, programs or test results, and `selka test DIR` passes `--release`, `--unoptimized`, `--optimize-debug` and
`--debug-lean` to the children it starts (a child's own default is `-O0`). On the 99k-line port the lean build
costs a typical edit the same CPU as `-O0` (0.34 s against 0.33 s), the edit of the largest module 2.2 s against
1.5 s, and a cold build 29.6 s against 18.9 s; use `--debug-o0` when the build, not the run, is what you wait for.

```console
$ selka build app/main.selka -o app --cache-report
selka-core: cache: 3 units, 1 reused, 2 compiled, 0 verified; program linked; 3 processes
$ selka build app/main.selka -o app-fast --release --cache-report
selka-core: cache: 1 units, 0 reused, 1 compiled, 0 verified; program linked; 2 processes
```

### Effective optimization levels

Compiling the identical Release-generated LLVM for each of the six parity
benchmarks with requested `-O2` and `-O3`, then linking the same runtime objects,
produced byte-identical executable `.text` sections in every case. All outputs
matched the expected files. Thus the current `-O3` spelling provides no additional
optimization; Release still enables whole-program LLVM optimization and omits
the output of `debug(...)` lines from standalone builds (their arguments are still evaluated). Recheck the mapping after a toolchain upgrade.

Driver commands, effective flags and code hashes (`bench/parity/optimization_driver_20261009.json`)
are checked in. Reproduce with the pinned Zig, GNU `objcopy` and a new directory:

```bash
python3 scripts/qualify_optimization_driver.py --compiler zig-out/bin/selka \
  --output /tmp/optimization-driver-qualification
```

## Building for another CPU: `--target`

A `thumbv6m-none` build checks the program and compiles every unit with
`zig cc -target thumb-freestanding-eabi -mcpu=cortex_m0plus -Os -ffunction-sections -fdata-sections`: loops stay scalar
(no vector plans), `memchr` and `memcmp` take 32-bit sizes, and functions carry no unwind tables, though they keep their
DWARF line metadata for a debugger. In a program that starts [the second core](../tooling/native-build.md#the-second-core-registersstart_core1),
the allocator's free lists are the calling core's own: each inline fast path asks the runtime's `__emutls_get_address`
for them.

The build then links an ELF image with the bare runtime, `--link PLATFORM.c` and `--linker-script SCRIPT.ld`:

- The runtime is two C units embedded in the compiler (a build never reads the source tree): the hosted runtime's files
  that need no operating system, then `bare/core_bare_heap.c`, `bare/core_bare.c` and `bare/core_bare_cores.c`, as one
  unit compiled with `-DMYL_BARE` and the stand-in C headers of `bare/include` first on its include path; and
  `bare/core_bare_link.c`. The runtime has two optional flavours, each chosen by the build from what the program's units
  hold: one whose units call `registers.start_core1` gets the two-core runtime (the main unit also takes
  `-DMYL_BARE_CORES` and `-femulated-tls`: each core's heap, state and the locked log), and one that holds a
  freestanding fault site (a failed check of a `@freestanding` function, `udf #83` in the text) gets the fault decoder
  (`-DMYL_BARE_FREESTANDING`: the fault handler that names the code and place of a freestanding fault, with its table of
  code names, about 560 bytes). A program with neither gets the runtime of a compiler without them, byte for byte: the
  plain fault handler (`R_BARE_FAULT`), the same code bytes. A program with both gets both. Their objects are cached in the per-user
  runtime directory under a key of the target, the build's whole-image flags, every compile argument (the flavour's
  among them), the toolchain and their bytes; the host's runtime object and its key are untouched.
- The platform's C file, given with `--link` and compiled for the target like any `--link` source, supplies
  `myl_bare_write`, `myl_bare_exit` and, if it wants, `myl_bare_platform_start`. `scripts/bare/qemu/platform.c` and
  `scripts/bare/qemu/link.ld` are the ones for QEMU's mps2-an385 board.
- The link takes `--gc-sections`, the entry `myl_bare_reset`, no C start files and no C library (Zig's own
  compiler-rt), and the linker script; the program key holds the script's bytes. A bare build is never replayed.
- `--release` adds `-flto` to every compile and to the link: one whole-image optimisation across the program,
  `bare/core_bare_link.c` and the platform file. In the two-core flavour the runtime's main unit stays machine code
  (`-fno-lto` after it): link-time code generation would lower its thread-local variables to native TLS, which a bare
  image has no segment for. A plain build does not.

### The second core: `registers.start_core1`

`E_TARGET_DEVICE_REGISTERS`, which names the function. A program that calls it links the two-core flavour of the
runtime, which is what the rest of this section describes, with no flag; a program that does not pays nothing for it
(its image is the one-core runtime's: in `--release`, 1,328 code bytes for a `main` that returns 0, where the two-core
flavour takes 3,104).

- **What the cores share.** No heap value: each core allocates and frees in its own arena
  (`bare/core_bare_heap.c`, chosen by the core's number, the SIO CPUID register on the RP2040), and every piece of the
  runtime's state that the hosted runtime keeps per thread or shares between threads (the free lists, the live-block
  count, the byte ceiling, the output buffers, a trap's detail) is a thread-local variable with one copy per core,
  made in that core's heap the first time the core touches it (emulated TLS, `__emutls_get_address` in
  `bare/core_bare_cores.c`). The cores talk through the hardware: the SIO FIFOs and spinlocks (the `rp2040` package's
  `rp2040.sio` module in selka-rp) or a memory window both reach through `Registers`. A `once` of the runtime runs once
  on either core.

- **A trap or a fault** on either core ends the program on both, and the platform's `myl_bare_exit` runs once: a core
  that reaches the end second waits to be stopped. A trap on core 1 writes its lines (each beginning `core 1: `), then
  `core 1: the program ends here`, and keeps the log, so core 0 writes nothing more; core 0 runs at most until the
  platform's exit resets the chip (the RP2040's platform does not force core 0 off: the power-on state machine's
  FRCE_OFF register is not reset by the watchdog, so a core 0 held off would stay off through the reset into the
  bootloader).
- **The platform's hooks** (weak defaults describe one core): `myl_bare_core_register` (the address that reads the
  calling core's number), `myl_bare_core1_launch(vectors, stack_top, entry)` (the boot ROM's launch sequence over the
  SIO FIFO, datasheet 2.8.2), `myl_bare_core_stop(core)`, and `myl_bare_lock(n)` and `myl_bare_unlock(n)` for the
  runtime's two locks. `bringup/selka-ram/platform.c` and `bringup/selka-flash/platform.c` in selka-rp give them, with
  hardware spinlocks 30 and 31; QEMU's platform gives none, so `start_core1` answers `False` there
  (`test/bare/core1_one_core.selka`).
- **The entry's calling convention.** The runtime calls `entry` through a C function pointer; the compiler's internal
  functions use LLVM's `fastcc`, which on an AAPCS target without VFP registers (the Cortex-M0+) is AAPCS itself.

### A device described by its memory (MCU-NOC4A)

- **`boot`**: the name of a boot stage: `"rp2040-read-03h"` (the 256 bytes the RP2040's ROM loads first, serial read command 03h). The
  compiler seals it with its CRC-32/MPEG-2 (the bytes `tools/boot2.py seal` makes) and writes it as a `.boot2` section at the start of
  the code's region, so the ELF a debug probe loads and the `.bin` and `.uf2` made from it are bootable; the vector table follows at
  origin + 0x100. An unknown name is refused with the known ones.

- **`hooks`**: `{"start": "board.start", "write": "board.write", "exit": "board.exit"}` binds the runtime's platform hooks (`start`,
  `write`, `exit`, and the second core's `core_register`, `core1_launch`, `core_stop`, `lock` and `unlock`) to `MODULE.FUNCTION` of
  the program, a module it imports. Each is a `@freestanding` function whose first parameter is `Registers` (the hook holds no
  authority it was not handed): `start(reg)`, `write(reg, stream: int, address: u32, length: u32)` (the buffer is read through
  `registers.read8(reg, address + i)`), `exit(reg, status: int)` (it must not return; a return halts), `core_register(reg) -> u32`,
  `core1_launch(reg, vectors: u32, stack_top: u32, entry: u32) -> bool`, `core_stop(reg, core: int)`, `lock(reg, n: int)` and
  `unlock(reg, n: int)`. Any of the eight may take `host: Host` as its **second** parameter, after `reg` and before its own
  (`exit(reg, host, status: int)`), so it can call C: a boot ROM routine through an `@address extern func`, which the RP2040 board's
  `exit` hook needs to end in the USB bootloader. The C-ABI function the compiler writes passes the `Host` token that `main(host: Host)`
  gets (the runtime's grant, which a device gives unconditionally); a hook without `host` is built as before. A `Host` in any other
  place, or a second one, is the wrong signature. The compiler writes a C-ABI function named as the runtime's hook symbol that
  calls the hook, so a C file that defines the same symbol fails at the link. A hook that is missing (its module not imported, or no
  such function), not `@freestanding`, of another signature (the message shows both accepted forms, with and without `host`), or
  bound twice is refused with `E_DEVICE_HOOK`, one line naming the device, the hook and the function.
  `test/target_cli_test.zig` runs a hooks project whose `start`, `write` and `exit` take `host` on QEMU, plain and `--release`: the
  `exit` hook reaches a C function of a `--link` file through an address it computes.

`selka build prog.selka -o prog.uf2 --device flash` writes the whole flash image, boot stage included, and `scripts/bare/` runs the QEMU one
(`test/target_cli_test.zig` has `board.selka`: UART0 for `write`, a reset through the system control block for `exit`).

### C interop on a device

`debug(...)` writes through the platform's `myl_bare_write` (stream 2) in a plain build, as `--release` drops it on every
target: the bare runtime defines the function a `debug` line calls, `myl_core_span_stream_write`, as a weak symbol, so a
platform file that still carries its own definition keeps linking and its definition is the one used.
`test/bare/extern_host.selka` and `test/bare/extern_registers.selka` (each with `# bare-link: extern_host.c`, which
`scripts/bare/bare_run.py` adds as a `--link`) run on QEMU, plain and `--release`.

`test/bare/extern_address.selka` (with `# bare-link: extern_address.c`) calls a C function through its address with four
scalars, two of them on the stack, on QEMU, plain and `--release`.

## A program for machines other than this one: `--cpu`

The two Selka components (`libexec/selka/components`) are always built with `--cpu=x86-64-v3`, by a plain `zig build` and
by `zig build release` alike: the bundle ships them, and a bundle built on a runner with AVX-512 must not hold
instructions an ordinary AVX2 desktop faults on. Their receipts name the model, not the builder's `/proc/cpuinfo`. The
compiler itself is a separate matter: `zig build -Dcpu=MODEL` builds it for another CPU (the release workflow passes
`x86_64_v3`).

## Native compile memory

The native stage compiles each unit the object store does not hold with `zig cc -c`,
in parallel, and admits a compile when its estimated memory fits beside the compiles
already running. The estimate is 64 MiB per process plus 64 bytes for each byte of the
unit's LLVM text. The budget is at most one GiB and at most a quarter of the memory
available (`workerBudget` in `src/core/stage_metrics.zig`), so a small machine keeps
its headroom. A compile starts as soon as it fits, longest unit first; the scheduler
never waits for a whole batch to finish. A single unit whose estimate exceeds the
budget still runs, alone. The estimate is a reservation, not a measured peak: a
compile's resident memory is far below it, so the budget bounds concurrency rather
than predicting the process tree's RSS.

### Ending a run

`selka run`, `run-project`, `build --run` and `selka packages build --command run-project` wait for the program they
start, and the program ends with them. A SIGTERM, SIGINT or SIGHUP that reaches the compiler process alone (a
supervisor's `kill PID`, a timeout command) is passed on to the program while the compiler waits; the compiler then ends
by the signal that ended the program, so a shell reports 128 plus it as before, and a program that exits keeps its own
status. A signal the terminal sent (Ctrl-C, a hang-up) already reached the program through the shared process group and
is not sent twice, and a signal that was ignored when the command started stays ignored (a `nohup selka run` keeps its
SIGHUP ignored, and the program inherits that). A compiler that cannot pass anything on (SIGKILL, a crash) still takes the
program with it: the program asks the kernel for a SIGKILL when the thread that started it ends
(`prctl(PR_SET_PDEATHSIG)` before `execve`, with the check that the parent is still the one that started it, as the
runtime does for the programs a guest starts), and `selka test` starts its test programs and its directory children the
same way, so their forked trials follow. While the program is still being built there is nothing to pass on: a signal ends
the build as it always did. A program that does not declare a `Stop` does not hear the signal: it dies of it by the
system's default. One that does ([hearing a stop](../io.md#hearing-a-stop)) hears it as `process.stop_requested`, says
its goodbye and exits with its own status, which the compiler then exits with. The copy `selka run` passes on is
marked with the sender it heard (`rt_sigqueueinfo`, `SI_QUEUE`), so when one signal reaches both the compiler and the
program (a group kill, a service manager that signals every process), the program counts one stop, not two. Once the
program has ended, a signal that reaches the compiler (the second half of `timeout`'s signal to the compiler and then its
group, or the first half handled late) is recorded and ignored, so the compiler exits with the program's own status, or
by the program's fatal signal when it was sent that signal too.

## Warnings in the output

A project that has warnings gets them on every `check`, `build`, `run` and `test`, replays included, and a long-lived
one printed hundreds of lines about code nobody had touched (215 warnings, 645 lines, for the G3 port, every time). The
default output keeps the diagnostics whole and the text short: a warning is printed in full unless its module is

printed nor counted in the closing line. `check`, `check-project`, `check-module` and `lint` print them, and `--warnings`,
`SELKA_WARNINGS=all` and `--diagnostics=json` bring them back to a build. The policy lives in `src/wiring/warning_display.zig`; the findings it counts are the same ones `selka lint` and
`--diagnostics=json` list.

## Certificate validators

The ownership pass and the release fact analysis each write down what they relied on, and a
validator that shares no code with them checks that record against the final IR before the
function is emitted. A program never sees a validator unless it rejects; a rejection is an
internal compiler error, never a diagnostic about the program. The Lean proofs behind the
validators (`proofs/ownership`, `proofs/facts`, `proofs/arith`) are developer and gate tools,
never part of building or using selka, and `zig build test` runs them only with `-Dproofs=true`
(without the flag their four steps print that they were skipped and need no Lean; see
`docs/tooling/test-layout.md`).

**The union-tag rule counts in builds and refuses in the gate.** The IR verifier checks that every `union_payload k` and
`union_take k` reads a value whose tag the facts on the paths to it confine to case `k` (a test of the tag, the equality of
two tags, a `union_make` of the case, followed through a field read twice, a field stored and read back, and a `phi` of such
values). A build's verifier counts a read it cannot justify and refuses nothing, and a plain build prints nothing about it;
`--stats` prints the count. The gate's `verify-ir-proof` action refuses every such read outside shape M (a `list_get` value
read under a test of the element's tag, at most 10 in the corpus) over the language suites, the C interop programs and a
pinned real program (`test/fixtures/verify-ir-proof/protobuf-addressbook/`), through `selka verify-ir` and its Lean copy,
whose lemma (`VerifyIr.payload_of_verdict`) is about that refusing rule.

**The construct-read rule counts in builds and refuses in the gate** (lane VAL, after lane FX6's double free of a
dictionary's keys). The ownership validator asks of every constructor whose result is owned or `emptied`, and that is
not a lend, where each borrowed operand it reads lives: in owners the constructor consumes (or slots of them), or, for an
owned result, in an operand it lists as a loan among its parents and that the certificate marks a view (`views`, format
`ownership-certificate-v2`: a slot type its destruction leaves alone, such as a span or a list view). Anything else (a borrow rooted in the caller, in an owner
the constructor does not take, or with no recorded root) means the aggregate would destroy, or an owned take out of it
would hand out, storage it never received. A build's validator counts such a constructor and accepts the function
(`validate_ownership.build_mode`); `--stats` prints the count over the functions the build validated (a body served from
a record was counted by the build that made it). `selka validate-certificates`, `selka dump-ir --certificate --validate`
and the Lean checker refuse it (`reject J6`, tag `construct-read`), so the gate's `ownership-proof` action refuses every
such plan of the language suites, its mutants and its fixtures. Builds refuse too (`E_OWNERSHIP_VALIDATION`) once the
counts have stayed at zero for the period the coordinator sets: that is the one value `build_mode = .refuse`.

```console
$ selka build prog.selka -o prog --stats
selka: construct-reads: 0 constructors read a borrow they neither own nor lend (counted in builds, refused by the gate)
```

- **Every compiler validates every guest build by default**: `build`, `run`, `build --run`,
  `run-project` and `test`, in every mode, run the IR verifier and the ownership validator, and
  validate the fact tables of a build that computed them (a `--release` build; the default
  optimized debug build defers its facts, so it has none to validate). A build with demand bodies keeps them: it checks the bodies it brings in, and a body it
  serves from a record alone was checked by the build that made the record, which the record says
  (`validated`, set only when the ownership validator accepted the body and the IR verifier passed
  it). A validating build refuses a record that does not say so and makes the body again. The bit
  is bound to the record's key, which binds the `opt` stage identity: the import closure of
  `passes.zig` (the ownership validator and the IR verifier included) and the compiler's optimize
  mode, so a record one compiler validated is never served to another as validated.
- **A Debug compiler** (a plain `zig build`) also validates every build of every mode with every
  body present: the ownership certificate of every function it compiles, the op log of every build
  that restored no lowering artifact, and the fact tables of every build that computed them (a
  `--release` build, or one under `--verify-facts-static`, `--verify-facts` or
  `--emit-certificates`). `--validate-like-optimised`, a test-only flag that no usage text
  lists, makes it validate the way an optimised compiler does.

- **The hidden-copy check** (`E_CORE_HIDDEN_COPY`, rule C of [managed memory](../managed-memory.md#written-copies-rule-c))
  runs in every guest build under the same policy (lane N5, the user's decision of 12 November 2026): every body present
  is checked, and a final record says `validated` only when the check also passed it, so a body served from a record alone
  passed it in the build that made the record. It counts frame blocks and dictionary-key copies and refuses neither;
  `--stats` prints its census (`selka-core: hidden-copy check: ...`, [cost](../tooling/cost.md#allocation-and-copy-sites)). On the
  99k port with two Debug compilers it cost 0.27% more instructions on a one-line edit and 0.15% on a cold build
  (`experiments/audit-work-20261111/N5.md`), and it refused nothing in the repository's suites or the three projects.

What the default costs an optimised compiler (lane VT, 11 November 2026,
`experiments/validate-optimised-20261111/status.md`): a one-line edit build of the 99k port
1.9% more instructions than `--no-validate` (2.60 against 2.55 G; 0.335 against 0.329 CPU-s), a new-shape type edit 1.2%, a
cold build 4.4% (71.7 against 68.6 G; 8.86 against 8.54 CPU-s); `check` and an unchanged build cost the same. A `--release`
build with every validator cost 0.4% more instructions on the 99k port (638.0 against 635.5 G) and 0.3% on the G3 port.

The complete gate runs the validators over the whole test corpus and ties them to the Lean checkers
in the actions `ownership-proof` (with `scripts/fact_proof.py` as its facts half) and `arith-proof`; the
maintainer's coordinator passes `-Dproofs=true` for them, and a plain `zig build test` skips them and says so.
The checks, the stamps, the shared verdict store and the profiles are in
`docs/tooling/ownership-certificates.md`; the fact checks and their fault injection are in
`docs/tooling/fact-certificates.md`. The theorem, its assumptions and what each rule of
[the ownership rules](../ownership-rules.md#proof-coverage) rests on are in the
report (`docs/audits/ownership-certificates-report-2026-10-26.md`).

## Trap reports

The text is the same in debug and release builds, including for a function LLVM
inlined. The runtime finds the frames from the program's line tables when the trap
fires; a call does no bookkeeping for it. The runtime also writes one
machine-readable `SELKA-TRAP` record after the text, which `selka run` hides and
`--diagnostics=json` turns into the `trap_detail` of a `diagnostic-v1` record
([runtime diagnostics](../io.md#runtime-diagnostics)).

Each trap site carries its file, line, column and function, which the compiler writes into the program
beside the trapping operation; a C operation of the runtime (a text search, a byte read) is handed the
site of its call. The frames above it come from walking the stack with the unwinder and reading each
return address in the line tables, the inlined calls included, so `--release` prints the same frames.
The runtime's own frames at the top of the stack are passed over, so a trap raised inside a C
operation lists the program's callers like any other (before lane FX18, one whose C function called
the trap before returning, such as the bounded text search, listed only its site).
`--max-frames` bounds the call depth, counted as the program enters frames (compiled in only when
it is given); the trace's walk counts nothing and costs nothing until a trap.

## Interactive debugger qualification

The emitted debug information currently describes functions, call sites and trap
locations. It contains no source-variable declarations or variable locations.
Preserving trap reports therefore does not imply full source-level debugging.

GDB 17.1 probes on 2026-10-09 compared unoptimized Debug, optimized Debug and Release
using a two-module loop and a separate tiny helper. Both programs returned the
expected output in every mode. The table describes those fixtures, not a promise
that every function or source line supports the same operations:

| Probe | Unoptimized (`--unoptimized`) | Optimized Debug at `-O0` (`--debug-o0`) | Release |
|---|---|---|---|
| Named loop-function breakpoint | Hits entry; caller frame correct | Hits entry; caller frame correct | Relocates to a trap location; not hit on normal execution |
| Caller line breakpoint, then step into loop function | Hits; steps into function | Hits; steps into function | No compiled code for that line |
| Arithmetic source-line breakpoint | Accepted, but only on trap path; normal execution does not stop | Relocates to another line; normal execution does not stop | No compiled code for that line |
| Statement `step` / `next` inside loop function | Skips source body | Skips source body | No active frame after missed entry breakpoint |
| Tiny helper's named breakpoint | Hits | Helper eliminated; no named function | Helper eliminated; no named function |
| Inspect source arguments and locals | No symbols | No symbols | No frame or source symbols |

The probes ran on the `-O0` form of optimized debug. The lean build, now the default of `build` and `run`, was not
run through them. It keeps DWARF line tables: the same set of source lines as `-O0` on small programs, and on the
99k-line port 18,500 of the 19,028 lines the `-O0` build maps (a line whose code the instruction selector merges
away has no row, so a line breakpoint on it does not bind; `--debug-o0` has them all). Trap messages carry the same
text and lines in both builds.

Optimized Debug retains useful function and call-site breakpoints, but can remove
helpers that unoptimized Debug keeps. Neither mode currently supports normal
statement stepping or local-variable inspection. Supporting those requires
statement locations on normal execution paths and variable/type/location metadata
through optimization. Exact trap traces and `debug(...)` retention are checked
separately by the compiler's regression tests.

Sources and full GDB transcripts (`bench/parity/debugger_20261009.json`) are
checked in. Reproduce with GDB built with Python support and a new directory:

```bash
python3 scripts/qualify_debugger.py --compiler zig-out/bin/selka \
  --gdb gdb --output /tmp/debugger-qualification
```

## The caches

**The per-user object store** is shared by every project, worktree and temporary
test directory of one user: `SELKA_CORE_RUNTIME_CACHE`, else
`$XDG_CACHE_HOME/selka/core-runtime`, else `~/.cache/selka/core-runtime`.

| Entry | Keyed by |
|---|---|
| `units-v1/ab/<key>.o` and `<key>.o.sum` | the unit's exact LLVM text, debug or release, target triple and CPU, toolchain identity, runtime declaration/layout surface, preprocessing directives, ABI flags and store format |
| `core_rt-<key>.o` | the runtime's C source, settings and toolchain (the source is compiled as `core_rt.c` in the build's staging directory, so the key is not in the program's symbol table) |
| `core_number_text-<key>.o` | the number-printing runtime, which ships prebuilt inside the compiler |

A hit starts no process and is served only when the object's bytes match its `.sum`
record. A miss compiles beside its entry and is renamed into place. An empty
`SELKA_CORE_RUNTIME_CACHE`, no usable home directory or an unproved toolchain keeps
the objects in the build's own work directory instead.

**The work directory** is `--cache-dir DIR`, else `.selka-cache/core` under the
current directory:

| Directory | Holds |
|---|---|
| `frontend/`, `semantic/` | the front end's parsed modules, verdicts and checked bodies (compiler caches) |
| `programs-v2/` | linked executables, `<key>.<family>` with a `.sum` sidecar: keyed by every linked object's bytes and the link settings; a build whose objects all match copies the program and links nothing. The family is the optimization level, and the four of each family used last (linked, or served by a replay) are kept (below) |
| `foreign-v1/` | `--link` C objects with the compiler's output and a manifest of their inputs (an [inputs record](#inputs-records)): the source and the headers its depfile listed with their bytes, and every header a quoted `#include` or `__has_include` of those files asks for beside them, present with its bytes or absent; one is served only while all of it is unchanged. A source that names a header through a macro has no manifest: its object is keyed by the digest of its preprocessed text (`<key>.o`, `<key>.log`), and a source whose header names one through a macro gets a `.pp` marker beside its slot so later builds key it that way ([C interop](../c-ffi.md#linking-your-code)) |
| `replay-v1/` | up to four replay records per entry and settings, one per set of inputs (below) |
| `stages-packed-v1/` | the stage records of lowering, the optimizer and emission (lowered functions, final bodies, the optimizer's manifest chunks, receipts), in immutable checksummed packs ("Stage packs", below); the shared half of the same records is [the shared stage store](../tooling/native-build.md#the-shared-stage-store) |
| `lowering-assembly-v1/` | one file per entry and mode: the tables (functions, compound types, strings) a lowering ended with and, for each lowered function, the key its artifact is stored under and the digest of its effects on the tables. A build whose edit left every changed function's effects as they were assembles its tables from it instead of restoring each function; any other build replays, and a build that restored every function writes the next record. `SELKA_ENGINE_DECIDE_LOWERING=0` turns it off |
| `engine-v1/` | the engine's records: `selka test` verdicts and replayable reports ([guest tests](../tooling/guest-tests.md#reusing-unaffected-results)), the front end's module records, and under `packs/` the records a fresh work directory was served by the shared tier, one file per build (the store). The earlier `tests/receipts-v3/` and `tests/manifests-v3/` are no longer read or written |

`selka test` additionally shares eligible ordinary test successes across project
roots through the per-user `native-tests` store; `--shared-cache-dir DIR` or
`SELKA_TEST_SHARED_CACHE` names another root, and an empty value disables it. Its `DIR/native-tests-v3` namespace holds the engine's records under the same root-relative keys as
the private store and does not relocate these private frontend, executable or report caches. See
[shared test results](../tooling/guest-tests.md#reusing-unaffected-results) for eligibility.

<a id="inputs-records"></a>**Inputs records.** A cached step reads what its result depends on through an inputs
handle (`src/core/inputs.zig`), which writes each input down with what was seen, and
the record it leaves is served only while every input still matches. There are four
kinds: a file with its content digest (or a path that was looked for and was absent), a
path whose existence alone was tested, a directory listing (the digest of the entry names a
named filter keeps, so a file appearing or going is a change) and an environment variable
with its value or its absence. A file's recorded status (inode, size, modification and
change time) lets an unchanged one stand for unchanged bytes. The replay record and the
`--link` manifest are inputs records; a rule that forbids a cached step to touch the file
system or the environment except through the handle is planned (K5 of the
provable-cache plan (`docs/audits/provable-cache-plan-2026-10-26.md`)).

**Replay.** A build records every file it read — each module source, embedded file,
generated interface file, `--link` source and depfile header — with the digest of
the bytes it used, and the listing of the entry directory that decides the
shadowed-standard-module warnings (only the files named like standard modules count, so an
unrelated new file leaves the replay alone), under a key of the compiler's identity, the flags, the entry and
each `--link` source as the command line spelled them (a program embeds the path as
given), the working directory, the entry's configuration, the toolchain and the environment
variables the identity contract keys (`src/environment_identity.zon`: the compiler's `MYL_*`
and `SELKA_*` settings and the C toolchain's inputs). Placement variables (homes,
scratch, `PATH`, cache locations, job counts, build-slot admission markers) are not in the key:
they decide where cached work lives, not what a build produces. Each entry and settings keep
the records of the four builds with different inputs that were used last (written, or served by
a replay, which sets the record's and its program's modification times), so undoing an edit or
switching back to a branch replays however many other states were built in between; a replay
tries the record used last first. The next identical build compares each file's inode, size, modification time and
change time to status captured around a matching full hash. Identical status reuses
that digest; changed status rehashes, and missing or unstable files miss. Recording
always hashes again. It revalidates the toolchain and copies the recorded program
without checking, lowering or starting a process. `--verify-cache` bypasses replay.

The compiler's identity, which keys replay records and every front-end and stage store,
digests each Zig source under `src` by its tokens (`std.zig.Tokenizer`: the tag and
spelling of every token, without comments, doc comments or layout) and every other file,
such as the C runtime or an embedded `.selka` standard module, by its bytes. A comment or a
formatting edit of a Zig source therefore leaves the identity, the stores and every
replay record as they were, while a change of any token moves them all. After a
comment-only edit of `src/main.zig`, `selka --features` reports the same
`compiler_sha256` and a program built before it reports `program: replayed`.

The identity also digests the bytes of each build product that `build.zig` embeds in the compiler, today the number-text
object (`core_number_text_object`). A change to how that object is built (its CPU, optimize mode or strip setting) changes
those bytes and so the identity, although no source file differs; an edit of `build.zig` that leaves the object as it was
changes nothing. A stage identity carries a product exactly when its import closure reaches the product's `@embedFile`.
`src/build_identity_rules.zig` (`named_files`) marks the products, and the build refuses to embed a marked product without
digesting it. Not digested: the guide pages `selka docs` prints (a docs edit would move every key for text no cache holds)
and the objects linked into the compiler itself (hashing code whose results do not depend on how it was compiled).

**Work-directory retention.** A work directory's regenerable tiers are bounded by the compiler itself, not by a
script: `programs-v2/`, `programs-v1/` (the layout before the family rule), `foreign-v1/`, `replay-v1/`,
`stages-packed-v1/`, `ownership/stages-packed-v1/`, `semantic/` and `frontend/`. Every build and check holds the
directory's lease (a shared hold on `.retention.lock`) while its stores are open. When it finishes, it may sweep: at
most once every ten minutes, and only when the sweep gets the lease exclusively, so a directory that another build or
check holds is skipped, never waited for. A sweep removes whole files, oldest first (abandoned partials first),
until the tiers total at most `SELKA_CACHE_TIERS_CAP_GB` GiB (default 10; `0` turns it off, the same variable
build-slot admission reads). Lock files, the `sequence` counter, claim directories and dot files are never removed,
and symbolic links are left alone. Every removal costs a miss: a stage pack or record that is gone is recomputed, a
program that is gone is linked again, and a replay record that names a gone program is not replayed. Linked programs
also keep at most four per family, which a publication enforces at once (`program_store.zig`), so an edit loop does
not accumulate executables even under the default bound.

**Stage packs.** The front end's checked bodies and the lowering's demand records live in
`stages-packed-v1/` (and `ownership/stages-packed-v1/`) as immutable, checksummed packs.
Each process appends its records to a journal and seals it into a pack of its own when it
exits, and a process indexes every pack of its compiler the first time it looks a record
up. The ownership proofs' store is indexed once per process, not once per session: the
sessions of one process (`selka test` runs hundreds) share one catalog, and a session that
starts lists the directory, reads only the packs it has not yet indexed and forgets the records
of packs that have vanished, so a lookup costs its own queries and not the size of the store.
A sealing process that finds 16 valid packs merges the 12 smallest into one
(`NEW-CORE-STAGE-PACK-3`): it keeps the newest value of each key and the order of the
records. A sealed journal keeps the order its build wrote its records in, so one build's
records share blocks.

Each build publishes the keys it touched as the root manifest of its demand generation,
in `stages-packed-v1/roots/` (`stage_roots.zig`). The work directory's maintenance
(`work_retention.zig`) runs after the build's hold is released, under the exclusive lease:
it keeps the records the current and last generation of every demand scope name, the
generation each replay record names, and the newest session manifests. It rewrites those
live records into fresh packs in the order the newest build needed them, publishes the
packs by rename, removes the packs they came from and logs the decision to
`.stage-compact.log` (reason, packs and bytes before and after, live bytes, time). It
checks the store when it has grown by a quarter of its live bytes, by eight packs, or by
sixteen manifests since its last check, and compacts when its dead bytes exceed a quarter
of its live bytes or it has 24 packs. A record no root names is a miss, and a reader that
holds a pack open keeps reading it. `ownership/stages-packed-v1/` is not compacted; the
work-directory retention bounds it by age.

Blocks are written uncompressed by default (`SELKA_STAGE_CACHE_COMPRESSION` unset or
`none`), because recompressing the packs on every edit build cost 12-19% of its CPU; the
store is about twice the size it was with zlib. `SELKA_STAGE_CACHE_COMPRESSION=zlib` opts
back in. Each block says in its first byte how it is encoded, so a store written under
either setting is read under either, and `--report` names the setting it wrote with as
`storage.compression`. `stages-packed-v1/` and `ownership/stages-packed-v1/` are bounded by
the work-directory retention above, which removes whole packs oldest first and never one
an open store could list (the lease keeps any open store out of a sweep). The unit-test
runner gives each guest program its own cache directory; a project's `.selka-cache` holds
one project's records.

**What a stage record's key covers.** A record is served under its key and nothing else, so a key has to hold everything the record's
content depends on: the compiler's stage identity, the function's own text and the settings, and every definition it was made from.
The lowered artifact of a function (`lowered-function-v16`, `lowering-receipt-v7`) is keyed by its checked-body part
(`module-check`), which carries the region of source and the declarations its signature and body name (a list `T[]` or an option `T?`
names its base type `T`: until 6 November 2026 it named nothing, so a function whose signature said `a.Group[]` kept its stored check and its
lowering when `Group` gained a field, and was built with the old element size), and by the debug flag, whether it is the
entry and the embedded assets. A generic instance (`zig_str_map_put[Value]`) is its template's body at its type arguments, and its
template's part says nothing of them, so its key adds the instance's checked name and, for every record its type arguments are made
of, the record's name and the digest of its whole declaration: the fields, the payloads of an enum's or union's cases, the elements
and keys of arrays, tables, dictionaries and sets, a domain's backing type, a buffer's element and a callback's slots, followed
through every record they name. A record is hashed beside its neighbours by the digest of its name alone, so a record the walk
does not follow is a definition the key does not cover: until 5 November 2026 the walk followed fields only, and growing the record in
a payload of `Value` left the stored lowering of `zig_str_grow[Value]` in service, which then built the old copy of the record
into a program whose records were the new ones. The records the lowering feeds (the optimizer's bodies, the emitted units) are
keyed by the bodies and the layout they were made from, so they follow the lowering's key. A key built from a reach that was
complete is the same key as before; an edit that changes no record reached through a type argument moves no instance's key.
`--verify-cache` checks the keys (see its section below).

Every `zig` process gets a fresh private cache inside a staging directory that the
build removes, so Zig's own cache keeps no second copy of objects or programs.
New unit entries use two-hexadecimal-digit shards; reads verify the sharded entry
then the legacy flat entry, and verified hits refresh retention recency. Implementation-only runtime
body edits preserve guest unit keys when the extracted ABI surface and exact guest
LLVM stay equal; the runtime object and link still rebuild. Preprocessing directives
inside bodies remain ABI inputs. Unrecognized C syntax binds the whole source.

`scripts/prune-caches.sh` delegates per-user retention to `core_store_gc.py` and
prunes each worktree's `programs-v2`, `programs-v1`, `foreign-v1` and `replay-v1`.

**The per-user store's collector never holds a build off the store.** A build holds a shared
lease on the store root's `.retention.lock` for as long as it builds, so on a busy machine no
moment without one exists, and a collector that wanted the lease exclusively either never ran
or, once it had it, stalled every build for the length of its window: on 2 November 2026 the
scheduled run held the lease for up to 574 s while its inventory ran at idle I/O priority,
evicted nothing, and took a landing gate from 500 s to 1,085 s. The collector (`core_store_gc.py`)
now takes no lease that builds wait on for unit objects, and a build waits on one for
at most a second per namespace:

- **A run costs a bounded amount.** A persistent ledger (`.size-ledger-v4.sqlite3`) keeps one
  row per unit object and one per shard directory. A run reads again only the shards not read for
  six hours (`--rescan-hours`), for at most `--scan-seconds` (240), and picks eviction candidates
  from an index on last use, so its cost is the shards re-read plus the objects removed, not the
  store: the 1.09 million objects of the live store are re-read over about 24 runs. Until every
  shard has been read once (`inventory_complete: false`, "priming") only objects idle past the age
  limit go.
- **An object a build is using is never removed.** A hit refreshes an object's modification time
  at most an hour late (a file touched within the last hour is left alone, `Context.touch`), so an
  object modified or read within `--grace-hours` (6) is not a
  candidate however far over budget the store is (`fresh_bytes` reports what the grace period
  keeps). A candidate is observed again (inode and last use), renamed to a tombstone
  `<key>.o.<nonce>.partial`, observed once more, and only then unlinked; a touch or a republication
  that raced the rename puts it back. The ledger is advisory: a stale row changes how much is
  counted, never what is removed.
- **Over budget, a run shrinks the store to 90% of the cap** (oldest use first, within
  `--evict-seconds`, 600, on 8 threads) while builders keep publishing; a build whose shard was not read yet is
  counted at the next read.
- **Claims and runtime objects.** An idle work claim is removed by probing its flock (a held one is
  busy); a waiter on a removed claim opens the new file (`storage.lock` checks its name after
  locking). Runtime objects (`core_rt-*`, `core_number_text-*`) are never touched by builds, so they
  go only when idle for the age limit, inside a try-exclusive window on the root lease of at most
  `window_seconds` (2), skipped when any build holds it.
- **Builds bound their own wait.** `native_cache_work.leaseWithin` and `Claim.acquire` wait at most
  `lease_wait_ms` (1,000) for a namespace held exclusively, then the build works unclaimed; the claims of
  the rest of its units do not wait again (`driver.claimAll`), and the runtime object's claim never waits.
  That covers `--no-cache` builds, which share the per-user store.

**The cap is disk, not payload.** Every size the collector adds up is allocated bytes (`st_blocks` x 512), and a
name that shares an inode with another counts once. The store holds small files: a checksum record of 96 bytes holds
a whole 4 KiB block, and half the objects are smaller than a block. On 5 November 2026 the live store held 9.96 GB of
payload in 2.1 million files (3.8 million names), under the 10 GiB cap, and 15.87 GB of blocks plus 0.63 GB of directories
and a 0.23 GB ledger: the checksum records alone were 4.35 GB of blocks for 104 MB of data, and the cap that counted
bytes evicted nothing. The cap now counts blocks, so the store holds 10 GiB on disk (`retained_bytes` in the report,
"on disk" in the `store:` line); directories and the ledger stay outside the cap and are not freed by eviction.


Flat aliases of older objects (`units-v1/<key>.o`) are no longer created or counted separately; a
flat-only survivor is given a shard name once a day (`adopt_flat`) and then evicted like any other
object, and an eviction removes every name of an object together. The same pass retires the flat names of
every object that has a shard name (`flat_names_retired`): they were one inode with the shard name and held no
bytes, but each was a directory entry in a flat directory of 1.7 million, and a compiler since the shard layout
(13 October 2026) finds the object by its shard name and reads the flat name only when that misses. A run that ends before the listing does is continued by the next one. The first, second and third
ledger versions are deleted once the fourth has read every shard. Managed objects, checksums and runtime source snapshots (including recognized
partials) count toward the cap; administrative and foreign files remain untouched. The
production `selka-core-store.timer` was installed in R4 with a 10 GiB cap
(payload at first, disk blocks since 5 November 2026), 14-day retention and 10,000-entry batches. An active timer does not establish
a satisfied cap; inspect its actual maintenance report (`store: ...` line, `.last-maintenance.json`).

## Shared compiler artifacts

The namespace is `compiler-artifacts-v2`, separate from test-success receipts.
No key of the store names the hole mode (a debug build keeps a typed hole as a trap, `check` and a release build refuse it), so a
record never carries a verdict that depends on it: the check summaries a debug build publishes leave a body that holds a hole out
of the stand-ins (`docs/tooling/caches.md#check-summaries`), and a `check` of the same program in a new work directory beside the
same store still reports `E_TYPED_HOLE`.
The shared program key (`core-shared-program-v3`, SHARED-PROGRAM-3) binds the
exact ordered object bytes and qualified toolchain/link settings, including
`SOURCE_DATE_EPOCH` and `ZERO_AR_DATE`, and no longer the compiler identity: the
objects determine the bytes and the store's byte verification guards the rest.
A program record is the executable itself (`program/<key>.blob`), with its size and
digest in a `program/<key>.blob.sum` sidecar written after it. A worktree's private
copy becomes a hardlink to the shared executable, so no executable is stored twice; where
the link is refused (another file system) the private program stays as it is, equal in
bytes, and nothing is copied back. A fresh link publishes the other way round when it can:
the linked program has no write permission, so the shared record is made as a hardlink of
it (no bytes are written), and only a program on another file system than the store is
copied. The program is hashed once per link, by the work directory's store (in chunks, never
held whole in memory), and that digest goes into the shared record, which every restore and
every later publication verifies against the bytes. A build that finds its program already
in the work directory's store asks the shared store only whether the record holds that digest
(the sidecar and the executable's size) and publishes nothing when it does. The toolchain's files are
scanned once after each tool process of a build, not again before each publication
(`--report`'s `link.tool_scans`). Retention evicts the sidecar with its executable. Existing logical module paths can produce identical objects
across roots. An entry built without a project root (no `selka.json`) names
itself by its basename in the entry unit's `source_filename` and debug
information (ENTRY-PATH-1), so two checkouts building it by the same relative
spelling link identical programs. Trap sites still carry the path the command
was given, so an absolute spelling on the command line changes the bytes and
misses; source paths and literal strings are never rewritten to manufacture a hit.
Foreign `--link` inputs and unqualified tools do not use shared programs.

The front end's sharing contract covers
syntax/body eligibility and fresh validation. `--no-cache` and `--verify-cache`
disable all shared compiler-artifact lookup and publication. An explicitly
configured invalid store fails before a private replay can hide it. Corrupt
individual records instead cause correct fresh work. See
`docs/tooling/cache-retention.md` in the compiler repository before deleting entries.

**Default location.** A non-empty `SELKA_COMPILER_SHARED_CACHE` names an
explicit store and an empty value disables sharing. The compiler also knows a
per-user default, `$XDG_CACHE_HOME/selka/compiler-artifacts` (when
`XDG_CACHE_HOME` is absolute) or `~/.cache/selka/compiler-artifacts`, used for
an unset variable only when the `default_sharing` switch in
`src/shared_cache_policy.zig` is on. R4 enabled this switch after qualification
at the default store locations. A default store that cannot be created (an absent or read-only home) is skipped
quietly and the command builds without sharing. One that exists but cannot be opened (its format marker is not this cache's, or
the directory holds files that are not this cache's) prints one `warning:` line that names the repair, and the
command builds without sharing; an explicit store that cannot be opened still fails the command. A compiler store
that only lost its marker is adopted again (`docs/tooling/cache-retention.md`).

## The shared stage store

The stage records (lowered, optimized and emitted work) are shared between worktrees through a per-user store,
`stage-artifacts-v1`. A fresh worktree of a project another worktree built starts from the records that worktree published
(the optimizer's latest state of the project, the lowered functions, the finals), so its first edit costs 1.0-1.25x a warm edit's
wall time and 1.2-1.25x its CPU, instead of 10-15x (G4h, ReleaseFast compiler on the P cores: 99k port 1.25x wall and 1.19x CPU, 400k port
1.00x and 1.25x; with the store off 15.4x and 10.5x). The price is on warm edits: with the shared half on a one-line edit executes 2.4-4.4%
more user instructions, because the shared store keeps more packs to index (F60). `SELKA_STAGE_SHARED_CACHE` selects the root, like the other stores:

The store is the user's own, so the test harness keeps out of it: the build graph's `build-env project` and the verification
coordinator give every test and driver an empty `SELKA_STAGE_SHARED_CACHE` when the caller named none, the unit suites' runner
passes an empty one to its guest builds, and `test_paths.privateStores` empties it with the other two. `scripts/verify_cache.py`
also snapshots the store's live roots (each publishing build writes one, naming its work directory) before a request and fails
a green request (status 6) when a root naming a work directory under the checkout is new or rewritten afterwards: a test of that
request reached the user's store. A change of the store with no such root is another process's (every ordinary build writes the
store) and is only noted on standard error.

The store is bounded: a build collects it when ten minutes have passed since the last collection, to 4 GiB by default (the cap is the
namespace's `policy` file, which `selka cache configure --kind stages --max-bytes N` writes). A collection keeps every record a worktree's
last build used and every pack younger than 14 days, compacts the older packs, and evicts packs no worktree names, oldest first, when the
store is over the cap (soft between collections). It holds no lock a build waits for: compaction reads and writes outside the store's
`sequence` lock, which a build takes only to append its own records, and a collector that finds another running skips. `selka cache gc
--kind stages` previews the packs a collection would evict; `--apply` collects now. Its policies are in `docs/tooling/cache-retention.md`.

A function's lowered artifact depends on the order its project lowers its functions in (the first function to touch a type makes it;
the others find it), so two projects that share a library file can store different artifacts under one key. The store keeps the first,
and a build whose own it refused keeps that one in its work directory and reads it first, so projects that share files never send each
other's builds back to complete trees.

## Reports

  The `link` object times the link step in wall nanoseconds: `ns` (the linker
  process, 0 when the program was reused), `store_ns` (publishing the program to the
  work directory's store), `shared_ns` (publishing it to the per-user shared store),
  `output_ns` (putting the program at `-o`) and `placement` (`linked`, `copied`,
  `already` or absent).
  The additive `unit_timings` array describes distinct native inputs by name,
  source path, kind and content key. Each row records `action` (`compiled`,
  `reused` or `verified`) and `compile_ns`: an awake-clock interval around the
  actual native compiler process, including startup and diagnostic capture.
  It excludes queue waiting, frontend checking, input preparation and cache
  publication. A reused unit has `compile_ns: null`; whole-build replay has an
  empty array. Parallel unit intervals overlap and must not be summed into wall
  time. A whole-program release unit may span many sources; its source path is
  ownership context, not attribution of all its cost to that file.
  Existing `stages` retain phase costs, with native time inclusive of linker time.
  Saved developer history (`docs/tooling/timings.md`) collects these
  observations for ordinary commands once enabled.

## `--verify-cache` and `--no-cache`

- **The stage records.** The command first builds as an ordinary build does, up to its emitted LLVM units (the front-end cache, the
  work directory's stage records and the shared stage store serve what their keys match; nothing is linked and no replay is
  recorded), and keeps the digest of each unit's text. It then builds again without any of them (no front-end cache, nothing lowered,
  optimized or emitted from a record) and compares the units' LLVM text, the linkage keyword of a source function's definition
  (`internal` or `hidden`) included: a check served from the front-end cache finds the same functions private as a full check, and a
  function that a unit of another module may name as a value is `hidden`. A unit whose text differs, or that only one build made, is an error
  line naming its kind (`module`, `generic`, `helper`, `entry`, `program`), name and source file, and the build exits 2: a stage
  record was served under a key that does not cover its inputs. A generic or helper unit's name holds the digest of its text, so
  a differing one is reported twice, once as made only by the cached build and once as made only by the fresh one. To find the
  function, build with `--emit-llvm a.ll` and with `--emit-llvm b.ll --no-cache` and compare the two files. Removing
  `stages-packed-v1` of the work directory (and the shared stage store) builds from scratch. `--report` counts the units compared as
  `stages.emission.work.units_compared`. A unit's text is a function of the functions it holds and of nothing the build decides by its
  own numbering: an emission receipt serves the text an earlier build rendered, so a symbol named by a type's ordinal in the build's type
  table would differ from a fresh build's after an edit that adds a type, in every unit that holds it, and `--verify-cache` would report
  code that is the same. A unit's local symbols (`@myl.layout.N`, `@myl.str.N`, `@myl.empty.list.N`) are therefore numbered by first use
  in the unit, and a type descriptor is named by the type's stable id (`type_ids.zig`). A report whose two texts differ in a symbol's
  number alone is an emitter naming bug and not a stale key; until 6 November 2026 an empty list's constant was named by its element's
  type ordinal.

## Which compiler this is: `--version`

The **commit** is deliberately not inside the compiler, because a commit hash among the digested bytes would move the
identity at every commit and empty every cache. The install step (`zig build`, with or without `--prefix`) writes
`selka.commit` into the directory of the executable (`scripts/write-commit-file.sh`): `commit HASH` and `tree clean` or
`tree dirty`. A tree is dirty when `git` sees a modified or staged tracked file or an untracked file under `src`; the line
then shows `commit 11419ef271ab+dirty`. A compiler copied without its file, built outside a git checkout, or with a file that
names no commit prints `commit unknown`. The file is rewritten only when its text changes, a `--prefix` installation keeps
its own, and the compiler reads it only for this command (no environment variable selects another). Under the incremental
watch (`scripts/dev_loop.py`) `zig-out/bin/selka` is a link, and the command also looks beside the name it was run by.
The script asks git its questions of a private copy of the index (`selka.commit.index` in the tree's `.zig-cache/commit-file`,
made again whenever the repository's index changes; the installation's `bin` holds `selka.commit` and nothing else): the
repository's own index and its lock are never touched, and a tree whose index has stale stat
data (a fresh worktree, a merge, until someone runs a plain `git status`) no longer makes every install read all its tracked
files, which cost about 145 ms at every build and now costs about 18 ms after the first.

### The toolchain's identity

A build's toolchain identity covers the `zig` executable's content, each
library root's own generation, the runtime and discovery inputs and the native CPU,
and it is part of every key. A library tree is reviewed once against the pinned,
approved Zig distribution and the answer is memoized under
`~/.cache/selka/core-tools-v1`. A toolchain that cannot be proved to be that
distribution still builds, but its objects stay in the build's private directory and
nothing is cached or replayed. The target is `amd64` Linux (SysV) with the host
CPU's features.

The identity also tracks the library files `zig` reads for these commands one by one
(`src/core/tool_files.zig`): the Zig sources it builds compiler-rt and the C library stubs
from (`std`, `compiler_rt`, `c`, `libunwind`, whole, because which `std` files a compile
opens varies from run to run), and the headers and stub sources the core's own commands
opened under `strace` (`src/core/tool_files.list`, regenerated by `scripts/audit_cache_reads.py
toolchain --write-list`) with the directories above them, so that a header which appears beside
those `zig` opened is seen: about 1,150 files and directories with their status. A
thread-sanitizer build tracks more, because it compiles the sanitizer runtime from the library's
C++ sources. Each build compares that status on a few threads beside the replay's own reads. It
adds about a millisecond to a replay (selka markdown 2.4 to 3.3 ms, EDA stage 2 8.0 to 8.7 ms on
a quiet machine) and nothing measurable to a cold build. An edit inside an installed toolchain,
even a same-size one with the modification time put back, or a header that appears beside the
ones `zig` opened, moves the identity. The whole tree is then reviewed again against
the approved distribution, and a changed toolchain is unproved: it builds, caches nothing
and replays nothing. A file the table does not name (documentation, other targets' headers)
is not an input. The headers a `--link` source includes are not read from this table: that
compile writes a dependency file, and every header it opened, system ones included, is an
input of its object by its bytes.

**Where the link runs.** Zig makes the C library stubs a program links against, and
compiler-rt, in the working directory it is started in, and the stubs name that directory
in the program's debug information (`DW_AT_comp_dir`). The link therefore always runs in
`/`, with absolute paths, and a proved toolchain builds into a Zig global cache of its own,
`$XDG_CACHE_HOME/selka/zig-global` (else `~/.cache/selka/zig-global`), that only such links
fill; `ZIG_GLOBAL_CACHE_DIR` does not reach it. Programs linked from identical objects are
byte-identical wherever the project, the work directory and the command were. A program with
`--link` sources still names each C source as the command line spelled it, relative to the
directory the compile ran in, so those two stay part of its identity.

**Tool recipes.** `zig cc -c unit.ll` is three processes: Zig's driver, a child `zig clang`
that compiles, and a child `zig ld.lld -r` that relinks the child's one object; a `zig cc`
link is the driver (which hashes every input into a cache manifest no build reuses) and a
`zig ld.lld` that starts a worker thread per CPU. The children's command lines are what Zig
derives from its arguments, the CPU and its libc stubs, so for one toolchain they are the
same text every time, and a proved toolchain's first build learns them: it asks Zig to
print them (`ZIG_VERBOSE_CC` for a probe compile, `ZIG_VERBOSE_LINK` for a second link to a
throwaway output) and keeps them as a *recipe* under
`<runtime store>/tool-recipes-v1/`, keyed by the toolchain, the CPU and the driver's
arguments. Later builds start `zig clang UNIT RECIPE -c -o OBJECT` and `zig ld.lld --threads=2
RECIPE-WITH-OBJECTS` themselves. The linked program is byte-identical to the one `zig cc`
links from the same units (the tests state it), the compile saves about 12 ms of CPU a unit
and the link about 26 ms at 99k units' worth of objects (70 at 400k). A recipe is a hint: a
damaged one, one naming a stub that is gone, an unproved toolchain, a release build's unit
(its remark flags) or a child that fails runs `zig cc` instead, and that run's output is what
the build reports. `--report` shows `link.recipes`: `link` (the link used a recipe), `units` (units a recipe compiled) and `learned` (processes that only learned a recipe). The object a
recipe compile writes differs in bytes (not in effect) from `zig cc`'s, so the unit object
format is `core-unit-object-v2`.

## System libraries

with, and a file too many only costs a cold build now and then. For each name the compiler keys:

- every file `/etc/ld.so.cache` maps it to (glibc-hwcaps variants included), read from the cache's table in either layout
  (the old `ld.so-1.7.0` one that glibc before 2.32 writes holds the new table after it), and in any case every absolute
  path in the cache's bytes whose last component is the name, which holds whatever the cache's format is;
- every candidate in the loader's default directories (`/lib64`, `/usr/lib64`, `/lib/x86_64-linux-gnu`,
  `/usr/lib/x86_64-linux-gnu`, `/lib`, `/usr/lib`) with their `glibc-hwcaps/x86-64-v4`, `-v3`, `-v2` subdirectories
  and the 24 legacy ones glibc 2.26 to 2.36 searches (every combination of `tls`, `haswell` or `xeon_phi`, `avx512_1`
  and `x86_64`), whatever the cache says, because the loader falls back to them when a listed file cannot be opened.
  Absent candidates are keyed as absent.

The cache's own bytes are keyed only when it cannot be parsed; otherwise a package install that rewrites it (any that
runs `ldconfig`) stays warm when the files it maps the names to are the same. A file that exists but cannot be read (a
library of another user with mode 0600, one below a directory that cannot be searched) is keyed as unreadable, with the
kind of error: the loader cannot load it either, and no build fails on it.

`selka native show` prints the closure as builds key it (the files that are there, and how many absent candidates are
keyed), the closure's own digest, the toolchain identity every native key holds (the closure with the CPU and the
toolchain: two machines share results exactly when it is the same), and whether results are reused here and why not. A
compiler built with `-Dtest-system-root=DIR` (a test seam that reads the closure below `DIR`) says so on its first line
and in `selka --version`. `--zig PATH` names the toolchain. `--digest` prints the toolchain identity alone (64 hexadecimal
digits and a newline): the component builder (`selfhost/components.zig`) holds it in each component's receipt, so a change of
the identity (a library update) makes a new receipt instead of a rebuild that is compared with the old one.

## Retired build controls

The internal test switch `SELKA_CORE_SANITIZE=thread` instruments every emitted LLVM function, the native runtime and linked C sources with ThreadSanitizer, and links its runtime. `SELKA_CORE_SANITIZE=address` does the same with AddressSanitizer; its reviewed native `libasan.so.8` dependency is captured only in address-mode tool identities. The switch has no CLI flag or feature slug. Object/runtime/program/replay cache identities include the selected sanitizer, so sanitized and ordinary objects cannot mix; other values are rejected. Run sanitizer tests in a supported native environment. AddressSanitizer guest tests use `--max-memory 0` so its shadow-memory reservation is not limited by the test runner.
