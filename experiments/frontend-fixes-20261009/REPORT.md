# Frontend follow-through fixes — 2026-10-09

Completed §2 and F1–F10, in order, on `codex/frontend-fixes-20261009`. Each fix began with a failing regression and ended with a passing full gate and its own commit. The branch starts at the requested `b52b6edb2`; upstream `main` was merged with a real merge commit, `d9deb9b70`, before the cleanup baseline. Main remains at `b51a43b76`. No hard stop was reached, history was not rewritten, and nothing was pushed or merged into main.

Production implementation ends at `17676312e`; qualification tooling ends at `350a9e057`. The qualified Debug compiler SHA-256 is `a156c8c0351757a787dc2cea9c54a6e8f2cba45432c1bb491b1f92d73969a923`. Later report/evidence changes do not alter that compiler. [Final tree audit](final-tree-audit.json) binds 622 source/build files and confirms the protected Core files and Guardian policy/baselines were not edited by this task.

## Evidence cleanup

Cleanup commit: `310c4920f`. The two historical evidence directories changed as follows:

| Measure | Before | Retained |
|---|---:|---:|
| Files | 24,087 | 35 |
| Bytes | 270,758,633 | 2,208,312 |

Removed 24,052 files and a net 268,550,321 bytes. Every REPORT/STATUS, required small identity/qualification/summary JSON, and `full-gate-3.log` remains. Large summaries retain counts, identities, verdicts and hashes instead of embedded raw reports. Links and resolvable inline references to removed captures now cite `0bbfeb740:repository/path`, with retrieval instructions. The final audit finds no dangling Markdown links in retained reports. All original objects remain reachable; `git show 0bbfeb740:PATH` retrieves the archived bytes. [Cleanup receipt](cleanup.json) records exact counts and rewrites.

The cleaned, merged baseline passed 94/94 steps before F1 (`ede3e6a58`). Its first attempt exposed temporary fixtures beneath an intentionally ignored repository directory; moving TMPDIR to private home-volume scratch fixed the environment without changing source selection.

This run's complete evidence, scripts and report occupy less than 2 MB, below the 10 MB limit. External qualification retains only counts, hashes and guards; no external command failed, so no raw external streams are stored.

## Fixes and regression evidence

[Gate receipts](gates.json) retain failing and passing attempts, commands, log hashes and test failures. Focused counts below include neighboring regression cases and are not additive unique-test totals. Each row also passed the full 95-step gate.

| Fix | Failing reproducer and resulting behavior | Commit |
|---|---|---|
| F1 | Checks originally rejected allocating `noalloc` bodies; runtime/lint/replay behavior also failed the new assertions. Checks now avoid allocation contracts; Core execution warns and lint blocks. Focused CLI 8/8 and Core 1/1 pass. | `242a47ede` |
| F2 | Seed → bounded-body edit → unrelated edit lost summary publication. A separate fallback flag preserves publication; the third request uses stand-ins and equals a cold check in both policies. Focused 8/8 pass. | `bc14327e8` |
| F3 | Project/module mode reported only one of the errors at 2:15 and 6:15 and conflated repairs. It now retains every parser diagnostic with its own edits. Focused 4/4 pass; pinned Lox migration keeps 412 edits in 9 files over 30 rounds and remains idempotent. | `f97c31441` |
| F4 | A damaged four-line dictionary produced four diagnostics. Brace-aware recovery produces exactly one and publishes no partial tree. Focused 8/8 pass. | `811f0aa1d` |
| F5 | Branch locals used through `n += 10` or `xs.append(3)` received unsafe confined declarations. Shared term matching plus target resolution now reports `E_BINDING_SCOPE_MIGRATION`; call/buffer/file/resource owners and field/index targets are covered. Independent declarations remain repairable. Focused 15/15 pass. | `20b74bf4f` |
| F6 | A malformed `elif` caused an extra error at its continuation. Both recovery boundaries skip continuation clauses; tests also preserve independent errors and valid identifiers named `except`/`finally`. Focused 16/16 pass. | `cf2d77e75` |
| F7 | Doctest missed console-embedded programs; a private-module example also lacked a valid checked entry. Seven payloads became checked fences, a console-source detector prevents recurrence, and explicit project entries verify private test modules. Targeted prose and examples are current. Focused 23/23 pass. | `104a1f29b` |
| F8 | Formatting rejected the six embedded standard modules. Exact module-name/source-byte identity now supplies their trusted context; ordinary or modified lookalikes still reject intrinsics. Their leading blank lines are normalized. Removed 51 idiom and six stdlib exclusions; the seven specified exceptions retain accurate reasons. Focused 5/5 pass. | `fbc5ec1e7` |
| F9 | Two sequential same-name arena blocks were refused. Disjoint scopes now both migrate, check and remain idempotent; nested same-name bindings still refuse without editing. Focused 4/4 pass. | `78bbf1918` |
| F10 | The linear-work regression failed with 467 record-name visits for 19 records. One incrementally extended request index reduces this to 19, preserving missing/duplicate-name misses and provider-shape checks. Cold and warm requests execute to 28; warm reuse retains all 16 specializations. Focused 9/9 pass. | `17676312e` |

## F1 command behavior

For an otherwise valid program that violates written `noalloc`:

| Command | Behavior | Fixture exit |
|---|---|---:|
| `check`, `check-project` | No allocation-contract computation or warning | 0 |
| `build` | Nonfatal `W_NOALLOC_ALLOCATES`, identifying the bounded function and allocation witness/callee | 0 |
| `run`, `build --run` | Same warning; preserves program output and exit result | 0 |
| `test`, cached test replay | Same nonfatal warning; replay emits it once after acceptance | 0 |
| `lint` | Warning plus blocking-rule diagnostic `L_NOALLOC_ALLOCATES` | 0 |
| `lint --gate` | `noalloc-allocates` blocks in every profile | 3 |
| `cost` | Static may-allocate sites remain visible; no noalloc warning (four sites in this fixture) | 0 |

[Ten-command receipt](f1-commands.json). Explicit `effects(...)` ceilings retain their existing semantics. Unsupported concrete bodies warn with the reason and still block lint. Active code/tests no longer reference `E_CORE_ALLOCATION_BOUND`. Static site counts are not measured allocation counts.

The full gate now runs unfiltered `lint --gate` on all 14 live noalloc sources, including stdlib, with no unwaived allocation violations. Its first probe also found 47 unrelated pre-existing blockers in seven fixtures: deliberate conditional test bodies and declarations reached by constant evaluation/callback values. Explicit declaration-level waivers explain each; no lint profile or threshold was relaxed.

## Final qualification

- Full gate: **95/95**. The complete F10 run executed **2,314** passing tests. The final rerun after the qualification-tool update executed **600** passing tests, with other results cached; 4,200 skips are shard routing. Both exit 0.
- Format gate: **15/15**, covering **818** selected `.my` files; **200** exclusions remain. [Exclusion audit](f8-format.json).
- Whole-tree Guardian: **88 checks pass**. No policy or baseline changes. Required feedback is committed in `guardian-zig` as `0f21bd8`.
- Documentation: 773 files / 1,103 blocks; **221 run**, **62 checked**, 23 existing documented skips, zero mistagged blocks or failures. [Documentation receipt](f7-docs.json).
- S5: [fresh qualification](s5-final2/summary.json) passes install, all **600 Core tests across 32 shards**, and both conformance modes. Install **1.20 s ≤ 10 s**; test-core **40.99 s ≤ 300 s**; longest shard **27.38 s ≤ 90 s**. RSS inspection passes (largest test RSS 578 MiB). Admission waits are recorded separately.
- External: **450/450 commands** with exact case/mode/verdict membership, **974/974 Lox native answers**, and **34/34 byte-identical EDA outputs**. Compiler, source, build-input and runner guards pass. [External summary](external-final/summary.json), [Lox modes](external-final/lox-modes.json), [EDA modes](external-final/eda-modes.json), [Lox native](external-final/lox-native.json), [EDA native](external-final/eda-native.json).

S5 required a qualification-tool repair, committed as `350a9e057`. The [first unadapted attempt](s5-final/summary.json) remains rejected evidence: two test identities had been renamed by the already-accepted syntax migration, and four frontend files postdated the old-Core reference. The original 1,518 frozen cases and verdicts remain intact. Exactly two documented names are mapped, and an immutable pre-F1 compiler supplies 29 additional frontend cases, independently checked in both modes. `--set all` is retained. The fresh run requires **1,547 matches, zero mismatches and zero unsupported cases per mode**, with source/reference guards. The original reference hash remains `b6703c9fc0f135844131130cab4c0c8e263d2966ac5e85d24d380ae5deece3bc`. See [additive reference](s5-frontend-reference.json), [adapter regression receipt](s5-adapter-tests.json), and [final conformance guard](s5-final2/frontend-conformance.json).

The external replay uses the unchanged 302-file Lox and 3,744-file EDA snapshots. It retains the established EDA `src.` name mapping and the six property-bearing commands' seed, `8679566789041942096`. No command, case, mode, verdict or native output was dropped. Production bytes and the compiler remain unchanged since that replay despite the later qualification-tool changes.

## Measurements

All elapsed values are five-sample medians from ReleaseFast compilers on shared hardware. The frozen EDA graph has no written noalloc function, so a private copy marks scalar `support_strs.is_digit` noalloc. Each fresh-cache sample seeds the graph, changes decimal bounds to equivalent hexadecimal spelling, then makes an unrelated equivalent edit in `is_upper`. Both arms use identical source bytes and restore the private input.

| Change | Bounded edit before | After | Unrelated edit before | After |
|---|---:|---:|---:|---:|
| F1 | 273.107 ms | 213.885 ms | 271.453 ms | 195.536 ms |
| F10 | 332.750 ms | 312.181 ms | 326.910 ms | 308.275 ms |

Every edited request in all four arms still performs **1,205 ordinary bodies and reuses 8**, and performs **11 specialization bodies and reuses 8**. The seed performs 1,213 ordinary bodies. **This EDA measurement demonstrates no body-count improvement.** The elapsed observations are not a quiet-hardware speedup claim; the F10 before arm overlapped a focused Debug build.

F10's deterministic algorithmic evidence is separate: publication work falls from **467 name visits to 19** for the 19-record reproducer. The fixed warm request also visits 19 names and reuses all 16 specialization bodies. Missing names and late duplicates remain conservative misses. Receipts: [F1 before](f1-before.json), [F1 after](f1-after.json), [F10 before](f10-before.json), [F10 after](f10-after.json); [measurement runner](measure_check.py).

## Decisions and remaining scope

[DECISIONS.md](DECISIONS.md) records options, evidence, choices and reversibility:

- D1–D6 isolate the worktree, compact historical summaries, preserve reachable evidence, merge moving main, and correct TMPDIR placement. Guardian's 64 MiB diff-reader limit required a private pinned tool build with only its capture capacity increased to 512 MiB for the single cleanup commit; every quality check still ran.
- D7–D9 separate written noalloc from explicit effect ceilings, add blocking lint coverage and accepted-replay warnings, disclose the private measurement fixture, and preserve summary publication after concrete fallback.
- D10–D13 retain diagnostic batches and individual edits, balance braces, share complete binding-use matching, and recover past continuations without introducing exception syntax or reserved words.
- D14–D16 check console programs with existing doctest fences plus explicit private-module entries, trust formatter intrinsics only for exact embedded source identity, and distinguish disjoint arena bindings from nested shadowing.
- D17–D19 use one conservative request index, distinguish deterministic work from elapsed observations, retain compact guarded external evidence, and qualify every frozen and added frontend case without replacing the old oracle or lowering a threshold.

For the broader follow-through plan, **phase 1 is complete and requalified**: the current language, documentation/formatting coverage, arena migration, and full frozen Lox/EDA qualification. **Phases 2–6 have bounded first steps, not complete redesigns**:

| Phase | Completed step | Still limited |
|---|---|---|
| 2: editing/recovery | Independent diagnostics, reliable ownership/spans, conservative recovery | Original source plus tokens remain the lossless basis; there is no complete CST |
| 3: incremental checking | Nominal specialization reuse and linear name indexing | Conservative misses remain; the measured EDA edit still rechecks 1,205 ordinary bodies |
| 4: effects/contracts | Accepted Core noalloc warning and blocking lint contract | Inferred facts remain where capability, mutation, ownership and cache consumers need them |
| 5: source-shaped lowering | Checked range plans and a shared directory-path validator | **Range is the only construct family on the new lowering**; necessary generic/concrete checking remains |
| 6: cost visibility | Selected typed cost inventories and the existing Juice/counter example | No application speedup or new copy-annotation justification is established |

Historical quiet-timing evidence remains unfinished (15/21 jobs, 177/333 samples); it is not relabeled as passing evidence for this compiler. Guest HTTP libraries and borrowed views remain separate work. This branch is ready for review.
