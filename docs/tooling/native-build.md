# Native builds

`selka build` turns a checked program into a Linux x86-64 executable. `selka run`,
`run-project`, `build --run`, `test` and `doctest` are the same build followed by
running the result. The compiler drives every step itself; the only external tool is
the Zig toolchain's bundled clang (`zig cc`), so building and using selka needs the
pinned Zig and nothing else. For when to build `--release`, what the checks cost and
how to measure, see `docs/performance.md` in the compiler repository; for the stores a
build keeps, see [the caches](#the-caches) below.

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

There is no interpreter, no bytecode and no second back end. Checked ownership
manages memory through moves, read-only borrows, exclusive mutation and explicit
copies. Each owned value is cleaned up deterministically; nothing is collected
or traced.

## Debug and release builds

A build is **lean debug** by default for `build`, `run`, `run-project` and `build --run`;
`--mode Debug` selects the same mode. `selka test` builds at LLVM `-O0` by default.
`--debug-o0` and `--debug-lean` choose between the two on any of those commands, and
`--optimize-debug` selects the same Core passes at LLVM `-O2`.

- **Lean debug** (the default for `run`, `run-project`, `build` and `build --run`) runs
  the Core optimization passes, then compiles each module unit with LLVM's IR passes off
  (on for a unit of at most 50,000 bytes of LLVM text) and its code generation at `-O2`,
  less six switches that cost compile time and no run
  time (see [debug code generation](#debug-code-generation)). It keeps module units, so
  an edit recompiles the units whose emitted text changed, and it retains `debug(...)`
  output and source locations in trap traces. Generic instances, generated adapters and
  the entry have their own units. The program runs 1.2 to 1.3 times as long as the same
  program built with `--release` (an `-O0` build takes 1.7 to 2.8 times), for 1.0 to
  1.6 times the compile CPU of an `-O0` build.
- **Debug at -O0** (`--debug-o0`; the default of `selka test`) runs the same Core
  passes and compiles each unit at LLVM `-O0`: the cheapest cold build, and the slowest
  code of the three. The tests of `selka test` compile and start fastest this way, and a
  test that checks a program's behaviour sees the same result in either build.
- **Optimized debug at -O2** (`--optimize-debug`) is the same build with LLVM `-O2`:
  slower to compile and run its tests a little faster. Use it when a test depends on
  what LLVM folds or inlines, or to compare the two.
- **Unoptimized** (`--unoptimized`) skips the Core optimization passes and requests
  LLVM `-O0`, keeping module units and debug output. Use it to isolate optimizer bugs,
  preserve helper functions for breakpoints, or compare optimization costs.
- **Release** (`--release` or `--mode ReleaseFast`) emits the whole program as
  one unit, so LLVM can optimize across every module boundary. An unchanged
  release build compiles nothing, but an edit recompiles the whole unit.

The debug builds keep the always-inline helpers ordinary (LLVM decides where they
inline, and the lean build's LLVM does not inline at all); release keeps `alwaysinline`.
The unit and program keys carry the mode's name and the whole `zig cc` argument list it
compiles with, so the modes never share an object, and a change to the lean list
(`src/core/build_mode.zig`) moves every key made under it.

The development modes have the [tested debugger limitations](#interactive-debugger-qualification).
Lean and optimized debug are not a guarantee of Release speed on every program.

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

```bash
selka run app.selka                  # lean debug: Core passes, then -O2 code generation; LLVM's IR passes on units up to 50 KB
selka run app.selka --debug-o0       # the same Core passes at LLVM -O0: the cheapest cold build, slower code
selka build app.selka -o app --debug-o0
selka test tests/ --debug-lean    # a test run on the lean build; tests build at -O0 by default
```

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

All modes keep every check the program can reach (see
[checks in every build](#checks-in-every-build)) and report traps identically.
Release standalone builds omit the formatting and the write of `debug(...)` lines but still evaluate their arguments, so
a call or a bad index inside one behaves as in a debug build; ordinary output is unchanged.
`selka test --release` runs a suite on release builds;
`--verify-facts` (release or optimized debug) also checks at run time every fact the passes relied on
and traps `R_CORE_FACT` if one does not hold, and `--no-facts` turns the fact pass
off to measure what it buys. It also checks rule C on the final module: a copy the source did not write is
refused as `E_CORE_HIDDEN_COPY` (see `docs/managed-memory.md`, "Written copies"). Set
`SELKA_VERIFY_WRITTEN_COPIES=0` to run `--verify-facts` without that check.

### Effective optimization levels

The flags Selka requests and the optimization the pinned toolchain actually runs
are distinct. With Zig `0.17.1` (Clang 22.1.8), `zig cc -###`
reports Clang `-O0` for requested `-O0`, and Clang `-O2` for requested `-O1`, `-O2`
or `-O3`. This holds for both generated LLVM and linked C sources on the native
x86-64 target used here. The runtime's requested level remains `-O2`.

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

## `selka build`

```bash
selka build FILE.selka -o OUT [--release | --unoptimized | --optimize-debug | --debug-o0] [--link FILE.c]... [--emit-llvm PATH]
             [--emit-certificates DIR] [--cache-dir DIR] [--no-cache] [--local-stdlib] [--zig PATH]
             [--report | --cache-report] [--verify-cache] [--stats]
             [--diagnostics=text|json] [--no-facts | --verify-facts]
             [--verify-ownership] [--verify-facts-static] [--verify-names] [--cpu native|x86-64-v3]
selka build FILE.selka --run [run options] [-- ARGS...]
```

- **The entry** is a single file or a project entry: a module header or an import
  makes it a project, and the nearest `selka.json` supplies its import policy,
  limits and roots. `--project` and `--whole-program` are accepted for old scripts
  and ask for nothing more.
- **`-o OUT`** writes the executable and creates `OUT`'s missing parent directories
  (`-o build/bin/app` needs no `mkdir`). A failed build leaves an existing `OUT`
  untouched. `OUT` is a second name (a hard link) for the program the work directory
  stores, when both are on one file system, and a copy otherwise; the stored program
  and its shared-store record have no write permission, so `OUT` has none either (a
  program that patches itself or `cat > OUT` is refused). A build replaces `OUT` by
  removing it and linking the new program, so an older program that another name still
  holds is never written through, and a running program is not disturbed. An unchanged
  rebuild finds `OUT` already a name of the stored file and touches nothing. A hard
  link carries the stored file's modification time, not the build's, so a `make`
  rule that depends on `OUT` being newer than its sources runs the build again (a replay
  that costs a few milliseconds).
- **`--run`** replaces `-o`: the program is built into a private directory, run with
  `selka run`'s options and exit status, and removed afterwards; every value after
  `--` is the program's.
- **`--link FILE.c`** (repeatable) compiles a C source and links it in; see
  [direct C imports](../c-ffi.md).
- **`--optimize-debug`** selects the optimized debug build at LLVM `-O2`, including on
  `run`, `run-project`, `build --run` and `test`. `--mode Debug` is the command's default
  debug build: lean for `build` and `run`, LLVM `-O0` for `test`. **`--debug-o0`** selects
  the `-O0` debug build and **`--debug-lean`** the lean one, on the same commands. Each mode
  has its own cached builds and test results.
- **`--local-stdlib`** is a development switch: a standard module name resolves
  from a file beside the entry before the embedded copy. Copy the module you are
  editing into the project root and use this flag to check it without rebuilding
  the compiler; the switch is part of the build and guest-test replay keys.
- **`--unoptimized`** selects the optimizer-off diagnostic mode on those commands.
  It has separate build, native-object and test cache identities. Different
  explicit modes cannot be combined, in either order; repeating the same mode
  is allowed. The shared runtime stays `-O2`.
- **`--emit-llvm PATH`** also writes the emitted LLVM text. Such a build is neither
  replayed nor recorded.
- **`--diagnostics=json`** prints warnings, errors, refusals and (with `--run`) a
  trap as `diagnostic-v1` records on stderr.
- **`--zig PATH`** names the toolchain; see [toolchain](#toolchain).

The status is 0 for a built program, 1 for a check error or an `E_CORE_UNSUPPORTED`
refusal, 2 for a usage, configuration or tool failure, and 3 when the project's
import policy denies an import.

```console
$ selka build examples/factorial.selka -o /tmp/factorial
$ /tmp/factorial; echo $?
120
$ selka build examples/factorial.selka --run; echo $?
120
```

## Building for another CPU: `--target`

`selka build --target NAME` builds for the target `NAME`. There are two:
`x86_64-linux`, the host and the default when the flag is absent, and `thumbv6m-none`, an ARM Cortex-M0+ (RP2040
class) with no operating system. A name that is not known is refused with status 2 and the list of names.

A `thumbv6m-none` build checks the program and compiles every unit with
`zig cc -target thumb-freestanding-eabi -mcpu=cortex_m0plus -Os -ffunction-sections -fdata-sections`: loops stay scalar
(no vector plans), `memchr` and `memcmp` take 32-bit sizes, and functions carry no unwind tables, though they keep their
DWARF line metadata for a debugger. In a program that starts [the second core](#the-second-core-registersstart_core1),
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

A bare build without `--linker-script` is refused with one line that says what to pass, and a host build that names one
is refused too. A program that needs the host's prebuilt number-text runtime (a float written as or read from text, a
format specification, BLAKE3) is refused with `E_TARGET_NUMBER_TEXT`, which names what it used, instead of linking a trap.
`run`, `run-project`, `build --run` and `test` refuse the target, since its programs cannot run here;
`scripts/bare/bare_run.py` runs them on QEMU or on an RP2040 board and compares them with Linux.

A bare target provides two capabilities, its memory-mapped registers and `Host` (the next section). `main(reg: Registers)` receives the registers, and each
`registers.read32` or `write32` (and the 8- and 16-bit forms) is one volatile load or store at the address
([register access](../io.md#register-access)); a call of a function only a simulated bank has (`registers.simulated()`,
`poke32`, `script32`, `pin32`, the log readers) is refused with `E_TARGET_SIMULATED_REGISTERS`. A `main` that asks for any
other capability (`out: Stream`, `fs: Filesystem`, `fs: Filesystem?` and the rest) is refused by the build with
`E_TARGET_CAPABILITY` at each such parameter, for example "`Stream` is not provided on the target `thumbv6m-none`, which
provides `Host` and `Registers`", while a `main()` or `main(args: str[])` builds as above. The refusal comes from `build` only (`check` does not take
`--target`, and accepts `main(reg: Registers)` everywhere); the host provides every capability but `Registers`, so a host
build of `main(reg: Registers)` is refused the same way and every other host build is unchanged.

```console
$ selka build --target thumbv6m-none blink.selka -o blink.elf --link scripts/bare/qemu/platform.c \
    --linker-script scripts/bare/qemu/link.ld; echo $?
0
$ selka build --target thumbv6m-none blink.selka -o blink.elf --link scripts/bare/qemu/platform.c; echo $?
selka: a build for the target `thumbv6m-none` needs a linker script: add `--linker-script SCRIPT.ld` and the platform's C file, `--link PLATFORM.c`
2
$ selka run --target thumbv6m-none blink.selka
selka: the target `thumbv6m-none` only builds: its programs cannot run here; use `selka build --target thumbv6m-none FILE.selka -o OUT`
```

A host build is the same with and without `--target x86_64-linux`: the same text, objects and cache keys.

### The second core: `registers.start_core1`

`registers.start_core1(reg, entry)` starts core 1 of an RP2040 running `entry`, a top-level `func(Registers) -> int`,
beside `main`, and answers `True`; it answers `False` (a value, not a trap) when the platform has one core, when core 1
was started already, when it is called on core 1, when core 0's heap has too little room, or when core 1 does not
answer its start. Only a device has it: a host build (`build`, `run`, `test`) that calls it is refused with
`E_TARGET_DEVICE_REGISTERS`, which names the function. A program that calls it links the two-core flavour of the
runtime, which is what the rest of this section describes, with no flag; a program that does not pays nothing for it
(its image is the one-core runtime's: in `--release`, 1,328 code bytes for a `main` that returns 0, where the two-core
flavour takes 3,104).

- **Its memory.** Core 1 gets half of the largest free block of core 0's heap at the call: an 8 KiB stack at its top and
  its own heap below, which is core 1's byte ceiling (`R_MEMORY_BUDGET` past it). Core 0's ceiling drops by as much.
- **What the cores share.** No heap value: each core allocates and frees in its own arena
  (`bare/core_bare_heap.c`, chosen by the core's number, the SIO CPUID register on the RP2040), and every piece of the
  runtime's state that the hosted runtime keeps per thread or shares between threads (the free lists, the live-block
  count, the byte ceiling, the output buffers, a trap's detail) is a thread-local variable with one copy per core,
  made in that core's heap the first time the core touches it (emulated TLS, `__emutls_get_address` in
  `bare/core_bare_cores.c`). The cores talk through the hardware: the SIO FIFOs and spinlocks (the `rp2040` package's
  `rp2040.sio` module in selka-rp) or a memory window both reach through `Registers`. A `once` of the runtime runs once
  on either core.
- **The log.** Every write of the runtime to the platform's `myl_bare_write` takes the platform's lock 0 (a hardware
  spinlock), so two cores' lines do not mix within a write, and every line core 1 writes begins `core 1: `.
- **When `entry` returns**, core 1 writes its report, `core 1: returned N, live blocks L, heap high-water H of C, stack
  S of T` (its leak check: L is 0 when it freed everything), checks its stack's painted reserve (`R_BARE_STACK` when
  it ran past), and waits. The program goes on until `main` returns.
- **When `main` returns**, core 1 is stopped where it is (its heap goes with it), and core 0's report is the log's last
  line before the platform's exit.
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

`examples/device/two_cores.selka` in selka-rp runs both cores: core 1 counts and pushes a word per round through the FIFO
while both cores build and free a list per round, and core 0 checks every word.

### A device project: one command

A project describes its device once, in its `selka.json`, and builds it with `selka build F.selka -o OUT` and no other
flag. `target` is the target a build uses without `--target`; `devices` names each device with what a build for it needs
(`target`, `linker_script`, `links`, `include`, `image`, `uf2_family`), and `device` chooses one (`--device NAME` chooses
another). Every path of a device is relative to the `selka.json` and may not leave its folder. A flag of the command line
wins over each setting (`--target`, `--linker-script`); its `--link` and `--include` add to the device's. `check`, `run`
and `test` read none of these keys: only `build` (without `--run`) builds for a device.

```console
$ cat selka.json
{"version": 1, "device": "qemu",
 "devices": {
   "qemu": {"target": "thumbv6m-none", "linker_script": "plat/link.ld", "links": ["plat/platform.c"],
            "include": ["plat"]},
   "flat": {"target": "thumbv6m-none", "linker_script": "plat/flat.ld", "links": ["plat/platform.c"],
            "include": ["plat"], "image": "uf2", "uf2_family": "0xe48bff56"}}}
$ selka build blink.selka -o blink.elf
$ qemu-system-arm -M mps2-an385 -nographic -monitor none -serial none \
    -semihosting-config enable=on,target=native -kernel blink.elf; echo $?
120
$ selka build blink.selka -o blink.bin --device flat
$ selka build blink.selka -o blink.uf2 --device flat
```

- **The image follows the output's name**, or the device's `image` when the name has no `.elf`, `.bin` or `.uf2`:
  `.elf` is the linked ELF; `.bin` is the raw image, the bytes `zig objcopy -O binary` makes of that ELF (every
  allocated section with contents at its load address, from the lowest one, the gaps zero; more than 256 MiB is refused
  and the output removed, so QEMU's layout, with its vector table at 0 and the rest at `0x20000000`, has no `.bin`);
  `.uf2` is those bytes in UF2 blocks of 256 payload bytes, each with its address and the device's `uf2_family`. The
  compiler writes them itself.
- **`include`** (top level, beside `links`, resolved as `links` is) and `--include DIR` add folders to the include path of
  every C file the build links, a device's `include` those of a build for it; a header found there is an input of the
  file's object like any other, so editing it rebuilds.
- **Refusals** (status 2, one line naming the `selka.json`): a device name with no entry
  (`error[E_PROJECT_CONFIG]: device "pico" names no entry of devices; the devices are qemu, flat`), a device path that
  names no file, an unknown `target`. The file itself is refused when a device has an unknown key, a path leaves its
  folder, two devices share a name, or `device` names no entry of the file's `devices`.
- **A path's real location** must be inside the folder too: a symbolic link inside it that points out is refused, with
  where it points.
- **A package's device** (`"device": "rp2040/ram"`) is built through `selka packages build`, which reads it from the
  lock; `selka build` alone refuses it with one line that names that command ([packages](packages.md#devices-in-a-package)).
- **`selka test`** puts the project's `include` folders (and `--include DIR`) on the include path of the C it links, as
  `build` does.

### A device described by its memory (MCU-NOC4A)

A device entry may describe its memory instead of naming a linker script, name a boot stage the compiler holds, and bind the
platform's hooks to Selka functions. The compiler writes the linker script (and with it the boot stage's 256 bytes) and the C
platform file is no longer needed for the layout. `linker_script` and `memory` in one entry are refused; every other key and flag
keeps working, and `--linker-script` still wins over a device's `memory`.

- **`memory`**: `{"NAME": [ORIGIN, LENGTH]}`, one to sixteen regions that do not overlap. NAME is lowercase letters, digits and `_`.
  ORIGIN and LENGTH are `"0x..."` or decimal text, LENGTH with an optional `K` or `M`, all below 4 GiB.
- **`place`** (optional): `{"vectors": R, "code": R, "data": R}`. By default the code and the vectors are in `flash` and the data
  (with `.bss` and the heap) in `ram`, or everything is in `ram` when there is no `flash`. `.data` is loaded from the code's region and
  copied when that is another region (`__data_load != __data_start`, `*(.ramfunc*)` first, for code that runs from RAM).
- **`stack`** (needed with `memory`): `"16K"` at the top of the data's region, or `["8K", "sram45"]` at the top of another region.
  The heap runs from the end of `.bss` to the stack's limit (or to the end of the data's region when the stack is elsewhere).
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
- **Refusals** of the keys themselves are `E_PROJECT_CONFIG` lines naming the region, the stage or the hook: a `memory` that
  overlaps or has a zero length, a `stack` that does not fit, a `boot` that is not held, a `place` naming no region, an unknown hook.

The RP2040's flash layout of `selka-rp`'s `link.ld` (the vector table after the 256 boot bytes, the data copied from flash, a
16 KiB stack below the log area) and QEMU's, as descriptions:

```json
{"version": 1, "device": "flash",
 "devices": {
   "flash": {"target": "thumbv6m-none", "memory": {"flash": ["0x10000000", "2044K"], "ram": ["0x20000000", "252K"]},
             "boot": "rp2040-read-03h", "stack": "16K", "image": "uf2", "uf2_family": "0xe48bff56"},
   "qemu": {"target": "thumbv6m-none", "memory": {"boot": ["0x0", "1K"], "ram": ["0x20000000", "264K"]},
            "place": {"vectors": "boot", "code": "ram"}, "stack": "16K",
            "hooks": {"start": "board.start", "write": "board.write", "exit": "board.finish"}}}}
```

`selka build prog.selka -o prog.uf2 --device flash` writes the whole flash image, boot stage included, and `scripts/bare/` runs the QEMU one
(`test/target_cli_test.zig` has `board.selka`: UART0 for `write`, a reset through the system control block for `exit`).

### C interop on a device

Some of what firmware does is reached only through C on the device: a boot ROM's flash routines (erase and program a
sector, read the flash chip's unique ID), a vendor's driver. A device program calls it as a Linux program calls C
([direct C imports](../c-ffi.md)): an `extern func NAME(host: Host, ...)` declaration, and `main` asks for the `Host`,
alone (`main(host: Host)`) or beside the registers, in either order (`main(reg: Registers, host: Host)`). The bare
runtime hands the `Host` over unconditionally, as it hands over the registers: a device has no command line to say
`--allow-host`, so `main(host: Host?)` is always `Some`. Each call is a plain call of the C symbol under the target's C
convention (AAPCS: an `i64` takes a register pair, and what does not fit in r0 to r3 goes on the stack). What
`extern func` accepts and refuses is what it accepts and refuses on Linux. The C file is one more `--link` beside the
platform's:

```selka
# doc: check
# The C side, in flash.c: uint32_t flash_unique_id_low(void);
#                         int32_t flash_erase(uint32_t offset, uint32_t count);
import registers

extern func flash_unique_id_low(host: Host) -> u32


extern func flash_erase(host: Host, offset: u32, count: u32) -> i32


func main(reg: Registers, host: Host) -> int:
    registers.write32(reg, 0x40004008, 1)
    const id = flash_unique_id_low(host)
    debug(id)
    return int(flash_erase(host, 0x1F000, 4096)) + int(bit_and(id, 1))
```

```console
$ selka build --target thumbv6m-none config.selka -o config.elf --link platform.c --link flash.c \
    --linker-script link.ld; echo $?
0
```

`debug(...)` writes through the platform's `myl_bare_write` (stream 2) in a plain build, as `--release` drops it on every
target: the bare runtime defines the function a `debug` line calls, `myl_core_span_stream_write`, as a weak symbol, so a
platform file that still carries its own definition keeps linking and its definition is the one used.
`test/bare/extern_host.selka` and `test/bare/extern_registers.selka` (each with `# bare-link: extern_host.c`, which
`scripts/bare/bare_run.py` adds as a `--link`) run on QEMU, plain and `--release`.

A boot ROM routine has no symbol: its address is read from a table in the ROM at run time. An `@address` extern func
calls it through that address ([calls through an address](../c-ffi.md#calls-through-an-address)): the target is a `u32`
on `thumbv6m-none`, passed as given, so it is a Thumb address with its low bit set, as the ROM's table holds them, and
the address 0 traps `R_FOREIGN_TARGET` before the jump. Nothing is linked for it.

```selka
# doc: check
# The C side, in rom.c: uint32_t rom_lookup(uint32_t code);  (the table entry for a two-letter routine code)
extern func rom_lookup(host: Host, code: u32) -> u32


@address
extern func flash_range_erase(host: Host, entry: u32, offset: u32, count: u32, block: u32, command: u8) -> Unit


func main(host: Host) -> int:
    const erase = rom_lookup(host, 0x4552)
    flash_range_erase(host, erase, 0x1F000, 4096, 65536, 0xD8)
    return 0
```

`test/bare/extern_address.selka` (with `# bare-link: extern_address.c`) calls a C function through its address with four
scalars, two of them on the stack, on QEMU, plain and `--release`.

## A program for machines other than this one: `--cpu`

A program built for the host is compiled for the machine that builds it (`zig cc -march=native`), so it may use
instructions that an older machine faults on. `--cpu=MODEL` of `build`, `run`, `run-project`, `build --run` and `test`
picks the CPU model instead:

- `native` is the default and what a build did before the option existed: `-march=native`, the same flags and so the same
  cache keys.
- `x86-64-v3` is the AVX2 floor: `-march=x86_64_v3` (Zig's spelling of the x86-64-v3 model), the rest of the flags as they are.
  The program runs on any x86-64 machine with AVX2 (Selka's vector plans are 256-bit AVX2 anyway), whatever machine built it.

Any other value is refused with status 2 and one line naming the two. The model is part of every key that holds the
compiler's flags (a unit's object, the runtime object, the linked program, the replay record of an identical build and a
test's receipt), so a `x86-64-v3` build is never served by a `native` build's cache, or the other way round. `--cpu` is for
the hosted target: with `--target thumbv6m-none` it is refused (`native` changes nothing).

```console
$ selka build examples/factorial.selka -o /tmp/factorial --cpu=x86-64-v3; /tmp/factorial; echo $?
120
$ selka run examples/factorial.selka --cpu=bogus; echo $?
selka: unknown --cpu value `bogus`; the values are `native` and `x86-64-v3`
2
```

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

## Running a built program

A built executable hands `main(args)` every argument after `argv[0]` unchanged,
grants every capability, and exits with `main`'s value `& 0xFF` (1 on a trap). Its
runtime options come only from the `SELKA_OPTIONS` environment variable, spelled
as on the `selka run` command line and separated by spaces:
`SELKA_OPTIONS=--restrict ./app` denies every capability, and
`SELKA_OPTIONS=--print-result ./app` prints `main`'s value at exit. See
[the native backend](../io.md#the-native-backend) for quoting and errors.

`selka run` builds the same executable with its budgets compiled into `main`:
`--max-steps`, `--max-frames`, `--timeout` and `--max-memory`, described in
[runtime budgets](runtime-budgets.md#instruction-and-frame-budgets). A program
built with `selka build -o` carries no step, frame or byte budget and pays nothing
for one.

### Ending a run (RUN-SIGNALS-1)

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

## Warnings in the output

A project that has warnings gets them on every `check`, `build`, `run` and `test`, replays included, and a long-lived
one printed hundreds of lines about code nobody had touched (215 warnings, 645 lines, for the G3 port, every time). The
default output keeps the diagnostics whole and the text short: a warning is printed in full unless its module is
**tracked by git and identical to `HEAD`**. Those warnings are counted, and the command ends with one line:

```console
$ selka check src/main.selka
numeric.selka:34:5: warning[W_OPTION_TRY]: the `None` arm only returns `None`: ...
check: ok (177 modules, 176 cached)
warnings: 209 in 55 unmodified modules (W_RANGE_CHAIN 56, W_UNUSED_BINDING 53, W_OPTION_TRY 50, W_LITERAL_MATCH 22, W_PATTERN_SHORTHAND 16, ...); `selka check --warnings` lists them
$ selka check src/main.selka --warnings    # every warning, in full
```

A module with uncommitted edits (staged or not), an untracked or ignored one, and any module outside a git repository (or
when git cannot be run) print their warnings, so the ones a change introduced are in front of its author. The rule reads the
working tree and `HEAD`, never a cache: a cached check, a replayed build, a test run and a `--no-cache` build print the same
text for the same tree. `--warnings` (accepted by `check`, `check-project`, `check-module`, `build`, `run`, `run-project`
and `test`) or `SELKA_WARNINGS=all` in the environment prints every warning; `--diagnostics=json` always carries every
one; a project that denies warnings (`lint.warnings: "deny"`) prints all of them when a command fails on them. Errors are
never withheld. A directory test run (`selka test DIR`) ends with one such line for all its entries, after their results: a
warning is counted once however many entries import its module, and a module once, the same at every `--jobs`.

`selka check FILE` prints the warnings of the file it names, and for each other module it reached that has warnings one
line after its result, `` helper.selka: 3 warnings; `selka check src/helper.selka` `` (the module as its warnings name it, then
the check that lists them, from the working directory), so checking one file after another does not repeat the warnings of
every module it imports. Errors in any module print in full. `--warnings`, `SELKA_WARNINGS=all`, `--diagnostics=json`
and a project that denies warnings bring them all back as above, and so does a check that names its format
(`--diagnostics=text`), which is how `selka fix FILE` checks: its output is unchanged. `selka check DIR` prints every
warning of every module, as before.

A command run through `selka packages` leaves out, besides, the warnings of the files of a locked package and ends with one line per package, `` 2 warnings in package `rex` are not shown ``; it prints no `selka fix` line, which could not repair a file that imports a package; errors and `--warnings` are as above ([packages](packages.md#symbolic-links-repeated-warnings-and-interface-files)).

`build`, `run`, `run-project` and `test` also leave out the hints: `W_COPY_MOVE`, advice that a move could replace a copy
and the one warning that never carries a repair (about 450 lines on each build of the netlisp port), and `W_MATCH_ELSE` and
`W_MATCH_IS`, a `match` the flat forms say shorter (1,218 on a build of the port before its `selka fix`). They are neither
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

| Flag or command | What it does |
| --- | --- |
| `--no-validate` (`build`, `run`, `build --run`, `run-project`, `test`) | runs no validator that no flag asks for, in any compiler: the way out of a validator's fault, which every rejection names. The final records such a build writes say they were not validated, so a validating build validates them again before it reuses them, and it publishes nothing to the stage store's shared half |
| `--verify-ownership` (`build`, `run`, `test`) | validates the ownership certificate and checks the IR of every function the passes finish, with every body in the build, in any compiler, and prints `selka: ownership: N functions validated, M unchecked` |
| `--verify-facts-static` (`build`, `run`, `test`) | validates the fact tables against the final IR, forces the facts to be computed (the default optimized debug build defers them), and prints `selka: facts: N functions validated, ...` |
| `--verify-names` (`build`, `run`, `test`) | records the op log of lowering (the compound types, functions and strings each function's lowering made, with stable names instead of table positions) and replays it into an empty module, which must equal the one lowering built; prints `selka: names: N segments replayed, ...`, or says that it did not check a build that restored lowering artifacts (`src/core/op_log.zig`) |
| `--emit-certificates DIR` (`build`, `test`) | writes the ownership certificates, `program.fact-certificate` when the build computed facts, and `program.core-ir`, the final IR as text (`src/core/ir_text.zig`); `selka dump-ir FILE.selka --certificate` and `--fact-certificate` print the first two |
| `selka validate-certificates PATH` | the Zig validator's verdict on each function of the certificate files under `PATH`, in the line format of the Lean checker `certcheck` |
| `selka validate-fact-certificates PATH [--detail]` | the same for fact certificates; `--detail` lists what the validator assumed or left unchecked |
| `selka mutate-certificates FILE OUTDIR`, `selka mutate-fact-certificates FILE OUTDIR` | write the single-edit fault mutants of an accepted certificate, for the gate's fault-injection checks |
| `selka verify-ir PATH` | the IR verifier's verdict on each function of the `program.core-ir` texts under `PATH`, in the line format of its Lean copy `irverify` (`proofs/verify_ir`); `scripts/verify_ir_proof.py` compares the two. It refuses a union payload read the tag facts do not justify (`union-tag`), which a build only counts |
| `--stats` (`build`, `run`) | among its lines, `selka: union-tags: N payload reads not justified by a tag test (counted in builds, refused by the gate)`: the reads of the final IR the union-tag rule cannot justify |
| `--stats` (`build`, `run`) | also `selka: construct-reads: N constructors read a borrow they neither own nor lend (counted in builds, refused by the gate)`: the constructors of the functions this build validated that the construct-read rule refuses |

**The union-tag rule counts in builds and refuses in the gate.** The IR verifier checks that every `union_payload k` and
`union_take k` reads a value whose tag the facts on the paths to it confine to case `k` (a test of the tag, the equality of
two tags, a `union_make` of the case, followed through a field read twice, a field stored and read back, and a `phi` of such
values). A build's verifier counts a read it cannot justify and refuses nothing, and a plain build prints nothing about it;
`--stats` prints the count. The gate's `verify-ir-proof` action refuses every such read outside shape M (a `list_get` value
read under a test of the element's tag, at most 10 in the corpus) over the language suites, the C interop programs and a
pinned real program (`test/fixtures/verify-ir-proof/protobuf-addressbook/`), through `selka verify-ir` and its Lean copy,
whose lemma (`VerifyIr.payload_of_verdict`) is about that refusing rule.

```console
$ selka build prog.selka -o prog --stats
selka: union-tags: 0 payload reads not justified by a tag test (counted in builds, refused by the gate)
```

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

When a validator runs without being asked for:

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
  `--stats` prints its census (`selka-core: hidden-copy check: ...`, [cost](cost.md#allocation-and-copy-sites)). On the
  99k port with two Debug compilers it cost 0.27% more instructions on a one-line edit and 0.15% on a cold build
  (`experiments/audit-work-20261111/N5.md`), and it refused nothing in the repository's suites or the three projects.
- **`--verify-facts` and `--verify-written-copies`** make any compiler validate both, and run the hidden-copy check even
  under `--no-validate`.
- **`--no-validate`** turns all of these off; an explicit flag still runs its validator.
- The **sabotage modes** of the run-time fact checks state false facts on purpose and are not
  validated.

What the default costs an optimised compiler (lane VT, 11 November 2026,
`experiments/validate-optimised-20261111/status.md`): a one-line edit build of the 99k port
1.9% more instructions than `--no-validate` (2.60 against 2.55 G; 0.335 against 0.329 CPU-s), a new-shape type edit 1.2%, a
cold build 4.4% (71.7 against 68.6 G; 8.86 against 8.54 CPU-s); `check` and an unchanged build cost the same. A `--release`
build with every validator cost 0.4% more instructions on the 99k port (638.0 against 635.5 G) and 0.3% on the G3 port.

A rejection exits 2 and prints `error[E_OWNERSHIP_VALIDATION]` (the function, block and
instruction, the judgment J1 to J8 and the nearest source rule) or `error[E_FACT_VALIDATION]`
(the function, block, value and check F1 to F7), with a note naming `--no-validate`. With `--emit-certificates` the build keeps going so
the certificate exists to inspect, and fails at the end.

The complete gate runs the validators over the whole test corpus and ties them to the Lean checkers
in the actions `ownership-proof` (with `scripts/fact_proof.py` as its facts half) and `arith-proof`; the
maintainer's coordinator passes `-Dproofs=true` for them, and a plain `zig build test` skips them and says so.
The checks, the stamps, the shared verdict store and the profiles are in
`docs/tooling/ownership-certificates.md`; the fact checks and their fault injection are in
`docs/tooling/fact-certificates.md`. The theorem, its assumptions and what each rule of
[the ownership rules](../ownership-rules.md#proof-coverage) rests on are in the
report (`docs/audits/ownership-certificates-report-2026-10-26.md`).

## Trap reports

A trap prints its source position, code, message and call trace, innermost first,
on stderr, and the program exits 1:

```console
$ selka run trap.selka
trap.selka:2:12: error[R_LIST_BOUNDS]: native execution failed (index 5, length 3)
  in pick at trap.selka:2:12
  in main at trap.selka:6:12
```

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

When the site is in the standard library (a path starting `@stdlib/`), the first line names the
nearest frame outside it, the program's own call, and the library frame follows as the first `in`
line, as context:

```console
$ selka run find.selka
find.selka:4:12: error[R_TEXT_BOUNDARY]: native execution failed (offset 1, length 3: inside a multi-byte character; ...)
  in strings::find at @stdlib/strings.selka:128:18
  in find::find_from at find.selka:4:12
  in find::main at find.selka:8:16
```

The first line keeps its shape (`FILE:LINE:COL: error[CODE]: ...`) and every frame its `in NAME at
PATH:LINE:COL` form, so tools that read either need no change; `--diagnostics=json` puts the
program's call in the record's `location` and every frame, the library's first, in its `stack`.

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

A build keeps three layers of store. Every key is a BLAKE3 digest over the complete
input of what it names, so a hit cannot serve a wrong object, and a damaged entry is
recompiled rather than used.

| Layer | Where | Serves | Bound |
|---|---|---|---|
| the work directory | `--cache-dir DIR`, else `.selka-cache/core` | one project's records: front end, stages, engine, programs, replay | `SELKA_CACHE_TIERS_CAP_GB`, 10 GiB |
| the per-user object store | `SELKA_CORE_RUNTIME_CACHE`, else `$XDG_CACHE_HOME/selka/core-runtime`, else `~/.cache/selka/core-runtime` | compiled unit and runtime objects, for every project and worktree | the collector's 10 GiB |
| the shared per-user stores, on by default | `compiler-artifacts`, `stage-artifacts` and `native-tests` under `$XDG_CACHE_HOME/selka` or `~/.cache/selka` | what another worktree of the project built: front-end and ownership records and linked programs ([shared compiler artifacts](#shared-compiler-artifacts)), the stages of lowering, the optimizer and emission ([the shared stage store](#the-shared-stage-store)), test verdicts ([guest tests](guest-tests.md#reusing-unaffected-results)) | 10 GiB, 4 GiB and 256 MiB; `selka cache gc\|configure --kind compiler\|stages\|tests` |

`--no-cache` uses none of the work directory and the shared stores and does use the object store ([which store a cold build uses](#--verify-cache-and---no-cache)).
A build, check or test that keeps a work directory writes a `.gitignore` of `*` and a `CACHEDIR.TAG` (the standard signature line, which backup tools honour) into `.selka-cache` (also one an older compiler made) or into a `--cache-dir` folder it made itself, each only when no file of that name is there, so `git add -A` in a project does not commit the cache; a `--cache-dir` folder that already existed gets neither, so a folder of sources is never hidden.
A project's `selka.json` can name the object store, the shared stores, their parent (`XDG_CACHE_HOME`) and the temporary
folder in a `stores` object, read for each variable the caller's environment leaves unset: a flag, then the variable (empty
means off), then the file, then the default. `selka cache where ENTRY` prints where each resolved and what decided it.
An empty `SELKA_COMPILER_SHARED_CACHE`, `SELKA_STAGE_SHARED_CACHE` or `SELKA_TEST_SHARED_CACHE` switches the matching shared store off;
a non-empty one names another. A build that has none of them still produces the same program: a shared store only decides whether
a fresh worktree starts from another worktree's work (its first edit build costs about a warm one with the stores on, and about
ten times a warm one with the stage store off) and whether a cold work directory is served.

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
| `stages-packed-v1/` | the stage records of lowering, the optimizer and emission (lowered functions, final bodies, the optimizer's manifest chunks, receipts), in immutable checksummed packs ("Stage packs", below); the shared half of the same records is [the shared stage store](#the-shared-stage-store) |
| `lowering-assembly-v1/` | one file per entry and mode: the tables (functions, compound types, strings) a lowering ended with and, for each lowered function, the key its artifact is stored under and the digest of its effects on the tables. A build whose edit left every changed function's effects as they were assembles its tables from it instead of restoring each function; any other build replays, and a build that restored every function writes the next record. `SELKA_ENGINE_DECIDE_LOWERING=0` turns it off |
| `engine-v1/` | the engine's records: `selka test` verdicts and replayable reports ([guest tests](guest-tests.md#reusing-unaffected-results)), the front end's module records, and under `packs/` the records a fresh work directory was served by the shared tier, one file per build (the store). The earlier `tests/receipts-v3/` and `tests/manifests-v3/` are no longer read or written |

`selka test` additionally shares eligible ordinary test successes across project
roots through the per-user `native-tests` store; `--shared-cache-dir DIR` or
`SELKA_TEST_SHARED_CACHE` names another root, and an empty value disables it. Its `DIR/native-tests-v3` namespace holds the engine's records under the same root-relative keys as
the private store and does not relocate these private frontend, executable or report caches. See
[shared test results](guest-tests.md#reusing-unaffected-results) for eligibility.

**Inputs records.** A cached step reads what its result depends on through an inputs
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

```bash
python3 scripts/core_store_gc.py --store ~/.cache/selka/core-runtime            # a dry run: what would go, in blocks
python3 scripts/core_store_gc.py --store ~/.cache/selka/core-runtime --apply    # what the timer does every 15 minutes
```

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

Compatible worktrees can also share immutable frontend artifacts and linked
programs by setting `SELKA_COMPILER_SHARED_CACHE`. Each worktree keeps its own
private cache and executable copies. The native compiler implements this store;
installation and use need no Python.

```bash
export SELKA_COMPILER_SHARED_CACHE="$HOME/.cache/selka/compiler-artifacts"
selka build app/main.selka -o app.bin --cache-dir .selka-cache/private --report
```

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

With an empty private cache, a hit still performs frontend validation, lowering
and emission, then copies the verified program through the private program
store. When the per-user object store also hits, no compiler or linker process
starts. `cache-report-v1` reports `program: "reused"`, `program_shared: true`,
zero `compiled` and zero `processes`. A subsequent private replay reports
`program_shared: false`; it does not claim another shared lookup.

The front end's sharing contract covers
syntax/body eligibility and fresh validation. `--no-cache` and `--verify-cache`
disable all shared compiler-artifact lookup and publication. An explicitly
configured invalid store fails before a private replay can hide it. Corrupt
individual records instead cause correct fresh work. See
`docs/tooling/cache-retention.md` in the compiler repository before deleting entries.

**Mismatches.** When a build publishes its linked program and the store already
holds a verified program with different bytes under the same key, the build
keeps its own program and goes on: the shared record is not replaced, nothing
is published, and the store appends one line to
`compiler-artifacts-v2/mismatches.log`:

```text
mismatch program <key> existing=<digest> attempted=<digest>
```

The build counts it as `shared_mismatches` in its report (see
[Reports](#reports)). Syntax and typed records follow the same rule and log the
same line with their own kind; only linked programs are counted in the report.
A non-zero count means two producers built different bytes from one key, which
is a determinism bug to investigate.

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

```bash
export SELKA_STAGE_SHARED_CACHE="$HOME/.cache/selka/stage-artifacts"   # the default, set only to name another
selka build app/main.selka -o app.bin --report
selka cache gc --shared-cache-dir "$HOME/.cache/selka/stage-artifacts" --kind stages --max-bytes 2147483648
```

An unset variable selects the per-user default, `$XDG_CACHE_HOME/selka/stage-artifacts` (when `XDG_CACHE_HOME` is absolute) or
`~/.cache/selka/stage-artifacts`; an empty value disables the store, and each work directory then keeps its stage records
privately. `--no-cache` (on every command that takes it) and the fresh pass of `--verify-cache` never read or publish it; the first
pass of `--verify-cache` does, since that pass is the ordinary build it compares against. A default store that cannot be created is skipped quietly.

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

- **`--report`** (on `build`, `build --run`, `run` and `run-project`) prints one
  `cache-report-v1` JSON line on stderr: the units linked, served by the object
  store, compiled and verified, the tool processes started, and whether the program
  was `linked`, `reused` from the program store or `replayed` (every count 0).
  `program_shared` identifies an actual shared linked-program restore, and
  `shared_mismatches` counts shared program records that held different bytes
  for this build's key (a miss, logged in the store; normally 0).
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
- **`--cache-report`** prints the same as one `selka-core: cache:` text line.
  It ends with `; N shared mismatches` only when that count is not zero.
- **`--stats`** prints what the release passes did: calls inlined, loops unswitched,
  versioned and vectorized, checks proved, and the ownership plan's in-place
  updates, deterministic drops and lists promoted to the stack.
- **`--timings`** on `run`, `run-project` and `build --run` prints
  `timings: native_ns=N`, the program's own run time with the build excluded.
- **`selka dump-ir FILE.selka [--facts]`** prints the Core IR (with `--facts`, after
  the release passes, with their intervals); `--emit-llvm PATH` writes the LLVM text.
- **`--emit-certificates DIR`** (and `selka dump-ir FILE.selka --certificate`) writes the
  ownership certificates of the final IR, one file per unit (and `program.fact-certificate`
  when the build computed facts); see `docs/tooling/ownership-certificates.md`
  and `docs/tooling/fact-certificates.md`. Such a build is neither replayed
  nor served from the optimizer caches.
- **`--verify-ownership`**, **`--verify-facts-static`** and **`--verify-names`** run the
  validators in any compiler; see [certificate validators](#certificate-validators).

After a one-line edit to one module of a three-unit program, and again unchanged:

```console
$ selka build app/main.selka -o app --report
{"version":"cache-report-v1","program":"linked","units":3,"reused":2,"compiled":1,"verified":0,"processes":2}
$ selka build app/main.selka -o app --report
{"version":"cache-report-v1","program":"replayed","units":0,"reused":0,"compiled":0,"verified":0,"processes":0}
```

The old back end's `qbe-build-v1` and `work-report-v1` build reports, its
`--timings=json` phase profile and `--explain-invalidation` are refused on `build`,
`run` and `test`. The front-end commands (`check`, `check-project`) still print
`frontend-cache-v1`, `work-report-v1` and `invalidation-report-v1`
(work report).

## `--verify-cache` and `--no-cache`

**`--verify-cache`** recomputes what the stores served and fails the build, naming the unit,
when it differs. It never replays or uses the shared compiler-artifact tier. Use it when you
suspect the store, or after changing the emitter or a key. It checks two things:

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
- **The objects.** Every unit the object store served is compiled again, and a fresh object whose bytes differ from the cached one
  fails the build.

The second build is the one `--verify-cache` always ran, so the command costs the first build's front end, lowering, optimizer and
emission on top; the native compile and the link run once.

**`--no-cache`** (on `build`, `build --run`, `run`, `run-project` and `test`) is a cold build. It builds
through an empty private work directory that is removed when the command ends, and it neither reads nor
publishes any record of an earlier build: not the work directory's (replay, program, foreign-object,
front-end, stage and test-receipt stores), and not the shared stores, the compiler-artifact tier and the
shared stage store included. Until 6 November 2026 the shared stage store was still read and published on
`build`, `run` and `run-project` (only `test` skipped it), so a `--no-cache` build could be served the same
stale lowering, optimizer or emission record as the build it was meant to check; comparing a rebuild with a
`--no-cache` build now compares it with a build that read no stage record. Status, output and diagnostics are
those of the same command with caches. The one per-user store a cold build still uses holds objects, not
records of a build:

| Store | Where | With `--no-cache` |
| --- | --- | --- |
| the work directory | `--cache-dir DIR`, else `.selka-cache/core` | not used: the build gets an empty private one under it (`no-cache-PID`), removed afterwards |
| the shared compiler-artifact tier | `SELKA_COMPILER_SHARED_CACHE`, else `compiler-artifacts` | not read or published (the command's environment names no store); this covers the engine's shared records, which live in it |
| the shared stage store | `SELKA_STAGE_SHARED_CACHE`, else `stage-artifacts` | not opened: nothing read, nothing published, and a directory the variable names is not even created |
| the shared test-receipt store | `SELKA_TEST_SHARED_CACHE`, else `native-tests` | not read or published (`selka test --no-cache`); no other command opens it |
| the per-user object store | `SELKA_CORE_RUNTIME_CACHE`, else `core-runtime` | **used**: an object is keyed by the exact text of the unit (or the runtime source) it was compiled from, the toolchain's identity and the settings, and is served only when its bytes match their recorded digest, so it cannot be stale |
| the toolchain's identity memo | `core-tools-v1` under `$XDG_CACHE_HOME/selka` or `~/.cache/selka` | **used**: it remembers the content digest of the files the pinned `zig` reads and is validated against those files on every call; it holds no build result |
| Zig's global cache for the libc stubs and compiler-rt | `zig-global` under the same directory | **used**: a build product of the toolchain, not a record of the program |

A `--no-cache` build is therefore as slow as a first build of the program on a machine whose per-user object store
is warm: every function is checked, lowered, optimized and emitted again, and only the native compile of a unit
whose text the object store holds is skipped. Use it when a cached result is in doubt (a build that prints a value a
cold build does not), and `--verify-cache` when the question is which stored record is stale.
`selka check --no-cache`, `fix --no-cache` and `cost --no-cache` open no shared stage store either; they never did.

```console
$ selka build app/main.selka -o app --verify-cache --cache-report
selka-core: cache: 3 units, 3 reused, 0 compiled, 3 verified; program reused; 3 processes
$ selka run app/main.selka --no-cache
```

## Which compiler this is: `--version`

`selka --version` (or `selka version`) prints one line and exits 0: the commit the installation was made at, the
compiler's identity, the build mode, the Zig that built it and the target.

```console
$ selka --version
selka commit 11419ef271ab, identity 9f2c4e1a7b30, debug, zig 0.17.1, x86_64-linux
```

The **identity** (the first twelve digits) is the digest that keys every cached result: the compiler's sources under `src`,
the Zig toolchain, the optimization mode and the bytes of every product `build.zig` embeds (`build_identity.zig`). Two
builds with one identity share every cache, so a commit that changes only a guide, a test or `CHANGES.md` prints the same
identity as its parent, and a compiler rebuilt after it still serves every stored result.

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

```bash
selka --version
cat "$(dirname "$(command -v selka)")/selka.commit"
```

## Toolchain

### Finding Zig

Selka drives Zig (`zig cc`) to compile and link every program, so it needs one. It takes the first
of these that is set (for the bundled Zig, that is there):

1. `--zig PATH` on the command line;
2. the `SELKA_ZIG` variable;
3. the Zig the release bundles, `lib/selka/zig/zig` in the folder above the one that holds the
   running `selka` (`PREFIX/bin/selka` finds `PREFIX/lib/selka/zig/zig`; the executable's own path is
   read through any link, so `~/.local/bin/selka` pointing into an install finds that install's Zig);
4. the `ZIG` variable;
5. `zig` on `PATH`.

A variable that is set and empty counts as not set. The release download (`selka-VERSION-x86_64-linux.tar.xz`,
installed by its `install.sh`) holds the official Zig 0.17.1 at the third place, so a machine with no Zig
needs nothing else; from a source build there is none, and the Zig on `PATH` or named by `SELKA_ZIG` is used.
With none found a command says `error: no Zig found: install Zig 0.17.1 from https://ziglang.org/download/ ...`
after `cannot identify guest toolchain: ToolNotFound`. `selka native show` prints the one in use on its `toolchain:` line:

```console
$ env -i HOME=$HOME PATH=/usr/bin:/bin selka native show | grep -E '^(toolchain|reuse):'
toolchain: /home/you/.local/lib/selka/zig/zig
reuse: on
```

The bundle keeps Zig's `lib/` folder whole, because the toolchain identity below reviews that tree and turns reuse off for
a trimmed copy. `zig build release -Doptimize=ReleaseFast -Dbundle-zig=DIR` makes the bundle (`DIR` is an unpacked
official Zig 0.17.1 distribution) under `zig-out/release/`; it refuses a Zig that `selka native show` would not accept.

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

A built program loads files of the machine: the loader (`/lib64/ld-linux-x86-64.so.2`), libc, libm, libgcc_s and
libpthread, and whatever `/etc/ld.so.preload` names. Their path, resolved path and bytes go into the toolchain identity
that keys every native result (objects, linked programs, replay records, test verdicts), so every machine reuses results
under keys of its own, nothing is approved, and no list of machines is compiled in. The rule is that the keyed set is a
superset of every file the loader could load: a file left out would be a result reused under bytes it was not built
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

- **The first build on a machine** is cold and the second reuses, with no step in between and no package manager.
- **A library update** (a glibc security fix) changes the files' bytes: the next build is cold once for native results;
  the front end's stage records stay warm. Old entries are never served again and the per-user collector removes them
  after 14 idle days.
- **A preload file** keeps reuse on. It is read as glibc reads it (from `#` to the end of a line is a comment; entries
  are split at blanks, tabs, newlines and colons; `$LIB`, `$PLATFORM` and their `${...}` forms are expanded to every value
  they can have on x86-64), and each file it names is keyed like a library, a bare name with its cache and default
  candidates. An entry that cannot be keyed soundly (a relative path, another `$` token), a cache or preload file larger
  than 64 MiB, or more than 4096 candidate files turns reuse off, and `selka native show` says every reason why. `LD_PRELOAD`, `LD_LIBRARY_PATH` and the other loader and
  compiler overrides turn reuse off too, as before.
- **Two machines sharing a store** (a network folder) never serve each other's results unless their toolchain
  identities are the same: the same closure, CPU and toolchain.

`selka native show` prints the closure as builds key it (the files that are there, and how many absent candidates are
keyed), the closure's own digest, the toolchain identity every native key holds (the closure with the CPU and the
toolchain: two machines share results exactly when it is the same), and whether results are reused here and why not. A
compiler built with `-Dtest-system-root=DIR` (a test seam that reads the closure below `DIR`) says so on its first line
and in `selka --version`. `--zig PATH` names the toolchain. `--digest` prints the toolchain identity alone (64 hexadecimal
digits and a newline): the component builder (`selfhost/components.zig`) holds it in each component's receipt, so a change of
the identity (a library update) makes a new receipt instead of a rebuild that is compared with the old one.

```console
$ selka native show
the system libraries built programs load (their bytes key every native result):
  /lib64/ld-linux-x86-64.so.2 -> /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2
      c0b20d6e1ced12abfe0b1ef2b5b68017950beaaea3df69eb6949d73e0ecf7b40
  /usr/lib/x86_64-linux-gnu/libc.so.6 -> /usr/lib/x86_64-linux-gnu/libc.so.6
      9941dc28e68bc5fd788d9cd024c69e68c791d63799e7538a97b6040dd9f50fb6
  ...
  and 640 candidates in the loader's default directories, keyed as absent
/etc/ld.so.preload names nothing that is there
/etc/ld.so.cache: keyed through the files it names
closure digest: 5b0c... (these files alone)
toolchain: /usr/local/bin/zig
toolchain identity: 81d2... (what native keys hold: these files, the CPU and the toolchain)
reuse: on
```

Until 19 November 2026 a build reused native results only on a machine whose libraries matched a list compiled into the
compiler or an approval written by `selka native approve` (which needed `dpkg`), and reused nothing elsewhere (GH-3b,
`docs/audits/native-closure-keys-design-note-2026-11-19.md`). `selka native approve` now prints that it is no longer
needed and exits 0; `~/.config/selka/native-approvals` and `SELKA_NATIVE_APPROVALS` are read by nothing.

## Where to look when a build is slow

- **Every build compiles.** Run it twice with `--report`. An unchanged build says
  `"program":"replayed"`. If it does not, something the build reads changes between
  runs: a generated file, an embedded asset, the environment, or a `--link` source
  whose header changed while it compiled.
- **An edit compiles many units.** A debug build recompiles each unit whose text
  changed: the edited module's, plus any unit that inlined a changed public helper.
  A release build always recompiles the whole program, so iterate in debug.
- **The first build on a machine.** Zig builds its C library stubs once per toolchain
  (into `zig-global`, above) and the core runtime object is compiled once per user; later
  projects reuse both. A fresh `SELKA_CORE_RUNTIME_CACHE` pays the second again, and a fresh
  cache home both.
- **Checking dominates.** A large project's check is the front end's cost;
  `selka check FILE.selka --report` shows what it reused (compiler caches).
- **Tests are slow.** Each test file builds its own program; see
  [guest tests](guest-tests.md#reusing-unaffected-results) for receipts and `--jobs`.

## Build programs: `selka do`

A project's procedures (its checks, its image builds, its runs on an emulator or a board) are a Selka program,
`build.selka`, as Zig's are `build.zig`; facts stay data in `selka.json`. `selka do STEP [ARGS...]` finds `build.selka` in
the working folder or the nearest folder above it and runs it as `selka run build.selka -- STEP ARGS...` would, with
that folder as the working folder:

```console
$ cd ~/work/selka-rp/packages/rp2040
$ selka do check
$ selka do image blink --release
$ selka do all --board
```

The program is told what it would otherwise guess, in its environment only (the build itself does not see them):
`SELKA`, the path of the compiler that started it; `SELKA_ZIG`, the Zig that compiler uses (`ZIG`, then
`SELKA_ZIG`, then `zig` on `PATH`); and `SELKA_PROJECT_ROOT`, the folder of `build.selka`.
[`buildkit.locate(env)`](../standard-library.md#buildkit) reads the three. Everything after `do` goes to the program
after `--`, `--help` included, and `selka do` alone passes no arguments, so the program decides what that means. The
program's exit status is `do`'s; a program that does not build ends `do` as it ends `run` (status 1 for an error in
the source). With no `build.selka` in the working folder or above it, `do` prints `selka do: no build.selka in FOLDER or any
folder above it`, naming the folder it started from, and exits with 2. `build`, `run` and `test` keep their meanings.

## Retired build controls

The QBE back end, its bytecode IR and the QBE-to-LLVM translator were removed in
stage S5 of the new compiler core (2026-10), with the tracing collector, two-count
reference counting, arenas and host functions. These are refused with status 2 and
a one-line reason: `--backend`, `--llvm-opt`, `--lto`, `--keep-symbols`,
`--step-accounting`, `--gc-runtime`, `--gc-stress`, `--rc-runtime`,
`--legacy-sharing`, `--value-semantics`, `--library`, `--provider`,
`--link-library`, `--library-path`, `--explain-ownership` (use `--stats`), and the
commands `emit-qbe`, `emit-project-qbe`, `emit-runtime`, `dump-bytecode` (use
`dump-ir`), `compile-module`, `link-modules` and `invoke`. `--qbe PATH` is accepted
and ignored.

The internal test switch `SELKA_CORE_SANITIZE=thread` instruments every emitted LLVM function, the native runtime and linked C sources with ThreadSanitizer, and links its runtime. `SELKA_CORE_SANITIZE=address` does the same with AddressSanitizer; its reviewed native `libasan.so.8` dependency is captured only in address-mode tool identities. The switch has no CLI flag or feature slug. Object/runtime/program/replay cache identities include the selected sanitizer, so sanitized and ordinary objects cannot mix; other values are rejected. Run sanitizer tests in a supported native environment. AddressSanitizer guest tests use `--max-memory 0` so its shadow-memory reservation is not limited by the test runner.
