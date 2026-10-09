# Runtime parity wave 3 decisions

## M0-001 — current main as base

- Question: the plan records `0689d3407`, while main is `41ed360fb361c49938488ad111795bad8a726b73`.
- Options: use its historical base or obey the launch instruction to branch from current main.
- Evidence: current main includes the launch plan itself; changes since the recorded hash are plan commits.
- Choice: freeze `41ed360fb361c49938488ad111795bad8a726b73` as M0's base; merge later main movement with real merge commits and rerun gates.
- Reversibility: the base install remains pinned, with subsequent merge provenance recorded separately.

## M0-002 — isolated environment and coordination

- Question: how to preserve existing work and obey machine resource limits.
- Options: edit the dirty original checkout or create the required private worktree.
- Evidence: original checkout has unrelated modifications; disk has 402 GiB free; other runs occupy build and gate slots.
- Choice: use a locked, prune-kept private worktree; put TMPDIR, Zig local cache and compiler-tagged runtime caches inside it; use the shared build-slot wrapper unchanged.
- Reversibility: all scratch and evidence are owned by this run. U2/S2/R start only after M0 succeeds.

## M0-003 — quiet timing admission

- Question: the inherited timing scripts hold the CPU-10 lock but do not exclude other build-slot users.
- Options: rely on scheduling by other runs, or hold all existing build/gate locks during timing.
- Evidence: other runs occupy build and gate slots; the plan explicitly requires no build during CPU-10 timing.
- Choice: the retargeted `quiet.py` acquires the admission, gate, three build and CPU-10 locks together, nonblocking with release-on-contention. Only prebuilt binaries run while it holds them. Parity acquires them after building and output qualification.
- Reversibility: measurement-tool-only change, no policy, oracle, benchmark or compiler changes.

## M0-004 — current-main conformance provenance

- Question: frontend fixes changed the historical conformance totals.
- Options: record the unadapted oracle result or use the additive frontend reference already reviewed on main.
- Evidence: `experiments/frontend-fixes-20261009/REPORT.md` records 1,547 matches per mode with its additive reference; two historical names are mapped and 29 frontend cases are additive.
- Choice: first run the plan's exact unadapted invocation and preserve its result; also establish the reviewed additive invocation as the complete comparison if needed. Never edit frozen references or ignore an unexplained discrepancy.
- Reversibility: invocation/evidence only.

## M0-005 — restore reference builds after QBE retirement

- Question: `expanded/run.py --build-only` rejects current main's compiler because it requires a QBE asset.
- Options: restore a retired compiler backend, abandon references after the allowed time box, or rebuild the reference arms with their existing recipes.
- Evidence: the first build attempt stops at `cannot locate QBE compiler asset`, before compiling a reference.
- Choice: `tools/rows_references.py` reproduces all 16 Rust/Zig RS/Zig RF/Go build recipes from the existing runner, including Cargo's locked text dependency, then verifies every registry edge probe. The eight retired mylang backend arms are not reference arms; the current mylang rows are built by `measure_all46.py`.
- Reversibility: tooling only; reference sources and historical evidence stay read-only. A reference checksum failure is not waived.

## M0-006 — repair two unmigrated row sources in private copies

- Question: current main still rejects two rows that FU-PORT already reported as unbuildable.
- Options: skip the rows (forbidden), change language semantics (forbidden), or repair only their incomplete syntax migration.
- Evidence: `row_json_transform.my:16` produces E_NUMERIC_PARSE; `row_union_find.my:10` assigns the immutable scalar parameter x. The current base's `mylang fix` changes only `int(text)` to `parse_int(text)` in the former.
- Choice: retain private copies under `M0/row-sources`, changing numeric parsing to its current spelling and introducing a mutable local cursor initialized from x for union-find. Parent mutation and all timed work stay the same. `M0/row-migration.patch` captures the exact edits. Both base and final must use the same copies and pass the references' checksums.
- Reversibility: source-compatibility bug fixes only; no repository benchmark or compiler file changes. Delete the copies when main supplies the equivalent migration.

## M0-007 — reject the inherited no-op norc probe

- Question: the old PM count-removal regex no longer matches current LLVM.
- Options: accept the apparent zero gain, or retarget and remeasure.
- Evidence: every first Lox `norc` result reports zero changed LLVM lines and unchanged instruction counts. P1 now branches through `rc.inc/dec` and `rc.slow` instead of PM's old skip shape.
- Choice: reject the entire first counterfactual set, preserve a small invalid-attempt receipt, redirect both count paths to their existing continuation in owned probe LLVM, and fail immediately if zero count branches change. Rerun in a fresh v2 work directory. Production compiler/runtime and count encoding are untouched.
- Reversibility: diagnostic measurement adapter only; outputs remain mandatory checks for every probe. Generated per-layout release has no existing cf.py stub; only the requested reference_at-inlining probe can be measured before U2 implements generation.

## M0-008 — make EDA output ownership explicit before timing

- Question: the inherited EDA runner launches each executable in the read-only EDA reference repository; a relative --work would resolve output directories there.
- Options: let the queued command run or stop it before admission and use an absolute owned path.
- Evidence: the timing log was empty, the quiet lock had not been acquired, and no child EDA program had started.
- Choice: terminate only the owned queued quiet process and relaunch with an absolute --work under the integration worktree. No reference-worktree write occurred. This narrowly avoided the outside-worktree hard stop.
- Reversibility: command-line path correction only.

## M0-009 — cover the current full-size Lox corpus in counts

- Question: inherited VP3 counting cases cover 48 historical engine/size combinations, omitting current zoo_batch cells and some current full sizes.
- Options: keep the historical subset or extend it without dropping cases.
- Evidence: current bench/sizes.json contains 13 scripts for each engine; the historical VP3 result table contains 48 older combinations.
- Choice: corpus_counts.py keeps every VP3 cell and adds every missing full-size engine/script combination. corpus_perf.py measures all 45 parity arms, all 46 rows, all 26 full-size Lox cells and all 34 EDA designs for instruction regression comparisons.
- Reversibility: evidence tooling only; no thresholds or workloads changed.

## M0-010 — scale the corrected count matcher to EDA

- Question: the corrected P1 matcher repeatedly copied and scanned the remaining 52 MiB EDA LLVM file for each count branch.
- Options: let quadratic probe generation consume minutes per variant, or build each function's slow-block successor map once.
- Evidence: EDA spent over two CPU minutes in Python before producing a norc file; no EDA samples existed. The replacement produced byte-for-byte identical norc and checks+norc LLVM for the completed Lox probe in 0.12/0.19 seconds (`counterfactual-matcher-equivalence.json`).
- Choice: use cf_current.py for current P1 branches; stop only the owned unfinished EDA probe and driver, retain all completed Lox measurements, and rerun EDA through the same compiler/linker recipes. CPU-10 confirmation checks every output and EDA output file on every sample.
- Reversibility: tooling-only lookup optimization; production counts and compiler unchanged.

## M0-011 — reject invalid EDA count-removal bounds

- Question: the requested inline-count-removal probes abort on both EDA designs, while the production base and reference_at-inlining variants match output.
- Options: report their apparent 0.04× instruction ratios as speedups (invalid), invent a changed-workload probe, or report the bound as unavailable and preserve the actual failure.
- Evidence: both norc and checks+norc exit by SIGABRT on both designs. An owned diagnostic runtime with the C retain/release helpers stubbed removes the abort but produces `WireNotOrthogonal` instead of the rds3+flat golden output. Count removal changes copy-on-write decisions, so this diagnostic does not preserve EDA's answer. Production source and all correctness oracles remain unchanged; the counting-on/off EDA gate passes 34/34.
- Choice: keep both CPU-8 attempts as invalid, omit their bogus ratios from the bound table, and confirm every valid arm on CPU 10. No required U2 cell exit is lost: its four norc-based exits are Lox cells with matching outputs; EDA retains its explicit 0.93×-base exit and the valid reference_at-inline bound. CPU-10 confirmation applies to cells that set exits; the invalid EDA probes set none. This is diagnostic invalidity, not a correctness-gate waiver.
- Reversibility: evidence-only decision. A valid count-removal EDA probe can be added later without changing any gate or compiler behavior.
