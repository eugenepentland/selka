# Independent S3 §5/§6/§7 review after A merge

Read-only review of integration `5ee5b8d2e1d1c697a98dfa590cbeda704ed7ae55`.
No builds, gates, native executions, tracked-file edits or commits were made.
This checklist is preparation, not a final S3-X qualification or S4 approval.
The coordinator owns fresh X receipts and final report/design updates.

## Evidence already available

S3-A is qualified at `80fa132ad1bf5d1e5519ed9f3fb0ff65685651f6`, compiler/runtime
source `203c0ca6100344304cbd9fd20d22cc7f9448a145`, and is merged by `5ee5b8d2`.
Its inherited `wave-c/s3-a/qualification-final-01.json` is true and checks:

- Own-source exclusive install 2.33 s; Core64 276/276, exactly 64 verdicts,
  125.95 s, maximum shard 52.87 s and test RSS 249 MiB, no overrun.
- Strict full conformance: 1518 matching per debug/release mode, zero mismatches
  or unsupported results, exit/stdout/leak/fact checks.
- Fresh all40: all 80 size cells pass BOTH unrounded ratios <=1.10, 3200 raw
  four-program measurements, seven interleaved shuffled rounds and CPU10 locks.
- 137 strict native executions, four-mode pinned managed-split semantics,
  cursor split50/750 exact comparisons, complete all35 proof of 343 actual
  definitions with six approved scalar stores and two trace calls, zero residual.
- Full old03: test808.42 s, test-qbe75.43 s, test-qbe-build3.01 s, fmt0.24 s;
  all four summaries successful, exit0, RSS/overrun inspection clean.

These A receipts remain A-source results; they must not be relabeled as fresh
X-source executions. A's old runs01/02 are failed scratch-harness evidence.
A's combined35 run03 is an incomplete parser proof. Only run03 OLD and run04
complete LLVM proof qualify. The external /var/tmp correction and precise
header parser require no Source/performance repeat.

The final root merge qualifier currently records a fresh exclusive install of
1.79 s and a successful Core command of134.76 s. Its overall receipt was still
unqualified/in progress when reviewed; use the completed receipt rather than
those partial command statuses.

## Remaining final-exit checklist

| Requirement | Current disposition | Final evidence/decision needed |
|---|---|---|
| Frozen final integration source, explicit old/Core identities | Source5ee5 known; root qualifier active | Completed source-qualified root receipt, installed Core SHA and corrected old/QBE paths/hashes; do not silently replace either oracle during runs |
| Held uncontended Core rebuild and Core suite | Active root final-merge-run01 with64 shards | <=10 s rebuild, <=300 s suite, exact64 successful verdicts, longest shard under about90 s, test RSS<=2.5 GiB, no explicit overrun; default8 remains |
| Full ordinary language debug/release | X pending | 1518/1518 each, zero mismatch/unsupported; keep ordinary and leak/verify execution receipts distinct |
| Full leak/verify sweep | X pending | Strict exit, stdout and diagnostic comparison, no leak/fact failures |
| Five app admission/matches and all40 | A complete; fresh X pending | Fresh integrated40 rows, BOTH4096/64 cells and BOTHold/Zig limits, finite positive counters, exact output/checksum/exit, CPU10 and both locks, seven rounds/three startup samples |
| Natural-loop operation-count evidence | X pending | Fresh optimized LLVM/assembly for all40; report tagged count stores, constant-one stores, dynamic/saturated reads, exclusive parents, timed nonloop and setup scopes; runtime/callee/untagged allocation effects remain unknown |
| Strict fuzz | X pending | Nine kinds x200 fresh sources (1800;25800 comparisons), all original generators/argument sets, extended char and float methods, all statuses/leaks/facts/refusals; supplementary split200/3000 adds to this matrix |
| Full final old gate | A full old complete; X still owed once | Corrected unique /var/tmp tool on final source; test/test-qbe/test-qbe-build/fmt each exit0 and successful summary/RSS inspection; old times are not Core stop budgets |
| Four-corpus coverage before/after | Historical asset-preserving preparation exists; X pending | All four statuses, accepted/total and unique counts, exact remaining reasons/names, asset/context accounting, no relabeling preparation as final execution |
| Language exception inventory | Historical exact127-name manifest exists | Final named nine propagation/S4 and118 retired-arena exclusions; reproduce nine exact truncated spellings and link complete inventory; no new exclusions |
| Code identity / S0 preservation | Complete A35 and root C-retrospective proofs available | Preserve full baseline-to-C scaffold proof plus C-to-A6stores/2traces proof; explain S0 bodies unchanged and allowed outside-loop Host clock checks; actual all40 covers constant timing overhead |
| Protected contracts | Read-only checks green | ir.zig AND own.zig byte-identical to frozen dc1a5831; tests/lang unchanged after D2 commit225bee07; formatsv5/v6/v2; first64 aggregate positions; explicit runtime authority/fact verification |
| Final documentation and commits | Pending X completion | Record per-package/source/evidence/integration commits, all40+counts, conformance/exceptions, coverage/refusals, timings and all limits BOTH in design§11 and experiments exit report |
| Branch and stage handoff | Main/S2 unchanged at review | Maindf55c52d7b4d319c02dfac66d7222701151825aa; S2ref92590700; no pushes/main merge; old compiler remains default; final Guardian feedback append/commit; STOP for user's S4 go/stop |
| External temporary caches | A private scratches still exist | S2§6 clean-up at final handoff: remove only our completed private external scratch directories after retained evidence is safe; do not prune runtime-baseline or independent task caches |

The S0 kernel rule has the inherited alternative of identical generated bodies
or measured +/-1% (S2 package exit wording). Existing complete identity proofs
cover its unchanged bodies; do not invent a new native rerun solely from this
checklist. All40 is still mandatory. Similarly, passing A/source checks do not
need reruns merely for tool/report edits.

## Draft edits required before a qualified exit report

- `exit-report-draft.md` opening says application repairs and A are pending.
  Replace with qualified A80fa/source203c, integration5ee5, and only X pending.
  Its completed-gates paragraph also says final A still owes receipts; remove
  that stale claim. Fill the A row and add packet/char/trace package identities.
- `exit-report-preparation.md` is explicitly a historical b2ab snapshot. Preserve
  that identity if retained as history; do not copy its broad `User modules/
  interfaces ... S4` and `source scalar/pointer` phrases into the final limits.
  The sharpened candidate correctly says fresh merged module source works and
  general source pointer/aggregate/Option extern ABI does not.
- `limits-final-candidate.md` and `remaining-limits.md` say final source not frozen
  and are preparation. Replace these status sentences only in the final output
  after the coordinator's frozen X source is qualified. Keep historical coverage
  refusals/context separate from final results.
- `docs/design/new-core-s3.md` still has Wave-B-go pending at the end of§10 and
  an empty pending§11. Frame§10 as its historical Wave A stop, record the user's
  subsequent go, and fill§11 with the final required evidence and limitations.
- Preserve A's two actual size64 misses/repeat and the fixes; do not round a
  ratio before deciding its gate. Preserve the failed Core32 trace shard timing
  alongside its successful64-shard replacement.
- `exit-report-draft.md` must supersede the historical HOLD/outstanding list and
  state the final user's S4 decision point, without starting S4.

## Limit wording checked

The candidate correctly distinguishes actual source refusals from runtime
budgets and optimization fallback. In particular:

- Private whitespace cursor fusion validates all uses/ownership/dominance,
  materializes and reprobes an inserted key, retains the source owner across
  loop iterations/rebinding, and uses signed lower/upper offset guards. Escapes,
  stored lists, ordinary calls and phis retain materialization. This is not a
  general view ABI or an allocation-free guarantee for all split expressions.
- Scalar character fusion requires all uses to be valid literal equality or
  disjoint append. Its original located bounds remain; guarded ASCII paths
  retain Unicode fallback. Other consumers/materialization remain supported.
- Source extern is scalar Host-erasing C ABI, while scalar Option is private
  runtime ABI. Copied Host None is rejected anywhere in the copied graph;
  immutable bytes is accepted only as a whole boundary payload, not nested.
- Module-source loading already merges checked whole-program source. S4 owes
  persisted per-module/.myi/Core-cache/incremental workflows, full Lox and EDA.
  Seven E_MODULE_NAME coverage contexts do not imply a general module refusal.
- Rendering depth24 differs from unbounded-by-that-cap iterative equality/hash;
  float parser768 retained digits is a rounding horizon, not input-length limit;
  keyed sort's flat1–8-field/offset255 ceiling is an actual admission refusal.
- The platform qualifier is x86-64 Linux/AVX2/SysV/current47-bit assumption.
  Generic-vector lowering does not qualify another target. Provider, Host,
  property, frontend, capacity and diagnostic budgets are stated with their
  separate scopes in the candidate.

A's completed scratch paths still present at review:
`/var/tmp/mylang-a-old-preflight-oktp5c3j` and
`/var/tmp/mylang-old-gate-old-gate-combined-final-03-pjjj4ulj`.
No deletion was performed by this read-only review.
