# WP-A3 typing closeout — 2026-09-29

WP-A3 implements float module constants and checked float-to-integer casts on
`codex/next-typing-20260929`, starting from `claude/typing` `4d6ffdf7`. The nine-file
unfinished diff and two float-constant guest fixtures from `claude-typing` were
copied into this isolated worktree; the original worktree was preserved.

Implementation commit: `aac69d9f426992bc7d2779a3e9446dd857825e54`. All checks below use the final source and the
private compiler snapshot `.tmp/a3/frozen-final/bin/mylang`, SHA-256
`bed296f2da5a4bf89f6e0ee643558c7045e4b75f36304a17fcf4f4d2ce18f298`.
No source or installed compiler bytes changed during the final gate or corpus
run. Caches and scratch are private to this worktree; all Zig builds and heavy
guest commands use `scripts/build-slot.sh`.

## Behavior and regressions

- `CONST-FLOAT-1/2/3`: float and aliased float constants retain binary64 values
  across ordinary/generic bodies, imports and `noalloc` reads. Constant arithmetic
  uses strict binary64 operations, including rounding-sensitive addition,
  integer conversion, division, floor/remainder and intrinsics. Negative zero
  retains its sign. Overflowing literals are rejected; nonfinite arithmetic
  remains permitted under the existing canonical observed-NaN policy. Interfaces
  retain initializer spelling and expand public aliases.
- `FLOAT-INTEGER-CAST-1`: every signed/unsigned fixed width accepts `float` and
  truncates toward zero before checking exact half-open power-of-two bounds.
  `i8(-128.5)` yields -128; `u8(-0.5)` yields 0. NaN, either infinity and an
  out-of-range truncated value trap `R_FLOAT_CONVERSION` before any native or LLVM
  float-to-integer operation. `int(float)` uses the checked `i64` rule.
- `NUM-LITERAL-4`: the lane base lacked the integration branch's silent hint fix.
  It is included here and strengthened with a side-effect-free declaration-policy
  inspection before constant resolution, including re-exports. Ordinary names
  never enter `Names.reference` merely to infer a literal hint. A direct Zig
  regression checks that declaration inspection leaves `project.problem` empty;
  guest regressions cover imported enum cases and ordinary function names.

Guest coverage adds 13 float-constant tests and eight integer-cast tests. Zig
rejections cover literal/type/operator errors and invalid constant conversions.
The final float-focused Zig selection passed 41/41. Independent default-QBE and
LLVM-release probes each passed 45 invalid conversions and nine valid boundaries,
including exact signed/unsigned 64-bit limits and fractional lower edges. Manual
interface generation/listing for infinity, negative infinity, NaN and negative
zero was stable across repeated listings; runtime output retained `-0.0`.

## Gate

All 20 recorded stage statuses are zero. Build-step counts include permitted Zig
cache reuse; the forced guest runs below have zero cached tests.

| Check | Final result |
| --- | --- |
| `zig build` | Installed compiler and bundled runtimes; Guardian 88/88 |
| `zig build test` | 96/96 steps, 2,600 selected tests passed |
| `test-qbe` | 51/51 steps, 479/479 tests |
| `test-qbe-build` | 29/29 steps |
| `fmt-check` | 2/2 steps |
| `test-native-memory` / `test-native-heap` | 23/23 and 10/10 steps |
| Guests: default, GC, release, counted RC, GC stress | Each 1,382/1,382 across 213 programs; zero cached/failed/skipped/dropped |
| Embed: default, GC, release | Each 8/8; default covered in the final full guest run, GC/release also checked directly |
| Lox: default and GC | Each project build, 65/65 tests across 10 programs and 13/13 driver cases; zero cached/failed/skipped/dropped |
| `test-rc-fuzz -Dfuzz-seeds=100` | 21/21 build steps; 98 ok, 0 invalid, 2 stress-only, 0 RC divergences |

Fuzz seeds 1–100 ran with three workers, alternating both generators and adding
LLVM-release RC every eighth seed. The report-only GC-stress findings are seed
19 (exit 134, descriptor scan-plan/fields disagreement, stdout/stderr differences)
and seed 87 (exit 139, stdout difference). There were no ordinary/counting/release
RC divergences. The generated cases and complete summary are retained in
`experiments/rc-fuzz/out/{found/s19.my,found/s87.my,summary.json}`. The plan
explicitly permits these known collector-only findings; this closeout does not
resolve the separate GC-stress backlog.

The full Zig gate executed 2,600 selected tests. Its aggregate summary shows
26,617 skips because each shard excludes tests assigned to the other shards;
selected-test runner results have zero skips. Documentation coverage found 208
documented features; doctests ran 214 examples and checked 55, with zero failures
or mis-tagged examples. Eleven explicit documentation skips remain: one removed
feature in `docs/audits/language-simplicity-2026-09-12.md`, two host/fragment
examples in `docs/byte-io-bulk.md`, one fragment each in
`docs/experiments/module-discovery.md`, `docs/experiments/module-interfaces.md`
and `docs/experiments/source-codecs.md`, four proposed-syntax examples in
`docs/named-constraints-proposal.md`, and one library fragment in
`docs/tooling/invoke.md`.

## Performance

The final 58/58 unique corpus builds were generated by the frozen compiler.
Development and smoke measurements each cover all 43 rows on both backends,
with 86/86 RC/GC output matches and zero failures. Timing CPUs were 2, 3, 10, 11.
The original m14 development and smoke JSON baselines were copied without edits.

| Size | Backend | m14 RC/GC geomean | Final geomean | Worst ratio | Rows ≤1.3 | Largest RC instruction increase |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| dev | QBE | 1.074153 | 1.065192 | 1.281561 | 43/43 | 0.13343% |
| dev | LLVM | 1.085282 | 1.070313 | 1.256200 | 43/43 | 0.18317% |
| smoke | QBE | 1.115238 | 1.105918 | 1.522276 | 38/43 | 0.13342% |
| smoke | LLVM | 1.157976 | 1.141994 | 2.381445 | 35/43 | 0.18317% |

No row regresses by more than 1% on either backend. Every development row meets
the 1.3 acceptance limit. Smoke ratios include the lane's earlier ancestry before
the integration startup fixes; its existing cap misses also occur in m14. The
final merged gate must compare against the completed A1 baseline.

An initial implementation appended narrow conversions to the existing hot float
switch. The corpus caught three QBE instruction regressions. A separate,
statically selected narrow-conversion helper removes that dispatch cost:

| QBE row | Rejected implementation vs m14 | Final vs m14 |
| --- | ---: | ---: |
| `parity/micro/float_loop` | +17.64270% | -0.00088% |
| `parity/suite/spectral_norm` | +8.21620% | -0.00028% |
| `parity/suite/raytrace` | +4.53134% | -0.00020% |

Existing unary op ordinals 0–11 are unchanged and compile-time asserted. The six
new narrow ops occupy 12–17. `myl_qbe_float_unary` is source-identical to the lane
base; the new helper is separately declared in the native/LLVM runtime ABI and
the RC quiet-call catalogs. The initial failed performance results and interrupted
intermediate gate remain under `.tmp/a3/before-dispatch-fix/`; they are not counted
as final validation.

Changes above 1% in magnitude are all improvements against the pre-batch m14
baseline: LLVM knucleotide -1.704%, QBE/LLVM nbody -4.327%/-22.283%, QBE/LLVM
sort_quick -17.431%/-22.707%, QBE/LLVM scan_split -3.149%/-2.647%, and QBE
bytes_scan -7.246%. These comparisons include already committed lane ancestry;
they are not isolated measurements of the new constant/cast feature. All other
instruction changes are within 1%. Exact per-row counts, input hashes, compiler
hashes and rejected/final measurements are preserved in
`typing-closeout-performance-2026-09-29.json`.

## Evidence and handoff

Final command statuses are in `.tmp/a3/summary.txt`; full logs are
`.tmp/a3/{zig-test,qbe,qbe-build,fmt,native-memory,native-heap,guests-*,embed-*,fuzz,lox-*}.log`.
Probe logs are `qbe-traps-final.log`, `llvm-traps-final.log` and
`focused-zig-final.log`; corpus build/measure/compare logs use
`quick-*-all-final*.log`. Final source, compiler snapshots, intermediate evidence
and the original source worktree remain available.

Guardian's final normal build passed all 88 checks without baseline exceptions.
The cognitive-complexity check caught the generic expression checker at 26/25;
extracting the integer-cast helper retained the limit. The expanded unary ABI
assertion was split after reaching 256 columns against the 240-column limit.
The cold standalone `--full` gate passed all 88 checks; the normal implementation
commit hook confirmed zero blocking findings using that green stamp. The exact
`expressionValue` complexity subject was labelled `useful-review`
(`subj_915ad34935bdd9fe50e32417`), assigning the shared failed-install cycle once.
The ABI line-length finding was verified at its original `src/qbe.zig:2958`
location, but telemetry groups its 101 QBE locations, including existing advisory
lines, under one per-file subject/observation ID. That broad item and unrelated
pending subjects remain unlabelled; attributing them all to this task would
misclassify existing warnings. The parent appended and committed this task's
Guardian feedback in `guardian-zig` as `8037b10`, covering both catches and the
ROI grouping limitation. This lane makes no main merge, push or source-worktree removal; the
parent owns integration and the plan's user approval checkpoint.
