# Lox evaluator improvements, 2026-10-02

Three parallel source changes reduce the checked Lox evaluator's VM runtime
by **18.73% with LLVM** and
**13.93% with QBE**, as geometric means over all 13
benchmark scripts. Tree runtime decreases **3.77% with LLVM** and **4.41% with QBE**.
The compiler and runtime implementations
remain main `6df58b02554401f9d37564cceffd14277a835ae1`; this is an evaluator
source improvement.

The integrated source is reconstructed by
`docs/audits/d9-stage3d-migrations/apply-lox.sh WORK --optimized`. The new
`lox-runtime-perf-20261002.patch` follows the existing source migration. Its
SHA-256 is `44fc88224c39006b3e6053dabb602eb82f66f7e6187b97e3e93441772dcb2dfd`.
Unoptimized migration behavior is unchanged. Implementation and evidence
live on `codex/lox-perf-improvements-20261002`; main and the preexisting dirty
`local-reasoning/integration` checkout were left untouched.

## Changes and semantics

- **Frames:** dispatch one activation per `vm.run` call, retaining the caller's
  existing `ExecFrame` across a child call. Return resumes that frame rather
  than rebuilding its code/constants/upvalue list descriptors. Calls that
  add no Lox frame continue in the current dispatcher. Existing frame roots,
  published instruction pointers, error reset/unwind and `FRAMES_MAX == 64`
  remain authoritative. Native dispatcher recursion is bounded by that limit.
- **Stack:** read tagged numeric operands once and replace the surviving
  stack slot directly for arithmetic/comparison/negation. Compute before
  shrinking the root interval. Allocating string addition keeps its original
  path. Normal indexed writes retain snapshot/COW and bounds checking.
- **Lookup:** return scalar instance-field/method results before allocation
  or mutation, sharing the name hash between field and method reads. Fields
  containing nil/false still shadow methods; method binding retains its roots.
  Read-only table probes skip insertion bookkeeping and return the value
  directly. Insert/delete and tombstone reuse remain unchanged. Tree property,
  super and initializer reads use scalar helpers, and setter writes retain the
  original receiver and current fields after evaluating the RHS.

Seven meaningful port tests and four matching driver providers were added.
The composed patch changes eight files, preserves all 65 existing tests, and
contains 72 unique public tests. Independent review verified exact lane
composition, all original fixtures, root/error ordering and bounded recursion.

## Measured results

All percentages below are **reductions relative to the unchanged audited
optimized port**, using median candidate/control ratios paired within each
round, then geometric means across scripts. Positive values mean less time
or fewer instructions.

| Engine | LLVM wall time | QBE wall time | LLVM instructions | QBE instructions |
|---|---:|---:|---:|---:|
| VM | 18.73% | 13.93% | 15.99% | 13.33% |
| Tree | 3.77% | 4.41% | 3.95% | 2.94% |

| Script | VM LLVM time | VM QBE time | Tree LLVM time | Tree QBE time |
|---|---:|---:|---:|---:|
| binary_trees | +11.73% | +7.47% | +11.36% | +9.80% |
| closures | +14.53% | +10.23% | +0.06% | +0.66% |
| equality | +3.39% | +3.32% | -0.29% | +0.49% |
| fib | +28.67% | +18.68% | +1.10% | -0.34% |
| instantiation | +7.12% | +7.22% | -0.30% | +3.43% |
| invocation | +25.22% | +24.07% | +3.48% | +7.30% |
| method_call | +25.59% | +16.47% | +10.29% | +10.04% |
| properties | +31.69% | +23.02% | +5.46% | +7.41% |
| string_equality | -1.14% | +3.26% | +0.07% | -0.34% |
| strings | +5.51% | +2.71% | -0.76% | -0.07% |
| trees | +27.54% | +16.53% | +6.09% | +5.62% |
| zoo | +28.01% | +22.55% | +5.23% | +6.17% |
| zoo_batch | +26.25% | +21.01% | +6.14% | +6.24% |

The largest median wall-time regression is LLVM VM `string_equality`, at
**1.14% slower**. Six tree engine/backend cells are **0.07–0.76% slower**;
the table includes each. Three rounds do not establish the statistical
significance of these small changes. No individual baseline-to-joined
instruction sample or median case increases on either engine/backend.
Two lanes change VM execution only, so tree gains are smaller.

Median `(max paired ratio - min paired ratio) / median paired ratio` across
the three rounds:

- vm/llvm: median paired-ratio spread 1.20%.
- vm/qbe: median paired-ratio spread 0.51%.
- tree/llvm: median paired-ratio spread 1.00%.
- tree/qbe: median paired-ratio spread 0.75%.

Individual VM instruction diagnostics isolate the lanes:

| Source lane | LLVM instructions | QBE instructions |
|---|---:|---:|
| Frames | 4.94% | 6.38% |
| Stack | 4.15% | 2.56% |
| Lookup (final) | 7.96% | 4.32% |
| Joined | 15.99% | 13.33% |

Frames use three rounds, stack uses two, and final lookup uses three. They
use the same calibrated tree-sized VM inputs. These are diagnostics rather
than additive speedups or separate final wall-time acceptance. Initial lookup
receipts remain preserved; the final lookup and joined sweeps use the version
that retains the original class-kind assertion order.

## Measurement controls and limits

- Frozen ReleaseFast compiler SHA-256:
  `45d05b554849bf3c12553549d9138556ba0204f9d59ba3aaa2ecb2327eb39ac4`.
  Baseline source is the old `apply-lox.sh --optimized` at audit commit
  `bbefb77f711076b036bb581b0986ac91eec05ca9`; all 26 source hashes match the
  previous audit. References and inputs remain `4e48a09220c2e018eba8c4b1eb3fe1137a3dae73`.
- Timed guests use explicit checked RC and symbols. LLVM uses O3/full LTO;
  QBE uses the same frozen compiler and RC policy. Separate native GC builds
  serve correctness probes. Ownership sites builds are diagnostic only.
- **312 timed executions:** 13 scripts × both engines × four arms × three
  rounds at the original engine-specific input sizes. Arms are shuffled and
  interleaved per case/round, with exact expected stdout, zero status and empty
  stderr. Every input and executable hash is checked after the sweep.
- **468 counter executions:** 13 scripts × both engines × six arms × three
  rounds at unchanged calibrated tree sizes. Six arms include unchanged,
  joined and final lookup on both backends. Instructions, cycles, branches
  and branch misses all report 100% running time. Source/executable/input
  identities and all case/round/arm coverage were independently verified.
- Wall time is pinned to CPU 2, counters to CPU 10, on the i7-12700H. Siblings
  3/11 are reserved too. Builds/tests use `scripts/build-slot.sh`; quiet checks
  precede measurements. The host uses its existing powersave governor.
- Three rounds establish a focused evaluator comparison, not the full
  43-program compiler performance gate. Reference runtimes were not retimed
  here, so the previous audit's Zig ratios are not new matched wall ratios.
  The substantial compiler-generated ownership/checking work remains.

Joined guest SHA-256:

- LLVM: `9b4f3c1b2f6701edcd060fae8a8a5556c4812114836eb55016fd78e2bfccacbf`.
- QBE: `07dec25e2d797ba80681bd4304783378d55502e8a9e66482125ed27d0fae112b`.

## Ownership and memory diagnostics

At fib N=28, owner acquisitions fall from 6,176,885 to 3,091,514 (**49.95%**).
At properties N=100,000, they fall from 24,108,727 to 9,108,724 (**62.22%**),
and holds fall from 12,119,517 to 119,517 (**99.01%**). Frame list publications
are approximately halved in both cases. Allocation/retirement and clone-shell
counts remain unchanged; holds balance, and owner releases equal owner
acquisitions plus fresh allocations. No counter saturation or limit failures
occur. Independent review checked these against the prior sealed baseline.

**Total uniqueness checks remain unchanged**: 14,929,348 on fib and 25,322,000
on properties. Arithmetic shifts writes from push to surviving slots; it
does not establish stack uniqueness or remove generic checks. That compiler
proof/lowering work remains a future target, along with broader tree ownership
and the extra work QBE emits.

The frame change uses native stack space proportional to Lox call depth.
Single diagnostic depth-60 VM peak-RSS samples were 4,032 → 4,280 KiB LLVM
and 4,308 → 4,808 KiB QBE. These measure the joined evaluator; they do not
isolate dispatcher stack bytes or establish a memory distribution. The
unchanged 64-frame bound and exact overflow diagnostic are covered by probes.

## Correctness and gate receipts

- **288/288 fresh port tests:** all 72 on QBE Debug and LLVM release under
  normal RC and separately under native GC stress. No failures, skips, cached
  results, missing tests or unloaded modules. Tests use `--force`, one-billion
  steps and 180-second timeout allowances for the existing/new Lox stress
  tests; production runtime/benchmark checks are unchanged.
- **104/104 joined smoke executions:** all 13 scripts × both engines × four
  RC arms, exact output and identical Lox allocations/collections/freed/live.
- **192 exact regression pairs:** 12 independently specified programs × both
  engines × Lox stress normal/enabled × both backends × RC/native GC stress.
  Expected stdout, full baseline observations and collector statistics match.
- **184 exact VM diagnostic pairs:** 23 error cases × Lox stress
  normal/enabled × both backends × RC/native GC stress, preserving status,
  output, error text and frame/IP traces.
- **256 successful activation runs:** eight additional probes × both engines
  × Lox stress normal/enabled × reference/candidate × both backends ×
  RC/native GC stress. They cover closures, suspended/open and closed
  upvalues, roots replaced during child allocation, bound/super calls,
  no-frame calls, deep calls and repeated frame-slot reuse.
- Canonical migration replay matches all 30 port files and 26 modules byte
  for byte. Sources, providers and frozen compiler remain unchanged after
  tests. Python syntax, shell syntax and source whitespace checks pass.
- Each lane's automatic Guardian whole-tree pre-commit gate passed all 88
  checks. No Guardian baselines or waivers were accepted. The final integration
  gate receipt is retained with the raw evidence.

The lookup lane's own bounded native GC smoke matrix has 1,104 matched
observations and 48 explicitly unrun tree observations. This is preserved as
a partial matrix. The joined native GC qualification consists of the complete
72-test suite and the specific regression/activation/error probes above;
the timed all-13 sweep and joined smoke/statistics sweep use RC.

## Reproduction and sealed evidence

See [build and replay instructions](../../experiments/lox-perf-improvements-20261002/README.md).
Individual overlays expect the old audit revision; current optimized
`apply-lox.sh` already includes all three and must not receive them twice.
The preserved `.tmp-lox-improvements/binaries.json` maps exact controls,
individual lanes, final lookup and joined guests to source hashes. Raw
measurements contain every sample rather than aggregate ratios alone.

Self-contained evidence is outside Git at
`/home/epentland/ai/canopy/evidence/lox-perf-improvements-20261002/integration`. It preserves **914 payloads**: raw
measurements and validation logs/receipts, exact build/test commands,
independent reviews, original/initial/final source and input archives, the
measured/validation guest ELFs, and sealed individual lane evidence. Its
`MANIFEST.sha256` hash is
`37d9a4198f25382178f56bbf886898a05bca70c993de54d4cdaa69d357faf437`; every payload was verified after sealing.
The preceding audit and its frozen compiler remain in the separate audit
worktree and evidence archive.
