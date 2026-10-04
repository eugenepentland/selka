# Runtime parity campaign evidence

Implementation branch: `perf/runtime-parity-20261003`. The integrated production
candidate is `730a86e62b47c922dc1411d24b5868c3bd2132f3`, based on runtime/compiler
sources matching main `1fd1d566`. Three `gpt-6.1-sol` agents using `xhigh`
implemented and measured bounded packages in separate worktrees. The original
working checkout and frozen benchmark sources/targets were preserved.

This campaign implements the measured candidates from the
[audit plan](../audit/README.md). It does **not** establish the goal of matching
every fastest-runtime target. Each of the 140 microbenchmark and 20 application
targets remains an individual acceptance decision. The final integrated full
run, correctness gates and independent timing confirmation passed.
Intermediate results retain their original source identities.

## Final integrated measurement

[Current fastest = 1.00](final-730a86e6-releasefast-20261003-fastest.md) ·
[All six absolute/frozen comparisons](final-730a86e6-releasefast-20261003-six-arm.md) ·
[Every MyLang target](final-730a86e6-releasefast-20261003-comparison.md) ·
[Full measurement receipt](final-730a86e6-releasefast-20261003-README.md) ·
[Code size and memory probes](final-730a86e6-releasefast-20261003-resources.md) ·
[Unseen-input checks](final-730a86e6-holdouts-20261003-README.md)

The ReleaseFast candidate ran all 40 cases at both sizes against Rust, Go,
Zig ReleaseSafe and Zig ReleaseFast, with LLVM and QBE as separate MyLang arms.
The run from 23:40 UTC on October 3 to 00:04 UTC on October 4 retained 7,200
samples, 720 qualification probes, 15 randomized rounds and three warmups.
Independent coordinator replay verified all 480 groups and 160 MyLang
comparisons with live artifact checks. CPU 2 was pinned; its sibling averaged
1.07% busy. Powersave and residual host-interference limitations remain.

| Targets | Numerically at or below frozen 1.00 | Above 1.00 but within 5% | More than 5% above |
|---|---:|---:|---:|
| LLVM, 80 targets | 4 | 3 | 73 |
| QBE, 80 targets | 3 | 0 | 77 |
| Both backends | 7 | 3 | 150 |

All seven numerical successes are microbenchmarks: LLVM byte scanning and
string search at both sizes, QBE byte scanning at both sizes and large string
search. Thus **153 of 160 targets remain above 1.00**, including all 20
application targets. Being within 5% does not satisfy the goal. Full-session
intervals suggest eight improvements versus the original winner rerun in the
same session, including small LLVM nested mutation, which remains 1.0081
against its frozen target. The separate confirmation run repeated all eight
with upper paired interval bounds below one. QBE improvements versus the
original winner do not imply it beats current LLVM.

The fresh confirmation pairs current-main and final ReleaseFast guests in the
same rounds. Large-input candidate/main ratios include:

| Case | LLVM | QBE |
|---|---:|---:|
| Integer arithmetic | 0.845 | 0.465 |
| Direct calls | 0.541 | 1.048 |
| JSON transformation | 0.314 | 0.394 |
| Lox evaluation | 0.520 | 0.512 |
| Byte scanning | 0.210 | 0.0246 |

Lower is better. JSON is 3.18×/2.54× faster and Lox 1.92×/1.95× faster in these
large-input LLVM/QBE comparisons. This does not close their frozen application
targets. Regressions remain: LLVM float arithmetic is 5.2–6.2% slower and QBE
direct calls/Result propagation about 4.8–5.0% slower, across the two sizes.
The corrected loop-specialization pass admits no compute specialization; its
paired results overlap the preceding scalar-policy candidate in all 24
backend/case/size checks. These regressions were already visible before the
dispatch experiment and remain unresolved.

The confirmation retained 2,310 samples across 154 groups. Independent replay
first exposed a verifier assumption that original winners were identical at
both sizes; string search switches from LLVM to QBE. A regression-tested fix
counts qualification probes per actual plan. The raw evidence was unchanged
and the coordinator's corrected replay passed all 154 groups. Confidence
intervals remain exploratory and uncorrected for multiple comparisons; a
second session reduces, but does not eliminate, selection and tuning bias.
See the [confirmation and regression tables](final-730a86e6-releasefast-confirmation-20261003-README.md)
and [coordinator replay receipt](validation/730a86e6-coordinator-replay.json).

The exact full report SHA256 is
`5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`.
The frozen baseline and audit target files retain their original hashes.

[Static before/after size receipts](validation/730a86e6-code-size-versus-main.json)
verify every MyLang executable against both reports before reading ELF section
sizes. Whole-guest `.text` ratios (final/current main) are:

| Guest group | LLVM | QBE |
|---|---:|---:|
| legacy | 0.935 | 0.933 |
| compute | 0.938 | 0.904 |
| collections | 1.016 | 0.979 |
| text | 1.069 | 1.071 |

These include runtime code and every kernel in a group. They measure static
code growth, not executed hot-loop cost or comparative compiler speed.

## Implemented work and remaining scope

| Package | Implemented and checked | Remaining scope |
|---|---|---|
| P0: evidence | Compiler/source/asset receipts; fixed historical and concurrent-original comparisons; micro profiles; hybrid-PMU attribution; controlled source/component diagnostics; ownership counts; unseen-input holdouts. | Throttled whole-process samples are hotspot hints. Holdout parameters preserve the original generator shapes; no measured population-coverage percentage is claimed. |
| P1: scalar lowering | Exact constant division/remainder, bounded loop facts, direct integer-to-float conversion, compact checked multiply-high, exact QBE zero simplifications. LLVM retains its native checked divide/remainder optimization through a cache-keyed backend policy. | General range inference and residual scalar/register costs remain. |
| P2: loops | Bounded unswitching of an immutable scalar selector, complete certified-literal coverage or refusal, original fallback and trap PCs, no step/frame-accounting bypass. A folded comparison must have no incoming edge inside its producer sequence. | The corrected compute fixture has no admitted specialization. The original twelve-copy/20.9% code-growth observation is superseded by the join correction; removing invariant dispatch from this fixture remains open. |
| P3: calls and values | Entry-call logical frame admission, leaf/record/Option/Result inlining, original error-return traces, inline dependency/cache tracking and retained physical bodies for nested provenance. | General indirect-target specialization and broader managed aggregate scalar replacement remain open. |
| P4: collections | Guarded small plain append/pop, composed scalar/read/byte loop paths, original cold/COW/alias paths. | Broader uniqueness propagation, nested transfer costs and managed variants remain. |
| P5: maps and sets | Plain publication avoids generic ownership helpers; duplicate unit-set additions avoid replacement; existing probe invalidation is retained. | General managed publication, scope/borrow overhead and more lookup/iteration work remain. |
| P6: text | Direct immutable text/byte equality, dedicated integer formatting and one-pass parsing. | Borrowing an encoded buffer needs allocation-budget and owner-lifetime proofs; simply removing the copy changes an observed refusal. Split/join ownership remains. |
| P7: allocation | A narrow, closed scalar-list stack path with real cached allocation tickets, whole-activation escape/refusal checks and conservative LLVM alias policy. An isolated eligibility comparison supports retaining it. | It does not admit frozen `alloc_short`; backedges, overlapping allocations, retained lists and general escape analysis remain open. |
| P8: applications | JSON scalar cursor, contiguous scanning, direct control classification and buffered serialization; unchanged application ports; sorting and snapshot residual attribution. | Static sort-key callback specialization and broader sort scratch/allocation work remain. No speculative threshold or benchmark algorithm change was made. |
| P9: QBE | A proved byte sum/XOR reduction calls a baseline-SSE2 runtime primitive, with scalar fallback and original checked slow paths. | Arbitrary vector loops, other spill/ABI gaps and a matched-ISA timing campaign remain open. Portable fallback correctness alone is not portable-policy performance evidence. |

The allocation experiment required a correctness correction before final
measurement: stack-capable units could inherit heap-only LLVM alias metadata.
The corrected emitter disables explicit and inferred alias metadata in those
units, and dynamic-index int/u8/bool translation tests cover the boundary.
The old experiment also ordered backend options incorrectly and supplied runtime
limits through ignored guest arguments. Its old alleged LLVM/ceiling results
are invalid for those claims. Corrected scripts assert the effective backend,
check accounting mode, and require actual triggered limits. See the
[allocation evidence and limitations](../../../experiments/runtime-parity-local-list-20261003/README.md).

Candidate `188da416` was also [rejected before timing](188da416-failed-qualification-20261003-README.md)
when frozen `branch_predictable` exposed an unsound P2 short-circuit fold on
both backends. Its existing full gate and LLVM corpus had passed; those results
did not cover this join. The corrected certificate scans all incoming bytecode
edges and leaves joined decisions intact. Eight admitted expression forms now
have 40 exact accounted/unaccounted QBE comparisons, including conditional
operands, zero trips and skipped division traps. A separate
[three-lane join diagnostic](../../../experiments/runtime-parity-arithmetic-20261003/unswitch-joins.md)
passes 432 executions over 144 inputs in accounted QBE, ReleaseFast QBE and
actual LLVM O3/LTO. It verifies the emitted specialization in every expression
form, the independent checksum oracle, exact output/failure behavior and real
accounting-limit triggers. The [archived receipts](validation/730a86e6-producer-joins.tar.gz)
bind those results to source `730a86e6`. Final validation is pinned to that revision.

Supporting evidence includes
[five cross-language component diagnostics](d348026f-components-20261003-README.md),
[isolated allocation eligibility](d348026f-b22dac0e-p7-eligible-20261003-README.md),
[original short-allocation elimination](alloc-short-original-reference-static-20261003-README.md),
[controlled scalar policy](main-before-policy-controlled-20261003-README.md),
[bulk byte reduction](main-scalar-bulk-controlled-20261003-README.md),
[whole-process ownership counts](ownership-20261003.md),
[sorting/retained-allocation profiles](current-main-p8-residuals-20261003-README.md),
[final profiles and remaining hotspots](final-730a86e6-residual-profiles-20261003-README.md),
[P2 code growth and semantic evidence](../../../experiments/runtime-parity-arithmetic-20261003/p2-unswitch.md),
and [map/set path evidence](../../../experiments/runtime-parity-arithmetic-20261003/p5-dictionary-paths.md).
Each report distinguishes observations from causal cost or parity claims.

All 40 final profiles passed their exact checksum and archive-identity checks.
Seven have fewer than 200 samples, eight hit iteration caps, 36 miss the
requested duration, and all retain throttle records. They remain qualified
hotspot evidence; none passes every sampling-quality flag. Their limitations
do not apply to the separately collected ordinary timing samples. Remaining
named work includes native sorting, retained allocation/draining, nested
transfer/clone/release, float-helper work and generated compute bodies. These
samples do not prove which change caused a regression or an additive share of
application cost. The narrow byte-scan profiles are too sparse for strong
proportional claims.

The final [ReleaseFast build and static receipts](730a86e6-releasefast-build-static-20261003-README.md)
bind all eight MyLang guests to the corrected compiler and installed runtime.
An independent replay of the
[corrected-source paired screen](main-policy-730a86e6-debug-controlled-20261003-README.md)
passed all 108 groups. It retains the LLVM floating-point and QBE Result
regressions against current main rather than averaging them into larger wins.
The screen uses a Debug candidate host; final acceptance uses the separately
built ReleaseFast host. All guests use ReleaseFast, with actual backend
manifests checked before and after measurement.

The separate allocation witness measures LLVM at 59.974 → 22.571 ns/call
(after/before 0.376, paired interval 0.362–0.403) and QBE at 78.205 → 36.874
ns/call (0.472, 0.446–0.506). Those are 15-round exploratory measurements with
matching Debug host compilers and ReleaseFast guests. QBE admission is witnessed
through the timed guest's objects; LLVM admission uses an explicitly non-LTO
companion while the timed LLVM guest uses O3/LTO. These results support this
mechanism, not the frozen `alloc_short` target or broad allocation parity.
The [corrected semantic archive](validation/b22dac0e-allocation-corrected.tar.gz)
preserves 136 exact outcomes, 32 accounting-mode probes, four C proof replays,
source/artifact hashes, manifests and logs. Its source/artifact capture is
retrospective, not a pre-build attestation; binaries are hash-recorded rather
than copied into the archive.

## Final correctness validation

[The validation receipt](validation/730a86e6-validation.json) binds clean source
`730a86e6` and the unchanged Debug compiler/QBE hashes before and after testing.
The full four-shard gate passed 97/97 steps and 2,903 host tests. Both the RC and
GC-stress guest corpora passed 1,579 tests from 239 programs with no cached,
failed or skipped cases. A separate fresh LLVM ReleaseFast corpus passed the
same 1,579 cases. The native boundary matrix had 68 agreements; module oracles
had no differences; documentation checks ran 228 examples and checked 57 more,
with 11 explicit skips and no failures.

Zig emitted a 2.34 GB peak-memory diagnostic for one successful four-shard test
process against its declared 2 GiB ceiling, yet returned success. A rerun using
the repository default of 12 shards passed 109/109 steps with no such diagnostic,
without raising limits. That rerun reuses successful unchanged steps; its counts
are not additional independent tests. Both complete logs and the fresh LLVM
case records are retained beside the receipt. Performance qualification uses
the separately pinned ReleaseFast compiler and guests.

Broader semantic cases include all control characters, mixed Unicode and
surrogate escapes, empty strings, malformed JSON offsets and duplicate keys
in `tests/lang/standard_json.my`; view lifetime, arena escape and retention in
`text_views.my`; aliased growth, callbacks, snapshots and plain/managed payloads
in `rc_plain_appends.my`; and deletion histories/equal-but-distinct keys in
`scalar_dictionary_publication.my`. The fresh corpus records every named result.
These support correctness beyond the timed fixture generators; they do not
establish a population coverage percentage or performance on those extra shapes.

## Fresh current-main baseline

`current-main-1fd1d566-20261003` is a fresh baseline of runtime/compiler sources
exactly matching main `1fd1d566793dcae92449d937aca595c55ee318c8`. The benchmark
harness is committed at `89f4f85b`. The compiler build receipt records a
ReleaseFast compiler-only build through `scripts/build-slot.sh`, private Zig
caches, disk TMPDIR and `-j2`. MyLang guests were rebuilt; reference guests were
copied only after checking their original manifest, executable, source and
toolchain hashes. The raw report includes these receipts and original commands.

The complete run took place from 20:04 to 20:33 UTC on 2026-10-03. All 40 cases
ran at both frozen sizes with six current arms, 15 randomized rounds and three
warmups. It saved 7,200 samples and 720 checksum qualification probes. The seven
plans originally won by MyLang also ran the original MyLang executable in the
same session: 105 supplemental reference samples and 21 warmups. Every guest
acquired the campaign timing lock and ran on CPU 2. Its sibling averaged 3.50%
busy; the recorded governor was powersave. Average activity does not exclude
short interference or frequency drift.

Both the independent verifier and candidate comparison passed with
`--check-artifacts` before subsequent harness edits. Compiler/runtime source
bytes and benchmark assets matched their receipts before and after sampling.
These are local provenance checks, not an independently attested build.

The raw report SHA256 is
`f2e24958ec044a12de49d93c73108ebfa8e2ccd2dcd9e94f92dfce38b3b9d5f9`.
The comparison SHA256 is
`873c83e8b9af6dbc43982915c58cf96891575f7c009f715305b29f7045246a89`.
The gzip files preserve the exact uncompressed JSON bytes. Replay without live
artifact checks after decompression:

```sh
gzip -dc benchmarks/runtime/candidates/current-main-1fd1d566-20261003.json.gz > /tmp/current-main.json
python3 benchmarks/runtime/expanded/verify.py /tmp/current-main.json
python3 benchmarks/runtime/compare_candidate.py /tmp/current-main.json --output /tmp/current-main-comparison.json
```

In this current-main baseline, all 160 backend/case/size targets were numerically
above the immutable historical targets. Against the original winner rerun in the same session,
LLVM has 73 intervals wholly above one and seven inconclusive intervals; QBE
has 79 wholly above one and one inconclusive interval. These exploratory
intervals do not correct for repeated tuning or multiple comparisons. No
independent confirmation or campaign improvement is claimed by this baseline.

Large application ratios are shown separately; lower is better:

| Application | LLVM / frozen target | LLVM / concurrent original | QBE / frozen target | QBE / concurrent original |
|---|---:|---:|---:|---:|
| packet_decode | 2.647 | 2.504 | 13.764 | 13.020 |
| lox_eval | 11.248 | 6.895 | 11.778 | 7.220 |
| word_count | 10.788 | 8.809 | 14.003 | 11.434 |
| csv_aggregate | 9.684 | 7.640 | 13.751 | 10.849 |
| json_transform | 32.705 | 27.117 | 42.107 | 34.912 |

Calibration limits are retained for every affected row. In particular,
`alloc_short` permits optimizer elimination, with exceptionally short reference
pilots; its very large ratios do not measure physical allocation cost. The subsequent
[original-reference dispatch extraction](alloc-short-original-reference-static-20261003-README.md)
locates its selected nine-instruction case body and eliminated inner
construction loop. That evidence explains why the target requires allocation
elision; it does not waive the frozen target or make whole-process allocation
counts a measurement of the timed kernel.
