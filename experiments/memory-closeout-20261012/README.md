# Memory-management closeout, 12 October 2026

The user revised the stopping point: finish the complete verification gate, record
performance differences already measured, then stop. Further performance work,
default promotion and legacy RC retirement are deferred. The complete gate passed on
`941bf4c18449492dadaf1a17ba20e35ff702ba0e`. Work is stopped at that endpoint.
[Final receipt](coordinator/exploratory-verify-02/attempt-5.json) ·
[Machine-readable results](results.json).

Work is local on `codex/memory-closeout-20261012`. C0 is
`fbfcaa7a923186a8e773c3760f81c10aa345a432`, exactly `origin/development` at kickoff;
both documented ancestor checks passed. One coordinator and ten workers ran in
separate sibling worktrees. After A06/A07 became unavailable, the coordinator and
existing workers completed their saved followups. The original dirty checkout,
GitHub branches and immutable bootstrap seed history remain untouched.
[Kickoff and tools](kickoff.json) · [item ledger](ledger.json).

| Original milestone | Status at the revised stopping point |
| --- | --- |
| Qualified implementation | Not claimed: expanded common qualification and measurements remain incomplete |
| Zero-RC default | Deferred; checked ownership remains opt-in |
| Active legacy RC retirement | Deferred; active guest RC/COW remains |

## Final verification

`verify_cache.py` completed all 45 selected actions fresh, with zero reused
verification receipts and stable frozen inputs. Zig reported 135/135 build steps
and 3,061 test-pass entries; shard-filtered skip entries remain in the raw receipt.
Live-source formatting passed all 858 checked files. Guardian passed all 88 checks
both in the gate and in a separate whole-tree run. The exact command, selected
component inputs, compiler and installed-component hashes, action keys and raw
logs are preserved with the [receipt](coordinator/exploratory-verify-02/attempt-5.json).
Evidence/report-only commits after that revision do not change the tested source.
No further benchmarks or implementation changes followed the green gate.

## Integrated implementation

The branch includes bounded parallel-map chunks; the user-approved Result-list
support; capacity arithmetic guards; managed list operations; explicit-copy library
and application migrations; checked guest-test command/cache plumbing; and fixes
for transfers, borrowed selections, tuple unpacking, field writebacks, numeric ABI,
provider cleanup and warm generic memo cache hydration. Ownership and lifetime
annotations were not added to the language.

The complete registered gate includes compiler tests, guest tests, documentation,
formatting, lint and Guardian requirements. Its earlier failures are preserved under
[verification attempts](coordinator/exploratory-verify-02/attempt-3.json). Followup
fixes restore the original record-copy bounds and moving-Unicode-cursor bound,
update stale admitted-operation and generated-unit expectations, preserve extrema
assertions behind lint-compatible wrappers, discover the current cache format, and
forward the exact selected pin/archive into the real empty-PATH bootstrap test.
Focused worker passes do not substitute for the complete gate.

Recursive structural equality remains an explicit checked-ownership limitation.
Its new borrowed implementation passed focused native tests but failed a recursive
canonical-cache shadow comparison. The [unapplied patch and reproducer](A10/equality/handoff.md)
are preserved. No test was dropped to qualify it and no RC fallback was introduced.

## Shared-compiler evidence

Support7 is the earlier measured compiler, source
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`, SHA256
`540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
Its complete installation and selected owned-component recipe are pinned in the
[installation identity](coordinator/support7/support7-identity.json). These results
are not relabeled as results for the later gate revision.

- [Census](A03/Support7-full/REPORT.md): 435 builds and 695 counted executions pass
  across five modes, including all original 30 cases and the expanded corpus.
  Normal counted runs have correct output, zero RC events and zero managed exit-live
  bytes, with LLVM/symbol checks. The original 30 allocation counts are below.
- [Four application shapes](coordinator/support7/applications/summary.json):
  20 builds and 60 counted executions pass, including parallel workers 1/2/8.
- A04's 80 public functions and five types are classified; its expanded original
  source suite passes 1,330 checked/ordinary native tests. A05's remaining exports
  are classified, but its Support7 matrix has four warm-memo failures among 180
  native lanes; the subsequent fix has focused evidence, not a final common rerun.
- A01's shared-compiler map, Result, trap, cleanup and supported ThreadSanitizer/task
  stress matrices pass. Intentional fatal exits are reported separately from normal
  managed-leak checks.
- The actual owned installation passes 42 component tests and 688 fresh counted
  protocol cases. A08's 39 cache probes pass. Compile scaling remains unmeasured.

| Original 30, workload allocations | Allocating | Allocation-free | Refused / executing RC |
| --- | ---: | ---: | ---: |
| Release, verified release, optimized debug | 23 | 7 | 0 / 0 |
| Unoptimized debug, release without facts | 28 | 2 | 0 / 0 |

Whole-program accounting includes entry/setup and reports allocations in all 30.
The broader guest-source survey retains failures and unsupported contracts in its
denominator; passing the pinned census does not qualify every language shape.

## Performance and package boundaries

The [performance handoff](A09/final-performance-handoff.md) and its
[machine-readable data](A09/final-performance-handoff.json) preserve 15 matched
C0/Support7 counter configurations per compiler and three completed runtime cases
(66 observations). Remaining runtime cases, valid
final RSS comparisons and compile scaling are deferred at the user's request.

| Recorded guest workload | C0 median | Support7 median | Change |
| --- | ---: | ---: | ---: |
| JSON array lookup | 310.611 ms | 302.566 ms | −2.59% |
| JSON object lookup | 316.188 ms | 302.066 ms | −4.47% |
| Record unpack | 173.003 ms | 169.327 ms | −2.12%; ranges overlap |

These are two warmup pairs and nine alternating measured pairs per case, on the
same host and matched inputs. Full ranges and all samples are retained in the
handoff. Parallel workloads show substantial managed-allocation reductions, but
their runtime and RSS comparisons were deferred.

Instrumented allocation traffic, managed peaks, guest time and process RSS are
separate metrics. Earlier launcher-contaminated RSS observations are invalid.

The original A01 prototype reduced 4,097-element cheap-map total allocations from
12,308 to 16/37/111 at 1/2/8 workers. This is identified prototype evidence, not a
final timing claim; output and independently owned callback results may still grow
with input size. [Map evidence](A01/handoff.md).

A02 retained the existing capacity growth policy after its bounded comparison:
smaller initial capacities reduce singleton storage but increase reallocation
traffic elsewhere. It is a measured rejected experiment, not a production saving.
[Capacity decision](A02/README.md).

The later text cursor repair reduces measured walked bytes from 1,201,439,895 to
1,639,865 on its recorded fixture, with unchanged managed allocation metrics.
The record-writeback repair restores two existing LLVM memcpy counts from 2 to 0.
These are operation-count observations on their respective worker artifacts; they
are not guest-time or RSS measurements on the final gate compiler.

The verification build uses an explicitly qualified owned component compiler pin
and matching source archive. This avoids the immutable historical seed's known
native-object lifetime defect without rewriting or silently repinning that seed.
Normal component default selection and active guest RC retirement are still pending.
A green registered gate therefore does not make the entire installed language
package RC-free. Migration instructions and current source contracts are in
[ownership documentation](../../docs/tooling/ownership.md) and the worker handoffs.

No publication is authorized: the branch has not been pushed and no self-hosting
branch or GitHub `main` merge is part of this run.
