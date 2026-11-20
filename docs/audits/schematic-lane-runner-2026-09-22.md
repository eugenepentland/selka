# Schematic lane 1: the runner's build policy — 2026-09-22

Items 1 and 8 of [the schematic parity gap audit](schematic-parity-gap-2026-09-22.md):
give the shipped `schematic-svg` the code generator a plain `mylang build`
produces, take instruction accounting off its guest, and keep a runaway guard
that costs nothing. Branch `perf/schematic-1-runner-policy` over
`base/schematic-20260922` (`6ee47415`). Harness, arm specifications and raw
rounds: [`experiments/schematic-lane-runner-20260922`](../../experiments/schematic-lane-runner-20260922/README.md).

## Headline

1. **The guest the tool runs is 3.4× faster**: 20.0 ms → 5.9 ms on the fixture
   in one interleaved batch (7.39× → 2.19× the Zig port). It now lands within
   1.5% of what a plain `mylang build` of the same sources produces, which is
   the whole point of the item.
2. **The tool the user runs is unchanged, and that is the real finding.** One
   warm `schematic-svg` invocation is about **1.00 s**, of which the guest's
   render is **6 ms**. The frontend runs **twice** per invocation — once
   in-process for the host-declaration list, once as the driver's child — for
   **774 ms**, and a relink costs **142 ms**. End to end, before 1045 ms and
   after 1068 ms, ratio 1.02 [0.95, 1.07]: a wash.
3. **Full LTO would have made the tool 7.6× slower.** A host builds into a
   fresh private directory and passes `--provider`, so link reuse never
   applies and every invocation pays the LTO link: 7.9 s against 1.0 s, for a
   render that is 0.6% faster. The shipped policy is therefore
   `--backend llvm --llvm-opt 3` **without** `--lto`, which is the one place
   this lane deliberately departs from the roadmap's wording.
4. **The ceilings that replace instruction accounting are free.** A call-depth
   ceiling and a wall-clock ceiling cost nothing measurable on the render, and
   both stop a runaway guest; instruction accounting cost 14 ms of the old
   20 ms.
5. **Static linking is not adopted.** The relinked binary is byte-identical in
   output and 7.5% faster by median but *identical by minimum* (4.696 against
   4.714 ms), so the median difference is this machine's interference, not a
   floor. It would also make every `mylang build` depend on the host having a
   static libc. Numbers below.

## What changed

- `src/host_native.zig`. A host names a policy instead of restating flags. Only
  a `.qbe` backend passes `--qbe PATH` — an explicit assembler is exactly what
  pinned QBE for every host guest ("an explicit backend is never upgraded"), so
  an `.llvm` host now lets the driver resolve the release code generator it
  asked for. The three LLVM controls moved into one `llvm` field, and a new
  `accounting` field says what the runtime will enforce: `.steps` builds with
  `--step-accounting` and runs under `--max-steps=`, `.frames` builds with
  `--max-frames=1024` and runs under that ceiling plus `--timeout=60`.
  `Accounting.bounds()` is the single source of both halves.
- `src/schematic/app.zig`. `App` remembers the ceilings its guest was built to
  enforce and appends them to every invocation, so a caller can no longer hand
  a guest a ceiling its build dropped (which is `R_NO_STEP_ACCOUNTING`), and a
  caller that names a tighter ceiling of its own is the one the runtime reads
  first. `App.release` is the shipped policy.
- `src/schematic/runner.zig`, `dev_session.zig`. Both start from `App.release`
  and neither passes `--max-steps` any more. `--backend qbe` drops the LLVM
  controls QBE refuses, `--llvm-opt`/`--llvm-adapter`/`--lto` override the
  rest, and the new `--bounded` restores instruction accounting.
- `src/schematic/tests.zig`. The staged single-file boundary guests keep QBE
  and step accounting explicitly (`staging`) because they exercise the trusted
  boundary, not generated code; the whole-fixture test and the two new runaway
  tests take `App.release`, which is what the runner uses.
- `docs/tooling/runtime-budgets.md` gains a *Host application guests* section
  and `src/features.json` the matching slug; `SPEC.md` gains
  `HOST-GUEST-POLICY-1`, `SCHEMATIC-RUNNER-POLICY-1` and
  `SCHEMATIC-RUNNER-BOUNDS-1`.

## Measurement conditions

Every number below was taken on a machine where **three other agents were
compiling**: load average 14–50 throughout. Absolute times are inflated about
twofold against the parity audit's quiet machine (its `zig-o3` is 1.31 ms;
here 2.71 ms), so **read the ratios, not the milliseconds**, and expect the
integrator's re-measurement to be uniformly faster. Arms are interleaved in a
random order within each round, pinned to CPU 2, 31 rounds after 3 warmups for
guest binaries and 21 after 3 for the whole tool, and **every run's SVG is
hashed** against `68157ea785ee3766c039714d1d081ea1c7a55def6cf9124660495f8b797ed388`
— all 380 runs of the two batches below, and every run of the earlier policy
batch, produced exactly the fixture's 49,617 bytes.

## 1. The guest binary

`results-guest.json`. "Before" is the binary the audit built from the runner's
own argument vector (`--step-accounting --qbe PATH`); "after" is the guest the
new policy builds, run under the ceilings that policy passes.

| arm | policy | median ms | p10–p90 | min | × zig-o3 |
|---|---|---:|---:|---:|---:|
| `zig-o3` | Zig ReleaseFast | 2.710 | 2.48–3.43 | 2.362 | 1.00 |
| `rust-o3` | rustc `-O3` | 3.119 | 2.84–4.33 | 2.603 | 1.15 [1.08, 1.26] |
| **before** | `--step-accounting --qbe PATH`, `--max-steps=1e8` | **20.023** | 19.03–21.82 | 18.345 | **7.39 [7.00, 7.67]** |
| **after** | `--backend llvm --llvm-opt 3 --max-frames=1024`, run `--max-frames=1024 --timeout=60` | **5.933** | 5.57–7.58 | 5.417 | **2.19 [2.09, 2.45]** |
| after + `--lto` | same plus full LTO | 5.898 | 5.59–7.32 | 5.317 | 2.18 [2.08, 2.26] |
| reference | plain `mylang build` (LLVM O3 + LTO, unbounded) | 5.848 | 5.41–6.97 | 5.078 | 2.16 [2.04, 2.24] |

**before ÷ after = 3.37×.** The shipped guest is now within 1.5% of the plain
`mylang build` reference, and LTO is worth 0.6% of the render — inside the
noise of this batch and consistent with the parity audit's own non-LTO relink
(within 2% of its LTO arm).

The three ceilings priced separately, on the same guest sources (earlier batch,
same conditions): unbounded 3.027 ms, `--timeout=60` 3.078 ms, frame accounting
with `--max-frames=1024` 3.072 ms, step accounting 9.669 ms. **Instruction
accounting is the whole tax; the wall clock and the call-depth ceiling are
free.** `--max-frames=1024` is also the number of frame slots the runtime
already allocates for an unbounded run, so it changes neither the mapped
execution stack (32 KiB per frame) nor the address space; a larger ceiling
would enlarge both, and `--max-frames=65536` already fails to start under a
256 MiB budget.

## 2. The tool, end to end

`results-runner.json`, 21 rounds, each a fresh `schematic-svg` process with a
warm object cache — what the user actually runs.

| arm | median ms | p10–p90 | ratio |
|---|---:|---:|---:|
| **before** (base install) | **1045.1** | 928–1246 | 1.00 |
| **after** (lane install) | **1067.8** | 952–1299 | **1.02 [0.95, 1.07]** |
| after, `--backend qbe` | 1029.8 | 907–1187 | 0.99 [0.93, 1.04] |
| after, `--lto` | 7923.3 | 7051–9106 | 7.58 [7.08, 8.25] |

The 14 ms the render saves is 1.4% of an invocation and is lost in the spread.
Decomposition of one warm invocation of the new runner (CPU 2, five runs each,
`--report` for the driver's phases):

| phase | ms | share | what it is |
|---|---:|---:|---|
| in-process frontend check | 476–518 | 50% | `App.initDiskWithOptions` loads and checks the project and emits a 7.3 MB manifest, only to read the guest's `host` declaration names out of it |
| driver frontend child | 274 | 27% | `qbe_build` re-runs the same frontend as `/proc/self/exe emit-project-qbe`, with its own content cache |
| codegen | 29 | 3% | 124 of 124 objects reused |
| link | 142 | 14% | a full relink every invocation |
| guest render | 6 | 0.6% | the guest's own work |
| **total** | **986–1026** | | |

Warm rebuild per policy, fresh output path (`policy-builds.json`; base compiler,
loaded machine):

| policy | cold s | warm s |
|---|---:|---:|
| QBE + step accounting (before) | 5.99 | 0.38 |
| LLVM `-O3` (after) | 9.82 | 0.35 |
| LLVM `-O3 --lto` | 8.04 | 2.59 |
| LLVM `-O3 --lto --step-accounting` | 16.66 | 5.68 |

This is why the shipped policy drops `--lto`: warm, it is 2.2 s of relink per
invocation for a render that is 0.06 ms faster.

## 3. Static linking (item 8)

The driver's `zig cc` link was replayed exactly as captured from a real build
(`strace -e trace=execve`), once as it is and once with `-static`, over the same
objects and the same runtime archive:

| link | bytes | median ms | min ms | × zig-o3 (median) |
|---|---:|---:|---:|---:|
| dynamic (today) | 994,344 | 5.774 | 4.714 | 2.13 [2.01, 2.25] |
| `-static` | 1,827,120 | 5.339 | 4.696 | 1.97 [1.88, 2.09] |

Both produce the fixture's exact SVG. The medians differ by 7.5% but the
**minima differ by 0.4%** (4.696 against 4.714 ms), which says the median gap
is this machine's interference rather than a start-up floor; the parity audit
priced the whole dynamic-libc and loader floor at 0.14 ms. Against that, the
change would apply to every `mylang build`, not to this tool: `zig cc -static`
here resolves the *system's* `/usr/lib/x86_64-linux-gnu/libc.a`, so a static
link makes every native build depend on a static libc being installed, and it
is incompatible with `--library` (shared objects) and with any guest that ends
up in `dlopen` or glibc's name resolution. **Not adopted.** No commit changes
the link; the replay script's numbers are recorded here and the capture is
reproducible from the harness README.

## 4. Anything else on the per-invocation path (item 4, raised not fixed)

1. **The frontend runs twice, for 774 ms of a 1,000 ms invocation.** `App`
   needs one thing from its in-process check — the list of `io::*` operations
   the guest declares, for provider registration — and pays a full parse,
   check, lowering and a 7.3 MB JSON manifest for it, which it then parses
   again. The driver then repeats the whole frontend in a child process.
   `qbe_build` already accepts `--manifest-file=PATH`, which skips its child
   entirely; the blocker is that the host's `emitQbe` does not apply the
   lowering policy the driver's child does (`--drop-debug`,
   `--drop-step-checks`, `--drop-frame-checks`), so handing it over today would
   silently re-enable the accounting this lane just removed. Exposing those
   options on `embedded_project` and passing `--manifest-file=` is the single
   largest remaining win in the tool: roughly **−500 ms per invocation**.
2. **Every invocation relinks (142 ms).** `BUILD-BACKEND-4`'s link reuse is
   disabled by `--provider` and could not apply anyway, because
   `Program.build` links into a fresh random directory each time. A stable,
   content-addressed output path under the object cache plus treating the
   embedded provider as the content-addressed object it already is would make
   an unchanged guest skip the link.
3. **Transport files are not the problem.** The three documents, the output and
   the issue file are written and read per invocation; at 49 KB of SVG and
   1.1 MB of input this is well under a millisecond and did not appear in the
   decomposition.
4. **The `--dev-session` path already benefits in full.** It builds once and
   renders many times, so for it the 3.4× guest speed-up is the whole story.

## 5. Gate

Run through `ZIG_LOCAL_CACHE_DIR=… ~/capbuild` from the lane worktree.

| step | exit | wall | note |
|---|---:|---:|---|
| `zig build test --summary all` | 1 | 329 s | 47 failing tests, **all pre-existing** |
| `zig build test-qbe --summary all` | 1 | 77 s | 2 failing tests, identical on the base |
| `zig build test-qbe-build --summary all` | 0 | 4 s | |
| `zig build fmt-check` | 0 | 1 s | |
| `zig build test-schematic --summary all` | 0 | 15 s | 19/19, up from 17/19 on the base |

The base was re-run in the same worktree (`git checkout --detach
base/schematic-20260922`) to separate inherited failures from new ones:
`zig build test` fails there too, with **49** distinct failing tests against
this branch's **47** — the same set minus the two schematic tests this branch
repairs. `zig build test-qbe` fails on the base with exactly the same two tests
(`golden_parity`, `native_test_wire`). No test that passes on the base fails
here.

The two repaired tests are unrelated to this lane's subject: the
`E_UNUSED_CAPABILITY` migration (`28e31419`) updated the corpus and fixtures but
missed two staged guests in `src/schematic/tests.zig`, which took a `Host` they
never used and so no longer compile. They now use it.

## 6. Known limits

- Every absolute millisecond here was measured on a loaded machine; ratios
  within a batch are sound, cross-batch absolutes are not.
- The end-to-end arms rebuild the guest inside the timed process, so their
  spread is the build's, not the render's; a quiet machine will show a smaller
  median and the same conclusion.
- `--max-frames=1024` is a real capability bound: a guest that recursed deeper
  than 1,024 frames would now trap `R_FRAME_LIMIT` where it previously ran on
  until the 32 MiB execution stack. The schematic guest parses with an explicit
  stack bounded at depth 128 and has no deep recursion, so nothing in the
  shipped tool approaches it.
- The wall-clock ceiling is 60 s for one render, which is generous for a 6 ms
  workload but is a fixed constant rather than a flag; `--bounded` is the only
  way to change the bounding policy from the command line.
- The static-link numbers come from a replayed link, not from a compiler that
  emits one; adopting it would need its own spec bullet, a `--library`
  exclusion and a portability decision about static libc.
