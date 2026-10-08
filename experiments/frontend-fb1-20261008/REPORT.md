# FB1 cost report — 2026-10-08

Branch `codex/frontend-fb1`, locked worktree created from plan commit `637a85d6`.
Implementation: `ea61b771a`, positive RC-elision attribution coverage:
`54bfb47b9`, dictionary deletion scratch regression/fix: `061f46aba`.

The cost command reports each reachable emitted Core function, including
specializations, with text/JSON output, optional filtering and build-mode flags.
Per-function pass events sum to the existing whole-program counters. The two
legacy `--stats` lines keep their fields, spellings and meanings; new site and
LLVM-remark metrics are additive. LLVM successes are distinct from Core vector
plans; missing or unmatched LLVM evidence stays explicitly unknown.

Allocation means a static site that may allocate managed heap or runtime scratch
memory, including COW branches, collection growth, deletion tombstone bitmaps,
stable-sort scratch and compound-key hash/equality worklists. An unknown runtime
helper is conservative; foreign and unresolved function calls count separately.
Internal calls do not double-count their separately emitted callee. The shared
`cost.allocation` API requires post-ownership IR. F2 must run debug ownership
before release optimization and follow every internal callee and every block,
including cold paths two calls down. A regression covers this contract. Stack
storage and audited borrow/identity helpers are allocation-free.

## Package-specific exits

- `all46-final/summary.json`: all 46 rows × debug/release/verify/no-facts = 184
  comparisons. Every scalar total agrees with the sum of function rows and the
  `--stats` totals. LLVM text and executable SHA-256s are byte-identical with and
  without stats/LLVM-remark collection in every comparison.
- `p1-final-2/{lox,eda}.{json,md}`: every reachable emitted function's in-place,
  tested and copied update counts, plus the top 20 by copied sites. Inputs are
  the coordinator's locked detached corpus pin clones (`f44302d8` Lox and
  `7e938b6` EDA). Ranking breaks ties by tested count then function name.
- Seven focused cost/collector tests pass. Tests exercise all ownership forms,
  kept/proved checks, allocations, RC counts including a positive removed pair,
  stack lists, inlining, real vector plans, loop versioning and unswitching,
  unknown and successful LLVM remarks, unresolved calls, filtering and JSON/text.
  The collector's missing-tool, unusable-staging, compile-failure and OOM paths
  are covered.
- The deletion regression reproduced expected two allocation sites but reported
  one before the fix. Both the ownership copy branch and the deletion bitmap now
  count. No language-output or migration mismatch occurred.

| Corpus | Functions | In place | Tested | Copied | Allocation sites | Unresolved calls | Unknown source loops | LLVM successes |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| lox | 294 | 48 | 52 | 193 | 801 | 338 | 81 | unknown |
| eda | 749 | 1270 | 159 | 90 | 3585 | 1551 | 608 | unknown |

## Gate receipts

- Final post-S5 `zig build test`: 88/88 build steps; zero test failures,
  Guardian passes. `logs/package-full-gate-final.{stdout,stderr,json}`.
- Standalone whole-tree Guardian: all 88 checks pass,
  `logs/guardian-full-5.{stdout,stderr,json}`. No policy change or exception.
- Final frozen conformance: 1518/1518 in debug and 1518/1518 in release/verify,
  zero mismatches and zero unsupported tests, leak checking enabled.
  `logs/package-frozen-conformance-final.{stdout,stderr,json}`.
- Strict nine-kind × 50-case matrix: all 450 accepted, 6450 native
  comparisons, debug/release/verify and leak checks complete; source and oracle
  hashes unchanged. `fuzz50-final/matrix.json`. Admitted time 133.521s.
- No corpus migration in this package; the frontend, stdlib and application
  source files are unchanged. `ir.zig` is byte-identical to `637a85d6`.

Every build/test used `scripts/build-slot.sh`; heavy commands acquired
`bench-compile.lock` before admission. Reserved CPUs 2, 3, 10 and 11 were excluded.
The final gate and conformance timer run inside the admitted slot; their JSON
records actual affinity and separate admission wait. Per-row commands record
inherited admitted affinity and concurrent heavy processes. Frozen fuzz workers
retain every build/run with its own time and enforce the same excluded CPUs.
Fuzz command affinity is inherited from the recorded admitted matrix/worker
context; unchanged frozen tools do not sample other processes per command.
Their maximum concurrency is three workers under the shared benchmark lock.
Large evidence is committed as this one directory. No main merge, push, global
cache pruning or protected benchmark worktree/cache access occurred.

## Timing, deltas and remaining gates

Command timing/affinity/concurrency evidence is in `logs/*.json` and
`commands/*.json`; bootstrap commands are summarized in `logs/bootstrap.json`.
Authoritative reports use committed `061f46aba` and compiler SHA-256
`5ddab7ce39d576615f55676886252e4dbfff863d0d253cc003886a769c7b1a55`. Earlier `all46-1`/`p1` reports were
measured while the implementation was uncommitted and are superseded by final
reports. The preserved failed `p1-final` attempt exposed a reused evidence-label
error; the tool now namespaces labels by run ID.

The proposal §2 front-end groups (sema core; generics/nominal types;
whole-program analyses; caching/incremental; parsing/syntax;
constants/formatting; other front-end helpers/stdlib) each have zero delta.
The additions live in the post-S5 Core/tooling files. File-by-file deltas are in
`line-deltas.json`; combined implementation delta is +870/-40.

No completed package step exceeded five minutes uncontended. The full gate's
admitted time was 153.809s, final all46 sweep 81.808s, final P1 sweep 27.070s,
and final conformance 27.253s. The observed incremental compiler compile was
2s; the combined focused compile/test command was 4.730s. These are ordinary
slot timings, not the protected CPU10 budget measurements.

Coordinator-owned §5 receipts remain pending here: Lox 974 conformance and 65
tests; EDA 310 tests and 34 byte-identical goldens; the shared synthetic-project
48k/96k/192k timing and compiler/dev-loop budgets on CPU10; and the idiom-suite
C1/C2_policy/C3 report. The coordinator must hold these before asserting the
whole package exit. The wave exit still requires 200 cases per kind.

`list-interfaces --cost` and general CLI help are coordinator-owned additions
after merge. This branch stays available for VP3. The LLVM collector performs a
separate same-flags native compile of exact emitted units; it intentionally has
no remark cache yet. Final P1 collection takes under 30s and individual commands
remain below five minutes. Unknown LLVM loop counts are not replaced with zero.

Guardian feedback observations have been sent to the coordinator for its
required consolidated append+commit in `guardian-zig/FEEDBACK.md`: all 88 checks
pass, the hard line/format checks caught the expanded regression table, and the
focused test wrapper prints `failed command` despite a PASS result and exit 0.

## Strict matrix detail

| Kind | Accepted | Native comparisons | Seconds | Verdict |
|---|---:|---:|---:|---|
| s0 | 50 | 750 | 23.951 | pass |
| s1 | 50 | 750 | 33.510 | pass |
| rc | 50 | 450 | 18.472 | pass |
| rebinding | 50 | 750 | 28.890 | pass |
| iteration | 50 | 750 | 42.168 | pass |
| dict | 50 | 750 | 64.608 | pass |
| text | 50 | 750 | 15.511 | pass |
| number | 50 | 750 | 29.368 | pass |
| functions | 50 | 750 | 24.019 | pass |

Closeout staging/commit/status commands are timed with the same runner in
`.mylang-cache/frontend-fb1/closeout/logs`, preserved locally; this avoids a
commit attempting to include its own completed receipt recursively.
