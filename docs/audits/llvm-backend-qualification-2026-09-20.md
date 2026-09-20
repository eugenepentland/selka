# LLVM backend qualification: is the arm ready to be the default?

20 September 2026. Answers a question the 19 September experiment did not: not
"how much faster is LLVM on this lowering" but **is the LLVM arm ready to be the
default backend at the current language level**.

The earlier decision was conditioned on a `<10%` speedup threshold and measured
5.4–8.9%; a re-measurement on the current tree reported 12.3% (census) and 17.3%
(render) on the 7.42 MB input, which cleared the threshold and re-opened the
decision. This document qualifies the arm on evidence rather than on that number:
build coverage over the whole language tree, behavioural equivalence, the trap
and accounting surface, what of the full gate can run through the arm, paired
runtime measurement, and cost.

Raw evidence: `experiments/llvm-backend/evidence/qualification-20260920/`. Every
stage records the compiler binary plus `src/qbe.zig`, `src/native_types.zig` and
the four translator files as identity hashes at its start and its end; a stage
whose compiler moved is void. One command reproduces the block:
`experiments/llvm-backend/qualify_all.sh`.

## Decision

**Not the default yet — but no longer because anything is missing from the
language. Adopt it as an opt-in release backend, and gate a default switch on
the two items in §8.** Every gate that was runnable passed, on every entry the
language tree contains:

* the 326-entry build sweep has **0 LLVM-only failures** (as found, it had 10);
* the four guest suites agree **test for test** with QBE (42/42, 227/227,
  227/227, 114/114), both arms exiting 0;
* the trap matrix is green across every trap code the language defines, in both
  modes and under `--gc-stress`;
* the paired measurement puts LLVM **17–20% ahead** on the census/render pair,
  in **124 of 124 rounds**.

What keeps it from being the default is not correctness but the cost of the
switch and the remaining unknowns: a **2.97× cold build** (3.39× in codegen), a
single-workload performance picture, and a translator that still **fails closed**
on constructs outside the emitted subset rather than being proven total. §8
names exactly which caveats are acceptable and which need work first.

## 1. What was qualified, and against which revision

The whole qualification runs against one frozen compiler and one frozen
translator. Payload-carrying hashes are recorded at the start and the end of
every stage and are identical everywhere; only the emitter source moved *between*
stages, and no stage straddled it.

| artifact | sha256 |
|---|---|
| compiler (frozen copy `.tmp/llvm-qual/bin/mylang-f5fa59a0`) | `217838b2e1512cabd81fdcd7224b0384713596f704d7d6ddf27196906fa1f6f9` |
| `src/qbe.zig` | `f5fa59a0ea7339b5c334492c039d38576cb7f296f25a226460fd83aa9bb4804f` |
| `src/qbe_aggregate.zig` | `bac844d762c6284e8c9055f2df85b7bf35c431b6bb2c09dc74a51fffcdd8acd4` |
| `src/native_types.zig` | `02810bf47830686d53e1ebd753ae4c33c7875194774611fe111770ed0a108000` |
| `qbe_llvm.py` | `d3ab8c24eb4e1f23e88531b31adabc3340ef59d3efccc84a6bb86f8e0fc7c8b6` |
| `llvm_emit.py` | `3ccf0f73e34cccc0e83e5f460587640b62a21b9e31b31d597a9ee6abd1766a2b` |
| `runtime_signatures.py` | `8d0c48cdc747661daacc9eb776811543c0d24ec2ff53624a5ed4bc8b20fb637c` |
| `amd64_sysv.py` | `1d0252b37ec42904808f879590b9100292720c746efc3d9c85b537c001422919` |

Both arms are built by that compiler with the same flags
(`--mode=ReleaseFast --keep-symbols`), the same frontend, the same runtime
archive, the same assembler and linker; only the QBE tool differs. The receipt
of every measured binary records the runtime object hash, and both arms share it.

The qualification is a statement about that revision. The tree moved twice while
it ran — `src/qbe.zig` was rewritten at 14:03, 14:08 and 14:10, and the installed
compiler was rebuilt at 14:03 and 14:13 — which is why the compiler was frozen to
an immutable copy before the load-sensitive stages, and why the earlier
`f42c3c9c` (13:05) and `996a33e7` (13:37) results are kept but labelled
**superseded**.

## 2. Build coverage — every `.my` entry, both arms

The single most important gate: a test suite only builds what some entry point
reaches, so an unsupported opcode in a construct no test exercises stays
invisible. Every `.my` file under `tests/lang/`, `tests/`, `examples/` and
`experiments/sexpr-port/` (326 unique files after deduplicating `tests/lang`
inside `tests`) was built twice — once through QBE, once through `qbe_llvm.py` —
with identical flags and separate caches.

| outcome | as found (13:05 build, as-found adapter) | frozen revision (`f5fa59a0`, fixed adapter) |
|---|---:|---:|
| built by both arms | 173 | **183** |
| failed in both arms (fragments, negative fixtures, no `main`) | 143 | 143 |
| **LLVM-only failures** | **10** | **0** |

The 143 both-arm failures are not backend findings: they are module fragments
that need `--project` (`error[E_MAIN]`), negative fixtures that must not compile
(`error[E_REMOVED_SPELLING]`, `error[E_SYNTAX]`), and similar. The classification
is in `build-sweep-fixed.json`, which keeps each arm's status, its exact
diagnostic and its timing per entry.

### What the as-found sweep found, and what it cost

Ten entries built with QBE and failed with the LLVM arm. Two root causes, both
translator gaps rather than compiler bugs:

**Every function value was unsupported.** `%v =l call %vN(...)` — an indirect
call — raised `cannot parse a call`, because the call parser accepted only
`$name`. Eight entries failed on it: `examples/callbacks.my`,
`examples/unit.my`, `tests/guest/callbacks.my`, `tests/lang/callbacks.my`,
`tests/lang/python_core.my`, `tests/lang/migrated/generic_inference.my`,
`tests/lang/migrated/structural_constraints.my`,
`tests/fixtures/idioms/lambda_sort_key.my`. Function values are core language
(`def(int) -> int` parameters, stored and returned callbacks), so this was a
hard blocker, not a corner: minimal reproducer, QBE builds and returns 8, LLVM
exited 2:

```mylang
def inc(n: int) -> int:
    return n + 1

def apply(f: def(int) -> int, n: int) -> int:
    return f(n)

def main() -> int:
    return apply(inc, 7)
```

**One load opcode was misspelled.** `tests/lang/python_collections.my` failed
with `unknown opcode loadsh`: the translator's table carried `loadb`/`loadh`/
`loadw`, which are not QBE opcodes at all — the real mnemonics are `loadsb`/
`loadub`, `loadsh`/`loaduh`, `loadsw`/`loaduw` (`vendor/qbe/ops.h`). A row that
can never match is invisible until a unit contains the true spelling, which is
exactly how it survived the earlier qualification.

**A harness hole, not a translator gap.** `experiments/sexpr-port/main.my` — the
benchmark closure itself — did **not** build through the LLVM arm as found:
`myl_native_bytes_buffer_append_float` is `@export`ed from
`src/native_format.zig`, and the signature registry read only `src/*.h`, so the
symbol was invisible and the translator refused it. The arm needed a hand patch
to build at all, which means the earlier "12–17%, two suites pass" measurement
was taken on an arm that could not build the benchmark unaided. That weakens the
earlier number, not this one.

### The fixes, and the tests that keep them fixed

| gap | fix | regression test |
|---|---|---|
| indirect calls | `call_target()` parses `%temp` into an `IndirectTarget`; `render_indirect_call` lowers it from the call site's own evidence (`%ctx` first, pointer-width arguments, destination annotation as the result), with `parameter_abis` still classifying the whole signature | three ABI tests link hand-written QBE through the real toolchain and compare an indirect call against a direct call to the same callee: scalar result (44), >16-byte aggregate result through the hidden `sret` pointer (84), >16-byte aggregate argument through `byval` (12) |
| nested indirect call | the operand parser accepts `call %temp(...)` too | one test: `add 10, call %callee(l 4)` → 15 |
| `extern $f` plus `call $f` | the symbol is declared once, as the function, instead of also as `external global` | covered by the tests above, which take the callee's address and call it directly |
| load/store mnemonics | the table spells the vendored opcodes | a test extracts the opcode list from `vendor/qbe/ops.h` and asserts `LOADS` and `STORES` equal it |
| Zig-`@export`ed runtime helpers | `runtime_signatures.generated()` reads `@export(&fn, .{ .name = … })` from `src/*.zig` and converts the declaration's Zig types to C ABI shapes; unrecognised types are left out so an unknown helper still fails closed | the hand-registered entry was **removed** so the closure depends on the generator, and a test pins the generated `(ptr, ptr, i64) -> i32` and `(ptr, i64, i32, ptr) -> i32` |

The point of the last row is that the fix is structural: the next Zig-exported
helper does not need a hand edit, and one that is added without a recognisable
declaration still refuses translation rather than receiving an invented
signature.

## 3. Behaviour equivalence — the guest suites

Each suite is run twice, in **separate cache directories** so no result can be
reused across arms, and compared by **test name** as well as by totals.

| suite | QBE | LLVM | exit status |
|---|---|---|---|
| `tests/guest` | 42 passed / 0 failed | 42 passed / 0 failed | 0 / 0 |
| `tests/lang` | 227 passed / 0 failed | 227 passed / 0 failed | 0 / 0 |
| `tests/lang --gc-stress` | 227 passed / 0 failed | 227 passed / 0 failed | 0 / 0 |
| `experiments/sexpr-port` | 114 passed / 0 failed | 114 passed / 0 failed | 0 / 0 |

No test present in one arm is missing from the other, and no verdict differs.

### A methodological warning: totals lie

`mylang test` reports a per-file **build** failure as a host failure: the summary
line still prints `N passed, 0 failed` and the process exits 2, with the failed
file's tests simply absent. The as-found run of this very gate is the
demonstration: `mylang test tests/lang --qbe=…` printed **"174 passed, 0 failed"**
while three programs (`callbacks`, `python_core`, `python_collections`, 53 tests)
never built. Any qualification that compares summary totals alone will call that
green. This report compares verdicts by name and requires exit status 0 from both
arms; the earlier claim that both suites passed through the LLVM arm is exactly
the failure mode above.

### Byte-equality on the entries that used to fail

Parsing a construct and compiling it correctly are different claims, and a
mis-compiled calling convention would be worse than a refusal. All ten entries
the as-found sweep failed were therefore **built and run** through both arms and
compared byte for byte (exit status, stdout, stderr), with their guest tests
compared by name: **10/10 agree, 0 divergences**
(`affected-byte-equality.json`). A harness bug in the first version of that check
is worth recording: the output path was keyed by file *stem*, so
`examples/callbacks.my`, `tests/guest/callbacks.my` and `tests/lang/callbacks.my`
raced for one binary and the comparison reported the winner — the divergence it
showed was the harness, not the arm. The check now keys on the whole relative
path.

## 4. Traps, ceilings, GC stress and exit status

Eighteen probes cover every trap code the language defines, each declaring the
code it must produce, so "both arms agree" cannot be satisfied by two identical
silent successes. Each probe is built in **ReleaseFast and Debug** by both arms
and run **plain and under `--gc-stress`**: 72 arm comparisons, **0 failures**.

| trap | probe | trap | probe |
|---|---|---|---|
| `R_LIST_BOUNDS` | list index past the end | `R_FILE` | `with fs.open` on a missing path |
| `R_TEXT_BOUNDS` | `str` index past the end | `R_OUTPUT` | write to a closed stdout |
| `R_OVERFLOW` | `i64` ceiling; narrowing cast | `R_MEMORY_BUDGET` | allocation past `MYLANG_MEMORY_LIMIT` |
| `R_DIVISION_BY_ZERO` | quotient and remainder | `R_STEP_LIMIT` | recursion under `--max-steps` |
| `R_FLOAT_CONVERSION` | float that does not fit `int` | `R_FRAME_LIMIT` | recursion under `--max-frames` |
| `R_BYTE_RANGE` | `bytes([72, 300])` | `R_ASSERT` | failing `assert` with a message |
| `R_INVALID_SHIFT` | shift count at the operand width | exit status | `main` returning `300` and `-1` |

The historical differential set (`experiments/sexpr-audit/evidence/hot-loops/
trapdiff`, 21 fixtures) is also run unchanged: six build modes per fixture,
including `--max-frames` and `--max-steps`, plain and under `--gc-stress`, with
its accounting assertions intact — 504 built-binary comparisons, 0 mismatches.
Both sets are in `trap-matrix-fixed.json` and `historical-trapdiff.json`.

Two limits are stated rather than hidden: `mylang run` does not accept `--qbe`,
so GC stress is exercised on built binaries rather than through the driver; and
the probes are cheap enough that physical-stack exhaustion is bounded rather than
explored.

## 5. The full gate through the LLVM arm

`zig build test` **cannot** be run through the LLVM arm, and the reason is
structural: `build.zig` sets `MYLANG_QBE` for every test step to
`zig-out/bin/qbe` (line 238 assigns it, line 96 installs it), and no build
option overrides the backend. The Zig test roots therefore always exercise QBE.
Replacing `zig-out/bin/qbe` would be the only way in, and that is not something a
qualification should do to a shared tree.

What the gate runs *besides* the Zig roots **was** run through the arm, with the
same compiler and the same flags the step uses:

| gate step | through the LLVM arm |
|---|---|
| `mylang test tests/guest` | 42/42, exit 0 (§3) |
| `mylang test tests/lang --gc-stress` | 227/227, exit 0 (§3) |
| `mylang doctest .` | **144 examples run, 0 failed**, exit 0 |
| `mylang doc-coverage .` | static, no backend |
| `experiments/sexpr-port/golden_compare.py` | **17/17 passed** |
| `experiments/sexpr-port/compare.py` | **4/4 fixtures agree** with the reference reader |
| `zig build test` (Zig roots: `src/root_test.zig`, `test/integration.zig`, Guardian) | **not runnable** through the arm — see above |

Not claimed: the Zig test roots and Guardian. They were not run through the LLVM
arm and this report does not assert anything about them.

## 6. Runtime, paired

31 interleaved rounds of QBE O2 against LLVM O2, both arms built by the frozen
compiler with `--mode=ReleaseFast --keep-symbols`, parent and children pinned to
one physical CPU, all four workloads in every round, output verified on every
captured run. 1-minute load stayed between 0.36 and 1.3 for the whole batch.

| workload | QBE O2 | LLVM O2 | ratio | LLVM gain |
|---|---:|---:|---:|---:|
| census 927 KB | 4.84 ms | 3.99 ms | **1.214×** [1.188, 1.264] | 17.6% |
| render 927 KB | 9.79 ms | 8.05 ms | **1.216×** [1.196, 1.240] | 17.8% |
| census 7.42 MB | 39.29 ms | 31.35 ms | **1.253×** [1.242, 1.268] | 20.2% |
| render 7.42 MB | 89.50 ms | 72.94 ms | **1.227×** [1.220, 1.233] | 18.5% |

Brackets are 95% bootstrap intervals that resample **rounds**, preserving the
pairing. Per-round ratios (`measure-rounds.json`): **124 of 124 rounds favour
LLVM**, minimum 1.115, maximum 1.492.

| workload | QBE instructions | LLVM instructions | QBE cycles | LLVM cycles |
|---|---:|---:|---:|---:|
| census 927 KB | 48.9 M | 29.8 M (−39%) | 14.4 M | 10.4 M (−28%) |
| render 927 KB | 108.8 M | 74.4 M (−32%) | 32.9 M | 24.7 M (−25%) |
| census 7.42 MB | 421.4 M | 268.8 M (−36%) | 130.7 M | 98.6 M (−25%) |
| render 7.42 MB | 907.9 M | 633.2 M (−30%) | 295.9 M | 230.9 M (−22%) |

Counters are `cpu_core/instructions/u` and `cycles/u` from `perf stat`, sampled
in a separate matched batch because `perf stat` perturbs a short run's wall time;
they include the C runtime and libc.

**The gap did not close when the QBE arm got faster.** An earlier batch on the
`996a33e7` build measured census-7.42 at 40.43 ms and render-7.42 at 90.30 ms;
this revision measures 39.29 ms and 89.50 ms, and the LLVM arm improved by the
same proportion (32.30 → 31.35 ms, 75.01 → 72.94 ms), so the ratio is unchanged
within noise (1.252 → 1.253 and 1.204 → 1.227). The two emitter changes that
landed during the qualification — the re-enabled payload projection and the
record-constructor forwarding — helped both arms, not QBE alone.

## 7. Cost

Cold cache: the cache directory is deleted before every round, so the number
includes the frontend, every unit's code generation, the runtime archive, the
assembler and the link. Three interleaved rounds per arm, medians reported.

| arm | cold median | frontend | codegen | link | executable |
|---|---:|---:|---:|---:|---:|
| QBE | **4656.1 ms** | 0.749 s | 3.831 s | 0.028 s | 1 357 752 B |
| LLVM O2 | **13813.2 ms** | 0.762 s | 12.999 s | 0.030 s | 1 308 816 B |
| ratio | **2.97×** | 1.02× | **3.39×** | 1.07× | 0.96× |

Both arms report 101 compiled functions and 0 reused. The frontend differs by
2%, so **all of the difference is code generation**: the translator emits LLVM IR
for each unit and runs `zig cc -S -O2` on it, while QBE selects instructions
itself. The LLVM executable is 3.6% smaller.

## 8. Verdict and caveats

**Ready as an opt-in release backend; not yet ready to be the default.** The
language-level question the earlier decision turned on is now answered: there is
no construct in the tree the arm cannot build, no suite that disagrees with QBE,
and no trap that behaves differently. What is left is cost and coverage breadth.

Acceptable as-is for an opt-in arm:

* **Per-unit optimization only.** The tool sees one emitted unit at a time, so it
  cannot inline across guest functions. This bounds the win, it does not threaten
  correctness, and lifting it needs a manifest-aware build path — a separate arm.
* **The arm's own aggregate call convention.** Aggregate call boundaries use the
  arm's convention, not the target C ABI. Both ends of a build use the same
  convention, the generated entry point hands the guest only the context pointer
  and capability words, and the driver's object keys include the tool's stamp, so
  a cache cannot silently mix arms — but an LLVM-arm object is not a drop-in
  replacement for a QBE-arm object, and any future mixed-mode build must keep
  them apart deliberately.
* **It fails closed.** An unsupported opcode, type or calling shape raises
  `ParseError` naming unit, line and text; nothing falls back to QBE and nothing
  is silently replaced by zero. That is why the sweep could enumerate the gaps
  exactly instead of guessing at miscompiles.
* **Unrecognised runtime helpers refuse translation.** The generator reads
  C headers and Zig `@export`s; a helper declared some other way would need the
  table extended. Acceptable because it is loud.

Needs work before it becomes the default:

1. **Cold build cost.** 2.97× wall and 3.39× codegen is a real tax on every
   from-scratch build and on CI. It is the same order as before the frontend work
   (the frontend got 3.5× faster, and both arms got the benefit), so shrinking it
   means either parallel code generation across units or a cached-IR path — not a
   translator tweak.
2. **One workload family.** The 17–20% is census/render on two input sizes. A
   default switch should be justified on a broader corpus, and the per-unit limit
   above suggests the win will vary with call density.
3. **A concurrency defect in the driver, found while running this qualification**
   (§10). It drops tests and reports a smaller, still-green-looking summary. It
   affects both arms, but a backend used by default should not be qualified or
   run through a harness that can lose work silently.

## 9. Reproduction

One command runs the block; every stage records its identity hashes and writes
its evidence beside the others.

```sh
cd /home/epentland/ai/canopy/mylang
experiments/llvm-backend/qualify_all.sh /tmp/llvm-qual-run
```

The individual stages, in the order the report presents them:

```sh
M=.tmp/llvm-qual/bin/mylang-f5fa59a0          # frozen compiler
D=experiments/llvm-backend
E=experiments/llvm-backend/evidence/qualification-20260920

# 2. build coverage over every .my entry, both arms
python3 -B $D/qualify_sweep.py   --mylang $M --work /tmp/q/sweep --jobs 8 --json $E/build-sweep-fixed.json
# 3. byte-equality for the entries the as-found sweep failed
python3 -B $D/qualify_affected.py --mylang $M --work /tmp/q/aff --jobs 3 --json $E/affected-byte-equality.json
# 3. suites, both arms, separate caches, verdicts by name (sequential: see §10)
python3 -B $D/qualify_equiv.py   --mylang $M --work /tmp/q/eq --jobs 1 --json $E/equivalence-fixed.json
# 4. traps, ceilings, GC stress, exit status; then the historical set
python3 -B $D/qualify_traps.py   --mylang $M --work /tmp/q/tr --jobs 4 --json $E/trap-matrix-fixed.json
python3 -B $D/verify_traps.py    --work /tmp/q/htr --jobs 8 --json $E/historical-trapdiff.json
# 5. what the full gate runs besides the Zig roots, through each arm
$M doctest . --jobs 1 --report $E/doctest-qbe-serial.json
MYLANG_QBE=$PWD/$D/qbe_llvm.py $M doctest . --jobs 6 --report $E/doctest-llvm.json
python3 -B experiments/sexpr-port/golden_compare.py            # and again with MYLANG_QBE set
python3 -B experiments/sexpr-port/compare.py                   # and again with MYLANG_QBE set
# 6. paired runtime, then 7. cost
$M build experiments/sexpr-port/main.my -o /tmp/q/arm-qbe  --mode=ReleaseFast --keep-symbols --cache-dir=/tmp/q/cq
$M build experiments/sexpr-port/main.my -o /tmp/q/arm-llvm --mode=ReleaseFast --keep-symbols --cache-dir=/tmp/q/cl --qbe=$PWD/$D/qbe_llvm.py
python3 -B $D/measure.py --work /tmp/q/m --rounds 31 --skip-zig --cpu 6 --arms qbe,llvm-o2 \
  --binary qbe=/tmp/q/arm-qbe --binary llvm-o2=/tmp/q/arm-llvm --json $E/measure.json
python3 -B $D/qualify_cost.py --mylang $M --work /tmp/q/cost --rounds 3 --json $E/cost.json
```

## 10. Limitations

* **The harness can silently drop work under concurrency.** With roughly sixteen
  concurrent compilers on this machine, the driver's cache staging failed with
  `unexpected errno: 2` (ENOENT in `createDirPath`,
  `src/qbe_build_io.zig:160`), and `mylang test` then reported a *smaller*
  `N passed, 0 failed` and exited 2. Trigger: run several `mylang test <dir>` or
  `mylang doctest` invocations, each with `--jobs`, at the same time. Observed
  twice — `mylang test experiments/sexpr-port` lost 8 tests under a concurrent
  sweep, and `mylang doctest . --jobs 6` lost 2 of 144 examples while
  `--jobs 1` ran all 144 green. It hits the QBE arm too, so it is a driver
  defect, not an arm difference; it is recorded here rather than fixed because
  `src/qbe_build_io.zig` is outside this qualification's change budget. Every
  correctness number in this report was produced without concurrent load.
* **The Zig test roots were not run through the arm** (§5). The gate's guest
  steps, the documentation corpus and the port's own comparisons were.
* **`mylang run` does not accept `--qbe`**, so the arm is selected by the
  `MYLANG_QBE` environment variable for run-based drivers, and GC stress is
  exercised on built binaries rather than through the driver.
* **The workloads are the sexpr census and rendering** on 927 KB and 7.42 MB.
  They do not establish schematic-layout performance, and no other benchmark
  family was measured.
* **The translator is a subset, not a general QBE backend.** It supports the IL
  this frontend emits, targeting amd64 SysV Linux, with the integer aggregate
  subset; floating-point aggregate members, unions and other targets are outside
  what has been tested.
* **The revision is frozen, the tree is not.** Everything here describes
  `f5fa59a0` / `217838b2`; results from the `f42c3c9c` and `996a33e7` builds are
  kept in the evidence directory but are superseded and are not cited.
