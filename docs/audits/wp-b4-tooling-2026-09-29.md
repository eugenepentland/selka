# WP-B4 tooling and GC follow-up

This lane starts from `claude/rc-perf` at `1a098368`. Embed work waits for the
combined Phase A branch. Independent changes and their evidence are recorded
here so that integration does not mistake the remaining collector work for a
completed item.

## Independent tooling changes

| Item | Rule and coverage | Evidence |
| --- | --- | --- |
| Named module tests | `test-memory-budget` uses `src/memory_budget.zig` as its own test root and participates in `test` and `test-compile`. The named `runtime_contract` module has no tests; other named modules have existing dedicated roots. | Six memory budget tests pass; input coverage recognizes the new root. |
| No-cache objects | `--no-cache` disables frontend reuse independently of `--cache-dir`; no-cache tests stage native objects inside their owned source snapshot. | CLI-CACHE-ISOLATION-1 checks both argument orders; the CLI driver checks test/build source-root cleanliness and explicit build object placement. |
| Doctest workspaces | Workspaces use `TMPDIR` or `/tmp`; child builds receive the workspace object directory. | The CLI driver checks both documentation and caller roots remain clean and temporary workspaces are removed. |
| Frame advice | Failed tests retain their located R_FRAME_LIMIT trap and explain `--max-frames=N` and the required `--max-memory`. | TEST-FRAME-ADVICE-1 exercises a recursive test with a two-frame budget. |
| Host and guest ceilings | Only guest children receive a one-use receipt for restoring the compiler-installed soft RLIMIT_AS; caller soft and hard ceilings remain effective. | MEMORY-HOST-GUEST-1 covers the named module and native guard. The CLI maps over 9 GiB virtually under the default compiler ceiling; an inherited 6 GiB soft ceiling permits a 5 GiB reservation and rejects a 9 GiB reservation. |
| Selfhost numbers | The lexer recognizes numeric prefixes, underscores, leading dots and exponent extents with the production token boundaries, including malformed spelling boundaries. The existing differential harness accepts a live compiler and runs in `test-selfhost-numeric`. | NUM-LITERAL-1 fixture plus the full lexer corpus: 31 fixtures, 450 token lines, zero mismatches, three documented skips. Ampersand now produces the production lexer's existing token; expression rejection belongs to parsing. |

## Proven snapshot corrections

- GC-MUT-ARG-ROOT-1: preparing a mutable field or element can redirect the owner
  at the beginning of its copy-on-write place. A previously read expression
  snapshot must then publish its own root. The original mutable argument repro
  passes regular GC and stress; the reduced guest test passes RC, GC, stress,
  counting RC, release RC and release GC.
- ITERATION-FIELD-SNAPSHOT-1 and RC-ITERATION-HOLD-TRANSFER-1: a hidden loop
  source remains a semantic observer of a named transfer, so moving a record
  field cannot give that name exclusive ownership of the loop's header.
  Ownership classification and field extraction preserve a snapshot. The RC
  field-transfer planner no longer treats the hidden iteration hold as an
  exception. Direct structural writes to the actual iteration source retain
  their existing mutation trap. The original field-move repro passes regular
  GC and stress; the guest regressions pass all six modes above. The older CLI
  assertion has been updated to check the original iteration sum and final
  grown collection rather than expecting a false mutation trap.

The iteration observer currently compares root identity conservatively. Exact
field paths would let later interface analysis avoid copying unrelated sibling
fields of the same record. Generated code and corpus measurements remain lane
acceptance requirements.

## Remaining work and validation

GC-ARENA-LOCAL-LIFETIME-1 fixes the remaining arena and scan-plan historical
repros: both now pass regular GC and stress, where stress previously exited
139 and 134. Removing only their arena scope lines initially eliminated the
failures; backtraces placed them in collection during list clones before an
arena opened. Arena close checks had implicitly extended every earlier compiler
receiver temporary's lifetime. They now check source bindings, so old receiver
snapshots acquire no new implicit close-time read. A tagged guest regression
reproduces the historical arena program and checks named values remain correct.
Both new regressions pass RC, GC, stress, counting RC, release RC and release
GC. The second iterates a fresh list without a source-level owner, allocates
inside an arena, then reads the row and continues after close: the hidden
iteration receiver remains live through its real uses. Existing QBE-ROOTLIVE-1
tests pass 17/17 and ARENA-MANAGED tests pass 35/35, including source-binding
retention and escape coverage.

A dictionary metadata lifetime experiment and a live scalar root-slot
experiment did not fix the failures and are excluded from the change.

The independent checkpoint's broad Zig gate passed every non-CLI step,
including `test-qbe`, `test-qbe-build`, `test-native-memory`,
`test-native-heap`, and formatting. It exercised 1,328 guest cases across 208
programs in both default RC and GC. Its two CLI failures were the outdated
iteration assertion and the documented cold libunwind `ar rcs` stderr flake.
The warm full CLI run passed 254/255; the remaining new assertion needed to
accept the counted runtime's expected statistics line. The corrected filtered
CLI and formatting gate passes 2/2, and the final warm full CLI rerun passes
255/255 (10/10 build steps). Full stress and release guest suites pass
1,328 cases; the final counting suite, including the two new arena regressions,
passes 1,330 cases across 209 programs with no dropped cases. An earlier counting
run captured a transient name-shadow diagnostic in the new fixture and was
rerun after the fixture correction.

The RC dev corpus uses the frozen independent checkpoint and the original
accepted GC denominator. All 86 program/backend output pairs match. Compared
with A1's `results-m16-codex-dev.json` absolute RC counts:

| Backend | Rows under 1.3x | Geomean RC / accepted GC | Worst ratio | Largest instruction increase |
| --- | --- | --- | --- | --- |
| QBE | 43/43 | 1.064 | 1.2814 | 0.0266% (`schematic/changed-value`) |
| LLVM | 43/43 | 1.069 | 1.2560 | 0.0398% (`schematic/changed-net`) |

All movements are below the 1% allowance. The affected arena repro's `f1`
emission shrinks from 3,306 to 2,270 IL lines, from 12 to 8 root slots, from 178
to 80 descriptor-root stores, and from 11 to 5 arena retain checks. The five
remaining checks still cover its source bindings.

Lox build, tests and driver gates pass in default RC, GC, release RC and release
GC. The supported `MYLANG_TEST_ASAN=1` native-memory driver passes after its
host-limit test first probes whether kernel guards are supported; sanitizer
builds deliberately decline them and keep their large shadow mapping free.

The 100-seed RC fuzz gate reports 98 clean seeds, zero RC divergence and two
GC-stress findings. The sources and exact before/after stdout, stderr, exit
codes and compiler hashes are preserved in
[`experiments/wp-b4-gc-20260929`](../../experiments/wp-b4-gc-20260929/comparison.json).
Both findings predate the arena lifetime correction: seed 19 aborted with 134
before it, and seed 87 exited 139. Both regular-GC runs print the expected
results. After the correction seed 19 exits zero but still prints a stale
numeric field; seed 87 still exits 139 with the same partial output. These
remain open GC findings; the four historical B4 repros are fixed. The earlier
compiler hash is `bebf5f524f1cb1465d89c82350ca2a4b6172c13b1bfe590349cf445a1b77cb15`
(checkpoint `e356e099`); the corrected compiler hash is
`8a2216a8cf470b6ed7833df949d67afae832991e55d3eedfba2a2894d28f23cf`.

The separate final GC dev measurement matches every output and records new-GC
instruction counts relative to the original accepted GC baseline: QBE geomean
1.011, non-Lox 1.001, worst 1.08; LLVM geomean 1.014, non-Lox 1.003, worst
1.13. These explain the collector build and do not replace the accepted
GC denominator for RC acceptance. Both measured JSON files are preserved in
`experiments/wp-b4-gc-20260929`. A further collector build with the frozen
`e356e099` compiler isolates the arena lifetime follow-up: all 86 outputs match,
its before/after GC geomeans change by +0.000029% QBE and +0.0000068% LLVM, and
all row movements are below 1%. Largest increases are +0.00461% QBE
(`lox/vm/string_equality`) and +0.00489% LLVM (`schematic/changed-value`);
largest decreases are -0.00675% QBE and -0.00905% LLVM (`schematic/fixture`).
These are measurement noise. The 1.011/1.014 ratios against the older accepted
GC are already present at the frozen checkpoint, so cannot be attributed to
the arena correction. `gc-followup-comparison.json` preserves each row's
absolute counts and both compiler hashes.

## Combined Phase A continuation

The combined continuation is based on `ac504471` (frozen Phase A `d8f66585`
plus the independent B4 checkpoints). Its compiler source is the same Phase A
base that landed on main at `80dd5190`; the continuation stays on its own
candidate branch. Independent measurements above retain their original source
and collector baselines and are not the final combined gate.

- EMBED-CONTEXT-1 adds status, byte count and BLAKE3 embed receipts to navigation
  and context snapshots, including partial answers. Held bytes and file-backed
  providers are rechecked, with stale and unavailable outcomes distinct. Empty
  embed envelopes and source-only snapshot digests remain compatible; actual
  embeds intentionally contribute to the snapshot digest. Byte-limited answers
  list `source.embeds` in omissions without losing their identity contribution.
- EMBED-PROJECT-BUDGET-1 bounds providers before allocation by per-file and
  remaining source-plus-embed totals. Successful module/path identities charge
  once; repeated references deduplicate before reading, while separate modules
  using one physical file charge separately. `counts.bytes` remains source-only
  and `embedded_bytes` records the successful embedded total.
- Native test snapshots capture the loaded entry closure under the same caps.
  Physical copies deduplicate before reading. Refused files retain length-only
  metadata and materialize as sparse refusals, never accepted zero-filled
  contents. Configuration identity forces recapture after budget changes.
  Replacement providers recapture their reachable closure from the original
  asset roots, include its receipts in graph identity and recheck it before
  publication. Real CLI coverage checks exact/tight/widened budgets, a 1 MiB
  refused input, cross-module charging and warm-cache replacement fixture edits.
- The real `host_native.Program.build` path reads file-backed embedded projects;
  a generic `schema-project` fixture compiles an embedded generic body. The
  `generic_api` provider performs constraint lookup on the loaded project and
  `reference.EntryReader` deliberately offers disk-free synthesized/stdlib
  entry reads, so neither requires a new ambient disk callback. Main context
  now carries its loader's existing embed callback.
- MEMORY-HOST-GUEST-1 applies the same receipt equality and hard-ceiling checks
  to frame preflight and actual restoration. Native host invocation restores
  only the child; directory compiler children inherit checkpoint metadata even
  when mode normalization needs no exec. Actual CLI and host tests cover
  reservations above 8 GiB and genuine tighter caller ceilings. Extreme frame
  values return status 2 without arithmetic overflow. Native receipt parsing
  now matches Zig's strict unsigned decimal grammar.
- The actual snapshot test exposed `qbe-build` rejecting a forwarded
  `--diagnostics=json` flag. The driver now accepts and forwards presentation to
  the source frontend, with a direct native-build E_TYPE JSON regression.

Focused combined coverage passes: 239 native-test root tests, 27 embedded
loader tests, 41 context tests, four host-native tests, and actual CLI snapshot,
context/schema, guest-budget and replacement tests. The final frozen combined
lane gate below supersedes the pre-review broad runs.

Scratch evidence stays in this worktree's `.tmp`. No unresolved collector fuzz
finding is claimed fixed by embed or memory-boundary changes.

## Guardian feedback and ROI

The independent checkpoint's whole-tree commit gate passed all 88 checks. Local
ROI labels record `ban-globals` subject `subj_ba39a80d22592d7c5edec56f` and the
primary duplicate-spec subject `subj_bc6a023edd15942c395d7b8b` as useful review,
with one extra gate cycle attributed to each. Duplicate location details
`subj_23564688439ba1cdc31744ae` and `subj_804bd6acd1808a96122e0085` share that
classification with cost omitted to avoid counting the same retry twice. Triage
minutes are unknown. The experimental unverified GC spec finding remains
pending. Guardian already declares `src/memory_budget.zig` a test root in its
configuration, so an additional check must compare that declaration with the
actual runners in `build.zig` to catch the original wiring gap. Parent recorded
the shared feedback entry in Guardian commit `0d87670`; the final independent
checkpoint/transplant follow-up is Guardian commit `e479723`. It records the
whole-tree 88-check pass and distinguishes configured roots from executable
build/gate runners.


## Final combined acceptance

The source freeze is `b5c04602`, with Debug compiler SHA256
`18106e5f38ae4544082cfbe56672f6cf7a4d7ee259b8fe11b151a825ff7e4de2`.
The installed and prefixed compilers are byte-identical. The final
`gate.sh b4-final` completed with HEAD unchanged and all 27 recorded statuses
zero. Its strict verifier checks that one source/compiler, every status, all
case names and counts, corpus outputs and supplemental results. No frozen gate
retry or source edit was needed. Evidence is preserved in
[`experiments/wp-b4-combined-20260929`](../../experiments/wp-b4-combined-20260929/verification.json).

| Check | Frozen result |
| --- | --- |
| Install; full Zig gate | Pass; 102/102 steps, 2,681 selected Zig tests |
| QBE; native build driver; formatting | Pass; 484/484 QBE tests, 29/29 native-build steps |
| Native memory; native heap | Pass; 23/23 and 10/10 steps |
| ASAN native memory | Pass; 23/23 steps |
| Language suite in all nine modes | Identical 1,442 fresh cases across 220 programs, zero cached/failed/skipped/dropped/unloaded |
| Lox build, RC/GC and release RC/GC | Four project builds pass |
| Lox tests and driver, same four modes | 65 cases across 10 programs plus 13 driver cases per mode, zero failures/skips/drops |
| Historical collector repros | All four pass GC and stress, eight successful runs |
| Selfhost numeric differential | 31 fixtures, 450 token lines, zero mismatches, three documented skips |
| RC fuzz, 100 seeds | 98 clean, zero invalid, zero RC divergences, two known stress-only findings |
| Source-freeze Guardian hook | All 88 whole-tree checks pass |

Sharded Zig runners report tests belonging to other partitions as skipped;
their selected union is the count above. Every language mode has the same case
name digest `a7bf31abd49868b94f9aa5445f8e7c5402acfc369e4dc882c271e777e51f7e3a`.
Compared with final A5, four cases are added. The existing
`iteration_identity::test_write_back_through_a_field_keeps_the_iterated_list`
is renamed to `test_write_back_through_a_field_preserves_iteration_snapshot`
and retains coverage of the approved copy/write-back behavior. No unrelated
case is removed.

The final RC dev and smoke corpus both match all 86 accepted GC output pairs.
The original accepted archived GC binaries remain the denominator; their
manifest is archived separately. Absolute RC counts are compared with A1 and
final A5 controls, with every row within 1% on both backends:

| Backend | Rows <= 1.3x | Geomean RC / accepted GC | Worst ratio | Largest increase vs A1 | Largest increase vs final A5 |
| --- | --- | --- | --- | --- | --- |
| QBE | 43/43 | 1.064491 | 1.281419 | 0.015454% | 0.014089% |
| LLVM | 43/43 | 1.069105 | 1.255957 | 0.025790% | 0.030738% |

All maxima are `schematic/changed-value`. The full per-row absolute counts and
changes are in `rc-comparison.json`, so the A1-to-A5 inherited changes are
separate from B4. The largest reduction vs A1 is LLVM `parity/suite/text_ops`
(-0.1483%); its change vs final A5 is below 0.001%, so it is inherited. Other
movements are small startup/ownership traffic and layout noise, below the
allowance. The earlier generated-arena reduction remains the direct emission
proof for the liveness correction; the new combined changes mostly affect
frontend/provider reads and startup receipt decoding.

A separate frozen GC dev corpus also matches all 86 outputs. Relative to the
accepted archived GC its geomeans are 1.011305 QBE and 1.014061 LLVM. It does
not replace the RC acceptance denominator. Comparing absolute counts against
both independent frozen checkpoint GC and its post-arena follow-up establishes
that these ratios are inherited: every row moves below 0.02%. Against the
post-arena follow-up, largest increases are 0.000151% QBE (`lox/vm/binary_trees`)
and 0.001986% LLVM (`lox/vm/string_equality`); largest decreases are -0.009190%
and -0.018937% (`schematic/changed-net`). `gc-comparison.json` retains all rows.

The residual fuzz source hashes match the independent checkpoint's preserved
sources. On frozen combined B4, seed 19 exits zero under stress but still
prints a stale numeric field; seed 87 still exits 139 with partial stdout.
Their regular GC and RC outputs match. `fuzz-comparison.json` preserves exact
exits, stdout/stderr and the new compiler hash, while the independent comparison
above preserves the earlier hashes and symptoms. Final A5's compiler
`4059a85e3d081f8a73b370e03e7d86cba8eb8a47531bfcdd7c09e6cc109d74b1`
had seed 19's scan-plan abort (134) and seed 87's crash (139). Both findings
remain open; only the four historical B4 repros are claimed fixed.

Final Guardian feedback is appended and committed in `guardian-zig` at
`e59b878`, recording the exact frozen checks/counts and retained collector
findings. The candidate does not update main; the integrator owns that merge.
