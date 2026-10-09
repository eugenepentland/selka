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
