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

## M0-012 — include all rebuilt row references in timing

- Question: the inherited 46-row timing registry times only Rust and Zig RS for its first 40 rows, although M0 rebuilt Go and Zig RF too; the six S4 rows already include Go.
- Options: report the narrower inherited comparison or extend its configuration table while retaining the exact timing, startup-subtraction, checksum and threshold rules.
- Evidence: all 16 expanded reference binaries pass 480 edge probes. The first pilot batch validates every row against the inherited gate references, but does not time the extra available arms.
- Choice: rows_allrefs.py adds Go and Zig RF for those 40 rows, keeps the six S4 rows' existing reference arms, and runs three fresh 7-round batches. The pilot is retained separately. The queued second pilot batch was stopped before timing began; no completed measurements were overwritten. X uses the same extended registry.
- Reversibility: additive measurement coverage only; no compiler, workload, reference source or gate threshold changes.

## M0-013 — keep complete evidence within the delivery size limit

- Question: per-cell count journals and the frozen fuzz command journals grow beyond the 10 MB deliverable budget.
- Options: discard measurements or preserve exact raw data in owned scratch with compact reviewable summaries and compressed archives.
- Evidence: 108 completed count cells summarize to 193,361 bytes with every cell's totals and the required hot sites retained. Raw fuzz JSONL journals compress losslessly; their generated source trees can be archived without affecting the completed matrix verdict.
- Choice: exact counting JSON stays in .mylang-cache/rp3/ce/raw/<tag>; committed summaries retain all totals/kinds, raw hashes and hot-site detail. Completed fuzz JSONL is gzipped and generated sources are tar-gzipped, retaining all original bytes. Only workers with exit 0 are compacted; summaries and oracle identities remain unchanged.
- Reversibility: every raw datum is retained or losslessly archived; no gate is skipped or weakened.

## M0-014 — pin parity qualification as well as compilation

- Question: the inherited parity harness restores unrestricted affinity after its build context, before output qualification. This allows heavy qualification programs onto reserved CPUs outside the quiet guard.
- Options: retain that omission or correct the adapter before accepting timing.
- Evidence: the queued parity process had affinity 0–19 after all 153 builds and output checks. Its quiet guard had not been acquired and no timing JSON existed. A first attempted global pin was correctly rejected by the runner's CPU-availability preflight.
- Choice: stop only that owned queued process, retain hashes of all 153 binaries/sources/flags, and repeat the complete qualification with parity_prebuilt.py. The adapter now preserves the real CPU-availability preflight, then pins away from reserved CPUs before the first tool probe; timed blocks select CPU 10 only after quiet admission. No timing from the earlier attempt is accepted. The omission is recorded rather than claiming its original qualification had the required affinity.
- Reversibility: harness correction only; all original builds, outputs, workload sizes and timing rounds remain covered.

## M0-015 — interleave X parity arms in each round

- Question: inherited part3.sh runs final and base parity in separate sessions, while wave 3 requires them interleaved.
- Options: retain the old session split or extend the unchanged benchmark runner's arm registry.
- Evidence: the complete registry contains 45 mylang arms and 108 references. A paired registry validates 45 base + 45 candidate + 108 reference arms with unique names.
- Choice: parity_pair.py adds base-my* arms to each benchmark's shuffled rounds, builds both compilers with separate compiler-tagged object/runtime caches, and uses the shared quiet guard. validate_parity.py rejects any missing arm, failed build/output or incomplete timing; speed misses remain reported independently against the plan's targets. No threshold file is rewritten.
- Reversibility: measurement tooling only.

## M0-016 — derive paired runtime caches from compiler identity

- Question: environment-only runtime-cache tags are easy to reuse accidentally when timing-prep builds both a base and a candidate compiler's guests.
- Options: rely on caller discipline or make the retargeted builders derive an owned cache path from the compiler binary hash.
- Evidence: the inherited paired row and Lox preparation wrappers pass both compilers through one shell environment. The current M0 counting run explicitly uses base-fast, but future mixed-compiler preparation needs stronger isolation.
- Choice: ce.py, outputs.py, prepare_rows.py and timing-prep.sh select compiler-hash runtime caches automatically. This isolates future base/candidate compile timings without changing code generation, inputs, or already-qualified guest outputs.
- Reversibility: cache placement only.

## M0-017 — batch remaining counting builds within one admitted slot

- Question: short guest compilations repeatedly wait behind other projects' long builds and pay admission settling for every binary.
- Options: continue two queued per-binary workers or run the unfinished compiler invocations serially inside one admitted build slot.
- Evidence: the two owned row-build workers waited more than 10 and 4 minutes at one checkpoint, while 118 completed counting/plain binaries were already available.
- Choice: stop only the owned waiting build and continuation processes, hash all retained binaries and the compiler in count-build-resume.json, and finish through build_count_batch.py inside scripts/build-slot.sh build. The batch asserts that it owns a build-slot descriptor, runs only one compiler at a time, and verifies every reused hash. The supported one-second poll setting changes admission responsiveness; slot counts, memory thresholds, affinity restrictions, workloads and gates are unchanged.
- Reversibility: scheduling/tooling only; the complete counting and output gates still follow the build.

## M0-018 — report the standalone recursive-tree arm without an invented reference

- Question: the current parity registry has 28 benchmarks, but binary_trees_recursive contains only its mylang arm. The historical geomean covers 27 reference-bearing primary arms.
- Options: drop the standalone arm, invent a peer, or keep its timing/output coverage and mark the relative gate unavailable.
- Evidence: bench_parity.discover/arms_for yields 153 arms, including all 45 mylang programs; binary_trees_recursive is the sole benchmark without Zig or Rust arms.
- Choice: keep all 45 mylang programs in timing and the gap table, mark the standalone relative gate unavailable, and compute the reference geomeans over the 27 primary arms with Zig RS/RF references. No speed result or passing gate is inferred for missing coverage.
- Reversibility: reporting correction only; no benchmark, oracle, threshold, or runner changes.

## M0-019 — preserve paired row ratios when aggregating batches

- Question: sort_records/4096 has a 1.2277× new/old result in batch 3 despite byte-identical old/new binaries. The two earlier batches are 1.0092× and 1.0138×.
- Options: discard the outlying batch, divide separately pooled absolute medians, or follow FU-X's median of the three within-batch ratios and retain every raw sample.
- Evidence: both binaries hash to 8f900581c0adca405b03aaba325e5f6c6e2341ba78483b1c82d2de141b3e629e. CPU-8 instruction samples are 232443933, 232443925, 232443931. The CPU-10 cycles have two modes around 51 M and 64 M. FU-X tools/summarize.py explicitly takes the median of per-batch ratios. Pooling absolute medians first incorrectly turns the paired 1.0138× result into 1.2054×.
- Choice: correct m0_gap.py to preserve paired ratios for every reference. Keep all three complete 7-round batches unchanged, report the single-batch outlier, and run one separate sort_records confirmation at both sizes with the original 7-round/reference/checksum method. The confirmation is diagnostic and replaces none of the full batches.
- Reversibility: aggregation correction only; original harnesses, thresholds, workload sizes, reference coverage, and raw results are unchanged.

## M0-020 — add timing for the reference-free parity program

- Question: the native parity runner qualifies binary_trees_recursive, then skips its timing with `no qualified zig-fast`. The strict complete-coverage validator caught the missing wall samples.
- Options: drop the arm, label a mylang binary as Zig, or add absolute timing without a reference ratio.
- Evidence: all 153 arms build and match output, but the unmodified runner records timing for only 152. The standalone mylang binary matches its build-manifest hash and expected output.
- Choice: retain the complete original runner receipt as parity-native27.json.gz and add the missing 9 rounds / 2 warmups with the same run_timed/measure primitives under the quiet lock. The adapter verifies output before and after, checks every timed status, and invents no reference arm or ratio. The completed receipt now passes all 28-benchmark / 153-arm coverage checks. parity_pair.py uses the same adapter while retaining its lock, interleaving base and candidate for this program at X. Historical speed-threshold failures remain in the native and completed receipts; no thresholds changed.
- Reversibility: additive measurement only. No native benchmark source or runner is edited.

## X-001 — review the exact timed binaries and row sizes

- Question: the complete 151-program instruction corpus measures each row at one registered size, while X has 92 row/size timing cells. A small-row regression cannot be diagnosed by substituting the large-row run.
- Options: reuse generic corpus counters for every wall-time flag, or add exact-command CPU-8 review for each flagged timing cell.
- Evidence: row timing receipts retain every binary, size, iteration count and seed; parity build receipts identify the exact output binary, and Lox/EDA receipts retain their binary commands. M0's sort_records result already demonstrated that instruction and cycle evidence must be attributed precisely.
- Choice: x_gap.py validates every expected arm and sample, retains paired ratios, and lists every final/base result above 1.03. review_perf.py uses the actual timed binaries (hashed before and after), exact row sizes/iterations, and matching Lox/EDA workloads for interleaved CPU-8 instructions, cycles and branch misses. It requires build-slot admission. No automatic noise classification is made; the coordinator reviews the evidence. X timing scripts require an explicit final compiler instead of silently defaulting to the base.
- Reversibility: additive validation/reporting only; no runtime, workloads, or thresholds change.

## X-002 — validate outputs as well as counter agreement

- Question: a counting-on/off comparison alone could accept two identical wrong answers; the standalone EDA wrapper also selected failures by golden-file mismatch without including process status.
- Options: rely on later timing qualification alone, or verify each counting receipt's exact registry and M0's already-qualified outputs too.
- Evidence: the saved M0 receipts contain all 199 cell identities and plain-output hashes; row stdout includes a checksum followed by variable native-clock time. EDA records both process status and golden comparison separately.
- Choice: validate_counts.py requires every registered cell, zero plain/counting status, counter presence, matching on/off output, and matching M0 output (checksum only for rows). Parity expectations and EDA golden files remain explicit checks. outputs.py's EDA branch additionally rejects nonzero status even if files happen to match. The complete M0 receipt passes this validation unchanged.
- Reversibility: stricter receipt validation only; no oracle, workload, or threshold changes.

## X-003 — exclude nondefault build slots from binding timing

- Question: the shared wrapper defaults to three build slots, but another run was observed building directly under build4.lock.
- Options: keep the original three-slot quiet guard, or reserve every numbered slot present plus the known fourth slot.
- Evidence: external process 3790925 ran a ReleaseFast build under build4.lock on 2026-10-10; build5.lock and build6.lock also exist. These files and processes belong to other runs and are not modified or stopped by this task.
- Choice: quiet.py now discovers numbered build/gate locks on every nonblocking acquisition attempt, always includes build1–4 and gate1, and retains admission/CPU-10 locks. On contention it releases all held locks before retrying. A scratch test verifies that cleanup, a newly appearing build7 lock on retry, and complete release on exit. All subsequent CPU-10 measurements use this guard.
- Reversibility: measurement admission only; production code and thresholds remain unchanged.

## X-004 — preserve the row method for the R5 bound

- Question: a generic wall-time ladder comparison would omit the startup subtraction required by the row measurements.
- Options: compare elapsed process times, or use the inherited row sampling and normalization for the two R5 exit cells.
- Evidence: the prescribed cells are result_propagate/4096 and option_handle/64; M0 retains their full workloads, startup checksums and measured checksums. R's probe receipts identify prebuilt baseline and barrier-removed binaries.
- Choice: confirm_rows_bound.py validates those exact cells and binary hashes, uses the inherited CPU-10 sample function, takes three startup samples and seven shuffled rounds per batch, and reports the median of three within-batch ratios. Every output must match M0's corresponding checksum. It runs with the updated quiet guard and final X binaries. A prepare-only check validates command construction; actual X measurement remains pending.
- Reversibility: additive comparison only; it replaces none of the full row timing batches.

## X-005 — separate R5 compiler-recipe controls

- Question: R's reconstructed baseline and barrier-removed probe binaries match each other, but neither matches the actual M0 row binary.
- Options: treat the reconstructed baseline as M0, or retain both identities as separate controls.
- Evidence: `R/row-probe-controls.json` attributes differences to the native-clock compilation flags, runtime/LLVM/clock link order, and link flags. Reachability markers show no small-free barrier execution in result_propagate/4096 and one timed execution in option_handle/64. The probe pair is byte-identical, so it provides no measured code-generation improvement.
- Choice: preserve all recipes, identities and original receipts. X's R5 confirmation includes actual M0, reconstructed baseline, barrier-removed and final arms with the inherited row method. Report recipe/layout effects independently from any production change; keep F1's barrier unless a narrower sound alternative is established.
- Reversibility: additive controls and attribution only; no safety or timing threshold changes.

## X-006 — attribute sampled instruction families consistently

- Question: allocation/free and text-materialization exits depend on which sampled stacks count toward a family, including allocator helpers and inlined symbols.
- Options: reuse incomplete name matching, or state and apply one exact family to both arms.
- Evidence: coordinator review found that the draft U2 classifier omitted `block_alloc`, `small_alloc` and `aligned_alloc`; the first accounts for a material fraction of EDA's base instructions. S2's exact-name matching also needed normalization of `(inlined)` and symbol-offset suffixes. Saved raw profiles permit reparsing without replacing evidence.
- Choice: include the allocator helpers before U2's first admitted profile, normalize S2 symbols identically in both arms, and retain family definitions plus binary/raw profile hashes. Preserve S2's original receipt alongside its normalized result. Treat LBR attribution as a sampled lower bound where inlining or truncated stacks hide work; do not claim the absolute share exits from an incomplete family alone.
- Reversibility: measurement attribution only; original samples and invalid attempts remain available.

## U2-001 — preserve the original owner cutoff through forwarded records

- Question: an expanded frame snapshot prints the expected answer and then crashes with the nested-borrow prototype, while M0 passes.
- Options: abandon path-preserving borrows or correct the ownership reachability cutoff.
- Evidence: the original frames read precedes an intermediate record definition. `Taking.clearThrough` used that intermediate definition as its cutoff, overlooking later reads through a record whose disjoint stack field was updated. LLVM consequently releases the frames block before those reads.
- Choice: use the original owner's definition throughout the traversal. Checkpoint `4661eb368` passes all 13 focused host tests, including eight language fixtures in all five modes and the formerly crashing case. Retain the failed probe and IR evidence; full lane gates still determine acceptance.
- Reversibility: localized ownership correction. No count-word encoding or safety contract changes.

## S2-001 — reject escaped substring blocks after measuring their overhead

- Question: base profiles make stored token slices eligible for the conditional substring experiment, but does the implementation improve EDA without regressions?
- Options: retain the new representation, keep it disabled, or remove it while retaining split/view improvements.
- Evidence: after fixing sorting and numeric-parser consumers, the prototype passes the sampled golden outputs but takes 1.1262× base instructions on rds3+flat and 1.1524× on labstation. Materialization shares fall from 14.875% to 12.122% and from 15.868% to 13.434%; neither meets the exit. Parent-count traffic and data resolution outweigh the avoided short copies.
- Choice: remove the escaped substring representation in `3405f2511`. Keep the lazy/offset split, byte-view, span-parse, stack-prefix and search changes. Preserve the prototype commits and rejection receipt for the final bound; do not present eligibility evidence as an achieved benefit.
- Reversibility: the rejected prototype remains in lane history. Reconsider only with a representation that avoids the measured overhead and passes the same gates.

## R-001 — remove the regressing sret-sharing prototype

- Question: the private single-pointer ABI eliminates record_pass copies but increases work.
- Options: enable it, retain dormant new machinery, or remove it under R3's conditional acceptance rule.
- Evidence: the combined prototype records zero copies but 1.2065× base instructions and 1.1741× cycles for record_pass. Its exact LLVM, identities and copy attribution are retained under R.
- Choice: remove the new ABI machinery and retain the original `share_sret = false` behavior. R4's separately investigated payload mechanism is subsequently rejected in R-002. X reports R3's negative bound rather than claiming that copy elimination alone is a gain.
- Reversibility: prototype commit and evidence remain available; reintroduction requires passing the unchanged instruction and timing gates.

## X-007 — qualify each integration merge with a stable source identity

- Question: §2 requires gates after every merge, while §7 specifies the U2, S2, R merge order before final timing.
- Options: validate only the fully merged tree, or qualify each intermediate integration tree as well.
- Choice: merge in the specified order and run the complete correctness/instruction sequence after each merge. `qualify_tree.py` uses a fresh evidence basename, asserts an unchanged clean tracked tree, snapshots Debug and ReleaseFast compiler identities, runs exact raw/additive conformance, 9×200 fuzz at integration, external tests/conformance, all 199 counting/output cells and all 151 instruction cells. Full repository tests include the registered lane fixtures. Fuzz holds the gate slot so it cannot run beside a full gate. Binding CPU-10 timing still runs on the complete final tree.
- Evidence: the tool composes the already validated M0 gate adapters and checks every subprocess status; command-line/schema checks pass. No integration execution or passing gate is claimed before a lane hand-off.
- Reversibility: orchestration only; no source, oracle, workload or threshold changes.

## X-008 — summarize completed fuzz command journals within the evidence budget

- Question: retaining the three lane matrices and a full matrix after each integration merge would exceed the plan's 10 MB evidence limit if every raw command journal remained in the committed directory.
- Options: discard observations, compress the journals only, or retain exact journals in owned cache with checked summaries in the evidence tree.
- Evidence: M0's nine command journals are already gzip-compressed, yet constitute most of its fuzz evidence. Each worker summary records exact command counts, native comparison totals, completion, failures and qualification; the matrix also records source/oracle stability.
- Choice: after a matrix passes completely with unchanged source/oracles, count every journal event by role/build/status and verify its count against the worker summary. Preserve uncompressed and gzip hashes, copy the exact journal to owned cache, verify its hash, and retain its location in commands-summary.json. Keep the original matrix, worker summaries and source archives. Failed or incomplete matrices cannot use this path. The operation passes on all nine completed M0 workers; integration qualification uses it after successful fuzzing.
- Reversibility: raw journals remain byte-identical in the locked worktree's owned cache and can be restored. No cases, comparisons, seeds, or gates are omitted.

## R-002 — retain ordinary returns after the payload-destination experiment

- Question: can the generalized detached payload ABI safely eliminate parse_list's P6 copies?
- Options: broaden lending despite the lifetime conflict, retain a conservative but ineffective ABI, or remove the prototype and report the blocker.
- Evidence: the corrected conservative prototype passes the sampled EDA goldens/counting comparisons but leaves P6 at 444,833,472 bytes and increases total EDA record-copy bytes by 30.70%. On the actual parse_node error path, parse_list releases the destination children list before it reads and releases the returned error payload. The generalized ABI relocates overlapping error bytes as well as success bytes; lending there would dangle. Its initial 60-cell CPU-8 diagnostic records EDA instruction geomean 1.008163× M0. A subsequent direct 60-program / three-round comparison against the same R1/R2 ordinary-return control isolates a 1.008136× EDA instruction ratio (range 1.005833–1.009559); diagnostic cycles are 1.045816×. All processes succeed. The rejection is therefore independent of the array and sort changes.
- Choice: preserve the corrected prototype in `07534f41b`, remove its production ABI machinery in `09ed22709`, and keep the regression fixtures. A future selected-case ABI needs tag-aware return-home placement, caller projections/ownership and a CFG/lifetime proof together. Do not weaken the conservative refusal merely to remove the measured copies.
- Reversibility: all prototype history and attributed LLVM remain available. No language, trap, count-word or safety change is accepted.

## X-009 — require fresh guest units for the final compile-time comparison

- Question: an isolated --cache-dir does not prevent native guest unit reuse through the parent runtime store.
- Options: accept the cached pilot, rebuild runtimes as part of every timed guest, or copy only warm runtime top-level files into fresh guest stores.
- Evidence: U2's first pilot reused units-v1 and is retained as invalid. Its corrected 16 builds each report one unit compiled, zero reused, a linked program and two processes. S2's equivalent helper also rejects an empty runtime seed before timing.
- Choice: final compile_times.py uses fresh run directories, compiler-hash runtime seeds without units-v1, one excluded warmup and three shuffled paired rounds for EDA/Lox. It records wall and child CPU time, binary/compiler hashes and exact cache reports; cached guest units fail validation. The parser accepts all 16 corrected U2 reports and rejects a reused-unit report. Actual final-tree timing remains pending.
- Reversibility: measurement-only cache isolation. No compiler optimization or threshold changes.

## X-010 — validate each timed parity execution and recompute row normalization

- Question: the inherited parity timer can append a failed measured process, and the row reader trusts precomputed normalized values and startup checksums.
- Options: trust initial qualification only, or check the actual warmups/timed executions and independently reparse row evidence.
- Evidence: eight mocked parity execution checks and fourteen corrupted row receipts exercise the failure paths; all three original M0 row batches pass the stricter reader. Proofs and exact applied hashes are in X/tool-audit.
- Choice: capture parity stdout in a preopened temporary file, preserve spawn/wait timing and verify output/status after timing. Invalid execution returns status 2 with an independent incomplete receipt. This changes stdout I/O from M0's /dev/null equally for all paired final/base/reference arms; final/base comes from the same new session. Rows retain their exact method, with raw command/checksum/cycle verification and recomputed startup subtraction. No baseline result or threshold changes.
- Reversibility: measurement adapters only; historical raw receipts and proposal diffs are retained.

## X-011 — separate strict allocation/free frames from ambiguous traversal

- Question: reference_at and shared traversal/release helpers can also execute non-final decrements or sharing, so matching them without an allocation/free ancestor overstates the strict lower bound.
- Options: retain broad attribution or split strict allocation/free and ambiguous-only stack periods.
- Evidence: reparse of the exact original U2 samples reproduces all original totals. Corrected strict shares are labstation 25.786% → 21.707%, rds3+flat 23.504% → 20.082%. Seven classifier boundary checks pass.
- Choice: use disjoint strict and ambiguous-only families for both arms. Generated dictionary key/value release callbacks require a strict ancestor; fresh X profiles hash binaries before/after recording and cannot reuse a prior recording through the old --reuse option. Preserve old broad receipts and the exact reparse provenance. These bounded LBR samples cannot prove a share below 15%; the corrected U2 strict lower bounds still exceed it.
- Reversibility: attribution-only correction, no runtime or optimizer changes.

## X-012 — isolate conformance by unique evidence leaf names

- Question: the second integration run fails before conformance because the inherited qualifier uses only out.name for its temporary cache. Unique parent directories do not isolate raw/additive leaf names.
- Evidence: merge-s2-01 passes repository95/95 with2,349 tests, then both qualifier invocations raise FileExistsError before any conformance case. Raw status1 happens to equal the known-mismatch status, but no valid summary exists and the overall run remains incomplete.
- Choice: change only the owned orchestrator to qualify with tag-specific leaf basenames, add immediate strict raw validation, retain the failed attempt, and rerun every gate with fresh merge-s2-02 evidence. Keep the existing raw+additive cross-compiler validation and all original thresholds.
- Reversibility: measurement orchestration only. The frozen qualifier, references and compiler implementation are unchanged.

## X-013 — merge advancing main and requalify the current integration step

- Trigger: main moves from the frozen M0 base41ed360fb to1ab0d92e7, bringing incremental stage/frontend caching, deferred facts and reclaimable compiler scratch. The launch explicitly requires a real main merge and fresh gates.
- Evidence: merge-s2-02 has passed its build but its repository wrapper is still unadmitted (expected owned command, no fd9). Only that wrapper is canceled; its receipt/log remain.
- Choice: merge main into the coordinator, preserve U2 ownership cutoff and U2/S2 pass ordering across the two textual conflicts, and rerun the complete current integration step. Completed lane branches need no ongoing-development merge. Main's other-package evidence arrives unchanged through the merge, as permitted; it is not edited. M0 compilers, original baseline, 683 copied corpus files and gate thresholds remain fixed. Future qualification receipts bind the integrated main hash and reject an unmerged or advancing main.
- Reversibility: both parent histories are retained by a real merge. No performance outcome is assumed for the cache changes; final qualification and timing still apply to their combination with wave3.

## X-014 — preserve split optimization across main's new fusion replay

- Trigger: main advances again to fa1160602 with source-local fusion checkpoints, recursive summary receipts and generic-instance reuse. The running 74adf3466 matrix completes all1,800 cases successfully, then the driver stops at its main-identity guard. Its earlier repository/conformance results remain a partial checkpoint; external/counting/instruction stages did not run.
- Evidence: new fusion replay captures declarations and per-producer helper requests, but S2 additionally creates compound offset/list types and helpers in both split passes, including duplicate count-helper names. Restoring only slice-helper requests cannot reconstruct those catalogs or prove eager helper order after a dirty edit.
- Options: implement full ordered type/declaration replay and all split producer recordings; or retain S2 behavior with a precisely bounded eager preparation path.
- Choice: merge main with real history; retain whitespace→split views→slice fusion and U2 arithmetic proofs. Eligible split declarations in raw demand catalogs load all raw bodies and skip demand/compact pipeline indexes; normal transformation, final and emission artifact caches remain active. Declaration presence is conservative even where a split ultimately cannot transform. Other catalogs retain demand/fusion reuse. Both slice rewriting branches record helper requests, and S2's public helper API remains compatible. Full ordered split replay is deferred, not claimed implemented.
- Validation: four targeted cache tests pass in both trusted and verify modes: explicit offsets/prefix/duplicate-count/lazy cases, whitespace-only probe insertion, dirty helper-order changes under an equal raw catalog with unchanged spectators, and retained byte-only demand reuse. Whole-tree qualification and actual final compile-time comparison remain required.
- Reversibility: localized cache eligibility and recording adaptation; no guest source, language, safety, runtime optimization or gate threshold changes. M0 remains frozen. Incoming other-package evidence is retained unchanged.

## X-015 — retain array type information when record analysis is skipped

- Trigger: accepted R seeds fixed-array literal/update facts and proves fixed-length accesses through `FieldIntervals.module`. Incoming main skips whole-program field rounds in modules without record compounds; the empty table then lacks the module needed by array analysis.
- Options: force record-field rounds for array-only modules, or preserve the module pointer in both exploratory context and returned field table while retaining the shortcut.
- Choice: supply the existing module to both contexts. The change carries type information, performs no extra record rounds, and keeps main's demand/compact cache path. Accepted R1/R2 runtime behavior and all safety checks remain subject to the full final gates.
- Evidence: two focused cache regressions pass (8/8 steps) after the real conflict-free R merge. They assert absence of record compounds, literal/update array hulls, trusted check removal, verify-mode restoration, and eager/cold/warm/demand cache equivalence including compact emission. Proposal, hashes and focused log are in `X/r-main-merge-review.json`.
- Reversibility: localized compiler-context plumbing plus regression tests; no benchmark, language, task ABI, count encoding, or threshold changes. The final combined 9x200 qualification and CPU-10 measurements are still required.


## X-016 — Preserve the complete first timing run and repair confirmed regressions

Question: the fully qualified integrated source passes all correctness and 151 instruction cells, but CPU10 exposes small-size and runtime-dispatch regressions. Options were to waive the crossings from overall gains, stop with incomplete X, or preserve the complete run and repair actual regressions. The plan requires the last option.

Evidence: `X/timing-run-01/regression-ratios.json`, the three complete row batches, and seven exact-binary CPU8 rounds. `sort_int/64` is 2.082902× base (1.958415× instructions): radix setup replaced an adaptive two-run merge. `mutate_nested` is 1.069577× / 1.053759× at4096/64 despite reduced instructions; generated per-element release dispatch is the actionable changed path. `sort_records/64` and `result_propagate/4096` remain under review. The tuned-text primary crossing does not recur in its already-recorded independent confirmation; both observations remain.

Choice: snapshot all first-run identities, results and logs; test restoring typed powersort for33–64 integer words and direct release of provably guardless one-pointer list elements using existing count primitives. Preserve callback coverage and add boundary/lifetime tests. No threshold, benchmark input, count encoding or task ABI changes. Fresh complete qualification and affected timing follow any accepted source fix; the first-run report is not final acceptance. The changes remain reversible and must demonstrate improvement before shipping.


## X-017 — Repair measured dispatch costs and validate the whole small-sort boundary

- Question: the first repair restored the official 64-value sort and pointer-list release, but additional sort sizes 65 and 128 remained 2.068447× and1.093828× M0. Options were to stop at the official size, add a natural-run detector, or move the existing adaptive merge dispatch to one histogram width.
- Choice: merge 33–256 integer words, retain allocation-free insertion through 32 and the existing radix implementation above 256. Each radix byte clears/prefixes 256 buckets; using the established merge path below this scale avoids fixed histogram cost. This is a measured conservative cutoff, not a universal optimum. Ordered short lists again allocate the same bounded scratch as M0; no writes precede allocation success. The 255/256 samples give up first-build gains to return to base performance, while 257/512/4096 and the 2-million-value sort retain their gains.
- Release repair: recognize only generated, guardless list layouts with one pointer at offset 0 and stride sizeof(pointer), and only the destruction visitor. Release each occurrence with the existing primitive and pending-chain order. The generic stride 16 fixture retains its 50001 callback assertion; a separate eligible-list fixture covers nulls, duplicate owners, unique children, saturated counts, publication and concurrent shared-count traffic without worker-side frees.
- Evidence: both focused tests pass; the sorting fixture exercises five native modes and signed/unsigned, alias, reverse, packed and wide-key stability through 255–257. Seven CPU8 rounds and three CPU10 batches retain M0, preserved first and each candidate. Candidate 02 fixes all official development crossings; counting-sort register allocation returns to M0's 916 normalized instructions, removing 126 instructions and 95 loads per 64-element sort. The repeated result loop remains byte-identical and its candidate slowdown disappears, without a proven microarchitectural mechanism. The size 32 development crossing gets one confirmation and does not recur; both results remain. `X/repair-probes/01` and `02` preserve all samples and compile/source identities.
- Repeat integrity: preserve all 31 first outputs and 286 exact timed binary copies, then retarget the measurement driver by qualified tag and run ID. Fresh baseline/candidate profile namespaces and fresh compile trials prevent cache reuse. All 197 cells, references, rounds, bound comparisons and regression review remain. Lossless archive 03 compression keeps historical evidence available within the 10 MB budget; M0 and results/base consumed inputs stay at their existing paths.
- Reversibility: two localized runtime branches, focused tests and tooling parameterization. No benchmark source, semantic contract, count encoding, task runtime, threshold or corpus changes. Full fresh qualification and full X timing must pass before final acceptance.

## X-018 — Merge the third advancing main and restart complete qualification

- Question: main advanced from `fa1160602` to `e9011d9c6` while the repaired source was running the repository gate. Options were to time the stale tree, finish superseded checks before merging, or stop superseded work and qualify the real merge. The launch requires incorporating main and repeating the step.
- Choice: terminate only the verified descendants of the owned qualification process, preserve its incomplete receipt and exact partial logs, and merge main with a real merge commit. The build passed 9/9 with 88 Guardian checks; 18 completed repository shard verdicts reported 1263 passes and zero failures, but no completed repository verdict is claimed. Every X gate and full timing run will execute again under fresh names.
- Evidence: the textual merge preview is clean. Main adds portable checked-type recipes, semantic-store v6, external-source demand proofs, and lowering demand/function/header v3 keys. Separate U2 and S2 reviews found no actionable ownership, identity, helper-metadata or provenance interaction. Main's 97/97 steps, 2475 tests, and 88 checks are historical incoming evidence, not merged qualification. `X/main-e901-review.json` preserves review limits.
- Retain X-014's eager split-catalog fallback: portable checked-type reconstruction does not implement optimizer-generated split compound/helper replay. Keep all four existing cache integration tests. Old frontend cache misses after format-version changes are expected; final guest compile trials remain fresh. No benchmark, gate, language, count encoding or task runtime is changed by the coordinator. Other-package files arrive unchanged through main.
- Reversibility: ordinary real merge history; incoming changes and wave-3 changes remain separately reviewable. No hard-stop exception or skipped gate is introduced.

## X-019 — Serialize the complete repository test graph after observed cache contention

- Question: after roughly an hour, the repaired/main-merged repository gate had 17 completed shard verdicts (1153 passes, zero failures) and no final repository verdict. Repeated snapshots showed ten guest compilers waiting on one stage-cache sequence lock while the owner changed and performed CPU work. Options were to add workers, wait through the contention, alter the production cache, or restart the identical full test graph with serial build-step scheduling.
- Evidence: the shared stage directory held 4953 files. `stage_pack.zig` refreshes its directory catalog after another writer advances the sequence; filename lookup is linear. Save and flush refresh under the publication lock. A lone writer updates its own sequence and can bypass the next refresh. This supports a contention mechanism, not a measured speedup. `X/tool-audit/repository-cache-contention.json` records the observation; `serial-qualification-review.json` records independent coverage review.
- Choice: cancel only the 47 PID/start-time/UID-verified descendants of the owned qualifier, all confirmed exited; retain the incomplete receipt, exact partial log archives and hashes under `X/gates-final-fix-main-01`. Restart every qualification gate under `final-fix-main-serial-01`. The repository command adds `-j1 -Dtest-rerun=true`: all 12 unit, 6 CLI and 8 Core shard dependencies remain, Guardian's test partition is unchanged, and every cached test step executes afresh. Explicit concurrency inside tests stays intact. No `MYLANG_UNIT_JOBS` override is inherited.
- Safe overlap: an admitted ReleaseFast build ran on CPUs 0,1,8,9 while repository tests continued, with a separate install prefix and runtime cache. It passed all 9 build steps and 88 diff-scoped Guardian checks in 281.69 seconds. `release-build-overlap.json` records it. The qualifier still runs its normal ReleaseFast build and hashes its own installed compiler; no step is substituted or omitted.
- Reversibility and limits: only qualification-tool scheduling options change. Production compiler/runtime code, corpora, test filters, shard counts, fixture modes, fuzz cases, timing rounds and thresholds are unchanged. Initial cache catalog scans remain; re-estimate duration from the serial run rather than treating the earlier parallel duration as a reliable bound. No X exit is claimed from either incomplete repair qualification.

## X-020 — provisional Juice comparison and separately requested FIFO queue

- Trigger: the user asks for an instruction proxy while waiting for the shared gate, then explicitly requests FIFO admission so new jobs cannot overtake waiting jobs.
- Evidence: final serial qualification waited 2,217 seconds before gate admission. Six full unchanged workloads were captured with frozen M0 and the repaired ReleaseFast compiler, three samples per arm on CPU 8. All 36 samples match their output oracles with 100% PMU availability. S2 independently verifies sources, contexts, libraries, 12 guest binaries, 108 raw artifacts, 18 logs and all six instruction ratios.
- Choice: publish the native Juice results as provisional work comparisons only. Preserve the initial mylang-adapter failure (duplicate attribution keys: ten baseline groups and two candidate groups) and its exact captures; native recording retains ordinary release execution with semantic attribution explicitly unavailable. No correctness or performance gate is replaced or narrowed. Candidate prewarm source 90982ff has the same production code as qualified source 6a40a150; enclosing receipts bind executable hashes.
- Separate user-authorized change: commit 986f54a5 on codex/build-slot-fifo implements per-kind monotonic FIFO tickets, stale-waiter cleanup, cancellation and queue status while retaining parallel slots and admission constraints. Nine real-process tests pass and all 88 whole-tree Guardian checks pass. It is not merged into Wave 3 or main. Only updated-wrapper participants receive FIFO order; old wrappers and direct flock callers bypass it. FIFO prevents overtaking among participating waiters, but does not bound running-job duration or unavailable resources.
- Future policy discussion: richer counters and held-out nightly calibration could support a short merge screen with targeted timing for uncertain cases. This remains a proposal, with no new model, scheduler or gate policy implemented. The current Wave 3 timing requirement stands.
- User instructions: Guardian feedback entries and commits are no longer required and are made only on explicit request. No feedback entry or commit is made in this run.
- Reversibility: evidence publication and an isolated infrastructure branch; production source and all Wave 3 acceptance thresholds stay unchanged.

## X-021 — complete executable preservation and R5 diagnostic reporting

- Evidence review finds that the original first-run binary manifest omitted twelve Mylang row executables, 34 row references, four EDA references and ten exit-confirmation paths. Recover these bytes before another preparation step, preserving the original manifest and every observation. Row/EDA supplemental receipts explicitly label hashes recovered after timing, without claiming timing-time identity; all ten diagnostic paths match hashes embedded in their first timing receipts. Of 34 recovered row references, 28 match the frozen M0 maps; six supplementary Zig-safe binaries differ and remain explicit recovered identities.
- Choice: derive all 126 row executables from recorded commands, include six Lox and six EDA paths, and preserve 198 parity paths. Before the second primary timing starts, synchronously capture the 138 non-parity executable hashes at the committed driver's successful timing-preparation receipt write. After all commands finish, compare and preserve all 336 primary paths; retain ten diagnostic paths against their timing-recorded hashes as well. The ignored orchestration helper adds evidence capture only. Workloads, commands, rounds, admission locks, result validation, compiler source and acceptance thresholds are unchanged. Exact helper source/hash snapshots are retained in X/tool-audit/timing-run-02-capture-plan.json.
- Reporting correction: retain both prescribed R5 cells' CPU8 branch misses, instructions and cycles across actual M0, reconstructed, no-barrier and final arms, validating the spec and binary hashes. Report branch-miss ratios to both actual M0 and the probe even if neither cell triggers the general regression threshold. Do not invent a numeric tolerance for the plan's word "near".
- Attribution limits: headline frame counters cover validated source sites, not all native copies; call-derived execution denominators require IR validation if inlining changes. Conservative allocation/free attribution is a sampled share, not an exact instruction census. Derived counter journal hashes and profile command options are checked against the selected final generation.
- Reversibility: additional evidence preservation and report validation only; the qualified production tree remains unchanged.

## X-022 — reject an already-failing timing candidate without waiting for batch three

- Evidence: two independent completed tree_build_walk/4096 batch ratios are1.0759452125 and1.0574355225. The required final metric is the median of three batch ratios, whose minimum possible value is therefore1.0574355225. A third batch cannot meet1.03. The exact before-hashed binaries also show1.052925610 CPU8 cycles with0.969926327 instructions over seven shuffled rounds; checksums match and all three events report100% running under --no-scale. This is supporting diagnostic evidence, including startup, rather than a replacement timing gate.
- Choice: reject this candidate, signal only its verified owned unadmitted quiet waiter, and retain the resulting incomplete driver receipt/status143 verbatim. Publish a separate derived rejection receipt, preserve all336 primary binary paths and every completed observation, and perform the proposed BOX-release repair. The replacement candidate must pass the complete original qualification and timing sequence. No incomplete result is accepted and no threshold, final workload or gate is removed. Independent R review validates the median argument; U2 validates binary/sample preservation and the recorded ratios.
- Cause hypothesis and repair: the pointer-list shortcut added a LIST-kind test to boxed-tree release. Native comparison identifies the extra path instructions but does not establish them as the sole wall-time cause. Handle BOX once before testing the pointer-list shortcut, extracting the unchanged per-element generated/fallback child visit. U2 static review finds no change to guards, publication, counts, pending order or fallback semantics; meaningful generated BOX tests and exact-binary tree/pointer-list probes are required before accepting the repair.
- Preservation: original receipt remains immutable. Ten diagnostic binaries were prepared; only recorded CPU8 identities are claimed, and unfinished CPU10 bound measurements remain unavailable. Historical repository command logs are summarized with all verdicts/failure diagnostics and exact owned-cache archives, and large completed JSON is losslessly compressed to keep the package under10MB. No samples are dropped.
- Reversibility: separate evidence checkpoint and proposed runtime patch; complete fresh gates can reject the repair. Guardian feedback is not requested or written.
