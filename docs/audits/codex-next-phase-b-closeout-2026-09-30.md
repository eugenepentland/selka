# Combined Phase B closeout — 2026-09-30

WP-B1, B2a/B2b, B3 and B4 are implemented and integrated on
`codex/next-closeout-20260929`. The complete final gate passes on frozen source
`a3e451d76ebfa875a989151f995ffc4e84687db0` (tree `bcdd90bbf7d95f5f92914086d140c1507a1034f6`).
The documentation/evidence commit following that source changes no compiler,
runtime or tests. Main remains at approved `80dd5190`; Phase B is ready for the
user's explicit landing approval. Phase C has not started.

## Source and completed work

The [source commit ledger](evidence/codex-next-phase-b-final-20260930/source-commits.txt)
records all 182 commits reachable beyond approved main through the frozen tip;
the [diff summary](evidence/codex-next-phase-b-final-20260930/source-diff-stat.txt)
records the combined scope. The lane reports supply the rule, spec/test tags,
implementation commits and original before/after evidence:

| Work package | Implemented rule and evidence |
| --- | --- |
| B1 | Byte sorting, charset trimming, bounded/reverse Unicode and byte search, and scalar repr; `PY-BYTES-SORT-1`, `PY-TEXT-TRIM-1`, `PY-TEXT-RANGE-1/2`, `PRELUDE-REPR-1`. [Python text closeout](python-text-closeout-2026-09-29.md) records CPython and native oracles. |
| B2a/B2b | Per-module interfaces, compilation, scheduling, projects, linking, checks and tests; declaration/body authority and unchanged-state publication preserve whole-program semantics and invalidation. [Module closeout](codex-next-modules-closeout-2026-09-30.md) records adversarial admission, cache/state matrices and the nominal 200k fixture. |
| B3 | Equality allocation, scope journals, exclusivity, text dictionaries, list/startup images, canonical release and backend follow-ups. [Runtime checkpoint](codex-next-runtime-checkpoint-2026-09-29.md), [QBE phi repair](wp-b3-qbe-phi-2026-09-30.md), [registered release](wp-b3-registered-release-2026-09-30.md) and the [combined performance receipt](wp-b3-registered-release-combined-2026-09-30.md) retain the rejected checkpoints and corrected proofs. Two full-width O/H counts and all runtime guards remain. |
| B4 | Named module test coverage, cache/workspace isolation, frame advice and memory ceilings, selfhost numeric fidelity, GC snapshot/arena fixes and embed receipts/budgets. [Tooling closeout](wp-b4-tooling-2026-09-29.md) records the contracts and historical collector repros. |

The final production continuation uses registered canonical collection shapes
to omit a redundant source-identity probe. The public source-shape API continues
to validate identity; traversal, lifetime guards, slot clearing and death order
are unchanged. The final test repairs bind count assertions to admitted SSA
and receiver assertions to actual journal writes, activation and pin lifetimes.
Earlier narrowed counts, incorrect zero-branch prototypes and rejected corpus
samples remain excluded and archived in their original receipts.

## Final gate and independent reviews

Tag `phase-b-final-20260930-codex` completes all 27 canonical integration steps
with status zero and unchanged HEAD. The adapted runner retains all coverage;
its recorded changes select the owned worktree/cache, four workers and an 8 GiB
scheduler budget, export the reserved timing CPUs and capture all binary hashes
before measurement. The separately pinned full-measurement runner and supplements
are also green. No gate failure was retried or waived in this final run.

| Required check | Actual result |
| --- | --- |
| Install and corpus build | Frozen compiler installed; all 58 distinct measured binaries built fresh in 317 seconds |
| Full Zig gate | 115/115 steps; 2,804 selected tests passed, zero failed; 28,526 shard-excluded selections |
| QBE / backend build | 51/51 steps and 505/505 tests; 29/29 backend-build steps |
| Formatting / native memory / native heap | 2/2, 23/23 and 10/10 steps |
| Nine guest runtime/backend modes | Each 1,486/1,486 across 227 programs: 13,374 fresh executions, identical unique names, zero failed/cached/skipped/dropped/unloaded |
| Lox RC/GC × QBE/LLVM | Four successful project builds; four source runs each 65/65 across 10 programs; four driver runs each 13/13, zero cached/failed/skipped/dropped |
| 100-seed RC fuzz | 98 ok, zero invalid, zero RC divergences; two known GC-stress-only findings, seeds 19 and 87 |
| Documentation | 227 examples run, 57 checked, 11 declared skips; zero mis-tagged/failed. Coverage: all 14 standard modules and 176 exports, zero failures |
| Corpus module byte oracle | 29 distinct programs / 43 rows, 62 interfaces, 664 units, 29 identical ELF pairs; zero reference failures, differences or compiled-function-object fallback |
| Four runtime module oracles | Each two programs, nine interfaces, 80 units and two identical ELF pairs; zero failures, differences or compiled-function-object fallback |

All twelve unit and six CLI shards finish successfully. The original cold-cache
CLI stderr assertion passes unchanged in the final warm-cache run. The large
Zig skip number counts test selection across shards; the independent guest runs
have no skips or other omitted results.

Subagents independently check the registered-release native/source proof,
strict verifier admission, Zig shard ledger and completed guest/Lox receipts.
The final module review rereads 1,328 corpus IL/metadata byte pairs and repeats
the four two-program runtime modes with retained work: 640 further byte pairs,
36 interfaces, 320 unit rows and eight identical ELF pairs. Its original result
fields match the final gate exactly. The original runtime oracle deletes successful
work by default and has no embedded source/compiler fields; its identity comes
from the pinned wrapper/summary. The additional retained replay supplies independent
byte evidence without replacing the original results. All 1,504 members of its
supplemental archive were hashed again by root.

## Performance acceptance

All 258 dev/full/smoke RC-to-GC outputs agree. Dev and full enforce <=1% on every
row against both the original approved A5 and a new explicitly CPU-pinned A5
control, and <=1.3x against the unchanged accepted GC counts. Smoke follows the
approved A5 differential-output policy: every movement is reported and no new
cap miss is permitted. Every candidate JSON is bound to the exact compiler,
tag and size; all 58 pre-measurement ELF hashes still match. Both controls and
the accepted GC binaries/manifest/cache remain unchanged.

| Size | Backend | RC/GC geomean | Worst RC/GC | Rows <=1.3x | Largest increase vs approved A5 |
| --- | --- | ---: | ---: | ---: | ---: |
| dev | QBE | 1.051431x | 1.262224x | 43/43 | +0.374015% |
| dev | LLVM | 1.051731x | 1.229905x | 43/43 | +0.792467% |
| full | QBE | 1.049719x | 1.262223x | 43/43 | +0.240940% |
| full | LLVM | 1.047553x | 1.224329x | 43/43 | +0.887011% |
| smoke | QBE | 1.092491x | 1.496435x | 39/43 | +1.252773% |
| smoke | LLVM | 1.128000x | 2.415996x | 37/43 | +2.919184% |

Every dev/full row passes against both controls. Maximum dev/full increases are
LLVM Lox instantiation (+0.792467%/+0.887011% against approved A5); all six
backend/size tables retain every absolute instruction count and both baseline
movements in the [verification JSON](evidence/codex-next-phase-b-final-20260930/verification.json).
The final full LLVM text row is 1,352,857,082 instructions (+0.572385% approved,
+0.572378% pinned control), resolving the rejected +1.167106% checkpoint.
QBE full text operations improves 1.790450%. These are the first final frozen
source measurements; earlier rejected measurements were not replaced.

The combined runtime/codegen changes reduce repeated publication/readiness work,
equality temporary allocations, dictionary setup and list/text overhead.
The larger improvements include Lox strings (-18.073960% QBE/-34.156252% LLVM),
LLVM quicksort (-6.031329%) and string equality (-5.655831%), knucleotide
(-3.915118% QBE/-3.455201% LLVM), and Lox tree programs. Individual proof and
attribution limits remain in the linked checkpoint reports; combined row changes
are not presented as isolated measurements of a single helper. Rows moving by
less than 1% remain visible in the full tables without a stronger attribution claim.

The same six diagnostic smoke increases remain:

| Smoke program | Backend | Increase vs approved A5 |
| --- | --- | ---: |
| lox/vm/invocation | LLVM | +1.871291% |
| lox/vm/properties | LLVM | +2.554639% |
| lox/vm/string_equality | QBE | +1.252773% |
| lox/vm/string_equality | LLVM | +2.475787% |
| lox/vm/trees | LLVM | +2.919184% |
| lox/vm/zoo | LLVM | +2.173701% |

Smoke has four QBE and six LLVM cap misses, all on existing A5 miss rows;
no new miss is introduced. The complete dev/full acceptance has no exception.
`RC_QUICK_CPUS=2,3,10,11` is explicitly exported by the recorded runners; root
reserved that pool through measurements, then released it after all three sizes
completed. The old address-dependent 2–4 million-instruction variation is retained
as observed control evidence; full causal attribution remains unproven.

## Durable evidence, Guardian and remaining boundary

The [archive receipt](evidence/codex-next-phase-b-final-20260930/receipt.json)
binds the source/tree/compiler, complete verifier and all final evidence.
The compressed archive is 42,874,488 bytes, SHA256
`95fdde317eb23e647219ab115a7e748a8686cb5239016f4c486a68b4d5db661c`. Root decompresses and verifies all
5,197 payload members against the
[manifest](evidence/codex-next-phase-b-final-20260930/archive-manifest.json).
It includes the 58 measured candidate ELFs, all raw final logs/results/runners,
actual corpus interfaces/unit serialization/ELFs, controls and the retained
independent module replay. Reproducible host runtime/object and Lox test caches
are excluded; the Debug compiler remains pinned in the isolated worktree.
Final strict verifier SHA256 is `43bc18a6b7228a728bb283e59b1cbe96cf1474045bcea0d1b1aeba887d6c1800`.

Guardian passes all 88 build-wired checks, diff-scoped against main over 169/719
source files with 38 whole-tree checks. The separate readiness commit at a3e451d7
already passed whole-tree checks. The final evidence commit also uses the
whole-tree commit gate. No baseline or policy exemption was added.
Required appended feedback is committed in `guardian-zig` at
`f779d82a907943694110e396f006da21c2189bc6`.

Known fuzz seeds 19 and 87 still fail only GC stress and remain open collector
findings; their raw reproductions are retained. The 11 declared documentation
skips and smoke diagnostics are reported above. No required integration step,
guest test, module program or Lox case was omitted. Original checkouts and other
agents' worktrees were not edited.

The next authorized implementation is WP-C1 after Phase B lands. The plan's
explicit-main-approval rule still applies: this green closeout prepares a concrete
fast-forward from `80dd5190`, and does not itself perform or authorize that update.
