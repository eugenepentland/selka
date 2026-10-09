# Frontend fixes decisions — 2026-10-09

## D1 — Isolate the requested branch

Question: where can the work run without disturbing existing changes?
Options: switch the dirty original workspace, or create an isolated worktree.
Evidence: the original workspace is on `local-reasoning/integration` with staged-independent local source and documentation changes.
Choice: create `codex/frontend-fixes-20261009` at `b52b6edb2602f73ef02c750ba2678419cc6d3bea` in its own worktree. `main` starts at `8a2fccd2f1e42c9f09adeecb6c0bb158127f1375`.
Reversibility: ordinary branch/worktree removal after review; no history rewrite.

## D2 — Compact the historical evidence summaries

Question: how to keep each sub-report summary within §2's 10 MB ceiling?
Options: retain all summary bytes (15,403,996 bytes), drop summaries, or compact their embedded raw command reports.
Evidence: the historical directories contain 24,087 files / 270,758,633 bytes; the large mode summaries repeat complete commands and report differences.
Choice: retain all REPORT/STATUS files, the requested identity and qualification JSON, every summary, and full-gate-3.log. Compact large mode summaries to their original metadata, exact case names, verdicts, counts, and hashes; include the SHA-256 and Git object location of each original. The 35 retained files total 2,208,312 bytes. Rewrite report links and resolvable inline capture references to `0bbfeb740:repository/path`; add retrieval instructions to each report. `cleanup.json` records the counts and rewritten references.
Reversibility: all original bytes remain reachable at `0bbfeb740`; no Git objects are removed.

## D3 — Missing autonomy-reference document

Question: the plan references a concurrency document absent from the starting commit.
Options: ignore the reference, or read an existing local copy without modifying it.
Evidence: `docs/audits/concurrency-plan-2-2026-10-09.md` is present in the existing `mylang-performance-proxy` worktree.
Choice: read §9 there. Apply this task's explicit branch and hard-stop rules; log question/options/evidence/choice/reversibility, investigate gate failures, and rerun a suspected flake once. Builds use build-slot with worktree-local caches and home-volume TMPDIR.
Reversibility: documentation-only interpretation; no other worktree was changed.

## D4 — Guardian's diff-reader capacity on the single cleanup commit

Question: how to commit a 274,396,893-byte deletion diff when Guardian captures at most 64 MiB per Git subprocess?
Options: split the cleanup (contrary to §2), bypass Guardian (forbidden), or increase only its subprocess-reader capacity in a private tool build.
Evidence: the ordinary commit hook failed with `GitSpawnFailed` at int-from-float-budget; `src/git.zig` caps stdout/stderr at 64 MiB. The diff is 274 MB even at zero context.
Choice: create a private detached Guardian worktree under this worktree's ignored cache, at Guardian `beee3df`, and change only `max_git_output_bytes` from 64 MiB to 512 MiB. Build through build-slot with private local cache and home-volume TMPDIR; use this binary for the cleanup commit's complete `all . --gate` hook. No check, baseline, quality threshold or source scope is relaxed. The original Guardian worktree and its installed binary are untouched. Subsequent ordinary builds use the original Guardian after the large diff has been committed.
Reversibility: remove the private tool worktree after use; the sole source change is recorded here and remains local.

## D5 — Merge main's F/U port before the baseline gate

Question: `main` advanced during the cleanup; continue on the old tree or merge?
Options: defer upstream changes, or obey the launch instruction's real merge.
Evidence: `main` advanced from `8a2fccd2f` to `b51a43b76`, bringing the F/U port and its evidence. Upstream includes a change to `src/core/own.zig`.
Choice: merge `main` with `--no-ff` immediately after cleanup commit `310c4920f`, before the §2 full gate. This is an upstream merge, explicitly allowed by §6; no edit by this task to `src/core/own.zig` or `src/core/ir.zig` is made.
Reversibility: ordinary merge history is preserved; never reset, rebase or push.

## D6 — Keep temporary external fixtures outside the checkout

Question: why did five embedded-migration tests fail on the cleanup baseline?
Options: change migration selection rules, or correct this run's TMPDIR placement.
Evidence: the temporary fixtures were beneath this repository's `.mylang-cache`, which the migration tool intentionally excludes; tests expecting external source selection were therefore exercising protected repository paths. Moving TMPDIR outside the checkout makes all 12 driver tests pass unchanged.
Choice: use `/home/epentland/.cache/mylang/frontend-fixes-20261009/tmp` for subsequent builds/gates. It remains private and on the home volume. Rerun the full baseline gate; no source behavior or gate is changed.
Reversibility: environment-only; the first failed run remains recorded separately.

## D7 — F1 warning semantics and the repository lint gate

Question: which existing noalloc checks must change, and how should the new repository gate cover them?
Options: only demote the late Core diagnostic (leaving early E_EFFECT_BOUND rejections), or remove written noalloc from checker ceilings and inspect it in Core.
Evidence: the new CLI regression initially exits 1 with E_EFFECT_BOUND before Core; the edited-body regression exits SourceError. All three new CLI cases fail before the fix. Explicit effects(...) lists have separate established contracts.
Choice: retain the noalloc spelling and source span, but allow allocation in its frontend mask. Builds/tests collect a warning witness per violated concrete declaration, including unsupported roots; check does no Core contract work. Explicit effects(...) negatives retain their tests using effects() instead of the now-advisory noalloc promise. Lint libraries use their checked library bodies, so stdlib contracts can be gated too. Reasoned noalloc waivers attach to the declaring function; allocation violations cannot be accepted silently into the baseline store.

There was no repository lint step. Add test-noalloc-lint to the full gate: run the unfiltered lint --gate on every live selected .my source containing noalloc, plus stdlib sources regardless of formatter exclusions. The initial probe found no allocation violations but 47 pre-existing unrelated blockers: 15 deliberate conditional test bodies and 32 declarations used by constant evaluation/callback values outside direct runtime call edges. Add explicit declaration-level waivers with those reasons to the seven affected fixtures. No lint mode, numeric threshold, existing assertion, or gate is disabled. Future unrelated blockers in these sources still fail the gate.
F1 validation follow-up: comment waivers apply only to the immediately following line, while Guardian requires spec tags immediately adjacent to a test. Use existing @allow attributes before spec-tag comments on functions; constants retain immediately preceding comment waivers. Both tools retain their intended scope. Test receipts carry rendered allocation warnings and emit them only after replay is accepted; speculative receipt probes remain read-only.
Reversibility: source/documentation changes and reasoned fixture comments are ordinary commits; no syntax rule changes.

## D8 — F1 measurement fixture

Question: the frozen migrated EDA graph has no source-written noalloc function to edit.
Options: use a synthetic graph, or mark an existing scalar leaf in a private EDA copy.
Evidence: EDA's support_strs.is_digit is scalar and allocation-free. Its return compares against 48 and 57.
Choice: copy the frozen EDA snapshot into private scratch and add noalloc to that leaf. Each of five independent-cache samples seeds the graph, changes decimal bounds to equivalent hexadecimal bounds, then makes an unrelated equivalent spelling edit in is_upper. The same script and inputs serve both compiler arms. The ReleaseFast before compiler rechecks 1,205/1,213 bodies after either edit; shared-machine median times are 273.107 ms and 271.453 ms. These are elapsed observations, with deterministic work counts reported separately.
Reversibility: only the private copied input changes; the frozen snapshot is read-only.

F1 after measurement: the identical private input and five fresh cache arms report median bounded-edit 213.885 ms and later unrelated-edit 195.536 ms (before: 273.107 ms / 271.453 ms). Both arms report 1,205 bodies performed and 8 reused after each edit; this EDA workload does not demonstrate a body-count improvement. Report that unchanged count explicitly rather than attributing elapsed variation to summary reuse. The validation-session regression separately proves summaries can stand in without running Core allocation contracts.

## D9 — F2 retains publication after a concrete fallback

Question: how can allocation-contract requests publish after a bounded-body edit without changing lowering-only requests?
Options: add a body-policy enum case, widen the shared request, or remember the fallback on its per-check plan.
Evidence: the new three-run regression passes in validation mode and fails in allocation-contract mode because the edited run publishes no summaries. The plan currently has six fields.
Choice: add one allocation_fallback flag to the plan, set only when a new/changed noalloc body requests concrete trees. Publication remains enabled for that run. Existing concrete lowering requests keep their publication rule. The regression requires third-run stand-ins and cold/warm equality in both modes.
Reversibility: a local planning flag, no persistent format or language semantics change.

## D10 — F3 preserves parser diagnostics as a batch

Question: how can project loading retain every parser error and its own edits while preserving existing single-problem callers?
Options: replace the project's problem API, or retain the parser batch beside its first problem.
Evidence: new CLI tests report one error instead of two at 2:15 and 6:15, and attach both binding repairs to the first diagnostic. Project already has seven fields; Problem has six.
Choice: retain the arena-owned parser diagnostic slice in Problem's seventh field. Text and JSON rendering visit the batch. The primary problem and its own fix remain available to existing callers; unrelated edits are never flattened into it. No partial syntax is published. The existing variant-batch test keeps its minimum of three edits, counted across diagnostics instead of requiring all edits on the first one. The pinned Lox migration still makes 412 edits in 9 files over 30 rounds (heap: 147); its log now correctly includes E_FRONTEND_SYNTAX, whose repairs were previously misattributed to the first diagnostic.
Reversibility: in-memory diagnostic transport only, no cache format or syntax change.

## D11 — F4 balances dictionary and set delimiters during recovery

Question: where should a damaged multiline literal stop recovery?
Options: restart at each newline, or honor braces like the existing parentheses and brackets.
Evidence: the four-line dictionary regression produces four diagnostics instead of one and never publishes syntax.
Choice: count opening and closing braces in the existing recovery scan. The same regression requires exactly one diagnostic on the damaged entry and no partial syntax.
Reversibility: recovery synchronization only; accepted syntax is unchanged.

## D12 — F5 shares term matching and separately scans assignment targets

Question: which AST uses must the binding migration resolve before offering a block-local declaration?
Options: enumerate only expression names, or share arena term matching and include statement targets.
Evidence: both requested regressions initially offer E_BINDING_DECLARATION instead of E_BINDING_SCOPE_MIGRATION. arena_fix.termNamed covers directly stored call/operation owners; method receivers and field/index targets also have child nodes in the complete node array. Simple and augmented assignments instead store their target on the statement.
Choice: share termNamed, scan assignment targets, and resolve both against declarations available in the containing lexical block. Skip initial assignment targets themselves: they declare independent identities, as the existing sibling-scope migration contract requires. A new outer plain assignment remains repairable; an unresolved augmented assignment does not. Cover call, buffer/file/resource owners, nested receivers, field/index writes and independent declarations in tests.
Reversibility: migration diagnostic/fix eligibility only; no accepted syntax or runtime semantics change.

## D13 — F6 keeps continuation clauses inside recovery

Question: which restart boundaries must reject continuation tokens?
Options: guard only newline restarts, or also the dedent that ends the damaged suite.
Evidence: the requested malformed-elif regression produces two diagnostics instead of one. Recovery can stop on either boundary.
Choice: guard both with one continuation predicate. elif/else/case are tokens; except/finally are ordinary identifiers in this language, so recognize only their unsupported clause-header form ending in an indent token. This avoids swallowing independent assignments to valid locals named except or finally. Tests cover all five clause forms, subsequent independent errors and those identifier assignments. No partial tree is published.
Reversibility: error synchronization only; no exception syntax or new reserved word is introduced.

## D14 — F7 converts console source to executable fences

Question: teach doctest shell execution/extraction, or make the source explicit in existing checked fences?
Options: introduce a shell transcript runner, or convert examples and reject future embedded source.
Evidence: the new doctest regression fails to identify a cat grow.my transcript and a shell heredoc. The scan also finds package and private-test-module examples with removed module headers.
Choice: convert all seven .my cat payloads in five active guides to mylang fences, with project/file directives for multi-file examples. Keep command/output transcripts separate. Extend the mis-tag lint specifically to cat commands with a .my operand followed by content; command-only and interface-output transcripts remain valid. The deliberately huge memory-budget program is type-checked rather than run without its documented byte ceiling. Convert the recursive record fragment to a checked fence; update stale binding/list/enum/Unit/try prose and noalloc warning semantics. Retain the old generic-section anchor while updating the active feature pointer.
Reversibility: documentation and documentation-gate coverage only; no guest syntax change.

F7 validation follow-up: a grouped private test module cannot use an unrelated neutral main as evidence, because check-project checks only reachable modules; importing that test module would remove its private-access privilege. Add optional `# doc: entry <file>.my`, constrained to one file declared in the project, and check scanner_test.my as the entry. Its missing main receives the runner's existing neutral stub. The new planning regression first fails with action invalid; the actual documentation run validates the private call. No shell execution or new guest syntax is introduced.

## D15 — F8 uses exact embedded-source identity for formatting

Question: how can disk formatting accept the compiler's own intrinsics without trusting arbitrary paths?
Options: permit internal names for every stdlib-looking path, or require the standard module name and all embedded bytes to match.
Evidence: the CLI regression checks an embedded standard module successfully and fails fmt --check. The retained seven idioms comprise five one-blank-line declaration separators (formatter requires two), plus clock_cap and f64_* removed-spelling errors.
Choice: derive the formatter's temporary source context from exact name/byte identity, for both fmt and fmt-module. Ordinary math.my and a real math.my with an extra newline still reject intrinsics. Keep checking behavior unchanged. Remove exactly 51 idiom exclusions and six standard-library exclusions; retain the seven specified oracle inputs with their actual spacing or removed-spelling reason.
Reversibility: formatter context and manifest coverage only; no syntax or trust is granted to modified ordinary source.

F8 validation follow-up: once parsing is permitted, all six standard modules expose two leading blank lines left by their old module headers. Apply their formatter output (exactly those two newlines removed in each file) and rebuild the embedded sources. The first focused green attempt also exposed a Zig module-ownership boundary; keep source-context derivation in Compilation rather than importing its module directly from the separate CLI root. Guardian requires the new formatter contract on a tagged SPEC bullet, so add FRONTEND-FORMAT-STDLIB-1 with the CLI regression as its primary test.

## D16 — F9 distinguishes disjoint arena bindings from shadowing

Question: does a same-name resource binder in another non-nested block make this arena's escape calls ambiguous?
Options: refuse every repeated spelling, or compare the blocks' source containment.
Evidence: the sequential-block CLI regression initially exits 1 without applying both repairs.
Choice: ignore another with_scope binder when neither statement contains the other. Keep nested binders and ordinary local/parameter collisions conservative. The CLI regression requires both arenas and escape calls removed, two remaining expressions, a successful check and an idempotent second fix. A nested same-name regression requires refusal and unchanged source bytes.
Reversibility: fix eligibility only; the retired arena syntax remains rejected.

F9 gate follow-up: Guardian rejects the combined containment condition's four boolean operators (cap three). Name the containment predicate inside the with_scope branch; retain the same logic and threshold. Update the existing tagged arena-fix SPEC bullet with the disjoint-scope contract, and correct its stale W_ARENA_RETIRED/post-check wording to the already-established E_ARENA_REMOVED/syntax-derived behavior. No diagnostic behavior is changed by that documentation correction.

## D17 — F10 measures catalog work and extends one request index

Question: how can a performance-only regression fail deterministically without relying on quiet hardware?
Options: elapsed thresholds, or count actual catalog name visits at the existing scans.
Evidence: instrument the unchanged scans with a specialization statistic, then run the new eight-record/16-specialization reproducer: it fails the linear-work assertion with 467 name visits for 19 final catalog records. Freeze the uninstrumented F9 ReleaseFast compiler before that test for the elapsed baseline.
Choice: reuse Checker's existing record_by_name map and rename its unused initial-count field to an incremental cursor. Populate lazily for lookup/publication and append only newly materialized records. Duplicate names remain maxInt; provider-shape checks and conservative misses are unchanged. The counter stays in in-memory specialization statistics and changes no cache format. The regression now reports 19 visits on each request, 16 fresh specializations initially and 16 reused on the warm request; both execute to 28. A separate index regression proves late duplicates stay ambiguous and a settled catalog is not rescanned.
Measurement: use the same five-sample private EDA fixture and equivalent edits as F1. Before medians are 332.750 ms (bounded edit) and 326.910 ms (unrelated edit), on shared hardware. Record after timings and body counts even if the elapsed result is small or negative.
Reversibility: local lookup algorithm and work counter only; no type identity, cache format, runtime semantics or numeric gate threshold changes.

F10 after measurement: medians are 312.181 ms (bounded edit) and 308.275 ms (unrelated edit), versus 332.750 / 326.910 ms before. All five samples in both arms still perform 1,205 ordinary bodies and reuse 8, and perform 11 specialization bodies and reuse 8. These shared-machine elapsed observations are not a quiet-hardware speedup claim (the before arm overlapped a focused debug build). The deterministic publication reproducer is the algorithmic evidence: 467 catalog visits fall to 19; warm lookup/publication also visits 19 and reuses all 16 bodies.

## D18 — final qualification retains summaries and verifies frozen inputs

Question: how can the required external replay stay below 10 MB without weakening the closeout comparison?
Options: copy another raw capture tree, or run against the unchanged frozen trees and retain only identities, counts and hashes.
Evidence: the historical source inventories match all 302 Lox and 3,744 EDA files. The original mode receipts contain 84 Lox and 366 EDA commands; the native baseline contains 974 Lox answers and 34 EDA answers.
Choice: replay all 450 saved commands with the established EDA module-name mapping and property seed. Compare exact case/status membership, process status, every native answer and EDA output byte hash against the historical references. Preserve raw streams only for failures. Guard the compiler, runner, production tree, build inputs and frozen sources before/after. Keep compact per-command hashes to make the summary auditable; reference the unchanged historical runners and answer files at 0bbfeb740. Run the unmodified S5 qualification in fresh evidence with its original thresholds, shard count and both conformance modes.
Reversibility: evidence and runner storage only; no oracle, source, gate threshold or test selection is changed.

## D19 — preserve the frozen S5 oracle and qualify the added frontend cases

Question: how should S5 compare the already-migrated frontend fixtures without dropping cases or refreezing its old-Core verdicts?
Evidence: the first fresh S5 run passes install (1.25 s) and all 600 Core tests (47.86 s; longest shard 30.18 s), then fails conformance. All 1,516 unchanged identities match in both modes. Commit a9c1109e8 renamed two comprehension tests during the accepted syntax migration and added frontend_mut, frontend_numbers, frontend_type_helpers and frontend_types; the frozen reference predates them. All five current files are unchanged by F1–F10. A read-only inspection finds the same two-name mapping in the separate concurrency qualification adapter, but its frozen-manifest-only selection would omit the new files here.
Choice: retain --set all and every frozen verdict. Add an explicit optional frontend reference to the S5 runner: map only the two documented identities, reject collisions/missing identities, and add the four files from the immutable pre-F1 compiler already preserved for measurement. Require both baseline modes to agree, all added tests to pass, source/reference hashes to match, and exact frozen-plus-added totals with zero mismatches or unsupported cases. The original frozen reference is never edited. The unadapted failure stays recorded. Also make GNU time quiet on a nonzero exit, so a failed command's numeric duration and status are recorded instead of a float-conversion exception. No compiler semantics, source fixture, selection, numerical gate threshold or frozen verdict changes.
Reversibility: optional qualification metadata and harness support only. The default S5 path still uses its original frozen reference; new frontend qualification opts into the checked additive reference.

D19 validation: the preserved pre-F1 compiler passes all 29 additional tests in both modes (10 mut, 3 numeric, 16 type tests; the helper module correctly has zero). Three adapter tests first fail, then pass, including collision, overwrite, missing-name, changed-verdict and incomplete-total rejection. Both the adapter preflight and fresh s5-final2 qualify all 1,547 cases per mode with unchanged references and sources. The fresh S5 install takes 1.20 s, test-core 40.99 s, and its longest shard 27.38 s, within the unchanged 10/300/90-second limits. The final repository and format reruns pass 95/95 and 15/15 steps. The first unadapted S5 failure remains in s5-final.
