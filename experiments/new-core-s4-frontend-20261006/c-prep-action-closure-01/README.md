# LLVM-only action input preparation (2026-10-07)

This is observational C preparation. No compiler sources, toolchain inputs,
system files or protected baselines changed; no cache eligibility or timing gate
is claimed. All nine tool actions ran inside normal build-slot admission with
CPU 10 excluded. Every compilation used a fresh invocation-owned local/global
Zig cache, the actual retained E Debug LLVM unit, its canonical basename and the
prospective merged `-target x86_64-linux-gnu.2.31` flags.

Input SHA-256: `1c40b584bc71793ebd6e8a1d597b03c65677dd33857bed2370293efed1363e48`.
Pinned executable SHA-256:
`1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f`.
The baseline full object is 3,184 bytes with SHA-256
`d8dd5741be1e8c641748d89dec8810ff602a9203e1b8afeaf4006e4cfe7a0b37`.

## Actual accesses and the existing inventory

`baseline.strace` retains file metadata calls, successful reads, failed lookups,
directory enumeration, process execution and readlink results. It follows every
thread/process and includes fd path annotations; `baseline-accesses.json` joins
unfinished/resumed calls (including the thread-ID change across exec).
`inventory-comparison.json` compares those paths with the decoded existing
20,907-input v3 hint, whose exact file hash is recorded. The Python reader uses
the hint only for path comparison and does not validate its BLAKE3 checksum.

The baseline examines 93 distinct normalized paths. It opens the adjacent
library's `std/std.zig` to establish library-root presence but does not read its
contents or any other bundled library file in this action. It reads the LLVM
input and the freshly generated cached object. It also reads `/etc/os-release`
(resolved `/usr/lib/os-release`) and `/etc/lsb-release`, which are outside the
20,907-input inventory, and `/dev/urandom` for temporary output names. The two
host files' logical/resolved paths, hashes and generations are retained in
`observed-host-inputs.json`; this is a post-probe snapshot, not a race test.

The driver enumerates `/usr/lib/gcc/x86_64-linux-gnu`, observes version 15 and
checks its `crtbegin.o` and C++ include-directory existence. Other searched GCC,
resource, library and multilib locations include numerous absent paths outside
the inventory. A failed resource lookup includes the derived sibling path
`/home/epentland/zig-toolchains/lib/clang/22/share/ubsan_ignorelist.txt`.
The baseline's tool-root probe also first tries absent adjacent `lib/zig` before
finding `lib/std/std.zig`. Exact successes/failures/search paths are retained,
not reduced to a list of files with successful content reads.

Static alias snapshots cover `/etc/os-release`, `/lib` and `/lib64`; dynamic
`/proc/self/exe` and `/proc/self/fd/*` targets come from the traced process's
readlink results, not the later analyzer process. Alias targets and ancestor
selection must be guarded by any future action certificate.

## Generic flag controls

| Control | Full object | Observed searches |
| --- | --- | --- |
| Original merged target/CPU flags | baseline hash | GCC enumeration and both host distro reads |
| Explicit `--no-default-config` | baseline hash | same searches |
| `-nostdinc -nostdinc++` | baseline hash | same searches |
| `--gcc-toolchain=<owned empty directory>` | baseline hash | GCC enumeration disappears; distro reads remain |
| `--sysroot=<owned empty directory>` | baseline hash | same GCC and distro searches |
| Combined config/header/GCC/sysroot controls | baseline hash | 48 paths; no GCC enumeration; distro reads remain |
| Combined controls plus `-resource-dir=<adjacent lib>` | baseline hash | resource probes move into inventoried library; distro reads remain |

All these actual compilation statuses are zero. The empty directories and
fresh native caches are task-owned. The explicit resource directory changes
search policy and would require an approved production flag/key change; these
observations do not authorize it. Zig consumes the tested `--sysroot=` option
and forwards it to its `ld.lld -r` action, but its emitted Clang child argv does
not contain a Clang sysroot option in this control. Thus it is not evidence that
Clang's system discovery has been isolated.

Adding `-MD -MF unit.d` returns zero but warns that both options are unused for
LLVM IR and writes no depfile. It changes the Zig control path to direct Clang
output: 2,912-byte full object SHA-256
`b08b1dd6faa7d93c6e0ee993a806a84c5e5f5de9d64662d052930a5f8fc60af2`.
The baseline instead invokes Clang and then `zig ld.lld -r`. Consequently this
flag route cannot provide a byte-preserving closure receipt for the original
native action. The raw trace and failed depfile presence remain evidence.

`-###` successfully retains the in-process cc1 argv. It resolves native CPU to
`alderlake` and emits a long explicit target-feature list. Its dry driver still
reads the same host distro files; it is not an input-free identity query.

## Available local implementation and missing proof

`local-source-evidence.json` reads Git objects from the locally available Zig
revision `5ceec001b5`, records complete file hashes and relevant numbered
excerpts. It leaves that source worktree untouched. The source establishes:

* `Compilation.addCCArgs` already injects `--no-default-config`; non-assembly
  inputs get `-nostdinc`; the header/define setup is excluded for `.ll`/`.bc`.
* `FileExt.clangSupportsDepFile` explicitly rejects `.ll`/`.bc`. The existing
  filesystem-input collection records C/LLVM source inputs, link objects and
  parsed depfile prerequisites, not every Clang driver's discovery query.
* Explicit user depfile mode can replace the Zig process with Clang for a single
  object, explaining the observed byte change and absent `ld.lld -r` action.
* Pinned `Build.Cache.File.Stat` stores inode/size/mtime, and cache-hit checking
  compares those three. It omits ctime and cannot prove restored-mtime safety.
* The Clang wrapper reads `CCC_OVERRIDE_OPTIONS`, which can rewrite arguments,
  and delegates `BuildCompilation` to the linked Clang library. A future small
  closure must include or conservatively reject input-selecting environment
  overrides, not merely hash their strings.

The distribution includes Zig's Clang wrapper but no implementation of Clang's
Linux/GCC/Distro toolchain discovery. This source snapshot is not a reproducible
source-to-binary attestation for the linked LLVM/Clang build. Neither the trace
nor the existing source/depfile metadata proves that the observed paths are the
complete semantic dependency set for every permitted generated LLVM unit.

A sound smaller certificate needs a narrowly specified LLVM-only action and
review of every file-dependent branch in the actual pinned driver/backend:
prove which initialization reads cannot affect this action, or capture their
contents/generations; cover absent higher-priority candidates and enumerated
search-directory generations; preserve effective Zig library resolution,
symlink targets, native CPU/features, full flags, environment and canonical
basenames; reject unsupported inline assembly/external file references or
include their dependencies. Cold execution must validate the exact closure
before and after compilation and before atomic publication. Warm lookup must
validate that same versioned closure before accepting an object. A separate
link/runtime/number/executable certificate must cover its own actual consumed
inputs and default loader closure. The full general helper remains the existing conservative baseline, but the
observed unguarded distro/search inputs are an unresolved closure gap. No final
cache qualification may rely on its completeness until the guard audit resolves
that gap. Its existing inputs must be retained; no directory-mtime-only shortcut
is justified.

## Actual link grouping risk

Root's retained E observation reports that replacing one LLVM input with a
prebuilt `.o` at the same printed argv position moved native C `main` from
`0x1032940` to `0x1008ac0`, despite identical `.text` object bytes and unchanged
global addresses; timings changed enough that this diagnostic was rejected.
This preparation did not rerun that app diagnostic or claim its qualification.
The local pinned `src/link/Lld.zig` explains the concrete hazard: ELF linking
appends explicit `link_inputs` objects first and then generated `c_objects`,
regardless of their original interleaving in `zig cc` argv. All-object C linking
must retain actual child linker argv plus ordered input identities, inspect ELF
section/symbol/segment layout, and repeat every application/row gate. Native
input order and input-kind grouping belong in the executable key; preserving
only E's printed high-level argv order cannot establish equivalent layout.

## Retained operational errors

`command-02.log` retains a task-owned fixture-name collision after the successful
empty-GCC control; the remaining fresh controls ran in command-03. Analyzer
logs 05/06 retain missing dirfd annotation and exec thread-ID handling errors;
08 handles both, avoids attributing later Python `/proc/self` links to Zig and
records all observed traces. No native correctness failure was hidden by those
analysis repairs. No Guardian gate was exercised for this read-only task.
