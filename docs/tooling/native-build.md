# Native builds

`selka build` turns a checked program into a Linux x86-64 executable. `selka run`, `run-project`, `build --run`, `test` and `doctest` are the same build followed by running the result. The only external tool is the Zig toolchain's bundled clang (`zig cc`), so building needs the pinned Zig and nothing else. For when to build `--release` and how to measure, see `docs/performance.md` in the compiler repository; for the stores a build keeps, see [the caches](#the-caches).

## How a build works

The compiler checks the program (an error stops here with status 1), builds Core IR (a construct the core cannot build yet stops with `E_CORE_UNSUPPORTED`), runs the optimization passes, emits LLVM text, and compiles and links it with `zig cc` and the C runtime. There is no interpreter, no bytecode and no second back end. Checked ownership manages memory through moves, borrows, exclusive mutation and explicit copies; each owned value is cleaned up deterministically, and nothing is collected or traced.

## Debug and release builds

A build is lean debug by default for `build`, `run`, `run-project` and `build --run`; `selka test` builds at LLVM `-O0` by default.

| Mode | Select with | What it does |
|---|---|---|
| Lean debug | the default; `--mode Debug`, `--debug-lean` | Core passes, then module units compiled with LLVM's IR passes off and code generation at `-O2` ([debug code generation](#debug-code-generation)). An edit recompiles only the units whose text changed; `debug(...)` output and source locations in traps are kept. Speed between `-O0` and release |
| Debug at `-O0` | `--debug-o0`; the default of `selka test` | The same Core passes at LLVM `-O0`: the cheapest cold build, the slowest code |
| Optimized debug | `--optimize-debug` | The same build at LLVM `-O2`: slower to compile, faster tests. Use it when a test depends on what LLVM folds or inlines |
| Unoptimized | `--unoptimized` | No Core optimization passes, LLVM `-O0`. Use it to isolate optimizer bugs |
| Release | `--release`, `--mode ReleaseFast` | The whole program as one unit: an unchanged build compiles nothing, an edit recompiles everything |

- Two different modes on one command line are refused, in either order; a repeat is allowed. A build in one mode never serves another mode's objects, programs or test results. `selka test DIR` passes the mode to the children it starts.
- Every mode keeps every check the program can reach ([checks in every build](#checks-in-every-build)) and reports traps identically. Release standalone builds omit the formatting and write of `debug(...)` lines but still evaluate their arguments. `selka test --release` runs a suite on release builds.
- `--verify-facts` (release or optimized debug) also checks at run time every fact the passes relied on and traps `R_CORE_FACT` if one does not hold; `--no-facts` turns the fact pass off. It also refuses a copy the source did not write as `E_CORE_HIDDEN_COPY` ([managed memory](../managed-memory.md#written-copies-rule-c)); `SELKA_VERIFY_WRITTEN_COPIES=0` runs it without that check.

The development modes have the [tested debugger limitations](#interactive-debugger-qualification).

### Debug code generation

The lean build compiles each LLVM unit at `-O2` with LLVM's own IR passes off, so a unit keeps the shape Core's passes gave it and its trap sites keep their lines; a few machine-pass switches that cost compile time and bought no run time are off too. A unit of at most 50,000 bytes of LLVM text also gets LLVM's `-O2` IR pipeline. That rule has no option. `--debug-o0`, `--optimize-debug`, `--unoptimized`, `--release`, `selka test`'s default and a bare target compile as before. A trap reports the same text and lines in both builds. When the build, or the lines of a debugger, matter more than the run, `--debug-o0` is the way back.

```bash
selka run app.selka                  # lean debug: Core passes, then -O2 code generation; LLVM's IR passes on units up to 50 KB
selka run app.selka --debug-o0       # the same Core passes at LLVM -O0: the cheapest cold build, slower code
selka build app.selka -o app --debug-o0
selka test tests/ --debug-lean    # a test run on the lean build; tests build at -O0 by default
```

### Effective optimization levels

With the pinned Zig, `zig cc` runs Clang `-O0` for a requested `-O0` and Clang `-O2` for a requested `-O1`, `-O2` or `-O3`, so the `-O3` spelling adds no optimization. Release still enables whole-program LLVM optimization and omits `debug(...)` output from standalone builds. The runtime is always compiled at `-O2`. Recheck the mapping after a toolchain upgrade.

## `selka build`

```bash
selka build FILE.selka -o OUT [--release | --unoptimized | --optimize-debug | --debug-o0] [--link FILE.c]... [--emit-llvm PATH]
             [--emit-certificates DIR] [--cache-dir DIR] [--no-cache] [--local-stdlib] [--zig PATH]
             [--report | --cache-report] [--verify-cache] [--stats]
             [--diagnostics=text|json] [--no-facts | --verify-facts]
             [--verify-ownership] [--verify-facts-static] [--verify-names] [--cpu native|x86-64-v3]
selka build FILE.selka --run [run options] [-- ARGS...]
```

- **The entry** is a single file or a project entry: a module header or an import makes it a project, and the nearest `selka.json` supplies its import policy, limits and roots. `--project` and `--whole-program` are accepted and ask for nothing more.
- **`-o OUT`** writes the executable and creates `OUT`'s missing parent directories. A failed build leaves an existing `OUT` untouched. `OUT` is a hard link to the stored program (a copy across file systems) with no write permission, and a build replaces it by removing it and linking the new program, so a running program is not disturbed. The link carries the stored file's modification time, not the build's, so a `make` rule that wants `OUT` newer than its sources runs the build again (a replay costs a few milliseconds).
- **`--run`** replaces `-o`: the program is built into a private directory, run with `selka run`'s options and exit status, and removed; every value after `--` is the program's.
- **`--link FILE.c`** (repeatable) compiles a C source and links it in ([direct C imports](../c-ffi.md)).
- **`--release`, `--optimize-debug`, `--debug-o0`, `--debug-lean`, `--unoptimized`** select the build mode, on `run`, `run-project`, `build --run` and `test` too.
- **`--local-stdlib`** resolves a standard module name from a file beside the entry before the embedded copy, so you can check a module you are editing without rebuilding the compiler.
- **`--emit-llvm PATH`** also writes the LLVM text; such a build is neither replayed nor recorded.
- **`--diagnostics=json`** prints warnings, errors, refusals and (with `--run`) a trap as `diagnostic-v1` records on stderr.
- **`--zig PATH`** names the toolchain ([toolchain](#toolchain)).

| Status | Meaning |
|---|---|
| 0 | a built program |
| 1 | a check error or an `E_CORE_UNSUPPORTED` refusal |
| 2 | a usage, configuration or tool failure |
| 3 | the project's import policy denies an import |

```console
$ selka build examples/factorial.selka -o /tmp/factorial
$ /tmp/factorial; echo $?
120
$ selka build examples/factorial.selka --run; echo $?
120
```

## Building for another CPU: `--target`

`selka build --target NAME` builds for `x86_64-linux`, the host and the default, or `thumbv6m-none`, an ARM Cortex-M0+ (RP2040 class) with no operating system. An unknown name is refused with status 2 and the list of names. A host build is the same with and without `--target x86_64-linux`.

A `thumbv6m-none` build links an ELF image with the bare runtime, a platform C file and a linker script:

- **`--link PLATFORM.c`** supplies `myl_bare_write`, `myl_bare_exit` and, if it wants, `myl_bare_platform_start`. `scripts/bare/qemu/platform.c` and `scripts/bare/qemu/link.ld` are the ones for QEMU's mps2-an385 board.
- **`--linker-script SCRIPT.ld`** is required for a bare build (without it the build is refused with one line saying what to pass) and refused for a host build.
- The link takes `--gc-sections`, the entry `myl_bare_reset`, no C start files and no C library. `--release` adds `-flto`. A bare build is never replayed.
- A program that needs the host's prebuilt number-text runtime (a float written as or read from text, a format specification, BLAKE3) is refused with `E_TARGET_NUMBER_TEXT`, which names what it used.
- `run`, `run-project`, `build --run` and `test` refuse the target; `scripts/bare/bare_run.py` runs bare programs on QEMU or an RP2040 board and compares them with Linux.

A bare target provides two capabilities, its memory-mapped registers and `Host`. `main(reg: Registers)` receives the registers, and each `registers.read32` or `write32` (and the 8- and 16-bit forms) is one volatile load or store ([register access](../io.md#register-access)). A function only a simulated bank has (`registers.simulated()`, `poke32`, `script32`, `pin32`, the log readers) is refused with `E_TARGET_SIMULATED_REGISTERS`. A `main` that asks for any other capability (`out: Stream`, `fs: Filesystem` and the rest) is refused by `build` with `E_TARGET_CAPABILITY`; `main()` and `main(args: str[])` build as usual. `check` does not take `--target`, and a host build of `main(reg: Registers)` is refused the same way.

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

### The second core: `registers.start_core1`

`registers.start_core1(reg, entry)` starts core 1 of an RP2040 running `entry`, a top-level `func(Registers) -> int`, beside `main`, and answers `True`. It answers `False` (a value, not a trap) when the platform has one core, core 1 was started already, it is called on core 1, core 0's heap has too little room, or core 1 does not answer. Only a device has it: a host build that calls it is refused with `E_TARGET_DEVICE_REGISTERS`. A program that does not call it pays nothing for it.

- **Memory.** Core 1 gets half of the largest free block of core 0's heap at the call: an 8 KiB stack at its top and its own heap below, which is core 1's byte ceiling (`R_MEMORY_BUDGET` past it). Core 0's ceiling drops by as much.
- **Sharing.** No heap value is shared: each core allocates and frees in its own arena. The cores talk through the hardware (the SIO FIFOs and spinlocks, `rp2040.sio` in selka-rp) or a memory window both reach through `Registers`.
- **The log.** Writes to `myl_bare_write` take the platform's lock 0, and every line core 1 writes begins `core 1: `.
- **When `entry` returns**, core 1 writes `core 1: returned N, live blocks L, heap high-water H of C, stack S of T` (L is 0 when it freed everything), checks its stack's painted reserve (`R_BARE_STACK` when it ran past), and waits. When `main` returns, core 1 is stopped.
- **A trap or a fault** on either core ends the program on both, and the platform's `myl_bare_exit` runs once. A trap on core 1 writes its lines, then `core 1: the program ends here`.
- **The platform's hooks** (weak defaults describe one core): `myl_bare_core_register`, `myl_bare_core1_launch(vectors, stack_top, entry)`, `myl_bare_core_stop(core)`, `myl_bare_lock(n)` and `myl_bare_unlock(n)`. QEMU's platform gives none, so `start_core1` answers `False` there.

### A device project: one command

A project describes its device once, in its `selka.json`, and builds it with `selka build F.selka -o OUT` and no other flag. `target` is the target a build uses without `--target`; `devices` names each device with what a build for it needs (`target`, `linker_script`, `links`, `include`, `image`, `uf2_family`); `device` chooses one (`--device NAME` chooses another). Every path is relative to the `selka.json` and may not leave its folder. A command-line flag wins over each setting; `--link` and `--include` add to the device's. Only `build` (without `--run`) reads these keys.

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

- **The image follows the output's name**, or the device's `image` when the name has no `.elf`, `.bin` or `.uf2`: `.elf` is the linked ELF; `.bin` is the raw image (more than 256 MiB is refused, so QEMU's layout, with its vector table at 0 and the rest at `0x20000000`, has no `.bin`); `.uf2` is UF2 blocks of 256 payload bytes with the device's `uf2_family`.
- **`include`** (top level, beside `links`) and `--include DIR` add folders to the include path of every C file the build links; editing a header found there rebuilds. `selka test` puts them on the include path of the C it links too.
- **Refusals** (status 2, `E_PROJECT_CONFIG`, one line naming the `selka.json`): a device name with no entry (`device "pico" names no entry of devices; the devices are qemu, flat`), a path that names no file or leaves its folder (also through a symbolic link), an unknown `target`, an unknown device key, two devices with one name.
- **A package's device** (`"device": "rp2040/ram"`) is built through `selka packages build`; `selka build` alone refuses it with one line that names that command ([packages](packages.md#devices-in-a-package)).

### A device described by its memory (MCU-NOC4A)

A device entry may describe its memory instead of naming a linker script, name a boot stage the compiler holds, and bind the platform's hooks to Selka functions. The compiler then writes the linker script (and the boot stage's 256 bytes), and no C platform file is needed for the layout. `linker_script` and `memory` in one entry are refused; `--linker-script` still wins over a device's `memory`.

| Key | Meaning |
|---|---|
| `memory` | `{"NAME": [ORIGIN, LENGTH]}`: one to sixteen regions that do not overlap. NAME is lowercase letters, digits and `_`. ORIGIN and LENGTH are `"0x..."` or decimal text, LENGTH with an optional `K` or `M`, all below 4 GiB |
| `place` (optional) | `{"vectors": R, "code": R, "data": R}`. By default code and vectors are in `flash` and data (with `.bss` and the heap) in `ram`, or everything in `ram` when there is no `flash` |
| `stack` (needed with `memory`) | `"16K"` at the top of the data's region, or `["8K", "sram45"]` at the top of another region. The heap runs from the end of `.bss` to the stack's limit |
| `boot` | A boot stage name: `"rp2040-read-03h"` (the 256 bytes the RP2040's ROM loads first), sealed with its CRC-32/MPEG-2 at the start of the code's region; the vector table follows at origin + 0x100. An unknown name is refused with the known ones |
| `hooks` | `{"start": "board.start", "write": "board.write", "exit": "board.exit"}` binds the runtime's platform hooks to `MODULE.FUNCTION` of a module the program imports |

A hook is a `@freestanding` function whose first parameter is `Registers`: `start(reg)`, `write(reg, stream: int, address: u32, length: u32)` (read the buffer with `registers.read8(reg, address + i)`), `exit(reg, status: int)` (it must not return), and for the second core `core_register(reg) -> u32`, `core1_launch(reg, vectors: u32, stack_top: u32, entry: u32) -> bool`, `core_stop(reg, core: int)`, `lock(reg, n: int)` and `unlock(reg, n: int)`. Any may take `host: Host` as its second parameter (`exit(reg, host, status: int)`) so it can call C, such as a boot ROM routine through an `@address extern func`.

A hook that is missing, not `@freestanding`, of another signature, or bound twice is refused with `E_DEVICE_HOOK`, one line naming the device, the hook and the function; a C file that defines the same hook symbol fails at the link. Other refusals are `E_PROJECT_CONFIG` lines naming the region, stage or hook: overlapping or zero-length memory, a `stack` that does not fit, an unknown `boot`, a `place` naming no region, an unknown hook.

The RP2040's flash layout and QEMU's, as descriptions:

```json
{"version": 1, "device": "flash",
 "devices": {
   "flash": {"target": "thumbv6m-none", "memory": {"flash": ["0x10000000", "2044K"], "ram": ["0x20000000", "252K"]},
             "boot": "rp2040-read-03h", "stack": "16K", "image": "uf2", "uf2_family": "0xe48bff56"},
   "qemu": {"target": "thumbv6m-none", "memory": {"boot": ["0x0", "1K"], "ram": ["0x20000000", "264K"]},
            "place": {"vectors": "boot", "code": "ram"}, "stack": "16K",
            "hooks": {"start": "board.start", "write": "board.write", "exit": "board.finish"}}}}
```

`selka build prog.selka -o prog.uf2 --device flash` writes the whole flash image, boot stage included.

### C interop on a device

Some of what firmware does is reached only through C on the device: a boot ROM's flash routines, a vendor's driver. A device program calls it as a Linux program calls C ([direct C imports](../c-ffi.md)): an `extern func NAME(host: Host, ...)` declaration, and `main` asks for the `Host`, alone (`main(host: Host)`) or beside the registers in either order (`main(reg: Registers, host: Host)`). The bare runtime hands over the `Host` unconditionally, so `main(host: Host?)` is always `Some`. Each call is a plain call of the C symbol under AAPCS. What `extern func` accepts and refuses is what it does on Linux. The C file is one more `--link` beside the platform's:

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

`debug(...)` writes through the platform's `myl_bare_write` (stream 2) in a plain build; `--release` drops it on every target.

A boot ROM routine has no symbol: its address is read from a table in the ROM at run time. An `@address` extern func calls it through that address ([calls through an address](../c-ffi.md#calls-through-an-address)). The target is a `u32` passed as given, so it is a Thumb address with its low bit set, as the ROM's table holds them, and the address 0 traps `R_FOREIGN_TARGET` before the jump. Nothing is linked for it.

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

## A program for machines other than this one: `--cpu`

A program built for the host is compiled for the machine that builds it (`zig cc -march=native`), so it may use instructions an older machine faults on. `--cpu=MODEL` on `build`, `run`, `run-project`, `build --run` and `test` picks the model:

- `native` is the default: `-march=native`.
- `x86-64-v3` is the AVX2 floor (`-march=x86_64_v3`). The program runs on any x86-64 machine with AVX2, whatever machine built it.

Any other value is refused with status 2 and one line naming the two. The model is part of every key that holds the compiler's flags, so a `x86-64-v3` build is never served by a `native` build's cache or the other way round. `--cpu` is for the hosted target: with `--target thumbv6m-none` it is refused (`native` changes nothing).

```console
$ selka build examples/factorial.selka -o /tmp/factorial --cpu=x86-64-v3; /tmp/factorial; echo $?
120
$ selka run examples/factorial.selka --cpu=bogus; echo $?
selka: unknown --cpu value `bogus`; the values are `native` and `x86-64-v3`
2
```

`zig build -Dcpu=MODEL` builds the compiler itself for another CPU; the two Selka components it ships are always built for `x86-64-v3`.

## Native compile memory

Units compile in parallel, each admitted when its estimated memory fits beside the compiles already running. The budget is at most 1 GiB and a quarter of the memory available, so a small machine keeps its headroom; a single unit whose estimate exceeds it still runs, alone.

## Running a built program

A built executable hands `main(args)` every argument after `argv[0]` unchanged, grants every capability, and exits with `main`'s value `& 0xFF` (1 on a trap). Its runtime options come only from the `SELKA_OPTIONS` environment variable, spelled as on the `selka run` command line and separated by spaces: `SELKA_OPTIONS=--restrict ./app` denies every capability, and `SELKA_OPTIONS=--print-result ./app` prints `main`'s value at exit. See [the native backend](../io.md#the-native-backend) for quoting and errors.

`selka run` builds the same executable with its budgets compiled into `main`: `--max-steps`, `--max-frames`, `--timeout` and `--max-memory` ([runtime budgets](runtime-budgets.md#instruction-and-frame-budgets)). A program built with `selka build -o` carries no step, frame or byte budget and pays nothing for one.

### Ending a run

`selka run`, `run-project`, `build --run` and `selka packages build --command run-project` wait for the program they start, and the program ends with them:

- A SIGTERM, SIGINT or SIGHUP that reaches the compiler alone (a supervisor's `kill PID`, a timeout command) is passed on to the program, and the compiler ends by the signal that ended the program, so a shell reports 128 plus it; a program that exits keeps its own status.
- A signal the terminal sent (Ctrl-C) already reached the program through the process group and is not sent twice. A signal that was ignored when the command started stays ignored.
- A compiler that cannot pass anything on (SIGKILL, a crash) still takes the program with it, and `selka test` starts its test programs the same way. While the program is still being built, a signal ends the build.
- A program that does not declare a `Stop` dies of the signal by the system's default. One that does ([hearing a stop](../io.md#hearing-a-stop)) hears it as `process.stop_requested`, says its goodbye and exits with its own status, which the compiler then exits with. When one signal reaches both compiler and program (a group kill), the program counts one stop.

## Checks in every build

Every build keeps the language's value guards: integer overflow on `+`, `-`, `*` and unary `-`, narrowing integer casts, division by zero, index bounds on lists, fixed arrays, `bytes`, `str` and dictionary position reads, and `pop()` of an empty list. That holds for debug and release builds and for `run`, `build --run` and `test`. A would-be trap is always reported, never undefined behaviour, and optimization never changes a program's result. A release build leaves a guard out only where its facts prove it cannot fire, such as a cast whose source range fits its target; `--verify-facts` keeps those guards and checks the facts instead. The former `--unchecked` policy is refused with a usage error (exit 2) that says so.

## Warnings in the output

A project that has warnings gets them on every `check`, `build`, `run` and `test`, replays included. The default output keeps the diagnostics whole and the text short: a warning is printed in full unless its module is tracked by git and identical to `HEAD`. Those warnings are counted, and the command ends with one line:

```console
$ selka check src/main.selka
numeric.selka:34:5: warning[W_OPTION_TRY]: the `None` arm only returns `None`: ...
check: ok (177 modules, 176 cached)
warnings: 209 in 55 unmodified modules (W_RANGE_CHAIN 56, W_UNUSED_BINDING 53, W_OPTION_TRY 50, W_LITERAL_MATCH 22, W_PATTERN_SHORTHAND 16, ...); `selka check --warnings` lists them
$ selka check src/main.selka --warnings    # every warning, in full
```

- **Printed in full:** a module with uncommitted edits (staged or not), an untracked or ignored one, and any module outside a git repository, so the warnings a change introduced are in front of its author. The rule reads the working tree and `HEAD`, never a cache: a cached check, a replayed build and a `--no-cache` build print the same text for the same tree.
- **Everything back:** `--warnings` (on `check`, `check-project`, `check-module`, `build`, `run`, `run-project` and `test`) or `SELKA_WARNINGS=all`. `--diagnostics=json` always carries every warning, and a project that denies warnings (`lint.warnings: "deny"`) prints all of them when a command fails on them. Errors are never withheld.
- **A directory test run** (`selka test DIR`) ends with one such line for all its entries, each warning counted once.
- **`selka check FILE`** prints the warnings of the file it names and, for each other module it reached that has warnings, one line (`` helper.selka: 3 warnings; `selka check src/helper.selka` ``). `--diagnostics=text` (how `selka fix FILE` checks) brings them all back, and `selka check DIR` prints every warning of every module.
- **Through `selka packages`**, the warnings of a locked package's files are left out and each package gets one line ([packages](packages.md#symbolic-links-repeated-warnings-and-interface-files)).
- **Hints** (`W_COPY_MOVE`, `W_MATCH_ELSE`, `W_MATCH_IS`) are left out of `build`, `run`, `run-project` and `test` and not counted in the closing line. `check`, `check-project`, `check-module` and `lint` print them; `--warnings`, `SELKA_WARNINGS=all` and `--diagnostics=json` bring them back to a build.

## Certificate validators

The ownership pass and the release fact analysis each write down what they relied on, and a validator that shares no code with them checks that record against the final IR before the function is emitted. A program never sees a validator unless it rejects, and a rejection is an internal compiler error, not a diagnostic about the program: it exits 2 and prints `error[E_OWNERSHIP_VALIDATION]` (function, block, instruction, judgment J1 to J8) or `error[E_FACT_VALIDATION]` (function, block, value, check F1 to F7), with a note naming `--no-validate`. With `--emit-certificates` the build keeps going so the certificate exists to inspect, and fails at the end.

| Flag or command | What it does |
| --- | --- |
| `--no-validate` (`build`, `run`, `build --run`, `run-project`, `test`) | runs no validator that no flag asks for: the way out of a validator's fault. Its records say they were not validated, and it publishes nothing to the stage store's shared half |
| `--verify-ownership` (`build`, `run`, `test`) | validates the ownership certificate and the IR of every function, in any compiler; prints `selka: ownership: N functions validated, M unchecked` |
| `--verify-facts-static` (`build`, `run`, `test`) | validates the fact tables against the final IR; prints `selka: facts: N functions validated, ...` |
| `--verify-names` (`build`, `run`, `test`) | replays the op log of lowering into an empty module, which must equal the one lowering built; prints `selka: names: N segments replayed, ...` |
| `--emit-certificates DIR` (`build`, `test`) | writes the ownership certificates, `program.fact-certificate` when facts were computed, and `program.core-ir`, the final IR as text |
| `selka validate-certificates PATH`, `selka validate-fact-certificates PATH [--detail]`, `selka verify-ir PATH` | the validator's or the IR verifier's verdict on each function of the certificate or `program.core-ir` files under `PATH`; `--detail` lists what it assumed or left unchecked |
| `selka mutate-certificates FILE OUTDIR`, `selka mutate-fact-certificates FILE OUTDIR` | write single-edit fault mutants of an accepted certificate, for the gate's fault-injection checks |
| `--stats` (`build`, `run`) | among its lines, `selka: union-tags: N payload reads not justified by a tag test` and `selka: construct-reads: N constructors read a borrow they neither own nor lend`: builds count them, the gate refuses them |

```console
$ selka build prog.selka -o prog --stats
selka: union-tags: 0 payload reads not justified by a tag test (counted in builds, refused by the gate)
```

When a validator runs without being asked for:

- **Every compiler validates every guest build by default** (`build`, `run`, `build --run`, `run-project` and `test`, in every mode): the IR verifier, the ownership validator, and the fact tables of a build that computed them (a `--release` build). A body served from a record was checked by the build that made the record.
- **A Debug compiler** (a plain `zig build`) also validates every body present and the op log of every build that restored no lowering artifact.
- **The hidden-copy check** (`E_CORE_HIDDEN_COPY`, rule C of [managed memory](../managed-memory.md#written-copies-rule-c)) runs in every guest build under the same policy. It counts frame blocks and dictionary-key copies and refuses neither; `--stats` prints its census ([cost](cost.md#allocation-and-copy-sites)).
- **`--verify-facts` and `--verify-written-copies`** make any compiler validate both, and run the hidden-copy check even under `--no-validate`. **`--no-validate`** turns the rest off; an explicit flag still runs its validator.

The complete gate runs the validators over the whole test corpus and ties them to the Lean checkers; a plain `zig build test` skips those and says so (`-Dproofs=true` runs them). See `docs/tooling/ownership-certificates.md` and `docs/tooling/fact-certificates.md`.

## Trap reports

A trap prints its source position, code, message and call trace, innermost first, on stderr, and the program exits 1:

```console
$ selka run trap.selka
trap.selka:2:12: error[R_LIST_BOUNDS]: native execution failed (index 5, length 3)
  in pick at trap.selka:2:12
  in main at trap.selka:6:12
```

The text is the same in debug and release builds, including for a function LLVM inlined. The runtime also writes one machine-readable `SELKA-TRAP` record after the text, which `selka run` hides and `--diagnostics=json` turns into the `trap_detail` of a `diagnostic-v1` record ([runtime diagnostics](../io.md#runtime-diagnostics)). `--max-frames` bounds the call depth.

When the site is in the standard library (a path starting `@stdlib/`), the first line names the nearest frame outside it, the program's own call, and the library frame follows as the first `in` line, as context:

```console
$ selka run find.selka
find.selka:4:12: error[R_TEXT_BOUNDARY]: native execution failed (offset 1, length 3: inside a multi-byte character; ...)
  in strings::find at @stdlib/strings.selka:128:18
  in find::find_from at find.selka:4:12
  in find::main at find.selka:8:16
```

The first line keeps its shape (`FILE:LINE:COL: error[CODE]: ...`) and every frame its `in NAME at PATH:LINE:COL` form. `--diagnostics=json` puts the program's call in the record's `location` and every frame, the library's first, in its `stack`.

## Interactive debugger qualification

The emitted debug information describes functions, call sites and trap locations. It contains no source-variable declarations or variable locations, so preserving trap reports does not mean full source-level debugging.

- Function and call-site breakpoints work in `--unoptimized` and `--debug-o0` builds; the optimized builds can remove small helpers, which then have no named function.
- Statement `step` and `next`, and the inspection of arguments and locals, are not supported in any mode.
- A release build has no compiled code for most source lines: a line breakpoint relocates or never binds.
- The lean build keeps line tables, but a line whose code the instruction selector merged away has no row, so a breakpoint on it does not bind; `--debug-o0` has them all. Trap messages carry the same text and lines in every build.

## The caches

A build keeps three layers of store. Every key is a BLAKE3 digest over the complete input of what it names, so a hit cannot serve a wrong object, and a damaged entry is recompiled rather than used.

| Layer | Where | Serves | Bound |
|---|---|---|---|
| the work directory | `--cache-dir DIR`, else `.selka-cache/core` | one project's records: front end, stages, programs, replay | `SELKA_CACHE_TIERS_CAP_GB`, 10 GiB |
| the per-user object store | `SELKA_CORE_RUNTIME_CACHE`, else `$XDG_CACHE_HOME/selka/core-runtime`, else `~/.cache/selka/core-runtime` | compiled unit and runtime objects, for every project and worktree | 10 GiB |
| the shared per-user stores, on by default | `compiler-artifacts`, `stage-artifacts` and `native-tests` under `$XDG_CACHE_HOME/selka` or `~/.cache/selka` | what another worktree built: front-end records and linked programs ([shared compiler artifacts](#shared-compiler-artifacts)), stage records ([the shared stage store](#the-shared-stage-store)), test verdicts ([guest tests](guest-tests.md#reusing-unaffected-results)) | 10 GiB, 4 GiB and 256 MiB; `selka cache gc\|configure --kind compiler\|stages\|tests` |

- `--no-cache` uses none of the work directory and the shared stores, and does use the object store ([which store a cold build uses](#--verify-cache-and---no-cache)).
- A work directory a build creates gets a `.gitignore` of `*` and a `CACHEDIR.TAG`, so `git add -A` does not commit the cache; a `--cache-dir` folder that already existed gets neither.
- A project's `selka.json` can name the object store, the shared stores, their parent (`XDG_CACHE_HOME`) and the temporary folder in a `stores` object. Precedence for each: a flag, then the variable (empty means off), then the file, then the default. `selka cache where ENTRY` prints where each resolved and what decided it.
- An empty `SELKA_COMPILER_SHARED_CACHE`, `SELKA_STAGE_SHARED_CACHE` or `SELKA_TEST_SHARED_CACHE` switches the matching shared store off; a non-empty one names another. `selka test` also takes `--shared-cache-dir DIR`. A build without the stores produces the same program, only slower to start.
- An identical build replays: the next identical build copies the recorded program without checking, lowering or starting a process (`"program":"replayed"`). Each entry and settings keep the records of the four builds used last, so undoing an edit or switching back to a branch still replays. `--verify-cache` bypasses replay.
- The compiler sweeps a work directory at most once every ten minutes, oldest whole files first, until its tiers total at most `SELKA_CACHE_TIERS_CAP_GB` GiB (default 10; `0` turns the sweep off). Linked programs keep at most four per optimization level.
- `SELKA_STAGE_CACHE_COMPRESSION=zlib` compresses stage records (the default is none); `SELKA_ENGINE_DECIDE_LOWERING=0` turns off the lowering-assembly record.
- `scripts/core_store_gc.py` collects the per-user object store to 10 GiB counted in disk blocks:

```bash
python3 scripts/core_store_gc.py --store ~/.cache/selka/core-runtime            # a dry run: what would go, in blocks
python3 scripts/core_store_gc.py --store ~/.cache/selka/core-runtime --apply    # what the timer does every 15 minutes
```

## Shared compiler artifacts

Compatible worktrees can share immutable front-end artifacts and linked programs through `SELKA_COMPILER_SHARED_CACHE`. Each worktree keeps its own private cache and executable copies; installation and use need no Python.

```bash
export SELKA_COMPILER_SHARED_CACHE="$HOME/.cache/selka/compiler-artifacts"
selka build app/main.selka -o app.bin --cache-dir .selka-cache/private --report
```

- **Location.** A non-empty variable names an explicit store, an empty one disables sharing, and an unset one selects the per-user default, `$XDG_CACHE_HOME/selka/compiler-artifacts` or `~/.cache/selka/compiler-artifacts`. A default store that cannot be created is skipped quietly. One that exists but cannot be opened prints one `warning:` line that names the repair, and the command builds without sharing; an explicit store that cannot be opened fails the command.
- **A hit** still performs front-end validation, lowering and emission, then copies the verified program through the private store. When the object store also hits, no compiler or linker process starts, and `cache-report-v1` reports `program: "reused"`, `program_shared: true`, zero `compiled` and zero `processes`.
- **`--no-cache` and `--verify-cache`** disable all shared lookup and publication. A corrupt record causes correct fresh work.
- **Same bytes in two checkouts.** An entry built without a project root (no `selka.json`) names itself by its basename, so two checkouts building it by the same relative spelling link identical programs; an absolute spelling changes the bytes and misses. Foreign `--link` inputs and unqualified tools do not use shared programs.
- **Mismatches.** When the store holds a verified program with different bytes under the same key, the build keeps its own program, publishes nothing and appends one line to `compiler-artifacts-v2/mismatches.log`, counted as `shared_mismatches` in the report ([Reports](#reports)). A non-zero count is a determinism bug to investigate.

```text
mismatch program <key> existing=<digest> attempted=<digest>
```

See `docs/tooling/cache-retention.md` in the compiler repository before deleting entries.

## The shared stage store

The stage records (lowered, optimized and emitted work) are shared between worktrees through the per-user store `stage-artifacts-v1`. A fresh worktree of a project another worktree built starts from those records, so its first edit costs about a warm edit instead of ten times as much; the price is a few percent more work on warm edits, because the store keeps more packs to index. `SELKA_STAGE_SHARED_CACHE` selects the root:

```bash
export SELKA_STAGE_SHARED_CACHE="$HOME/.cache/selka/stage-artifacts"   # the default, set only to name another
selka build app/main.selka -o app.bin --report
selka cache gc --shared-cache-dir "$HOME/.cache/selka/stage-artifacts" --kind stages --max-bytes 2147483648
```

- An unset variable selects the per-user default, `$XDG_CACHE_HOME/selka/stage-artifacts` or `~/.cache/selka/stage-artifacts`; an empty value disables the store, and each work directory then keeps its stage records privately. `--no-cache` and the fresh pass of `--verify-cache` never read or publish it.
- A build collects the store when ten minutes have passed since the last collection, to 4 GiB by default (`selka cache configure --kind stages --max-bytes N` sets the cap). A collection keeps every record a worktree's last build used and every pack younger than 14 days, and evicts the rest oldest first when over the cap. `selka cache gc --kind stages` previews it; `--apply` collects now. The policies are in `docs/tooling/cache-retention.md`.

## Reports

| Flag | What it prints |
|---|---|
| `--report` (`build`, `build --run`, `run`, `run-project`) | one `cache-report-v1` JSON line on stderr: units linked, served by the object store, compiled and verified, tool processes started, and whether the program was `linked`, `reused` from the program store or `replayed` (every count 0) |
| `--cache-report` | the same as one `selka-core: cache:` text line, ending `; N shared mismatches` only when that count is not zero |
| `--stats` | what the release passes did: calls inlined, loops unswitched, versioned and vectorized, checks proved, in-place updates, deterministic drops and lists promoted to the stack |
| `--timings` (`run`, `run-project`, `build --run`) | `timings: native_ns=N`, the program's own run time with the build excluded |
| `selka dump-ir FILE.selka [--facts]` | the Core IR (with `--facts`, after the release passes, with intervals); `--emit-llvm PATH` writes the LLVM text |
| `--emit-certificates DIR` | the certificates of the final IR ([certificate validators](#certificate-validators)); such a build is neither replayed nor served from the optimizer caches |

The `cache-report-v1` line also carries `program_shared` (an actual shared linked-program restore), `shared_mismatches`, a `link` object with the link step's wall nanoseconds, and a `unit_timings` array with each unit's name, source path, kind, content key, `action` (`compiled`, `reused` or `verified`) and `compile_ns` (null when reused). Parallel unit intervals overlap and must not be summed.

After a one-line edit to one module of a three-unit program, and again unchanged:

```console
$ selka build app/main.selka -o app --report
{"version":"cache-report-v1","program":"linked","units":3,"reused":2,"compiled":1,"verified":0,"processes":2}
$ selka build app/main.selka -o app --report
{"version":"cache-report-v1","program":"replayed","units":0,"reused":0,"compiled":0,"verified":0,"processes":0}
```

The old back end's `qbe-build-v1` and `work-report-v1` build reports, `--timings=json` and `--explain-invalidation` are refused on `build`, `run` and `test`. The front-end commands (`check`, `check-project`) still print `frontend-cache-v1`, `work-report-v1` and `invalidation-report-v1`.

## `--verify-cache` and `--no-cache`

**`--verify-cache`** recomputes what the stores served and fails the build, naming the unit, when it differs. It never replays or uses the shared compiler-artifact tier. It checks two things:

- **The stage records.** The command builds as usual up to its emitted LLVM units, then builds again without any cache and compares the units' LLVM text. A unit whose text differs, or that only one build made, is an error line naming its kind (`module`, `generic`, `helper`, `entry`, `program`), name and source file, and the build exits 2: a stage record was served under a key that does not cover its inputs. To find the function, build with `--emit-llvm a.ll` and with `--emit-llvm b.ll --no-cache` and compare the files.
- **The objects.** Every unit the object store served is compiled again, and a fresh object whose bytes differ fails the build.

**`--no-cache`** (on `build`, `build --run`, `run`, `run-project` and `test`) is a cold build. It builds through an empty private work directory that is removed when the command ends, and neither reads nor publishes any record of an earlier build. Status, output and diagnostics are those of the same command with caches. Three stores it still uses hold objects, not records of a build:

| Store | With `--no-cache` |
| --- | --- |
| the work directory, the shared compiler-artifact tier, the shared stage store and the shared test-receipt store (`selka test --no-cache`) | not read or published; a directory a variable names is not even created |
| the per-user object store (`SELKA_CORE_RUNTIME_CACHE`) | **used**: an object is keyed by the exact text it was compiled from, the toolchain's identity and the settings, and is served only when its bytes match their recorded digest, so it cannot be stale |
| the toolchain's identity memo (`core-tools-v1`) | **used**: it holds the digest of the files the pinned `zig` reads, validated on every call, and no build result |
| Zig's global cache for the libc stubs and compiler-rt (`zig-global`) | **used**: a build product of the toolchain |

A `--no-cache` build is as slow as a first build on a machine whose object store is warm. Use it when a cached result is in doubt, and `--verify-cache` when the question is which stored record is stale. `selka check --no-cache`, `fix --no-cache` and `cost --no-cache` open no shared stage store either.

```console
$ selka build app/main.selka -o app --verify-cache --cache-report
selka-core: cache: 3 units, 3 reused, 0 compiled, 3 verified; program reused; 3 processes
$ selka run app/main.selka --no-cache
```

## Which compiler this is: `--version`

`selka --version` (or `selka version`) prints one line and exits 0: the commit the installation was made at, the compiler's identity, the build mode, the Zig that built it and the target.

```console
$ selka --version
selka commit 11419ef271ab, identity 9f2c4e1a7b30, debug, zig 0.17.1, x86_64-linux
```

The **identity** (the first twelve digits) is the digest that keys every cached result: the compiler's sources, the Zig toolchain, the optimization mode and the bytes of every product `build.zig` embeds. Two builds with one identity share every cache, so a commit that changes only a guide, a test or `CHANGES.md` prints the same identity as its parent.

The **commit** is deliberately not inside the compiler, since a commit hash among the digested bytes would empty every cache at every commit. The install step (`zig build`, with or without `--prefix`) writes `selka.commit` into the directory of the executable: `commit HASH` and `tree clean` or `tree dirty`. A dirty tree (a modified or staged tracked file, or an untracked file under `src`) shows as `commit 11419ef271ab+dirty`. A compiler copied without its file, built outside a git checkout, or with a file that names no commit prints `commit unknown`.

```bash
selka --version
cat "$(dirname "$(command -v selka)")/selka.commit"
```

## Toolchain

### Finding Zig

Selka drives Zig (`zig cc`) to compile and link every program. It takes the first of these that is set (an empty variable counts as not set):

1. `--zig PATH` on the command line;
2. the `SELKA_ZIG` variable;
3. the Zig the release bundles, `lib/selka/zig/zig` in the folder above the one that holds the running `selka` (`PREFIX/bin/selka` finds `PREFIX/lib/selka/zig/zig`, through any link);
4. the `ZIG` variable;
5. `zig` on `PATH`.

The release download holds the official Zig 0.17.1 at the third place, so a machine with no Zig needs nothing else; from a source build there is none, and the Zig on `PATH` or named by `SELKA_ZIG` is used. With none found a command says `error: no Zig found: install Zig 0.17.1 from https://ziglang.org/download/ ...`. `selka native show` prints the one in use on its `toolchain:` line:

```console
$ env -i HOME=$HOME PATH=/usr/bin:/bin selka native show | grep -E '^(toolchain|reuse):'
toolchain: /home/you/.local/lib/selka/zig/zig
reuse: on
```

The bundle keeps Zig's `lib/` folder whole, because the toolchain identity reviews that tree and turns reuse off for a trimmed copy. `zig build release -Doptimize=ReleaseFast -Dbundle-zig=DIR` makes the bundle (`DIR` is an unpacked official Zig 0.17.1 distribution) under `zig-out/release/`.

### The toolchain's identity

A build's toolchain identity covers the `zig` executable's content, each library root, the runtime and discovery inputs and the native CPU, and it is part of every key. A toolchain that cannot be proved to be the approved Zig distribution still builds, but its objects stay in the build's private directory and nothing is cached or replayed. An edit inside an installed toolchain moves the identity. The link always runs in `/` with absolute paths, so programs linked from identical objects are byte-identical wherever the project and the work directory were. `ZIG_GLOBAL_CACHE_DIR` does not reach the Zig global cache such links use (`$XDG_CACHE_HOME/selka/zig-global`).

## System libraries

A built program loads files of the machine: the loader (`/lib64/ld-linux-x86-64.so.2`), libc, libm, libgcc_s and libpthread, and whatever `/etc/ld.so.preload` names. Their path, resolved path and bytes go into the toolchain identity that keys every native result, so every machine reuses results under keys of its own and nothing is approved. The keyed set is a superset of every file the loader could load: a file left out would be a result reused under bytes it was not built with, and a file too many only costs a cold build now and then. A file that cannot be read is keyed as unreadable, and no build fails on it.

- **The first build on a machine** is cold and the second reuses, with no step in between.
- **A library update** (a glibc security fix) makes the next build cold once for native results; stage records stay warm. The collector removes the old entries after 14 idle days.
- **A preload file** keeps reuse on; each file it names is keyed like a library. An entry that cannot be keyed soundly (a relative path, another `$` token), a cache or preload file larger than 64 MiB, or more than 4096 candidate files turns reuse off, and `selka native show` says why. `LD_PRELOAD`, `LD_LIBRARY_PATH` and the other loader and compiler overrides turn reuse off too.
- **Two machines sharing a store** (a network folder) never serve each other's results unless their toolchain identities are the same.

`selka native show` prints the closure as builds key it, its digest, the toolchain identity every native key holds, and whether results are reused here and why not. `--zig PATH` names the toolchain; `--digest` prints the toolchain identity alone.

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

`selka native approve` and `SELKA_NATIVE_APPROVALS` are no longer needed: the command prints that and exits 0, and nothing reads the variable.

## Where to look when a build is slow

- **Every build compiles.** Run it twice with `--report`. An unchanged build says `"program":"replayed"`. If it does not, something the build reads changes between runs: a generated file, an embedded asset, the environment, or a `--link` source whose header changed while it compiled.
- **An edit compiles many units.** A debug build recompiles each unit whose text changed: the edited module's, plus any unit that inlined a changed public helper. A release build always recompiles the whole program, so iterate in debug.
- **The first build on a machine** builds Zig's C library stubs once per toolchain and the core runtime object once per user; a fresh `SELKA_CORE_RUNTIME_CACHE` pays the second again, and a fresh cache home both.
- **Checking dominates.** `selka check FILE.selka --report` shows what the front end reused.
- **Tests are slow.** Each test file builds its own program; see [guest tests](guest-tests.md#reusing-unaffected-results) for receipts and `--jobs`.

## Build programs: `selka do`

A project's procedures (its checks, its image builds, its runs on an emulator or a board) are a Selka program, `build.selka`, as Zig's are `build.zig`; facts stay data in `selka.json`. `selka do STEP [ARGS...]` finds `build.selka` in the working folder or the nearest folder above it and runs it as `selka run build.selka -- STEP ARGS...` would, with that folder as the working folder:

```console
$ cd ~/work/selka-rp/packages/rp2040
$ selka do check
$ selka do image blink --release
$ selka do all --board
```

The program is told what it would otherwise guess, in its environment only: `SELKA`, the path of the compiler that started it; `SELKA_ZIG`, the Zig that compiler uses; and `SELKA_PROJECT_ROOT`, the folder of `build.selka`. [`buildkit.locate(env)`](../standard-library.md#buildkit) reads the three. Everything after `do` goes to the program after `--`, `--help` included, and `selka do` alone passes no arguments. The program's exit status is `do`'s. With no `build.selka` in the working folder or above it, `do` prints `selka do: no build.selka in FOLDER or any folder above it` and exits 2. `build`, `run` and `test` keep their meanings.

## Retired build controls

The old back end's controls are refused with status 2 and a one-line reason: `--backend`, `--llvm-opt`, `--lto`, `--keep-symbols`, `--step-accounting`, `--gc-runtime`, `--gc-stress`, `--rc-runtime`, `--legacy-sharing`, `--value-semantics`, `--library`, `--provider`, `--link-library`, `--library-path`, `--explain-ownership` (use `--stats`), and the commands `emit-qbe`, `emit-project-qbe`, `emit-runtime`, `dump-bytecode` (use `dump-ir`), `compile-module`, `link-modules` and `invoke`. `--qbe PATH` is accepted and ignored.

The internal test switch `SELKA_CORE_SANITIZE=thread` (or `address`) instruments every emitted LLVM function, the native runtime and linked C sources with ThreadSanitizer (or AddressSanitizer). It has no CLI flag; other values are rejected, and sanitized and ordinary objects never mix in a cache. AddressSanitizer guest tests use `--max-memory 0`.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/native-build.md).
