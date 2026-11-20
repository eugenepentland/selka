# Changes

Breaking changes to the language and the standard library, newest first. From the stage-2 EDA
port on, each one ships with a certain `selka fix` migration, so running `selka fix` with the
new compiler moves a project across with no hand edits (roadmap §4.H, requirement R-6).

## Unreleased (after 0.1.0)

### The friction harvester is in `tools/friction/` (lane GH-7.5, 19 November 2026)

Not breaking: no program, diagnostic or output changes. `velocity/friction/` (`harvest.py`, `classifier.json`, `README.md` and the sample log
`session-2026-09-20.jsonl`) moved to `tools/friction/`, so the repository builds and passes its gate without the `experiments/` and `velocity/` folders. Run
`python3 tools/friction/harvest.py LOG`; `--friction-log=PATH` and `SELKA_FRICTION_LOG` are unchanged.

### Fixed: a compiler built with `-Doptimize=ReleaseFast` crashed on every `selka run` and `selka build` (lane GH-7.3, 19 November 2026)

A ReleaseFast compiler built from the tree of 19 November (after the device `hooks` change, MCU-NOC4A) ended with a segmentation fault on the first `selka run`,
`selka build` or `selka build --release` of any program, three-line hello world included; `selka check` was not affected, and a Debug compiler never was.
The list of roots a build starts from (`main`, then a device's hooks) was a pointer into a stack frame that had already returned, and the optimised compiler
read the slot again after other code had reused it. The list is now allocated in the build's arena. A compiler built from the tree of 19 November in
ReleaseFast mode before this change should be rebuilt; nothing else is needed.

### `--cpu=x86-64-v3` builds a program for any AVX2 machine, and the release's components are built that way (lane GH-7.4, 19 November 2026)

Not breaking: with no `--cpu` every build passes the flags it always did and keeps every cache key. New: `selka build`, `run`,
`run-project`, `build --run` and `test` take `--cpu=native` (the default, `-march=native`: the machine that builds) or
`--cpu=x86-64-v3` (`-march=x86_64_v3`, Zig's spelling of the AVX2 floor, the other flags as they are); any other value exits 2 with the one line
``unknown --cpu value `X`; the values are `native` and `x86-64-v3` ``. The model is in every key that holds the flags (unit objects,
the runtime object, the linked program, the replay record of an identical build, test receipts), so neither model is ever served
the other's build. `zig build` now compiles the two Selka components in `libexec/selka/components` with `--cpu=x86-64-v3`, plain
or `release`, so a bundle built on an AVX-512 runner runs on an ordinary AVX2 desktop, and their receipts name the model instead of
the builder's `/proc/cpuinfo` (the next `zig build` rebuilds them once). See `docs/tooling/native-build.md`, "A program for
machines other than this one: `--cpu`".

### The compiler finds the Zig bundled in its install, and `zig build release` makes the download (lane GH-7.1, 19 November 2026)

Not breaking: no program, diagnostic or output changes, and a plain `zig build` is as it was. The compiler looked for the Zig it drives
in `--zig`, `ZIG`, `SELKA_ZIG` and `PATH`; it now looks in `--zig`, `SELKA_ZIG`, the Zig bundled at `lib/selka/zig/zig` beside the
install (the folder above the one that holds the running executable, links resolved), `ZIG`, then `PATH`. Only a machine that sets both
`ZIG` and `SELKA_ZIG` to different Zigs sees a difference (`SELKA_ZIG` now wins), and an empty variable now counts as not set. With no Zig
found a command adds `error: no Zig found: install Zig 0.17.1 from https://ziglang.org/download/ ... or use the Selka release that bundles it`
to `cannot identify guest toolchain: ToolNotFound`, and `selka native show` prints a `toolchain:` line with the Zig in use. New:
`zig build release -Doptimize=ReleaseFast -Dbundle-zig=DIR` (DIR an unpacked official Zig 0.17.1) assembles
`zig-out/release/selka-0.1.0-x86_64-linux/` and its `.tar.xz`, with `bin/selka`, the components, Zig whole under `lib/selka/zig`, the
licenses and `install.sh`, and refuses a Zig the compiler would not accept for cache reuse; `-Dcpu=MODEL` builds the compiler for a
CPU model other than the machine's (the release workflow passes `x86_64_v3`). `.github/workflows/release.yml` builds and attaches the
download on a `v*` tag. `THIRD-PARTY-NOTICES.md` lists Zig's licenses and the third-party code in the sources.

### The language is called `selka` now: the command, the suffixes, the project file, the variables and the directories (lane GH-5.3, 19 November 2026)

Breaking, for every project and every script that names the old spelling. What changed for a user:

- The command is `selka` (was `mylang`): `bin/selka`, `libexec/selka`, `selka.commit`. The compiler's own output lines that began `mylang-core:` begin
  `selka-core:`.
- Source files end in `.selka` (was `.my`), module interfaces in `.selkai` (was `.myi`), test files in `_test.selka`. The project file is `selka.json`
  (was `mylang.json`). The work directory is `.selka-cache` (was `.mylang-cache`); the per-user directories are `~/.cache/selka`, `~/.config/selka` and
  `~/.local/state/selka`. Every cache identity changed with the names, so the first build and the first test run after the change are cold.
- The variables begin `SELKA_` (was `MYLANG_`) and `SELKA_CORE_` (was `MYL_CORE_`): `SELKA_JOBS`, `SELKA_OPTIONS`, `SELKA_MEMORY_LIMIT` and the rest. The
  test runner's flags are `--test-shard=`, `--test-shard-plan`, `--test-filter=`, `--test-list=` and `--test-announce-filter=`, its variables
  `SELKA_TEST_*` and its output lines begin `test:` (were `--guardian-shard=` and the others, `GUARDIAN_TEST_*`, `guardian/test:`).
- A documentation block is tagged ```` ```selka ```` (was ```` ```mylang ````; the short tag ```` ```my ```` is gone) and opts out with `# doc: not-selka`
  (`# doc: not-mylang` still works).

A project crosses with `python3 scripts/rename_to_selka.py --project DIR`: it renames the sources, interfaces and project file, rewrites the names inside
them and in the scripts and documents of the project, and keeps the old work directory's line in `.gitignore` beside the new one. Run it on a clean
checkout and read the diff; `--project DIR --report` first lists what it would change and changes nothing.

None of the old spellings is honoured and no fallback reads them, but each one gets one line for one release. `selka check main.my` (any command given a
file that ends in `.my`) says source files end in `.selka` now and names the crossing command, and exits with status 2. A folder that holds `mylang.json`
and no `selka.json` says the project file is `selka.json` now, and exits with status 2. When a variable that begins `MYLANG_` or `MYL_CORE_` is set and
its `SELKA_` spelling is not, the compiler writes one line on standard error, once per process, naming the first such variable in sorted order, its new
spelling and how many more there are, and goes on. A built program ends with status 2 before `main` runs, with one line on standard error, when
`MYLANG_OPTIONS` or `MYLANG_MEMORY_LIMIT` is set and its `SELKA_` spelling is not: these two carry `--restrict`, the grants and the memory ceiling, and a
program that ignored them would run with more rights than its user asked for. `selka run` and `selka test` run built programs and end the same way.

The names inside built programs did not change: the runtime's symbols (`myl_...`) and C macros (`MYL_...`), the guest symbols (`my.NAME`) and the
debug-info producer (`mylang-core`) keep their spelling, so a project's own C functions named `selka_*` stay accepted. The entries below this one describe
the compiler of their day and keep the old names.

### The product's names live in `src/product.zig`, and the code that computes with them reads them there (lane GH-5.1, 19 November 2026)

Not breaking: no program, diagnostic, file name or output changes. The command name, the source suffix (`.my`), the interface suffix
(`.myi`), the test-file suffix, the project file name (`mylang.json`), the work directory (`.mylang-cache`), the per-user directory
name (under `~/.cache`, `~/.local/state` and `libexec`), the commit file, the variable prefixes, the documentation fence tags and the
`not-mylang` marker, and the guest symbol prefix are now named constants in one file, with the helpers that test and strip a suffix
(the helpers take the suffix as an argument, and `src/product_test.zig` checks them with a six-character one). About 200 places
in 90 files that spelled `.my` or `.mylang-cache`, joined `~/.cache/mylang` by hand, assumed a three-character suffix (`len - 3`), or kept their
own copy of the fence tag list now go through it, so the rename of the language to `selka` changes these constants and no line that
depends on the old spelling's shape. Whole names inside messages, documents, tests' expected output and whole variable names such as
`MYLANG_ZIG` stay literal text, so a search for the full name still finds them.

### A package's device may carry its description: `memory`, `place`, `stack`, `boot` and `hooks` (lane MCU-NOC4E, 19 November 2026)

Not breaking: a package's `devices` entry took only the old keys (`target`, `linker_script`, `links`, `include`, `image`,
`uf2_family`) and the staged entry dropped `memory`, `place`, `stack`, `boot` and `hooks`, so a board's description lived in every
application's `mylang.json`. A package's entry now holds them, checked as a project's are when the package is locked and built
(`mylang packages lock` refuses `library/mylang.json: device "virt": unknown hook "begin"`), recorded by the lock in a new
`device_descriptions` object beside `devices` (a package with no described device writes none, so an old-style device locks exactly
as before and a lock written before still builds), and staged into the snapshot's entry unchanged. A description edited after
locking is refused as an edited file is: `locked dependency changed: qemu (its device virt: the stack key)`. A hook names
`MODULE.FUNCTION` as the program imports the module (`qemu.board.start`). A device that names no file (no `linker_script`, `links`
or `include`) holds no C, so an application building for it needs no `allow_links`. See
[devices in a package](docs/tooling/packages.md#devices-in-a-package).

### Two devices of one project keep their own `start` hook in a plain build (lane MCU-NOC4D, 19 November 2026)

Not breaking: a fix. The cache key of the entry unit's text, and of its compact receipt, named a device's hooks but not the Selka
functions they bind. Building one program in a plain (not `--release`) build for two devices of one `mylang.json` whose hooks bind
different functions, through the same stores, therefore reused the first device's entry unit: the second link failed with
`undefined hidden symbol` when the first device's function was reached from nowhere else, and when `main` called both functions the
second image ran the first device's hook without any error. Both keys now bind each hook's function (its name, signature and
symbol); a program without hooks keys exactly as before.

### A device hook may take `Host`, so it can call the boot ROM (lane MCU-NOC4C, 19 November 2026)

Not breaking: a device hook (`hooks` in `mylang.json`) may take `host: Host` as its second parameter, after `reg: Registers` and before
its own parameters, for any of the eight hooks, so it can call C through an `@address extern func` (a boot ROM routine found in the ROM's
table). The C-ABI function the compiler writes passes the `Host` token `main(host: Host)` gets. A hook without `host` checks and builds as
before; a `Host` in another place or a second one is `E_DEVICE_HOOK`, whose message now shows both accepted forms. See
[a device described by its memory](docs/tooling/native-build.md#a-device-described-by-its-memory-mcu-noc4a).

### `cpu` in freestanding code, and RAM code in an image that runs from RAM (lane MCU-NOC2F, 19 November 2026)

Not breaking: code accepted before is accepted. A `@freestanding` or `@freestanding(ram)` function may now call the
`cpu` functions that act on the machine (`wait_for_event`, `wait_for_interrupt`, `send_event`, `barrier`, `breakpoint`,
`interrupts_off`, `interrupts_restore`): on a device each is its instruction inline, plain and `--release`, in the RAM code
itself; on Linux each records on the simulated bank as from ordinary code. The bank's readers (`event_count`,
`interrupts_are_off` and the rest) are still refused there, by name. The image check of `@freestanding(ram)` counts a
section as RAM when it lies within the initialised data (`__data_start` to `__data_end`) as well as when it is writable or
loaded elsewhere, so an image that runs from RAM, whose `.data` holds only `.ramfunc` code, no longer needs a dummy
initialised word to build; a `.ramfunc` left in `.text` or in flash is still refused. Docs:
[Code that runs from RAM](docs/functions.md#code-that-runs-from-ram).

### A device's start-up from its description: `memory`, `stack`, `boot` and `hooks` (lane MCU-NOC4A, 19 November 2026)

Not breaking: a `devices` entry of `mylang.json` may describe its memory (`memory`, `place`, `stack`) instead of naming a linker
script, name a boot stage the compiler holds (`boot`: `rp2040-read-03h`, sealed with its CRC-32 and written as a `.boot2` section),
and bind the platform's hooks (start, write, exit, the second core's five) to `@freestanding` Selka functions that take `Registers`
(`hooks`). The generated script gives the sections and symbols of `selka-rp`'s `link.ld` for the RP2040 and of `scripts/bare/qemu/link.ld`
for QEMU. `linker_script` and `memory` in one entry are refused; every existing key and flag builds what it built. A hook that is missing,
not freestanding or of another signature is refused with the new `E_DEVICE_HOOK`. See [a device described by its memory](docs/tooling/native-build.md#a-device-described-by-its-memory-mcu-noc4a).

### `@freestanding(ram)`: a function placed in RAM, proved to reach nothing in flash (lane MCU-NOC2B, 19 November 2026)

Not breaking: a program with no `@freestanding(ram)` function is checked, emitted and linked as before. The placement
`ram` (the only one; another word is `E_FREESTANDING`) puts the function's code in the section `.ramfunc` on a device,
with no jump table; the device's linker script loads that section into RAM with the initialised data, as
`scripts/bare/qemu/link.ld` now does. On the host it changes nothing. A `ram` function calls only `ram` functions,
`extern func`s and the inline built-ins (`E_FREESTANDING` otherwise), and after a device link the image is read: a call,
branch or literal of its code that reaches flash (a library routine such as `__aeabi_uidiv` for a division, `memcpy` for
a record copy, a table in read-only data, C left in flash) fails the build with `E_FREESTANDING_RAM`, naming the
function, the symbol and what needed it. A ram function's failed check is the same `udf #83` fault as any freestanding
function's (the decoder is linked for it), its `extern func` call compares the `Host` token inline (lane MCU-NOC2C's form), and
a program may start the second core beside its ram functions, the entry itself being one (lane MCU-NOC2E). Docs:
[Code that runs from RAM](docs/functions.md#code-that-runs-from-ram).

### The runtime object has a new key, so compilers from before GH-3f cannot serve it (19 November 2026)

Not breaking: no program changes. GH-3f made the hosted runtime object hold the source name `core_rt.c` where it had
held `core_rt-<key>.c`, and kept the object's key. Compilers from before that change, still built in other worktrees,
went on storing the old kind under the same keys in the per-user object store, so a build through the store and a build
with an empty one linked different objects: the component bootstrap test ("the uncached test-index build is not
reproducible") failed at random in gates, with the same two digests swapping. The key domain is now
`core-runtime-object-v5` (`runtime_object_domain` in `src/core/driver.zig`, with the rule beside it: a change to the
object's bytes needs a new domain). Each compiler compiles the runtime object once more. The core tests' seed store
(`.mylang-cache/core-tests/runtime_seed/`) takes the domain into its variant's name as well: with the name unchanged, a
worktree that had run the suite before held both generations of objects in one variant, and the tests that count
runtime objects failed after merging main (delete that folder in a worktree that merged main between the two fixes).

### The freestanding fault decoder costs a device image nothing unless the program has a freestanding fault (lane MCU-NOC2D, 19 November 2026)

Not breaking: a program's device image grew by 450 to 560 bytes when `@freestanding` landed, because every image linked the
fault decoder (the handler that reads a freestanding fault's code and place and names the code). The decoder is now a
flavour of the bare runtime beside the second core's, chosen the same way: only a program whose units hold a freestanding
fault site (`udf #83`) is compiled with `-DMYL_BARE_FREESTANDING`; every other image has the fault handler and the code
bytes it had before `@freestanding` (`return0` 1328, `list_growth` 4768, `sorting` 7424 in `--release`). A program with both
a freestanding function and `registers.start_core1` gets both flavours, and its fault now ends the program through the two
cores' one exit. The ceilings test gained `freestanding_checksum` (1912 bytes, ceiling 2100).

### Freestanding functions call C, and a freestanding fault is reported on Linux (lane MCU-NOC2C, 19 November 2026)

Not breaking: a program with no `@freestanding` function emits exactly as before, executable bytes included. A
freestanding function may now call an `extern func`, by name or through `@address`: the call records no place and
compares its `Host` token inline (a mismatch is the fault `R_CAPABILITY`), and a null address is the fault
`R_FOREIGN_TARGET`. On x86-64 Linux a fault's `ud2` is followed by the bytes `MYLF`, and a program that holds
freestanding code installs a `SIGILL` handler before `main` that flushes the output, prints `error[CODE] PATH:LINE`
with the trap record and exits 1, as a trap does; `mylang test` reports a failed test with the code instead of a
crashed process. A freestanding function's `registers` reads and writes now build under `mylang test`. Docs:
[Freestanding functions](docs/functions.md#freestanding-functions).

### `@address` extern funcs call C through a handle or an address (lane MCU-NOC3, 19 November 2026)

Not breaking: every plain `extern func` parses, keys, builds and calls as before. An `extern func` marked `@address` calls
the C function its parameter after `host` names, not a symbol: an `extern type` handle (a function pointer C returned)
or an unsigned integer, `u32` or `u64` (a `u32` works on every target and is zero-extended where addresses are 64
bits; on `thumbv6m-none` a Thumb address keeps its low bit set). The rest of the signature follows a plain
`extern func`'s rules. Another target type, a missing or a `mut` target is refused with the new `E_EXTERN_ADDRESS`,
a `u64` target when the program is built for 32-bit addresses;
a null handle or the address 0 traps the new `R_FOREIGN_TARGET` before the jump. `@address` was added to the attribute
list `E_UNKNOWN_ATTRIBUTE` names. The runtime's trap table gained the one entry, so every executable's runtime part
changes once. Docs: [calls through an address](docs/c-ffi.md#calls-through-an-address).

### `@freestanding` functions: code the compiler proves needs nothing from the runtime (lane MCU-NOC2, 19 November 2026)

Not breaking: a program with no `@freestanding` function is checked and emitted as before. The new attribute marks a
function that holds only unmanaged data and calls only other freestanding functions, `extern func`s and the `registers`
reads and writes; anything else is `E_FREESTANDING`, naming the rule. A failed check inside one calls nothing: its code
and place go in registers and the trap instruction runs (`udf #83` on `thumbv6m-none`, `ud2` on x86-64); the bare
runtime's fault handler reports it as `error[CODE] PATH:LINE`, and on Linux the program ends with `SIGILL`. Its emitted
code is checked to name no runtime symbol. Docs: [Freestanding functions](docs/functions.md#freestanding-functions).

### The toolchain identity stays put when nothing it covers changed; the component receipt is keyed by it; the runtime's key leaves the program (lane GH-3f, 19 November 2026)

Not breaking for the language: no program, diagnostic or output changes. At 06:13:56 UTC an unattended upgrade ran `ldconfig`,
and the toolchain identity of the pinned Zig moved although no library of the closure had (`mylang native show` printed the same
`closure digest` before and after): the inventory hint a toolchain's identity is read through was keyed by the loader's default
directories but not by their subdirectories, so a hint written at 03:09 with 11 subdirectories (565 inputs) was trusted by
compilers that look in 27 (949 inputs, 640 candidates) until the loader cache changed and the inventory was taken afresh. A
component built before that moment then differed from its receipt ("the uncached test-index build is not reproducible"). Now
the hint key holds every constant the candidate list is made from (`native_closure.policy`, a test names each constant), so a
hint of another rule is never read; the first command after this change takes one fresh inventory per toolchain, and the digest
of a toolchain whose hint was current does not change. A Selka component's receipt (format 6) holds the compiler's toolchain
identity, which the builder reads with the new `mylang native show --digest` (64 hexadecimal digits and a newline, nothing
else): a change of the identity, a library update among them, makes a new receipt and never a "not reproducible" failure. The
runtime's C source is compiled as `core_rt.c` inside the build's private staging directory (no `core_rt-<key>.c` stays in the
store), so `core_rt-<key>`, which holds the toolchain identity, is no longer in the symbol table of every executable.

### CPU instructions from Selka: the `cpu` module (lane MCU-NOC1, 19 November 2026)

Not breaking: a new standard module, `import cpu`. `cpu.wait_for_event`, `wait_for_interrupt`, `send_event`, `barrier`
and `breakpoint` take the `Registers` capability, and `cpu.interrupts_off(reg)` answers a sealed `@linear`
`InterruptState` that `cpu.interrupts_restore(reg, own state)` must take, so a path that forgets the restore is refused
(`E_LINEAR_UNCONSUMED`). A `--target thumbv6m-none` build emits each as its instruction (`wfe`, `wfi`, `sev`, `dsb sy`
and `isb sy`, `bkpt #0`, `mrs`/`cpsid i` and `msr` of PRIMASK) as inline assembly, with no runtime call. On a simulated
bank each call is recorded beside the write log, read by `cpu.events`, `count_of`, `interrupts_are_off` and
`write_with_interrupts_off`, which a device build refuses (`E_TARGET_SIMULATED_REGISTERS`, whose message now names a
`cpu` function as `cpu.NAME`). [cpu](docs/standard-library.md#cpu).

### The RP2040's second core from Selka: `registers.start_core1` (lane MCU-CORE1, 19 November 2026)

`registers.start_core1(reg, entry)` starts core 1 running a top-level `func(Registers) -> int` with its own stack,
heap and `Registers` beside `main`, and answers `False` when the platform has one core (QEMU's) or core 1 was started
already; a host build that calls it is refused with `E_TARGET_DEVICE_REGISTERS`. The bare runtime is safe for two cores:
each core allocates in its own arena, the runtime's per-thread and shared state is one copy per core (emulated TLS,
the program's free lists too), log writes take a hardware spinlock and core 1's lines begin `core 1: `, each core's stack
is checked, and the end of the program (a return of `main`, a trap or a fault on either core) runs the platform's exit
once. Only a program that calls `registers.start_core1` links this two-core runtime (and in `--release` keeps its main
unit out of link-time code generation); every other device image is built as before, byte for byte. The board's platform hooks,
the `rp2040.sio` module (FIFO and spinlocks) and `examples/device/two_cores.my` are in selka-rp.
[The second core](docs/tooling/native-build.md#the-second-core-registersstart_core1).

### The compiler builds with Zig 0.17.1, the stable release, not a development snapshot (lane GH-4, 19 November 2026)

Not breaking for the language: no program, diagnostic or output of `mylang` changes. What a developer must install: Zig
0.17.1 (the official tarball from <https://ziglang.org/download/>, SHA-256 `3581863e...b17a`; `.zigversion` and
`build.zig.zon` name it, and `source ~/.config/mylang/dev-env.sh` looks for it in `~/zig-toolchains/0.17.1`). The
snapshot `0.17.0-dev.1683+5ceec001b` can no longer be downloaded, so nobody else could build the compiler. `build.zig` now
accepts any 0.17 release from 0.17.1 on and refuses a snapshot; CI and the gate hold to exactly `.zigversion`
(`PINNED_ZIG` in `scripts/verification_native_telemetry.py`). The compiler reuses native results only with a reviewed Zig
distribution, and `src/core/tool_identity.zig` now holds the SHA-256 of the official 0.17.1 executable and of its library
tree instead of the snapshot's: `mylang native show` says `reuse: on`. A compiler built with 0.17.1 still gets `reuse: off`
from an unreviewed Zig (a snapshot, a distribution package, `master`). The source changes are 29 `ArrayList` literals
(`.fromOwnedSlice` instead of `.{ .items = x, .capacity = n }`, which does not compile on 0.17.1) and one line in `build_verification.zig`
(`Run.stdio` instead of `Run.test_runner_mode`). Measured against the snapshot with the same sources: the 35 programs of
`bench/parity` (suite, lib, micro, parallel; `--release`, same clang 22.1.8, `perf stat` instructions on the P cores) differ by
less than 0.001% in user-mode instructions (largest +0.00003%), outputs equal their `.expected`; a clean Debug build of the compiler costs 388.8 G
instructions on the snapshot and 401.8 G on 0.17.1 (+3.3%, twice each, stable to 0.02%), 44 to 60 s of wall time on both.

### The RP2040's second core from Selka: `registers.start_core1` (lane MCU-CORE1, 19 November 2026)

`registers.start_core1(reg, entry)` starts core 1 running a top-level `func(Registers) -> int` with its own stack,
heap and `Registers` beside `main`, and answers `False` when the platform has one core (QEMU's) or core 1 was started
already; a host build that calls it is refused with `E_TARGET_DEVICE_REGISTERS`. The bare runtime is safe for two cores:
each core allocates in its own arena, the runtime's per-thread and shared state is one copy per core (emulated TLS,
the program's free lists too), log writes take a hardware spinlock and core 1's lines begin `core 1: `, each core's stack
is checked, and the end of the program (a return of `main`, a trap or a fault on either core) runs the platform's exit
once. Only a program that calls `registers.start_core1` links this two-core runtime (and in `--release` keeps its main
unit out of link-time code generation); every other device image is built as before, byte for byte. The board's platform hooks,
the `rp2040.sio` module (FIFO and spinlocks) and `examples/device/two_cores.my` are in selka-rp.
[The second core](docs/tooling/native-build.md#the-second-core-registersstart_core1).

### A match arm whose payload is only numbers may replace the place it matched (lane FR93, 19 November 2026)

`match t.keys[i]:` / `case num(v=n):` / `t.keys[i] = Key.other` is accepted: a payload of numbers, flags or records of those
is copied when the arm binds it, fielded or not, so the arm may write the matched place, or the list or record that holds
it (`t = T(...)`), while `n` is live, and `n` keeps the value it had (before, `case Some(sec): attach[i] = None` was
accepted and `case num(v=n)` was refused with `E_SINGLE_OWNER_OVERLAP`, and the two guides disagreed). A payload with text,
bytes, a list, a dictionary or a resource, `match mut`, and a write while a binding of such a payload is live stay refused;
their message no longer says "not that place". Not breaking: nothing accepted before is refused, and nothing that built
changes its output. `docs/ownership-rules.md` and `docs/match-expressions.md` say the one rule.

### No approval step for system libraries: native results are keyed by them (lane GH-3b, 19 November 2026)

Every machine now reuses native results (objects, linked programs, replay records, test verdicts) under keys made from its
own system libraries' bytes: the loader, and for libc, libm, libgcc_s and libpthread every file `/etc/ld.so.cache` maps the
name to (in either cache layout) and every candidate in the loader's default directories, plus what `/etc/ld.so.preload`
names (a superset of what the loader could load; a file that cannot be read is keyed as unreadable, never an error). Before, a build
reused nothing unless the libraries matched a list compiled into the compiler or an approval made with `mylang native
approve`, and `zig build` failed elsewhere; a library update is now one cold build, and an install that only rewrites the
loader's cache stays warm. `mylang native show` prints the closure, its digest and whether results are reused
(`docs/tooling/native-build.md#system-libraries`). The first build of a worktree after this lands finds nothing in the
per-user object store (the identity's construction changed), compiles everything once and reuses from then on; the old
entries are collected after 14 idle days. Breaking: `mylang native approve` does nothing (it prints that it is no longer
needed and exits 0, for one release); `MYLANG_NATIVE_APPROVALS` and `~/.config/mylang/native-approvals` are read by nothing
(the file can be deleted); the build notice "the system libraries changed since they were approved", the component failure
`UnprovedNativeClosure` (with lane GH-3a) and the build option `-Dtest-unreviewed-platform` (now `-Dtest-system-root=DIR`)
are gone. Design note: `docs/audits/native-closure-keys-design-note-2026-11-19.md`.

### No seed compiler: the compiler the build builds compiles the components (lane GH-3a, 19 November 2026)

Not breaking for the language: no program, diagnostic or output of `mylang` changes, except one new line on standard error
described below. `zig build` no longer builds the 24 October compiler from git history to compile the two Selka components
(`test-index`, `cache-plan`): `selka-components --compiler` compiles them with the `mylang` the same build has just built,
which runs with the built-in test index and cache plan, so there is no cycle. A depth-1 clone with no sibling checkout
builds. A component's key binds the compiler's digest, the Zig toolchain, the native CPU and the sources; a component has
no native-closure identity of its own, and preparation never fails because a machine or its libraries are unknown. The
installed manifests keep every field. `zig build -Dcomponents=reference` builds and installs no component. A compiler that
finds no component folder (a copied `bin/mylang`) now uses its built-in implementations and prints, once per process,
`mylang: no component folder found; using the built-in test index and cache plan`, where it failed with
`ComponentMissing`; a folder that is present but holds a missing or wrong component is still an error. The component store
defaults to `$XDG_CACHE_HOME/mylang/components` when that is set. Gone: the seed pin `selfhost/component-seed.json`, the
archive extraction (`selfhost/component_archive.zig`), the seed store's `seeds/` and `native-probes/`, the guardian
symlink, the native input probe and its approval check (`selfhost/component_native_{approvals,environment,platform,probe}.zig`),
`selfhost/tools/reseed_components.py`, `selfhost/stage0-pin.json` with `selfhost/tests/stage0.py` and
`selfhost/tools/{build,pin}-stage0.sh` (`run_lexer_diff.py` now requires `--compiler`), the build options
`-Dcomponent-seed-source` and the gate's `-Dcomponent-owned-compiler-pin`, the step `seed-compiler`, the test variable
`MYLANG_TEST_COMPONENT_SEED_SOURCE` and `selfhost/test_ownership_default_components.py`. The gate identifies the
`components` artifact by the component sources and the compiler's own recipes.

### The Lean proofs run only with `-Dproofs=true`: `zig build test` needs no Lean (lane GH-3c, 19 November 2026)

Not breaking for the language: no program, diagnostic or output of `mylang` changes. Four steps of `zig build test`
(`ownership-proof`, `verify-ir-proof`, `arith-proof`, `cache-proof`) need the Lean build tool `lake` and failed without it, so
a checkout with only git and Zig could not run the tests. They now run only with `-Dproofs=true`; without it each prints one
line, `NAME: SKIPPED, not run: the Lean proofs run only with -Dproofs=true (they need lake)`, exits 0, starts no driver and looks
for no `lake` (the build summary still calls such a step a success: the line is the report, and it says skipped, never passed).
With the flag they run as before, and a missing `lake` fails them as before. The whole of each step waits for the flag: the
Zig validators keep running on every `zig build test` inside the language suites (`--verify-facts`), and the strict IR
verifier and the Zig-against-Lean comparisons are what the proof steps add. The environment manifest records `lake` only with
the flag. The maintainer's coordinator (`scripts/verify_cache.py`) passes `-Dproofs=true` on every build it runs, drops any
other `-Dproofs=` and refuses an inventory exported without it, and `verification_profiles.coverage` never completes the gate
for a plan that says the proofs were off, so no receipt records a skipped proof as a pass; the complete profile runs the same
actions as before.

### A device `main` may take `Host` and call the platform's C (lane MCU-EXT, 19 November 2026)

Not breaking: everything that built before builds the same. A `--target thumbv6m-none` build now provides `Host` as
well as `Registers`: `main(host: Host)`, `main(reg: Registers, host: Host)` (either order) and `main(host: Host?)`
(always `Some`) build, and each `extern func` call is a plain AAPCS call of the C symbol, with the C file given as one
more `--link`. Every other family is still refused with `E_TARGET_CAPABILITY`, whose message now lists what the target
provides (`` `Stream` is not provided on the target `thumbv6m-none`, which provides `Host` and `Registers` ``).
`debug(...)` on a device links without the platform defining `myl_core_span_stream_write`: the bare runtime defines it
(weak, forwarding to `myl_bare_write`), and a platform's own definition still links and wins. Docs:
[C interop on a device](docs/tooling/native-build.md#c-interop-on-a-device).

### The lean debug build runs LLVM's passes on small units (lane DBG-CAP50, 19 November 2026)

Not breaking: no program is refused, and every program gives the same results. The plain debug build (`build`, `run`,
`run-project`, `build --run`, and `--debug-lean` of every command) compiles each LLVM unit whose text is at most 50,000 bytes
without `-Xclang -disable-llvm-passes`, so LLVM's own `-O2` pipeline (inlining, SROA, GVN, loop and vector passes) runs on it;
a larger unit is compiled as before. There is no option: `--debug-o0` is the way back to the cheapest cold build. Together
with `-enable-ipra` (the entry below), against the lean build before both: the EDA port runs 3.9% less CPU time and 29
benchmark programs 17.6% less (`-enable-ipra` alone: 1.8% and 1.2%); a cold build of the port costs 2.9% more and an edit 0 to
1.2% more instructions; the debug line table keeps 96.6% of `--debug-o0`'s lines (97.3% before), and a trap's text, exit status and
call chain are unchanged. Every lean store key moves once (it now spells both lists and the cap); `--debug-o0`,
`--optimize-debug`, `--unoptimized`, `--release`, `mylang test`'s default and a bare target are unchanged.
`docs/tooling/native-build.md#debug-code-generation`, `experiments/debug-run-speed-20261118/DBG-CAP.md`.

### The lean debug build compiles with interprocedural register allocation (lane DBG-IPRA, 18 November 2026)

Not breaking: no program is refused, and every program gives the same results. The plain debug build (`build`, `run`,
`run-project`, `build --run`, and `--debug-lean` of every command) adds `-mllvm -enable-ipra` to the `zig cc` compile of each
LLVM unit, so a caller keeps values in the registers a callee in its unit does not touch. On the EDA port it ran 3.5% fewer
instructions and about 2% fewer cycles, at the same LLVM compile work. Every lean store key moves once (the key spells the whole
compile argument list); a bare target (`--target thumbv6m-none`), `--debug-o0`, `--optimize-debug` and `--release` are unchanged.
`docs/tooling/native-build.md#debug-code-generation`, `experiments/debug-run-speed-20261118/DBG-IPRA.md`.

### A device build is one command, a package can offer the device, and the lock pins its files (lanes MCU-C1 and MCU-C1B, 18 November 2026)

Not breaking for a project that built: its `mylang.json` gains keys it did not have. `target`, `include` and `devices`
(each a target, linker script, C files, include folders and image) with `device` choosing one let `mylang build F.my -o
X.elf` (or `.bin`, `.uf2`, written by the compiler) build for a device with no other flag; `--device` and `--include` are
new flags of `build`. A package's `mylang.json` may describe devices too: an application chooses one with
`"device": "PKG/NAME"`, allows its C with `allow_links`, and builds it with `mylang packages build ... --command build`.
`mylang packages lock` records each device's files (script, C files, every file under its include folders) with their
SHA-256 in the package's entry (`devices`), and `build` refuses a changed one by name; a lock without the record still
builds everything that uses no package device. `mylang test` passes `include` to the C it links. A device path whose
real location is outside its folder (a symbolic link) is refused. `experiments/mcu-20261118/C1.md`.

### Guardian is off: its test runner is two files of this repository (lane GH-2, 18 November 2026)

Not breaking for the language: no program, diagnostic or output of `mylang` changes. The build no longer imports the
sibling `guardian-zig` (`build.zig.zon` has no dependency), so the build graph configures without it; only the first build
of the compiler seed still needs it, because the seed's pinned commit imports it (stage GH-3 replaces the seed). Guardian's
test runner is kept unchanged under `tools/test_runner/` (MIT, with its `LICENSE`), with every flag, variable and output
line it had (`--guardian-shard=`, `--guardian-test-filter=`, `--guardian-test-list=`, `guardian/test: N test(s) selected`,
`RESULT`); its own tests run in `zig build test` as `test-test-runner`. Gone: `guardian.toml`, `.guardian/`, the
`guardian`, `guardian-explain`, `guardian-selfcheck`, `mutate`, `mutate-full` and `optimize-divergence` steps, Guardian's
checks on the nine test steps (and the four that ran nothing else: `test-intent`, `test-verification`,
`test-repair-study`, `test-agent-tools`), the gate's Guardian cheap check and cohort, `GUARDIAN_PREBUILT` (now an ignored variable),
and the Guardian step of `scripts/patch_gate.py`; `-Dgate-install` is accepted and does nothing, `scripts/precommit.sh`
prints one line and exits 0, and the SPEC history replay, whose reuse borrowed Guardian's Git authority, runs every time.
No longer enforced, kept as conventions (README, "Compiler quality gate"): a behavioural change needs a test change; structs
of at most 7 fields and functions of at most 6 parameters; a doc comment on every `pub`; no import cycles and no orphan
files; no RNG or wall clock outside the sanctioned modules; the type-size ratchet; a test needs an assertion and no
top-level control flow.

### A `byte_buffer` in an option or a result can be passed to a function (lane FR92, 19 November 2026)

Not breaking: `check` accepts and refuses what it did, and nothing that built changes. A call to a function with a
`byte_buffer?` or `Result[byte_buffer, E]` parameter (`Result[E, byte_buffer]` too) failed to build: `internal
error[E_CORE_INVALID_IR] ... str_len does not match its signature`, or `E_CORE_UNSUPPORTED (cast source)` for `bytes(b)`
of the payload binding. Such a parameter is now passed as a plain `byte_buffer` parameter is, so `len(b)`, `b[i]`,
slices, `bytes.find`, iteration and `bytes(b)` of the binding work. `experiments/audit-work-20261111/FR92.md`.

### A call that lends a list element `mut` beside a managed `mut` field of the same record builds (lane FR94, 19 November 2026)

Not breaking: a program that checked but did not build now builds. `try step(mut server.state, mut server.counts, mut
server.connections_of[index], now)`, with `state` holding a list and the element at a run-time index, was refused by
`build` and `run` with `E_OWNERSHIP_VALIDATION` (J8, "a take from %15, which is borrowed"); so were the same call without
`try`, in a `match`, with elements of two lists, and with a field of the element (`mut server.connections_of[index].reader`).
Core set the field into the record before it set the element into its list, read from the record before the call; it now
rebuilds every changed child before it sets the first into their parent. No validator, certificate, verifier or trust-point
rule changed. `experiments/audit-work-20261111/FR94.md`.

### `fs.dir("LINK")` is refused under a grant that names the link (lane R5-DIRLITERAL, 18 November 2026)

A change for restricted runs only. Under `--restrict --allow-read=LINK` (or `--allow-write=LINK`), where `LINK` is a
symbolic link, a handle from `fs.dir("LINK")` or `fs.dir("LINK/sub")` read and wrote through the link; every call on it
is now refused as in a run without `--restrict` (`read 'a.txt': a parent of the path is not a directory`). Nothing
reports it when the program is checked or built: grant the real folder and name it (`--allow-read=real`,
`fs.dir("real")`). A plain read through such a grant (`fs.read_text("LINK/a.txt")`) works as before. Docs:
[narrowing](docs/io.md#a-folder-named-at-run-time-filesystemdir_at) and the `fs.dir` paragraph before it.

### `mylang fix` renames a prelude-named function together with its docstring example (lane FR86, 18 November 2026)

Not breaking: `check` and `test` accept and refuse what they did. A `public func floor(x: int)` whose only bare `floor`
was its own docstring example `>>> floor(3)` failed `mylang test` (`E_BUILTIN_FUNCTION_NAME`), and `mylang fix` made
two edits a round for 200 rounds without changing the file: the edit to the example kept the offsets of the generated
test function, past the end of the file. It is now mapped into the docstring, so one round renames the function and
the example. A run whose two rounds in a row change no file now stops at once and names the repair that changed
nothing. `experiments/audit-work-20261111/FR86.md`.

### A function that returns a resource may take a `Clock`, a `Filesystem` or a `Network` beside it (lane FR90, 18 November 2026)

Not breaking: it accepts code refused before, and every function accepted before keeps the same origin. Rule P3 now counts
only the inputs a returned resource can come from: a resource, or a provider of its kind (a `Filesystem` for a file, a
`Network` for a `Poller`); a `Clock`, an `Entropy`, an `Environment`, a `Process` and a provider of the other kind are not
counted. When exactly one parameter is an `own` resource of the result's type, it is the origin and no provider beside it is
counted. So `step(own live: network.Poller, root: Filesystem) -> network.Poller`, `on_event(own live, mut st, clock: Clock)`,
`dial_slot(own live: network.Poller, net: Network) -> network.Poller` and `open_server(net: Network, fs: Filesystem) ->
network.Polling` check. The `E_RESOURCE_ORIGIN` message names only the counted inputs and no longer tells a `Poller` to be
taken `mut`. `docs/ownership-rules.md` (P3), `experiments/audit-work-20261111/FR90.md`.

### `mylang fix` repairs a missing `own` inside a generic function (lane FR88, 18 November 2026)

Not breaking: `check` accepts and refuses what it did, with the same text. A generic body refused at its declaration
(a message "the body of `make` is refused when `K` is ...") now carries its inner refusal's repair, an `own` written or removed or a
`copy(...)`, when every refused kind of type argument asks for the same edit, so `mylang fix` applies it where it said
`nothing to fix`. `docs/tooling/fix.md`, `experiments/audit-work-20261111/FR88.md`.

### A bare name that an imported module declares says so (lane R5B-MSGS, 18 November 2026)

Not breaking: nothing the compiler accepts or refuses changes, only the text and the repair of one refusal. After `import bitio`, a
bare `new_bitout()`, a parameter of type `BitOut` or a constructor call `BitOut(out=[])` was refused as "this module declares no `new_bitout`" without saying that
`bitio` declares it. When exactly one module the file imports declares the name publicly, as the kind the position needs (a function
or constant, a type), the message now adds "the imported module `bitio` declares it: write `bitio.new_bitout`" and `mylang fix` writes
the qualifier (under the alias the import gives, `bio.new_bitout` for `import bitio as bio`). When two or three imported modules
declare it, the message names them all and `mylang fix` chooses none. A private declaration and a module the file does not import are
not offered. `docs/modules.md`, `experiments/audit-work-20261111/R5B-MSGS.md`.

### A `fails` call used as its value says `try` (lane R5B-MSGS, 18 November 2026)

Not breaking: nothing the compiler accepts or refuses changes, only the text and the repair of one refusal. `2 + parse("1")`,
`show(parse("22"))`, `mut n: int = parse("333")`, `n = parse("4")`, `n += parse("5")`, `return parse(text)` and `parse("6") + 2` where the
value is `int` and `parse` is declared `-> int fails str` were refused as "expected int, found Result[int, str]". The message now names the
call and the two ways out (`try parse(...)`, or `const n = parse(...) else Err(e):`), says what the enclosing function would declare
when it has no `fails`, and `mylang fix` writes `try ` before the call when the enclosing function declares the same `fails` type. The
same goes for a `fails` call as an `if`, `while` or `assert` condition, under `not` or `-`, and in `<`, `+` and the like. Where `try` is
refused (a contract condition, a lambda, a `detach` loop, a function with an `on fail:` clause, a function that still holds an
unhandled result) the message stays plain and `mylang fix` writes nothing. A `Result` held in a variable keeps the plain message. `docs/results-and-options.md`.

### A test that passes its default budget says what it was and where to raise it (lane R5B-MSGS, 18 November 2026)

Not breaking: only the report of a failing test changes. A `mylang test` test that stopped with `R_STEP_LIMIT` or `R_FRAME_LIMIT`
under the default budget (1,000,000 steps, 1,024 frames) was told only "raise it with --max-steps=N", which reads as the flag of
`mylang run`. The report now says that every test has a budget, what it is, and both ways to raise it: `mylang test --max-steps=N`
(`--max-frames=N`) or `limits.test.max_steps` (`max_frames`) in `mylang.json`. A test whose budget a flag or the project set keeps the
old line, as do `mylang run`, `build --run` and a built binary. `docs/tooling/guest-tests.md`.

### Field moves: owned bindings, a message for each refusal, and a repair that joins two moves (lane FR91B, 19 November 2026)

Not breaking: nothing that checked is refused, and nothing that built lowers differently. Several fields now also move in one
statement out of a `match own` payload and the payload of `own x else:` (the element of `for x in own xs:` already did). Each
refusal a writer can still meet names the way out in the program's words: two statements (the moves in one, shown as the
writer's call), a read between or after the moves (read it into a local first), `and`, `or`, a branch or another operation
such as `append`, one field twice (`copy` at the first), a borrowed or `mut` parameter (declare it `own`), and `E_TAKE_TYPE`
beside a move of another field (`own` in one statement). `mylang fix` rewrites `const a = own p.x` and `const b = own p.y`,
used once each as `own a` and `own b` of one call or constructor in the next statement, into that call. B8 in
`docs/ownership-rules.md`, `experiments/audit-work-20261111/FR91B.md`.

### Several fields move out of one owned record in one statement (lane FR91, 18 November 2026)

Not breaking: every program that checked before checks and builds as before, and one field moved lowers as before.
`total(own p.lo, own p.hi)` and `Graph(ids=own t.ids, nodes=own t.nodes)` now check when `p` or `t` is an `own` parameter or
a `const` or `mut` local: the record is consumed once, at the first move the statement makes, and the fields no move names
are destroyed there, as with one move. The moves must be in one statement, each of a different field, outside a
short-circuit operand or a conditional; a read of the record after the first move, one field twice, moves in two statements
and a field of a borrowed record or of a list element stay refused. The refusal of a second move no longer sends a type
with no default to `take`. `experiments/audit-work-20261111/FR91.md`.

### A generic function's signature may name `byte_buffer` bare (lane FR87, 18 November 2026)

Not breaking: `func note[K](mut out: byte_buffer, key: K) -> int:` was refused with `E_UNKNOWN_TYPE` unless something else
in the file had named the buffer (`byte_buffer[]`, a generic record's field); it now checks, builds and runs as its
non-generic twin does, as a parameter, a result, a `fails` result or a local's annotation. Nothing that checked before changes.
`experiments/audit-work-20261111/FR87.md`.

### `mylang fix A B ...` repairs several paths (lane FR81, 18 November 2026)

Not breaking: `mylang fix PATH` with one path does what it did, edit for edit, line for line and in its exit status. `mylang fix`
now takes two or more paths, each a file or a directory, and repairs them one after another in the order written, each by
the rules of its own kind, on the files as the paths before it left them: a module two programs import is repaired once, and
the second program checks it repaired. A path that does not exist or is not a `.my` file or a directory is named on stderr
before anything is written (exit 2). The status is the worst of the paths' (0, 1, 2), one `fix: N edits in M files over R rounds`
line counts them all, and `--check`, `--report`, `--diagnostics=json`, `--imports`, `--cache-dir` and `--no-cache` apply to
every path. `docs/tooling/fix.md`, `experiments/audit-work-20261111/FR81.md`.

### `Registers` on a device, and a simulated bank that models hardware (lane MCU-B1D, 18 November 2026)

Not breaking for a program that built: `func main(reg: Registers)` now checks clean on every target (it was `E_MAIN`),
and a build for Linux refuses it with `E_TARGET_CAPABILITY`, which keeps the old message: a `Registers` is provided only
on a device target, and a test makes one with `registers.simulated()`. On `--target thumbv6m-none` `main` receives the
device's registers and each `registers.read8/16/32` and `write8/16/32` is one volatile load or store at the address;
a device build that calls `simulated`, `poke32`, `script32`, `pin32` or a log reader is refused with
`E_TARGET_SIMULATED_REGISTERS`, which names the function. New: `registers.script32(reg, address, values)` (the next reads
of a word answer `values` in order, then the stored word) and `registers.pin32(reg, address, mask, value)` (the masked
bits always read as `value`'s; writes are logged as written). A `parallel` task may make its own bank.

### `shift_left(1u32, 2u32 * ep.number)` checks: a product is not a float literal (lane FR84, 18 November 2026)

Not breaking: programs that were refused now check, and every program that built before gives the same results. An
operand of an integer builtin (`shift_left`, `bit_or`, `wrapping_add`, ...) or of `min`/`max` that starts with a number
and holds a `.` or an `e` later (`2u32 * ep.number`) was taken for a float literal and refused beside a peer of its own
type (`E_TYPE`, "the literal `2u32 * ep.number` is u32 and cannot take the u32 type of `1u32`"). Only one number token
is now a literal there. Two different integer types stay refused, now with the operator's own message ("expected u32,
found u64"), and a literal that does not fit its peer keeps its message. `experiments/audit-work-20261111/FR84.md`.

### `mylang test build` and `mylang check build` walk a folder named `build` (lane FR85, 18 November 2026)

Not breaking: a run that found nothing now finds the tests of the folder it was told to walk, and nothing the compiler emits
changes. A folder the command line names is walked whatever it is called: `mylang test build` ran `0 passed` and exited 3 with no
word of why, and `mylang check build` said `ok (0 modules)`, because the walk left out any path with a `build`, `zig-out`,
`node_modules` or dot segment, the named folder's own name included (`mylang fix DIR` and `mylang packages build DIR` share the
walk). Such a folder met inside the named one, and in a walk of the project root, is left alone as before. A directory run
that selects nothing now ends with one line on standard error, `note: no tests found under `tools`: `tools/build/` is left alone as
a build-output folder; name it to include it`, naming the left-alone folders that hold `.my` sources (standard output and exit
status 3 as before). `import build.x` from `build/t.my` works under a `mylang.json`; with none, the import root is the folder
named, for a folder of any name, and the refusal (`E_MODULE_READ`) already names `--import-root`.
`experiments/audit-work-20261111/FR85.md`.

### The lean debug build compiles with interprocedural register allocation (lane DBG-IPRA, 18 November 2026)

Not breaking: no program is refused, and every program gives the same results. The plain debug build (`build`, `run`,
`run-project`, `build --run`, and `--debug-lean` of every command) adds `-mllvm -enable-ipra` to the `zig cc` compile of each
LLVM unit, so a caller keeps values in the registers a callee in its unit does not touch. On the EDA port it ran 3.5% fewer
instructions and about 2% fewer cycles, at the same LLVM compile work. Every lean store key moves once (the key spells the whole
compile argument list); a bare target (`--target thumbv6m-none`), `--debug-o0`, `--optimize-debug` and `--release` are unchanged.
`docs/tooling/native-build.md#debug-code-generation`, `experiments/debug-run-speed-20261118/DBG-IPRA.md`.

### `case _:` is the wildcard arm in a generic function too (lane FR82, 18 November 2026)

Not breaking: programs that were refused now check, and every program that built before gives the same results. A `case _:`
arm of a `match` in a generic function was refused (`E_UNKNOWN_VARIANT`, "case is not a variant of the matched type")
wherever the match sat: in an `else Err(failure):` block, an `else:` block, an `if r is Err(e):` body or the body itself.
The generic body check now reads it as the concrete check does, with the same refusals (`E_WILDCARD_ARM` when it is not
the last arm or every case already has one). A case the type does not declare stays `E_UNKNOWN_VARIANT`.
`experiments/audit-work-20261111/FR82.md`.

### A `match` arm with a payload of numbers writes a field beside the matched place (lane FR80, 18 November 2026)

Not breaking: programs that were refused now check, and every program that built before gives the same results.
`t.ints[n] = at` or `append(mut t.seen, n)` in `case num(v=n):` of `match t.keys[at]:` or `match t.key:` (a fielded
payload of numbers, flags or records of them) was refused (`E_SINGLE_OWNER_OVERLAP`, X1); it now runs as the
`match copy(t.keys[at]):` form does. The refusal that stays (a write to the matched place, to a place that holds it, or
beside a payload that holds text, bytes or a list) names the matched place and the place written as the source spells
them, not `'<collection>'`, and offers `match copy(...)` or a local read before the match; the advice to match on a call
now appears only for a matched local a call initialized. `experiments/audit-work-20261111/FR80.md`.

### Three refusals say what to write: a quote in an f-string hole, an `else` block that continues, a pattern that discards a field (lane R5-MSGS, 18 November 2026)

Not breaking: only message text changed, with the codes, spans and `mylang fix` repairs. `f"{names["a"]}"` (a quote of the
literal's own kind inside a hole) said "unterminated interpolation" and suggested `{{`, which was wrong: the quote had ended
the literal inside the hole. It now says so and gives the three ways out, the other kind of quote in the hole
(`f"{names['a']}"`), the other kind for the literal (`f'{names["a"]}'`), or a name bound first; an open hole with no `}` after
the quote on its line keeps the advice about a literal brace. `E_ELSE_FALLTHROUGH` ("the `else` block must leave the enclosing
block") now adds how to handle a failure and go on: `if CALL is Err(e):` (`is None` for an Option) or a `match` with an arm for
each case. `case Failed(_):` on `Failed(message: str)` was told that `case Failed(message=_):` "renames" the field; it now says
it "discards" it, and the message for an enum of another module names each field the pattern left unlabelled (at most four, then
"and N more") as `mylang fix` labels them all. `experiments/audit-work-20261111/R5-MSGS.md`.

### Call results that are never live together share a stack slot (lane FR79, 18 November 2026)

Not breaking: every program gives the same results, and deep recursion that filled the stack may now finish. A function
kept a stack slot for each record or union over four words it computed, one per call site: a tree-walking interpreter's
`eval` (30 recursive calls, a 208-byte `Result` each) had an 8.8 KB frame and trapped `R_FRAME_LIMIT` on 1,000 nested
`+` under the default 8 MiB stack. Once a function's slots pass 4 KiB, values of one size whose lives never overlap now
share one slot: that `eval` is 2.3 KB with `--release` and 1.3 KB in a debug build, its `exec_assign` 0.4 KB (23 KB
before), and the 1,000-operator input runs. `experiments/audit-work-20261111/FR79.md`.

### A call given `mut` a binding of a nested `match mut` arm passes the strict IR verifier (lane FR77, 18 November 2026)

Not breaking: programs that were refused now check, and every program that built before gives the same results.
`one(mut u)` in `case two(u, v):` of a `match mut x:` on a binding of an enclosing `match mut` arm built and ran right, but
its IR held a payload read no tag test justified, which `mylang verify-ir` refused. The call now tests the inner case where
it takes the inner payload, as an assignment through the binding does. Two bindings of such an arm (`fill(mut u, mut v)`)
and bindings of two nested arms (`fill(mut u, mut y)`) in one call, refused before (`E_SINGLE_OWNER_OVERLAP`, M5), now
check and build. No validator, certificate, verifier or trust-point rule changed. `experiments/audit-work-20261111/FR77.md`.

### A built binary honours a memory limit from its environment (lane R5-BINCEIL, 18 November 2026)

A program from `mylang build -o` started by hand now takes a byte ceiling from `--max-memory=SIZE` in `MYLANG_OPTIONS`,
else from `MYLANG_MEMORY_LIMIT` (`K`/`M`/`G` suffixes, `0` for none), and traps `R_MEMORY_BUDGET` past it with the same
accounting and the same `RLIMIT_AS` lowering as under `mylang run`; with neither set it has no ceiling, as before.
Breaking only where that environment already names one: `MYLANG_OPTIONS=--max-memory=...` used to exit 2 as "not a
runtime option", and a binary started with `MYLANG_MEMORY_LIMIT` set used to ignore it; a malformed size now exits 2.
`mylang run`, `build --run` and `mylang test` keep their own precedence and defaults. Docs:
[runtime budgets](docs/tooling/runtime-budgets.md#guest-memory-ceilings), [the native backend](docs/io.md#the-native-backend).

### `filesystem.dir_at` refuses a symbolic link under a grant that names it (lane R5-DIRATLINK, 18 November 2026)

Breaking for a program run under `--restrict` that narrows with `dir_at` to a folder through a grant named by a link:
with `--allow-read=LINK`, `filesystem.dir_at(fs, "LINK")` succeeded and read through the link, and `dir_at(fs,
"LINK/sub")` too; both now fail as in a run without `--restrict` (`dir_at 'LINK': is a symbolic link the sandbox does
not follow`). Name the real folder in the grant or in the path. A plain read through such a grant
(`fs.read_text("LINK/a.txt")`) works as before (for `fs.dir("LINK")`, see lane R5-DIRLITERAL). Docs:
[a folder named at run time](docs/io.md#a-folder-named-at-run-time-filesystemdir_at).

### A scalar passed `mut` through a `match mut` payload binding builds (lane FR76, 18 November 2026)

Not breaking: programs that checked but did not build now build, and every program that built before gives the same
results. `bump1(mut vals[0])` in `case pairs(keys, vals):` of a `match mut` (two elements in one call, an element beside
a managed sibling, a field or an element of a record payload, a scrutinee that is a list element, a `mut` parameter or a
field of a local, a dictionary binding's value, a nested `match mut`) was refused at build (`E_CORE_UNSUPPORTED`, "a
borrowed part", or `E_OWNERSHIP_VALIDATION`, J8); it now gives what `vals[0] = bump_value(vals[0])` gives. No language,
validator, certificate, verifier or trust-point rule changed. `experiments/audit-work-20261111/FR76.md`.

### A `Registers` capability and the `registers` module, simulated on Linux (lane MCU-B1, 18 November 2026)

New: `registers.read8/16/32(reg, address)` and `registers.write8/16/32(reg, address, value)` through a `Registers`
capability, and `registers.simulated()`, a bank with a write log (`write_count`, `write_address`, `write_value`,
`write_width`, `writes`, `last_write`) and `poke32`, so hardware library code is tested with no board. `main` cannot
ask for a `Registers` on this target (`E_MAIN`). The reads and writes allocate nothing, so `@noalloc` code may make them;
a full bank or log traps `R_REGISTER_BANK`. Breaking only for a project that has its own module file `registers.my`:
the standard module now wins (as for every standard module name), so rename the file. A record named `Registers` still
wins inside its own module. Docs: [register access](docs/io.md#register-access), the
[standard library guide](docs/standard-library.md#registers).

### `mylang fix` leaves the builtin's call when it renames a function that shadows a prelude name (lane FR78, 18 November 2026)

Not breaking: `check` refuses and accepts what it did, with the same code. The `E_BUILTIN_FUNCTION_NAME` repair renamed
every bare call of the name, so beside `func flush(n: int)` the builtin call `flush(out)` became `main_flush(out)` and the
fixed file failed `E_TYPE`. A bare call whose arguments cannot be the declared function's (their count, or a literal or
typed parameter of another kind than the parameter it binds) now stays the prelude's, and the message names it ("with
every use but the bare call at main.my:6:5, whose arguments cannot be this function's: it stays the prelude's `flush`").
For a re-export the repair is withheld with that reason. `experiments/audit-work-20261111/FR78.md`.

### `own x` moves the payload of an option local narrowed to `Some` (lane FR64, 18 November 2026)

Not breaking: programs that were refused now check, and every program that built before gives the same results. After
`if x is None: return` (or `fail`, `break`, `continue`, or in the `else:` of that test), `own x` of an option the function
owns (a `const` or `mut` local, or an `own` parameter) moves the payload out and consumes `x`, with no copy, as
`const p = own x else:` does; a bare `return x` or `fail x` gives it the same way. It was refused (`E_OWN_MARKER`, "`x` is
lent by a temporary value"). The bare-`x` refusal (B7) now offers `own x` before `copy(x)`, and `mylang fix` writes the
`own` where nothing reads `x` after it and no loop runs it again. `own x` of a narrowed plain or `mut` parameter, loop
variable or `match` binding stays refused, now naming that lender, and `mylang fix` writes `copy(x)` instead of removing
`own` only to meet the bare-`x` refusal. No validator, certificate, verifier or trust-point rule changed.
`experiments/audit-work-20261111/FR64.md`.

### Two fields of one `match mut` payload may be passed `mut` to one call (lane FR75, 18 November 2026)

Not breaking: programs refused before now check, build and run, and every program that built before gives the same
results. `match mut t:` / `case pairs(keys, vals):` / `put(mut keys, mut vals)` (and `mut p.keys, mut p.vals` of a
record payload `p`, a scrutinee that is a local, a parameter or a field path of one) was refused with
`E_SINGLE_OWNER_OVERLAP` and a copy per call; it now gives what `put(mut t.keys, mut t.vals)` of a record gives, and so
does a read argument that makes a value of its own beside such a binding (`emit(mut held, copy(held.targets[0]) + "?")`,
F-24's rule). Still refused: a matched place inside a list element (ELEM-FIELDS) or under an enclosing arm's binding
(nested `match mut`, bindings of two arms), one binding twice, a binding beside the matched place or a field path under
itself, an argument that lends a part, and a read of a binding beside a `mut` sibling. No validator, certificate, verifier or
trust-point rule changed. `experiments/audit-work-20261111/FR75.md`.

### A restricted run's refusal of an ungranted capability says a `main` may declare it optional (lane R4-MSGS, 18 November 2026)

Not breaking: only the text of one refusal changed; no program is newly refused or accepted. Under `--restrict`, a `main`
that asks for a capability the command line did not grant stops with the same sentence as before, and the line now ends
with "; or, if the program can run without it, declare the parameter optional (`fs: Filesystem?`)", naming the family's own
type (`rng: Entropy?`, `net: Network?`, `env: Environment?`, `proc: Process?`, `host: Host?`; a `Clock` never reaches it).
It is still one line, and `run`, `build --run` and an installed executable still print the same one. "Capabilities" in
`docs/io.md` and the Host example in `docs/c-ffi.md` show it. `experiments/audit-work-20261111/R4-MSGS.md`.

### A pattern that binds an enum field under another name says the field's own name and the renaming form (lane R4-MSGS, 18 November 2026)

Not breaking: only the text of two refusals changed, with their codes and the `mylang fix` repair. `case array(elems):` on
`array(items: int[])` was refused with "name the enum field bound by this pattern" (`E_FRONTEND_VARIANT`, an enum of the
same file) or "payload fields must be supplied by name" (`E_NAMED_PATTERN`, an imported or generic one), which did not say
that a bare name in a pattern is the field's own. Both now read "`array`'s field is `items`: `case array(items):` binds it
under its own name, `case array(items=elems):` renames it"; a case of several fields lists them (at most four, then a
count) and shows `items=elems` for the field that was bound by another name. The card's line on enum patterns says the
same. `experiments/audit-work-20261111/R4-MSGS.md`.

### `+=` on an element of a local list whose right side lends another element `mut` builds (lane FR74, 18 November 2026)

Not breaking: programs that checked but did not build now build, and every program that built before gives the same
results. `rows[i].n += bump8(mut rows[j])` with `rows` a local or a `mut` parameter (the same element lent instead, `-=`,
in a loop, a local list of lists, a local dictionary) was refused at build (`E_CORE_UNSUPPORTED`, "write to a receiver's
place while its arguments are evaluated"); it now gives what `x = x + bump8(mut rows[j])` gives, and the call's write to
element `j` is kept. An element write whose index lends an element of the same local list `mut` (`rows[save(mut
rows[1])].n = 13`) builds too, and gives what binding the index to a `const` first gives. No language, validator,
certificate, verifier or trust-point rule changed. `experiments/audit-work-20261111/FR74.md`.

### `+=` on a list element's field whose right side lends another element `mut` builds (lane FR73, 18 November 2026)

Not breaking: programs that checked but did not build now build, and every program that built before gives the same
results. `s.rows[i].n += bump8(mut s.rows[j])` (the same element lent instead, `-=`, in a loop, two levels of lists, an
element of another field, a dictionary of lists) was refused at build (`E_CORE_UNSUPPORTED`, "write to a receiver's place
while its arguments are evaluated"); it now gives what `x = x + bump8(mut s.rows[j])` gives, and the call's write to
element `j` is kept. An element write whose index lends a sibling field `mut` (`points.left[save(mut
points.right)].x = 13`, refused the same way) builds too, and gives what binding the index to a `const` first gives. No
language, validator, certificate, verifier or trust-point rule changed. `experiments/audit-work-20261111/FR73.md`.

### `+=` on a dictionary entry's field whose right side lends another entry `mut` builds (lane FR72, 18 November 2026)

Not breaking: programs that checked but did not build now build, and every program that built before gives the same
results. `server.conns[id].sent += reset8(mut server.conns[8])` (the same entry lent instead, `-=`, in a loop, two levels
of entries) was refused at build (`E_CORE_UNSUPPORTED`, rule Z3, "cannot schedule a store", at the `mut` argument); it
now gives what `x = x + reset8(mut server.conns[8])` gives, and the call's write to entry 8 is kept. No language,
validator, certificate, verifier or trust-point rule changed. `experiments/audit-work-20261111/FR72.md`.

### `+=` on a dictionary entry's field whose right side calls a function builds (lane FR71, 18 November 2026)

Not breaking: programs that checked but did not build now build, and every program that built before gives the same
results. `server.conns[id].sent += twice(server.conns[8].sent)` (the call on another entry or on the same one, two
arguments from two entries, `len` of fresh `bytes` a call made, a call lent an entry, `-=`, in a loop, two levels of
entries) was refused by `build` and `run` with `E_CORE_UNSUPPORTED` (rule Z3, "cannot schedule dict_set_value"), while
`x = x + twice(...)` built. A call given the place `mut` is still refused, as before. No validator, certificate, verifier or
trust-point rule changed. `experiments/audit-work-20261111/FR71.md`.

### `bytes.find_any` takes an `end`, as `bytes.find` does (lane R3-FINDEND, 18 November 2026)

Not breaking: `bytes.find_any(data, octets, start)` answers what it did, and no program is newly refused. The search for the next
octet of a set had no upper bound (friction logs-s F-3), so a scanner asking for the next delimiter inside one line of a large
buffer read the rest of the buffer when the line held none. `bytes.find_any(data, octets, start, end)` reads the octets in
`[start, end)` only, named as `bytes.find`, `bytes.rfind` and `bytes.count` name theirs (`end` is the fourth argument and defaults
to the length). An octet at `end - 1` is found and one at `end` is not; an `end` past the length is the length; an `end` at or
before `start`, an empty window and an empty set answer -1. The offset answered still counts from the first octet of `data`, which
may be a slice, a view or a `byte_buffer`. A negative `end` is `E_NEGATIVE_INDEX_REMOVED` when written as a literal and traps
`R_LIST_BOUNDS` when computed, as a negative `start` always did. `docs/bytes.md` ("Searching a byte set"),
`experiments/audit-work-20261111/R3-FINDEND.md`.

### `mylang build` no longer spins on a recursive enum where `check` is instant (lane BUILDHANG, 18 November 2026)

Not breaking: the same programs build, with the same output. A Debug compiler's IR check asked whether an undefined value's
type holds a function by walking every path through the type, so a recursive enum with two or more recursive cases (a JSON
`Value` with `array(items: Value[])` and `object(keys: str[], vals: Value[])`) took time exponential in the number of types
in the module: friction R3-4-F-2, where `lists.pop_at(mut vals, 0)` in a loop over such a case built for 12 minutes and
more. The check now visits each type once, and that build takes seconds. `experiments/audit-work-20261111/BUILDHANG.md`.

### `+=` on a dictionary entry's field whose right side reads other entries builds (lane FR70, 18 November 2026)

Not breaking: programs that checked but did not build now build, and every program that built before gives the same
results. `server.conns[id].sent += server.conns[8].sent * len(server.conns[id].out)` (the other entry on either side of
the operator, two other entries, a key equal to `id` or not, a list element of another entry, `-=`, `*=`, in a loop, two
levels of entries) was refused by `build` and `run` with `E_CORE_UNSUPPORTED` (rule Z3, "takes ownership of
`server.conns` ..., which is a borrowed part of `server`"), while `x = x + ...` built. Core now reads the place once, as
the plain form does, and the right side's reads borrow that read until the write. No validator, certificate, verifier or
trust-point rule changed. `experiments/audit-work-20261111/FR70.md`.

### Six guide fixes from the round-3 programs: the C binding you write, a folder walk, rule M5 inside a list element (lane R3-DOCS, 18 November 2026)

Not breaking: documentation only, no compiler change. `mylang docs c-ffi` shows the `sqlite` binding as a module you write (there is no shipped one) and says an `extern type` held by a `public` record must be `public`; `primer` says `strings.join(pieces, "")` and that fields of one list element are not proven disjoint (pass the element); `io` has a folder-walk recipe; the `network` poller's `recv` takes the `Builder`; the guest-tests guide says why a long input meets `R_STEP_LIMIT` and how to raise it for one test; the card names `filesystem.list_entries` and `x is case(payload)`. `experiments/audit-work-20261111/R3-DOCS.md`.

### `mylang fmt` keeps a block of one-line constants together (lane R3-FMTCONST, 18 November 2026)

Not breaking: a file the formatter called canonical is still canonical. Consecutive one-line top-level `const` declarations with no blank line between them
(five `const S_NONE: int = 0` lines in a row) stay together instead of getting two blank lines each, and the comment above the block, or between two of its constants,
stays where it is (R3-2 F-4); a constant over several lines, a blank line between two constants and every other declaration keep the two blank lines.

### `json.loads` keeps the last value of a repeated member (lane R3-JSONDUP, 18 November 2026)

Not breaking for programs that ran: `json.loads` read `{"a":1,"a":2}` as an error ("JSON object has a duplicate key"); by the user's decision JSON-DUP it now reads `{"a":2}`. The member keeps the place of its first occurrence and the value of its last, as Python's `json.loads` does, nested objects included, and `json.dumps` writes that order. A repeated key is compared after escapes are decoded (`"a"` and `"\u0061"`); lone surrogates are still refused.

### `E_UNKNOWN_SYMBOL` on an enum case written without its enum says `did you mean Enum.case`, and `mylang fix` writes it (lane R3-SMALLDIAG, 18 November 2026)

Not breaking: the same programs are refused. `argparse.MissingValue(name="db")` and `MissingValue(name="db")` (a file that imports `argparse`) said only "declares no `MissingValue`" (tasks-h F-2); when exactly one enum in reach has a case of that name, the message now says `did you mean `argparse.Error.MissingValue`?` and `mylang fix` writes the call with its enum. A case that two enums have is left as it was.

### `E_TOKEN` at a `\"` inside an f-string's braces says a hole holds an expression and what to write (lane R3-SMALLDIAG, 18 November 2026)

Not breaking: the same programs are refused, with a message instead of "unexpected character in source" alone (tasks-h F-1). `f"{d[\"k\"]}"` now says a quote inside a hole is the other kind, `f"{d['k']}"`, or the value goes in a local first; `\'` inside `f'...'` likewise. No fix: the repair has two spellings.

### `--restrict` names both directory grants when a program's `Filesystem` is not granted (lane R3-SMALLDIAG, 18 November 2026)

Not breaking: the same command lines launch and the same ones are refused. The launch refusal for an ungranted `Filesystem` said "pass --allow-read=DIR", so a program that only writes was sent to a read grant (loadtest-h F-2); it now says "pass --allow-read=DIR or --allow-write=DIR", and either one satisfies the launch check, as before.

### A file that imports and is named like `my-prog.my` is refused with `E_ENTRY_NAME` and the name to give it (lane R3-SMALLDIAG, 18 November 2026)

Not breaking: the same files are refused, with a message that names the code, the file and the repair. `mylang check my-prog.my` with an `import` in it printed `list-modules: entry must be an identifier.my file; imports resolve beneath its directory`, and now prints `my-prog.my:1:1: error[E_ENTRY_NAME]: rename `my-prog.my` to `my_prog.my`: a file that imports must be named like a module (...)`. `check-session` says the same. No fix (a rename is not an edit of the file).

### A `bool` test that returns one failing comparison says what was compared (lane R3-TESTMSG, 18 November 2026)

Not breaking: no program is refused, and a test passes or fails as before. `return a == b` (or `!=`, `<`, `<=`, `>`, `>=` over integers, floats or texts) as the last line of a test that comes out `false` now reports `expected true, got false`, then `returned comparison: left 6, right 5` and `in main::test_x at main.my:4:12` (an `assert`'s wording and cuts), instead of the advice to write one `assert` per fact; any other `false` keeps the advice. Only the executables `mylang test` builds change, and only for a test of that shape. `experiments/audit-work-20261111/R3-TESTMSG.md`.

### A line continued without parentheses says to write them, and `mylang fix` writes them (lane R3-CONTINUE, 18 November 2026)

Not breaking: every program refused before is refused with the same code, and none is newly refused. `total = a +` with `b` on
an indented next line (`E_INDENTATION`) and a backslash at the end of a line (`E_TOKEN`) now say that an expression continues
on the next line only inside parentheses and show `(a +` ... `b)`; `mylang fix` writes the parentheses and removes the
backslashes when the statement is an assignment, a `return`, or an `if`, `elif` or `while` condition.
`experiments/audit-work-20261111/R3-CONTINUE.md`.

### `argparse` reads a program with commands: `tasks --db F add TITLE --prio 2` (lane R3-ARGSUB, 18 November 2026)

Not breaking: new types and functions; `parse`, `usage` and `help_text` print and accept what they did. Two tracker programs
split the command word by hand (about 100 lines). `argparse.new_commands(program, summary)` makes a `Commands` whose `global`
spec holds the options before the command word (`argparse.add_option(mut program.global, ...)`), `add_command(mut program,
name, spec)` adds one spec per command, and `parse_command(program, items)` returns an `Invocation` that names the command and
holds both sets (`invocation.global`, `invocation.local`, read with `has`, `get`, `get_int`) or fails with a `CommandError`.
`command_message` names the command (`unknown option --prio for command done`, also for the program's option written after the
word), `command_usage` and `command_help` give the command's own usage line and help text, and `command_of(error)` says which.
Guide: "Commands" under `argparse` in `docs/standard-library.md`; `experiments/audit-work-20261111/R3-ARGSUB.md`.

### `main` may take a capability as `T?`, and a `Clock` needs no grant (lane CAPGRANT, 18 November 2026)

Not breaking for any program's source: no program is newly refused. By the user's decisions of 17 November 2026 (CAP-OPT,
STOPWATCH), an entry parameter of a capability a command line grants may be written `T?` (`fs: Filesystem?`,
`net: Network?`, `clock: Clock?`, `rng: Entropy?`, `env: Environment?`, `proc: Process?`, `host: Host?`): under
`--restrict` it is `None` when the command line grants nothing of that capability (any `--allow-read` or `--allow-write`
counts for a `Filesystem`, any `--allow-endpoint` or `--allow-listen` for a `Network`), and `Some` otherwise, so a log
reader of standard input no longer needs a directory grant to start. The plain `T` keeps its refusal to start, word for
word; `Stream?`, `Input?` and `Stop?` are `E_MAIN`. A `Clock` now starts under `--restrict` without `--allow-clock`:
`time.monotonic` and `time.sleep` work, and `time.now` fails with "the wall clock is not granted: pass `--allow-clock`"
until it is given (a `logging` logger with that clock writes its lines without a time). A run that relied on the old
refusal of a `Clock` to stop before its first instruction now starts. `experiments/audit-work-20261111/CAPGRANT.md`.

### `mylang fix` writes a Python `!r` or `!s` conversion in an f-string hole as the call (lane R3-PYSPELL, 18 November 2026)

Not breaking: the same programs are refused and accepted, with the same code, position and message. `f"{text!r}"` (`E_TOKEN` at the
`!`) now carries a structured fix: `mylang fix` writes `f"{repr(text)}"`, and `{n!s:>8}` becomes `{str(n):>8}`, keeping the format
specification. The fix is written only where the hole is one expression followed by `r` or `s` alone; `!a`, two conversions and
an expression that does not parse as one keep the message without a fix. Python's `"-" * n` already had its fix
(`strings.repeat("-", n)` and the import, `E_REPETITION_REMOVED`); the guide and the fix table now say so.
`experiments/audit-work-20261111/R3-PYSPELL.md`.

### A slice of a list element bound to a local is a view, as the two-step form is (lane FR69, 18 November 2026)

Not breaking: a program that was refused now checks, and no program that built gives another result. `const piece =
names[0][0:5]`, `p.lines[0][0:5]`, `xs[1][0:2]` with `xs: bytes[]` or `int[][]`, and a slice of a field of an element at
any depth (`t.leaves[0].words[0][6:11]`), bound to a `const` local, were refused with `E_SLICE_ESCAPES` (V2, "the local
`piece` needs its own value") while `const line = names[0]` then `const piece = line[0:5]`, and the slice of a field
(`p.name[0:5]`) or of a dictionary value (`d["k"][0:3]`), checked: the guide's "a slice bound to a local is a view in every
build mode" held only for those. The one-expression form is a view too: no copy (a `@noalloc` helper may bind it), and a write
to the source (`names[0] = "x"`, `append(mut names, "y")`, an assignment of `names`) while the view is read later is refused as
for the two-step form, with the same V3 message. A slice of an element of a fresh record or a call's list
(`made().items[0][0:1]`) is still refused; the advice there no longer says that a `const` cannot hold the slice of an element
of a local record. `experiments/audit-work-20261111/FR69.md`.

### A value of its own made from a record goes to an `own` parameter beside `mut` of the record (lane FR67, 18 November 2026)

Not breaking: programs that were refused now check, and every program that built before gives the same results.
`keep(mut state, copy(state.name))`, with `func keep(mut totals: Run, own text: str)`, was refused with
`E_SINGLE_OWNER_OVERLAP` (M5), and so were a call (`make(state.files)`), concatenation, a format string and a record
literal over `state` given to an `own` parameter, though each was accepted for a plain parameter. They now check, build
and run: the read ends when the value is made, and the callee owns a value that shares nothing with `state`. `own
state.name`, `own state` and a borrow of a part of `state` (`state.name`, a call declared `from state`) stay refused with
the same code and message. `mylang fix --warnings` no longer rewrites such a copy to `take(mut state.name)`, which M5
refuses. No validator, certificate, verifier or trust-point rule changed. `experiments/audit-work-20261111/FR67.md`.

### A field written through dictionary entries, or by `+=` that reads its entry again, builds (lane FR66, 18 November 2026)

Not breaking: programs that checked but did not build now build, and every program that built before gives the same
results. `server.groups[g].conns[id].out = b"xyz"` (two or three levels of entries, a list of dictionaries, a dictionary
of lists) and `server.conns[id].sent += len(chunks[at]) - server.conns[id].sent` (in a loop or not; `-=`, `*=`; the right
side reading the same field or a sibling one; a `mut` parameter or a local) were refused by `build` and `run` with
`E_CORE_UNSUPPORTED` (rule Z3, "takes ownership of `server.groups[g]` ..., which is a borrowed part of `server`"). Core
wrote the entry into the dictionary it had read and rebuilt the records above it from a second read of the place; it now
rebuilds them from the reads the entry was reached by. No validator, certificate, verifier or trust-point rule changed.
`experiments/audit-work-20261111/FR66.md`.

### A plain parameter of a `@linear` type borrows it read-only for the call (lane FR65, 18 November 2026)

Not breaking: no program is newly refused, and every program that built before gives the same results. By the user's
decision of 18 November 2026 (LINEAR-LEND), `func column_int(host: Host, st: Stmt, column: int) -> int` is accepted where
a plain parameter of a `@linear` record, option or union was refused (`E_LINEAR_USE`, "a plain parameter is neither"):
the caller passes a named owner or a field of one with no marker, keeps it and consumes it as before, and the callee
reads it and lends it on to other plain parameters without consuming it. Moving, ending, writing, replacing or lending
it `mut` through the plain parameter is `E_LINEAR_USE` with a message that names the loan, and so is a call that also gives
the lent owner (or a record that holds it) `own` or lends it `mut`; `own` and `mut` parameters
are unchanged, and a generic function still takes a `@linear` parameter `own` or `mut`. A `mut` written only for the old
refusal still builds. Core sees the borrow of an ordinary record. `experiments/audit-work-20261111/FR65.md`.

### A call that lends a scalar field and a managed field of one record `mut` builds (lane FR62, 18 November 2026)

Not breaking: a program that checked but did not build now builds. `split_url(options.url, mut options.port, mut
options.path)`, with `port` an `int` and `path` a `str` (M5: different fields are disjoint places), was refused by `build`
and `run` with `E_CORE_UNSUPPORTED` (rule Z3, "takes ownership of a value that `split_url` still reads afterwards"), with
or without the read of `options.url`, for a local record, a `mut` parameter, a nested field (`mut a.b.x, mut a.c`) and a
dictionary entry. Core stored the scalar field back first and then rebuilt the managed field's path from the record read
before the call; it now stores the scalar field after that path. No validator, certificate, verifier or trust-point rule changed.
`experiments/audit-work-20261111/FR62.md`.

### `mylang fix` reads a field first, or moves several fields out of one record with `take`, where `own` on a field consumes the record (lane FR63, 18 November 2026)

Not breaking: the same programs are refused and accepted, with the same codes, positions and rules; only the words of
`E_SINGLE_OWNER_MOVED` after a move of a field, and which of those diagnostics carry a `fix`, change. `own state.lat` consumes the
whole record `state` (rule B8), so `Tally(lat=own state.lat, status=own state.status, flag=state.flag)` was refused at the second
move with "use copy(value)" and no edit, and an agent copied a latency list. Now a number or `bool` field of the record, or the
length of one, read after the moved field is told to come first (`Tally(flag=state.flag, lat=own state.lat)`), and where several
fields are moved out of a `mut` record the function declares, the message names the first move and offers `take(mut state.lat)` and
`take(mut state.status)` for each, with the same edits in `fix`, only where the statement is the last use of the record and the
function checks with them. A `const` record, a parameter, a later use or a field with no default to leave keeps no edit and says
that moving several fields needs `take(mut ...)` on a `mut` record. A diagnostic that carried a `fix` keeps it.
`experiments/audit-work-20261111/FR63.md`.

### `mylang check FILE` no longer repeats the warnings of every module it imports (lane R3-WARNONCE, 18 November 2026)

Not breaking: no status changes and no program runs differently; only what `mylang check FILE` prints as text. A check of one file
printed the warnings of every project module it imported, on every run, so checking file after file showed the same screens again
and an error among them was easy to miss. It now prints the named file's own warnings and, after its result, one line for each
other module that has warnings: `` helper.my: 3 warnings; `mylang check helper.my` ``. Errors in any module print as before.
`mylang check FILE --warnings` (or `MYLANG_WARNINGS=all`) lists every warning, `--diagnostics=json` carries every one, a project
that denies warnings prints them all when it fails on them, and a check that names its format (`--diagnostics=text`, which `mylang
fix` uses) prints them all, so `mylang fix FILE` and `mylang fix DIR` report what they did. `mylang check DIR`, `check-project`,
`check-module`, `build`, `run` and `test` are unchanged. `docs/tooling/native-build.md`, `experiments/audit-work-20261111/R3-WARNONCE.md`.

### `json.encode` and `json.decode` derive JSON for a program's own types (lane CODEC-S1, 18 November 2026)

Not breaking: the `codec` bound accepts more types than before and refuses nothing it accepted. `json.encode(value)` writes a value
of any type with a plain JSON form and `json.decode[T](text)` reads one, with no codec written by hand: every integer width as an
exact number (`u64` past 2^53 included; `1.0`, `1e3` and one past the width are refused), `bool`, `float` and `f32` (NaN and the
infinities cannot be written), `str`, records as objects in declaration order (a missing member takes the field's declared default, a field
without one is required, an unknown or repeated member is refused), enums (a case name, or `{"case": ..., "value": ...}` for a
case with fields), options (`null` or the value), lists and fixed arrays, up to 1,000 arrays and objects deep. A refusal is a `json.CodecError`
with a `kind`, the field `path` (`projects[3].tracker.tasks[12].stamp`), the byte `offset` and the sentence `str(error)` prints. A
decoded record whose `@invariant` does not hold fails with kind `invariant`; nothing traps. A type with a part that has no form is refused at the
call with `E_NO_CODEC` naming that part: a function, a capability or a resource, and until the next step a dictionary, a set,
`bytes`, a tuple or a `json.Json` field. Typed JSON (`mylang test --cases`) is unchanged.
`docs/standard-library.md#deriving-json-for-your-own-types`, `experiments/audit-work-20261111/CODEC-S1.md`.

### `E_RESULT_UNHANDLED` points at the binding that holds the result, with the exit as the note (lane R3-RESULTLINE, 18 November 2026)

Not breaking: the same programs are refused and accepted, with the same code and rule; only where the refusal points and its
words differ. A result held across an early `return` (`const first = step(1)`, then `const value = after else Err(_): return 1`
before `first` is matched) was reported at the `return`, so the author looked at the line of the `else` and not at `first`. The
refusal now sits on the binding, "`first` is a result still unhandled on a path out of its scope: match it, return it or write
`_ = first` before that exit", and the note is the exit: "this exit leaves while `first` is still unhandled". Refusals are still
ordered where the path leaves, so a result handled on some branches only still reports `E_RESULT_PATH` first.

### `E_RESOURCE_ORIGIN` names the inputs it counted (lane R3-RESORIGIN, 18 November 2026)

Not breaking: the same programs are refused and accepted, with the same codes, positions, rules and structured `fix`; only the
words of "a resource result requires exactly one provider or resource input" differ (friction F-3 of the load-test sample: a
function that returned a `Poller` and took a `Clock` and a `Network` beside it was refused five times with no input named). The
message now names the function, lists the inputs it counted in source order with their types, and says what to write for each
kind: read a `Clock`, `Entropy`, `Environment` or `Process` in the caller and pass the value (the time as an `int` is
`time.monotonic(clock)`); do the work that needs a `Network`, a `Filesystem` or a second resource in a function that returns a
`bool` or an `int`, the resource as `mut`. `docs/ownership-rules.md` (P3), `experiments/audit-work-20261111/R3-RESORIGIN.md`.

### `E_SLICE_ESCAPES` on an invalidated slice names the write and puts the copy last (lane FR57, 18 November 2026)

Not breaking: the same programs are refused and accepted, with the same codes, positions, rules and structured `fix`; only the
words of the refusal of a slice view that a later change to its source made unreadable (rule V3) differ. It said "this slice
view was invalidated by a move, mutation, replacement or branch of its source; bind a copy with copy(value)", which points at
the slice and not at the line that changed the source (friction W1-F-2: a write to `r.pos` ends a view of `r.buf`, and the
author took three tries). It now names the view and its slice, the lender, the write, `mut` argument or move with its line and
column, and the read that is refused, then the repairs in the order that copies nothing first: read the view before that line,
keep its span (start and length) and slice again where it is read (after a write whose source is a local or a parameter the slice
names), and the copy of the binding last. A repair that does not apply is left out. A view that became unreadable another
way (two branches gave it different sources, rule V5), or whose lender has no name, keeps the old words.
`experiments/audit-work-20261111/FR57.md`.

### A file under a hidden folder of a project imports from the project's root (lane R3-HIDDENCFG, 18 November 2026)

Not breaking for a program that works today: a module whose name has a segment beginning `__hidden_` (nothing in the four projects or the samples) can no
longer be imported, see the end. `mylang check .tmp/x.my` (and `run`, `build`, `test`, `lint`, `fix`) in a project with a `mylang.json` took the
hidden folder `.tmp` as the import root, so `import sqlite` failed `E_MODULE_READ` (`there is no sqlite.my under the import root .tmp (no mylang.json sets
it)`) although the same file in a folder named `scratch` found the project. An entry under a hidden folder is now a file of its project: its imports start at
the directory of the nearest `mylang.json` and its diagnostics name it by its path (`.tmp/x.my:5:3`). `mylang test DIR`, `check DIR` and `mylang packages`
still leave hidden folders out. The compiler names such an entry `__hidden_tmp.x` inside, and that spelling is reserved: a test run reports
`.tmp.x_test::test_a`, and `import __hidden_tmp.x` (or any import with a segment beginning `__hidden_`) is `E_INTERNAL_NAME` (`hidden folders cannot be
imported`); move the module out of the hidden folder to import it.
`docs/modules.md`, `experiments/audit-work-20261111/R3-HIDDENCFG.md`.

### `parallel.map` reads a slice or a list parameter in place, with no copy (lane FR59, 18 November 2026)

Not breaking: no program is newly refused, and every program that built before gives the same results. By the user's
decision of 17 November 2026 (PARMAP), `parallel.map(xs, f)`, `parallel.map_results` and `parallel.map(xs, f, ARGS)` accept
a slice, a plain list parameter or a `from`-returned list as the input, and a slice or a plain text, bytes or list parameter
as a trailing argument; each was refused with `E_SLICE_ESCAPES` ("write copy(...) around the input"). The tasks read the
caller's elements in place until the map returns. `try parallel.map(xs, f)` no longer copies its input: the standard
`map_fallible` passed `copy(values)` to the map, a copy the source did not show, even for a list the caller owned
(`mylang build --stats` counts one written copy fewer). A `copy(...)` written only for the old refusal still builds and
still copies. The map's worker is now a task thunk, so the IR verifier's existing task-environment rule admits the view it
holds; no verifier, validator, certificate or trust-point rule changed. `experiments/audit-work-20261111/FR59.md`.

### `process.group`: one owner for any number of started programs (lane PROCGROUP, 17 November 2026)

Not breaking: new functions and two new types; `start`, `start_to`, `run` and `Child` behave as before. A started program is a linear `Child`, so no
list, dictionary or second record field could hold one, and a job runner that ran `-j N` recipes at once wrote one local binding per slot, polled each
in turn and shelled out to `setsid` and `kill` for process groups (W3-F-1, F-2, F-3). `process.group()` makes a `process.Group`, a sealed linear owner of
as many started programs as the system lets the program start: `group_start(proc, mut jobs, request, stdout_path, stderr_path)` (and `group_start_to`
with `Destination`s) starts one as `start` does, under the same grant, and answers its key (0, 1, 2, never reused); `group_wait_any(proc, mut jobs)`
and `group_wait_any_within(proc, mut jobs, millis)` answer the key and how the first program to end ended, one that ended unseen included; `group_signal`
and `group_signal_all` signal one program or all; `group_stop(proc, mut jobs, grace_millis)` sends `SIGTERM`, waits the grace and sends `SIGKILL`;
`group_size`, `group_pid`; and `group_close(proc, own jobs, grace_millis)`, which stops the programs still running and ends the group. Each program
leads a process group of its own, so a signal reaches what it started too, and it does not hear the terminal's Ctrl-C (a program that declares a
`Stop` hears that and stops the group). The wait sleeps in a `poll` of every program's `pidfd` and wakes when one ends. A scripted Process answers
`group_start` from its rules with the program already ended. `docs/io.md#running-several-programs-at-once-a-group`, `docs/standard-library.md#process`,
`experiments/audit-work-20261111/PROCGROUP.md`.

### `network.open_client_poller` holds many outgoing connections without listening (lane CLIENTPOLL, 17 November 2026)

Not breaking: a new function; `open_poller` and `open_poller_at` are unchanged. A program that only connects out and holds many connections in one
`Poller` (a load tester, a crawler, a fan-out client) had to open a listener it never used and, under `--restrict`, be granted
`--allow-listen=127.0.0.1:0`: authority it does not need. `network.open_client_poller(net)` returns a `Poller` that listens on nothing. `dial`,
`dial_to` and their `_within` forms add connections to it, and `wait`, `recv`, `send`, `close_connection` and `connection_limit` work as they do on
the connections of `open_poller`, with the same limit (the descriptor limit less 64) and table. It needs no listen grant; each dial still needs its
`--allow-endpoint=IP:PORT`, and a launch that grants no endpoint at all is refused with 1, as `connect` is. `accept` on it answers `OUTCOME_WOULD_BLOCK`,
`wait` never reports `LISTENER`, and `port` and `set_interest` of `LISTENER` answer `OUTCOME_BAD`. `network.memory()` offers no such poller (2), as for
`open_poller`. `docs/standard-library.md#a-client-with-no-listener`, `docs/io.md#network-grants`, `SPEC.md` (NETWORK-POLL-6),
`experiments/audit-work-20261111/CLIENTPOLL.md`.

### A server gives freed memory back when its event loop idles (lane HEAPTRIM, 17 November 2026)

Not breaking: a program that never waits in a poller behaves as before. A server that stored 10,000 values of 1 KB and deleted them all still held 15 MB
(`VmRSS`), because the runtime keeps the memory a request freed so the next request does not fault the same pages in again (a heap of up to 32 MiB is
kept on purpose). `network.wait` now gives it back when it is about to block and the loop is idle: no event is ready and either its own limit is a second
or more (or none), or the waits before it found nothing for a second. It does so only after at least 256 blocks of about a kilobyte or more were freed and
the C library holds 1 MiB or more free, so a quiet server trims once and a busy one never. The server above holds 3.9 MB one idle second after its deletes
(the process alone: 2.4 MB); a server whose values were 100 KB holds 2.9 MB where it held 59 MB. A trim took about 1 ms for 11 MB and 4 to 9 ms for 57 MB; a heap with many small holes
between live blocks gives little back, and the runtime then waits 100 times as long as the look and trim took before it tries again. Small values (about a
kilobyte or less, kept in 64 KiB chunks) are still never returned to the system, only reused: 100,000 small keys keep the memory they peaked at.
`docs/standard-library.md` ("Event loop"), `SPEC.md` (RUNTIME-HEAP-RETURN-1), `experiments/audit-work-20261111/HEAPTRIM.md`.

### A program whose standard output or standard error has no reader ends quietly with status 141 (lane PIPEQUIET, 17 November 2026)

Breaking only for a program that was meant to see the old ending. `mk -n | head -5` ended with `error[R_OUTPUT]: native execution failed`, `standard
output refused a write` and status 1 once `head` had gone (W3-F-6), where a Unix tool stops quietly and a shell reports 141. A write or flush to
standard output or standard error that fails because the reader has gone (`EPIPE`) now ends the program at once with exit status 141 and no
message, writing nothing further: for `print`, `write` and `flush`, for a write larger than the stream's buffer, and for standard error, which
ignored every refusal before. The status is `main`'s no longer, and no signal is raised (the runtime still ignores `SIGPIPE`). Every other refusal
keeps its rule: a full device (`> /dev/full`) or a closed descriptor (`>&-`) still traps `R_OUTPUT` with status 1 behind standard output and is still
ignored behind standard error. A pipe the program opened itself is not this: a file opened on a FIFO whose reader has gone still traps `R_FILE`
(`write 'ff': the other end of the pipe is closed`), and the input of a program it started is still dropped from the point that program stops
reading. `mylang run` hands the 141 on, says nothing of its own, and when its own standard error is the pipe that was closed
(`mylang run prog 2>&1 | head`) stops reading the program's, which ends the same way at its next write there (it ended `mylang run` with status 2 before);
a `mylang test` test cannot meet it, since its `out` and `err` are captured. `docs/io.md` ("Stream"), `docs/logging.md`, `SPEC.md` (`STREAM-PIPE-1`),
`experiments/audit-work-20261111/PIPEQUIET.md`.

### `buffers.clear(mut data)` empties a byte buffer and keeps its storage (lane BYTEWIN, 17 November 2026)

Not breaking: a new function. A program that assembles output in a `byte_buffer`, writes it and starts the next chunk had to make a new
`buffers.empty()` for each chunk (W2B-F-10), which allocates the buffer and grows it again. `buffers.clear(mut data)` sets the length to 0 and
leaves the capacity, so one buffer serves every chunk: a loop of 1,000 fills allocates what 10 fills do (two blocks, the buffer and the room for
the first fill), where a buffer per fill allocates two each. It answers nothing, so it is a plain statement; a byte builder is emptied through its
field, `buffers.clear(mut builder.buffer)`. `data.clear()` on a byte buffer was `E_COLLECTION_METHOD` and is now `E_METHOD_REMOVED` with the
repair `buffers.clear(mut data)`, which `mylang fix` makes. The same entry of the friction log asked for a write of a part of a `bytes`: there
is nothing to add, because `write(out, data[a:b])` and `f.write(data[a:b])` already pass a view of the owner's octets and copy nothing (1,000 such
writes allocate nothing, where `copy(data[a:b])` allocates for each); the guides now say so. A slice of a `byte_buffer` is a new buffer and does
copy. `docs/standard-library.md` ("buffers"), `docs/bytes.md`, `docs/io.md`, `experiments/audit-work-20261111/BYTEWIN.md`.

### `try` is accepted as an operand: `try f() + 1`, `if n > 5 and try ok(n):`, `assert try f() == x` (lane TRYOP, 17 November 2026)

Not breaking: programs refused before are accepted; nothing accepted is refused, and nothing accepted changes meaning. `try` binds to the call
after it (with its `.`, `[]` and call suffixes) and an operator after it takes the call's value, so `try f() + 1` is `(try f()) + 1`. It stands
anywhere a value is computed at run time: arithmetic and comparisons, `and`/`or`/`not`, an index or slice bound, a list or dictionary element,
a format string's hole, the condition of `if`, `elif`, `while` and `assert`, a `match` subject, a `for` list and a `return` or `fail` value.
Operands run left to right; a failing `try` leaves before anything to its right runs, and what the left made is destroyed once. Under
`and`/`or` it runs only when its side does; in a `while` condition on every test. A `@linear` owner, a pending result, an armed `on fail:` and a
`detach` loop refuse it as they refuse a `try` in an argument. Still `E_TRY_POSITION`, each naming what to write: `try` over an operator
expression (`try (a + b)`, `try -f()`), and `try` in a module constant or a default. `mylang fix` no longer declares such a `try` on a line of
its own (every place it did is accepted now), and the old postfix `f()?` becomes `try f()` in place in an operand too (`(try f()).x` before a
suffix). `docs/results-and-options.md#try-in-an-operand`, `experiments/audit-work-20261111/TRYOP.md`.

### A relative `--import-root DIR` of `mylang test` is taken from the working directory (lane PKG-B, 17 November 2026)

Not breaking: a run that named an absolute folder is unchanged. `mylang test rows/more_test.my --import-root .` and `--import-root sub` were silently
ignored (the entry kept its own folder as the import root and failed `E_MODULE_READ`), because the entry's path was compared with the folder as typed, and
only an absolute one matched. A relative folder is now resolved against the working directory, as every other path option is. The note a directory run
ends with names `--import-root DIR` without "an absolute path". `docs/tooling/guest-tests.md`, `experiments/audit-work-20261111/PKG-B.md`.

### `mylang packages` and `mylang test DIR` walk the same folders (lane PKG-B, 17 November 2026)

Breaking only for a program that imports from a folder the walk now leaves out. `mylang packages build` and `mylang packages lock` read every folder under
the application's folder and under a package root, hidden folders, `build`, `zig-out`, `node_modules` and the compiler's cache folder included, so a link
to a folder anywhere in them (a scratch tree under `.tmp/`, a vendored `node_modules`) refused the whole build with `symbolic-link directories are
rejected`, their `.my` files were staged, and a cache folder of fifteen thousand files counted against the 50,000-entry walk budget. They now leave out
what `mylang test DIR` leaves out, by one rule and one function (`release_project.walkSkips`): a folder whose name begins with `.`, `build`, `zig-out` and
`node_modules` at any depth, the `--cache-dir` folder (named among the words after `--`), and the paths `release.exclude` of the project's `mylang.json`
lists. Nothing in them is read, and a module in one is not staged, so a program that imports a module from `build/` or `node_modules/` cannot be built
through `packages` (move it); a lock written before that pinned such a file in a package is refused as `locked dependency changed` until the package is
locked again. `tmp/` is not left out, by either command: scratch that holds links to folders belongs in a folder whose name begins with `.`, such as `.tmp/`,
or in `release.exclude`. A link to a folder in a folder they do walk is still refused, with the message it had. `docs/tooling/packages.md`,
`docs/tooling/guest-tests.md`, `experiments/audit-work-20261111/PKG-B.md`.

### A test module needs no interface file, and an application that sets `interface_files` can be built through `mylang packages` (lane PKG-B, 17 November 2026)

Not breaking: every project that passed before still passes; a check that asked for a file now asks for fewer. With `"interface_files": true`,
`mylang test m_test.my` and `mylang check m_test.my` asked for `m_test.api`, which `mylang api m.my --write` never wrote, since nothing imports
a test module. A module named `*_test.my` now needs no interface file and `mylang api` writes none for it (a file written for one before is
left alone and never compared). Through `mylang packages build`, the snapshot held no `.api` file, so every module was reported missing and
`mylang api main.my --write` could not see the package to write the application's. The snapshot now holds the `.api` files beside the application's
sources, the check asks none of a package's modules (the lock pins their bytes), and `mylang packages build ENTRY --lock LOCK --command api -- --write`
(or `--check`) writes the application's own files through the snapshot and copies them back, refusing, with none written, when one changed since the
snapshot was taken. The missing-file line names that command in place of `mylang api` of the private snapshot. `docs/tooling/packages.md`,
`docs/tooling/interface-files.md`, `experiments/audit-work-20261111/PKG-B.md`.

### A package named like a standard module is refused (lane PKG-B, 17 November 2026)

Breaking only for a lock that could never have worked: `mylang packages lock` accepted a package called `strings` and `build` staged it, but
`import strings` always loads the standard module, so the package's functions were never reached and a call to one failed as `module strings declares
no ...`. `lock` now refuses the name, and `build` refuses a lock written before, with `` package strings is named like the standard module `strings`,
which `import strings` always loads ``, the rename to make and "lock again". No program that built through such a lock calls anything of the package, so
none changes meaning: drop the package from the manifest or rename it. `docs/tooling/packages.md`, `experiments/audit-work-20261111/PKG-B.md`.

### Three messages of `mylang packages` and a directory test run say what to do (lane PKG-A, 17 November 2026)

Not breaking: no program is accepted or refused differently; the text, and one line on standard error, change. A package source that is neither `NAME.my` nor under
`NAME/` was refused with `dependency source must declare its package namespace: inner.my`, though a source declares nothing; `mylang packages lock` and `build` now
say `` package rex: ../pkg/inner.my is neither rex.my nor under rex/, ... move it to ../pkg/rex/inner.my and import it as `import rex.inner` ``. The words of
`mylang packages build --command run-project -- WORDS` go to `run-project` as its options, and a program's own arguments need a second `--`; a word that
`run-project` refuses (``'ing$'``) printed the usage of `mylang run` and nothing else, and now the refusal names the word and shows the line with the second `--`
(a real usage error, such as an option given twice, still prints the usage). A directory test run that has a file with no `mylang.json` over it that fails to
check or build now ends with a note naming the two ways to give it an import root (a `mylang.json`, or `--import-root DIR` with an absolute path), and a `mylang.json`
of the directory itself that cannot be read is named with its line and reason where the run printed only `MissingVersion`. `mylang docs tests` now lists the folders a
directory run skips and says that `tmp/` is walked. `docs/tooling/packages.md`, `docs/tooling/guest-tests.md`, `experiments/audit-work-20261111/PKG-A.md`.

### `a ? b : c` inside a call's arguments says what `?` does (lane MSG-G, 17 November 2026)

Not breaking: the program is refused as before (`E_SYNTAX`, at the same token); only the text changes. `a ? b : c` as a statement said that `?` after a value only passes its
failure on and named the `if`/`else` and `match` forms, but `f(a ? 1 : 2)` stopped with "unexpected token; expected )" and no repair. The same message, with the same advice, now stands
where the conditional is written inside the arguments of a call or a method call, a parenthesis or a tuple, a list, an index, or a dictionary or set literal. A declaration such as
`func f(x: int? y: int)` keeps its text: there the `?` is a type. `src/declaration_hints_test.zig` pins each position.

### The functions a Python, JavaScript or Rust author guesses on a list or a dictionary are answered with the loop or the builtin that does the job (lane MSG-G, 17 November 2026)

Not breaking: no program is accepted or refused differently (the code stays `E_UNKNOWN_SYMBOL`, at the same place, with no `mylang fix` edit, since the rewrite is a loop); the message
changes. `lists.map` was "did you mean `pop`?", `lists.filter` "did you mean `filled`?", `dicts.any` "did you mean `add`?", `lists.zip` "did you mean `pop`?", and `lists.reduce`,
`lists.sum`, `lists.count`, `lists.enumerate`, `lists.rindex` said nothing. Each now says what the language has for the job, with the loop written out: `map`, `filter`, `reduce`,
`fold`, `each` and `for_each` (on a list, a set and a dictionary) are a `for` loop that collects into a typed accumulator or into `total += item` (there is no lambda to pass; `parallel.map(values,
double)` applies a named function to every element of a list on several threads); `any` and `all` are a loop that keeps the answer, and the builtins `any(flags)` and `all(flags)` take a list
of `bool`; `sum` is the builtin `sum(values)` (`sum(list(dicts.values(mapping)))` for a dictionary); `count` is `len(values)` or a counting loop; `enumerate` and `zip` are the builtins
that stand in a `for`; `lists.rindex` is a loop over `enumerate(values)` that keeps the last `index`; `sets.find` names the operator `in`, and `dicts.index` the key (`mapping[key]`,
`dicts.find`, `dicts.get`). `src/guessed_names_test.zig` writes each quoted loop into a program and checks it.

### The argument-count message of a file helper shows the spelling that works (lane MSG-G, 17 November 2026)

Not breaking: no program is accepted or refused differently (the code stays `E_ARITY`, at the same place); only the text changes. A file helper called with the
wrong number of arguments printed the free form, `write_text(fs: Filesystem, path: str, text: str) -> Result[Unit, str]`, which the compiler refuses as a removed
spelling, and a note that told the author to write `open(fs, path, mode)`, refused for the same reason. The message now prints the method of the capability,
`` `fs.write_text(path: str, text: str) -> Result[Unit, str]` takes 2 arguments, but this call passes 1 ``, and `input.read(max: int) -> bytes` for the `Input`
methods; a call written in the free form says that the free spelling was removed and which method takes its place. The standard library's channels (`run_process`,
`process_control`, `stop_control`) called outside the library say they are the library's own and name the `process` module's functions. Each printed spelling
is checked on the compiler by `src/advice_messages_test.zig`.

### A task given a list, text or bytes parameter reads what the caller passed (lane FR58, 17 November 2026)

Not breaking: nothing `check` accepts or refuses changes. This fixes a wrong result. `func by_list(xs: int[])` that ran
`g.submit(weigh, xs)` in a `with parallel.group() as g:` block gave the task an empty list when the caller passed a slice
(`by_list(ys[1:3])`), with no diagnostic; a `str` parameter gave an empty text the same way. The task was handed the
parameter's hidden cache owner, which is a static empty placeholder for a slice. It is now lent the view itself, as a direct
call passes it, with no copy: `by_list(ys[1:3])` gives the task `[20, 30]`. A plain `bytes` parameter given to a task, which
`mylang build` refused with "the new core does not support a bytes parameter given to a task", now builds and runs the same
way. A slice of text or bytes written at the submit itself (`g.submit(f, data[0:2])`) is refused as before, now with
"the new core does not support a slice of bytes given to a task yet" (or "of text") in place of "a bytes parameter given
to a task"; a slice of a list there is copied into a new list, as before. `parallel.map` keeps its `E_SLICE_ESCAPES`
refusals. The task's environment is the one place a view is now stored, so by the user's decision of 17 November 2026 the
IR verifier's `view-storage` rule and its Lean copy (`proofs/verify_ir/VerifyIr/Check.lean`, `taskEnvironment`) both
admit it, and the trust point A7.2 (`proofs/ownership/AXIOMS.md`) says the validator does not follow that loan through the
box. `experiments/audit-work-20261111/FR58.md`.

### A poller holds as many connections as the process may open, not 1,024 (lane POLLER, 17 November 2026)

Not breaking: a poller that held 1,024 connections or fewer behaves as before, with the ids it always gave. A server that kept 2,000 idle
connections and had to serve a 2,001st found every `connect()` succeed, only 1,024 accepted, `network.connection_limit` answering 1024 and the last
client unanswered (W5-F-1). A `Poller` now holds as many connections as the process may open descriptors, less 64 kept for the rest of the program,
and at most 1,048,576: `connection_limit` answers that number in `value` (524,224 where the hard limit is 524,288; `ulimit -n 2000` gives 1,936). The
poller raises the soft descriptor limit to the hard one when it opens, as it raised it toward 1,088 before; a program this one starts with
`process` (`run` or `start`) gets back the soft limit this program started with, so a helper that uses `select` is not handed 524,288. Its table starts at 1,024 slots, so an
idle poller holds the memory it did, and doubles as connections arrive: a slot costs about 50 bytes. At the limit `accept` answers `OUTCOME_FULL`
as before, and an `accept` that the process has no descriptor for answers `OUTCOME_FULL` too, where it answered `OUTCOME_FAILED` with the
errno. The first 1,024 connections of a poller have the ids they had (1,024 and up); the ones after them have ids from 2,147,483,648 up, still never
0 and still never the id of a closed connection. Open files, listeners and blocking connections keep their bound of 256 open handles. `docs/standard-library.md`,
`docs/design/event-loop-2026-10-18.md`, `SPEC.md`, `experiments/audit-work-20261111/POLLER.md`.

### `strings.format_shortest` writes a float with an exponent where the plain form is long (lane FLOATTEXT, 17 November 2026)

Not breaking: a new function; `str(x)`, f-strings, `format_float` and `format_decimal` print what they printed. `str(1e300)` is 301 digits and
`str(5e-324)` a point and 323 zeros, so a program that prints numbers as JSON or as `jq` does had to cut digits out of `str` and lay them out itself.
`strings.format_shortest(value)` answers the shortest text that `parse_float` reads back as the same float, by Python's `repr` rule: `str(value)` from
1e-4 up to but not including 1e16 (`"0.0001"`, `"100000.0"`), otherwise the shortest digits with an exponent of a sign and two digits at least
(`"1e+300"`, `"1.5e-05"`, `"5e-324"`, `"1.7976931348623157e+308"`). Negative zero is `"-0.0"`, an infinity or a NaN is `str`'s `"inf"`, `"-inf"` or
`"nan"`. It matches Python's `repr` on the 110 vectors of its test and reads back as the same bits for every power of ten from 1e-320 to 1e308. Go's
`'g', -1` starts its exponent at 1e6 and `jq` when the zeros after the digits pass 15, so a program that must print theirs lays those out from this
text. `docs/standard-library.md#strings`, `experiments/audit-work-20261111/FLOATTEXT.md`.

### `math.to_int` and `math.to_int_saturating` convert a float to an integer without the trap (lane FLOATTEXT, 17 November 2026)

Not breaking: two new functions; `int(x)`, `i8(x)` to `u64(x)` still trap `R_FLOAT_CONVERSION` on not-a-number, an infinity and an out-of-range value.
`math.to_int(value)` answers `Some(int(value))`, and `None` where `int(value)` would trap. `math.to_int_saturating(value)` never traps: a value from 2^63
up gives 9223372036854775807, one below -2^63 gives -9223372036854775808, not-a-number gives 0, every other value truncates toward zero as `int` does.
`docs/standard-library.md#math`, `experiments/audit-work-20261111/FLOATTEXT.md`.

### `flate` inflates in pieces, and `crc32` and `adler32` have running forms (lane GZSTREAM, 17 November 2026)

Not breaking: `flate.inflate`, `flate.zlib_decode`, `flate.gunzip`, `flate.crc32` and `flate.adler32` keep their names, results, messages and limits, and no
program that ran before runs differently. They took all the compressed bytes and gave all the plain ones, so a `.tgz` cost its decompressed size in memory (a
5 MB gzip of 5 GiB of zeros took 4.2 GB before the limit refused it) and a program that inflated in pieces itself could not check a trailer. New:
`flate.inflater(limit)`, `flate.zlib_inflater(limit)` and `flate.gzip_inflater(limit)` make an `Inflater`, a value passed with `mut`;
`flate.feed(mut stream, piece)` takes the next piece of compressed bytes, which may end anywhere, and returns the plain bytes it yields; `flate.ended(stream)`
and `flate.finish(stream)` say, once all the input is fed, whether the stream ended cleanly and with which of the one-shot functions' messages it did not.
A stream holds the 32 KiB window and one piece, never the output: a gzip of 1 GiB of zeros inflates in 6 MB, several gzip members and their CRC-32 and size
included. A call returns about a mebibyte at most; when it returns something, call again with `b""` until it returns nothing. `flate.crc32_update(value, data)`
and `flate.adler32_update(value, data)` take the checksum so far (0 and 1 for no bytes) and give it with `data` after, so `crc32(a + b)` is
`crc32_update(crc32(a), b)` over any cut. The one-shot functions are now the inflater fed one piece: the same bytes and messages on 4,620 damaged streams
against the old code, about twice as fast on text (a 100 MB gzip: 0.8 s of processor time against 1.6 s) and `crc32` is about 2.4 times as fast. A guest test
that inflates small streams executes fewer blocks than before, not more (one call of `gunzip` on a stream of 70 bytes: stored 255 blocks against 6,454,
fixed-code 5,447 against 9,700, dynamic-code 13,481 against 15,898, of the default budget of 1,000,000 blocks a test counts). A cold check of a program that
imports `flate` takes 0.25 s instead of 0.05 to 0.10 s (`docs/source-evaluation.md`). The module does not compress. `docs/standard-library.md`,
`docs/source-evaluation.md`, `tests/lang/standard_flate_stream.my`, `experiments/audit-work-20261111/GZSTREAM.md`.

### `network.recv` and `send` no longer clear and copy a 16 KiB buffer per call (lane KVPERF, 17 November 2026)

Not breaking: what `recv`, `send` and a connection's `read` and `write` return, append and trap on is the same at every size from 0 to 16,385 bytes
and under a peer that closes midway; only the work per call changes. The key-value server of the W5 program spent a quarter of its time in `memmove`
and a tenth in `memset` because `recv` read its answer into one array of 16,396 bytes, which the runtime cleared twice and the compiled code copied
several times, for a request of 30 bytes. `recv` now reads the first 256 bytes of an answer (the 12-byte header and 244 of payload) and, if there
is more, the rest in one array sized for it; a read of a file or a socket hands the runtime's own provider the destination block itself, with one
clear of the bytes it did not fill, and `write` hands it the caller's bytes without a private copy; `send` and every command reserve the bytes they
build. 200,000 messages of 30 bytes over a loopback pair, one process, `--release`: 1,201 million instructions before, 849 million after, and 1,285
million user cycles before, 487 million after; the key-value server runs 12,850 instructions per non-pipelined request before and 10,050 after (GET
12,700 and 9,860); messages of 16,384 bytes cost the same and pipelined requests 0.8% more. Memory that a server frees stays in the process (the
runtime keeps free heap up to 32 MiB on purpose); that is not changed. `experiments/audit-work-20261111/KVPERF.md`.

### An `own` marker keeps its repair beside another error of the same function (lane FR61, 17 November 2026)

Not breaking: what `check` accepts and refuses is unchanged; only which `E_OWN_MARKER` carries a fix, and one message, change.
The `own` repair was proven by re-checking the whole function with the marker written, so any other refusal in the function
withheld it, while the message still read "write `own a` to give it". Now the repair stands when the function without the
marker stops at the same refusal and the moved local is used nowhere else and moved once per declaration; `mylang fix` writes
it and the next check prints the other error. When the repair is still withheld, the message reads "the repair waits for the
error at line L, column C: once that is repaired, write `own a` to give it, or `copy(a)` to keep both".

### A record that holds an open file is refused where it is declared (lane HOLDFILE, 17 November 2026)

Breaking only for a declaration that nothing used. `record Holder: f: File` passed `mylang check` and `mylang build` when no function had a
local, a parameter or a return of that type, and was refused with `E_WITH_RESOURCE` the first time one did, so the same declaration was accepted
in one program and refused in another. It is now refused where it is written, with the words the refusal of a local gives (an open file belongs
to its `with` block; call its methods there, or lend it to a helper declared `mut f: File`). That covers a field of `File` or `TextFile`, a list,
dictionary or option of them, a variant case, a generic record instantiated with one and a callback type that takes or returns one. A generic
type is refused where it is instantiated, at the spelling that names it (`Box[File]` in a field, a parameter or a local), and `Box[V]` itself is
not refused. A `result` whose `ok` case is a file (what `fs.open` returns) is still accepted. `Connection`, `Poller` and `process.Child` follow
their own rules and are unchanged.
There is no `mylang fix` migration: the change refuses programs that were accepted and no edit is certain, because a program that stores a file
has to be restructured. None of `tests/lang` or the four projects was affected; the one shape that was accepted is `_ = Holder(r=own f)`, building
a record that holds a file from `try fs.open(...)` and dropping it. One verdict loosens: a fixed array of no elements stores nothing, so
`FixedArray[TextFile, 0]` in a local, a parameter or a return, which was refused, is accepted, as it already was in a record declaration.
`experiments/audit-work-20261111/HOLDFILE.md`.

### `for x in detach r.items:` loops over a record's list while the body changes the record (lane LOOPDETACH, 17 November 2026)

Not breaking: a new form; nothing that `check` accepted or refused before changes, and `detach` stays usable as a name. `for it in ev.items:` with
`resolve(it.expr, mut ev)` inside is `E_SINGLE_OWNER_OVERLAP`, because `resolve` could change `ev.items` under the loop; the repair was a loop over
positions that copies each element. `for it in detach ev.items:` moves the list out of its place for the loop (the place is empty while it runs) and
puts it back at every exit: running out, `break`, `return`, `fail` and a `try` whose error leaves. The value of a `return` or `fail` is computed
before the put-back, and one that borrows the loop variable is refused with the copy or position to return instead; `x = try f()`, `return try f()`
and a `try` in an argument are `E_TRY_POSITION` in the loop. A place that the body or a callee wrote while it was set aside traps `R_ASSERT` at the
put-back, naming the place and the loop's line. The message of `E_SINGLE_OWNER_OVERLAP` for this loop and `mylang docs card` now name passing only
the field the callee changes, then the `detach` loop, then the loop over positions. `docs/value-semantics.md#setting-a-list-aside-for-a-loop`,
`experiments/audit-work-20261111/LOOPDETACH.md`.

### A guessed library name is answered with what does the job for that value, not with a module that cannot take it (lane MSG-F, 17 November 2026)

Not breaking: no program is accepted or refused differently (the code stays `E_UNKNOWN_SYMBOL`, at the same place); the message changes, and `mylang fix` writes
a `rename` or the operator `in` where the edit is certain. `strings.index(text, part)` was "did you mean one of: `char_rindex`, `text_rindex`, `char_index`? The
standard module `bytes` declares a function `index`", `strings.has` sent the author to `argparse` and `network`, `strings.is_empty` to `spans`, `strings.compare` to
`spans` and `time`, `lists.find` to `bytes`, `dicts`, `strings` and `symbols`: each a module that cannot take the value in hand. The names that agents guessed are
now answered for the kind of value: `strings.index` and `strings.rindex` name `strings.text_index(text, part)` and `strings.text_rindex(text, part)` (byte offsets,
trapping when absent; `strings.find` answers `None` instead, `strings.char_index` counts scalars); `lists.index` names `lists.index_of`, and `lists.find` the same
with `lists.contains`; `has` and `includes` of text, bytes, a set or a dictionary name the operator `in` as `contains` does (MSG-B), and of a list `lists.contains`;
`is_empty` and `len` name the builtin `len(text)`, `len(values)`, `len(mapping)` (and `strings.char_count` for scalars); `empty` names the literal (`""`, `b""`, or `mut values: int[] = []`, `{}` and `set()` with their types named); `strings.compare` names the comparison
operators and `sort.compare_strs(a, b)`, `bytes.compare` the operators. A pointer to another module ("the standard module `bytes` declares a function `index`") is now
given from `strings`, `bytes`, `lists`, `dicts` and `sets` only to a module whose function of that name takes the same kind of value first (`strings.basename` names
`path.basename`; `lists.join` names `strings.join` and `bytes.join`, no longer `path` and `spans`); any other module's miss is unchanged. `mylang fix` renames
`lists.has` and `lists.includes` to `lists.contains` (the same meaning) and rewrites `has` and `includes` of text, bytes, a set or a dictionary as `part in text`; it
makes no edit for `strings.index`, `strings.rindex` or `lists.index`, whose answers trap when the part is absent where the author may have meant `-1` or `None`. `docs/tooling/fix.md`, `src/guessed_names.zig`, `src/standard_library.zig`, `experiments/audit-work-20261111/MSG-F.md`.

### `csv.parse_fields` keeps whether a field was quoted, and the guide says what `csv.parse` accepts (lane CSVQUOTE, 17 November 2026)

Not breaking: a new function and a new record; `parse`, `parse_table`, `write`, `write_table` and `Error` read and return what they did, and no
program that ran before runs differently. `csv.parse` returns text, so `a,,b` and `a,"",b` gave the same row, and a program for which an empty
unquoted field is NULL and `""` is empty text had to write its own scanner. `csv.parse_fields(text)` reads the same documents, accepts and refuses
exactly what `parse` does with the same messages, and returns `Field[][]`, each `Field` holding `text: str` and `quoted: bool` (whether the document
wrote the field inside quotes): `a,,b` gives `quoted` `False` for all three and `a,"",b` gives `True` for the middle one. A `Field` record rather
than a parallel `bool[][]` keeps a field and its flag together when a program filters or reorders rows, as `Table` keeps a header with its rows.
The guide's "csv" section now lists what `parse` accepts and refuses, each case from a run: a doubled quote, a line break (LF, CRLF or CR) inside a
quoted field, LF, CRLF and bare CR row endings, a last line with no ending, an empty line as an empty row, a quote in an unquoted field, text after a
closing quote, and a byte-order mark (not removed: it stays in the first field, and before a quote it is refused at line 1, column 4), with the
line and column of each error (a column counts bytes, a line counts LF). `tests/lang/csv_quoted_fields.my`, and `tests/lang/csv_python_vectors.my`,
which checks `parse`, `write` and `parse_fields` against Python's `csv` module on 200 generated rows. `docs/standard-library.md`,
`experiments/audit-work-20261111/CSVQUOTE.md`.

### `filesystem.create_mode`: a file opened for writing is created with its mode (lane FS3, 17 November 2026)

Not breaking: one new function and builtin. `fs.open(path, "wb")` creates a file with the default mode, and `chmod` can only follow
the data, so an archive member recorded `0o600` was readable by the group while it filled (a folder has `filesystem.mkdir_mode` for the
same reason). `filesystem.create_mode(fs, path, mode) -> File fails str` (also `fs.create_mode(path, mode)`, which a `with` may open
directly) opens `path` for writing as `fs.open(path, "wb")` does, and a file it creates has the permission bits `mode` from the
`open(2)` that makes it (the umask narrows it, as `creat(2)`'s). A file that exists is truncated and keeps its own mode, as
`fs.open(path, "wb")` leaves it. The path rule is that of every write; failures read `open 'PATH': REASON`; `memory()` keeps the mode as
given. `docs/io.md` ("Real paths, permissions and times"), `docs/standard-library.md`, `src/features.json`.

### A narrowed `Filesystem` names a file whose name holds a backslash (lane FS3, 17 November 2026)

Not breaking: only calls that were refused now work. A handle from `fs.dir("d")`, `filesystem.dir_at(fs, d)` or `read_only()` of one
refused every path with a backslash in it (`denied: a Filesystem narrowed by fs.dir takes a path inside its folder, ...`) while the plain
`fs` wrote and read the same name, so a program confined to its output folder could not restore a file named `a\b`. On Linux, the one
system the compiler targets, a backslash is a byte of a name: the narrowed handle now takes it, `..\x` and `a\..\b` are names in the folder
and climb nowhere, and `fs.dir("a\\b")` is a folder of that name. A NUL is still refused. `docs/io.md`, `SPEC.md` (FILESYSTEM-DIR-1).

### `filesystem.stat_follow("/dev/stdin")` describes a pipe instead of failing (lane FS3, 17 November 2026)

Not breaking: a call that failed now answers, nothing that answered changes. Without a restriction, `stat_follow` of a path that
leads to a pipe or a socket through the kernel's own links (`/dev/stdin`, `/dev/stdout`, `/dev/fd/N`, `/proc/self/fd/N`) failed
with `the path does not exist` while `fs.open` of it read it: the call asked the kernel for the object's path, which a pipe does
not have. It now answers what `stat(2)` answers, a `Stat` of kind `Other`. Under `--restrict` and on a narrowed handle nothing
changes: such a path is refused, as `fs.open` of it is. `docs/io.md`, `experiments/audit-work-20261111/FS3.md`.

### `mylang packages fix` repairs a program that imports a locked package (lane FR55, 17 November 2026)

Not breaking: a new subcommand, and one changed closing line of a run through `mylang packages build`. A program that imports a locked package
had no automatic repair: `mylang fix main.my` beside it ends `E_MODULE_READ`. `mylang packages fix ENTRY|DIR --lock LOCK [SWITCHES]` verifies the
lock as `build` does, stages the program and its packages privately and runs `mylang fix` there with the switches given (`--check`, `--warnings`,
`--imports`, ...), by `fix`'s rules and with the user's paths in its summary. A repair that edits a package's file is never applied; the summary counts
them per package in one line (`` fix: left 2 fixes in package `rex` alone: `mylang packages fix` never writes a package's files ``). Only the files
`fix` changed are written back, and only when each still holds the bytes it was staged from; otherwise nothing is written and the run exits 2. A check,
build, run or test through `mylang packages build` that printed repairable diagnostics now ends `` `mylang packages fix main.my --lock lock.json
--warnings` repairs 3 of these 3 `` where FR53 left no line, counting no diagnostic in a package's file. `mylang fix` without packages is unchanged.
`docs/tooling/packages.md`, `docs/tooling/fix.md`, `experiments/audit-work-20261111/FR55.md`.

### `mylang docs card` is rewritten from what eleven programs written from it cost their authors (lane CARD, 17 November 2026)

Not breaking: no program is accepted or refused differently, so there is no migration; the text of `mylang docs card` changes, still at most 6,000
characters. Eleven programs were written by agents that had only the guides, and their 2,497 compiler runs were counted by diagnostic code. The card now
opens with `mylang check FILE`, then `mylang fix FILE`, and says what `fix` writes (ownership, imports, `try`, removed spellings), because most of the
failed runs were codes it repairs. New on it: the loop over a record's list with a `mut` call on the record (`E_SINGLE_OWNER_OVERLAP`) and the loop over
positions that repairs it; a module constant needs its type; `bit_and`, `bit_or`, `bit_xor`, `shift_left` and `shift_right` for `& | ^ << >>`; a slice is
a borrowed view; `"b" in t` tests text and `strings.contains` does not exist; where imports start and what `mylang.json` sets (`E_MODULE_READ`); `try` as
a whole argument or an assignment's value but not in a condition; a `Result` has no methods; `mylang docs io`. Two statements were wrong and are
corrected: `mylang check` prints `W_NEEDLESS_COPY` without `--warnings`, and an enum pattern is `case rect(w, h)` (`case rect(w=w, h=h)` draws a
warning). Lines no run needed (`time.now(clock)`, `char_at`, the quoting examples, `exchange`, `E_IS_BINDING`) are gone. `docs/card.md`, `experiments/audit-work-20261111/CARD.md`.

### A field of a dictionary's element held in a record can be read and then assigned (lane FR54, 17 November 2026)

Not breaking: nothing `check` accepts or refuses changes. `func f(mut server: Server, id: int)` that read `server.conns[id].out` (a `dict[int, Conn]`
field, `Conn` holding `out: bytes`) and then assigned `server.conns[id].out = ...` passed `mylang check` and failed `mylang build` with the internal
`E_OWNERSHIP_VALIDATION` (J4, "operand %10 (borrowed) is not usable here"); so did `server.conns[id].out = g(server.conns[id].out)` and
`const queued = server.conns[id].out` before the write, which is what `mylang fix` makes of the `copy(...)` workaround. The ownership pass merged
the assignment's take of `server.conns` into an earlier read of it that ran before the last use of a view of the element's field: its walk of
what a read lends stopped at a dictionary's entry and at a span view. It now follows both, past every part but a plain scalar (`lendsFirst`,
`holdsNothing` in `src/core/own.zig`), so the take stays at the assignment; these functions build, validate and run, as does a loop that reads
and updates such an element's fields around a call. `experiments/audit-work-20261111/FR54.md`.

### The argument-count message of a file helper prints `Result[Unit, str]` (lane MSG-E, 17 November 2026)

Not breaking: only the text of an `E_ARITY` message changes. ``write_text(fs: Filesystem, path: str, text: str) -> Result[None, str]` takes 3 arguments, but
this call passes 2`` printed `Result[None, str]` for every whole-path helper that gives nothing back (`write_file`, `mkdir`, `remove`, `rename_path`,
`chmod_path` and the others), a spelling the compiler refuses as a type (`use the canonical array, optional or Unit type spelling`); it now prints
`Result[Unit, str]`, which is the one `docs/io.md` uses for `f.sync()` and the one a declaration of the result takes.
`experiments/audit-work-20261111/MSG-E.md`.

### `mylang fmt --check` says what the formatter wants at the first difference and names `fmt --write` (lane MSG-E, 17 November 2026)

Not breaking: the exit status and the output on a formatted file (nothing, status 0) are as before, and the line still begins `path:line:column: formatting
differs`. After 1,500 lines written with one blank line between module-level constants the check named the first line and nothing else, and `fmt --diff`
showed the cause (W5-F-9). The same line now continues with what the formatter wants there, read off the two texts, and ends with the repair:
``input.my:3:1: formatting differs: line 1 is followed by one blank line, and the formatter wants two blank lines between top-level declarations;
`mylang fmt --write input.my` repairs it``. A run of blank lines of another length, trailing whitespace, another indent, a missing final newline and blank
lines at the end of the file each have their own wording; any other difference quotes the line as written and as wanted. `fmt-project --check` and a project
run say it for each file.
`docs/tooling/formatter.md`, `docs/primer.md`, `experiments/audit-work-20261111/MSG-E.md`.

### `x >> 2` and the operators of C are answered, as `x << 2` was (lane MSG-E, 17 November 2026)

Not breaking: every program refused before is refused now, at the same place unless said, and none is accepted; only the text changes. `x >> 2` was
`E_EXPRESSION: expected an expression` while `x << 2` said "`<<` and `>>` are not operators" and named `shift_left(value, count)` and `shift_right(value,
count)` (SP1B-F-4); the parser looked for the second `<` of a pair and not the second `>`. Both now say it, and so do the augmented `x <<= 1` and `x >>= 1`;
`x **= 2` says what `x ** 2` says. `x++`, `++x` and `x--` (before a line that is no operand) said "expected an expression" or nothing useful: they now say
`++` and `--` are not operators and name `x += 1` and `x -= 1` (for `--` the message stands on the pair). `x &= 3`, `x |= 3` and `x ^= 3` named only a set's
spellings; the note now also writes `x = bit_or(x, y)` (`bit_and`, `bit_xor`) for an integer. `~x` was `E_TOKEN: unexpected character in source`; it is
`E_REMOVED_SPELLING` and says to write `bit_not(value)`, as `!` says `not`. `a ? b : c` was `unexpected token; expected a newline` at `b`; it says that `?`
after a value only passes its failure on and that the result is declared first and assigned in an `if`/`else`, a `match` or a `return` in each arm. No
`mylang fix` edit for any of them: the shifts stop at the second operator, before the right operand is read, so the edit would not be certain.
`docs/python-syntax.md`, `docs/integer-operations.md`, `experiments/audit-work-20261111/MSG-E.md`.

### `pax.size = f() else:` on a field or an element names the forms that work (lane MSG-E, 17 November 2026)

Not breaking: no program is accepted or refused differently, and the refusal stays where it was, at the `else`. An assignment to a field or an element
followed by an unwrapping `else`, `pax.size = parse_int(text) else:` or `xs[i] = read(n) else Err(m):` (or a compound operator), was `E_SYNTAX:
unexpected token; expected a newline` (SP1B-F-3), although the same line for a declaration is the documented form. It now says, in the voice of the
message for a local, that the `else` unwraps into a new name and so belongs to a declaration, and writes the three forms that do the job for a place:
`const value = parse_int(text) else:` and then `pax.size = value`, `pax.size = try parse_int(text)` in a function that can fail (that returns an
Option, for an Option), and `if parse_int(text) is Some(value):` (`Ok(value)` for a Result) with the assignment inside. It carries no `mylang fix`
edit: each form needs the author's choice of a name or of a block. A value that is itself a `try` keeps the old text.
`docs/statements.md`, `experiments/audit-work-20261111/MSG-E.md`.

### A build through `mylang packages` no longer prints a package's warnings or a `mylang fix` line (lane FR53, 17 November 2026)

Not breaking: no program that ran before runs differently, no status changes and no recorded result changes; only what a build, check, run or test
through `mylang packages build` prints. A program built against a package printed the package's own warnings (two for a regex package, each with the
source line of a file its author may not read) among its own, and ended `` `mylang fix /tmp/mylang-packages-06d0744955246975/main.my --warnings` repairs 5
of these 5 ``, counting them and naming a temporary copy. The warnings of the files of a locked package are now not printed, and one line per package says
how many were left out (`` 2 warnings in package `rex` are not shown ``), the same on a build and on its replay. Such a run prints no `mylang fix` line:
`mylang fix` does not know the package (`mylang fix main.my` reports `E_MODULE_READ`), so a repair in the program's own files is made by hand. An error in a
package's file is printed as before; `--warnings` after the `--` (or `MYLANG_WARNINGS=all`) and `--diagnostics=json` still carry every warning; a project
that denies warnings prints the package's too when it fails on them. `mylang check .` in the package's own folder prints its warnings as before. One
internal option, `--package-namespaces NAMES`, which `mylang packages build` gives the command it runs and the compiler reads before the command does.
`docs/tooling/packages.md`, `docs/tooling/fix.md`, `docs/tooling/native-build.md`, `experiments/audit-work-20261111/FR53.md`.

### `mylang fix` no longer passes on the closing line of the check it runs (lane FR52, 17 November 2026)

Not breaking: only a line of standard error goes, no edit changes, `check`, `build`, `run` and `test` print their closing line as before. A
`mylang fix main.my` run that left warnings printed the final check's own `` `mylang fix /abs/path/main.my --warnings` repairs 2 of these 2 ``
between the diagnostics and `fix`'s own lines, which end with `fix: left 2 warnings with a repair alone; `mylang fix main.my --warnings`
repairs them too`: the same advice twice, once with the absolute path `fix` gave the check. A folder run that left a repair alone (a file marked
`# generated by`) printed it too. `fix` now drops that one line from what it passes on (`warning_display.isFixLine`, beside `fixLine`, whose
text is unchanged); the diagnostics and `fix`'s own lines remain. `--diagnostics=json` never held the line. `docs/tooling/fix.md`,
`experiments/audit-work-20261111/FR52.md`.

### `mylang test DIR` reads a nested test file as `mylang check DIR` does, and one unreadable file no longer hides the rest (lane FR51, 17 November 2026)

Not breaking: no program that ran before runs differently, and no recorded result or test name changes. A directory with no `mylang.json` and a
test file in a folder below it (`rows.my`, `rows_test.my`, `rows/more.my` and `rows/more_test.my` importing `rows`) was accepted by `mylang check .` and
refused by `mylang test .` with `error: directory test discovery failed: SourceError` and an `E_MODULE_READ` under `.../rows`, with no test run at all.
A file that cannot be loaded with its own folder as the import root and can with the directory now takes the directory, as `check DIR` takes it for
every file beneath it, and runs as `rows.more_test::test_doubled`, the name a `mylang.json` gives; a file that loads with its own folder keeps it.
A file that cannot be loaded either way (a missing module, a syntax error) no longer ends the run with `directory test discovery failed`: its diagnostic
is printed and it is listed as `failed PATH: failed to check or build, so no tests ran`, as a file with a type error already was, and the other entries
run (status 1). A directory with a `mylang.json`, a folder of flat files, and `mylang test FILE` take the roots they took. New flag `--import-root DIR` of
`mylang test FILE`, which a directory run gives its child processes. `docs/tooling/guest-tests.md`, `docs/tooling/packages.md`,
`experiments/audit-work-20261111/FR51.md`.

### `filesystem.link` (a hard link) and `filesystem.mkdir_mode` (a folder made with its mode) (lane LINKS2, 17 November 2026)

Not breaking: additions only. `filesystem.link(fs, target, path) -> Unit fails str` (and the builtin `fs.link_path(target, path)`) creates the
hard link `path` to the existing regular file `target`, as `link(2)` and `ln TARGET LINK` do, beside `filesystem.symlink` and shaped like it: the two
names share the bytes, the permission bits, the times and the inode, so `Stat.links` reads 2 for both (it had no way to read more than 1 for a file
before) and a write through either is read through the other. Each path is resolved as `symlink` resolves its own ("How a path is read"), and both must
fall where the call may write: under `--restrict` inside write grants (a file that can only be read is never linked into a place that can be written, which
would let a program write it), on an `fs.dir` or `filesystem.dir_at` handle inside its folder, `fs.read_only()` refuses, and no link is followed on the
way or at the end of `target`. `target` must be a regular file: a folder fails with `is a directory` and a symbolic link with `is a symbolic link the
sandbox does not follow, or links nest too deeply`, so the call cannot name a folder twice or reach through a link. A failure reads `link 'TARGET' to
'PATH': REASON`. `filesystem.mkdir_mode(fs, path, mode) -> Unit fails str` (and `fs.mkdir_mode(path, mode)`) creates a folder with the permission bits
`mode` as `mkdir(2)` takes them, so it never exists with the default mode, which `fs.mkdir` then `chmod` leaves it with (`0o775`, open to the group) until
the `chmod` runs (SP1-F-11, a tar extractor recreating a folder recorded `0o700`); the umask narrows `mode` as it does a file's, the system keeps the nine
permission bits and the sticky bit, and `chmod` sets the rest. `filesystem.memory()` answers both: a hard link is a second entry that shares the file's
bytes, mode, times, inode and lock (the in-memory entry is now a name and a body), and `mkdir_mode` stores the mode as given. The permission matrix of
`test/fs_permissions_cli_test.zig` runs both calls against a real directory and `memory()` and requires the same refusals (96 new lines). `link_path` and
`mkdir_mode` become reserved builtin spellings, which a function or a local of the same name shadows, as `read_link_path` does.
`docs/io.md#real-paths-permissions-and-times`, `experiments/audit-work-20261111/LINKS2.md`.

### A `!` conversion in a format string hole says what a hole holds and writes `repr(text)` (lane MSG-D, 17 November 2026)

Not breaking: no program is accepted or refused differently (the code stays `E_TOKEN`, at the `!`), and no `fix` is offered. `f"{text!r}"`, the
conversion of Python's format strings, was `E_TOKEN: unexpected character in source` at the `!` with nothing about what a hole takes (W2A-F-7). The
message now continues: "a format string hole holds an expression, then an optional format after `:`, as in `{count:>8}`; it has no `!` conversion, so call
the function in the hole: `{repr(text)}` for `!r`, `{str(text)}` for `!s`", with the hole's own expression in place of `text` when it is one short line (an
expression of more than 40 bytes is written as `value`). A `!` that opens a hole (`{!x}`) is still the retired `not` spelling, and a `!` in the code of the
program, outside a hole, keeps its text. `docs/text.md#format-strings`, `src/parser.zig`, `src/format_strings.zig`.

### A Unicode escape with braces is refused with the accepted spelling, and `mylang fix` writes it (lane MSG-D, 17 November 2026)

Not breaking: no program is accepted or refused differently; the `fix` is new. `"\u{fffd}"`, the spelling of Rust and JavaScript, was refused as
"invalid Unicode escape" (or, for `"\u{e}"`, "too few hexadecimal digits"), without the spelling that is accepted (W1-F-4: one attempt, guessed from the text
guide's `"café"` example). The lexer takes `\u` and exactly four hexadecimal digits, or `\U` and exactly eight for a character above U+FFFF, and never
took braces, so every escape that opens with a brace stays refused. All three messages of an escape now end with that spelling ("write `\u` and exactly
four hexadecimal digits, as in `\u00e9`, or `\U` and exactly eight, as in `\U0001f600`, for a character above U+FFFF"), and a brace has its own, "a Unicode
escape has no braces". When the braces hold one to four hexadecimal digits of a scalar value after a `\u`, the diagnostic carries the edit that writes the
same digits as `\u` and four (`"\u{e9}"` becomes `"\u00e9"`), which `mylang fix` applies once per escape of a literal and round; `"\u{1f600}"`, `"\U{...}"`
and a surrogate in braces have no edit. `docs/text.md#writing-a-scalar-in-a-literal` (new), `docs/tooling/fix.md`, `src/byte_literal.zig`.

### `E_WITH_RESOURCE` says what the `with` block refuses and what to write instead (lane MSG-D, 17 November 2026)

Not breaking: no program is accepted or refused differently, and no `fix` is offered (the repair restructures the program). The refusal of an open file
said "cannot be stored, passed as own or returned" (the table row of `mylang explain` still said "passed", which sent a reader of it away from the lent
form, SP1-F-7), and the refusal of a file held inside another type said only "store file owners in named local scopes". Both now say that the file
belongs to its `with` block and what to write: call its methods there, or lend it to a helper declared `mut f: File` and called as
`put(mut f, data)`, as `docs/io.md` shows. The first says what is refused (returned, stored, given away with `own`); the second names the types (a list,
a record, a variant, a callback type). `src/core/single_owner.zig`, `src/diagnostic_codes.zig`.

### The `E_TASK_HANDLE` hint in a loop writes `parallel.map`'s arguments in the order of the call (lane MSG-D, 17 November 2026)

Not breaking: no program is accepted or refused differently, and no `fix` is offered. A task handle that is not the initialiser of a `const` binding, inside
a loop, was refused with "inside a loop, `parallel.map(fn, items, ARGS)` runs one task per item", which has the function before the values; the call is
`parallel.map(values, fn, ARGS)`, as `docs/concurrency.md` writes it, and a reader who copied the hint got a type error of its own. The hint now writes
`parallel.map(values, fn, ARGS)`. No other task diagnostic had the order wrong. `src/sema_tasks.zig`.

### `parallel.threads()` and `parallel.cpus()`: a program asks how many threads its tasks have and how many CPUs it may use (lane CPUS, 17 November 2026)

Not breaking: two new functions, so no program is accepted or refused differently and no `fix` is offered. A program that cuts its work into pieces had no
call for the size of the pool (SP3-F-3: it counted CPUs by reading `/sys/devices/system/cpu/online` through `Filesystem`, which is Linux-only and ignores
`--threads`), and the guide did not say when the size is fixed. `parallel.threads() -> int` is the pool's size, at least 1: `--threads N` or
`MYLANG_THREADS=N`, else one per CPU the process may use, at most 256. It is read once, when the pool starts or the program first asks, and a program cannot
change it; in a task it answers what the calling thread does, and under `mylang test` (whose step and frame budgets force one thread, `--threads`
or not) and under `--max-steps` it answers 1, which is what tasks get there. `parallel.cpus() -> int` is the process's affinity mask, at least 1, read at the
call, whatever `--threads` says, so a program can print `using N of M`. Neither takes a capability. Under a hard address-space limit the pool can start with
fewer threads than asked, and a call before the first task still answers the count asked for. A test that calls either is no longer answered from a receipt
(`live-effects: ... reads the thread count or the CPU count, which no key binds`), because `--threads` and the machine set the answer and no key binds
either; its neighbours stay cached. `docs/concurrency.md#the-pools-size`, `docs/standard-library.md#parallel`, `src/stdlib/parallel.my`,
`src/core/build_parallel.zig`, `src/core/runtime/core_tasks.c`.

### `mylang fix DIR` reads a folder below a directory with no `mylang.json` as `mylang check DIR` does (lane FR50, 17 November 2026)

Not breaking: no program is accepted or refused differently by `check`, and no repair changes. A directory with no `mylang.json` and a file in a
folder below it (`rows.my` and `rows/more.my` with `import rows`) was accepted by `mylang check .` and refused by `mylang fix .` with
`E_MODULE_READ: there is no rows.my under the import root .../rows`: `check DIR` takes the directory as the root of every file beneath it, where
`fix` checked each file alone and took the file's own folder. Such a file now counts as a module of the directory's project, so the round that
checks the directory once (FR23) takes it and `fix .` ends 0 with nothing of its own to say; an error with a repair in that file is repaired and
the directory then checks. A directory with a `mylang.json`, a directory of flat files, and a folder of independent programs that `check DIR`
refuses are checked as before (that last one counts one more directory check under `--report`). `mylang fix rows/more.my`, `mylang check rows/more.my`
and `mylang test .` still take the file's own folder as the root. `docs/tooling/fix.md`, `experiments/audit-work-20261111/FR50.md`.

### A failed file operation says why, and the trap of a failed method names the path and the reason (lane WRITEWHY, 17 November 2026)

Not breaking for programs that only test for `Err`; a program that compares an error text changes with it. `failed: the path does not
exist or could not be used` answered a full disk, a size limit, a quota, a read-only folder and a missing path alike (SP2-F-11), and a failed
`f.write` on an open file ended the program with `R_FILE: native execution failed` and no reason (SP3-F-9). One table from the system's error to
a plain sentence now serves the durable calls, the whole-file calls, the methods of an open file and `filesystem.memory()`: `no space left on the
device`, `disk quota exceeded`, `the file is too large for the size limit or for the filesystem`, `the filesystem is read-only`, `permission
denied`, `too many files are open`, `the path, or a name in it, is too long`, `input/output error`, `is a directory`, `the path does not exist`
(`a folder on the way does not exist` for a call that creates below a missing folder); an error outside the table gives its number and the system's
words. The trap reads `error[R_FILE]: write '/dev/full': no space left on the device`. Three messages change beyond the new reasons: a write of a
new file in a folder without the write bit said "does not exist" (now `permission denied`, as the system said), the generic sentence is gone, and
`the path is too long` reads `the path, or a name in it, is too long`. Which operations fail and succeed is unchanged. docs/io.md;
`experiments/audit-work-20261111/WRITEWHY.md`.

### `try` is accepted as the value of an assignment to a field or an element (lane TRYFIELD, 17 November 2026)

Not breaking: programs refused before are accepted; nothing accepted is refused. `x = try f()` was accepted for a local, but `r.a = try f()`,
`xs[i] = try f()`, `rows[i].inner.name = try f()`, `d[key] = try f()` and their compound forms (`r.n += try f()`) were `E_TRY_POSITION`,
although the guide lists an assignment's value among the places `try` stands (F-PB-2: every generated decoder). They mean the two-statement
form: for `=` the call runs before the place's index and key expressions, for a compound form after them, as in an ordinary assignment; a
failing `try` leaves before the write. In the reach of an `on fail:` clause such a `try` is `E_ON_FAIL`, as `x = try f()` is.
`mylang fix` has nothing to repair there any more. `docs/results-and-options.md#try-as-the-value-of-an-assignment-to-a-place`,
`experiments/audit-work-20261111/TRYFIELD.md`.

### `mylang fix` no longer drops the labels of a nested pattern and loops on the refusal (lane FR49, 17 November 2026)

Not breaking: no program is accepted or refused differently; a hint goes. `W_PATTERN_SHORTHAND` (`field=field` is written `field`) also fired on the
fields of a pattern nested in an arm's payload, `case Some(item(value=value, note=note))`, where the checker refuses the bare form
(`E_NAMED_PATTERN`, "payload fields must be supplied by name"), takes the bare form at the top of an arm only, and whose repair writes the label
back. `mylang fix DIR` then drops the labels and puts them back for 200 rounds (399 edits) and ended "fixes did not settle", leaving the refused
program. The hint is now raised, and its repair offered, for the fields of the case the arm names only; a nested field keeps its label. The hint
and its repair at the top of an arm are unchanged. `docs/records-and-unions.md`, `docs/tooling/fix.md`, `docs/tooling/lint.md`,
`experiments/audit-work-20261111/FR49.md`.

### `E_SINGLE_OWNER_OVERLAP` in a loop over a list inside the value being changed shows the loop over positions (lane MSG-C, 17 November 2026)

Not breaking: no program is accepted or refused differently, and no `fix` is offered (it restructures a loop). `for name in st.names:` with `touch(mut st, name)`
inside was refused with the one text every overlap with a loan had, "copy it with copy(value) or finish the borrow first", which in the hottest loop
points at copying the whole list on every visit (W3-F-7, W4-F-6: hit three times, five minutes each). When the loan that blocks the change is the loop's own
iteration over a list of the value being changed, `for NAME in PLACE:` with a place of fields and list elements, the message now says so, names the loop,
and writes the repair for it: `mut k = 0`, `while k < len(PLACE):`, `const NAME = copy(PLACE[k])` as its first line (`const NAME = PLACE[k]` for a scalar
element: the copy is of one element, not the list) and `k += 1` as its last, or iterating `copy(PLACE)` at the price of one copy. Both repairs were checked
to be accepted. A `own` move of the value, a loop whose header is not that form (`enumerate`, a call, a slice) and every other loan keep their text.
`docs/ownership-rules.md#r7--iteration`, `src/core/single_owner.zig`.

### The trap of an `@invariant` that a field write broke says the fields can be written together (lane MSG-C, 17 November 2026)

Not breaking: no program is accepted or refused differently, and no `fix` is offered. An invariant over two fields (`self.count + len(self.free) <=
len(self.keys)`) traps at the first of two writes that restore it, and the trap said only `R_INVARIANT: invariant violated: Slots invariant ...: every
key and every free slot has a slot`, so the way out (SP2-F-8: `replace`, found in the guide afterwards, four attempts) was not in it. A trap at a field
write, a write in place (`append(mut t.free, x)`, `take`, `exchange`, a `mut` argument) or a write through a `match mut` binding, of an invariant whose
condition reads two fields of `self` or more, now ends with `; each write is checked on its own: to change the fields this invariant relates (count,
free, keys) together, write them in one replace(record, field=value, ...)`. A construction, a `replace` and an invariant over one field keep their
text. The hint carries no backtick, because a reader of the trap takes the last one as the end of the clause; it is part of the contract `message` that
a `diagnostic-v1` record carries. `docs/contracts.md`, `src/sema_contracts.zig`.

### `E_LINEAR_UNCONSUMED` on a `try` names the `on fail:` clause and its shape (lane MSG-C, 17 November 2026)

Not breaking: no program is accepted or refused differently, and no `fix` is offered. A `@linear` owner still live at a `try` whose failure leaves the
function (`mut tx = begin()` then `try add(mut tx, 1)`) was refused with the advice for the end of a scope ("give it to an `own` parameter, return it"),
which does not fit: the repair the language offers is `on fail: close(own tx)` right after the owner is declared (SP2-F-3: found by grepping the guides
after ten minutes of wrapping each `try` in a `match`). The message now says that the owner is lost if this `try` fails, writes that clause for the
owner in question, says what `close` stands for and that the clause runs on every failure exit after it and never on the success path, and keeps the old
ways of ending the owner before the `try`. A `try` on an option keeps the old text (`on fail:` runs for a failure, not for `None`), as does every other
path that leaves the owner unconsumed (`return`, `fail`, `break`, a block's end, a `match mut` that lent it). `src/linear_rules.zig`.

### A literal takes the type of the operand beside it when that operand is a call or a nested expression too (lane LITERAL, 17 November 2026)

Not breaking: every program accepted before checks with the same types; some refused before are accepted. The rule that an unsuffixed
literal beside a typed operand takes its type held only when the operand was a name, a field or an element: the literal was typed before
either operand was checked, from what the syntax shows. Now a literal the context leaves untyped waits for its neighbour, so `num(x) != 0`
(`num -> i32`), `shift_right(bit_xor(x, shift_right(x, 29)), 24)` (`x: u64`), `u32(x + 2147483647 + 1)` (`x: i32`), `0 <= num(x) < 10`,
`f32(x) * 2` and `max(num(x), 0)` check (selka-protobuf F-PB-1 and F-PB-3, selka-samples SP3-F-7); `min` and `max` follow the rule for a
name as well. A literal its neighbour's type cannot hold is `E_INTEGER_RANGE` at the literal, naming the neighbour ("the literal `200` does
not fit i8, the type it takes beside the i8 value of `n(3i8)`"); a float literal beside an integer in `shift_right`, `bit_and` and their kind,
or in `min` and `max`, is refused at the literal. `docs/integer-operations.md`, `docs/floating-point.md`,
`experiments/audit-work-20261111/LITERAL.md`.

### `sort.sort_by_compare` and `sort.sort_by_compare_with`: a stable in-place sort by a comparison function the caller names (lane SORTCMP, 17 November 2026)

Not breaking: two new functions in the `sort` module; no program is accepted or refused differently, and the refusals of `sort` and `sorted` keep their codes
(`E_CALL_ARGUMENT` for `cmp=`, `E_SORT_KEY` for a key with no order or a key of two parameters) with a message that now names them. `sort(mut xs, key=f)` orders by
one `int`, `float`, `str` or flat record, so two programs written by agents new to the language (a `jq` clone ordering values across types, a `SELECT` over CSV with
several keys of mixed type and a direction each) wrote merge sorts of their own over a list of indexes. `sort.sort_by_compare(mut values, compare)` takes a top-level
`compare(first, second) -> int` (negative, zero or positive, as `compare_strs` and `time.compare` answer), and `sort.sort_by_compare_with(mut values, compare, context)` calls
`compare(first, second, context)` with one read-only context value of any `copy + storable` type (a record of the directions, a lookup table), because the language has
no closures. It is written in the language: a merge sort of the positions, then the elements move into place with `exchange`, so they are lent to the comparison and
moved, never copied. On a million records (two texts and an int) sorted by two fields, `--release`, six runs each at load averages of 14 to 45: median 1.60 s against
1.58 s for the hand-written index merge sort (CPU 1.50 s against 1.40 s, of which 0.1 s builds the records), 171 MB peak against 168 MB (150 MB is the input), and
2,000,012 allocations against 2,000,106, no record or text copied. A comparison that is not an order ends and leaves every element once. `docs/standard-library.md`,
`docs/python-syntax.md`, `SPEC.md` (SORT-COMPARE-1), `experiments/audit-work-20261111/SORTCMP.md`.

### An unread `match` payload binding says what to write and carries the repair (lane FR45, 17 November 2026)

Not breaking: no program is accepted or refused differently, and no other diagnostic changes. `W_UNUSED_BINDING` on a name that a `match`
pattern binds (a `case`, an `is`, a `while ... is`, a bind-or-else's `else Err(e):`, nested patterns too) used to say "use it or remove it,
preserving initializer effects with `_ =`", advice that does not fit a pattern, and carried no repair; a first-time agent's `mylang fix` left
30 to 40 of them (W1-F-12). It now reads ``binding `lit` is never read; write `lit=_` in its place to ignore this field`` and carries that edit:
`_` for a single payload (`Some(x)`, `Err(e)`, a `result`'s `ok(v)`) or a labelled field, `name=_` for a bare field of an enum case, which
`W_PATTERN_SHORTHAND` leaves alone. `mylang fix DIR` and `mylang fix FILE --warnings` apply it. A name the arm writes (`match mut`), a type that
must be handled, an arm of an alternatives list `case a(x) | b(x):` and a case name that an enum and a `result` both declare keep the old
message and no repair, as does every binding that no pattern introduces (`const x = f()`, a parameter, a loop variable, a bind-or-else's
`const x`). `docs/match-expressions.md`, `docs/tooling/fix.md#mylang-fix`, `experiments/audit-work-20261111/FR45.md`.

### A `File` parameter used only through its methods is no longer warned as never read (lane FR48, 17 November 2026)

Not breaking: no program is accepted or refused differently; one warning goes. `func put(f: File, data: bytes) -> int: return f.write(data)` printed
`warning[W_UNUSED_BINDING]: binding is never read` on `f` (SP1-F-7), because a call of a handle's method did not count as a read of the handle, while
`mut f: File` escaped the warning for another reason. Every method (`read`, `readline`, `readlines`, `write`, `flush`, `close`, `sync`), on a binary and
a text handle, now counts. A `File` or `TextFile` parameter the body never touches is still warned. `experiments/audit-work-20261111/FR48.md`.

### A failed file operation says why, and the trap of a failed method names the path and the reason (lane WRITEWHY, 17 November 2026)

Not breaking for programs that only test for `Err`; a program that compares an error text changes with it. `failed: the path does not
exist or could not be used` answered a full disk, a size limit, a quota, a read-only folder and a missing path alike (SP2-F-11), and a failed
`f.write` on an open file ended the program with `R_FILE: native execution failed` and no reason (SP3-F-9). One table from the system's error to
a plain sentence now serves the durable calls, the whole-file calls, the methods of an open file and `filesystem.memory()`: `no space left on the
device`, `disk quota exceeded`, `the file is too large for the size limit or for the filesystem`, `the filesystem is read-only`, `permission
denied`, `too many files are open`, `the path, or a name in it, is too long`, `input/output error`, `is a directory`, `the path does not exist`
(`a folder on the way does not exist` for a call that creates below a missing folder); an error outside the table gives its number and the system's
words. The trap reads `error[R_FILE]: write '/dev/full': no space left on the device`. Three messages change beyond the new reasons: a write of a
new file in a folder without the write bit said "does not exist" (now `permission denied`, as the system said), the generic sentence is gone, and
`the path is too long` reads `the path, or a name in it, is too long`. Which operations fail and succeed is unchanged. docs/io.md;
`experiments/audit-work-20261111/WRITEWHY.md`.

### `filesystem.dir_at` narrows a Filesystem to a folder named at run time (lane NARROW, 17 November 2026)

Not breaking for programs: `fs.dir("literal")` is unchanged, and `fs.dir(value)` is still `E_FILESYSTEM_DIR`, whose message now names
`filesystem.dir_at(fs, path) -> Filesystem fails str`. That call reads the path as `fs` reads one (absolute or against the working
directory; under `--restrict` inside a grant; on a narrowed handle by its own rule), requires an existing directory reached without a
symbolic link, and returns the handle `fs.dir` gives, so a program confines itself to a folder from its command line (SP1-F-1,
SP2-F-7) instead of checking names itself. One runtime fix rides along: a handle narrowed to the working directory itself
(`fs.dir("")`, now also `dir_at(fs, ".")`) is narrowed for the durable `filesystem` calls too (`stat`, `list_entries`, `chmod`...),
which took `..` and followed links on it before. docs/io.md, "A folder named at run time";
`experiments/audit-work-20261111/NARROW.md`.

### The refusal of a binding in a nested pattern names the pattern the author wrote, and no longer offers a fix that is not a program (lane PATTERNMSG, 17 November 2026)

Not breaking: no program is accepted or refused differently. `match next_item(i): case Ok(Some(v)): append(mut all, v)` was `E_OWN_MARKER`
naming "the local `\x00pattern269.0`" (a name the compiler makes for a layer) and telling the author to write `own` "in the initializer of `v`",
which does not exist; where the refusal carried a copy, `mylang fix` wrote `case Ok(Some(copy(v))):`, which does not parse. Now the message says
"`v` is lent by the value that `case Ok(Some(v))` matched" and "to give it, match one layer at a time (`case Ok(inner):`, then `match own inner:` with
`case Some(v):`, and write `own v`), or write `copy(v)` to keep both", for two or three layers, a case with named fields, and a matched local
(`match own r:` first). The refusal carries no fix, so `mylang fix` answers "nothing to fix" for it. No diagnostic of the ownership check prints
a name the compiler made for a pattern. `experiments/audit-work-20261111/PATTERNMSG.md`.

### `x in range(a, b)` names the comparison, and `mylang fix` writes it for plain operands (lane MSG-A, 17 November 2026)

Not breaking: the refusal keeps its code (`E_UNKNOWN_SYMBOL` in a project, `E_UNKNOWN_FUNCTION` in one file) and its place at `range`; no program is
accepted or refused differently. `if x in range(0, hi):` was "this module declares no `range`" (a module the author never wrote), which does not say that
`range` is only a loop source (SP3-F-11). The message now says so and writes the comparison with the bounds as written, `0 <= x < hi` (`x < 0 or hi <= x`
for `not in`; `range(hi)` reads as `0 <= x < hi`). When the needle and every bound is a name or a number and there is no step, `mylang fix` replaces the
whole test with that comparison; a call, an operator or a step gets the message and no edit. A module that declares its own `range` is not touched.
`docs/python-syntax.md`, `docs/tooling/fix.md`, `experiments/audit-work-20261111/MSG-A.md`.

### `x = f() else Err(m):` on an assignment says the `else` unwraps into a new name (lane MSG-A, 17 November 2026)

Not breaking: no program is accepted or refused differently, and the refusal stays where it was, at the `else`. An assignment to a name that
already exists, `x = read(path) else Err(m):` (or `x += ...`) followed by a block, was `E_SYNTAX: unexpected token; expected a newline`, and an
agent had to find on its own that the unwrapping `else` belongs to a declaration (SP1-F-5). It now says that the `else` unwraps the value into a
new name, so it belongs to a declaration and not to an assignment to the existing `x`, and writes the two forms that do the job:
`const value = read(path) else Err(m):` and then `x = value`, or `match read(path):` with an arm for each case. No `mylang fix` edit: either form
needs the author's choice of a name or of the arms. An assignment through a field or an index keeps the old text.
`docs/statements.md`, `experiments/audit-work-20261111/MSG-A.md`.

### A module constant written without its type says it needs one, and `mylang fix` inserts a plain literal's type (lane MSG-A, 17 November 2026)

Not breaking: no program is accepted or refused differently; the refusal's text, and whether it carries a repair, change. A top-level
`const X = 1` (also `public const`) was `E_SYNTAX: unexpected token; expected :` at the `=`, which three projects read as a typo (SP1-F-3, W3-F-4). It
is now `a module constant needs its type: write `const X: int = 1``, at the same place. When the value is one literal of a plain type (an integer
without a width suffix, a decimal float, a text, `True` or `False`, a minus sign allowed on a number) `mylang fix` inserts `: int`, `: float`,
`: str` or `: bool` after the name; any other value says `write `const X: TYPE = ...`` and has no edit. `docs/python-syntax.md`,
`docs/tooling/fix.md`, `experiments/audit-work-20261111/MSG-A.md`.

### Every guide the compiler names can be read with `mylang docs` (lane DOCS2, 17 November 2026)

Not breaking: no program is accepted or refused differently, so there is no migration; the text of `mylang docs` and `mylang reference` changes.
`mylang docs packages` and `mylang docs integer-operations` print the local-packages and integer-operations guides, and 25 more pages that the
guides link to (`floating-point`, `match-expressions`, `value-semantics`, `lint`, `c-ffi`, ...) are topics under a second heading of the list;
`mylang docs tooling/packages.md#section` takes a page as a guide links to it. A test fails when a guide that `mylang docs` prints links to a
file it cannot print (116 of 277 links did; 8 remain, in `io.md` and `managed-memory.md`). `mylang reference` names a feature's guide as
`guide: mylang docs TOPIC (section #anchor)` instead of a `docs/` path, names `mylang docs logging` for the logging module, and answers the
`bit_*`, `shift_*`, `wrapping_*` and `saturating_*` calls. The packages guide now says how a package is laid out, how modules import each other,
that the lock is absolute and written again after an edit, where a program's own arguments go, how to run only one's own tests, and what a
symbolic link or `"interface_files": true` does. `experiments/audit-work-20261111/DOCS2.md`.

### A project file named like a standard module is named when it is passed over (lane MSG-B, 17 November 2026)

Not breaking: which file wins is as it was (the standard module), so there is no migration; only what is said changes. A project's own
`options.my` beside the entry never loaded, because `options` is a standard module, and `options.Options(...)` was refused with "module
`options` declares no `Options`", which does not say why. That refusal now adds "`options` here is the standard module, so your `options.my`
is not used: rename it" (the file must lie beside the entry, as `--local-stdlib` looks). The warning `mylang: local standard module
'options.my' is ignored; pass --local-stdlib to prefer it`, which only `build` and `run` printed, is now also printed by `check`,
`check-project`, `test` (a single entry or a directory) and so by `mylang packages build` with any of its commands; `--diagnostics=json` and
`test --json` stay free of it, and a file named as the `check` entry is the file, so it hides nothing. `experiments/audit-work-20261111/MSG-B.md`.

### After `import sort`, a call of the builtin `sort` is told the import owns the name (lane MSG-B, 17 November 2026)

Not breaking: what is accepted and refused is as it was, so there is no migration; one refusal changes its text and may gain a repair. After
`import sort` the name `sort` is the module's, so `sort(mut rows, key=by_name)` is read as a call of the module and was refused with "this module
declares no `sort`", which does not mention the import. It now says that `sort` here names the imported module, which hides the builtin, and what to
write: a function of the module, with at most two named as examples (those named `sort_...` that take their first parameter `mut`, the shape
of the call, the shorter name first; `mylang reference --query sort` lists the rest) or no import. When the call is the
builtin's form (`sort(mut values ...)`) and the file names the module nowhere else (no `sort.` qualifier), `mylang fix` deletes the import line.
`sort` is the only standard module that shares a name with a prelude function it hides (`bytes` also does, and `bytes(buf)` still works after
`import bytes`). `experiments/audit-work-20261111/MSG-B.md`.

### `strings.contains` and `lists.contains` of text or bytes say to write `in`, and `mylang fix` writes it (lane MSG-B, 17 November 2026)

Not breaking: what is accepted and what is refused is as it was, so there is no migration; two refusals change their text and gain a repair.
`strings.contains(text, part)` (and `bytes.contains`, `sets.contains`, `dicts.contains`) was answered "the standard module `lists` declares a
function `contains`", which points at a function for lists, and `lists.contains(data, 10)` on bytes, text, a set or a dictionary was answered
"argument shape does not match the generic parameter type" (`E_GENERIC_INFERENCE`, the same code at the same place). Both now say that
whether text holds a part, bytes hold a byte, a set holds a value or a dictionary has a key is the operator `in`, with the call as written
swapped (`"ell" in text`). When both operands are a name, a field of one or a literal, the diagnostic carries the repair and `mylang
fix` rewrites the call (`not strings.contains(a, b)` as `b not in a`, parentheses where an operator beside it would capture it); any other
operand keeps the sentence with its placeholders (`part in text`) and no edit. `experiments/audit-work-20261111/MSG-B.md`.

### Under `--restrict` a path means what it means in a plain run (lane PATHS, 17 November 2026)

Breaking for restricted runs, and no source edit is offered: `mylang fix` cannot help, because the meaning is in how the program is
started. Under `--restrict` a path was relative to each granted directory in turn (`--allow-write=out` and `report.txt` named
`out/report.txt`), and `out/report.txt`, `./out/report.txt` and the absolute path were refused. Now a path is read as an ordinary
process reads it, against the working directory or absolutely, and must then fall inside a grant (docs/io.md, "How a path is
read"), so the command line that works in a plain run works restricted. **To move across:** name files as the plain run names them,
and either start the program in the granted folder (`cd out && mylang run prog.my --restrict --allow-write=.`) or pass it the folder
(`--allow-write=out` and `out/report.txt`). A program that still uses the old names is refused at run time with the path as it was
resolved: `write 'report.txt': denied: '/home/me/report.txt' is outside the granted directories`. The one refusal sentence (`denied:
outside the granted directories, or the mode needs a write grant`) is now three: outside every grant (as above), a write inside a
read grant (`denied: writing needs a write grant (--allow-write); 'PATH' is granted for reading only`), and a narrowed handle (`denied:
this Filesystem was narrowed by fs.read_only() and does not write`, or `fs.dir`'s own sentence); a plain run never mentions grants.
Also: without `--restrict` the durable `filesystem` calls (`stat`, `read_at`, `list_entries`, `chmod`, `symlink`, `rename_path`...)
accept `..`, `.`, `a//b` and a trailing slash as `read_text` does; `canonical_path` and `filesystem.cwd` answer the absolute path under
a grant too; `filesystem.memory()` reads `./a`, `a/../b` and `dir/` as the system would and refuses `..` past its root or an absolute
path as outside. Narrowed handles (`fs.dir`, `fs.read_only()`) keep their rule. `experiments/audit-work-20261111/PATHS.md`.

### `mylang fix` deletes a trailing `return` that can never run (lane FIXUNREACH, 17 November 2026)

Not breaking: no program is accepted or refused differently, so there is no migration; `E_UNREACHABLE` gains a repair and a clearer message. A `return`
or `fail` that is the last statement of its block and follows a statement that always leaves (a `match` whose arms all return, an `if`/`else` chain whose
branches all leave, a `return`, `break` or `continue`) now carries a fix that deletes its whole line, and `mylang fix FILE` applies it, because it is an
error's repair. Any other statement after one that leaves (two statements, a call, an assignment) keeps the refusal with no repair. The message now names
the statement that leaves when it is a `match` or an `if`: "every arm of the `match` at line 6 returns, so this statement cannot run"; a plain `return`
followed by a statement keeps its wording. An agent wrote the fallback `return 0` after an exhaustive `match` about 20 times in an hour (W1-F-11).
`docs/tooling/fix.md`, `experiments/audit-work-20261111/FIXUNREACH.md`.

### A record of borrows held by a `mut` local and written through a `mut` argument is refused, no longer a crash (lane FR46, 17 November 2026)

Not breaking: the programs this changes crashed the compiler (a segmentation fault, or an abort after minutes of recursion in the
ownership check), so no program accepted before is refused and no refusal changes. `mut p = Parser(toks=toks, i=0)` with `toks` a
`const` list, then `advance(mut p)` (a function that writes `p.i`), is now `E_OWN_MARKER` at the field that needs `own toks` or
`copy(toks)`, and the note says which later line makes `p` own its fields; `mylang fix` writes `own toks`, which checks.
`experiments/audit-work-20261111/FR46.md`.

### The compiler's work directory keeps itself out of git (lane CACHEIGNORE, 17 November 2026)

Not breaking: no program is refused or means anything else, so there is no migration. A `mylang build`, `check`, `test` or `packages build`
that keeps a work directory now writes a `.gitignore` containing `*` and a `CACHEDIR.TAG` (signature `8a477f597d28d172789f06886806bc55`)
into `.mylang-cache`, or into the `--cache-dir` folder when this command made it, each only when no file of that name is there; an
existing `.gitignore` is left alone and a `--cache-dir` folder that already existed gets neither. Three agents had committed 14,900 cache
files with `git add -A`. `docs/tooling/native-build.md#the-caches`, `experiments/audit-work-20261111/CACHEIGNORE.md`.

### `mylang fix FILE` repairs errors only; a directory, or `--warnings`, repairs warnings too (lane FR44, 17 November 2026)

A tooling default changes, by the user's decision of 17 November; no program is accepted or refused differently and no diagnostic changes its code, text,
severity or fix. Two agents who ran `mylang fix FILE` to clear an ownership error got 9 and 33 edits, most of them warnings rewritten into the code they were
editing (`match` into `is Some(x)`, `copy(a)` into `take(mut a)`), and their next scripted edit no longer matched (SP2-F-10, SP3-F-12). Now `mylang fix FILE.my`
applies the fixes of errors only, in every file the run may edit; `mylang fix FILE.my --warnings` applies what a file run applied before, edit for edit; `mylang fix DIR`
is unchanged, byte for byte, and takes `--warnings` without changing anything. `--check` lists what the run would apply. A file run that leaves warnings with a repair
ends with `fix: left 2 warnings with a repair alone; `mylang fix main.my --warnings` repairs them too` (on standard output, before the `--report` line, whatever
`--diagnostics` says). The closing line of a check names the command for each kind of repair: `` `mylang fix FILE` repairs N of these M `` when every repair is an
error's, `` `mylang fix FILE --warnings` repairs N of these M `` when every one is a warning's, and both counts on the one line when there are both; a directory's
line is as it was. A script that ran `mylang fix FILE` to apply a warning's repair adds `--warnings`. `docs/tooling/fix.md#mylang-fix`,
`experiments/audit-work-20261111/FR44.md`.

### A docstring example that returns is graded on its output so far (lane DOCEX, 17 November 2026)

Not breaking: an example whose statements ran a `return` always failed before (`expected "oops\n", got "oops\n"`, two equal texts
and a failure), and one whose `return` was not reached is unchanged, so there is no migration. A `return` now ends the example's case
there: the output written up to it is compared with the expected output of the prompt it returned in, a later prompt never ran and
fails as not reached (naming the prompt that returned), and `return False` fails the case, so `const value = f() else Err(_):` with
`return False` in its block unwraps a result, and `print(out, message)` then `return True` shows what a failing call reports. `fail`,
`try`, and `break` or `continue` outside the example's own loop stay refused by the ordinary check. See `docs/functions.md`,
"Runnable examples".

### `try` is accepted as a call's argument (lane TRYARG, 17 November 2026)

Not breaking: no program accepted before is refused or means anything else, so there is no migration. `f(a, try g(x))`,
`Row(size=try parse(t))`, `len(try load())` and `f.write(try encode(x))` were `E_TRY_POSITION`; they now check, in any statement
(a `while` or `elif` condition included), at any depth. The arguments run left to right: a failing `try` leaves the function
before the later arguments and the call, and what the earlier arguments made is destroyed once. A `@linear` owner given away
before the `try` is `E_LINEAR_UNCONSUMED` at the `try`, and a `try` in an argument in the reach of an armed `on fail:` clause is
`E_ON_FAIL`. A `try` under an operator, in an index or in a list literal keeps `E_TRY_POSITION` and its repair; `mylang fix`
no longer hoists a `try` that is an argument, and a legacy `g(x)?` in an argument becomes `try g(x)` in place.
`docs/results-and-options.md#try-in-a-calls-arguments`, `experiments/audit-work-20261111/TRYARG.md`.

### `W_COPY_RETURNED` also repairs a `public` function of a project that is no package (lane COPY-FROM-PUBLIC, 17 November 2026)

Not breaking for the project that is repaired: every caller of the function is in it, and the check refuses nothing new. A `public`
function every return of which copies a place of one parameter, and whose callers in the project only read the result, is declared
`from` that parameter by `mylang fix DIR`, like a private one, under the rule `W_COPY_FOR_STORE` has (decision COPY-FROM-PUBLIC: a
library that others import keeps its public signatures): the project's `mylang.json` sets no `interface_files` and its modules do not
all lie in one namespace. The warning says "its signature changes". A caller that keeps the result, a function named as a value and a
recursive one withhold it as for a private function; a package, a project with `interface_files` and a check of one file print what
they printed. `experiments/audit-work-20261111/COPY-FROM-PUBLIC.md`.

### A `logging` module in the standard library (lane LOG, 17 November 2026)

A new module, written in Selka, with no builtin, runtime function or compiler change. Like every standard name it takes the name: a
project's own file `logging.my` is now ignored with a warning unless `--local-stdlib` is passed (none of the repository's programs and
none of the four projects has one). `logging.new(err)` makes a `Logger` from a stream the program
holds; `with_level`, `named`, `with_field`, `with_clock` and `as_json` each answer a changed copy; `debug`, `info`, `warn` and `error`
write an event whose fields (`text`, `number`, `real`, `flag`) are an optional last argument; `enabled` and `parse_level` answer
whether a level is shown and read one from text; `event` and `write` let a task, which holds no capability, build an event and the
caller write it. One event is one line in text or JSON whatever it holds: a value is quoted and control bytes are escaped, a key
and a name are written bare. It reads no environment and opens no file, prints a time only when given a `Clock`, flushes each line,
and a failed write behaves as `print` does. `mylang docs logging`, `docs/logging.md`, `docs/standard-library.md#logging`,
`experiments/audit-work-20261111/LOG.md`.

### A cached build follows an edit of the function a module constant calls (lane CONSTSTALE, 17 November 2026)

Not breaking: a stale value is no longer served, and no program is accepted or refused differently by a cold build. A constant
computed at check time (`const VALUE: int = build(4)`) is folded into each reader, but its digest held only its own text and its
callees' headers, so after an edit of `build`'s body (or of a function `build` calls, in any module) a reader whose text had not
changed kept the old value under `run`, `build`, `build --release` and `mylang test` (a test pinning the old value was served as
passed), and the shared stage store carried it to another work directory. The digest of such a constant now holds its value (a `bytes`
table's octets), and a module's interface record reads the text of every module whose bodies its constants evaluate; an edit that
leaves the value as it was rebuilds no reader. `--no-cache` built it before the fix. `experiments/audit-work-20261111/CONSTSTALE.md`.

### `mylang lint` says when the analysis behind the loop rules failed, and `--copies` no longer prints a 0 it does not know (lane FR43, 17 November 2026)

Not breaking: a run whose analysis succeeds prints, byte for byte, what it printed, text and JSON, and no finding changes. When the
Core build behind `L_ALLOC_IN_LOOP` and `L_COPY_IN_LOOP` failed (a broken `@noalloc` promise, a stale record: lane COPY-C1c), the lint
said nothing and `mylang lint --copies` printed `0 in a loop` and counted those copies as named by nothing, with status 0. Now one line
on standard error names the file, the first error code and the rules not judged. `--copies` prints `?` for "in a loop" and "named by
nothing" and says how many copies they share; its `--json` keeps `copy-count-v1` and, only then, has `"in_loop":null`,
`"unnamed":null`, `"split_known":false` and `"in_loop_or_unnamed":N`. Under `--gate`, a run whose `copy-in-loop` could not be judged
exits 3 (it passed silently before); without `--gate` the status is unchanged. A file with no `main` has nothing to analyse and prints as
before. `docs/tooling/lint.md`, `experiments/audit-work-20261111/FR43.md`.

### A module constant can be a table of numbers, held as `bytes` (lane CONSTTAB, 17 November 2026)

Not breaking: an addition. A `bytes` constant may be a call of a source function that builds its octets (`mut table = buffers.empty()`,
`_ = buffers.append_byte(mut table, value)`, `return bytes(table)`, with the loops, branches and integer operations a scalar constant
function already has). The compiler runs it while it checks the program, within a size limit of 262,144 octets and a work limit of 33,554,432
units (a scalar constant keeps 65,536), and the value is static data in the built program: reading it allocates nothing and does no work, and
a function that only reads it passes `@noalloc`. `flate.crc32` reads its table that way (`CRC_TABLE`) instead of rebuilding 256 entries in
every call: 4 octets take about 5 ns where they took 1.1 to 1.4 us (`--release`, 2,000,000 calls in 0.01 s against 2.1 to 2.8 s; a 1 MiB input
takes the same 3.5 billion cycles for 400 MiB with 36 percent fewer instructions). A module constant of a
list, record, option or union type was refused before and still is, but with `E_CONSTANT_TYPE` at the type (it was
`E_CONSTANT_EXPRESSION` at the initializer), and its message says a table of numbers is `bytes` and lists are not constants yet (that
needs static list data, which the back end does not have). No `mylang fix` migration. `L_DEAD_PRIVATE` no longer calls a private function dead when only a module constant's initializer calls it (scalar constants had the same fault). Also found, not fixed: a cached build can keep the
value of a constant that calls a function when only that function's body changed (scalar constants too);
`experiments/audit-work-20261111/CONSTTAB.md`.

### A lowered body is no longer reused after its callee's parameter becomes `own` (lane COPY-C1c, 17 November 2026)

Not breaking: a stale record is no longer served, and no program is accepted or refused differently by a cold build. The store that
keeps a function's lowered body left "which parameters are `own`" out of a callee's declared digest (`core/lowering_cache.zig`), so
after `func header(name: str, ...)` became `func header(own name: str, ...)` a caller whose text had not changed was served as it had
been lowered for the borrowing callee. A warm `build` or `run` then ended with exit 2 (`E_CORE_HIDDEN_COPY` at the caller's line, then
`internal error[E_CORE_INVALID_IR]: ... call does not match its signature`) when the caller passed a literal, even from a fresh work
directory, since the record is in the shared half of the stage store; and `mylang lint --copies`, `L_ALLOC_IN_LOOP` and `cost --sites`
read the failed analysis as no rows and counted fewer copies in a loop. The digest now includes the `own` parameters, so every declared
digest changes once. `--no-cache` built it before the fix. `experiments/audit-work-20261111/COPY-C1c.md`.

### `mylang fix` writes the read before the move where a call gives a value and reads it again, with no copy (lane FR41, 17 November 2026)

Not breaking: two messages and one repair change, and no program is accepted or refused differently. For
`Source(mem=plain, total=len(plain))` the refusal (`E_OWN_MARKER`) said to write `copy(plain)`, and `mylang fix` did, a second copy of a
buffer that may be gigabytes, where the length is read first and `plain` moved after it. When every argument after the moved one is a read that
gives a number or a `bool` (`len(x)` of a text, bytes, list, dictionary or set, a comparison or arithmetic over it, a scalar local) or is a
literal (a text or bytes one too, which reads nothing), is written `name=value`, and the function
checks with the call so written, the refusal names it: "write `mem=own plain` after `total=len(plain)` so that `plain` is read before it moves,
or write `copy(plain)` to keep both", and `mylang fix` writes `Source(total=len(plain), mem=own plain)` (a call argument as well as a
constructor field). `Source(mem=own plain, total=len(plain))` (`E_SINGLE_OWNER_MOVED`) names the same form and gets the same edit. The
arguments evaluate left to right as written, so the edit changes no result. A value read in a later statement, a read that keeps part of the
value, positional arguments and a comment between the arguments keep the copy. `experiments/audit-work-20261111/FR41.md`.

### A discarded field of a `@linear` record: the refusal no longer offers a repair that leaves it unconsumed (lane FR42, 17 November 2026)

Not breaking: two messages change and one repair goes, and no program is accepted or refused differently. `_ = own tx.undo` on a
`@linear` record was refused with "this position only reads it; remove `own`", `mylang fix` removed the marker, and the next check
said the record was not consumed and recommended "end it with `own tx.field`": a circle. A discard of a list, text or record field
only reads it (on any record), so it does not end the owner. The refusal now says that, names the forms that do (`const kept = own
tx.undo`, `return own tx.undo`, or giving `tx` to an `own` parameter) and carries no repair; `E_LINEAR_UNCONSUMED` and the discard's
`E_LINEAR_USE` say where `own tx.field` ends the owner. A value that is not `@linear` keeps its message and its repair.
`docs/records-and-unions.md`, `experiments/audit-work-20261111/FR42.md`.

### `f.sync()`: an open file can be synced, so an appended log can be made durable (lane FSYNC, 17 November 2026)

Not breaking: an addition only. A handle from `fs.open` has a seventh method, `f.sync() -> Result[Unit, str]`: when it answers `Ok`,
everything written through the handle is on stable storage (one `fsync(2)`, after the data; the handle holds no buffer of its own). A
full disk or an I/O error answers `Err("sync 'PATH': REASON")`, naming the path the file was opened under and the system's reason in
words, and is not a trap. A handle opened only to read answers `Ok` and does nothing, as `flush` does there; the in-memory filesystem a
test is handed answers `Ok`; a device that cannot be synchronized (`/dev/full`) answers `this kind of file cannot be synchronized`. The
folder of a new file is not synced implicitly: call `fs.sync_directory` once after the file is created (`docs/io.md`, "Making an
appended record durable"). The `E_FILE_ARGUMENT` message for an unknown file method now lists `sync`. `flush` and `write` are unchanged.
`experiments/audit-work-20261111/FSYNC.md`.

### `W_NEEDLESS_COPY` writes the bare value for a copy that holds nothing managed (lane COPY-A1d, 16 November 2026)

Not breaking: one repair changes its edit and its message, and no program is accepted or refused differently. For a copy at a last use
the repair wrote `own x` whatever `x` was, and for a value with no managed part (a record of numbers, an option of one) the check
refuses that marker (`E_OWN_MARKER`), so `mylang fix` passed through a round in which the project did not check and took the `own` back
in the next one. The repair is now the bare value, in one round, and the message says why: "`fill` holds no managed value, so
`copy(fill)` copies nothing a plain use would not: write `fill`". The test is the check's own (`owned_types.zig`, moved unchanged out of
`core/single_owner.zig`). A value with a managed field keeps `own x`. `experiments/audit-work-20261111/COPY-A1d.md`.

### The guides say what first-time writers needed: `mylang docs concurrency`, `mylang.json` and four sentences made true (lane SPDOC, 17 November 2026)

Not breaking: documentation only, and no program is accepted or refused differently. `mylang docs concurrency` prints `docs/concurrency.md`,
which opens with the four task rules (values in and out, no capability, no `mut` argument, no handle in a list) and the thread count. The card
names that topic and says `debug(...)` prints nothing in a `build --release` executable; two function names left its operations list to keep it
under 6,000 characters. `docs modules` shows the smallest `mylang.json` and every key it accepts; `docs io` says a `with`-bound file is lent as
`mut`; `docs records` says a loop that goes on after consuming an outer `@linear` owner is refused and one that leaves the function is not;
`docs stdlib` names the reads that take no `byte_buffer`. `experiments/audit-work-20261111/SPDOC.md`.

### `filesystem.read_link`, and the owner, group and link count in `Stat` (lane FSLINK, 17 November 2026)

Not breaking: additions only. `filesystem.read_link(fs, path) -> str fails str` (and the builtin `fs.read_link_path(path)`) answers
the text stored in the symbolic link at `path`, as `readlink(2)` does and without following it: relative or absolute, dangling or not,
the first link's text for a link to a link. It resolves its path as `filesystem.stat` does on every kind of root (no restriction, a
`--restrict` grant, an `fs.dir(...)` narrowing, `fs.read_only()` and `filesystem.memory()`), so it refuses a link on the way, an
absolute path under a grant and a `.` or `..` component as `stat` does, and reads a link whose target is outside the grant, which
gives no access to the target. An entry that is not a link fails with `read link 'PATH': is not a symbolic link`. `Stat` has three
more fields, `owner`, `group` and `links` (`st_uid`, `st_gid`, `st_nlink`), default `0`, so constructions and matches compile as
before; the in-memory filesystem is owned by `filesystem.MEMORY_OWNER` and `MEMORY_GROUP` (1000), a file or a link has one link and a
directory two plus its directories. The raw answer of `stat_path` is 80 octets, not 56; its first seven words are unchanged.
`experiments/audit-work-20261111/FSLINK.md`.

### An append under a grant refuses a final symbolic link (lane FSAPPEND, 16 November 2026)

Breaking, by the user's decision of that day, for the one program that relied on the hole: `fs.open(path, "a")` through a root other than
the unnarrowed one of a run with no restriction (a `--restrict` or `--allow-*` grant, or any `fs.dir(...)` narrowing) now refuses a
symbolic link as the last component of its path, as a read, a write and every other call on that root already did. It had followed the
link: under `--restrict` an append through a link to a file outside the grant wrote there, and through a dangling link it created the
file outside the grant. It now answers `open 'LINK': is a symbolic link the sandbox does not follow, or links nest too deeply`, writes
nothing and creates nothing. An append to a regular file or to a new name, and the append of an unnarrowed `Filesystem` in a run with no
restriction (which follows a link, as an ordinary process does), are unchanged. `experiments/audit-work-20261111/FSAPPEND.md`.

### `mylang fix` writes the `for x in own xs` that `W_COPY_MOVE` named (lane COPY-A2c, 16 November 2026)

Not breaking: hints become repairs, and no program is accepted or refused differently. The loop hint "`x` is copied out of each
element of ..." repaired nothing. Inside one function, a loop over the list a call returns or over a list local the function owns,
whose copy of the element or of a field of it (`copy(x.f)`) nothing reads after, is now a `W_NEEDLESS_COPY` repair: `for x in own xs:`
and `own x.f`. A plain list parameter nothing reads after the loop is the `own`-parameter repair, `W_COPY_FOR_STORE` in a project check:
`own` before the parameter, `for x in own xs:`, `own x` or `own x.f` for the copy, and `own` before each caller's last use of a name,
withheld as that warning is (a generic or recursive function, a `public` one unless the project is no package, a function value, a
default, a `from`, a caller that passes a place or keeps its list). `experiments/audit-work-20261111/COPY-A2c.md`.

### `W_COPY_FOR_STORE` also repairs a `public` function of a project that is no package (lane COPY-A3d, 16 November 2026)

Not breaking for the project that is repaired: every caller of the function is in it, and the check refuses nothing new. A `public`
function whose stored parameter no caller needs afterwards is declared `own` by `mylang fix DIR`, like a private one, when the project's
`mylang.json` sets no `interface_files` and its modules do not all lie in one namespace (`NAME.my` and `NAME/`: a package root, which
is how another project imports a module, keeps its public signatures); the warning says "its signature changes". A package, a project
with `interface_files` and a check of one file print what they printed. The check summaries are keyed by this answer.
`experiments/audit-work-20261111/COPY-A3d.md`.

### `W_COPY_FOR_STORE` also repairs a parameter whose callers pass a name at its last use (lane COPY-A3c, 16 November 2026)

Not breaking: the repair reaches more parameters, and no program is accepted or refused differently. Where a caller passes the bare
name of an owned local or an `own` parameter and the ownership check finds it does not use it again, the one repair also writes `own `
before that name at the call, in whatever file the caller is; `mylang fix FILE` sets such a repair aside and `mylang fix DIR` applies
it. A name read again, a plain parameter, a field, a loop element or a pattern binding still withholds it. The check summaries' format
is `check-summaries-v29` (each caller's stored answer holds its marks): the first check after the upgrade checks every body once.
`experiments/audit-work-20261111/COPY-A3c.md`.

### `mylang fix` declares a result `from` last, in a round of its own (lane COPY-A2e, 16 November 2026)

Not breaking: no program is accepted or refused differently, and a run with no `W_COPY_RETURNED` repair takes the rounds it took. The
`from` repair judges every caller as it is written now, and another repair of the same round may rewrite a caller so that it takes the
result (`for x in own keys(row)`, a parameter made `own`), which `from` then refuses: the run ended in `E_SINGLE_OWNER_BORROW`, or wrote
a `copy(...)` into a caller. Now a round that applies any other fix, in any file of the run, leaves the `from` fixes out and prints
nothing; the next round's check judges them again against the callers as they then are. A run that set one aside takes a round more.
`check --warnings` still prints both warnings. `experiments/audit-work-20261111/COPY-A2e.md`.

### `W_COPY_RETURNED`: `mylang fix` declares a result `from` the parameter whose places every return copies (lane COPY-A2d, 16 November 2026)

Not breaking: a check warning and its `mylang fix` repair are added, a false hint is dropped, and no program is accepted or refused
differently. The `W_COPY_MOVE` hint "every return of `f` copies a place of `p`" repaired nothing. A project check (`mylang check DIR`)
now warns `W_COPY_RETURNED` in its place where the function is private, not generic, not recursive and not named as a value, and no
caller in the project is refused once the result is `from p` (a caller that returns the result is). The repair writes ` from p` after
the result type and each returned `copy(PLACE)` as `PLACE`; no caller changes. The hint is no longer given where a return is a new
value (`E_BORROW_MIXED` whatever the callers do) or the parameter cannot lend the result. `experiments/audit-work-20261111/COPY-A2d.md`.

### `mylang fix` writes the `take` of a `const` local and the `options.take_or` that `W_COPY_MOVE` named (lane COPY-A2b, 16 November 2026)

Not breaking: two hints become repairs, and no program is accepted or refused differently. `W_COPY_MOVE` said "declare `x` with `mut`,
then `take(mut x.f)` moves it out" for a copy of a field or an element of a `const` local that nothing reads again, and "`options.take_or(own
opt, d)` returns its payload" for `copy(opt.unwrap_or(d))`, and `mylang fix` made neither edit (agents acted on 3 of 534 such hints). Both
are now `W_NEEDLESS_COPY` repairs of every edit: the first replaces the copy by `take(mut x.f)` and the `const` of `x`'s declaration by
`mut`; the second replaces the copy by the call and adds `import options` when the unit has none. Two copies of fields of one local give
two repairs that carry the one identical declaration edit, which a round applies once (`mut mut` is never written). The hint stays for a
declaration that has no `const` word of its own (`const a, b = ...`), a function that has a local named `options`, an option or default
text that holds a comment, an option local that a loop outside its declaration runs again, a `match` or `with` head or a branch condition
that reads it, and another read of it in the statement that holds the copy. One shape draws no `take` finding at all now, hint or repair: a
local that a bind-or-else payload borrows (`const at = sc.at_v else:`, then `take(mut sc.cite)`) while the payload is read after the copy or
held by a `match` around it; the checker refused that edit (`E_SINGLE_OWNER_OVERLAP`), and main's repair for a `mut` local wrote it.
`experiments/audit-work-20261111/COPY-A2b.md`.

### Breaking at run time: a `Filesystem` narrowed by `fs.dir` follows no symbolic link in any run (lane FSDIR, 16 November 2026)

No program is refused or accepted by `check` or `build` differently; a run without `--restrict` answers differently. `fs.dir("d")` narrows
a `Filesystem` to a directory, and `docs/effects.md` promised that the derived handle rejects any request that could leave the subtree, yet
a run without `--restrict` resolved the joined path as an ordinary process does, so a link inside `d` led out of it: `read_text`, writes,
listings, `mkdir`, `remove`, `open` and the durable calls (`stat`, `rename_path`, `atomic_write_file`, `chmod_path`, locks and the rest)
all went through it. The handle now resolves each request as a `--restrict` grant does, by the decision of 16 November (ACM-1: "refuse in
every run"): a link on the way is refused with `a parent of the path is not a directory`, a link at the end of a read, write or append
with `is a symbolic link the sandbox does not follow, or links nest too deeply`, a listing of a link with `is not a directory`, and a
narrowing whose own prefix is a link (`fs.dir("link")`) refuses what lies below it the same way. A nested narrowing (`fs.dir("a").dir("b")`) is one prefix and behaves so.
Unchanged: the unnarrowed `Filesystem` of a run without `--restrict` (it still follows links and takes absolute paths), anything under
`--restrict`, `fs.read_only()` of an unnarrowed handle, `canonical_path` and `stat_follow_path` through a narrowed handle (they follow a
link only while it stays inside the narrowing), and which kinds of file the unrestricted root serves (a FIFO or a device is still opened
through a narrowed handle). To migrate: a program that reached a directory through a link under a narrowing names the link's target
directory in `fs.dir`, or reads it through the unnarrowed handle. `experiments/audit-work-20261111/FSDIR.md`.

### `W_COPY_FOR_STORE`: `mylang fix` declares a stored parameter `own` where every caller passes a new value (lane COPY-A3b, 16 November 2026)

Not breaking: a check warning and its `mylang fix` repair are added, and no program is accepted or refused differently. A project check
(`mylang check DIR`) warns where a private, non-generic, non-recursive function copies a plain parameter into storage it keeps, the
needless-copy pass proves the copy a move once the parameter is `own`, and every caller in the project passes a new value there (a
literal, a call's result, a constructor, a concatenation or a `copy(...)`). The repair writes `own ` before the parameter and `own name`
for the copy, all in the function's file; no caller changes. Elsewhere `L_COPY_FOR_STORE` stays advice.
`experiments/audit-work-20261111/COPY-A3b.md`.

### `mylang fix` writes `match own` where a match payload is copied and its owner is not read again (lane COPY-A2a, 16 November 2026)

Not breaking: a hint becomes a `W_NEEDLESS_COPY` repair, and no program is accepted or refused differently. `W_COPY_MOVE` named
`match own r:` as the form that replaces `copy(p)` of a payload of `match r:` and repaired nothing. Where `r` is an owned local that nothing
reads after the match or inside it, the match is a statement written `match r:`, no loop around it runs it twice with `r` declared outside,
and the payload is read nowhere after the copy, the finding is now `W_NEEDLESS_COPY` with two edits, `match r:` to `match own r:` and
`copy(p)` to `own p` (a bare `p` at a `return` or `fail`), which `mylang fix` applies; a bind-or-else `const p = r else:` takes `own` in the
same place (`const p = own r else:`). Two arms that copy report the same `own ` edit, which a round applies once. Every other copy of this
form keeps its hint, in its old words (`if r is Some(p):` has no `own` spelling). `experiments/audit-work-20261111/COPY-A2a.md`.

### `W_NEEDLESS_COPY` reaches three last uses it called used again (lane COPY-A1c, 16 November 2026)

Not breaking: a lint finding and its `mylang fix` repair are added, and no program is accepted or refused differently. The `own x`
repair was silent for three last uses the move checks. A copy in an early `return` or `fail` was counted as followed by every read the
source puts after it, though a later `return` reads the value on a path the copy never takes; only the rest of the statement now counts
(a loop's generated statements, spelled over the whole loop, no longer stand for the statement that holds the copy). The last of several
copies of one local in a constructor, a list literal or a call moves when every other mention is an earlier operand's copy (operands run in
the order written, a call's through `evaluation_order`). A copy in a `with` body was always held; the scope holds what its head names, and
the body runs once. `experiments/audit-work-20261111/COPY-A1c.md`.

### `mylang lint --copies A.my B.my ...` prints one count for several entries (lane COPY-C1b, 16 November 2026)

Not breaking, except that the JSON gains a field: `mylang lint --copies` with two or more entry files lints each in turn, in one process, and
prints one count for the union of the files they reach: each file and each copy once, a copy in the best category any entry gave it, and
`entries: N` as a first text line (the JSON line carries `"entries":N` after the schema name, for one entry too; the schema stays
`copy-count-v1`). One entry prints the text it printed. An entry that does not check ends the command as it ends a lone entry, and one line
names it. Several entries without `--copies` are a usage error. `experiments/audit-work-20261111/COPY-C1b.md`.

### `L_COPY_FOR_STORE` no longer advises `own` where `own` cannot be written (lane COPY-A3a, 16 November 2026)

Not breaking: fewer lint findings, and no program is accepted or refused differently. The finding advised "declare it `own`" for a `mut`
parameter, for a parameter that is already `own`, and for a parameter whose type holds no managed storage (a record of numbers, where
`own required` is `E_OWN_MARKER`). It is no longer raised for those three; every other finding is unchanged in code, position and text.
The detection moved to `src/copy_for_store.zig`. `experiments/audit-work-20261111/COPY-A3a.md`.

### `W_NEEDLESS_COPY` reaches a return of what a result handed over (lane COPY-A1b, 16 November 2026)

Not breaking: a lint finding and its `mylang fix` repair are added, and no program is accepted or refused differently. `return copy(text)`
stayed silent where `text` was bound by `const text = strings.decode(bytes[a:b]) else Err(_):` or by a `case Ok(text):` of
`match fs.read_file(path):`, though the bare `return text` checks. The pass knew a match over a user function's fresh result owns its
payload, but a library function and a capability's method are nodes of their own, not calls, and a slice argument wraps the call in a
block; none was read as fresh. They are now (a result declared to borrow with `from` still lends its payload). In a function that `fails` or
returns `T?`, `return copy(x)` was also worded `pass own x` and edited to `return own x`, which `E_OWN_MARKER` refuses and a second round
mended; the `Ok` or `Some` the return wraps is now seen as a return, so the first edit is `return x`. `experiments/audit-work-20261111/COPY-A1b.md`.

### `mylang lint --copies` prints how many copies a program writes per 1,000 lines (lane COPY-C1, 16 November 2026)

Not breaking: a new switch, and `mylang lint` without it prints what it printed. `mylang lint --copies PATH` prints the count of
`copy(...)` calls the program writes (test files included, the standard library left out), the number per 1,000 lines, and how many
of the copies `L_NEEDLESS_COPY`, `L_COPY_MOVE`, `L_COPY_FOR_STORE` and `L_COPY_IN_LOOP` name, each copy once in the first of them
that sits on it; `--json` prints one `copy-count-v1` line with each file's share. It adds no finding and changes none; `--gate` or
`--accept` with it is a usage error (exit 2). `experiments/audit-work-20261111/COPY-C1.md`.

### `W_NEEDLESS_COPY` reaches a last use in a branch (lane COPY-A1a, 16 November 2026)

Not breaking: a lint finding and its `mylang fix` repair are added, and no program is accepted or refused differently. The `own x`
repair of a copy that is the last use of an owned local was silent in two shapes the copy audit found by hand. A copy in the body of an
`if` was refused whenever the condition read the local (`if len(asked) > 0: version = copy(asked)`), though a condition is a boolean and
its read is over before either body runs; the refusal now holds only for a condition the copy is part of. A copy that is the value of an
element write (`items[0] = copy(loose)`) was judged as a binding of a lowering temporary and never as a value the write takes over; it is
now judged as an assignment is. `experiments/audit-work-20261111/COPY-A1a.md`.

### Two copy lints reach what they missed (lane FR40, 16 November 2026)

Not breaking: lint findings are added, and no program is accepted or refused differently (both rules stay as they are: `L_COPY_FOR_STORE`
reports only, `L_COPY_IN_LOOP` refuses under `--gate` only in a declaration changed against `--against REF`). `L_COPY_FOR_STORE` named
the first parameter a statement copies into storage and none of the others, at the start of the statement; it now gives one finding for
each parameter, at that parameter's own `copy(...)` (a parameter copied twice in one statement is named once). `L_COPY_IN_LOOP` reported
nothing for a file named `_test.my`, because `cost --sites` follows only what `main` reaches and a test file has none; a lint now also
reads the copy rows of the functions the project's discovered tests reach. `experiments/audit-work-20261111/FR40.md`.

### The copy-in-a-loop lint no longer sends a `str` to `symbols` or `spans` (lane FR39, 16 November 2026)

Not breaking: the text of one lint finding changes, and no finding appears or disappears and no program is accepted or refused
differently. `L_COPY_IN_LOOP` told a `str` copy to "intern it once with `symbols`" or to "store a `spans.Span` into the source", and both
hold `bytes`: `symbols.intern(mut table, name)` is `E_TYPE` "expected bytes, found str", and a span's text is `bytes`. The advice for a
`str` now names a form that checks: when the copy reads the element of a `for x in xs` loop over a list the function owns (a local or an
`own` parameter), the loop that takes the list (`for x in own xs`, then `own x` or `own x.field`, if neither is read again); over a list the
function is lent, that the copy is a real transfer and an `own` list parameter would let the loop take the elements; for a slice of a `str`
or a `str` read elsewhere, a real transfer. The advice for `bytes` is the same. `experiments/audit-work-20261111/FR39.md`.

### A directory test run ends with one `warnings:` line (lane FR36, 16 November 2026)

Not breaking: the closing `warnings: N in M unmodified modules (CODES); `mylang check --warnings` lists them` line of `mylang test DIR`
changes, and no program is accepted or refused differently. It was printed once for each entry's process, so ten entries that shared a
module with a warning printed it ten times, in the order the processes ended. The run now ends with one line, after the results, that
counts a warning once however many entries import its module (the same place and code is one warning) and a module once, the same at
every `--jobs`. An entry hands the warnings it withheld to the run in the file of the internal option `--fix-count-file` (FR33), after
its two counts; a project that denies warnings and fails still prints every warning withheld. One change reaches single runs too: codes
as common as each other in the line are now in name order, where they were in the order they were first met.
`experiments/audit-work-20261111/FR36.md`.

### `mylang fix` deletes the unused Stream parameter of `main` (lane FR35, 16 November 2026)

Not breaking: one refusal gains the repair its message already named, and no program is accepted or refused differently.
`func main(out: Stream) -> int:` with `out` unread was `E_UNUSED_CAPABILITY: ... delete the parameter` and `mylang fix` said `nothing to fix`; the
diagnostic now carries the deletion, the check's closing line says `mylang fix FILE` repairs it, and the file then checks. The edit takes
the parameter and the comma that separates it (`main(args: str[], out: Stream)` becomes `main(args: str[])`, a sole parameter leaves
`main()`, a list over several lines keeps its lines); `out` and `err` both unused are repaired over two rounds. It is offered only when
nothing else can see the change: no comment between the parameter and its neighbour, and `main` named nowhere else in the file but in
a comment line (a call would keep its argument), else the message stands with no edit. Every other capability parameter keeps its rename.
`experiments/audit-work-20261111/FR35.md`.

### A method call on a value is told the standard module's function it meant, with its import (lane FR34, 15 November 2026)

Not breaking: the text of one refusal changes and it gains a repair, and no program is accepted or refused differently. `clock.now()` was
`E_UNKNOWN_TYPE: ... write the function form `now(clock)`; no function `now` is declared or in the prelude, so declare it first`, which
points at a function that does not exist. When no function of that name is in scope and exactly one standard module declares one whose
first parameter takes the receiver's type, the answer is now `` write the function form `time.now(clock)`, from the standard module
`time`, and add `import time` `` (without the last clause when the file imports `time`), and `mylang fix` rewrites the call and writes the
import. It holds for a capability, a `str`, an `int` and any other type the language supplies (`n.gcd(4)` is `math.gcd(n, 4)`); a
receiver of a type the program declares, a function the program declares, two modules that both declare the name, and a module imported
under another name (`import time as t`) keep today's text. `experiments/audit-work-20261111/FR34.md`.

### A call's qualifier that is nothing at all says it is not a name in scope (lane FR34, 15 November 2026)

Not breaking: the text of one refusal changes, and no program is accepted or refused differently. `print(out, nosuch.f(1))`, where `nosuch`
is no local, parameter, type, imported module or module file, was `E_UNKNOWN_TYPE: type is not declared`. It is now `` `nosuch` is not a
name in scope here: it is no local, parameter, type or imported module, and no module file of this project has that name ``, followed by
`; did you mean `count`?` when a local or a type in scope is within two edits (`cuont.f(count)`). The code is unchanged, a qualifier that
is a module file of the project is still told to import it (`E_MODULE_NOT_IMPORTED`), and a file that imports modules still reports
`E_UNKNOWN_SYMBOL` for the same slip. `experiments/audit-work-20261111/FR34.md`.

### Ten library declarations are described by their own comment, not by their module's header (lane FR34, 15 November 2026)

Not breaking: comments and the answer of `mylang reference` change, and no program is accepted or refused differently.
`mylang reference --query buffers.empty` and `--query sets.add` answered with "The byte-buffer module: ..." and "The set module: ...",
because the module's header comment ran straight into the first function's comment. The same held for `bytes.starts_with`,
`dicts.find`, `simd.splat`, `spans.Span`, `binary.Error`, `http.Header` and `process.Request`, which now answer with their own first
sentence. A header is the comment that opens a module's file and ends at its last empty `#` line, or sits above the `import` lines
(`mylang fmt` removes a blank line between comment lines, so a blank line cannot separate them); `src/reference_test.zig` checks all
38 modules. `experiments/audit-work-20261111/FR34.md`.

### A project module used without its import is told to import it, as a standard module is (lane FR32, 15 November 2026)

Not breaking: the text and code of one refusal change, and no program is accepted or refused differently. `util.twice(2)` in a file with
no `import util` was refused as `E_UNKNOWN_TYPE: type is not declared` (or `E_UNKNOWN_SYMBOL`, `E_UNKNOWN_NAME` or an `E_SYNTAX` for
`util.Row` in a type's place), which named neither the module nor the import. When a module file of that name is under the import root
(`util.my`, `shared/calc.my` for `shared.calc.f(x)`), the refusal is now `E_MODULE_NOT_IMPORTED`: `` `util` is a module of this project
that this file does not import; add `import util` ``, and `mylang fix` writes the line. `calc.f(x)` with the one file `shared/calc.my`
below the root gets `import shared.calc`. A qualifier that is no module file keeps its message. `experiments/audit-work-20261111/FR32.md`.

### A directory test run ends with one `mylang fix` line (lane FR33, 15 November 2026)

Not breaking: the closing `` `mylang fix FILE` repairs N of these M `` line of `mylang test DIR` changes, and no program is
accepted or refused differently. It was printed once for each entry's process, each with that entry's file, so ten entries with one
finding each gave ten lines, in the order the processes ended. The run now ends with one line: the directory as it was given, the
counts of all its entries summed (`` `mylang fix tests` repairs 10 of these 10 ``), the same at every `--jobs`. An entry hands its
counts to the run through an internal option, `--fix-count-file`, which only a directory run passes.
`experiments/audit-work-20261111/FR33.md`.

### The last places that called a function a method now say function (lane DOC1, 15 November 2026)

Not breaking: comments, two guides and the language card change, and no program is accepted or refused differently. Five library
comments described a function by "the method" (`buffers.my`, `byte_builder.my`, `sets.my`, `strings.lines`, `strings.split`) and now
say what the function does. The guide sections "String methods" (`docs/text.md`) and "Set methods" (`docs/sets.md`) are "String
functions" and "Set functions": the set section named `issubset`, `issuperset`, `isdisjoint` and `copy` as if they were `sets`
functions (they are `sets.subset`, `superset`, `disjoint` and the prelude's `copy(s)`), the string section said `find` answers `-1`
(it answers `None`; `strings.char_find` answers `-1`) and that its results are all fresh (`strip`, `lstrip` and `rstrip` answer a
view). The `python-string-methods` feature's `doc` pointer is `docs/text.md#string-functions`. `docs/card.md` says
`time.now(clock)`, not `clock.now()`, and drops the sentence on `sort.sort_by_key` taking `int` keys to stay within 6,000
characters. `experiments/audit-work-20261111/DOC1.md`.

### Two parameter-list messages name what is wrong and what to write (lane FR31, 15 November 2026)

Not breaking: the text of two diagnostics changes, and no program is accepted or refused differently. A parameter without `named`
after one that has it was refused with `put 'named' and 'mut' before each parameter name`, which named neither parameter; it now says
`` `items` follows the `named` parameter `factor`, and a parameter without `named` cannot follow one that has it: write `named items`,
or move `items` before `factor` ``, and `mylang fix` writes what it says (`named items: int[]`). A parameter after the `*` separator and
a `mut` written before the type have messages of their own. A parameter written without its type, `func f(named = 3)` (`named` before an `=` is the
parameter's own name, as before a colon since lane FR29) and `func f(count = 3)`, was refused with `unexpected token; expected a name`
and `unexpected token; expected :`; both now say `` parameter `count` has no type; a parameter needs
its type after a colon, as in `count: int = 3` ``. `experiments/audit-work-20261111/FR31.md`.

### An unused Stream parameter of `main` is told to be deleted, not renamed (lane FR31, 15 November 2026)

Not breaking: the text of one diagnostic changes and one repair goes, and no program is accepted or refused differently. On the entry
`main`, `E_UNUSED_CAPABILITY` for an unused `out` or `err` Stream used to say `rename it to `_out` to retain the callback signature`,
and `mylang fix` made that rename, which `E_MAIN` then refused (an entry's Streams are named `out` or `err`). It now says
`capability parameter `out` is never used; delete the parameter (an entry Stream parameter must be named `out` or `err`, so it cannot be
renamed `_out`)` and carries no edit. Every other capability parameter, `main(host: Host)` included (`_host` is accepted), keeps the
rename advice and its repair. `experiments/audit-work-20261111/FR31.md`.

### `mylang rename` of a parameter called `named`, `mut` or `own` is no longer refused for the modifier beside it (lane FR30, 15 November 2026)

Not breaking: a rename refused before is accepted now, and every rename accepted before writes the same edits. Since lane FR29 a
parameter can be called `named` (`own` and `mut` already could), and `mylang rename` of such a parameter was refused, `2 uses of
`named` could not be resolved ... nothing was written`, whenever its file also held the modifier (beside it or in another function):
it counted the modifier word as a use of the name. The resolver now records a modifier the parser reads before a
parameter's name (`named limit: int`, `own rest: T`, `mut total: int`), before a binding (`mut sum = 0`) or in a call
(`add(2, mut sum)`, `keep(own rest)`) as naming nothing, so the parameter is renamed with its reads and its keyword-argument labels
and the modifier stays. `docs/tooling/rename.md`, `experiments/audit-work-20261111/FR30.md`.

### `mylang rename` of a function a local hides is accepted, as the rename of the local is (lane FR30, 15 November 2026)

Not breaking: a rename refused before is accepted now, and every rename accepted before writes the same edits. A local with the
name of a function of its module (`E_SHADOWING`) could be renamed, but renaming the function, which cures the same error, was
refused: with the error gone the later checks run, and a warning the file always held counted as a difference (`2 diagnostics
differ: [new: warning W_NEEDLESS_COPY] [gone: error E_SHADOWING]`; on the site, 25 `W_COPY_MOVE` of code the rename did not
touch). A rename whose target is hidden by bindings (`E_SHADOWING` with a `declared here` note at the target) is now compared
with the project cured by renaming those bindings in a copy: the errors must be the project's less those refusals, and the
renamed project must check exactly as the cured copy does, so the warnings the refused check could not reach are counted as the
binding's repair counts them (`1 warning the refused check did not print is printed now`), and any other difference still
refuses it. `docs/tooling/rename.md`, `experiments/audit-work-20261111/FR30.md`.

### The component builder's seed compilers use the gate's own stores (lane GATE3B, 15 November 2026)

Not breaking: a tooling change to `selfhost/components.zig` and `scripts/verify_cache.py`; no program or flag of the compiler
changes, and the two components keep their bytes. The builder starts the seed compilers with every `MYLANG_`
variable dropped, except the locations of the stores they open (`MYLANG_COMPILER_SHARED_CACHE`, `MYLANG_TEST_SHARED_CACHE`,
`MYLANG_STAGE_SHARED_CACHE`), so a complete gate's seed compilers open the request's own stores and not the per-user ones. The
gate's exception for them is gone: a seed compiler that opens a per-user store fails the request with status 6 like any build.
The builder's source is part of a component's key, so each of the two components is rebuilt once, to the same bytes. `experiments/audit-work-20261111/GATE3B.md`.

### A report that holds diagnostics with a fix ends by saying how many (lane B2, 15 November 2026)

Not breaking: one more line of text on standard error, and no program is accepted or refused differently. `check`, `check-project`,
`check-module`, `build`, `run`, `run-project` and `test` end a report in which some printed diagnostics carry a structured fix
with `` `mylang fix FILE` repairs N of these M ``: N of the M diagnostics printed, errors and warnings together, have an edit that
`mylang fix` applies, and FILE is the path as it was given. Withheld warnings (`warnings: 7 in 3 unmodified modules ...`) and dropped
hints are in neither number, a replayed build or test and a project check served from its stored verdict print the line their first
run did (the verdict record is `mylang-frontend-cache-v16`, so older ones are not served), and `--diagnostics=json` is unchanged.
Agents repaired by hand what `mylang fix` does in one command (of five lanes of the site, one ran it). `docs/tooling/fix.md`,
`experiments/audit-work-20261111/B2.md`.

### A method call on a value no longer advises a function that is not in scope (lane B2, 15 November 2026)

Not breaking: only the text of a refusal changes. `out.write_line("hi")` was refused with `E_UNKNOWN_TYPE: a value of type `Stream` has no
methods; write the function form `write_line(out, "hi")``, and a lane of the site wrote it: nothing declares a `write_line` (the
hint repeated the method's name, and no `write_line` exists in the sources or the prelude; `print(out, ...)` writes to a Stream).
The message now says whether the function form names a function in scope: for a Stream that has none, it names `print(out, ...)`;
for any other receiver it adds `; no function `NAME` is declared or in the prelude, so declare it first` after the form. The same
call with a declared or prelude function keeps the earlier text. `experiments/audit-work-20261111/B2.md`.

### An unknown function of a module lists its close names, and for a name with none close, the names it holds (lane B2, 15 November 2026)

Not breaking: the refusal is the same and its message says more. `strings.isdigit(text)` already said `did you mean `is_digit`?` (F-51,
within two edits). A name with no function within two edits (`strings.splitlines`) now lists the functions of the module that contain
it or that it contains once underscores are left out, up to three, longest first (`did you mean one of: `lines`, `split`?`). Neither
list is a fix: a nearest name is a guess (`strings.rfind` one edit from `strings.find` is another function), so the diagnostic carries
no edit and `mylang fix` leaves the file alone. `experiments/audit-work-20261111/B2.md`.

### `mylang docs card`: the rules a writer trips on, on one screen (lane C2, 15 November 2026)

Not breaking: a new guide and nothing else. `mylang docs card` prints `docs/card.md`, at most 6,000 characters for a reader who
knows Python and is about to write Selka: the shape of a program and its capabilities, bindings, ownership (what borrows, what a
loop variable and a match payload are, and what to write instead of `copy(...)`), results and options, text, collections, modules
and tests, and the three commands to use before guessing. Each rule was run against the compiler; the two examples are run by the
doc gate, and a unit test keeps the page at 6,000 characters or fewer. The first lines of `mylang --help`, the topic list and the
primer name it. `experiments/audit-work-20261111/C2.md`.

### `mylang reference` answers a library function's call (lane B1, 15 November 2026)

Not breaking: no program's check changes, and no JSON field changes. `mylang reference --query strings.split` printed
`match=none`, so agents read the library's source out of the repository instead, or guessed (`strings.isdigit`,
`strings.splitlines`). A module-qualified name (`strings.split`, `lists.index_of`, `strings.Error`) or a bare prelude name (`len`, `sorted`,
`parse_int`) now answers in at most eight lines with the call as the source spells it, the first sentence of the comment above it and the
`mylang docs` guide; a module's name (`strings`) lists its declarations in source order; a qualified name no module declares answers with
the three nearest names of that module. The call forms are read from the embedded modules (`src/reference_source.zig`), the prelude rows
are curated in `src/reference_text.zig` and held against `prelude_names.zig`. The JSON envelope gains an `answers` array, `call` and
`summary` on each declaration and `method_form` on each method; the text of these answers leaves out the substring search. The curated
text that still described method forms W13 refused is corrected: the `core-builtin-spellings` entry, the `text` and `sets` guide lines,
the method facts (each now says its method spelling is refused) and two library comments. `docs/reference.md`,
`experiments/audit-work-20261111/B1.md`.

### A parameter can be called `named` (lane FR29, 15 November 2026)

Not breaking: only programs that were refused are accepted. `named` before a parameter's name is the modifier that makes its label
required, and the parser took every `named` at the head of a parameter for it, so `func count(named: int[])` was refused with
`E_SYNTAX: unexpected token; expected a name` and the caret under the colon, which says nothing about `named`; a local and a record
field called `named` were accepted. A `named` followed by `:` is now the parameter's name, in a function and in a callback type
(`func(named: int) -> int`), and in a callback type a `named` followed by `,` or `)` is a bare type of that name, as `own` and `mut`
already were; `named named: int` is the modifier and then the name. Nothing accepted before changes: a modifier is always followed
by a name, so each of those spellings was refused. `docs/python-syntax.md`, `experiments/audit-work-20261111/FR29.md`.

### The gate runs against compiler and test stores of its own (lane GATE3, 15 November 2026)

Not breaking: a tooling change to `scripts/verify_cache.py`; no program, flag of the compiler or key changes. An ordinary
verification request now gives every worker an empty compiler store and an empty test store of its own
(`.mylang-cache/verification-v3/gate-stores`, removed when it ends), as it gave an empty stage store before, so a gate's result no
longer depends on what other worktrees stored and a determinism mismatch a store logs is that request's alone: status 5. A build
of the request that opens a per-user store fails a green request with status 6 (a sample of `/proc/locks`; the component
builder's seed compilers are noted, not failed). `--own-stores off` restores the per-user stores; a store the caller names is kept.
Twelve forced complete gates: wall 1.05 times and CPU 0.98 times today's at the median. `experiments/audit-work-20261111/GATE3.md`.

### The refusal of a bare `open(fs, ...)` comes before the failure of its mode (lane FR28, 15 November 2026)

Not breaking: only the order of two refusals of a program that is refused already. `open(fs, p, mode)` with a mode that is not a
literal reported `E_FILE_ARGUMENT` and not the removed spelling (`E_REMOVED_SPELLING`, "write `fs.open(p, mode)`"), because the call's
own check failed before the spelling was judged. The spelling is reported first, as for every other bare file call, and its rewrite
(certain) is made by `mylang fix`; the mode is then reported for the form the program will have. `experiments/audit-work-20261111/FR28.md`.

### The advice for a `const` slice of an element of a fresh record says what a program can write (lane FR28, 15 November 2026)

Not breaking: only the text of a refusal changes. `const piece = make(t).items[0][0:1]` (and `.rows[0].text[0:1]`, a constructor or
a call's result) is `E_SLICE_ESCAPES`, which ended "or bind the record to a local first and slice that local's field". A `const`
slice of an element is refused for a local record as well (`const piece = r.items[0][0:1]`), so that advice led nowhere. It now
ends "or bind the record to a local first, then its element to another local, and slice that (a `const` cannot hold a slice of an
element, even of a local record)": `const r = make(t)`, `const item = r.items[0]`, `const piece = item[0:1]` checks. A `mut` binding of
the same slice keeps the short advice, which works for it. `experiments/audit-work-20261111/FR28.md`.

### `mylang fix` adds every missing import of a file in one round (lane FR28, 15 November 2026)

Not breaking: nothing is refused that was not, and `mylang fix` writes the same imports in the same sorted block. A file that calls
`strings`, `lists`, `hex` and `bytes` with none imported was refused four times (`E_MODULE_NOT_IMPORTED`) and `mylang fix` took
four rounds, a whole check of the project each: the four repairs insert at one point of the directive block, and a round took the
first of any edits that collide. A round now merges the import lines that belong at one point into one insertion, sorted by
module name (`fix_plan.mergedImport`); lines that belong at other points of the block were never in the way. And a refusal that
ends its statement's check no longer hides the imports named after it in the same statement (`print(out, hex.encode(b"hi"),
bytes.find(b"abc", b"c"))` reported `hex` and left `bytes` for the next check): `sema_recovery.siblingImports` reports them with it.
The file of the coordinator's report (`imp4.my`) went from 4 edits over 4 rounds to 1 edit over 1 round; the corpus is
`test/fixtures/fix-migration/missing-imports.my`. `experiments/audit-work-20261111/FR28.md`.

### `parse_f32` of a text parameter builds (lane FR28, 15 November 2026)

Not breaking: a program that passed the check and stopped the build now builds, and nothing is refused that was not.
`parse_f32(text)` of a `str` parameter (or of a local bound from one, or of a format string's text) stopped the build with
`internal error[E_CORE_HIDDEN_COPY]` ("`str_from_view` ... used by drop"): the lowering copied the borrowed text, the runtime helper's
span form then read the original, and the copy was left unnamed and dropped. `parse_int` and `parse_float` were already on the
list of text operations that read a borrowed receiver in place (`build_borrowed_view.spanReceiver`); `parse_f32` was not. The grid
`test/fixtures/parse-matrix` (`experiments/audit-work-20261111/FR28-grid/grid.py`) maps `parse_int`, `parse_float`, `parse_f32` and
the byte parses by where their text comes from: 862 cells, 860 build and run as the same parse of a local copy does. The other two
are `parse_f32` inside a generic function, which is refused at the check (`E_UNKNOWN_SYMBOL`) as before. `experiments/audit-work-20261111/FR28.md`.

### A trap inside a library function names the program's line first (lane FX18, 15 November 2026)

Not breaking: only the text of a trap's report changes, and no program's verdict or output. A trap whose site is in the
standard library (`strings.find(text, "x", start)` with a bound inside a character, `bytes.read_u8(data, 9)`, a failed
`assert` of `spans.text`) printed the library's line first, `@stdlib/strings.my:128:18: error[R_TEXT_BOUNDARY]: ...`. Its
first line now names the nearest frame outside the library, the program's own call (`main.my:4:12: error[...]`), and the
library frame follows it as the first `in` line, as context; the shapes of both lines are unchanged. A trap raised inside
a C operation of the runtime that does not end in its trap call (the bounded searches `find_offset` and `rfind_offset`
behind `strings.find` and `strings.rfind`) listed no caller at all; it now lists every program frame, in debug and
`--release` builds. `experiments/audit-work-20261111/FX18.md`.

### A buffer given where `bytes` is expected is told to write `bytes(...)` (lane FX17, 15 November 2026)

Not breaking: only the text of a refusal changes. A slice of a `byte_buffer` is a buffer since lane FR27, so `takes_bytes(buf[1:3])`
for a `bytes` parameter is `E_TYPE` "expected bytes, found byte_buffer", which said nothing of the repair. It now ends "; write
`bytes(buf[1:3])` for its octets" for a call's argument, and "; write `bytes(...)` of the value for its octets" wherever else a
buffer meets `bytes` (a typed binding, a return). `experiments/audit-work-20261111/FX17.md`.

### A returned slice of a buffer is told to copy it, not to declare the buffer result `from` (lane FX17, 15 November 2026)

Not breaking: only the text and the repair of a refusal change. `return buf[1:3]` in a function whose result is a `byte_buffer`
was refused (`E_BORROW_UNDECLARED`) with the advice "declare the result `from buf`", and `mylang fix` wrote that clause, which the
checker then refused: a `byte_buffer` result cannot be declared `from` a parameter. The advice is now "write `copy(buf[1:3])` to
keep both: a `byte_buffer` result cannot be declared `from` a parameter; for the octets alone, return `bytes(buf[1:3])` from a
function whose result is `bytes`", and `mylang fix` writes the copy. `experiments/audit-work-20261111/FX17.md`.

### Two writes through one `match mut` binding in one arm build, and a field of an element is written in place (lane FX17, 15 November 2026)

Not breaking: programs that passed the check and stopped the build now build, and nothing is refused that was not. Inside an arm
of `match mut`, a write whose receiver is the payload binding itself (`lists.exchange(mut items, 1, v)`, `lists.pop`, `dicts.pop`)
after an earlier write through it (`items[0] = v`, `append`, `exchange(mut items[0], v)`, `take(mut items[0])`, a dictionary
store) stopped the build with `E_CORE_UNSUPPORTED` ("write to a receiver's place while its arguments are
evaluated", Z3); and any write of a managed field of an element (`items[0].text = v`), alone or not, stopped it with
`E_CORE_UNSUPPORTED` ("the ownership pass cannot schedule a store"). Both build now, and each write sees the ones before it as
on a `mut` local. A write whose own argument changes the binding (`lists.exchange(mut items, 0, take(mut items[1]))`) stays
refused at the check (`E_SINGLE_OWNER_OVERLAP`), as on a local. `experiments/audit-work-20261111/FX17.md`.

### Breaking: one spelling for each operation; the method forms and second spellings are refused (lane W13-S5, 15 November 2026)

What is refused. A method on text, bytes, a byte buffer, a list or a set (`text.encode()`, `", ".join(parts)`,
`data.decode()`, `buf.find(b",")`, `xs.exchange(0, v)`, `seen.remove(x)`) is `E_METHOD_REMOVED`; a second spelling of an
operation (`math.min`, `max`, `sqrt`, `abs`, `round`, `floor`, `ceil`, `trunc`, `strings.to_int`, `to_float`, the bare
`unwrap_or(x, d)` and the 32 bare file functions such as `exists(fs, p)`) is `E_REMOVED_SPELLING`; a program's call of the
library's channels `run_process`, `process_control` or `stop_control` is `E_INTERNAL_NAME`. Since W13-S2 these were the
warnings `W_METHOD_FORM` and `W_DUPLICATE_SPELLING`, with the same rewrite. What stays: the option's `x.unwrap_or(d)`,
`strings.starts_with_at`, and the methods of capabilities and handles (`fs.read_text(p)`, an open file's `f.read()`).

The one command: `mylang fix src/` (each directory you check). It writes the function and the import it needs, in one
round for most files; a line with two nested rewrites takes two. A function of a standard module used without its
import (`strings.encode(text)` with no `import strings`) is now `E_MODULE_NOT_IMPORTED`, which `mylang fix` repairs too.
A `# lint: allow method-form` comment no longer excuses anything.

What `mylang fix` cannot rewrite for you, with the reason in the message: `math.abs(x)` (it fails on the most negative
`int`, where `abs` does not: handle that case and write `abs(x)`); a bounded `text.find(x, start)` whose answer is kept
rather than compared with a literal (it is `int?` now); a join whose separator and parts are both calls; a method whose
home a declaration of the same name in your file captures; a rewrite whose import a binding of the module's name would
hide. In the four projects swept (the netlisp port, selka-protobuf, selka-sqlite and a copy of the artifacts site) one
place needed a hand edit, protobuf's `math.abs`.

The one answer that can change: a rounding of a negative value to zero by the prelude's `round`, `floor`, `ceil` or
`trunc` keeps the sign (`round(-0.4)` is `-0.0`, where `math.round(-0.4)` was `0.0`); the two compare equal and print
differently. Add `+ 0.0` after the call where such a zero can reach printed output. See
`experiments/audit-work-20261111/W13-S5.md`.

### The loop `W_COPY_MOVE` hint asks whether a view is read again, and the near-guard note of `L_TEXT_SLICE_OCTETS` is one clause (lane FR27, 15 November 2026)

Not breaking: two warnings change their text or their presence, and nothing is refused. Lane FR26 withheld the loop hint
(`for x in own xs` and `own x.field` in place of `copy(x.field)`) wherever a view of the element or the list existed anywhere in the
function, since a move invalidates the views the checker still sees. Of the six hints that cost the port, three advised an edit the
checker refuses (a view read after the copy, a bind-or-else whose arm holds the value, a consuming loop inside another loop) and
three advised an edit it accepts (the view is read only before the copy, or sits in another branch). The hint now asks whether a
view is read again from the copy on, in the source after it or in a loop around it that the view was declared before, and it counts
a match that holds a call's returned view through the arm; the `mylang fix` repair keeps the broader question. The hint for a list
consumed in a loop inside another loop is withheld on its own merits (it was only by the accident of a view). The three accepted
hints are back on the port. The note of `L_TEXT_SLICE_OCTETS` for a guard that tests another text is one clause that names the guard
and the width the cut counts: "the guard `strings.starts_with(line, "x-length:")` tests another text than `len("content-length:")`, the
width this cut measures". `experiments/audit-work-20261111/FR27.md`.

### The advice to bind a fresh record first fits what the refused expression reads (lane FR27, 15 November 2026)

Not breaking: only the text of a refusal changes, and no program is refused that was not. Lane FR25's message for a value read
from a field of a newly made record (a constructor or a call's result) ended with "or bind the record to a local first and
slice that local's field", whatever the expression was: `Bag(items=[x]).items[0]` is an element, not a slice. It says now what
the expression reads: "slice that local's field" for a slice, "read the element from that local" for an element and "read that
local's field" for a field of one. It is left out where binding the record does not help, which the repaired program showed:
a returned value still lends the local it came from (every shape), and a slice that is appended or stored is still a slice of
the local. `experiments/audit-work-20261111/FR27.md`.

### A copy of a `byte_buffer`'s slice is a buffer that builds (lane FR27, 15 November 2026)

Not breaking: no program that built before changes what it does, and the checker's verdicts are the same except one message.
`mut piece = copy(buf[1:3])` followed by `buffers.append(mut piece, b"x")` passed the check and stopped the build with
`internal error[E_CORE_INVALID_IR]` ("call does not match its signature"): the checker typed the slice a `byte_buffer` and the
lowering made `bytes`. So did the slice passed to a `byte_buffer` parameter, `copy(buf[1:3])` returned, stored in a record
field or a list, passed `own` or `mut`, and a slice compared with a buffer (`E_CORE_HIDDEN_COPY`). The slice is lowered as what
it is typed, a new `byte_buffer` of the range (`myl_core_buffer_slice`: the bounds clamp and a negative one traps `R_LIST_BOUNDS`,
as for `bytes`), so every one of those builds and runs, writes and grows without touching the buffer it came from, and leaks
nothing. A comparison with octets and `bytes(buf[a:b])` still make one copy of the range. The one message that changes is
`E_BUFFER_SLICE_NAME` (lane FR26), which now says to write `copy(buf[1:3])` for a buffer of the range or `bytes(buf[1:3])`
for its octets. `experiments/audit-work-20261111/FR27.md`.

### `exchange` and `take` of an element of a `match mut` binding (lane FR27, 15 November 2026)

Not breaking: only programs that were refused are accepted. Inside a `match mut` arm whose payload `items` is a list of
managed elements (text, a record with a text field, a list), `exchange(mut items[0], v)` and `take(mut items[0])` were refused
(`E_SINGLE_OWNER_OVERLAP`, "'b' is written by a `match mut` arm that is running"), while `items[0] = v` and
`lists.exchange(mut items, 0, v)` in the same arm were accepted. The element is staged in a compiler temporary, and the check
did not know that a temporary read through another temporary of the binding reaches the binding too. It does now, so the builtins,
and `append(mut cells[i], v)` on a list of lists, are accepted where the accepted forms are. A loop over the binding that changes
an element is still refused (R7), with or without the loop variable read. The 167 cells of the exchange grid that were refused run
as their copy-and-store oracles do (`test/fixtures/exchange-matrix`). `experiments/audit-work-20261111/FR27.md`.

### Builds now: a part of another accessor's lent result returned under the same `from` (lane FX16, 15 November 2026)

Not breaking: it makes accepted programs build. `func first_name(xs: Net[]) -> str from xs: return pick(xs).name`, with
`pick(xs: Net[]) -> Net from xs`, passed `mylang check` and then stopped every build with `internal error[E_CORE_INVALID_IR]:
returned borrowed payload is not derived from its declared argument or final owner`, on every compiler; so did the result bound
first (`const x = pick(xs)` then `return x.name`), a chain of two accessors, and the same return in a loop or a `match` arm. The
IR verifier's borrowed-return rule followed a call only when the caller returned exactly the part the callee lends; it now also
follows a part inside that part (a field, an element, a slice, an option's payload), which the callee's contract already makes
its source's storage. The checker's verdicts do not change: a wrong contract stays refused. `experiments/audit-work-20261111/FX16.md`.

### An exchanged record whose fields are read builds (lane FX15, 15 November 2026)

Not breaking: a program that built before builds to the same code. `lists.exchange(mut xs, i, v)`, `xs.exchange(i, v)`
and `exchange(mut xs[i], v)` on a list of records with a managed field, when the code then read the old element's
fields (`was.text`), stopped the build with the internal error `E_OWNERSHIP_VALIDATION` ("a transferred read whose
result is not owned"). The code the compiler made was right: the old element is moved out of its slot and each of its
managed fields is handed to its read, so the element itself owns nothing (`emptied`). The certificate writer refused to
state a moved-out element in that state, which the ownership validator and its Lean copy already check (each listed
field taken exactly once, J8). It now states it, and both checkers judge it. See `experiments/audit-work-20261111/FX15.md`.

### Accepted again: a slice of a loop element's field bound to a name (lane FX14, 15 November 2026)

Not breaking: it undoes a refusal. Since lane FR25 `for net in nets: const suffix = net.name[1:]` was refused (`E_SLICE_ESCAPES`,
"needs its own value") over a parameter, a field, a local, a call's list or `enumerate`, for `str` and `bytes` fields, where every
earlier compiler bound a view of the element's field. FR25 refused a bound slice of a newly made record's field by treating every
compiler local of a record type as a temporary, and a loop's element is one. Only the hidden owner a slice expression makes for a
fresh record counts now, so the binding is a view again and a fresh record's slice stays refused. A refusal of a slice of a call's
result declared `from` a parameter names that parameter again instead of "a temporary value". `experiments/audit-work-20261111/FX14.md`.

### The standard library is written as programs are (lane W13-S3, 15 November 2026)

Not breaking: no program's verdict changes, and every program prints what it printed. The library's own sources (`src/stdlib`) are written in the
function forms a program must use: 274 calls moved from a method or a second spelling to its home (248 by the
edits `mylang fix` writes, 26 by hand), and the library
draws `W_METHOD_FORM` and `W_DUPLICATE_SPELLING` like any program, with no exemption and no waiver (friction entry
F-2): the bounded search that `strings.find` and `strings.rfind` convert to `int?` is a private home of the library's,
and the library's channel calls in `process` draw nothing, since the channels are the library's own. `bytes.find` and
the other `bytes` reads take a byte buffer's slice, and `bytes.rfind`, `index` and `rindex` a buffer with a literal
needle, as the methods do. `strings.strip`, `lstrip`
and `rstrip` are now `builtin func` homes of the native trim (still a view of the text, with every refusal the `from
text` declaration gave), and `lists.exchange` is the list's own exchange: it takes an index of any integer type and any
element, so `xs.exchange(i, v)`'s warning now carries its rewrite, `lists.exchange(mut xs, i, v)`. `lists.pop` takes any
storable element, as its method does. A receiver with no methods left (text, a list, a dictionary, a set) says so and
names its module in an unknown-method message, instead of listing retiring spellings. See
`experiments/audit-work-20261111/W13-S3.md`.

### BREAKING: nothing changes a collection while a loop walks it, through a `match mut` binding too (lane FR26, 15 November 2026)

Breaking, though nothing in the repository, the site, `selka-protobuf`, `selka-sqlite` or the port was refused (856 repository files,
77 site and project entries and the port's 539 modules, checked with the old compiler and this one: the same refusals, none new). A
loop over a payload binding of a `match mut` arm could change the collection it walks where the same loop over a plain `mut` local was
refused (`E_SINGLE_OWNER_OVERLAP`, rule R7): `for x in ns: append(mut ns, 1)` over a binding grew its list under its own loop (the loop
then walked the new elements too) and `for key in value: value["z"] = 1` over a dictionary binding trapped `R_LIST_ITERATION_MUTATION`
at run time, the loop variable unread after the change. The arm's own hold on the matched owner covered the loop's iteration loan; the
loan is taken beside the hold now, so a list, a dictionary and a set binding are refused as a local is, in a nested loop and under an
`if`, with R7's message, or, where the loop variable is read again, with the older "'slot' is changed here while 'word', a borrow of
its contents, is still used". A change after the loop, a change of another collection in the loop and a nested loop that only reads
stay accepted. There is no mechanical repair (the loop walks a copy, `for x in copy(ns):`, or the change moves out of the loop; which
one the program means is not certain), so `mylang fix` makes no edit. `docs/match-expressions.md`,
`experiments/audit-work-20261111/FR26.md`.

### The text-slice lint reads the length of a literal or a constant, and a tested cut stays quiet (lane FR26, 15 November 2026)

Not breaking: a lint finding, report only; no program's check changes. `L_TEXT_SLICE_OCTETS` did not see a bound that is the length
of a literal or a constant (friction F-77): `line[len("content-length:"):]` and `line[len(PREFIX):len(line)]` are the same fixed width
as `line[15:]`, and trapped `R_TEXT_BOUNDARY` on a text whose character spans the cut while the lint said nothing. `len` of a text
literal or of a module constant is read as the number it is, alone, in a sum with a literal and as the base of the other bound
(`text[len(text) - len(SUFFIX):len(text)]`). A cut at exactly that width is quiet where control reaches it only after
`strings.starts_with(text, X)` held for the same text and the same literal or constant `X` (the true branch of an `if`, the false
branch of an `if not`, or the rest of the block after an `if not ...: return`), and a suffix cut under `strings.ends_with`; a test of
another text, a text written in between, an `if` that does not leave and any other flow guard nothing, and a test that covers the cut
but names another prefix is named in the finding's message. `docs/tooling/lint.md`, `experiments/audit-work-20261111/FR26.md`.

### Messages write an option type as `T?`, as the source does (lane FR26, 15 November 2026)

Not breaking: only diagnostic text changes. A refusal that printed an option as `Option[int]` now prints `int?`: the instance name of a
generic function or record (`expected int, found Box[int?]`, `put[int?, Row?]`, a list of options `Box[int?[]]`, an option of a
list `Box[int[]?]`), the type of a function that takes or returns one, the way out of `E_RECURSIVE_RECORD` ("a `T?` field"), and the
three messages of the `sentinel-int` lint (`return `int?` and test `is None``). The lane FR25 did the same for lists (`T[]`). The
module interface files keep `Option[T]`; a module's own type named `Option` and a name that merely ends in the word keep theirs. Five
golden lines changed (three in `lint_sentinel_test.zig`, two new tests). `src/typed.zig: messageTypeText`,
`experiments/audit-work-20261111/FR26.md`.

### The consuming-loop hint is withheld where a view of the element would be invalidated (lane FR26, 15 November 2026)

Not breaking: only a hint goes. `W_COPY_MOVE` said `for one in own values():` and `own one` for a copy of each element of a list, and
the edit it named was refused (`E_SLICE_ESCAPES`, rule V3, "this slice view was invalidated by a move") whenever a view of the
element, `const head = one[0:1]`, was read after the move. The hint is now withheld for a list a call returns, and for a named list,
where a view of the element (or of the list) exists, the test the repair already used (`needless_copy.viewedAnywhere`); the program
checks as before and draws no hint there. A copy of an element nothing views keeps its hint or repair. The same test holds where
the view is not read after the move and the edit would have been accepted (a `return one` after `head` was last read): no hint
there either, as there was never a repair. `experiments/audit-work-20261111/FR26.md`.

### A name bound to a slice of a `byte_buffer` is refused at the check (lane FR26, 15 November 2026)

Not breaking: every program this refuses stopped the build before (nothing that built is refused). `const piece = buf[1:3]`,
`x in buf[1:3]` and `mut m = buf[0:1]; len(m)` on a `byte_buffer` passed `mylang check` and then stopped the build with
`E_CORE_UNSUPPORTED` ("a view binding without a slice initializer", "length of a non-string"), the open item of lane FR25. A
buffer has no borrowed slice (it can grow under one, and nothing tracks that), so its slice is a copy of the range that a read in
place uses once. `x in buf[1:3]` is such a read and now builds. A name bound to the slice (`const` or `mut`, in a loop, through a
field or a call's result) is refused by the check with the new `E_BUFFER_SLICE_NAME` and a message that says to write `bytes(buf[1:3])`, an
owned immutable copy. The neighbouring `mut other = copy(buf[1:3])` followed by `append(mut other, ...)` still stops the build
with `internal error[E_CORE_INVALID_IR]` (on main as well; a copy of a buffer's slice is typed as a buffer and lowered as `bytes`);
it is open. `docs/bytes.md`, `experiments/audit-work-20261111/FR26.md`.

### A call statement followed by `else` says what to write (lane FR26, 15 November 2026)

Not breaking: only a refusal's text changes, and it gains a repair. `check(-1) else Err(reason):` (friction F-76; `check` is a
function that fails and gives nothing back) was refused with "unexpected token; expected a newline", which named neither `else`
nor what to write. `else` unwraps the value a declaration or `_ =` takes, and a statement that is only a call has none, so the
message says that and names the three forms: `if check(-1) is Err(reason):` for a call that gives nothing back (the shape
`W_MATCH_IS` prefers), `_ = check(-1) else Err(reason):` to drop the value and `const NAME = check(-1) else Err(reason):` to keep
it. `mylang fix` rewrites the statement to the `if` form when the pattern is `Err(name)`, `Err(_)` or `None` (two edits: `if ` in
front, `is` for `else`); a bare `else:` names no case, so its message gives `is Err(e)` and `is None` and no repair is made. The
bare statement form is not added. `test/fixtures/fix-migration/else-statement.my`, `experiments/audit-work-20261111/FR26.md`.

### A cached check reports the W13 warnings the file earns now (lane FX13, 15 November 2026)

Not breaking: nothing is refused that was accepted, and what `check` prints is what `--no-cache` prints. A cached check could keep
a `W_METHOD_FORM` warning after a file waiver was added, hide one after a waiver was removed, withhold a rewrite after the
parameter that hid its module was renamed, keep a rewrite that no longer adds the import it needs, and keep or withhold a
duplicate's rewrite after the file declared the prelude name or stopped declaring it: those decisions read the whole file, and the
check summaries and the checked-body store keyed the function by its own region. A function with a W13 site now stands in only
while its whole file is as it was, and the checked-body store keeps no body with a waived one. The check summaries' format is
`check-summaries-v28`: the first check after the upgrade checks every body once. `docs/tooling/caches.md`,
`experiments/audit-work-20261111/FX13.md`.

### The commit file's helper stays out of the installation (lane FR25, 15 November 2026)

Not breaking: `mylang.commit` says what it said. The install step's script kept a 1.4 MB private copy of git's index and a stamp
beside the compiler (`bin/mylang.commit.index`, `bin/mylang.commit.index.stamp`, lanes FR22 and FR24); they belong to the build, so they
are in the tree's cache now (`.zig-cache/commit-file`, `build.zig` passes it as the script's second argument) and an installation
holds `mylang.commit` alone; the script removes the two files an earlier install left there. About 13 ms a run in a worktree with
changes and 18 ms in a fresh one (20 runs each, a first run of 24 ms makes the copy), as before. `docs/tooling/native-build.md`,
`experiments/audit-work-20261111/FR25.md`.

### `mylang fix` takes the list a call returns and moves each element out of it (lane FR25, 15 November 2026)

Not breaking: a hint becomes a repair; nothing is refused that was accepted. The `W_COPY_MOVE` hint over `for one in values(): ...
return copy(one)` (friction F-75) named the right edit and `mylang fix` made none. The edit is certain when the list is the result
of a call that is not lent by an argument (the checker's own test for `for x in own CALL():`), the loop reads it directly (no
`enumerate`, `zip`, `reversed`), the copy of the whole element stands in a store, a `return` or a `fail`, nothing reads the element
after it, no view of it exists, and no loop around the copy runs it twice; a condition that reads the element does not hold it. It is
now one `W_NEEDLESS_COPY` repair of two edits, `own ` in the loop's header and the copy replaced (`own one` in a store, `one` at a
`return` or `fail`), as for a named list. A copy of a field, the second of two copies in one iteration, a loop around the copy and a
live view keep the `W_COPY_MOVE` hint or draw none, as before. `test/fixtures/fix-migration/fresh-loop-moves.my`,
`experiments/audit-work-20261111/FR25.md`.

### Messages write a list type as the source does, `int[]` (lane FR25, 15 November 2026)

Not breaking: only diagnostic text changes. A refusal that printed a list as `list[int]` now prints `int[]`: a function type
(`expected func(int[]) -> int, found func(own int[]) -> int`), the instance name of a generic function or record
(`Box[int[]]`), the signatures of the arity refusals of `sum`, `reversed`, `any`, `all` and `lists.stride`, and the way out
of `E_RECURSIVE_RECORD` ("or a `T[]`"). The module interface files keep their spelling. `experiments/audit-work-20261111/FR25.md`.

### The `{{` hint inside a generic function (lane FR25, 15 November 2026)

Not breaking: only a diagnostic gains a sentence. A name the program lacks in a hole that reads as the literal's own braces
(`f"body { margin: 0 }"`, `f"a { color }"`) says a literal brace is written `{{` in a generic function body too; the generic-body
checker reported the unknown name on its own path without it. Both checkers ask `format_strings.unknownNameAdvice`. An unknown name
in an ordinary hole keeps its message. `experiments/audit-work-20261111/FR25.md`.

### Accepted: a text slice of a field of a newly made record (lane FR25, 15 November 2026)

Not breaking: nothing accepted before is refused. `len(Name(text=own t).text[0:2])`, `print(out, Name(...).text[1:4])` and a
call's field slice read within the statement now check, as the plain field read did since lane FR24: the record is kept in a hidden
owner until the statement ends and destroyed there with its other fields. A slice that is bound, stored in a list or a `mut` local,
or returned would outlive the temporary and stays refused (`E_SLICE_ESCAPES`); the message now also says to bind the record to a
local first. A list slice of such a field (`Bag(...).items[0:1]`) and `strings.char_slice` of it are not covered.
`experiments/audit-work-20261111/FR25.md`.

### Fixed: a slice of a `byte_buffer` and a whitespace split of borrowed `bytes` stopped the build (lane FR25, 15 November 2026)

Not breaking: programs that stopped with `internal error[E_CORE_HIDDEN_COPY]` now run. `print(out, buf[0:1])`, a format hole, `len`,
a loop, an index, `find`, `hex`, `split`, `startswith` and `write` of a `byte_buffer` slice failed the build: a buffer has no
borrowed slice (it can grow under one), so the slice copies just its range, and that copy was not marked as the one the slice
expression names (the `W_NEEDLESS_COPY` advice on `print(out, copy(buf[0:1]))` pointed at the failing form). It is marked now.
`b.split()` and `bytes.words(b)` of a `bytes` parameter copied the whole borrowed receiver first (no span form) and failed the
same check; they read the borrowed octets in place now, as text does. `const piece = buf[1:3]` and `x in buf[1:3]` are still
refused by the build (`E_CORE_UNSUPPORTED`, a binding of a buffer's slice). `experiments/audit-work-20261111/FR25.md`.

### Fixed: a loop over a `match mut` binding refused the read of its loop variable (lane FR25, 15 November 2026)

Not breaking: programs that were refused now run, and nothing accepted before is refused. Inside an arm of `match mut`,
`for e in value:` over a dictionary binding (or over a list of text) was refused with `E_SINGLE_OWNER_OVERLAP` at the first read
of `e`, where the same loop over a plain `mut` local was accepted: the arm's hold on the matched owner counted a read of `e`, a
borrow of the binding's contents, as a read of the owner. Reading a borrow of the binding is reading the binding, so it is
accepted. The change that would free what `e` names is the refusal now: a write through the binding while a loop variable or
another named borrow of its contents is still used in the same statement or a later one of its block is refused at the write
("'s' is changed here while 'e', a borrow of its contents, is still used"); without that the build would stop with
`E_CORE_UNSUPPORTED` (Z3). A write after the loop, and a write in a loop that never reads the loop variable, are as before. `docs/match-expressions.md#mutable-element-matches`, `experiments/audit-work-20261111/FR25.md`.

### Coming: the method forms of text, bytes, buffers, lists and sets, and five second spellings, warn now and are refused in a later commit (lane W13-S2, 15 November 2026)

Not breaking yet: nothing is refused, and every program checks, builds and runs as before. A spelling W13 retires now
draws a warning from `check`, `lint` and `fix` (never from `build`, `run` or `test`) that carries the rewrite its refusal
will carry, so run `mylang fix` now and the later refusal finds nothing. `W_METHOD_FORM`: the methods with a function
home, `text.encode()` as `strings.encode(text)`, `", ".join(parts)` as `strings.join(parts, ", ")`, `text.count(n)`,
`text.split()`, `text.zfill(w)`, the bounded searches, `text.parse_int()`, every `bytes` and `byte_buffer` read
(`buf.find(x)` as `bytes.find(buf, x)`), `b.hex()` and `b.decode()`, a set's `clear`, `pop`, `remove` and `update`, and
(with a message and no edit) `xs.exchange(i, v)`. `W_DUPLICATE_SPELLING`: the bare `unwrap_or(x, d)` (the method `x.unwrap_or(d)` stays), `math.min`,
`max`, `sqrt`, `round`, `floor`, `ceil` and `trunc` (the prelude's stay; one difference: in the prelude's forms a result of
zero keeps its sign, so `round(-0.4)` is `-0.0` where `math.round(-0.4)` was `0.0`; the two compare equal and print
differently), `strings.to_int` and `to_float` (`parse_int`, `parse_float`), the 32 bare file
functions (`exists(fs, p)` as `fs.exists(p)`), and, with a message and no edit, `math.abs` and
the library's channels `run_process`, `process_control` and `stop_control`. `E_NUMERIC_PARSE` no longer writes
`text.parse_int()` where a declaration claims `parse_int`. `strings.starts_with_at` stays, with no warning: it is not a second
spelling (it answers False inside a multi-byte character, where `strings.starts_with(s, p, start=at)` traps). See
`docs/tooling/fix.md#spellings-that-are-retiring` and
`experiments/audit-work-20261111/W13-S2.md`.

### Tooling tests under load: leftover window, watch stall, state order, journal verdict (lane NIGHTLY2, 15 November 2026)

Not breaking: scripts only. The nightly's first run at its new hour failed three tooling tests at load 27 (`build_slot_test`'s
supervised trim, two `dev_loop_test.WatchLoop` tests) and skipped the flaky rerun for a helper that had already been killed. The
supervisor's two-second closeout window now counts only time in which no leftover is runnable or in disk wait (at most 60 s in
all); the watch loop's stall and wedge clocks count only looks at which every thread of the Maker's tree slept, one look at most
0.5 s; the daemon writes its state file before it answers a `wait`; `gate_summary.leftover_report` reads only the supervisor
lines after the build's last summary (a test's own quoted supervisor is not the action's leftover) and a real leftover's
`no flaky rerun` reason names the process and the test file that owns its directory; `service_worktree.py` relays the runner's
output and outlives its last line so `journalctl -u` shows the nightly's verdict, which now names the failed action and tests.
`docs/tooling/development-loop.md`, `experiments/audit-work-20261111/NIGHTLY2.md`.

### Fixed: a `match mut` binding given to an operation that makes a new value crashed the program (lane FX12, 15 November 2026)

Not breaking: programs that crashed now run. Inside an arm of `match mut`, a payload binding given to an operation that
reads it as its receiver and makes a new value (`copy(value)`, `value.strip("x")`, `value.split()`, `value.encode()`,
`value.zfill(n)`, `strings.upper(value)`, `data.decode()` of bytes, `3 in members` of a set) passed the check and ended
with SIGSEGV in every build mode, since `match mut` landed (C1, 23 October). The binding is a name for its place, and
those operations read it as if it held a value of its own; it now projects the payload from the held container, as
every other use does. The ownership validator now refuses an operation that reads an `undef` of a managed type (the
null owner), so a lowering that makes this mistake again stops the build with an internal error instead of running.
`f"{buf}"` with a `byte_buffer` in the hole, which stopped the build with `internal error[E_CORE_INVALID_IR]`, now gives
the text `print` shows (`b'ab\x01'`). See `experiments/audit-work-20261111/FX12.md`.

### The commit file no longer costs a fresh worktree 145 ms at every build (lane FR24, 14 November 2026)

Not breaking: `mylang.commit` says what it said (`commit HASH`, `tree clean` or `tree dirty`, `commit unknown`). The install step's
`scripts/write-commit-file.sh` asked `git --no-optional-locks status` at every build; that never refreshes the repository's index,
so in a tree whose index has stale stat data (a fresh worktree, a merge, any checkout until a plain `git status` runs) git read all
11,000 tracked files every time: 145 ms median, 20 runs, in a fresh worktree. It now asks a private copy of the index kept beside
the commit file (`mylang.commit.index`, replaced when the repository's index is), which it refreshes itself: 152 ms once, then 18 ms;
a tree with changes (the watch loop's usual state) skips the untracked-file walk, 19 to 14 ms. A tree with a fresh index is
unchanged (17.7 and 17.8 ms). The repository's own index and its lock are never touched, and a copy that cannot be made or read
falls back to the old questions. `docs/tooling/native-build.md`.

### A lone brace in a format string: the `{{` hint for two more shapes (lane FR24, 14 November 2026)

Not breaking: only the message of a program that was already refused changes, and no hole that checked is judged by it. Lane
FR21 made a lone `{` say "write `{{`"; `f"body { margin: 0 }"` (an unknown name `margin`, `E_UNKNOWN_NAME`), `f"p { color: red }"`
(`Invalid format specifier`) and JSON such as `f'{"a": 1}'` (`Sign not allowed in string format specifier`) kept messages that did
not mention it. The same sentence now follows them when the hole's text starts or ends with white space, a quoted text stands
before its colon, or a space follows the colon (`format_strings.holeLooksLikeText`); an unknown name in an ordinary hole
(`f"{colr}"`) and a refused specification of one (`f"{x:>8q}"`) are untouched. `docs/text.md#format-strings`.

### A token after a multi-line text's closing quotes continues its line (lane FR24, 14 November 2026)

Not breaking: nothing that checked reads differently. `x = """a\nb""" + y`, `return f"""..\n.."""  + footer`, `if """a\nb""" == y:`,
`"""a\nb""".upper()` and a comment after the closing quotes were refused with `E_INDENTATION` at the *next* line ("unexpected
indentation or dedent does not match an enclosing block"), because the layout pass (`src/python_layout.zig`) took the token after the
quotes for the first of a line of its own, at the indentation of the line the quotes close on. It now takes the line a token ENDS on
as the line it is on, so the next token on that line continues the statement; a text that stands inside brackets, or ends its
statement, was never affected, and neither is one whose closing line has the block's own indentation (those were accepted, with the
same tokens). The Selka copy of the layout pass (`selfhost/frontend/lexer.my`) changes the same way. See `docs/text.md#triple-quoted-text`
and `experiments/audit-work-20261111/F19.md`, "Open".

### Two type names read as the source writes them (lane FR24, 14 November 2026)

Not breaking for any program's logic, but one change of printed output.

- **A generic record prints its name as the source writes it.** `print`, `str`, `repr` and a format string's hole show
  `Pair[int, str](left=1, right='x')`, `Holder[int[]](value=[1, 2])` and `Choice[int].nothing` where they showed the checked
  names `Pair<i64,str>(...)`, `Holder<List<i64>>(...)` and `Choice<i64>.nothing`. The change reaches only a record or enum
  with type arguments; every other name prints as before. In the repository one test pinned the old text
  (`tests/lang/generic_record_names.my`, three assertions, now the new text); none of the three projects, the site or any guide
  printed one. A program that compares such a text, or a file it wrote, must be rewritten by hand: `mylang fix` cannot find it.
- **A list or option of functions is named `(func(int) -> int)[]` in a refusal,** where it read `func(int) -> int[]`, a function
  returning a list. The source has no spelling for such a list (the parentheses are for reading): it exists only as the type of
  `[f]` or of a generic instance. `print` of one is `E_IO_ARGUMENT`.

### A read through a field of a record constructor is accepted (lane FR24, 14 November 2026)

Not breaking: nothing that checked is refused or changes. `return len(Name(text=own t).text)`, the same in a `const`, in a sum, in a
condition or a `match` scrutinee, `len(Bag(items=[...]).items)`, a nested field and a `copy(...)` of one were refused with
`E_SINGLE_OWNER_BORROW` (`... is lent by a temporary value, and the returned value would keep it`), although `len` keeps nothing
and the same read through a call's result (`len(make(own t).text)`) was accepted. A record constructor is now rooted in a hidden
owner for the statement, as a call's result is (`freshFieldReceiver` in `src/collection_lower.zig`), so the record and its other
fields are destroyed once when the statement ends. Binding the field (`const items = Bag(...).items`) still keeps the temporary
and stays refused, with the `copy(...)` that keeps both; so does a text slice of it (`Name(...).text[0:2]`). Found by lane F71.
`docs/value-semantics.md`.

### `unwrap_or` on a `@linear` payload is refused with the way out, not an internal error (lane FR24, 14 November 2026)

Not breaking: that program was never accepted. `maybe().unwrap_or(d)` over an option whose payload is `@linear` (or a record
that holds one) ended with `E_INTERNAL_BORROW_SELECTION: compiler bug: invalid borrowed selection type contract`. It is now
`E_LINEAR_USE` at the call, saying that the default is made before the option is looked at and is dropped unconsumed when the
payload is there, and to take the payload with `match own value:` and make the default in the `None` arm. The call is refused
rather than accepted because no reading is sound: on `Some` the default is an owner that nothing consumes, and
`options.take_or` is generic, which a `@linear` type may not instantiate. A local option, the prelude spelling
`unwrap_or(R, d)` and a holder record around the owner are refused the same way. `docs/records-and-unions.md#linear-records`.

### Breaking: `strings.count` of the empty needle, `strings.words` on a vertical tab or form feed, and a buffer's `split` (lane W13-S1, 14 November 2026)

Three behaviours change; nothing is refused. `strings.count(text, "")` answered `0` and now answers `len(text) + 1`, the
boundaries between octets, as `text.count("")` and Python's `count` do (W13-Q4: in the repository, the three projects and
the site one call had a literal empty needle, the library's own fixture, which pinned the old answer; three more pass a
name, each guarded by `len(t) > 0`). `strings.words(text)` split at space, tab, line feed and carriage return; it is now
the native split of `text.split()` and also splits at vertical tab (`\x0b`) and form feed (`\x0c`): `"a\x0bb c"` gives
three words where it gave two. Nothing in the repository or the three projects splits such text with `strings.words`.
**Where the parts of a text decide access, name the separators yourself:** the user's site split a token's scopes
with `strings.words`, so after this change a scope `x\x0broadmap` would have held the entry `roadmap`; it now splits
at the gaps it means (found when the site moved to this compiler, 15 November). And `buf.split(sep)` on a `byte_buffer`, which every check accepted, now builds and runs (it stopped
every build with `internal error[E_CORE_INVALID_IR]`). `mylang fix` has nothing to rewrite. See
`experiments/audit-work-20261111/W13-S1.md`.

### Function homes for every method text, bytes, a byte buffer and a set still answer (lane W13-S1, 14 November 2026)

Not breaking: 29 new library functions, each the operation of a method that stays accepted, so the next slice can
rewrite the method with no change to what runs. `strings.strip_chars`, `lstrip_chars`, `rstrip_chars` and `zfill`;
`bytes.words`, `strip_chars`, `lstrip_chars`, `rstrip_chars`, `index`, `rindex`, `parse_int`, `parse_float`,
`scalar_count`, `to_list` and `find_any`; `hashes.sha256_bytes`, `sha256_text_bytes`, `blake3_bytes` and
`blake3_text_bytes` (the raw 32 octets); `sets.clear`, `pop`, `remove` and `update`. `strings.count`, `text_index`,
`text_rindex`, `find`, `rfind`, `starts_with`, `ends_with` and the `bytes` searches take optional `start` and `end`
bounds (the ranged methods' `text.find(x, start, end)`). `strings.words`, `strings.join`, `strings.encode`,
`strings.decode` and `hex.encode` are now the native operations, `words` about 20 and `join` about 1.6 times as fast as
their library loops were. Every `bytes` read also takes a `byte_buffer`, which lends its octets with no copy.
`sets.update` takes another set or a list of the element type and refuses a text (the method keeps adding its letters).
See `docs/standard-library.md` and `experiments/audit-work-20261111/W13-S1.md`.

### `mylang fix` checks a directory that is one project once a round (lane FR23, 14 November 2026)

Not breaking: the same edits, faster. A directory run checked every `.my` file as its own entry each round, and each entry's
check checked every module it imports again; on the port (523 files) a round took 7 to over 45 minutes at three processes,
and the migration of 14 November ran for about an hour at the machine's full width. When every entry is a module of the
project `mylang check DIR` loads and no source holds a docstring example, a round is now one `mylang check DIR`: the port's
migration takes 3.7 minutes at `MYLANG_JOBS=3` and the site's `src` 14 seconds instead of 125. The trees are byte for
byte those of the entry-by-entry run on the fix-migration corpora, the port, the site, selka-protobuf and selka-sqlite.
A run through errors can take more rounds to the same tree, and the final report is the project check's (each diagnostic
once, `W_COPY_MOVE` judged against every caller, one unmodified-modules line). `fix --report` counts the checks; the default
width of an entry-by-entry round allows 2 GiB per check. See `docs/tooling/fix.md` and
`experiments/audit-work-20261111/FR23.md`.

### The nightly integration check judges its own builds and runs the two-run test step (lane NIGHTLY, 14 November 2026)

Nothing the compiler accepts, builds or caches changes; only what `verify_cache.py --integration` (the nightly service) does.

- **Its own stores.** The request builds against empty compiler and test stores of its own and fails with status 5 only when
  those log a mismatch. The per-user `mismatches.log` files are reported as counts (now, during the request, since the last
  request), never as a failure: they record disagreements between builds of different compilers and worktrees (lane FX11), so
  the old check failed every night from the first line written.
- **The two-run test step.** `zig build test-lang-rerun` (lane FX10) runs after the forced fact/leak run, once a day, as the
  user decided on 14 November; it stays out of the per-landing gate.
- **A status per step:** 5 a mismatch of its own stores, the complete request's own status, 7 the forced fact/leak run, 8 the
  two-run step. `scripts/nightly-integration.sh` prints one line naming the step and the reason, which is what the service's
  journal shows. `docs/tooling/development-loop.md#integration-gate`.

### `mylang --version` (lane FR22, 14 November 2026)

Not breaking: `--version` and `version` printed the usage text; they now print one line and exit 0:
`mylang commit 11419ef271ab, identity 9f2c4e1a7b30, debug, zig 0.17.0-dev.1683+5ceec001b, x86_64-linux`. The identity is the one
that keys every cached result and does not move for a commit that changes nothing it digests. The commit is read from
`mylang.commit`, which the install step writes beside the executable (`+dirty` when the tree had changes, `commit unknown`
without the file); it is outside the compiler, since a hash inside it would change the identity at every commit and empty
every cache (`D-FR22-4`). See `docs/tooling/native-build.md#which-compiler-this-is---version` and
`experiments/audit-work-20261111/FR22.md`.

### The lint names only locals the program wrote (lane FR22, 14 November 2026)

Not breaking: lint reports fewer findings and never more. Every `for x in own CALL():` drew `L_NAMING: local consumed list
does not follow the naming convention`, and so did every element moved out of a call's list and every `unwrap_or` on a
call's option with an owned default (`temporary list`, `temporary option`, `temporary default`, `temporary payload`,
`temporary result`): those are the compiler's own hidden owners, not variables of the program (7 findings in the site, 13
after its F-16 edits). `L_NAMING` and `L_DEAD_WRITE` now read a local only when its name is one the program could have
written (`typed.Local.written`); a `match` scrutinee, a bind-or-else and a `try` name nothing and never did. See
`docs/tooling/lint.md` and `experiments/audit-work-20261111/FR22.md`.

### `mylang fix` leaves a generated file alone (lane FR22, 14 November 2026)

Not breaking: a project with no file that begins `# generated by` sees no change. A file whose first line is a `#` comment
starting `generated by`, in any letter case (the marker `mylang lint` and the change review already honour), is no longer
rewritten by `mylang fix`: a fix with an edit in it is set aside whole, and the summary says how many it left and in how
many generated files (`fix: left 3 fixes in 3 generated files alone (...)`). The file named on the command line is still
repaired. The site's generator checks bytes, so it no longer needs its three modules reverted by hand after a `fix`. The
decision (marker, not a `mylang.json` list) is `D-FR22-2` in `experiments/audit-work-20261111/FR22.md`; the details are in
`docs/tooling/fix.md#generated-files`.

### A text cut at a width: `strings.cut_octets`, a lint finding and a trap message that name the helpers (lane FR22, F-74, 14 November 2026)

Not breaking: no program that checked before is refused or changes what it does. A slice of a `str` counts octets, so
`text[0:WIDTH - 1]`, `kind[0:1]` and `text[at:at + 1]` pass `check` and every test with ASCII texts and end the program at
the first text with a long character in that place (one sat in a live server for a day). Three additions:

- `strings.cut_octets(text, limit)` is the longest prefix of at most `limit` octets that ends where a character ends, a view of
  `text` like a slice (`copy(...)` makes it storage of its own). A limit inside a character backs off to where it starts; one
  below the first character's width or negative gives the empty text; one at or past the length gives the whole text.
- `mylang lint` reports (`L_TEXT_SLICE_OCTETS`, report only, never blocking) a slice of a `str` whose end or start is an
  integer literal, a module constant, an expression over those, or the other bound plus or minus a literal. A found offset
  (`strings.find`, a position a loop reads), `len(...)`, a start of 0, a literal start after `starts_with` of an ASCII prefix at
  least as long (`url[7:]`), a text written in place (a literal, or a `const` bound to an ASCII literal), a slice of `bytes` and
  of a list draw none. The message names `strings.cut_octets`,
  `strings.char_slice` and `strings.starts_with_at`. See `docs/tooling/lint.md#a-text-cut-at-a-count-of-octets`.
- `R_TEXT_BOUNDARY` names the same three helpers in its message.

### Breaking: `print` refuses a value that holds a function or a capability (lane FR21, PRINT-1, 14 November 2026)

The user's decision of 14 November: `print`, `str`, `repr` and a format string's hole follow one rule, so a value that holds a
function value, a capability, an open file or an owned resource is refused when it is checked, wherever it holds it. Before,
`print(out, [f])` of a list of functions checked and wrote a memory address (different from run to run), and `print(out, [stream])`
or a record with a `Stream` field checked and then failed to build with `E_CORE_UNSUPPORTED`. Now `E_IO_ARGUMENT` (a hole:
`E_TEXT_CONVERSION`) at the argument: "`print` of `Stream[]` is refused: it holds a `Stream`, which has no text; capabilities, open
files, owned resources and callbacks cannot be shown, so write a name or a count that describes them". `docs/io.md#print`.

- **What it refuses, counted before it was built:** nothing in the repository's guest code (1,734 files of `tests`, `test`, `src`,
  `examples`, `bench`, `benchmarks`, `selfhost` and `velocity` checked one by one) or its 959 fenced examples, nothing in
  the three projects (`netlisp-selka-redo` `check src`, `selka-protobuf`, `selka-sqlite`) and nothing in the site's clone
  (`src`, `tests`, `viewgen`, `tools`). A program that printed such a value did not build or printed an address.
- **No `mylang fix` repair:** the edit is not certain. The program meant to print something; the compiler cannot know whether that
  is a name, a count or a loop over the parts (`fix` would have to invent the program), so the refusal names the part and
  says what to write, and there is nothing to migrate.

### Six small fixes in what the checker accepts and says (lane FR21, 14 November 2026)

- **The message of an `assert` is any `str` expression** (F-72). `assert allowed in kept, "kept: " + allowed` was refused at
  the `+` with `E_SYNTAX`; it checks and runs now (the text is built only when the condition fails). A message of another
  type is `E_TYPE` and names the `assert`, and a second comma after the message is `E_SYNTAX` with the sentence "join the texts
  with `+` or write a format string". No program that checked before changes. `docs/statements.md#assert-statements`.
- **An import cycle says what to do** (F-73; the rule stays, two modules may not import each other). `E_IMPORT_CYCLE` was
  `a -> b -> a` and a note. It now names, for each import of the cycle, what the importing module uses from the next
  (`` `a` uses `b.slot`; `b` uses `a.head` ``: at most three names per import, then "and N more") and the way out in one
  sentence: move what they share into a module they all import; an import nothing reads is named, and removing it breaks the
  cycle; a module that imports itself is told to remove the import. Found only when a cycle is, so a program without one pays
  nothing. `docs/modules.md#limits`.
- **`str()` and `repr()` take a record, a result and a fixed array** (F-38b, the user's decision of 14 November). Since lane
  F38 they worked inside a list (`str([p])` is `[Point(x=1, y=2)]`) and were refused alone; `str(p)` is now `Point(x=1, y=2)`,
  `str(parse("x"))` is `Ok(7)` and `str(FixedArray[int, 2]([1, 2]))` is `[1, 2]`: the text `print` writes, by the one renderer
  `print`, `str`, `repr` and a format string's hole share. A record that holds a capability or a function is still refused and
  the sentence names the part. An enum (`case_name(value)`), `bytes` (`repr(value)`) and an enum-indexed table (`f"{table}"`)
  keep their refusals. No program that checked before changes. `docs/text.md#the-text-of-a-collection`.
- **Two `W_COPY_MOVE` hints and one repair no longer advise an edit the checker refuses** (found by the site's compiler trial).
  At a `return` or a `fail` of a name the hint said `own reading`, which is `E_OWN_MARKER`; it now says `return reading` in place
  of `return copy(reading)` (`fail reading`, and `return own reading.figure` for a field, which does take the marker); the hint
  for a payload of `match own` says the same. For `for index, item in enumerate(items())` the hint named `for item in own
  items():`, which loses the index; and `mylang fix` rewrote `for index, item in enumerate(owned)` to `in own enumerate(owned)`,
  which is `E_ITERATION` (the same for `reversed(owned)` and `zip`). A loop over a wrapper of a list gets neither the hint nor the
  repair now. `mylang fix` has no edit for the hint at a `return` in a loop over a call's list: the repair of a loop over a named
  list proves more (that nothing else holds the element) than the hint does, and a fresh call's list stays a hint (F-16).
- **A lone `{` in a format string says a literal brace is written `{{`** (one-line and triple-quoted forms). `f"p { color:
  {color}; }"` was refused with "a nested `{...}` inside a format specification is not supported", true of what the lexer read
  and no help to someone who wrote CSS or JSON. That refusal, the refusal of a hole that is not one expression
  (`f"a {x y}"`), an unterminated hole or specification, and a specification that reads as text (a word after a word, a
  `;`: `f"p { color: red; }"` was only "Invalid format specifier") now add "A literal brace in a format string is written `{{`
  and `}}`: if `{ color:` was meant as text, write `{{ color:`", the hole's opening cut at 24 bytes. A specification that is
  one (`{x:.2d}`) keeps its own message with no advice. No program that checked before changes.
  `docs/text.md#format-strings`.

### `unwrap_or` on a call's option gives an owned value (lane F71, 14 November 2026)

Not breaking: it only accepts more programs. `const text = maybe().unwrap_or("")` followed by `Name(text=own text)` checks
and runs: when the option is the result of a call that lends nothing and the default is a value of its own (a literal, a
new value, `own name`), `unwrap_or` in a position that takes a value moves the payload or the default out, as
`options.take_or` does. A read elsewhere, a `mut` binding, an option that is a local, a parameter, a field or a lent call,
and a default that is a place keep the borrow; a refusal over a local option the function owns now names
`options.take_or(own o, d)`. A `fail` takes an element of a new list (F-55) the way a `return` does. The details:
`docs/ownership-rules.md#r6--borrowed-selections` and `experiments/audit-work-20261111/F71.md`.

### A format string may be triple-quoted (lane F19, 14 November 2026)

`f"""..."""` and `f'''...'''` are accepted (F-19, the user's decision of 14 November); they were refused with `E_FORMAT_STRING`
("a format string cannot be triple-quoted"), so no program that checked before changes, and no `mylang fix` migration is
needed. The rule is `D-F19-1` in `experiments/audit-work-20261111/F19.md` and `docs/text.md#triple-quoted-format-strings`:

- **The text** is the plain triple-quoted text of the same source (`docs/text.md#triple-quoted-text`), piece by piece: nothing
  stripped or dedented, every line end, tab, blank line and quote of either kind kept, a backslash at a line's end `E_BYTE_ESCAPE`.
- **A hole** is what it is in the one-line form, and **closes on the line it opens** (its specification too): a line end inside
  one is `E_FORMAT_STRING` at its `{`. A name, a call or a trap in a hole on a later line is reported at its own line and column.
- **The literal ends** at the first three unescaped quotes of its kind, wherever its holes are, as the plain form does; a hole
  cannot hold three of the literal's own quote. An unterminated one is `E_BYTE_LITERAL` and names the line it opened on.
- A plain triple-quoted string, a one-line format string and `b"""` read as before. The Selka lexer (`selfhost/frontend`) lexes
  the new form the same way; the lexer parity corpus has it. A bad escape in a piece of any format string is now reported at its
  own backslash rather than at the start of the piece.

### A program can hear that it is being stopped: the `Stop` capability (lane FR5b, 14 November 2026)

Not breaking: no program that checked before is refused, and one that does not declare a `Stop` builds to the same code
and dies of SIGTERM as before. A `main` that declares `stop: Stop` hears SIGTERM and SIGINT as
`process.stop_requested(stop)` turning true; the next `network.wait` of each poller and the next `time.sleep` on the real
clock end early, other waits resume, and a second signal ends the program by the default action. It needs no grant, is a
handle like `Stream`, is refused as a task argument (`E_TASK_CAPABILITY`), and a test gets a stand-in
(`process.simulated_stop()`, `process.request_stop(stop)`). `mylang run` now passes a signal on as a marked copy, so a signal
sent to a whole process group is one stop to the program, not two. `Stop` is a reserved type name the way `Process` is (a
program's own `Stop` type still wins), and `stop_control` is a reserved builtin name the way `process_control` is. The
details: `docs/io.md#hearing-a-stop` and `experiments/audit-work-20261111/FR5B.md`.

### Two warnings flatten a `match` that only unwraps, `try` is not offered over a borrowed place, and the lint counts a bind as the source reads it (lane FR20, 14 November 2026)

No program is refused or accepted differently by `check`, `build` or `test`. With `--warnings`, `mylang lint` or `mylang fix`:

- **`W_MATCH_ELSE`**: a two-arm `match` over an Option or a Result whose `None` or `Err` arm leaves is rewritten by `mylang fix`
  to `const x = value else:` (`else Err(e):`, `else Err(_):`) over that arm's block, followed by the other arm's statements.
  **`W_MATCH_IS`**: one whose other arm does nothing becomes `if value is Some(x):` (`is None`, `is Ok(x)`, `is Err(e)`). Each
  is offered only where the result is the same program (the rules are in `experiments/audit-work-20261111/FR20.md`); a nest
  settles one level per round. The lint rules are `match-else` and `match-is`, report only.
- **`W_ELSE_IS_TRY` is offered only over a call.** Over a borrowed place (`const h = x else: return None`, `x` a parameter),
  `try x` is refused and `mylang fix` used to go on to write `try copy(x)`, a copy the program did not make.
- **Idiom warnings are not reported in the standard library** a program compiles with: `mylang fix` cannot edit it.
- **`L_NESTING_DEPTH` counts a bind-or-else as one level for its `else` block and none for what follows**, as `try` adds
  none (F-70); `elif x is P(y):` and `while x is P(y):` count as the statement they are. A function of six binds in a row
  measured 6 and measures 1, so a function may now pass under `--gate` that was reported before; none is newly reported.

### `mylang native approve`: a machine approves its own system libraries (lane NP1, 14 November 2026)

This changes no program and no output of a build. Native build reuse used to require the six system files built programs
load to have the checksums written in `src/config_core_tool_platform.zig`; every glibc update (16 October, 4 November,
14 November) turned reuse off on every compiler until the source list was edited and the compiler rebuilt, and on any other
machine reuse never worked. Now `mylang native approve` checks the machine's files (the package manager, then the
loader-traced probes that the hand qualification ran, now inside the compiler) and records an approval in
`~/.config/mylang/native-approvals`, which every compiler reads. A build whose libraries match neither the list nor an
approval says so once a day and names the command; it still reuses nothing, as before. No cache key or format changes.
See `docs/tooling/native-build.md#approved-system-libraries`.

### A server's addresses at run time; `acquire_resource` on a Network is the standard library's own (lane FR5a, 14 November 2026)

**Breaking: `acquire_resource[...]` with a Network receiver is refused outside the standard library** (`E_INTERNAL_NAME`).
Its requests are the `network` module's internal encoding, and a request built at run time reached any address the launch
grants past the rule that `net.host` takes a literal. Use `network.connect`, `connect_within`, `listen`, `open_poller` or
`dial` on a `net.host("IP:PORT")` narrowing, or the new operations below. `mylang fix` rewrites the one certain shape, the
library's own `Connected`, `Listening` or `Polling` acquired with the one octet `0`, `1` or `2`, to `network.connect`,
`network.listen` or `network.open_poller`, which send the same request; any other use (a result type of the program's own,
a request in a name or carrying an address) is moved by hand. The repository had three such uses and the three ported
projects and the site none. `acquire_resource` on a Filesystem is unchanged. `read_resource`, `write_resource`,
`accept_resource` and `complete_resource` are unchanged.

- **New:** `network.connect_to(net, address)`, `connect_within_to(net, address, limits)`, `listen_at(net, address)`,
  `open_poller_at(net, address)`, `dial_to(mut poller, net, address, mut outcome)` and `dial_within_to`. Each is its literal
  sibling with the address as a `str` the program has at run time, checked when it runs against `--allow-endpoint` and
  `--allow-listen` verbatim under `--restrict` (every address without it). `net.host` still takes only a literal.
- **Changed:** a narrowed Network refuses any address but its own (`err(2)`); and an address, in a grant or a program, whose
  port has a sign, a space or anything after its digits is malformed (a grant stops the launch; an operation fails with 3),
  where `127.0.0.1:80 ` used to be read as port 80.
- The details, the address grammar and the decisions: `docs/standard-library.md#addresses-given-at-run-time` and
  `experiments/audit-work-20261111/FR5A.md`.

### `str()` and `repr()` take a list, a set, a dictionary or an option (lane F38, 14 November 2026)

This only accepts more programs: no program that checked before is refused, and `print` writes the same bytes. `str(order)` of
`[3, 1, 2]` was `E_TEXT_CONVERSION` and `repr(order)` `E_REPR_TYPE`, so every program that reports a list wrote a four-line
helper that collected the text of each element and joined it (friction entry F-38).

- **The rule (D-F38-1, `docs/text.md#the-text-of-a-collection`).** `str(x)` and `repr(x)` take a list, a set, a dictionary or an
  option whose parts all have a text, and answer the text `print(out, x)` writes for it, without the line end: `[3, 1, 2]`,
  `['a', "it's"]`, `{'b': 2, 'a': 1}`, `{5, 1, 3}`, `set()`, `{}`, `Some(3)`, `None`, `[Point(x=1, y=2)]`. A text element is
  quoted as `repr` quotes it, so `repr` of a collection is its `str`. A set and a dictionary show in insertion order, the
  same in every build mode and every run; equal sets built in different orders show different text.
- **One renderer.** `print`, `str`, `repr` and a format string's hole lower through `FnBuilder.textOf` and the C renderer
  `myl_core_values_render`; the checker now types `str(collection)` and `repr(collection)` as the `cast` it already made for
  a scalar, so the four cannot drift. `tests/lang/text_of_collections.my` compares each against a line `print` wrote to a
  capturing stream. `repr(set)` no longer reads the set as its list of keys (`sema_builtins.zig`, as `copy` already did), and
  Core's `case_name` lowering no longer takes an option's `str` for an enum case name (`src/core/build.zig: enumCast`).
- **What stays refused, with sentences that are true.** `str` and `repr` of a record, an enum, a tagged enum, a result, a fixed
  array or `bytes` by itself (`E_TEXT_CONVERSION`, `E_REPR_TYPE`: the message names the type and says `f"{value}"` writes it as
  `print` does; for an enum `case_name(value)` is its case name, for `bytes` `repr(value)` is its `b'...'` spelling). A
  collection with a part that has no text (a capability, an open file, an owned resource, a callback) is refused naming the part:
  ``` `str` of `Stream[]` is refused: it holds a `Stream`, which has no text ```. A generic body accepts `str(items)` of a
  `T[]`, and each instance refuses a `Stream`. FR2's sentences about collecting each element and `strings.join` are gone from
  the messages; `strings.join` stays for text with a separator of the program's choice.
- **Found, not changed.** `print(out, [out])` (a list of `Stream`) and `print(out, [holder])` check and then fail in Core with
  `E_CORE_UNSUPPORTED`, and `print(out, [twice])` (a list of function values) prints a memory address; `str` refuses all three
  at the checker instead (`experiments/audit-work-20261111/F38.md`).
- Tests: `src/collection_text_test.zig`, `tests/lang/text_of_collections.my`; the old FR2 test for the join advice moved there.
  Nothing to migrate: `mylang fix` has no edit to make.

### Messages say `int`, the removed `.contains` has a sentence and a repair for each receiver, and a killed compiler ends its children (lane FR19, 14 November 2026)

No program is refused or accepted differently by `check`, `build` or `test`. Look here when a script reads a message, an exit
status or the processes of a killed build:

- **A message names `int` where the source says `int`**, not the checker's tag `i64`: `case Ok:` ("carries int"), a bare `else:`,
  a literal arm and an incomplete match on an integer, a generic parameter inferred as two types, the concrete types in a generic
  body, the record in an ownership note (`R[int]`, not `R<i64>`), a missing field of a generic record, and the function in a hint
  (`put[int]`). A program's own printed values keep their text.
- **`seen.contains(name)` is worded for its receiver** (still `E_REMOVED_SPELLING`): a set, a dictionary, text, bytes and a list
  each get a sentence that is true of that type, in a concrete body, a generic body and on a text constant. `mylang fix` writes
  `name in seen` (`lists.contains(values, name)` and its `import` for a list) where the receiver is a name or fields of one and the
  argument names no `mut` or `own` place; elsewhere the message names the spelling and there is no edit.
- **The `http` codec's refusals are the most exact ones**: a status code of two, four or more digits "must be exactly three
  digits" (it said "outside 100..999"), a blank where the code goes and a status line that starts with a space have their own
  sentences, and a request line says it is empty, that its parts must be separated by a single space, or that it has no version.
  What is accepted is unchanged.
- **`mylang run` accepts `--allow-endpoint=*` and `--allow-listen=*`**, which a built program's `MYLANG_OPTIONS` already took
  (every endpoint, every listener); a pattern around the star (`127.0.0.1:*`) is still refused, and each star counts toward the eight.
- **A killed compiler takes its `zig cc` children with it**, and a killed `mylang doctest` its child compilers and their programs
  (`PR_SET_PDEATHSIG`, as the guest has had since FR16). The one `zig clang` that `zig cc` itself started finishes the file it was
  compiling.
- **A test file that imports a module named `main` runs** under `mylang test main_test.my`, in a directory run that cannot check its
  roots together and under `MYLANG_TEST_CHILDREN=1`: the runner's stub `main` no longer meets the file's `import main`
  (`E_IMPORT_ALIAS`, at a line the file does not have). A `main` the author wrote beside `import main` is still refused. The stub
  is now `# the test runner's entry point, appended to a test file that has none` above its `main`.
- **A test that returns `false` is told to write one `assert` for each fact**: the text report prints an `advice:` line after
  `expected true, got false`, and `--json` has an `advice` field beside `reason`, for a single file and for a directory run alike
  (a directory run's `--json` also carries the `contract`, `provider` and `source` of a test run against providers, which it dropped).
  A failed `assert` and a trap get none.
- **The guides say when a value is destroyed**: after its last real use, not at the end of its block, and `_ = own x` as a last
  line does not keep `x` open (a resource is closed above a `connect` written before the discard), with two examples of holding
  a listener open on purpose in `docs/standard-library.md`. No code changed.
- **`mylang rename` says what happened when a repair shows an error the clash was hiding**: the rename is right, the function had
  an error no check could show, here is its message and place, run the same command again once it is fixed. It still writes nothing.

### The shared compiler store logs a mismatch only for two records that disagree on the same inputs (lane FX11, 14 November 2026)

Nothing accepted, refused, built or served changes. Only what `mismatches.log` of the per-user compiler store records, and the
`shared_mismatches` a build reports, change.

- The store logged every publication that found another result under a key: 229,322 lines over 12,427 keys by 14 November,
  so the nightly integration check failed every night and nobody read the file. Every class reproduced was noise: another
  variant of an engine query that won a race for a shared slot (two programs' `main.my`, published at once), another
  program's `ownership-proof` table (a record that reads nothing and that its writer replaces on purpose), and a project's
  check-summary table or semantic pack, replaced on purpose by remove-then-save, racing another writer. An engine record is
  now offered to the store without a log line and judged by the tier: another result is a logged mismatch only when both
  records read the same things and read something. The table and the pack are written with `Store.replace`. A gate-like
  load (the documentation examples, the goals register and the three language suites at once, three rounds) logged 28 lines
  before and none after.
- What each class was, how it was found and what is still open: `experiments/audit-work-20261111/FX11.md`.

### `mylang test` fails a run with a test it could not build; a test file's private access no longer depends on what a work directory holds (lane FX10, 14 November 2026)

**A run with an `unsupported` test now exits 1.** A test whose program the core cannot build was reported `unsupported` and
was neither a pass nor a failure, so such a run could exit 0. The core is the only back end, so that test did not run: the
run now fails as for a failed test, its summary line ends `, N unsupported (not built, so not run: the run fails)`, and
`--json` gains `"result"` (`passed`, `failed` or `nothing ran`, the rule of the exit status). No test of the repository's
suites, the three projects or the site is unsupported after this change, so no correct suite changes its exit status; a
script that read exit 0 as success over unsupported tests now sees 1.

**What was wrong.** A test file that calls a private function of the module it tests (`lib_test.my` calling `lib.page`)
passed on a first `mylang test DIR` and was reported `unsupported` (`E_CORE_UNSUPPORTED: LLVM emission failed:
UnsupportedInstruction`, a link error `undefined hidden symbol` on an optimised compiler) on any later run in the same work
directory that was not replayed: after an edit of a body in `lib.my`, on a second `--force`, or after a build of the program.
A test that should then have failed did not run. The check a directory run's roots share enters through a generated module
that imports each root, and that module counted as an importer of the test file; the test file's checked body, stored by its
own check, was then served into the shared check, which made the private function private to its unit. The generated module
is no longer an importer (as `mylang check DIR`'s never was), and a test file's checked bodies and engine records are keyed by
the module it tests. The same keys fix `mylang check`, which accepted from its stores a test file that calls a private function
or builds a sealed record of its module once another module imported the test file; a fresh check refuses that program with
`E_PRIVATE_SYMBOL` or `E_SEALED_RECORD`, and now so does every check. The first run after the upgrade checks such test files'
bodies once. `zig build test-lang-rerun` (not in the complete gate) runs each language suite twice in one work directory and
fails on a verdict that changes.

### `mylang check` prints the same `W_COPY_MOVE` hints from a work directory that holds earlier checks (lane FR14b, 14 November 2026)

Nothing accepted before is refused, and nothing refused before is accepted. Only which hints are printed changes.

- A check that stands unchanged bodies in from its summaries judges a `W_COPY_MOVE` hint against every caller, as a check
  of every body does: each caller's summary now stores whether it keeps what a callee's hint would take, and the check reads
  those answers for the callers it did not check. On the port, a check after an edit printed 479 hints where a cold check
  printed 378; both now print 370. The friction program of F-27 no longer gets the hint from a work directory that checked
  another program at the same path.
- The hint's function is found by its declaration, so eight loop hints of the port whose function the filter missed before
  (a caller needs the list) are now left out.
- The check summaries' format is `check-summaries-v27`: the first check after the upgrade checks every body once.

### Breaking: a task cannot take a capability (lane W28, 14 November 2026)

A task (`g.submit(fn, ARGS)`, `parallel.map(values, fn, ARGS)` and its other names) is refused a `Stream`, `Filesystem`,
`Network`, `Clock`, `Entropy`, `Environment`, `Process` or `Input`, or a record, list, dictionary, option or union that holds
one: `E_TASK_CAPABILITY`, which names the field that holds it (`Host` keeps `E_TASK_HOST`). Tasks that shared a capability
interleaved their output from run to run, and a service and its client in two tasks never finished. To migrate:

- Let the task return what it would print or write, and print or write it after the group or map; read before it.
- A service and its client in one program are one event loop that accepts and dials (`network.dial`).
- `mylang fix` deletes an argument the task function never reads (a `_` parameter of a private function used once).

### `mylang run` ends its program, standard output arrives before the runtime waits, and three messages are true (lane FR16, 14 November 2026)

No program is refused or accepted differently by `check`, `build` or `test`. Look here when a supervisor, a log reader or a script sees
different timing:

- **A stop that reaches `mylang run` alone now ends its program.** `run`, `run-project`, `build --run` and `packages build
  --command run-project` pass SIGTERM, SIGINT and SIGHUP on to the program, wait for it and end by the signal it died of; a program that
  exits keeps its status. A compiler killed outright takes the program with it (`PR_SET_PDEATHSIG`), as does `mylang test` its test
  programs. It used to leave the program running with no parent.
- **Standard output is flushed before the runtime waits for something outside the program**: the poller's `wait` (a timeout of 0 does
  not), a read of standard input, a connection or a file handle, `accept`, a blocking connect, `process.run` and `process.wait`, a
  real-clock `time.sleep` and a blocking lease. A service whose log is standard output shows each line while it waits and loses none
  to a signal that ends it there. What a program writes and its order on each stream are unchanged; only when it arrives.
- **Messages.** A literal over 64 KiB (`E_BYTE_LITERAL_LIMIT`) names constants joined with `+` and `embed_str`/`embed_bytes` instead of
  "input buffers"; a tuple that is the only diagnostic no longer says it waits for other diagnostics (`mylang fix` reads whether a
  repair is published, not the text); `docs/io.md` lists `--allow-endpoint` and `--allow-listen`, which `mylang doctest` runs through
  two new directives.

### One file, one edit; `case Ok:` named; the Selka lexer and an apostrophe; the next compiler death recorded (lane FR14, 14 November 2026)

Nothing accepted before is refused, and nothing refused before is accepted.

- `mylang fix DIR` edits a file a project reaches through a symbolic link and by its own path once, and names it by its
  real path; a diagnostic `fix` or `check DIR` reports for that file under two paths is printed once.
- `case Ok:` (and `case Some:`, a declared result's case, an enum case with named fields) without a pattern says what the
  case carries and names `case Ok(_):` and `case Ok(value):` (`case circle(..):` and `case circle(radius):`); `mylang fix`
  writes the discard when the payload needs no handling.
- The Selka port of the lexer names a quote inside a word that ended a text as the Zig lexer does (F-61).
- A Debug compiler that dies of a fault prints the processor it ran on and the bytes around the source and the destination
  of the faulting copy beside its other `crash-state:` lines.

### `mylang rename` repairs the name clash `E_SHADOWING` refuses, and the refusal names the command (lane FR18, 14 November 2026)

No program is refused or accepted differently: `E_SHADOWING` is reported where it was, with the same first line. Its
refusal of a local, a parameter or a pattern binding named like a function, constant or type of its module, or like an
imported module, gains a note with the `mylang rename` command that renames the binding, complete but for the new name;
when one check refuses several bindings that hide one name, the note names `hiding:NAME` with their count. `mylang rename`
now writes such a rename although the project does not check: the files are written when the diagnostics after are the
ones before less the refusals of the renamed bindings, and the uses are found by resolution over a copy in which the
bindings are renamed (`docs/tooling/rename.md#a-binding-that-hides-a-module-level-name`). The new target `hiding:NAME`
renames every binding of the project that hides `NAME`. A rename of a project that checks prints what it printed.
`mylang fix` still offers nothing here: the new name is the author's. Three small changes: `mylang cache where` refuses a
`mylang.json` the other commands refuse (a relative store) with the same `E_PROJECT_CONFIG` line, where it printed the
default stores; `mylang test DIR` no longer tells one of its entries that the sibling `_test.my` file the run also tests
is left out; and `docs/io.md` says that `statfs` and `stat` refuse `.` and `/` on a `memory()` filesystem (its root is
`""`), as they always did.

### The reviewed native runtime follows the glibc security update of 14 November (lane NP, 14 November 2026)

No program is refused and no program changes. The compiler's reviewed list of the six files its native runtime loads
(`src/config_core_tool_platform.zig`) now names the bytes of glibc 2.43-2ubuntu2.7, which `unattended-upgrade` installed at
06:42 UTC: new digests for the loader, libc, libm, libpthread and `/etc/ld.so.cache` (libgcc_s is unchanged), requalified by
the debug and release loader probes (`experiments/audit-work-20261111/NP.md`). A compiler built before this change refuses
its native closure on an upgraded machine and builds every guest without cache reuse; one built after reuses again. A
machine still on the earlier glibc sees the opposite until it upgrades. How a closure is reviewed is unchanged.

### The `http` codec reads strictly, writes a length for an empty answer and says how long a message was (lane FR13, 14 November 2026)

No program is refused by `check`. At run time a message that is well formed by RFC 9110 and RFC 9112 is read and written as
before, with **two changes to what correct programs see**, and a malformed message is refused where the codec used to guess
(from a security review of the library, the site's F-62 to F-66). Look here when an upgrade changes a request's verdict or the
bytes an answer is written as:

- **An answer with an empty body gains a field.** `http.write_response` writes `Content-Length: 0` for an empty body (a redirect, an
  empty 200) unless the status is 1xx, 204 or 304 or the caller's fields already carry a `Content-Length` or a
  `Transfer-Encoding`. It wrote none before, so a reader on a connection that stayed open could not tell where the answer
  ended. A program or test that compares the written bytes of such an answer sees the new line (`HTTP/1.1 302 Found`,
  `Location: /x`, `Content-Length: 0`, then the blank line). `http.write_response_head` still adds none for an empty body.
- **`*` and an authority form have no path.** `http.path` answers `""` for the target `*` and for `host:port` (it answered `/*` and
  `/host:port`); a target `/x` or `http://host/x` is as before.
- **Refused where it was read before.** `Content-Length` and the status code are digits only (`+4`, `0_4`, `-0`, `2_00`; at most
  18 digits for a length, exactly three for a status). A control octet other than a horizontal tab is refused at either end of a
  field value, in a reason phrase, a version and a chunk-size line, instead of being trimmed away (only a space and a tab are
  trimmed, and the Unicode spaces `strip` removed now stay in the value); a bare LF never ends a line. `parse_request` refuses a
  target that is not an origin form, an absolute form, `*` or `host:port`, and any with a `#`. A trailer that names
  `Content-Length` or `Transfer-Encoding` is refused, and so is a 1xx, 204 or 304 response that claims to be chunked.
- **The writers check more.** `write_request` takes a token method, a version of `HTTP/1.0` or `HTTP/1.1` and a target of one of the
  four forms; both writers refuse a `Transfer-Encoding` beside a body or a `Content-Length`, and `write_response` a body on a
  1xx, 204 or 304 answer. Each refusal is an `http.Error` with a text that names it.
- **New:** `http.parse_request_prefix(data, limits)` and `http.parse_response_prefix(data, closed)` answer `ParsedRequest` and
  `ParsedResponse` (the message and `length`, the octets it took), so a server that keeps a connection open parses the next
  message from `data[length:]`. A chunked body is gathered in linear time (20,000, 40,000 and 80,000 one-byte chunks took 26 to 75,
  162 to 234 and 611 to 1,026 ms, and 3 to 5, 5 to 6 and 11 to 12 ms now). See `docs/standard-library.md#strict-reading`.

### Five shapes the checker refused and now accepts (lane FR11, 14 November 2026)

Nothing accepted before is refused, and no accepted program changes what it does or emits.

- A `str` or `bytes` constant may join literals and other constants of its type with `+`, in either order of
  declaration and through an import (`const SELECTOR: str = "#" + NAME`); it is folded into one literal. A cycle is
  `E_CONSTANT_CYCLE` naming its constants (F-54).
- `for x in own rows():` takes the new list a call returns; a call whose result is declared `from` an argument stays
  refused and says so, and the `W_COPY_MOVE` hint names the direct form (F-16).
- `TEMP[i]` of a new list (a call's result that lends nothing, a list literal) moves the element out where a value is
  taken: a binding, an assignment, a `return`, a store, an `own` argument, a constructor's field, a list element and
  `Some`/`Ok`/`Err`; the bounds trap is unchanged. A new dictionary's `TEMP[key]` moves its value out the same way
  (F-55).
- A call may pass a record `mut` beside an argument that reads the record into a value of its own
  (`emit(mut work, "x" + target(work))`); an argument that lends a part of the record stays refused and names the copy
  that frees it (F-24).
- `in` and `not in` take a field of a call's result as either operand, as `==` does (F-56).

### `http.path` and a URL in the query, type arguments through a function argument, three refusals that say what is true (lane FR12, 14 November 2026)

Nothing accepted before is refused, and no call that checked before resolves to another instance. Two behaviours change.

- `http.path` cuts the query off at the first `?` before it looks for an absolute-form target, and a target is in absolute
  form only when it does not start with `/` and has a `://` before its query. `/view?file=https://host/x.html` has the
  path `/view`, not `/x.html` (F-59). A well-formed target that has no `://` in its query answers as before.
- A function passed for a parameter of function type gives its parameter types and its result to the type arguments, in
  both spellings: a parameter typed `func(str) -> T fails E` takes `T` and `E` from a function declared `-> Link fails str`,
  and an expected `Result[S, E]` gives `S` to a callee declared `-> T fails E`. `try each(values, link_of)` and
  `count(each(values, link_of))` need no `each[Link]` now (F-58). A conflict between two sources names both, and an
  undetermined type parameter is named.
- Messages, with no change to what is accepted: an apostrophe inside a word that ended single-quoted text (or a quote that
  ended double-quoted text) is named with a note at it, and an unterminated literal is called a text, a format string or a
  byte literal for what it is (F-61); a bare `else:` or `else None:` over a call that fails says the call can fail and names
  `else Err(_):` and `else Err(reason):`, with a note at the called function, and `mylang fix` writes `else Err(_):` (F-60);
  `try` on an Option in a function declared `-> T? fails E` says that `try` there passes on a failure and names the
  bind-or-else (F-57). A note at a builtin type's case, which has no declaration in the program, is left out instead of
  printed at line 1.

### `mylang rename` renames a declaration and every use the checker resolves (lane FR3, 13 November 2026)

Nothing accepted before is refused. `mylang rename [--dry-run] [--json] ENTRY.my|DIR TARGET NEW` renames a function,
constant, type, case, field, parameter or local, named `module::name`, `module::Type.member`, `module::Type.Case.field`
or `FILE:LINE:COLUMN`, and every use the checker resolves to it in the files `mylang fix` visits for the same argument:
calls, named arguments, field reads and writes, pattern labels, case names, type positions, uses through an import or
its alias, `from` and contract clauses, f-string holes. String literals, comments and data files are never edited; the
command lists the old name's mentions there. The edits are checked in memory and written only when every check has the
same verdict as before; a taken name, a shadowing, a reserved word, a use it cannot resolve, a declaration outside the
project or an `extern func` refuses the whole rename and writes nothing (F-12, `docs/tooling/rename.md`).

### Messages and repairs from the friction log, round 2 (lane FR9, 13 November 2026)

Nothing accepted before is refused and nothing refused is accepted: messages, hints and `mylang fix` edits change, and a
failing `assert` of a comparison prints more.

- `E_UNKNOWN_SYMBOL` names the module (`module \`strings\` declares no \`joinx\``), its close names and the standard
  modules that declare the exact name (F-51).
- `E_SINGLE_OWNER_OVERLAP` at a write into the place a `match` is matching names `match mut PLACE:` where that form
  takes the write (F-49).
- Messages that named a retired form name an accepted one: `E_CONDITIONAL`, `E_COMPREHENSION`, `E_MATCH_YIELD`,
  `E_LAMBDA_PARAMETER`, the tuple messages, the two-name loop, generator arguments, `sum` of a generator and `dict()`
  (F-50). `if c: a else: b` in an expression is read as the removed conditional, so `mylang fix` writes the statement.
- An assert's quoted message followed by an operator, and `f"""`, have their own messages (F-52, F-19).
- `mylang fix`: `E_LIST_MEMBERSHIP_REMOVED` is repaired when one operand is a call, if the other is a plain read and
  the call passes no place `mut` or `own` (F-25).
- `check` leaves out the `W_COPY_MOVE` hint to consume a plain list parameter when a caller still needs the list it
  passes (F-27); the hint for a list a call returns and `E_ITERATION` say to write `own x` for `copy(x)` (F-16).
- A failing `assert LEFT op RIGHT` of integers, floats or texts prints both values after its message:
  `R_ASSERT: n == 4 (left 3, right 4)`; a text is quoted and cut after 80 octets (F-18).

### Gaps in the filesystem, the in-memory stand-ins and a started program's output (lane FR10, 13 November 2026)

Nothing accepted before is refused. Two behaviours change, both for the in-memory filesystem a test receives: it now honours
the permission bits it keeps (F-42), so a test that wrote through a read-only mode now sees the refusal the real
filesystem gives. No `mylang fix` migration is needed (no program stops checking), and no test of this repository, of the
standard library or of the three projects changed its result.

- `Stat.device` (`st_dev`; `0` when a constructor leaves it out) with `filesystem.device_major` and `filesystem.device_minor`,
  so an inode is named with its device as `/proc/locks` writes it; the in-memory filesystem is on `filesystem.MEMORY_DEVICE`
  (F-46). `stat_path`'s answer is 56 octets, up from 48.
- `filesystem.statfs(fs, path) -> Space` (`size_bytes`, `free_bytes`, `available_bytes`): the space of the filesystem that holds
  a path, under the grants `stat` needs; the in-memory filesystem answers the fixed numbers 1073741824, 536870912 and 402653184
  (F-45).
- `filesystem.read_at(fs, path, offset, max_bytes) -> bytes fails str`: at most `max_bytes` octets of a regular file from a byte
  offset, fewer at the end and none past it, real and in-memory (F-48).
- The in-memory filesystem refuses what the real one refuses to an ordinary user, call by call (`docs/io.md`, "Permission bits on
  the in-memory filesystem"): a write to a file without the write bit, a creation, removal or rename in a directory without it, a
  read without the read bit, a path through a directory without the search bit, with the real provider's words. One program of
  about 490 calls is pinned against a real directory. A read-only file in a writable directory is still replaced by a
  publication, as on disk (F-42).
- `process.start_to(proc, request, stdout, stderr)` with `process.Destination` (`Discard`, `File(path)`, `Caller`): a started
  program writes straight to the caller's own standard output or standard error while it runs (F-40). `process.start` and
  `process.run` are unchanged.
- The in-memory network already refused a second `listen` on a name a live listener holds; the friction's program kept no live
  listener (a binding never used again ends where it was made), so a test and the documentation now pin the rule and the
  listener's lifetime (F-43).

### A program that imports a locked package builds into a binary and runs its tests (lane FR4, 13 November 2026)

Nothing accepted before is refused. `mylang packages build ENTRY.my|DIR --lock LOCK.json` takes `--command build` and
`--command test`, and passes every word after `--` to the command: `--command build -- -o BIN --release` builds a binary,
`--command test -- --filter S` runs the tests of an entry or of every entry under a directory. Both link the C of the
packages the application allows and refuse a package that changed since locking, as `run-project` does. They stage the
snapshot into a directory kept per application under the per-user cache (`packages-v1`), so an unchanged build replays
and unchanged tests replay their passes; `check-project`, `run-project` and `index-project` still stage privately (F-1).

### Clearer refusals and repairs from the site project's friction log (lane FR2, 13 November 2026)

Nothing accepted before is refused and nothing refused is accepted: messages, notes and `mylang fix` edits change.

- `E_MODULE_READ` for a missing module names the import root it searched and the `mylang.json` that set it, and the
  import that reaches a file beside the importer (`import src.lib`); `mylang test DIR` prints that diagnostic under
  its discovery failure (F-6).
- `E_SHADOWING` names what a binding would hide (an imported module, a function, a module constant, a type, a local
  or a parameter) with a note at its declaration, for every binding form (F-10).
- `E_SINGLE_OWNER_BORROW` at a case or record built for `==` or `!=` says it is built for the comparison and names the
  `match` that compares without a copy (F-11); at a record of borrows with one owned field, a note names that field
  (F-44). `E_SINGLE_OWNER_OVERLAP` names a `with` scope opened from a record's capability field and the copy of the
  capability before the `with` (F-37), and, for a `match` on a call that lends from the local its arm replaces,
  `match copy(CALL):` (F-47).
- `mylang fix`: `E_TRY_POSITION` declares each embedded `try` before its statement where the order of evaluation
  cannot change (F-3); `return Unit()` becomes a bare `return` (F-41); a set's retired `add` method becomes
  `sets.include` for a lent value (F-2); `E_BORROW_UNDECLARED` declares `from` only when no caller in the program
  keeps the result and copies where one does, naming that caller, and `check` leaves out the `W_COPY_MOVE` hint of a
  function one of whose callers keeps the result (F-8, F-15).
- New: `strings.join(parts, separator)`; `str` and `repr` of a list name it (F-38).

### The watch loop an agent can block on (lane DL-3 part 2, P2 to P4, 13 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed. No gate verdict changes.

- `python3 scripts/dev_loop.py start | wait | test ROOT FILTER | stop | status | compare`: a daemon per worktree runs
  `zig build --watch -fincremental` frozen except inside a `wait`, which holds an ordinary build admission, returns
  when a build that holds the newest edit has finished (at most 20 lines, compile errors with `file:line:col`) and
  freezes it again. `test` runs the installed test binary with Guardian's runtime filter and compiles nothing. The
  daemon stops after twenty idle minutes and stops a frozen watcher short of a gate's memory. `compare` checks
  watch-built binaries against normal ones, verdict by test name: the newest edit check's selection, or every test
  with `--all`, one ordinary build admission per root.
- A host-ceiling refusal of a watch-built compiler is reported as watch-only, with the reason (decision D9, the
  user's, 13 November: "Yes, name it"): an incrementally linked compiler maps 433.7 MiB against 77.9 MiB, so one CLI
  test that sets `MYLANG_HOST_MEMORY_LIMIT=192M` fails on it. Any other difference stays a difference.
- Under `-Dwatch-identity` the compiler and the three test binaries install as symbolic links to the incremental
  artifacts instead of copies (about 4.5 s of each watch rebuild); an ordinary build puts files back. The identity
  tool writes `identity.zig` only when its bytes change.
- `scripts/focused_test.py units|cli FILTER` uses a running watcher's binaries (`--no-watch` builds as before).
- `docs/tooling/development-loop.md` has the agent's recipe; before a gate there is nothing to do.

### A test that fails in a gate and passes alone no longer fails it; a killed process slow to die is not a survivor (lane DL-4, 13 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed. A gate verdict can change, by the user's
decision D5: a gate whose only failures are at most five named tests that each pass when rerun once alone now passes.

- `verify_cache.py` reruns those tests after the build, under a gate admission, as their steps ran them (each launcher
  now records its command and environment); the verdict line counts them, the summary names them, and
  `~/.cache/mylang/flaky-tests/flaky.jsonl` logs them (`scripts/verification_rerun.py --log` reads it). Such a gate
  records no receipt. `--no-flaky-rerun` keeps the strict verdict.
- The admitted build's supervisor waits up to 60 s for a process it killed before calling it a survivor.
  Details: `experiments/dev-loop-audit-20261112/DL4c.md`.

### Replacing the matched value inside its own `match mut` arm is refused for every payload type (lane FX9, 13 November 2026)

- **Newly refused:** inside a `match mut` arm, a write that replaces the matched place or a container of it (`s =
  Sh.empty`, `h.shape = ...`, `h = ...`, `reset(mut h.shape)`, `exchange(mut s, ...)`, or the enclosing arm's binding an
  inner `match mut` matches) while a payload binding of the arm is still used afterwards, when the payloads hold no
  text, bytes or list. It was refused for those already; for plain numbers it has been accepted since `match mut` became
  usable on such a union (through a `mut` parameter since `match mut` arrived, 23 October 2026, item C1; on a `mut` local
  since 12 November, item FX5), and the binding then read a payload of another case and wrote the old case back. The
  refusal is `E_SINGLE_OWNER_OVERLAP` at the write: move the write after the binding's last use, or write through the
  binding. No `mylang fix` migration: moving the write changes what the program computes. The repository and the three
  project ports have no such write (the user's decision HOLD, made on that count).
- Still accepted: a read of the container during the hold, a write to a field beside the matched place, a write in an
  arm that binds nothing, and a write after the binding's last use.

### Gates restart on inputs changed before any action, wait for a saturated disk, and record what the edit check would have caught (lane DL-4, 13 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed. No gate verdict changes.

- `verify_cache.py` takes a new snapshot and starts again, at most twice, when its inputs change before any gate action
  started, printing the path; a change after an action started fails as before, and a third change fails with all
  three paths. A changed tool on `PATH` counts like any input (D4).
- Before the first admission it needs it waits, at most 20 minutes and saying why, while `/proc/pressure/io` shows
  `full avg60` above 25%; `--no-disk-wait` turns that off. The verdict line says how long it waited and how often it
  restarted.
- After a gate that failed on named tests it starts `scripts/edit_check_shadow.py` detached, which records in the edit
  check's store whether the selection held them; the gate does not wait for it. Details:
  `experiments/dev-loop-audit-20261112/DL4b.md`.

### `match mut` lends a `@linear` owner and no longer ends it (lane FX8b, 13 November 2026)

A program whose only use of a `@linear` owner was a `match mut` is now refused, and no `mylang fix` migration exists:
such a program must consume its owner, which no certain edit can choose for it.

- From `@linear` records' landing (`3507daf87c`, 11 November 2026) until this change a `match mut` of a linear owner
  counted as its consumption, so a program could drop the owner unconsumed: `match mut slot:` with no other use of
  `slot`, or an arm that assigns `slot` a new value. Both are now refused (`E_LINEAR_UNCONSUMED`, `E_LINEAR_USE`), and
  the message says that a `match mut` lends the owner and lists the four ways to end it. None of the repository's
  programs and none of the three projects relied on it.
- In return, a `match mut` binding of a linear payload is read, written and lent `mut` in place (refused before as
  "already consumed"), and the matched owner is consumed after the match: a state machine keeps a started
  `process.Child` in a union's arm, polls and signals it there, and stops it later.

### A watch admission kind that holds no build slot (lane DL-3 part 2, P1, 13 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed. No ordinary job is admitted that was
refused before.

- `scripts/build-slot.sh watch python3 scripts/dev_loop.py --daemon ...` holds one of `MYLANG_WATCH_SLOTS` (3)
  `watchN.lock` files, one per worktree, and no build slot, when `MYLANG_WATCH_MEM` (3G) is available; it never waits
  (exit 3, 4 or 5 says why) and refuses any command but the daemon (exit 2). The values are decision D2's, awaiting
  the user. `status` lists watchers with their state, and a timing request prints one line about the watchers beside
  it.
- A `build` or `gate` admission whose command is itself a plain `zig build` (no prefix) takes its worktree's
  `.mylang-cache/dev-loop/thaw.lock` shared, when it exists, before its ticket ("thaw before ticket before slot"), so
  it never writes `zig-out` while that worktree's watcher rebuilds. The verification coordinator and the scheduler
  backend do not take it yet.
- `scripts/worktree_cache_trim.py` counts a live watcher (its `watchN` slot, or its daemon's worktree lock) as an
  active job on every path that renames or deletes a cache. `docs/tooling/development-loop.md` has the details.

### The build-identity step costs what the edit costs (lane DL-3 part 1, 13 November 2026)

No program accepted before is refused, and no `mylang fix` migration is needed. The identity of a given tree is
byte-for-byte what it was.

- The build-identity tool analyzes each production source once (its token digest and its import edges) and forms every
  closure and digest from those facts: 0.21 s for all of `src` instead of 3.0 s, in every build. Under the admitted watch
  (`-Dwatch-identity=true`) the cached run only lists the sources and the live run forms the identity from a per-file record
  keyed by the BLAKE3 hash of each file's bytes (every run reads and hashes all of `src`), so an edit costs 0.02 to 0.03 s
  of identity. A symbolic link under `src` now fails the tool (none exists; it would be invisible to the identity).
- `-Didentity-record=off|on|check` (default `on` under the watch, `off` otherwise, so gates never read the record); `check`
  computes both ways and fails on a difference. `tests/compiler_identity_cache.py --only record` compares the two after
  each kind of edit, and `--only fixtures` pins the outputs of main's tool on fixed trees.
  `experiments/dev-loop-audit-20261112/DL3a.md` has the measurements and decisions.

### The gate reports format, Guardian and documentation findings before any test, and always names the failed step (lane DL-4, 13 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed. No gate verdict changes.

- `scripts/gate_cheap_checks.py` runs the commands of the gate actions that need no test (`zig fmt --check`, the `.my`
  format check, Guardian, `mylang doc-coverage .`, `test-inputs-coverage`, the registry of actions) beside the
  preparation build. A finding ends `verify_cache.py` before the gate build and any test action, with its `file:line`;
  `scripts/edit_check.py` runs the same checks, prints a finding at once, still runs its tests and then fails. A
  passing check changes nothing: the gate still runs its own action and records its receipt. `last-run.json` gains
  `cheap_checks`.
- `scripts/gate_summary.py` never prints "no failing step was found": it takes a step as failed from the build tree's
  marker or a `--fail-fast` beacon, names a driver's beacon by its script and action, the failed member rather than its
  parent, a failed compile step of the preparation build, Guardian's findings, doc-coverage's and `mylang test`'s
  failures from standard output, and otherwise the deadline, the changed input, the coordinator's error or the log's
  last lines. `experiments/dev-loop-audit-20261112/DL4a.md` has the measurements.

### A map of the compiler's source for agents, checked by the gate (lane DL-7, 13 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- `docs/tooling/compiler-map.md` lists the stages of a build in order with the function to open first, the files to touch
  to add a library function, a diagnostic, a statement form, a Core instruction or a flag (each recipe derived from three
  commits and tried on a fourth; `experiments/dev-loop-audit-20261112/DL7.md`), and where each area's tests are.
- The gate action `goals_register` also runs `tests/compiler_map.py` (`--map`): a path or `path: function` the page names
  that no longer exists fails with the page's line number, as does a page over 300 lines or 120 characters. The action's
  inputs now include `src/**/*.c`, `src/**/*.my`, `src/features.json`, `src/syntax_layout.txt`, `CHANGES.md`, `SPEC.md`,
  `test/core/` and the fix corpus, so an edit to any of them reruns it.

### The compiler's commands run on a thread with a 256 MiB stack of their own (lane DL-2, 13 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- `mylang` starts its work on a thread whose stack the compiler chooses (`compiler_stack_bytes` in `src/memory_budget.zig`, 256 MiB
  of address space; only the pages a compile touches are used) and the main thread waits. A 1,024-term expression, which needed
  about 10 MiB of stack to lower and overflowed `ulimit -s 4096` and, on a compiler built with Zig's incremental back end, the
  default 8 MiB, now compiles under a 1 MiB limit on every build. Exit statuses, output, the crash report and forked children are
  as before.
- A compiler held to a tight `MYLANG_HOST_MEMORY_LIMIT` (under 2 GiB) keeps Zig's 16 MiB thread stack, so its address-space
  ceiling is not squeezed; a system that will not start the thread (a caller's `ulimit -v`) leaves the work on the main thread.
  `experiments/dev-loop-audit-20261112/DL2.md` has the measurements.

### Build-slot admission costs what it decides: lock-woken waiters, a settle window that ends with its job (lane DL-1, 13 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- `scripts/build-slot.sh`: a waiter blocks on the lock it waits for, so it starts the moment a slot, the settle window or a
  timing window is released; `MYLANG_SLOT_POLL` (memory and earlier-ticket checks) is now 0.25 s and takes a decimal (it was
  5 s). The settle window (`MYLANG_SLOT_SETTLE`, 5 s) ends when the admitted job has exited instead of always running out.
  The line `build-slot: ... after Ns` and `MYLANG_ADMISSION_WAIT_S` now give the whole time from the request to the job's
  start, with milliseconds (the line printed whole polls, usually `0s`). The memory rule is unchanged.
- The cache trim decides on recorded sizes and walks no cache at an admission; the walk and the scan for half-done deletions run
  in a background process at most once in ten minutes per worktree, which renames nothing. A worktree nobody has measured yet
  is trimmed by the admission after its first measurement. Old and new wrappers share a slot directory
  (`experiments/dev-loop-audit-20261112/DL1.md`).

### CHANGES.md and docs/goals.md merge by union; the goals check refuses a repeated row or field (lane DL5, 13 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- `.gitattributes` gives both files Git's built-in `union` merge driver (no setup in a clone), so two lanes that add a
  dated entry at the same place no longer conflict: of the 191 merges of 3 to 12 November, 60 conflicted (54 in these two
  files); with the attributes 10 do. A lane whose branch lacks the lines still meets one conflict at its first merge of
  main (git reads attributes from the checked-out side): commit main's `.gitattributes` first.
- The `goals_register` gate action refuses what union can leave in `docs/goals.md`: a second summary row for a goal and an
  entry that gives a labelled bullet twice. `experiments/dev-loop-audit-20261112/DL5.md` has the replay.

### A slice of a text parameter that starts or ends inside a character now traps (lane FX8, 13 November 2026)

A running program can behave differently: no program is newly refused, and no `mylang fix` migration is needed.

- `text[a:b]` on a borrowed text (a plain `str` parameter, a payload matched from one, a returned borrow `-> str from x`,
  a slice of a slice) now traps `R_TEXT_BOUNDARY` when an endpoint falls inside a multi-byte scalar, as `docs/text.md`
  says and as the same slice of a field or a local always did. From commit `07d555f724` (21 October 2026, wave 2 C9 step
  3, a plain `str` parameter takes a view) until this change such a slice did not trap and handed out a `str` that began
  or ended in the middle of a character. A program that sliced a parameter inside a character and went on now stops
  there. None of the repository's programs and none of the three projects does.
- `strings.starts_with_at(text, prefix, at)` asks whether a prefix starts at a byte offset without slicing: an offset
  inside a scalar or past the end answers `False`, so a scanner can ask at every octet.
- `for x in own found:` takes a payload binding of `match own <name>:` (and a fielded payload of a matched call result),
  as `docs/match-expressions.md` says such a binding owns its payload; it was refused with `E_ITERATION`.
- `mylang check --no-cache` no longer crashes printing the `E_OWN_MARKER` refusal of `match own` on a borrowed parameter.

### Ownership certificates are format v2: a constructor names the views it holds (lane VAL phase 2, 13 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- `--emit-certificates`, `dump-ir --certificate` and `mutate-certificates` write `ownership-certificate-v2`. A Construct
  line whose result is owned or `emptied` lists the borrowed operands it holds in slots its destruction leaves alone
  (`views %V,…`: a span, a list view, a borrowed overlay). `mylang validate-certificates` and the Lean checker refuse a
  v1 file by name; a build writes its certificates afresh, so nothing old is read.
- The construct-read rule is complete: an owned aggregate may hold a borrowed operand as a loan only when the operand is
  one of its views, since it would destroy a borrowed `str`, list or record with itself. Builds count such a
  constructor and refuse nothing, as before; the gate refuses it. No program in the repository or in the three projects
  has one. The proof notes state the property as assumption A19.

### A project's stores in `mylang.json`, and `mylang cache where` (lane FR8, 13 November 2026)

Nothing accepted before is refused, builds and checks without a `stores` object write where they did, and no `mylang fix`
migration is needed.

- `mylang.json` takes an optional `stores` object: `cache_home` (`XDG_CACHE_HOME`), `objects`
  (`MYLANG_CORE_RUNTIME_CACHE`), `compiler`, `stages` and `tests` (the three shared stores, each also `false` for off)
  and `temporary` (`TMPDIR`). Each is read only when the caller's environment leaves its variable unset; an empty
  variable still means off. Paths are absolute or start with `~/`; a store inside the project's own directory, or a
  relative store, is refused with the file, line and column.
- `mylang cache where [ENTRY|DIR]` prints where each store and the temporary folder resolve for that project and what
  decided it: the environment, `mylang.json` (with its path), or the default.
- A program started by `mylang run` and a test process still see the caller's environment: the variables the file set
  are taken out again. Cache keys read `mylang.json` without its `stores` member, so moving a store invalidates nothing.
- A compiler from before this change refuses a file with a `stores` object (`unknown field in mylang.json`).

### A write through a `match mut` binding checks the record's `@invariant` (lane FX7b, 13 November 2026)

No program is refused, and no `mylang fix` migration is needed. One behaviour changes:

- **A `match mut` write is checked.** Since `match mut` arrived (23 October 2026, item C1), a write through a payload
  binding into a field of a record with an `@invariant` (`match mut s.mode:` then `v = -5`) was followed by no check of
  that record, so a program ran on with the invariant false. Now every record with an invariant on the matched place is
  checked after each such write (an assignment, `+=`, a `mut` argument, `take`, `exchange`, `append` and the other
  writes of a list binding, a write inside a nested `match mut`), as after a direct field write, and a broken one traps
  `R_INVARIANT` at the write. A program that broke its own invariant this way now traps where it used to run on. See
  [docs/contracts.md](docs/contracts.md#invariants).
- A `match mut` on a field of a record written in a loop, on a place two fields deep or on a field of a list element
  reads the payload under a tag test of its own, which the IR verifier's union-tag rule accepts; such programs can now be
  tested in the gate.

### The ownership validator counts a constructor that reads a borrow it neither owns nor lends (lane VAL, 12 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- The validator every build runs, and its Lean copy, have a new rule (J6 `construct-read`): a constructor whose result is
  owned or `emptied` may read a borrowed operand only when the borrow lives in owners the constructor takes (or slots
  of them), or when an owned result lists it as a loan. Lane FX6's plan, which freed a dictionary's keys twice, breaks
  it. Builds count such constructors and refuse nothing (`--stats` prints `mylang: construct-reads: N ...`); `mylang
  validate-certificates`, `dump-ir --certificate --validate` and the gate refuse them. No program in the repository or
  in the three projects has one. Builds will refuse them (`E_OWNERSHIP_VALIDATION`) once the counts have stayed at zero.

### A loop that serves and calls, a receive buffer, SHA-1 and the unit of `time.sleep` (lane FR7, 12 November 2026)

Nothing accepted before is refused or behaves differently, and no `mylang fix` migration is needed.

- `network.dial(mut poller, net, mut outcome)` and `network.dial_within(mut poller, net, limits, mut outcome)` open a
  connection from the event loop and name it by an id, as `accept` does, so one loop can serve and call and a client
  holds many connections without a list. Nothing blocks: `wait` reports the new `EVENT_CONNECTED` (32), or
  `EVENT_ERROR` for a refused, unreachable or timed-out connect; a refused dial is the new `OUTCOME_DENIED` (7).
- `network.Timeouts` gains `receive_buffer_bytes` (0 by default, the system's), for `connect_within` and `dial_within`.
- `hashes.sha1` and `hashes.sha1_bytes`, for protocols that require SHA-1 (the WebSocket handshake), not for security.
- A resource, or a record that holds one, as a list, dictionary or set element is still `E_GENERIC_REQUIREMENT`; the
  message now says that a resource has one named owner and names what to use instead, with no note at line 1.
- `docs/standard-library.md` and the module comments say that `time.sleep` and `time.monotonic` count nanoseconds, and
  `docs/concurrency.md` that a task's blocking network call or sleep holds every other task's capability calls.

### Vector loops with narrow invariant operands build; a nested `match mut` reads under a tag test (lane FX7, 12 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- **The vector lowering** splatted every loop-invariant operand as an `i64`, so a loop such as
  `total += values[j] + int(c // 7u8)` with `c: u8` failed to build in every mode that vectorizes, the plain build
  included (`ToolFailed`, clang: `'%v44' defined with type 'i8' but expected 'i64'`). It now widens or narrows the
  operand from its own width. A function with more than twenty vector loops also failed (two values named
  `%vtot21`); the names are now distinct.
- **A `match mut` on a payload binding of another `match mut` arm** read and took the inner union's payload with no tag
  test the IR verifier's union-tag rule accepts, so the gate's `verify-ir-proof` refused any test of it. The compiler now
  tests the inner union's tag where it reads it. A program that writes the outer binding before the inner binding's
  last use, which is accepted today for a union of scalar payloads, now traps `R_CORE_FACT` there instead of reading
  the other case's payload.

### A started program is no longer capped by the Selka program's memory ceiling; `process.start` (lane FR6, 12 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed. One behaviour changes:

- **A child is no longer capped.** A program started by `process.run` used to inherit the address-space limit
  (`RLIMIT_AS`) the runtime puts on itself: under `mylang run` the run's memory ceiling plus 256 MiB, 4.25 GiB by
  default, so headless Chromium died at once with only "Trace/breakpoint trap". Every child, of `process.run` and of
  the new `process.start`, now starts under the limit the Selka program itself started with (unlimited from an
  ordinary shell). The Selka program's own ceiling is unchanged. A program that relied on its children being capped
  can run them under `prlimit --as=BYTES` or `sh -c 'ulimit -v KIB; exec ...'`.
- **New in `process`:** `start(proc, request, stdout_path, stderr_path) -> Child fails Error` starts a program without
  waiting, its output in files or `/dev/null`; `pid`, `signal` (with `SIGTERM`, `SIGKILL` and seven other constants),
  `wait_within` (a limit in milliseconds, `None` while it runs), `wait` and `stop` (SIGTERM, a grace, SIGKILL). A
  `Child` is a sealed `@linear` record, so it ends exactly once on every path; a started program is killed when the
  Selka program ends first. A scripted Process answers `start` from its rules. See
  [docs/io.md](docs/io.md#starting-a-program-without-waiting).
- `process.run` starts its child with `vfork` and `execve` in the runtime instead of `posix_spawnp`, to set the limit
  in the child; the PATH search, the signal mask, `SIGPIPE`, the descriptors and the start errors are the same.

### An operation on a value that always traps builds, and `match mut` on a scalar union's `mut` local (lane FX5, 12 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- A program that shifts by, divides by or takes an exclusive-or of a value whose checked arithmetic always overflows
  (`const c: u32 = 14u32 - 31u32` then `shift_right(7u32, c)`, `bit_xor(c, c)`, or `7u32 // saturating_add(c, 1u32)`)
  crashed the compiler (a panic in the fact pass) in the plain build, `--release`, `--debug-o0` and `mylang test`; a
  release compiler died on the division with a floating-point exception. Such a value used as the bound of a `for` or
  `while` loop, or as the dividend of a division in a vectorized loop, failed with the
  internal error `E_FACT_VALIDATION` or crashed the vectorizer. Each now builds in every mode and traps `R_OVERFLOW` where
  the value is made, as `--unoptimized` always did.
- `match mut` on a `mut` local of a union whose payloads are all scalars (`enum Sh: empty, rad(value: int)`) was refused
  with `E_SINGLE_OWNER_BORROW` ("declare it `mut`") though the local was `mut`; the same match through a `mut` parameter
  was accepted. So were a `mut` local of a scalar option (`mut o: int? = Some(5)`) and a field of a `mut` local record
  whose fields hold no managed value (`match mut b.limit` with `limit: int?`). Each is now accepted and writes the payload
  back. A `const` local, a plain parameter and a loop variable are still refused with the same message.

### `dicts.items` over a lent dictionary no longer destroys its keys (lane FX6, 12 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- `for entry in dicts.items(d)` where `d` was lent by a borrowed result (a `from` function, the option such a function
  returns, a union payload behind an accessor, `json.as_dict`) destroyed each heap key at the end of its iteration
  while the dictionary still held it. Later reads saw freed memory (garbage keys, a wrong comparison), and the
  dictionary's destruction freed the keys again (`free(): invalid size`, a segmentation fault), in every build mode.
  Literal keys hid it, since they are never freed. Destructuring (`for k, v in`), `keys`, `values`, direct iteration,
  `list(dicts.items(d))` and dictionaries reached through a local, a field or a parameter were right.
- The cause was in the ownership pass. Each entry lookup reads such a dictionary through its own `borrow` overlay, so
  the pass did not see one entry and built the item as an owning record. It now compares the dictionaries the
  overlays lend from. A record of dictionary loans that it still cannot prove is one entry is refused as an internal
  error instead of being built as an owner.
- Since 24 October (`2f23f90ec`, borrowed results in signatures). The ownership validator accepted these plans; a rule
  that refuses them is proposed in `experiments/audit-work-20261111/FX6.md` and was not landed here.

### `mylang test` no longer passes a test whose value is False (lane FX4, 12 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- In `mylang test`'s default build (`--debug-o0`) and under `--unoptimized`, a test could be reported as passed although
  it returned False: `return not a() and b()`, a call of a function that computes its result that way, a record's
  `bool` field, a value passed through a generic, an option or another module. The trial handed the result to a C
  runtime helper whose `bool` parameter carried no `zeroext`, so an unoptimised caller left the register's upper bits
  undefined and the helper read them as True. `--debug-lean`, `--optimize-debug` and `--release` happened to be right,
  `if` and `assert` always were, and the value itself was always right.
- Every C callee, the runtime's helpers as well as a source `extern func`, now receives a `bool` or narrow integer
  argument widened (`zeroext`/`signext`) on its declaration and its calls, and the runner refuses a `bool` result word
  other than 0 or 1.
- What it could have hidden: any `bool` test returning False, in the default test build since 27 October
  (`ded1d5e13`, the default test build at LLVM `-O0`) and under `--unoptimized` since 6 October (`fc6f7c273`). A rerun
  with the fix of `tests/lang`, `tests/value_semantics`, `tests/ported`, `tests/guest` and the three projects
  (5,507 test runs) found no test that had been passing falsely.

### Sealed records, `@sealed` (lane W11, 12 November 2026)

`@sealed` above a `record` lets only its declaring module and that module's `<module>_test` file build one, write its
fields, `replace` or `take` it, or take it as a test input; another module reads its fields and moves, copies, compares and
keys with its values. A refusal is the new code `E_SEALED_RECORD`, and its message names a function of the module that
makes one. A `match mut` whose place passes through a field of a sealed record is refused there too, whatever its arms do
(read the field with a plain `match`). On a `@linear` record, `own r.field` outside the module is refused too, so a
protocol state ends only through the module's functions. See `docs/records-and-unions.md#sealed-records`.

Three standard-library records are sealed: `hashes.Digest`, `symbols.Table` and `spans.Span`. A program that built one
of them by its constructor or wrote one of its fields outside its module is now refused; build them with the module's
functions (`hashes.blake3`, `hashes.from_bytes`, `hashes.from_hex`; `symbols.create`; `spans.of`, `spans.between`,
`spans.whole`). There is no `mylang fix` migration, because the right function depends on what the value means. The
repository and the three projects (the EDA port, protobuf, sqlite) had no such site.

### The gate compares build modes on generated programs (lane GEN, 12 November 2026)

Nothing accepted before is refused, nothing refused before is accepted, and no `mylang fix` migration is needed.

- A new gate action, `mode_differential` (`zig build test-mode-differential`, driver `tests/mode_differential.py`), writes
  13 small valid programs (312 generated functions) from fixed seeds and builds them with the plain build, `--release` and
  `mylang test`, one program in four also with `--debug-o0`, `--unoptimized` and `mylang test --unoptimized`. The modes must
  agree on each function's printed value, its trap (code, operands, line and column) and its test's verdict, and no mode may
  stop with an internal compiler error or a panic. It is the one place `--release` builds run in the default gate. Outside
  the gate, `--seeds A..B` hunts with other seeds and `--reduce FILE` shrinks a failing program.

### Four network and HTTP additions a web server needed (lane FR1, 12 November 2026)

Nothing accepted before is refused or behaves differently, and no `mylang fix` migration is needed. Each is a new name.

- `network.connect_within(net, network.Timeouts(connect_ms=, read_ms=, write_ms=))` connects like `connect` within time
  limits the runtime keeps on the socket. A connect, or a later `read_resource` or `write_resource` on the connection,
  that runs out fails with the new code `network.timed_out()` (7), distinct from a refused endpoint (3) and a closed peer;
  `network.describe(7)` names it. A limit of 0 is none.
- `network.set_connection_idle_timeout(poller, id, millis, mut outcome)` gives one Poller connection its own idle timeout
  (0 never, a negative value back to the poller's); every other connection keeps `set_idle_timeout`'s.
- `http.write_response_head(response)` writes the answer to a HEAD request: the GET answer's header section, its
  Content-Length included, and no body.
- `http.parse_request_within(data, http.Limits(header_bytes=, header_fields=, body_bytes=))` parses a request within the
  caller's limits, whose defaults are `parse_request`'s. A body past the limit is `BodyTooLarge` (413).

### A list element that always overflows traps in every mode (lane FX3, 12 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- A list, fixed array or nested list holding an element whose checked arithmetic or checked conversion always overflows
  (`[1, 9223372036854775807 + 1]`, an `append` of one, `u8(300)`, a call of a function that always traps) failed to build
  with `--release` and under `mylang test` with the internal error `E_FACT_VALIDATION`, where the plain build traps
  `R_OVERFLOW`. The fact pass stated the list's elements from the never-produced value's empty interval; it now states the
  type's range there, as the fact validator derives it, and every mode traps `R_OVERFLOW` where the plain build does.

### Messages, `mylang fix` and documents the audit lanes found (lane FX2, 12 November 2026)

Nothing accepted before is refused and nothing refused before is accepted: a program keeps its verdict and its error code, and
no `mylang fix` migration is needed. Eight small items, one commit each:

- A method call through a field or an element (`b.p.norm()`, `ps[0].norm()`) now says `a record has no methods; write the
  function form `norm(b.p)`` (a scalar, `a value of type `int` has no methods`), as a local does, and not the union of every
  collection's methods. The codes are unchanged (`E_COLLECTION_METHOD`, `E_CALL_ARGUMENT` with keyword arguments).
- The friction classifier files `&&`, `||` and `!` as `logical-operator`, not `bit-operator`. The refusals of a property test
  (`cannot be generated`, `a property test returns bool or Result[bool, E]`) print source type spellings (`int`, `Box[]`,
  `dict[str, int]`, `Host`), not the compiler's (`i64`, `List<main::Box>`, `host_cap`).
- `mylang fix` writes `sets.include(mut seen, e.key)` for a lent value `sets.add` stores in one round (it wrapped `copy(...)`,
  which the needless-copy warning rewrote in a second); the text is the same, 7 edits where there were 21.
- `E_ERROR_CASE_AMBIGUOUS` in a generic declaration has the plain case's message and fix; a generic union's case is built
  through its bare name (`fail Wrap.First(value=x)`), so the fix for `fails Wrap[str]`, which wrote `Wrap[str].First` and did
  not build, now builds.
- `mylang fix .` waits to rename a prelude-named declaration (`E_BUILTIN_FUNCTION_NAME`, `E_BUILTIN_TYPE_NAME`) while a file
  that does not parse imports its module, and names the file; before, the modules that parsed were renamed and the calls in
  the other were left naming a function that was gone.
- `docs/records-and-unions.md` no longer says `E_DEAD_RECORD_WRITE` exists (the lint rule `dead-write` does, off unless asked
  for), the echo-server example in `docs/standard-library.md` keeps no table nothing reads, G3 of `docs/goals.md` says the
  union-tag rule landed, and `docs/audits/audit-work-plan-2026-11-11.md` records what the run did.
- The edit check selects `test-goals` for an edit of `docs/goals.md` or of a pinned example.
- `mylang doctest` accepts `# doc: expect-trap R_CODE`: the example runs and must stop with that runtime trap. G10-H2 uses it.

### Five defects the audit lanes found (lane FX, 12 November 2026)

Nothing accepted before is refused, and no `mylang fix` migration is needed.

- `Simd[T, N](v)` or `FixedArray[T, N](v)` of a value that is already a fixed array or a Simd crashed the compiler; it is
  now `E_TYPE`, naming the two forms the constructor takes (a list literal, a growable `T[]`) and the type it was given.
- `lists.stride` on a list parameter, a slice or a slice binding was `E_CORE_UNSUPPORTED`; it now gives the values it
  gives on an owned list, reading the view in place and copying only the elements it selects.
- `debug(...)` in a generic function was `E_UNKNOWN_FUNCTION`; it now checks as in a plain function, `sep=` and `end=`
  included, and each instance's check decides what it can render.
- A function named like a builtin type (`bytes`, `str`, `float`, `f32`, `dict`) in a single file with no import was
  `E_DUPLICATE_NAME` under `build`, `run` and `dump-typed` while `check` and every program with an import accepted it; it
  is accepted everywhere, as the rule of item W6 says for a function its module never calls bare. A declared type still
  conflicts with a function of its name.
- `buffers.append_range`'s comment, `docs/bytes.md` and `docs/standard-library.md` now say what it does: a negative start
  or end traps `R_LIST_BOUNDS`, and a range with nonnegative endpoints answers whether it is valid.

### A generic body is judged at its declaration (item W3, step 2, 12 November 2026)

**Breaking.** `mylang check` (and `check-module`, `check-project` and `mylang fix`) now checks the body of every
generic function of the program, instantiated ones included, for every kind of type argument its bounds admit: a scalar, a
text, a record with a managed field and a list. A body that one of them refuses is an error at the declaration, named once,
with the type parameter and the kinds (`the body of `first` is refused when `T` is a text, a record with a managed field or
a list`) and the place in the body as a note. Before, `check` tried `int` alone, so the same body was accepted until another
module first passed `str`, and the error then sat inside the template. A single-file `check` now judges generic bodies too
(it judged none). The code is the ownership code of the refusal (`E_BORROW_UNDECLARED`, `E_SINGLE_OWNER_BORROW`, ...). A build
reports a refusal inside a generic instance at the declaration in the same words. The standard library is judged once per
compiler, by a gate test (`mylang template-stand-ins --standard-library`), and a judgment that passed is kept with the module's
ownership proofs, so an edit judges again only the templates whose declaration, or what it names, changed.

**Migration.** `mylang fix` writes the certain repair: ` from xs` on the result for a returned borrow, `copy(...)` on a stored
value (only when every type parameter admits `copy`); a second round repairs a body that returns another's result. A body
refused for another reason (`take` of a type with no default, a resource moved twice) has no certain fix. Corpus:
`test/fixtures/fix-migration/generic-declaration/`. In the repository 52 templates of `.my` programs (49 by `mylang fix`), 6 of
the fixtures and `tests/guest`, 8 of the documentation and the helpers of Zig tests changed; the standard library needed none
after move 1 (see `experiments/audit-work-20261111/W3.md`).

### The hidden-copy check runs in every build (item N5, 12 November 2026)

`E_CORE_HIDDEN_COPY`, which refuses a copy no source wrote, now runs in every guest build (`build`, `run`, `build --run`,
`run-project`, `test`; debug and `--release`) beside the IR verifier and the ownership validator, under their policy:
`--no-validate` turns it off, and a final record says `validated` only when the check also passed its body, so a body
served from a record alone passed it in the build that made the record. It refuses what it refused under
`--verify-written-copies`, which with `--verify-facts` keeps its meaning; frame blocks and dictionary-key copies are
counted, not refused. No program a source can spell produces such a copy, so nothing accepted before is refused (the
repository's suites and the three projects: 0 refusals), and no `mylang fix` migration is needed.
`MYLANG_VERIFY_WRITTEN_COPIES=0` no longer turns the check off; `--no-validate` does. `--stats` prints the check's census
in every build. Turning it on found one hidden copy: `strings.char_stride` of a borrowed text copied the whole text and
dropped the copy unread; it now reads the view in place. A sweep of 98 library operations on a parameter, a slice and a
slice binding found no other (`tests/lang/view_receivers.my` keeps it).

### `sqrt`, `floor`, `ceil` and `trunc` are prelude names for the builtin-name rule (lane N4, 12 November 2026)

The four bare binary64 operations of the prelude (`sqrt(x)` and the others, `float_intrinsics`) were in neither of the
two lists that became `src/prelude_names.zig`, so a module that declared `func sqrt(x: float) -> float` still made every
bare `sqrt(...)` in it call its own function. They are now in the table (54 names), and the rule of item W6 covers them:
such a declaration, or `export module.sqrt`, is refused with `E_BUILTIN_FUNCTION_NAME` when its own module uses the name
bare, and `mylang fix` renames it (`sqrt` in `rounding.my` becomes `rounding_sqrt`) or writes the re-export's uses
qualified. A bare `sqrt(x)` in a module that declares no `sqrt` means what it meant. An `extern func floor` called bare is
refused with no rename, since its name is its C symbol: declare it in a module of its own (`examples/c-ffi/libc.my`).
`mylang docs operations` lists the four under "prelude, float operations".

### Library functions the compiler supplies are declared `builtin func`; every spelling of a call is the operation (item W10, 12 November 2026)

Ninety standard-library functions had a body on the page that a call did not run: the compiler answered the call with a
builtin operation. They are declared `builtin func` now, with no body: the 58 functions that replaced collection, text,
bytes and buffer methods, the nine `simd` lane operations, the `parallel.map` family, two private `testing` counters and
the fourteen scalar text helpers (`strings.char_count`, `strings.chars`, `lists.stride`, ...), which had no declaration
at all. A call is the operation however it is spelled. Before, an import alias (`import simd as v`), a re-export, a keyword
argument or an explicit type argument ran the body instead, so `v.sum(lanes)` gave the first lane, not the sum. What
changes for a program:

- Through an alias, a re-export, a keyword or a type argument, every `simd` operation gives the operation's answer;
  `dicts.keys`, `values` and `items` are live views, so a loop that writes the dictionary is refused
  (`E_SINGLE_OWNER_OVERLAP`); a constant negative index to `lists.pop_at` or `lists.insert` is refused at check
  (`E_NEGATIVE_INDEX_REMOVED`); `lists.reverse` and `lists.pop_at` on a `str` list compile; `simd.sum(value=v)` is
  accepted; an alias reaches the scalar text helpers.
- A `simd` operation or a scalar text helper is not a function value (`E_BUILTIN_FUNCTION_VALUE`): call it directly, or
  pass a named function that calls it. A `simd` one compiled before and gave a wrong answer. No structured fix: which
  named function to write is the program's choice. Nothing in the repository or the three projects passed one.
- `builtin func` in a program's own module is refused (`E_BUILTIN_DECLARATION`).

`mylang list-interfaces` lists these functions as `export builtin function`, and their interface role is `declared`.

### `sets.intersection`, `sets.difference` and `sets.symmetric_difference` work for sets of text and records (item W3, step 2, move 1, 12 November 2026)

Every call of these three on a `set[str]`, a `set[bytes]` or a set of records was refused with `E_SINGLE_OWNER_OVERLAP` at
the call: the lowering stored each kept element, borrowed from the operand it walks, into the result. The result now holds
its own copy of each kept element (the dictionary write's copy on insert, as `d[key] = value` stores a key written as a
place), so these calls are accepted and the operands stay usable. Nothing accepted before is refused, and no migration is
needed. Five standard-library bodies were also written so that they are accepted for every element type
(`sets.add`, `dicts.setdefault`, `dicts.pop_default`, `lists.pop_at`, `lists.reverse`); what their calls do is unchanged.

### `old(x)` of a managed value is written `old(copy(x))`; one meaning of "hidden copy" in the tools (item W4, 12 November 2026)

An `@ensures` clause that captures a managed place, `old(items)`, `old(state)` or `old(bag.items)`, copied it at every
call with no `copy(` written. It is now refused (`E_CONTRACT_OLD_COPY`) and written `old(copy(items))`; `mylang fix`
writes the copy (corpus `test/fixtures/fix-migration/old-copy/`). `old(len(items))`, a scalar, and an argument that is
already a new value stay as they are. In the repository one program and three documentation examples changed; the three
projects had none. `mylang cost --sites` and the hidden-copy check (`--verify-facts`) now read one list of copy sites,
the frame block included, in the same blocks. Each copy row of `cost --sites` is labelled `written`, `named operation` or
`implicit` (`frame block`, `dictionary key`, `old capture`, `unwritten`), the text's `hidden copies: N` line counts the
implicit rows by kind, and the JSON rows gain `label` and `implicit` beside the unchanged `written` (plus
`implicit_copies` beside `hidden_copies`). The dictionary-key copy stays, by the user's decision, as the one documented
implicit copy. The check refuses nothing new and prints its census under `--stats`.

### `mylang lint --rule=dead-write` counts the writes that nothing reads (item W7, step 1, 12 November 2026)

Nothing is refused, nothing new is printed by default, and no `mylang fix` migration is needed. A new lint rule,
`dead-write` (`L_DEAD_WRITE`), reports a write to a local, to a field or element of a local, or a writer call on a local
(`append(mut x, ...)`, `helper(mut x)`) when no later read sees it, such as an update made on a copy and then dropped
(`docs/goals.md`, G9-X6). It is off in every profile and runs only when `mylang lint FILE --rule=dead-write` names it, and
then it reports and never refuses. `--rule=NAME` is a new `lint` option that turns on one rule its profile leaves off.
The count it gave, and what the rule might become, are in `experiments/audit-work-20261111/W7.md`.

### Diagnostics no longer advise a spelling the compiler refuses (lane W8, 12 November 2026)

Nothing accepted before is refused and nothing refused before is accepted, so no `mylang fix` migration is needed; only
message text and, for three refused forms (`||`, `!` and `try` before an operator), the code changed. A removed or retired spelling's replacement is now code the
compiler accepts, and a gate test (`src/advice_tables_test.zig`) builds a program around every replacement of
`retired_methods`, `removed_names` and the parser's `declaration_hints` and requires it to check. Found and fixed with it:
`del xs[0]` names `lists.pop_at(mut xs, index)` (it said `xs.pop(index)`); the removed `mutates(...)` names `mut name: T`
(it said `name: mut T`); a lent value stored in a set is advised `sets.include(mut seen, e.key)` (it said `copy(e.key)`,
which `W_NEEDLESS_COPY` then refused); `a && b`, `a || b` and `!a` are answered with `and`, `or` and `not`
(`E_REMOVED_SPELLING`; they were `&` ... `mut value`, `E_EXPRESSION` and `E_TOKEN`); `sum += try half(x) + 1` is
`E_TRY_POSITION`, not the type error `E_TYPE`; a method signature in a message spells its types as source does
(`int?`, `str[]`, `Unit`, `str fails str`). Five small defects: the task message for a `bytes` argument no longer says "yet"
twice and every refusal reason is a noun phrase; `mut domain = 1` names the reserved word; `p.norm()` on a value says a
record has no methods and names `norm(p)`; two documentation examples were corrected.

### `try` and `fail` convert an error only when exactly one case fits (item W1, 12 November 2026)

A function that `fails` with an enum could write `try parse(s)` for an operation that fails with a `str`, or
`fail "text"`, and the error went into the first case of the enum that could carry a `str`, so reordering the enum's cases
changed which error the program reported. Now the conversion happens only when exactly one case fits (its payload is the
error's type, or it has one named field of that type). When several fit, `try` and `fail` are refused with
`E_ERROR_CASE_AMBIGUOUS`, and the message lists the cases that fit in declaration order. `mylang fix` repairs `fail value`
with the constructor of the first fitting case, `fail AppErr.Parse(value="text")`, which is the case the compiler chose
before; a `try` has no certain edit (naming its case means matching the result), so its message shows the form instead. No
program in this repository, the standard library or the three projects (the port, protobuf, the SQLite binding) was
refused. See `docs/results-and-options.md#converting-into-one-case`.

### A `build --release` binary evaluates the arguments of `debug(...)` (lane W5, 12 November 2026)

One narrow shape is newly refused (last sentences) and has no certain `mylang fix` edit. A release binary used to drop a whole `debug(...)`
line with its arguments unevaluated, so `debug(bump(mut counter))` wrote `counter` under `run` and not in the binary, and
`debug(xs[len(args) + 4])` trapped `R_LIST_BOUNDS` in one and exited 0 in the other. Now every build evaluates the arguments, in
order, and a release binary drops only the formatting and the write to standard error: a call runs, a `mut` argument is
written and a bad index traps in every mode. A release binary can therefore trap or write where it did not before, and an
argument that allocates allocates again (it is destroyed at once). `mylang cost` counts the evaluation of a `debug(...)`
line's arguments in its default (release) view. One shape is now refused: a `build --release` refuses a typed hole reached
only through a `debug(...)` argument (`E_TYPED_HOLE`), as `check` and `run --release` already did; the user decided on
12 November 2026 to keep that, with no carve-out for `debug`. The three projects hold no `debug(...)` statement outside a
friction repro, so none of their release binaries changed. See `docs/io.md#debug`.

### An ownership refusal names the line that made a borrowing local own; `mylang fix` writes no copy that loses a write (lane W2, 12 November 2026)

Nothing accepted before is refused and nothing refused before is accepted, so no `mylang fix` migration is needed. Whether a
local list, record or `mut` local borrows is still inferred from the whole function body, so a later line can make an earlier
one an error; that refusal keeps its code, position and repair and now carries a note at the later line ("`hits` owns its
elements because this line stores a new value in it, so the earlier line needs `copy(...)` or `own`"), and a record whose
left-out managed field defaults to a new value gets the note on that field's declaration. In `--diagnostics=json` the note
has the new role `cause`; a refusal may carry a `related` note and a `cause` note together. `mylang dump-typed` prints after
each named local of a managed type whether it `owns` or `borrows ... from` which locals. `mylang fix` no longer wraps
`mut x = xs[i]` in `copy(...)` when a later line writes through `x` or passes it with `mut`, no write-back is proved and `xs`
is a local or an `own` or `mut` parameter: the copy would take the write and leave the element unchanged, so the message
names the write and offers both spellings and the edit is left to the author. A borrowed loop variable added to a set is
advised `sets.include` (it said `copy(value)`), and a set reached through a field is no longer named by its record.

### A bare call of a prelude name is always the builtin (item W6, 12 November 2026)

A module could declare `func len(n: int) -> int`, and every bare `len(...)` in that module then called it, with no word
from the compiler; `export helpers.sum` did the same for a bare `sum(...)`, and `export math.abs` made a bare `abs(...)`
call the standard library's `math.abs`. Now a module function, public or private, whose name is a prelude function's (the
50 names of `src/prelude_names.zig`, the one table `mylang docs operations` prints) is refused with
`E_BUILTIN_FUNCTION_NAME` when its own module uses the name bare, as a call or as a function value, with a note at the
first such use. A re-export of such a name is refused the same way at its `export` line. A function its module never uses
bare is accepted: other modules reach it by its qualified name (`zipfile.write(...)`). `len`, `copy`, `str` and `bytes`
were never captured by a re-export and are not refused there. The standard library is exempt. Locals, parameters,
imports, fields and types keep their names.

`mylang fix` renames a refused function to its module's name and the old one (`len` in `shapes.my` becomes `shapes_len`,
with a digit added when the module already writes that name) together with every bare use in the module and every
qualified use in the modules that import it, and writes a refused re-export's bare uses qualified (`helpers.sum(...)`).
The repair is withheld when the module also writes the name as a parameter, a local or a field, and for an `extern func`,
whose name is its C symbol: declare it in a module of its own and call it qualified (`examples/c-ffi`).

### `on fail:` cleanup for the failure exits after it (lane FFI, stage 3, 11 November 2026)

Nothing accepted before is refused (`on fail:` was a syntax error, and `on` is a word only before `fail:` at the start of a
statement), so no `mylang fix` migration is needed. `on fail: STATEMENT`, or `on fail:` and a block, runs on each `try` and
`fail` after it in its block, latest clause first, until an owner it consumes (`own NAME` in it) is consumed outside it; the
parser rewrites each such exit into the bind-or-else it stands for, so a `@linear` owner can be closed on an error without a
helper. A clause cannot `try`, `fail`, `return`, `break` or `continue`, a function without `fails` cannot hold one, and in a
clause's reach `try` is a declaration's value or a statement (`E_ON_FAIL`). See
`docs/results-and-options.md#cleanup-on-failure`.

### Two `@linear` diagnostics say where and what (lane FFI, stage 3, 11 November 2026)

The refusal of a list, dictionary or set of `@linear` values now points at the type that names the container
(`Token[]`, `dict[str, Token]`) instead of the start of the file, and giving away a `match mut` binding says "a `match mut`
binding is lent, not owned" (`E_LINEAR_USE`) instead of reporting it already consumed.

### `links` in `mylang.json` (lane FFI, stage 2, 11 November 2026)

Nothing accepted before is refused, so no `mylang fix` migration is needed (`links` and `allow_links` were unknown fields,
which a configuration could not hold). A project lists its C sources once, `"links": ["vendor/sqlite3.c", "lib/shim.c"]`
relative to the `mylang.json`, and `build`, `build --run`, `run`, `run-project` and `test` link them before any `--link`
file. A package may list its own; `mylang packages lock` pins them and `mylang packages build` uses them only when the
application names the package in `"allow_links"`, else it stops naming the package and the entry to add. See
`docs/c-ffi.md#project-links` and `docs/tooling/packages.md#c-sources-in-a-package`.

### A `--link` source that names a header through a macro is cached (lane FFI, stage 1, 11 November 2026)

Nothing accepted before is refused and no emitted code changes, so no `mylang fix` migration is needed. A `--link` source
the depfile check could not cache (it, or a header it includes, names a header through a macro, as SQLite's amalgamation
does) is now keyed by the digest of its preprocessed text with the source's existing key, so an unchanged build of a
program linking the unpatched `sqlite3.c` costs about 0.2 CPU-s instead of 4.1 (debug) or 17.5 (`--release`). Such a build
runs the preprocessor each time and does not replay; a text holding `.incbin` or an unexpanded `#embed` is still compiled
every time. Every other source keeps its key, its depfile check and its cost. See `docs/c-ffi.md#linking-your-code`.

### `--verify-cache` checks `--link` objects (lane FFI, stage 1, 11 November 2026)

Nothing accepted before is refused, so no `mylang fix` migration is needed. `--verify-cache` never reached `--link`
objects: a served C object was linked without a recompile, so a damaged or forged one passed. It now compiles every served
`--link` object again, under either key, and fails with `--verify-cache: a --link source compiles to different bytes than
its cached object` on a difference.

### The IR verifier counts union payload reads without a test of their tag, and the gate refuses them (lane VL, V4, 11 November 2026)

Nothing a correct compiler builds is refused (every program of the three language suites, `wide_union_match.my` for a union
of 70 cases, the EDA port, the protobuf library and the SQLite binding) and the emitted code does not change, so no `mylang fix` migration is needed. `verify_ir.zig` now checks
that every `union_payload k` and `union_take k` reads a value whose tag the facts on the paths to it confine to case `k`
(a test of the tag, the equality of two tags, or a `union_make` of that case, followed through a field read twice, a field
stored and read back, and a `phi` of such values); a read of a `list_get` value under a test of
the element's tag is shape M, counted by the `verify-ir-proof` gate action. A build counts a read the rule cannot justify
and refuses nothing (`--stats` prints `mylang: union-tags: N payload reads not justified by a tag test`); the gate's
`verify-ir-proof` action refuses it (`mylang verify-ir`: `union payload read without a test of its tag`) over the language
suites, the C interop programs and a pinned protobuf program. The Lean copy proves the refusing rule sound for its tag
semantics (`proofs/verify_ir`, `payload_of_verdict`). See `docs/tooling/native-build.md#certificate-validators`.

### A `--release` build validates its IR, ownership and facts in every compiler (lane VT, 11 November 2026)

Nothing a correct compiler builds is refused and the emitted code does not change, so no `mylang fix` migration is needed. A
`--release` build of `build`, `run`, `build --run`, `run-project` and `test` now runs the IR verifier, the ownership validator
and the fact validator in every compiler, as a debug build runs the first two; it costs about 0.4% more instructions.
`--no-validate` turns it off, and a rejection names it.

### `@linear` records: owners a library hands out must be consumed (lane FFI F3b, 11 November 2026)

Nothing accepted before is refused (only a record written `@linear` gets the rules) and no existing program's emitted code
changes, so no `mylang fix` migration is needed. Every owner of a `@linear` record, and of any value that holds one, is
consumed exactly once on every path: given to an `own` parameter (written `own` at the call), returned, moved into another
owner, or ended with `own owner.field`. An unconsumed owner is `E_LINEAR_UNCONSUMED` at the path's end, a use after
consumption `E_LINEAR_CONSUMED`, and copies, plain parameters, discards, collections, generics, tasks and consumption on
some paths only are `E_LINEAR_USE`. See `docs/records-and-unions.md#linear-records`.

### Every compiler validates the IR and the ownership certificates of a debug build (lane VT, 11 November 2026)

Nothing a correct compiler builds is refused and the emitted code does not change, so no `mylang fix` migration is needed.
`build`, `run`, `build --run`, `run-project` and `test` in every mode but `--release` now run the IR verifier and the ownership
validator in every compiler, not only in a Debug one; a build with demand bodies keeps them, checking what it brings in and
reusing a stored body only when the build that made it validated it. A rejection is still an internal error
(`E_OWNERSHIP_VALIDATION`, exit 2) and now names the way out: `--no-validate` builds without the default validators (and
publishes nothing to the shared stage store). On the 99k port an optimised compiler pays 1.9% more instructions on a one-line
edit and 4.4% on a cold build. `mylang test` now shows the error line of a test program that failed to build, and a validator's
rejection no longer ends with a line about a missing stage record.

### The fact validator accepts a loop phi stated as the meet of its two bounds (lane VT, 11 November 2026)

Nothing accepted before is refused and the emitted code does not change, so no `mylang fix` migration is needed. A `--release`
build, or any build under `--verify-facts` or `--verify-facts-static`, of a loop whose accumulator grows by a constant and wraps
at a modulus (`bits += 6` then `if bits >= 8: bits -= 8`, as a base64 decoder does) was refused with `E_FACT_VALIDATION` (F3):
the facts state its interval as the meet of the hull of its operands and the counted-loop growth bound, and the validator
asked for one of the two alone. It now accepts the meet, which it derives itself; the Lean proof (`proofs/facts`) covers it.

### C interop: text, bytes, opaque handles, out-parameters and tests that call C (lane FFI, 11 November 2026)

Nothing accepted before is refused and no existing program's emitted code changes, so no `mylang fix` migration is needed.
An `extern func` now takes `str` and `bytes` parameters as a lent `(const uint8_t *, int64_t)` pair and may return
`bytes`, which the runtime copies from a pointer and a length C stores through a trailing `int64_t *` (`R_FOREIGN_RESULT`
traps a negative length or a null pointer with a positive one). `extern type T` declares an opaque C pointer type: `T()`
is NULL, `==` and `!=` compare, and every other use is refused with `E_EXTERN_TYPE`. A `mut` integer, `bool`, `float` or
`extern type` parameter is a C out-parameter, written back to its local, field or list element. `mylang test --allow-host`
hands the live `Host` to tests that declare it; without the flag such a test fails and names the flag. See
`docs/c-ffi.md` and `experiments/c-interop-sqlite-20261111/DECISIONS.md`.

### The IR verifier checks every constant and parameter, and refuses malformed tables instead of crashing (lane VL, 11 November 2026)

Nothing a program can write is refused, so no `mylang fix` migration is needed; emitted code does not change. A Lean copy of
the Core IR verifier (`proofs/verify_ir`) and a differential over the language gate's programs and single-rule mutants found
that constants and parameters, which no block lists, were never type-checked: a parameter read at another type than its
signature's, a float or text constant of any type, or an undefined function value passed the verifier. It now checks every
constant of the instruction table, refuses an entry block with predecessors, and refuses (rather than crashing or looping on)
a copy chain that leaves the table, a block whose last reference is out of range, and a type the module does not have. It
also makes a listed constant's uses follow dominance, refuses a value in a field a print, record constructor or call does
not read, and admits a span argument only for a text or bytes parameter: what the fact proof's SSA hypothesis and the
ownership proof's trust point A17 need, both now proved for the Lean copy.
`--emit-certificates` also writes each program's final IR as `program.core-ir`, which `mylang verify-ir` checks.

### A chained comparison in a condition narrows what follows it, as `and` does (proof steps, 11 November 2026)

Nothing accepted before is refused and no program computes anything else, so no `mylang fix` migration is needed; emitted
code changes for chained conditions. A chain of integers or booleans used as a condition (`if 0 <= i < len(xs):`, a `while`,
an `assert`, a contract clause, inside `and`, `or` or `not`) is now one branch per link, each operand still evaluated once,
in source order, and only while every earlier link held. So the facts know `0 <= i < len(xs)` inside such an `if`, and a
kept `@ensures(0 <= result <= 2)` tells every caller the result's range. A chain used as a value is lowered as before.

### A caller knows what a callee's `@ensures` says about an integer result (proof steps S2, 11 November 2026)

Nothing accepted before is refused, so no `mylang fix` migration is needed; emitted code changes where a check is now proved.
The interval a function returns takes the branches that dominate each `return`: an `if` that bounds a returned value, or a
kept `@ensures` on the result (its passing edge), now narrows what every caller knows, so with `xs` of length 3,
`xs[clamp(i - 3)]` has no bounds check when `clamp` ensures `0 <= result < 3`. `mylang cost --clauses` also counts, per
`@requires`, the call sites where it is proved (`call sites P/R/K`; `call_sites` in `cost-clauses-v1`).

### An `@invariant` is checked after `take`, `exchange` and every in-place update of a field (11 November 2026)

Nothing accepted before is refused, so no `mylang fix` migration is needed; a program that breaks an invariant this way now
traps `R_INVARIANT` where it ran on. `take(mut r.f)`, `exchange(mut r.f, v)`, a collection update on a field (`append(mut
r.items, x)`, `r.items[i] = v`, `r.map[k] = v`, a set addition, `h.rows[i].f = v`) and a call or callback that takes a field
as `mut` (`lists.pop(mut r.items)`, `f(mut r.items)`) now check every invariant on the written path afterwards, innermost first,
as a field store does, with no copy. So `take` and then a store of the new value can trap between the two; `exchange` is the
one-step form. A field store into a local of an inner block, or into a `match mut` binding whose other arm falls through, on
a record with an invariant was refused `E_UNBOUND` since the fixes of 10 November; it is accepted again. `match mut` on a
field is not checked yet. `experiments/proof-steps-20261110/TAKE.md`.

### Contract-clause fixes: `Unit fails E` postconditions, invariants beside managed fields, a local `result` (10 November 2026)

Refusals and a crash turn into acceptances, with one exception below. `@ensures` on a `-> Unit fails E` function, and any
`case Ok(v):` binding of a `Unit` success payload, no longer crash `mylang build`. A field store into a record whose
`@invariant` sits beside a managed field (`bytes`, a list, a nested record), through a `mut` parameter, a list, dictionary or
fixed-array element, a `match mut` binding or a narrowed option, is no longer refused (`E_SINGLE_OWNER_BORROW` rule M1, or
`E_SINGLE_OWNER_OVERLAP`): the invariant is checked after the write, on the written place, with no copy. A body local named
`result` beside `@ensures` now resolves at every `return result`. The exception: such a function that declares `result`,
returns it from an inner block and then declares `result` again in the outer block was accepted only through the defect and is
now `E_SHADOWING`; no `mylang fix` repair is certain (rename the second local). `experiments/proof-steps-20261110/FIXES.md`.

### `mylang cost --clauses` says which contract clauses the compiler proved (proof steps S1, 10 November 2026)

Nothing accepted before is refused and no emitted code changes, so no `mylang fix` migration is needed. `mylang cost ENTRY.my
--clauses` lists every `@requires`, `@ensures` and `@invariant` as proved (its check can never fail),
refuted (it fails whenever the program reaches it) or kept (checked at run time), with its copies counted in its own body and
inlined; `--asserts` adds the `assert` statements, which the totals always count. `--json` writes `cost-clauses-v1`.
`build --stats` and `run --stats` print a `mylang-core: clauses` line and one `mylang-core: refuted:` line per refuted clause,
only for a program with a clause or an `assert`. An ordinary build prints no warning for a refuted clause yet
(`docs/contracts.md#what-the-compiler-proved`).

### The primer teaches `assert` and the three contract clauses; one message loses a retired form (10 November 2026)

Nothing accepted before is refused, so no `mylang fix` migration is needed. `mylang docs primer` gains a section, "Stating what
code expects and promises", with a runnable example of `assert`, `@requires`, `@ensures` (with `result` and `old(...)`) and
`@invariant`, and its "Where to read more" list names the `contracts` topic. The `E_CONTRACT_TARGET` message for an `@invariant`
on anything but a record, `` `@invariant` attaches to a `record` declaration; a union, enum, alias, constraint or function
carries none``, no longer lists `class`, which the language retired; a script that matches the old text must match the code.

### A plain text, bytes or list parameter stored in a local list or dictionary is its frame block (H5, 10 November 2026)

Refusals turn into acceptances; nothing accepted before is refused, so no `mylang fix` migration is needed. `append(mut l, p)`,
`l[i] = p` or `d[k] = p` of a plain read-only `str`, `bytes` or list parameter `p` into a local list or dictionary, refused
before (R1, `copy(p)`), is now a collection of borrows (`docs/ownership-rules.md#collections-of-borrows`). It holds the
parameter's frame block, as a borrowed record does: the caller's own value for a whole argument, else one copy per call, made at
the first store and freed when the call returns, in a loop too. A bytes argument and a slice argument are always copied this way;
`--stats` counts the sites. A collection that leaves its call (returned, given to a `mut` out-parameter, stored) keeps its
refusal. The ownership matrix moves six cells from refused to accepted (plan Part B, H5).

### A `mut` local stored from a slice of a place borrows it (H4, 10 November 2026)

Refusals turn into acceptances; nothing accepted before is refused, so no `mylang fix` migration is needed. A slice of a place
(`p[0:2]`, `shelf.name[1:]`, `counts[a:b]`) stored into a `mut` local, once or among the local's assignments, now borrows the
place as a store of the place does (D4, `docs/ownership-rules.md#b9--const-place-bindings-borrow`), for text, bytes and lists:
`mut head = p[0:2]` then `if ...: head = port.name`, or `mut rest = p[0:]` rebound to `rest[1:]` in a loop, copies nothing, and
a list slice is a view of its elements. A write through the local, a store of it or a change of its owner while it is live keeps
the slice's refusal (V2) at the store, with `copy(...)` around the slice. The ownership matrix moves six cells from refused to
accepted (plan Part B, H4).

### A text or bytes slice given to an `own` parameter is refused, with its `mylang fix` (D8, 10 November 2026)

**Breaking.** `keep(text[0:2])` with `func keep(own s: str)` (or a bytes slice and an `own` bytes parameter) is now refused,
`E_SLICE_ESCAPES` under W4, as a list slice already was (`docs/ownership-rules.md#w4--no-slice-to-own`). The slice is a view of
its source, so the parameter needs its own value: before, the check accepted it and the build made a copy no `copy(...)` wrote,
which a `--verify-facts` build refused (`E_CORE_HIDDEN_COPY`). The refusal carries the certain repair, `copy(...)` around the
slice, so `mylang fix` migrates a project with no hand edits (`test/fixtures/fix-migration/text-slice-own.my`). A slice written
with `own` keeps its marker refusal (B2), which names the same copy. No site in `tests/`, the examples, `bench/`, the standard
library or the port was refused.

### A `mut` local stored once from a place borrows it (D4, 10 November 2026)

Refusals turn into acceptances or move; nothing accepted before is refused, so no `mylang fix` migration is needed. `mut c = place`
stored once now borrows the place, as a `const` does and as a `mut` local assigned more than once already did
(`docs/ownership-rules.md#b9--const-place-bindings-borrow`): reading `c`, and returning it under `from`, copy nothing. A write through
`c` (an append, a field or element write, a `mut` argument) is refused at the write, with the code and rule it had at the binding
before (B2 for a bare owner, R1, B7, B8, M1 or R3 for a lent place); the message names the binding and both repairs at it (`mut c = own place` for a bare owner,
`mut c = copy(place)`), and `mylang fix` writes the copy (`test/fixtures/fix-migration/written-through.my`). A move, a return
without `from` or a store of `c` keeps its refusal at the binding; a local assigned more than once keeps its refusals; `own`,
`copy(...)` and fresh initializers are owners as before. The ownership matrix moves 36 cells from refused to accepted (plan Part B,
H1).

### A comment edit replays a test entry's report (10 November 2026)

No source changes and nothing a test reports changes. An entry's stored report now reads each module source through the
new engine kind `module-tokens` (the source's tokens without comments, blank lines, trailing whitespace and line numbers)
instead of by its bytes, so after a comment edit or a line shift `mylang test` replays the report (`cache.reason`
`engine-report-hit`) instead of checking the entry again. Every other edit, and a comment in a module a printed diagnostic
names, checks again as before. The first run after the update records each report once more (the `test-report` kind's
identity moved); `MYLANG_TEST_TOKEN_REPORTS=0` reads every source by its bytes.

### A test run keys its lowering by the engine's checked-body parts (10 November 2026)

No source changes and nothing a test reports changes. A test run's key derivation keys each function's lowering by its
`module-check` part, as a build does, instead of hashing its tree; the check a directory's roots share now uses the work
directory's caches so that the engine decides it. The first run after the update lowers each function once more (its
lowering key moved); test keys and stored passes do not move. `cache.work.producer.lowering.by_part` counts the functions keyed
by a part; `MYLANG_ENGINE_DECIDE_LOWERING=0` keys them by their trees as before. A root's facts are read by group records of
about six functions each (`cache.work.producer.facts.groups`); the first run after the update reads each function's own record
once and records the groups, and `MYLANG_TEST_FACT_GROUPS=0` reads only the functions' own records.

### A directory run runs each test once (10 November 2026)

What `mylang test DIR` lists changes; no source changes, so no `mylang fix` migration is needed. A library's tests used to run,
and be listed, once for each root whose import closure reached the library. Now a source that declares tests belongs to the first
root in sorted path order whose closure holds it, and only that root runs its tests, so each test runs and is listed once (the
user's decision D1 of `docs/audits/test-loop-plan-2026-11-09.md`). A root still runs every test its own cases file names, which can
list such a test once more. A single-file run is unchanged and runs every test its closure declares.

A pass is now the test's, not its root's: the key of a passing test leaves out its entry's path, so a file run finds the
passes a directory run recorded, and the reverse. Every stored pass misses once after the update (the settings domain moved).

### The record a `from` function returns goes where the field it returns goes (10 November 2026)

Refusals turn into acceptances; nothing accepted before is refused, so no `mylang fix` migration is needed. A call whose result
borrows under a `from` contract and is a record (`first_of(shelf)` with `-> Item from shelf`) is now a source of a borrowed
record, a local list or dictionary of borrows, and a `const` option local, as the field it returns already was
(`docs/ownership-rules.md#b9--const-place-bindings-borrow`): `ItemBox(value=first_of(shelf))`, `append(mut items,
first_of(shelf))`, `table[k] = first_of(shelf)` and `const s: Item? = Some(first_of(shelf))` copy nothing, and a record of
such results returns under `from`. The owners are the call's sources, held until the last use. The escapes keep their
refusals. A text, bytes or list result is a view and stays refused there. The ownership matrix moves 4 cells from refused to
accepted (plan Part B, H3).

### `Some(place)` bound to a `const` local borrows the place (10 November 2026)

Refusals turn into acceptances; nothing accepted before is refused, so no `mylang fix` migration is needed. `const s: T? = Some(source)`
is now an option of a borrow when its payload is unboxed and `source` is a place, a bare owner, an `own` or `mut` parameter, or a plain
text, bytes or list parameter, as `Box(value=source)` already was a record of one (`docs/ownership-rules.md#b9--const-place-bindings-borrow`).
It copies nothing and holds the source's owner until its last use. Its escapes are refused where it goes, as a borrowed record's are: a store
into something that leaves, an `own` argument, a return without `from`, a change or move of the owner while it is live. The ownership matrix
moves 32 cells from refused to accepted (plan Part B, H2).

### One message for every refusal of the Escape rule (10 November 2026)

The text of a diagnostic changes; nothing else does, so no `mylang fix` migration is needed. Every refusal of the ownership model's
first rule (`docs/ownership-rules.md#rule-1-escape`: a lent value cannot be stored or given anywhere that outlives its lender)
now says the same four things in the same order, on one line: what is lent as the source spells it, who lends it, where the value
would outlive its lender or what the place it goes into needs, and the repairs. It covers `E_OWN_MARKER` (B2, B9, W2),
`E_SINGLE_OWNER_BORROW` (B7, B8, B9, R1, R3, R6, M1), `E_SLICE_ESCAPES` (V2, V4, V5, W4) and `E_BORROW_UNDECLARED` (R4):

```text
error[E_BORROW_UNDECLARED]: a bare `p` only lends the plain parameter `p`, and the returned value would keep it after the call returns; declare the result `from p`, or write `copy(p)` to keep both
error[E_SLICE_ESCAPES]: `data[0:2]` is lent by the local `data`, and the returned value would keep it after `data` ends; write `copy(data[0:2])` to keep both
```

The codes, the rule ids, the locations and the structured fixes are unchanged, and so is what each program is: the 1,775 programs of
the ownership matrix are accepted and refused as before, cell for cell. A repair the message names is the edit its fix makes.

Three more things change with it. A written `own` that takes nothing says what `own` gives and what the position needs:

```text
error[E_OWN_MARKER]: `own values` gives `values`, but this argument is only read; remove `own`
error[E_OWN_MARKER]: a return gives its value without `own`; remove `own`
error[E_OWN_MARKER]: a fresh value is already owned, so `own` adds nothing; remove `own`
```

The message that called a lent element or slice "a fresh value" no longer does. And `mylang reference --query CODE` names the
heading of the ownership reference that files each rule a code enforces, as in `ownership rules: Escape (B2, B9, W2)`; its JSON
record gains `rule_families`. A script or an editor that matches the old message text must match the code and the rule id instead.

### Collections of borrows: local lists and dictionaries of borrowed records and text (9 November 2026)

Refusals turn into acceptances; nothing accepted before is refused, so no `mylang fix` migration is needed. A local list or dictionary whose every
element store is a borrow now holds the borrows with no `copy(...)` (`docs/ownership-rules.md#collections-of-borrows`): a `mut` local made empty
(`[]`, `{}`), each `append`, `xs[i] = v` or `d[k] = v` storing a borrowed record, a place, `Some(place)`, `Some` of a borrowed record, `None` or a text literal; a list literal
of such values as a `const` or an argument built for one call; a borrowed record that lends one as a field.

The collection owns its buffer (a dictionary also its keys) and never its elements, and holds what they borrow until its last use. A function
that is refused for any reason is reported as it was before, every diagnostic, location and repair: a store, move or return of the collection
(even under `from`: a list returned under `from` stays a view of its sources), a `mut` out-parameter, a task, a mixed element, a write to a
source while the collection lives. Code changes only in functions that hold a collection of borrows.

### Every read-only place is a borrowed record source: dictionary, set, text, bytes and list parameters, and `Some(place)` (9 November 2026)

Refusals turn into acceptances; nothing accepted before is refused, so no `mylang fix` migration is needed. A borrowed record (a record whose managed fields all
borrow, `docs/ownership-rules.md#b9--const-place-bindings-borrow`) now also takes, with no `copy(...)`:
- a bare plain dictionary or set parameter, which is the caller's storage: `Table(counts=counts)` lends it, and `-> Table from counts` returns it;
- `Some(place)` of a field, an element or a dictionary value whose payload is not boxed: `Opt(ref=Some(owner.a))`;
- a bare plain text, bytes or list parameter. It arrives as a view, so the record holds a frame block: the caller's own text or list when the argument was a whole
  value, else one copy per call, made the first time the call builds such a record and freed when it returns. A bytes argument (bytes carry no owner) and a slice
  are copied this way; `--stats` prints how many sites can copy. A record that holds a frame block never leaves its call: returning it, even under `from`, keeps
  its old refusal.

Every other escape (a store, an append, a `mut` out-parameter, a move, a task, a return without `from`, a write to an owner while the record is live) keeps the
diagnostic, location and repair it had before. The netlisp port's F-PA-1 record (`IslandAnchorInputs`: a bytes, a list and three dictionary parameters) needs no `copy(...)`; its bytes field is copied once
per call that builds it.

### `symlink_path` and `Stat.changed`: creating a symbolic link, and the status-change time (8 November 2026)

New builtins and a new `Stat` field; nothing that was accepted changes, so no `mylang fix` migration is needed. The Filesystem capability could not create a symbolic link, so the
netlisp port's two symlink-containment tests could not build their tree (F-S1B-A-206), and `Stat` had no status-change time, so a file digest compared less than the Zig
did (F-S1B-A-400). `symlink_path(fs, target, path)` (and the method `fs.symlink_path(target, path)` and `filesystem.symlink(fs, target, path)`, `Unit fails str`) creates the link `path`
holding the text `target`, written target first as `ln -s TARGET LINK` and Zig's `symLink` take it. It is a write like the others: write authority, a path inside the granted directory with no `.` or
`..` component, a free name and an existing directory that holds no link, with the real wording of each refusal; the target (1 to 4094 octets, no NUL) is stored as written and not checked, since
`canonical_path` and `stat_follow_path`, the only calls that follow a link under a grant, already confine what they follow. `Stat.changed` (default `0`) is `st_ctim` in nanoseconds, a sixth word
of `stat_path`'s answer (48 octets now): the kernel moves it for any change, `set_modified` included, which is what a tool that remembers a file needs. The in-memory filesystem a test
receives makes both too: a link is an entry with its target text, mode `0777` and a size of that text's length, only `realpath` and `stat_follow` follow it and only inside the filesystem (an
absolute target, `..` past the root and more than 40 links are refused as under a grant), every other call refuses a link on the way or a read, a write or a lock of one with the wording the
real provider gives, and `changed` is the logical clock's reading for a call that writes and one nanosecond past the last change for `chmod` and `set_modified`, which leave the clock where it is.
`docs/io.md#real-paths-permissions-and-times`.

### `mylang fix FILE` repairs a module or a test file alone; `--imports` repairs its imports too (8 November 2026)

A tooling change, not a refusal of code, so no `mylang fix` migration applies to it. `mylang fix src/render_json.my` used to rewrite every module the file imports
(53 edits in 7 files from one file, 174 in 27 files from a test file that imports four modules), and a lane that ran it had to restore the files it did not own
(F-S1B-A-106, -210, C-102, -201: four entries, two lanes, each twice). Now a file that does not declare `main` (a module or a `*_test.my` file) is repaired by the
fixes whose edits all lie in it; a fix with an edit in another file waits, whole, and the last line names how many waited and where: `fix: left 3 fixes in 2 other files that
src/render_json.my imports; `mylang fix --imports src/render_json.my` repairs them too`. `--imports` is the former behavior. The program entry (the file that declares
`main`) still repairs the program it builds, and a directory still repairs every file beneath it, so `mylang fix main.my` and the migration corpus run as before.
`docs/tooling/fix.md#mylang-fix`.

### `case_name`, `Kind.cases()` and `Kind.from_name(text)`: the names of an enum's cases (8 November 2026)

New builtins; nothing that was accepted changes, so no `mylang fix` migration is needed (a `cases` or `from_name` that an enum already declared as a case keeps its
meaning, and a function or local named `case_name` hides the prelude name). The Selka port of the netlisp Zig program kept a hand-written `match` over every case for Zig's
`@tagName` (about 20 sites, one of 59 cases), a list written out by hand for `std.enums.values` and a chain of `if text == b"..."` for `std.meta.stringToEnum`
(F-S1B-A-103, -201, B2-2, C-104, C-106). `case_name(value)` is the declared name of the case an enum or tagged enum value holds, as a `str` (`case_name(Cooling.fan)` is
`"fan"`; a payload is ignored). `Kind.cases()` is the list of every case of an enum none of whose cases carries a payload, in declaration order, and `Kind.from_name(text)`
is `Some(case)` for the case a `str` or `bytes` name spells and `None` for any other text. The first is a prelude function because its operand carries the type, the other two
are calls on the enum type, which is where `Kind.case` already stands and keeps a call free of the explicit-type-argument form. `str(value)` of an enum is still
`E_TEXT_CONVERSION`: printing writes `Kind.case`, and `case_name` the bare identifier. A name that no identifier can spell (Zig's `@"power-budget"`) is not a case name,
and `Kind.from_name` does not read it. A non-enum operand, a `cases` or `from_name` of an enum with a payload, and a wrong arity report `E_ENUM_CASES` or `E_ARITY`.
`docs/records-and-unions.md#case-names`.

### A ReleaseSafe compiler refuses to start (8 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. A `mylang` built with `-Doptimize=ReleaseSafe` spun at 100% CPU the first time it read a
file to its end through a standard-library reader (`/proc/meminfo` when a build sized its work, `/proc/PID/stat` when a test run took its lock), about 570,000 `preadv` calls in 8 seconds:
the reader's loop never sees the empty read that ends the file, and the reader is used throughout the compiler, so no one call site can be mended. It now exits 2 at once with a message that
names the mode and the two that work (`-Doptimize=ReleaseFast`, the installed compiler, and the default Debug).

### A command that runs out of memory names the ceiling, not a host failure (8 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. `check`, `check-project` and the other commands the front end runs printed
`mylang: host failure: OutOfMemory` when the compiler reached its own address-space ceiling (`MYLANG_HOST_MEMORY_LIMIT`, 8 GiB by default); they now print the same message
`build`, `run` and `test` did: `mylang: out of memory: the compiler reached its own memory ceiling of ...; raise MYLANG_HOST_MEMORY_LIMIT ... or set it to 0`. The exit status is still 2.

### `build`, `run` and `test` leave out the `W_COPY_MOVE` hints (8 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. `W_COPY_MOVE` is advice that a move could replace a copy; it never carries a repair
and never fails a build, and the netlisp port drew about 450 lines of it on every build. `build`, `run`, `run-project` and `test` now print none and count none in the closing
`warnings:` line; `check`, `check-project`, `check-module` and `lint` are unchanged, and `--warnings`, `MYLANG_WARNINGS=all` and `--diagnostics=json` bring the hints back to a build. `docs/tooling/native-build.md#warnings-in-the-output`.

### A borrowed record may hold `Some(...)` of a read-only parameter (8 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. A record built from borrows (6 November) may also hold `None` beside its
borrows and `Some(p)` of a plain record parameter (not `own`, not `mut`): `walk(Scope(block=sb.block, name=sb.name, parent=Some(scope)), mut out)` and
`Scope(block=block)` with a defaulted `parent: Scope? = None` were `E_SINGLE_OWNER_BORROW` or `E_OWN_MARKER` and now borrow. A recursive field's box is a slot of the
call that made it (`box_frame` in Core IR), written once when the call starts; a value holding its own call's frame box is refused as a return, even under `from`
(`E_SINGLE_OWNER_BORROW`, R4), while a box an ancestor made is returned `from` the parameter that holds it. Every other escape keeps the refusal it had. The new warning
`W_COPY_IN_RECURSION` names a copy of a function's context passed into its own recursive call, and its fix deletes the record's copies where the record then borrows.
`docs/ownership-rules.md#borrowed-parents`, `docs/tooling/lint.md#copies-in-recursion`.

### `replace_file_synced`, an atomic write that syncs the file and not the directory (8 November 2026)

New builtins; nothing that was accepted changes, so no `mylang fix` migration is needed. `replace_file_synced(fs, path, data)` and `replace_file_synced_mode(fs, path, data, mode)`
publish a file the way `atomic_write_file[_mode]` and `replace_file[_mode]` do (a temporary beside the destination, renamed over it, so a reader sees the old file or the new one
whole) and force the file to disk before the rename but not the directory after it: one `fsync` where `atomic_write_file` makes two and `replace_file` none (50 rewrites took 194 to 228 ms,
against 382 to 409 and 5 to 12 on this ext4 disk on 8 November). After a power loss the old file or the complete new one is there; the rename itself may be lost. The mode rule, the
refusals and the `replace 'path': reason` text are `replace_file`'s, and the in-memory filesystem answers both. The other calls are unchanged;
`docs/io.md#replacing-a-file-without-forcing-it-to-disk` says which to use.

### `hashes.sha256` runs in the runtime; `data.sha256()` answers the raw digest (8 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed; `hashes.sha256(data)` keeps its signature and its
answer (64 lowercase hexadecimal digits). It was Selka code at about 250 MB/s and is now the C runtime's SHA-256, which reads the octets of
`data` in place and uses the x86 SHA extensions when the CPU has them (chosen when the first hash runs), portable C otherwise; both give
the same digest, about 2 GB/s (8.5 times the old speed) on a SHA-NI CPU and about 340 MB/s without. The new builtin method `data.sha256()` (also `text.sha256()`, over
the UTF-8 octets) answers the 32 raw octets as `bytes`, as `blake3()` does. `docs/standard-library.md#hashes`,
`experiments/native-sha256-20261108/REPORT.md`.

### The copy warnings point at the zero-copy form (7 November 2026)

A project that treats warnings as errors (`"warnings": "deny"`) sees more of them. `mylang fix` writes every `W_NEEDLESS_COPY` repair, so
a run of it clears them; the report-only `W_COPY_MOVE` has no `fix` and never fails a build (zero-copy part 4). `W_NEEDLESS_COPY` now finds a
copy of a value that is already new (a module constant, a fresh call result), a copy of a borrowed value in a read-only position (a
call's borrowed result, an option's default, an argument of a call through a function value), a `const` that copies a whole local it
owns, and the moves: `own row.name` for a field of a local nothing reads again, `own payload` for the payload of a match that
consumes a fresh result, `take(mut row.name)` for a field or element of a `mut` local or parameter, and `for x in own xs` with `own x`
for a list a loop copies out and nothing else reads. `W_COPY_MOVE` (`L_COPY_MOVE`, report only) names the form where the rewrite is
more than the checker can make: `take` on a `const` local, `options.take_or`, a consuming loop over a plain parameter or a field, and
a `from` clause for a function whose every return copies a place of one parameter. `L_COPY_IN_LOOP` names the form that fits where
the copy goes (a borrow, a move, a `spans.Span`, a `symbols` key, or a real transfer) with a link to its section in one line.
`docs/tooling/lint.md#moves-instead-of-copies`.

### Checker precision: narrowed options, loop variables, scalar match arms, slices of views, borrowing `mut` locals (7 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed; each change accepts correct code that
needed a copy or a restructure, and none costs anything at run time (zero-copy part 1). After `if x is None: return` (or `fail`,
`break`, `continue`), `x.unwrap_or(d)` and other reads of `x` borrow its payload in place (F-RA-204, -308, -400, F-RC-4). A loop
variable names an element of the iterated place, so a `mut` argument naming another field of its record is disjoint, also for
nested loops and repeated calls; the lowering reads the variable again after each write (F-RA-610, F-RC-204). A `match` arm whose
payload is a number or flag may change the place it matched (F-RC-110, F-RA-401). A slice of a text, bytes or list view binding is a
view (F-RA-300, F-RC-103, -203, F-RA-403). A `mut` local that borrows may also take a borrowed call result, and a literal beside
borrows of the caller's storage (F-RA-303, -311, -214, F-RC-120, -307). `docs/ownership-rules.md#b9--const-place-bindings-borrow`.

### `check` and `build` agree on the G3 redo's five shapes; a Z3 refusal names its statement (7 November 2026)

Four shapes `check` accepted and `build` refused with `E_CORE_UNSUPPORTED` (rule Z3) now build: two `mut` arguments that are disjoint fields of one record at different
depths (`handle(mut ctx.notes, mut ctx.block.rules)`, F-RA-710), a call lending a record and its nested field followed by a write to a sibling field (F-RA-14),
`sets.discard` and `dicts.pop_default` on a field of a `mut` record (F-RA-807), and a borrowed result of a `mut` parameter the function also writes
(`-> Entry? from self` after `self.index += 1`, F-RA-115). Two that never built are now refused by `check` with the diagnostic `build` gives; nothing that built
becomes a diagnostic, so no `mylang fix` migration is needed. A record built from a payload bound out of a borrowed text, bytes or list result
(`if text_a(node) is Some(design): Entry(design=design)`, F-RA-202) is `E_SINGLE_OWNER_BORROW`, as for any view. A function that fails with a managed error and returns
a borrow of its `mut` parameter is `E_CORE_UNSUPPORTED` (Z3) at its `from` name. A Z3 refusal now reports the call or store it could not place, at its line, with the
two places involved (`docs/ownership-rules.md#z3--build-time-ownership-limits`).

### A `Stream` field is printed as the field (7 November 2026)

Nothing that was accepted is refused, so no `mylang fix` migration is needed. `print(ctx.err, text)`, `write(sink.stream, data)` and `flush(self.log.stream)` were
`E_OUTPUT_CAPABILITY` ("print needs a Stream; add `out: Stream` to this function and pass one from main", advice that was wrong: the value is a Stream) and needed
`const err = ctx.err` first. The first argument of the three stream-first functions may now be a name followed by field names; it is checked as an expression, and one that
is not a `Stream` gets the same diagnostic as before. Binding the field first still works. `docs/io.md#stream`.

### `check-module FILE` counts the holes of other modules on one line, and a hole no longer hides the rest of its module (7 November 2026)

Output only; a program that checked still checks, so no `mylang fix` migration is needed. `check-module FILE` printed every `E_TYPED_HOLE` of every module FILE reaches (473 lines
for one file of the redo skeleton, burying the file's own errors). It now prints the holes of FILE in full, with FILE's other errors, and the others as one line,
`note: 473 typed holes in 41 other modules (check DIR lists them)`. Text only: `--diagnostics=json`, `check FILE` and `check DIR` list every hole, and the exit status is unchanged.
A check that a hole refuses ran no later pass, so an unread capability parameter (`E_UNUSED_CAPABILITY`) and the module's warnings stayed hidden until the last hole was filled;
the check that keeps the holes as traps (for the ownership errors it already reported) now also contributes the errors and warnings it found. `docs/typed-holes.md#checking-one-file-of-a-skeleton`.

### `--release` refuses only the typed holes `main` can reach (7 November 2026)

A program that was refused now builds, so no `mylang fix` migration is needed; nothing that was accepted is refused. `mylang build --release` and `mylang run --release`
refused a `todo[T]()` hole anywhere in the modules a program imports (897 errors for a skeleton whose stubs `main` never calls). They now check with holes kept as traps, as
a debug build does, and refuse after lowering: the build lowers only the functions `main` can reach, a function value counting as a call, so a hole left in a built function
is reachable. The refusal is `E_TYPED_HOLE` at the hole, naming the function, and no executable is written; a hole in a function nothing reaches is built as the
`R_TYPED_HOLE` trap a debug build has. `check` is unchanged. `docs/typed-holes.md#release-builds`; the CLI tests build with `--release`, so they run under `-Dtest-release=true`.

### A type cannot be named like a builtin type (7 November 2026)

A declaration that was accepted becomes a diagnostic, with its `mylang fix` repair. A record, enum, union, domain, resource or alias named `Unit`, `int` or another plain-name spelling
`typed.Type.fromName` resolves (the integer widths and `bool` are reserved words and were always refused) was declared without complaint and then could be neither built nor read in its own module (`E_SYMBOL_KIND`, `E_TYPE`: the builtin won the lookup);
three ports declared a `Unit` because the Zig does. It is now `E_BUILTIN_TYPE_NAME` at the name. `mylang fix` renames the type to the module's name and the builtin's (`ShapeUnit`;
a digit is added if that is taken) and every qualified reference to it (`shape.Unit`, `sh.Unit`) in the modules that import it, which is every use a program that checked can have: a
bare `Unit` in the declaring module meant the builtin and stays, unless the module builds or reads the type itself (`Unit(number=1)`, `Unit.case`), which the builtin cannot do: then
it never checked, the module plainly means its own type, and every bare `Unit` in it is renamed too. A module the fix cannot read gets the diagnostic without an edit. The names of prelude library types (`Stream`,
`Option`) are not builtin and stay declarable. `test/fixtures/fix-migration/builtin-type-name/`, beside `FIX-MIGRATION-1`; `docs/records-and-unions.md#type-names-the-language-already-uses`.

### A record field may default to a bytes literal or a module constant, and a required field may follow a defaulted one (7 November 2026)

One accepted program shape becomes a diagnostic, with its certain `mylang fix` repair (below). Everything else that checked before still checks, and means what it meant.

- **More defaults.** After `=` a record field may now be a non-empty bytes literal (`net: bytes = b"GND"`), a module constant of the record's module or an imported one
  (`limit: int = LIMIT`, `shape: bytes = limits.SHAPE`), or the negation of a constant (`below: int = -LIMIT`). A `float` module constant may hold NaN and the infinities
  (`const NAN: float = 0.0 / 0.0`), so those are field defaults too; a call such as `math.nan()` is still a call and is `E_DEFAULT_ARGUMENT`. The default is checked where
  its record is declared, with no local of the constructing function in scope (it used to read a local named like the constant, or like an enum, in the constructing function),
  and a private constant needs no import: a text or bytes constant is read as the literal it holds. A literal or constant default is static data, so reading it allocates
  nothing; the guest test counts the allocations of a loop of constructions. A non-empty list or dictionary, a call and a function used as a value stay refused.
- **Order.** A record is built by field name, so a required field may follow a defaulted one; `E_DEFAULT_ARGUMENT` "required fields must precede fields with defaults" is gone for
  records. A function's parameters and a variant case's fields keep the rule.
- **The one new refusal, with its fix.** A default that builds a record without one of that record's required fields (`inner: Inner = Inner()` where `Inner` has a field
  with no default) is `E_INCOMPLETE_CONSTRUCTION` at the declaration; it used to be reported only where something first built the outer record, or never. Such a default was
  never usable, since every construction that left the field out was refused. `mylang fix` deletes ` = Inner()`, which makes the field required and changes no program that
  checked. `test/fixtures/fix-migration/unbuildable-default/`, beside `FIX-MIGRATION-1`.
- `docs/records-and-unions.md#constant-defaults`, `tests/lang/record_constant_defaults.my`.

### `spans` and `symbols`: long-lived data holds a key (7 November 2026)

Two new standard modules (the thirty-seventh and thirty-eighth); nothing that was accepted changes, so no `mylang fix` migration is needed. `spans.Sources` is a table of the text of
every file a program reads, kept for as long as the table lives, and a `spans.Span` (file, start, length) names a piece of it: long-lived structures such as tokens, tree nodes and
model records point into the source without copying its text, and `spans.text(sources, span)` reads it back as a borrowed view. `symbols.Table` interns a name once and answers a
`Symbol`, one integer that is compared with `==` and keys a dictionary. `docs/value-semantics.md#long-lived-data-hold-the-key-not-the-borrow` teaches the cache idiom: the filling call
answers a key and the caller reads the entry in place after later `mut` calls.

### `byte_format`, a standard module: formatted appends for byte builders (7 November 2026)

New standard module (the thirty-sixth); nothing that was accepted changes, so no `mylang fix` migration is needed. `byte_format.shortest(mut w, x)` and `decimal(mut w, x, decimals)`
append what Zig's `{d}` and `{d:.N}` print for a float (checked against 294 values captured from the pinned Zig toolchain), and `byte_format.format(mut w, template, numbers)` with
`format1`, `format2` and `format3` (one, two or three texts) write a template whose `{d}`, `{d:.N}` and `{s}` placeholders take numbers and borrowed texts, so the run of literal
and number appends that a Zig `w.print` becomes is one call. A template that does not fit its arguments traps `R_ASSERT` naming the octet. `docs/standard-library.md#byte_format`.

### `replace_file`, an atomic write that does not synchronize (7 November 2026)

New builtins; nothing that was accepted changes, so no `mylang fix` migration is needed. `replace_file(fs, path, data)` and `replace_file_mode(fs, path, data, mode)` publish a
file the way `atomic_write_file[_mode]` does (a temporary beside the destination, renamed over it, so a reader sees the old file or the new one whole) but force neither the
file nor the directory to disk, as Zig's `AtomicFile` does. A small write is well under a millisecond where the durable call took about 40 ms on ext4 (two `fsync`s). The durable
calls are unchanged; `docs/io.md#replacing-a-file-without-forcing-it-to-disk` says which to use.

### `filesystem.list_entries`, and a stat that costs one system call (7 November 2026)

New library function and a faster stat; nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. `filesystem.list_entries(fs, path)` lists a
directory with each entry's kind (`Regular`, `Directory`, `Symlink`, `Other`) from the directory record, so a walk no longer `stat`s every entry; the builtin underneath is
`list_entries_path(fs, path)`, and `filesystem.memory()` answers both. `stat_path` and `filesystem.stat` are one `fstatat` without a restriction (three to five calls before) and
at most an `openat2` and a `close` more under a grant (up to thirteen before); a directory on the way needs search permission only. `list_directory` and the new listing open
the directory with one `openat` the same way, and say `is not a directory` for a file, as `listdir` does. `docs/io.md#listings-with-entry-kinds`.

### `listdir` and `list_directory` list a directory of any size (7 November 2026)

A bug fix; nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. `fs.listdir(path)` on a directory of more than 256 entries (and on a
`filesystem.memory()` one) answered `denied: outside the granted directories, or the mode needs a write grant` with every grant given: a fixed 256-entry, 64 KiB snapshot
in the runtime. The cap is gone and the snapshot grows with the directory. `list_directory(fs, path, max_entries)` no longer limits `max_entries` to 4,096: the bound is the
caller's, and a directory over it is refused as `directory listing 'p': has more than N entries (the max_entries bound)` (a negative bound as `max_entries must not be
negative`), never as a grant refusal. A listing over its bound no longer falls through to the next granted root. `docs/io.md#large-directories-and-listing-bounds`.

### `check` refuses a typed hole after a debug build (7 November 2026)

A bug fix; nothing that was accepted by design becomes a diagnostic, so no `mylang fix` migration is needed. After a debug build, `run` or `test` of a program with a
`todo[T]()` hole, a later `mylang check` of the same program printed `check: ok`, in the same work directory and, through the shared compiler store, in a new one. The
check summary the debug command published stood in the body that held the hole. A body that holds a hole is now never stood in, so `check` reports `E_TYPED_HOLE` again,
and a check that refused a hole still leaves the next build compiling it as a trap. `docs/typed-holes.md`, `docs/tooling/caches.md#check-summaries`.

### A record built from borrows is a borrowed value (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. A record constructor whose managed fields all read places without `own` (a field,
an element or a dictionary value of a named binding, a bare owner, `own` or `mut` parameter, loop variable or record binding, a nested such record, or a text or bytes
literal beside them) copies and moves nothing: `rail_pin(mut self, RailSpot(net=b.power, x=1))` and `const spot = Spot(net=bank.gnd, x=0)` were `E_SINGLE_OWNER_BORROW` or
`E_OWN_MARKER` and now borrow. The record may be a read-only call argument, a `const` local, a `mut` local whose every assignment borrows, or a result under `from`; its loans
are its fields' owners, held to its last use. Storing it in a list or an owned field, moving it, changing it, returning it without `from`, submitting it to a task, a change
of an owner while it is live, a plain text, bytes or list parameter as a field (a view), and a record mixing a borrow with a fresh value stay refused with the diagnostic and
repair they had before. `mylang fix` on code written before this change still writes the markers it wrote, except where a constructor now borrows: `const kept = Box(items=source)`
is left as written. `docs/ownership-rules.md#b9--const-place-bindings-borrow`.

### The consuming loop `for x in own xs:` (6 November 2026)

New syntax; nothing that was accepted changes (`for x in own xs:` was `E_OWN_MARKER`). The loop takes the list an owned local or `own` parameter holds and gives each element to `x` as
its owner, in order and with no copy, so `append(mut out, own x)` and stores need no `copy(x)`. An element the body does not move is dropped at the end of its iteration; `break`,
`return` and `fail` drop the rest. The list's name is moved from the loop on (`E_SINGLE_OWNER_MOVED`). A `mut` or borrowed list, a field, a call result, a dictionary and two
names are `E_ITERATION`. `docs/value-semantics.md#consuming-a-list-in-a-loop`.

### `lists.extend_own(mut values, own other)` (6 November 2026)

A new standard-library function; nothing that was accepted changes. It moves every element of `other` to the end of `values`, in order, copying none, and frees the emptied
`other`; `lists.extend` still copies. `docs/standard-library.md#lists`.

### A `from` accessor may return `[]` (6 November 2026)

Nothing that was accepted becomes a diagnostic. A `from` function may return the empty list literal `[]` beside its borrows, as it may return `None` or `""`; it was `E_BORROW_MIXED`.
The result is a view of the runtime's static empty list, so the call allocates nothing and the result owns nothing. A non-empty literal or a named list stays a new value (`E_BORROW_MIXED`).
`docs/ownership-rules.md#r5--one-kind-of-return`. With lane O's literal defaults (4c), `[]` is a static default too: `r.items.unwrap_or([])` and `dicts.get(d, k, [])`
borrow only their option or dictionary, so a `from` accessor returns them.

### `take` and `exchange` reach list elements, `match mut` bindings and records (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed.

- **The place may be a list element** (`take(mut rows[i])`, `exchange(mut blocks[i].items, [])`, `take(mut grid[i][j])`) or a `match mut` payload binding and its fields
  (`take(mut payload.holds)`, which failed with `E_CORE_UNSUPPORTED`). The element is moved out and the replacement stored back without a copy, as `rows.exchange(i, v)` does.
- **`exchange` takes any type** (a record, a union, a scalar) but a resource, a capability, a file or a pending result. **`take` takes a record whose fields all have defaults** and
  leaves the record those defaults build; a type with no default is `E_TAKE_TYPE`, whose message names the `exchange` to write instead.
- A dictionary value (`take(mut d[k])`), an octet of text and a call result stay refused (`E_ASSIGNMENT_TARGET`). `docs/value-semantics.md#taking-and-exchanging-a-value`.
- **A writer's argument may write another field of the writer's receiver's record**: `append(mut e.stack, exchange(mut e.block, B()))` and `append(mut e.stack, f(mut e.block))`
  were `E_SINGLE_OWNER_OVERLAP` (R2) and are accepted. The owner passed whole, the receiver itself and two elements of one list stay refused. A field of a `take` or `exchange`
  result is read from the moved value (`len(take(mut b.block).items)`).

### `W_NEEDLESS_COPY` writes `own value` for a copy of an owned local at its last use (6 November 2026)

Nothing that was accepted becomes a diagnostic; there is a new warning with a certain fix, so `mylang fix` removes the
copies. A copy of an owned local or an `own` parameter at its last use, in a position that takes the value over
(`append(mut out, copy(name))`, `d[copy(key)] = v`, `sets.add(mut s, copy(key))`, `Some(copy(net))`,
`Box(name=copy(name))`, `[copy(x)]`, an `own` argument, an assignment, `return copy(x)`), is now `W_NEEDLESS_COPY` with
the edit `own name` (a bare `name` when returned). The copies a move would break stay silent: in a generic instance, in
a loop the value was not declared in, beside another read of it in the statement, inside a match or a condition that
reads it, and while an alias or a view of it is live (a `mut` local that borrows it, 4f, included). A concatenation or
an f-string result now counts as an owned value for every case of the warning. See `docs/tooling/lint.md#needless-copies`.

### A literal default borrows nothing: `from` accessors may return `unwrap_or(b"")`; `options.take_or` (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed.

- **A literal default is static.** `r.name.unwrap_or(b"")` and `dicts.get(d, key, "none")` were refused in a `-> bytes from
  r` accessor (`E_SINGLE_OWNER_BORROW`, R6) because the default counted as a temporary owner. A text or bytes literal, a
  number, a bool and `None` are static constants with no owner, so the selection borrows only its option or dictionary:
  the accessor returns it under `from r`, and a `const` of it holds only `r`. A default that is not a literal still adds
  its owner, and an empty list `[]` is not yet a static default. The lowering already chose the immortal constant, so the
  certificate validator and the Lean proof are unchanged.
- **`options`, a new standard module** (the thirty-fifth): `options.take_or(own value, own default)` consumes an owned
  option (`match own`) and returns its payload, or the default, without a copy; the other value is dropped. See
  `docs/standard-library.md#options`.

### A `mut` local whose every assignment reads a place borrows it (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. Before, `mut net = port.name` was
refused (a move out of a borrowed record, or a move that needs `own`), so a default chosen by a condition was written
`mut net = copy(port.name)` then `if ...: net = copy(port.net)`, because conditional expressions are retired.

- **What is new.** A declared `mut` local that is stored more than once, and whose every store, its initializer and each
  assignment, is an unmarked read of a named place, holds a borrow, as a `const` of a place does (B9). A `mut` local stored
  once keeps its old diagnostics (write `const`). `mut net = port.name` then `if len(port.net) > 0: net =
  port.net` copies nothing, in branches and in loops (`mut best = b.title` then `best = p.name` for a longer name, or a
  running minimum `mut low = xs[0]` then `low = xs[i]`). The
  lowering gives the local the `const` borrow's representation (`build_const_borrow.zig`), and a join is a borrowed phi of
  its operands' views, so the certificate validator and the Lean proof are unchanged.
- **Still refused.** A change of any owner the local borrows while it is live (the local's loans are the union of every
  assignment's places, held to its last use, and a loop body that assigns it is checked again from the joined state, so a
  change before the assignment in the next iteration is caught); a change, move or store of the local; a return without
  a `from` contract; and a borrow of an owner a loop makes again in each iteration while the local lives past the loop. Such
  a refusal is reported as before this change, at the store that needs `copy(...)` with its certain repair, so
  `mylang fix` moves the program to a clean check. A program that changed such a local was refused before too.

### `match own name:` consumes a named owner, and `own payload.field` takes a field of an owned payload (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. `match own s` was refused for every
value but a resource (`E_OWN_MARKER`, W2), and `own payload.field` was refused even on the payload of a matched temporary.

- **What is new.** `match own s:` on an owned local or an `own` parameter moves `s` into the match, as matching a fresh call
  result does: each payload binding owns its value and may be moved, stored or returned with no `copy`, and
  `own payload.field` takes one field and drops the rest, as from an owned record (B8). The same field move now works on the
  payload of a matched temporary (`match make(): case account(value=p): return own p.holds`). The lowering is the existing
  temporary-scrutinee path, so the ownership certificate and its validator are unchanged.
- **Still refused.** A borrowed parameter or local, a `mut` parameter, a field or element place and `match mut own` keep
  `E_OWN_MARKER` (W2) and its certain fix, the removal of the marker, with a message that names the case. A use after the
  match is `E_SINGLE_OWNER_MOVED`, and a match while a borrow of the owner is live `E_SINGLE_OWNER_OVERLAP`. See
  `docs/match-expressions.md#consuming-matches`.

### A scripted Process for tests, and `process.executable_path` (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. A test with a `proc: Process` parameter used to become a property test and fail with "a Host capability is
never handed to a test"; it now runs, and `process.run` on its `Process` fails `no rule` unless the test scripts one.

- **A test's `proc: Process` parameter is a scripted Process with an empty script.** It needs no `--allow-process`, starts nothing (D6: no real child process in `mylang test`), and the test
  stays cacheable, because the script is program text. `process.scripted(own rules: Rule[]) -> Process` builds one anywhere; `process.expect(proc, rule)` adds a rule; `process.calls(proc)`
  returns the requests (with directory, input, environment and limit), answered or not, oldest first. `process.run` on one logs the request and the first covering rule answers:
  `Rule(program, reply, args=None, times=None)`, `args` a prefix of the arguments after the program, `reply` a `Reply` (`Exit(output)`, `Missing`, `Refused(message)`), `times` a use count.
  No rule: `Error.Failed("scripted Process has no rule for ['git', 'status']")`. `process.exited(code, stdout, stderr)` builds the `Output`. `docs/io.md#testing-code-that-runs-programs`.
- **`process.executable_path(proc) -> str fails str`** (D3) answers the running program's absolute path (`/proc/self/exe`); a scripted Process answers `process.SCRIPTED_EXECUTABLE_PATH`
  (`/scripted/program`).
- **New builtin `process_control(proc, data, op)`** is the channel the module uses to read and write a scripted Process's two byte strings (script and log); a program uses the `process`
  functions instead, as it uses `process.run` for `run_process`. **`__stand_in[Process](script)`** is reserved to the standard library like the other stand-ins.

### The test filesystem supports the durable family (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. What changes is that calls which always failed on the filesystem a test receives now work, so a
test that pinned the refusal changes (the four in `tests/lang/filesystem_paths.my`, and `test_memory_provider_cannot_claim_durability` in `tests/lang/application_cache.my`, now
`test_memory_provider_publishes_reads_and_syncs`).

- **`filesystem.memory()`, and so a test's `fs: Filesystem`, is durable.** `atomic_write_file[_mode]`, `rename_path` (a file replaces a file, a directory moves with its contents),
  `stat_path` and `stat_follow_path`, `sync_directory`, `canonical_path`, `chmod_path`, `touch_path`, `set_modified_path`, `read_regular_file`, `list_directory` and the three locks
  answer from the stand-in's entries. The port's `infra.atomic_write` can call the shipped path in its tests instead of a plain write. An embedding provider that cannot promise
  durability still refuses with `durable native filesystem provider is unavailable`.
- **Deterministic, no flag.** A file is `0644`, a directory `0755`; inodes count up from 2 (the root is 1), a rename keeps the inode and a replaced file gets a new one; `Stat.modified`
  reads a logical clock that starts at 946684800 s and moves one second per call that changes the filesystem, so no test sleeps. There are no symbolic links and no umask. A test file
  that uses these calls is served from the test cache on a rerun. `docs/io.md#the-durable-calls-on-a-tests-filesystem`.
- **Locks** are `File` resources whose release frees the lock: on `return`, `fail` and when the `with` block falls through. `try_lock_file` and a second `lock_directory` on a held path
  fail with `: the lock is held by another holder` (`filesystem.is_lock_busy` stays true); `lock_file` on a held path fails at once with `: the lock is held (a stand-in cannot wait)`.
- **The real `lock_directory` now says the same.** A directory lease held by another holder failed with the generic `failed: the path does not exist or could not be used`; it now fails
  with the busy text a file lock gives, so `is_lock_busy` recognizes it.

### The embedded standard library is outside a project's per-file byte budget (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed: the change only admits projects that were refused.

- **`budgets.max_file_bytes` bounds the project's own files** (and the files it embeds), not the compiler's embedded standard library. Before, a `mylang.json` that set `max_file_bytes` below
  95,604 could no longer `import math`, nor `strings`, which imports it (`E_PROJECT_BYTES`), because `math.my` had grown past a small budget. A standard module is no longer refused by the
  per-file budget. It still counts toward `max_total_bytes` (the library is part of what a project loads; `STANDARD-MODULES-2`), and a refusal for the total names that budget. A project file over
  the per-file budget is refused as before.
- The fixture `tests/fixtures/module_projects/mylang.json` has its 65,536-byte budget back.

### `list + list` builds a new list; `bytes.replace` (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed: `list + list` was `E_TEXT_OPERATOR` and `bytes.replace` did not exist.

- **`left + right` on two lists of one element type** is a new list holding copies of the elements of `left`, then of `right` (G32), as `"ab" + "cd"` is new text. Both operands
  are evaluated once, left first, and neither changes; a managed element (`str`, a record, a nested list) is copied. Two lists of different element types are `E_TYPE`, and `-`, `*`
  and the orderings stay `E_TEXT_OPERATOR`. A generic function body still cannot add two `T[]` values (the message says so and names `lists.extend` on a copy).
  `values += other` was already `extend`. `docs/managed-memory.md#concatenating-lists`.
- **`bytes.replace(data, old, new)`** replaces every non-overlapping occurrence of `old`, from the front, as `strings.replace` does for `str` (G31). An empty `old` traps with
  `R_EMPTY_SEPARATOR`, as `split` does. `docs/bytes.md#splitting-and-joining`.

### The rest of Zig-exact math: `ln`, `atan`, `acos`, `asin`, `tan`, `expm1`, `sinh`, `cosh`, `tanh`, `cbrt`; `sin` and `cos` change in place (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. What changes is the value of `math.sin` and `math.cos`, by one unit in the last place for
about 3% of the arguments, and that is the point.

- **New.** `math.ln`, `math.atan`, `math.acos`, `math.asin`, `math.tan`, `math.expm1`, `math.sinh`, `math.cosh`, `math.tanh` and `math.cbrt` (binary64) answer the bits of Zig's
  `@log`, `std.math.atan`, `acos`, `asin`, `@tan`, `std.math.expm1`, `sinh`, `cosh`, `tanh` and `cbrt`. None of these names existed in `math`, so no program changes meaning.
- **Changed in place.** `math.sin` and `math.cos` were evaluated by the C library (`__float_sin`, `__float_cos`), whose results differ from Zig's `@sin` and `@cos` in the last bit for
  3.1% of 200,000 arguments. They now follow Zig's routines (compiler_rt `sin_f64` and `cos_f64` with the `__sin` and `__cos` kernels and the `rem_pio2` reduction, Payne-Hanek included, so
  no finite argument traps). A program that pinned a libm result of `sin` or `cos` to the last digit changes by one ulp for about 3% of its arguments; `tests/lang/math_trig.my`
  pinned none (it compares within 1e-15), so nothing there moved. The intrinsics `__float_sin` and `__float_cos` stay in the compiler and no standard-library source calls them now.
- **Size.** `math.my` is now 95,604 bytes (it was 60,357), the largest standard-library file by three times. Its first landing counted it against a project's `budgets.max_file_bytes`;
  the entry above this one ends that for the per-file budget: it bounds the project's own files only.
- **Evidence.** Each of the twelve functions differs from the pinned Zig in 0 of at least 100,000 arguments, in a debug and a `--release` build: the special values, the
  thresholds of every branch, multiples of pi/2, subnormals and the largest finite values. `experiments/math-exact-20261106/` holds the capture program, the checker and
  `status.md`; `tests/lang/math_zig_exact.my` replays 2,969 of the results. `docs/floating-point.md#zig-exact-ln-atan-acos-asin-tan-expm1-sinh-cosh-tanh-cbrt-sin-and-cos` is the page.

### `--no-cache` is a cold build: `build`, `run` and `run-project` no longer read or publish the shared stage store (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. The cost is only that a `--no-cache` build is slower, which is the point.

- **What was wrong.** `mylang build`, `build --run`, `run` and `run-project` with `--no-cache` built through an empty private work directory and switched the shared
  compiler-artifact tier off, but still read and published the shared stage store (`MYLANG_STAGE_SHARED_CACHE`, by default `~/.cache/mylang/stage-artifacts`), the records of
  lowering, the optimizer and emission that every worktree shares. Only `mylang test --no-cache` skipped it. A build that a stale stage record had made wrong therefore
  matched its own `--no-cache` check, because both builds read the same record (the two stale-stage bugs of 6 November, `e6b4d30e2` and `72ba71e6a`).
- **What it does now.** `--no-cache` on `build`, `build --run`, `run`, `run-project` and `test` opens no shared stage store: nothing is read, nothing is published, and a
  directory the variable names is not created. The per-user object store, whose objects are keyed by the exact text of their unit and checked against their digest, is
  still used, and so are the toolchain's identity memo and Zig's global cache for the libc stubs. `docs/tooling/native-build.md#--verify-cache-and---no-cache` lists every
  store and says which a cold build uses. `--verify-cache` is unchanged: its first pass serves the stores, its fresh pass reads none.
- **Cost.** A `--no-cache` build of a program whose stage records were in the store checks, lowers, optimizes and emits every function again; see
  `experiments/no-cache-cold-20261106/status.md` for the 99k port.

### `mylang fmt` no longer writes text that does not parse; a generic function may call a helper that writes `set()`; `W_NEEDLESS_COPY` names a generic callee whole (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. Three defects from the G3 netlisp port's
first section (F-S1a-10, F-S1a-3 and the callee name of its `W_NEEDLESS_COPY` warnings) are fixed, and one safety net is new.

- **`mylang fmt` kept a trailing comma on delimiters that take none.** A parenthesized expression that spans lines,
  `return (\n    a\n    and b\n)`, came out as `(a and b,)`, a one-element tuple, and the next `check` failed with `E_SYNTAX`.
  The expression now goes on a line of its own between its parentheses, `return (\n    a and b\n)`, with no comma. The same
  trailing comma broke four more constructs when their delimiter spanned lines, and each is fixed: an attribute's arguments
  (`@ensures(\n    result >= 0\n)`), a pattern that ends with the rest marker (`case atom(text, ..)`), a comprehension or generator
  (`sum(x * x for x in xs)`), and the type arguments of a keyword intrinsic (`accept_resource[network.Accepted](listener)`, which now
  collapses to one line like any type argument list). Calls, constructors, tuples, lists, dictionaries and parameter lists keep
  their trailing comma. A layout fuzz that breaks every delimiter of 2,828 source files (this repository's and the G3 port's) over lines made the old formatter write
  unparsable text for 445 of them; the new one, none. See `docs/tooling/formatter.md#delimiters-that-take-no-trailing-comma`.
- **`mylang fmt`, `fmt-module` and `fmt-project` check their output before they write it.** The text is parsed again, as the
  module or program the input was, and its syntax is compared with the input's, ignoring layout, comments, a comma before a closing
  delimiter, a literal's quoting and the order of a `from` clause. Text that does not parse, or parses to other syntax, is
  `E_FORMAT_VERIFY` (exit 2): nothing is written, and the report names the input line and the formatted line. The check costs one
  more lex and parse of the output and one walk over both syntax tables (12.3 to 20.7 ms of CPU for a 242 KB module the formatter
  changes, a ReleaseFast compiler), and nothing for a source that is already canonical. See `docs/tooling/formatter.md#the-safety-net`.
- **A generic function can reach a helper that uses any prelude builtin.** The abstract check of a template followed every call into
  the ordinary functions it reached and refused what it did not know there: a helper that wrote `set()` was `E_UNKNOWN_FUNCTION`
  (`E_UNKNOWN_SYMBOL` in a project) although it checked alone, and so were `dict()`, `list(...)`, `sum`, `min`, `max`, `abs`,
  `any`, `all`, `reversed`, `zip`, `ord`, `chr`, `round` and `print`. The abstract check now walks the generic functions only; an
  ordinary helper is checked by the concrete checker, so an invalid helper is rejected with that checker's code (`E_TYPE`
  where the abstract check said `E_GENERIC_TYPE`). A prelude builtin written directly in a generic body is still refused, now as
  `E_GENERIC_BODY_UNSUPPORTED` with the repair (write an ordinary function), not as an unknown function. See
  `docs/generic-inference.md#helpers-a-generic-function-calls`.
- **A generic callee is named whole.** `W_NEEDLESS_COPY` cut the checked name of `zig_str_map_put[repro::Value]` at its last `::`
  and printed `` `Value]` ``; it prints `` `zig_str_map_put[Value]` ``. The lint findings that name a function or a record, and the
  text a generic record prints (`Holder<PathKind>(value=...)`, which printed `PathKind>(value=...)` when its type argument came
  from another module), use the same rule: the module qualifier goes from the name and from each type argument.

### A function whose signature says `T[]` or `T?` is rebuilt when `T` changes; `--verify-cache` no longer fails after an edit that adds a type (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. Two causes made `mylang build --verify-cache` fail (exit 2) after
an edit that gave a record a field; the first was a real stale build, the second a difference in text only.

- **A list or an option type named nothing.** The declaration graph that dependency contexts are folded from indexed the parts of generic
  applications, fixed arrays, tuples and callbacks, but not of a type written with a suffix. A function whose signature said `groups: a.Group[]`
  or `-> a.Group?` therefore depended on no declaration of `a`: when `Group` gained a field the engine vouched for the stored check of the
  function's module, the part its lowering is keyed by did not move, and the stored lowering was restored for the new layout. A Debug
  compiler stopped with `E_CORE_INVALID_IR` (`record_make does not match its signature`); a ReleaseFast one linked the old element size and the
  old copy of the record, so the program found no group where a cold build found one and read a field it never copied. The graph follows
  the suffix now, in the module's check, the lowering key and the engine's invalidation alike. An edit that changes no record a function's
  types are made of moves nothing. On the 99k-line port the same functions are lowered again in every edit scenario as before; the edit
  builds execute 0.04% to 0.26% more instructions (0.75% for a new-shape type edit, one more enum case) and `check` 0.2% to 0.7% more
  (3.2% for the type edit); the CPU time moves by less than the noise of the runs.
- **An empty list's constant was numbered by its type's ordinal.** After an edit that adds a type, `--verify-cache` also failed on units whose
  code was the same as a fresh build's: the emitter named the constant of an empty list (`@myl.empty.list.<n>`) by its element type's
  ordinal in the build's type table, an emission receipt serves the text an earlier build rendered, and the fresh pass rendered the
  unit under the new table (the G3 port's `eval.env.BoardSpec` gaining `mounting: BoardMounting`: 29 units, 12 of them the six instances of its
  hash map, which a text digest names). The constant is private to its unit, so no build was wrong. It is numbered by the element's place among
  the empty lists the unit declares, in order of first use, as layouts and strings are, so a unit's text no longer depends on the type table.
  The first build with this compiler compiles again the units that hold an empty list, whose text changed.

`--verify-cache` still reports a stale instance key (the `--sabotage-instance-keys` tests). See `docs/tooling/native-build.md#--verify-cache-and---no-cache`.

### A borrow of a record place no longer blocks a write to another field of the record (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. `const item = self.items[i]` followed by
`append(mut self.links, copy(item))` is accepted, where it was refused with `E_SINGLE_OWNER_OVERLAP` ("the fields of one record count
as one value here").

- **The rule.** A `const` binding of a place holds that place's container, not the whole record: `item` holds `self.items`,
  `const t = self.inner.tags[0]` holds `self.inner.tags`. Another field of the record may be written while the binding is live (an
  append, a `mut` argument, an assignment, an element write, a nested field such as `self.inner.n = 3`), and the binding may be read after
  the write. The field, the record, a part of the container (`self.items[1] = ...`) and a `mut` call of the whole record overlap and stay
  refused, as do a binding of a binding, a slice, a borrowed call result and a loop over a binding (they hold the whole record).
  It holds for a local record and for nested records (`self.a.b` against `self.a.c`). See `docs/ownership-rules.md#r2--loans-block-changes`.
- **Field assignment in a loop.** `t.count = t.count + 1` in the body of `for entry in t.entries:` was refused (R7) and is accepted: a
  write to a field next to the one iterated. The pinned Lox migration test lost its `table.my` refusal for that reason.
- **The M5 hint is corrected.** When a call passes `mut self` and also reads `self` or a part of it (`link(mut self, self.design + x)`),
  the message names both arguments and says the callee may change what the other reads; it no longer says the fields count as one value.
- **For compiler developers.** The certificate validator and its Lean proof are unchanged: the lowering reads a binding of a record place
  again from the record after a write to it (`src/core/alias_places.zig`, `build.zig`), so no borrow outlives the update that consumes its
  root. Programs accepted before lower to the same Core IR.

### A record field may default to an enum case or a record value (6 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. A new field of an enum or record type
no longer breaks every constructor of its record.

- **The rule.** After `=` a record field may name an enum case (`kind: Kind = Kind.ground`), an enum case whose payload fields are
  defaults (`Kind.tagged(code=7)`), or a record constructor whose arguments are defaults (`turn: Turn = Turn()`,
  `far: Turn = Turn(angle=90)`), to any depth; the arguments may also be scalar literals and empty collections. Each construction
  that omits the field builds the value afresh, so a record with a list inside a default never shares it. The default resolves in the
  module that declares the record: a module that constructs it needs no import of the enum or record the default names.
- **What stays refused** (`E_DEFAULT_ARGUMENT`): a call of a function at any depth (`Turn(angle=pick(2))`), a module constant, and
  `Some(...)`. Function parameter defaults and the fields of a variant case keep scalar literals only. See
  `docs/records-and-unions.md#enum-and-record-defaults`.

### A generic instance is rebuilt when a record in its type arguments' payloads changes; `--verify-cache` checks the stage records (5 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. A build that follows an edit of a nested
record now gets the program a cold build of the same sources gets; until now it could get code compiled for the record as it was.

- **The fix.** A generic instance (`zig_str_map_put[Value]`) was keyed by its template's body and by the records its type arguments
  reach through their *fields*. The payloads of an enum's or union's cases, the elements and keys of arrays, tables, dictionaries
  and sets, a domain's backing type, a buffer's element and a callback's slots are not fields, so growing the record in `Value`'s
  `big(value: Big)` moved no key, the stored lowering of the instance was served for the new program, and the build crashed, failed
  the leak check, answered wrongly (`==` of two values compared the old field list) or, in a Debug compiler, stopped with
  `E_CORE_INVALID_IR`. The reach now follows every type a record holds, and the instance is lowered again when any of them changes.
  The same stale record was served across directories through the shared stage store; its key moves too. A function that is not
  generic was never affected: its checked-body part carries the dependency context transitively. A key whose reach was complete is
  the key it was, so a typical edit costs what it did.
- **`--verify-cache` compares the stage records with a fresh build.** It used to build the program without reading a stage record, so
  it built the correct program and reported nothing. It now also builds as an ordinary build does, up to the emitted LLVM units,
  keeps their text digests, and fails (exit 2, one `error: --verify-cache:` line per unit) when the uncached build emits a
  different unit (ignoring the `internal` or `hidden` linkage of a source function's definition). It costs one more front end, lowering, optimizer and emission. See `docs/tooling/native-build.md#--verify-cache-and---no-cache`.

### `build` and `run` compile the debug build with lean code generation; `--debug-o0` gives LLVM `-O0` back (5 November 2026)

Nothing that was accepted becomes a diagnostic, so no `mylang fix` migration is needed. What changes is how a debug
build is compiled and what a script that depended on its speed or its cache identity sees.

- **`mylang build`, `run`, `build --run` and `run-project` compile each LLVM unit of their plain build with `-O2 -Xclang
  -disable-llvm-passes` and five `-mllvm` switches** (variable locations, machine scheduler, copy propagation, loop strength
  reduction, machine CSE and LICM off), in place of `-O0`: LLVM's IR passes stay off, so a unit keeps the shape Core's passes gave
  it, and its code generation runs as in an optimized build. The emitted text and the traps with their source
  lines are the `-O0` build's; the DWARF line tables map 97% of the lines the `-O0` build maps on the 99k-line port. Programs run 1.2 to 1.3 times as long as their `--release` build (an `-O0` build: 1.7 to
  2.8 times); a cold build of the 99k-line port costs 1.6 times the CPU, the largest module's edit 1.5 times, a typical edit the
  same. See `docs/tooling/native-build.md#debug-code-generation`.
- **`--debug-o0`** gives `build`, `run`, `run-project` and `build --run` the previous plain build: Core's passes and LLVM `-O0`,
  the cheapest cold build. `--debug-lean` names the new default. Both are build modes, so two different modes on one command line
  are refused in either order, and each mode has its own objects, programs, replay records and test results.
- **`mylang test` keeps the `-O0` build by default** (`--mode Debug` is the command's default debug build: lean for `build` and
  `run`, `-O0` for `test`) and accepts `--debug-lean` to run a suite on the lean build.
- **`mylang test DIR` passes `--optimize-debug` (and `--debug-lean`) to the roots it runs in child processes.** It passed
  `--release` and `--unoptimized` only, so a directory run with `--optimize-debug` tested the `-O0` build whenever a root ran
  in a child (`MYLANG_TEST_CHILDREN=1`, or a root that cannot share its project's check).
- Every store key that hashed the optimization level (unit objects, linked programs and their families, optimization-record
  keys, replay and callable-digest settings, test receipts) now hashes the whole `zig cc` argument list of the mode, so a build
  never serves another mode's object and an edit of the lean list moves every key made under it.

### `check` agrees with `build`; `check DIR`; capability records; Zig-exact `log10`, `exp`, `atan2`, `pow_float` (5 November 2026)

G3 fixes that land before the full netlisp port (decision D-G3-4). Nothing here turns a program that builds into a
diagnostic, so no `mylang fix` edit is needed.

- `mylang check DIR` checks every module of the project beneath `DIR`, imported or not, test modules included
  (F-G2d-1). `mylang check ENTRY.my` still loads only what `ENTRY` imports.
- A named `own` capability handed to a call (`take(own fs)`, `start(own fs, own entropy)`) now builds; `check` accepted
  it and `build` refused it with `E_CORE_UNSUPPORTED` (F-G2e-A-1). With it, a function that takes capabilities as `own`
  parameters builds and returns a record that holds them (F-G2b-23, F-G2c-18, F-G2e-b-1).
- A constructor that takes fields of a `mut` record and then passes the record whole to an inlined helper now builds
  (`move_out_build` of the stage-2 port).
- `copy(alias)` of a `const` alias read after its owner changed is `E_SINGLE_OWNER_OVERLAP` at `check` (render-7 of the
  stage-2 port). Before, `check` accepted the program and only `build` refused it, so no program that built is affected;
  the repair is to copy before the change, or to bind `copy(owner)`, and `mylang fix` makes neither choice for you.
- `math.log10`, `math.exp`, `math.atan2`, `math.pow_float` and their `f32_` forms answer the bits of Zig's `std.math`.
- A cold `check` of a large project could end in a segmentation fault (a dangling key in the engine shadow's syntax
  answers). It cannot now.

### Output and rules that read differently since 5 November 2026 (G3 section S0)

None of these refuses a program that was accepted, so none needs a `mylang fix` migration. Each changes what a script that
reads the compiler's output or a project that leans on a rule sees.

- **Warnings of committed, unmodified modules are counted, not printed.** `check`, `build`, `run` and `test` print a warning
  in full unless its module is tracked by git and equal to `HEAD`; those end the command as one line, `warnings: 215 in 40
  unmodified modules (W_OPTION_TRY 56, ...); `mylang check --warnings` lists them`. A module with uncommitted edits, an
  untracked or ignored module and any project outside a git repository print as before. `--warnings` and `MYLANG_WARNINGS=all`
  print every warning, and `--diagnostics=json` always carries every one. A script that counts `warning[` lines on stderr in a
  git checkout should pass `--warnings` or read the JSON. See `docs/tooling/native-build.md#warnings-in-the-output`.
- **A local named like the root of an imported module path is the local.** With `import eval.deprecations`, a function that has
  its own `eval` reads `eval.deprecations.items` as the field chain of that local (it was read as the module path, and failed
  with `E_UNKNOWN_SYMBOL` or `E_UNKNOWN_IMPORT`, or used a constant of the module the local was meant to hide). Where no such local
  is in force, including after its block ends, the spelling is still the module path. A binding form the pass does not follow is
  refused with `E_SHADOWING` at the use. See `docs/modules.md#a-local-named-like-a-path-root`.
- **A function whose body still holds a typed hole is not refused for a parameter it does not read.** A skeleton such as
  `func read_all(fs: Filesystem, path: str) -> bytes: return todo[bytes]()` builds and runs without the `_fs` rename, and
  `E_UNUSED_CAPABILITY` and `W_UNUSED_BINDING` apply again once the hole is filled. See `docs/typed-holes.md#running-with-holes`.
- **A test that invokes a callback is reused like any other.** `mylang test` refused a receipt to a test whose call tree invokes
  a function value through a local or a record field (an evaluator with recursion hooks, a sort with a comparison function),
  which kept 586 of the G3 port's 1,250 tests running on every invocation. Only a callback beside `function_digest`, a callable
  test input, a `Host` capability, a host function or an `extern func` still refuses, and `--json`'s `cache.reason` for those is
  now `live-effects: ` followed by what stopped the proof and the function (it was the bare `live-effects`).
- **`MYLANG_ADMISSION_WAIT_S`** is exported by `scripts/build-slot.sh` to the command it admits: the seconds the job waited for its
  slot. See `docs/tooling/many-agents.md`.
- **The per-user object store's cap counts disk blocks.** `core_store_gc.py` adds up allocated bytes (`st_blocks`), not file
  lengths, retires the flat aliases of objects that have a shard name, and keeps its ledger in `.size-ledger-v4.sqlite3`. See
  `docs/tooling/native-build.md#the-caches`.

### `http.Error` tells the limit refusals from `Malformed` (30 October 2026)

`http.Error` gained `HeaderTooLarge(value)`, `BodyTooLarge(value)` and `UnsupportedVersion(value)`. A header
section or field count past the limits was `Malformed` (and now is `HeaderTooLarge`), a body, chunk or declared
`Content-Length` past the limit was `Malformed` (now `BodyTooLarge`), and an HTTP version spelled `HTTP/` digit `.`
digit other than 1.0 and 1.1 was `Unsupported` (now `UnsupportedVersion`). `http.status(error)` answers the
status a server sends: 431, 413, 505, 501 for the other `Unsupported`, 400 for the rest. `http.message` returns the
same texts as before. A `match` over `http.Error` without `case _` no longer checks.

Migration: `mylang fix` adds, after the arm of the case each new one was, a copy of that arm under the new name
(`HeaderTooLarge` and `BodyTooLarge` from `Malformed`, `UnsupportedVersion` from `Unsupported`), nested patterns such
as `case Err(Malformed(value=_))` included, which is what the program did before. The repair is `E_INCOMPLETE_MATCH`'s
(see `variant_splits.zig`); a program that wants the new statuses then edits the copies. The corpus is
`test/fixtures/fix-migration/http-error-kinds.my`.

### `lists.exchange` takes its replacement with `own` (25 October 2026)

`lists.exchange(mut values, index, replacement)` used to borrow `replacement` and copy it into
the list. It now takes `own replacement` and moves it in, so the call copies nothing, like the
prelude's `exchange(mut place, own value)` and `append(mut values, own value)`.

Migration: `mylang fix` writes `own value` where the named value is not used again (an owned
local or an `own` parameter) and `copy(value)` everywhere else (a value read later, a plain
parameter, a loop variable, a field of a borrowed record), which keeps the copy the old version
made. Fresh values, copies and scalars are left alone. The corpus is
`test/fixtures/fix-migration/lists-exchange-own.my`.

### Ownership rules (24–25 October 2026)

- `own` is required on every move of a named managed value, including bindings, stores and
  constructor fields.
- `const` always borrows a managed place; `const alias = own owner` transfers it.
- A function that returns a borrow declares where it comes from in its signature,
  `-> T from a, b`.
- `fail value` needs no `own`, the same as `return value`.

Migration: `mylang fix` inserts the markers, copies and `from` clauses. The rules are in
`docs/ownership-rules.md`, and the migration's evidence is in
`experiments/ownership-closeout-20261025/REPORT.md`.
