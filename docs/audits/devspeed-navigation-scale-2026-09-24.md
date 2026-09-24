# Development-speed lane: navigation at scale (2026-09-24)

Branch `devspeed/navigation-scale`, based on `main` at `fd36abc2` (full gate green).
Scope: `index-project`, `context`, `tests-for` and `list-interfaces` on large
projects — the findings of §4 of `docs/audits/development-speed-2026-09-23.md`,
plus the `NavigationLimit` host failure at 200k lines.

## Outcome

| Requirement | Status |
| --- | --- |
| No fixed cap a real project can hit | Done. The navigation caps are gone: `Limits` defaults to no cap, a cap a caller passes still reports `NavigationLimit`, and no command passes one. Two more fixed caps blocked the 500k tier for every command, `check` included. The whole-program nominal-layout work budget is now derived from the source size. The 16 MiB project byte budget keeps its default, but its diagnostic now names the `mylang.json` field that raises it. |
| Works at 200k and 500k | Done: all four commands answer at both tiers (tables below). |
| Memory no worse than `check` | Peak RSS is within 0.5–4.6 % of `check --no-cache` at every tier. No command path holds every relationship row any more. |
| Bounded `index-project` output | The default is `navigation-summary-v1`: 15 KB, 58 KB and 144 KB at 50k, 200k and 500k. Before, the default was 36 MB at 50k and a host failure at 200k and 500k. `--module`, `--symbol` and `--kind` print `navigation-selection-v1`; `--full` streams the unchanged `navigation-v1`. |
| `tests-for` on a red project | Done. It answers from the syntax: the same answer as the checked graph plus a `basis: syntax` line, exit 0. |
| `context --symbol=module.function` | Done, and `tests-for` and `index-project --symbol` accept the same spelling. |
| Ratchet test | `NAVIGATION-SCALE-1` (see Tests). |
| Docs | `docs/tooling/navigation.md` gains two new sections ([summary and filters](../tooling/navigation.md#summary-and-filters-for-large-projects), [call-site spelling](../tooling/navigation.md#call-site-spelling)), and `tests-for` on a red project is documented. `docs/tooling/agent-context.md` is updated. `src/features.json` gains `navigation-summary-and-filters` and `navigation-call-site-spelling`, and the `source-navigation` and `tests-for-index` summaries are amended. The CLI help is updated. |

## What changed

The commits on the branch, oldest first:

1. `de17d690`: **a 500k-line project loads and checks.**
   - `src/nominal_layouts.zig`: the nominal-layout expansion budget was a
     fixed 100000 operations for the whole program. The generated 500k project
     (1200 modules) failed `check` with `E_GENERIC_LIMIT` at module 581, even
     though its layout work is linear. The budget is now `max(100000, source bytes)`
     (`NOMINAL-LAYOUT-WORK-1`). A growing generic family in a small program still
     rejects at 100000 with the old message.
   - `src/project.zig`: an `E_PROJECT_BYTES` refusal now names the budget
     that ran out, its size and the `mylang.json` field that raises it; before, it
     said only `TooLarge` (`PROJ-BUDGET-MESSAGE-1`).

   Both edits are outside the navigation files. They are small and localized, and
   without them no command answers at 500k.
2. `aff8b3c4`: **`list-interfaces` and test discovery are now linear in the
   function count.**
   - `list-interfaces` found each exported callable's checked entry, and its
     tests-column identity, by scanning every checked function: two scans per
     line, so quadratic. At 200k it took 4.4 s against 1.5 s for `check` (7.0 s
     under load in the first baseline). A name table built once per listing now
     answers both lookups, taking the first match in program order as the scan
     did.
   - `tests_index.discoveredTests` scanned every module for `@test`, once per
     function. It now reads each module's attributes once.
   - `tests_index.buildNamed` exposes the reachability walk over any function
     table.
3. `e7e92a08`: **navigation at scale.**
   - *No cap, bounded memory* (`src/navigation.zig`). `collect` now runs a
     declaration pass, then a relationship walk directed by `Collect.edges`:
     - `.all`: the old behaviour, used by `render` and the tests.
     - `.none`: used by the summary.
     - `.visit`: a visitor sees the finished declaration table, answers
       `wants(from, to)` before a row's location is computed, and decides
       whether to keep each row.

     `--full` streams each row to stdout and keeps none; a selection and
     `context` keep only the rows into or out of what they selected. The symbol
     table and the declaration map are sized once from the project
     (`declarationBound`) in the caller's allocator, so the largest table is not
     copied as it grows and leaves no outgrown buffers in the arena. The row order
     is unchanged, so `--full` is byte-identical to the old default output. At 50k
     both are 36,231,941 bytes and identical once the compiler identity is
     normalized.
   - *Bounded output* (`src/navigation_views.zig`, new).
     - `index-project` without a flag prints `navigation-summary-v1`: the
       snapshot digest, the compiler identity, totals, one row per module (path,
       exported count, non-zero declaration counts by kind) and the drill-down
       queries with the entry path filled in.
     - `--module=NAME`, `--symbol=NAME` (the declaration and the members it owns)
       and `--kind=KIND` print `navigation-selection-v1`: the selected
       `navigation-v1` records, every reference into or out of them, and the
       snapshot rows of the modules those records sit in. A filter that names
       nothing prints `status: missing|ambiguous` with the candidates and exits 2.
     - `--full` prints the old document.
     - The lexical path (a body syntax failure) offers the same three views.
   - *`tests-for` on a red project* (`src/navigation_syntax.zig`, new).
     - With no typed program, `tests-for` builds a call graph from the merged
       syntax. Each `call` node belongs to the declaration whose source range
       contains it, found by binary search.
     - A call resolves by name through the calling module's own declarations and
       its import aliases (the `interfaces.Index` units), following re-exports:
       `alias.f`, `alias.Domain.f`, `pkg.mod.f`, `Domain.f` and `f`.
     - Test discovery uses the checked rule.
     - The answer is the checked answer's three lines plus a `basis: syntax (…)`
       line, with exit 0; the diagnostics still go to stderr.
     - A project whose syntax does not parse gets a one-line explanation and
       exit 1.
   - *Call-site spelling* (`navigation.resolveSpelling`). `module.name` resolves
     to `module::name` by trying every split into a module path and a member path,
     because both module names and domain members can contain dots. One match is
     the answer; several are reported as ambiguous and never silently resolved.
     `context --symbol`, `tests-for` and `index-project --symbol` share the rule.
   - `src/main.zig` adds the `index-project` flags (both `--flag=value` and
     `--flag value`), streams stdout, adds `tests-for`'s red path and updates the
     help text.
   - `src/context.zig` resolves its selector between the two passes and keeps
     only the rows it needs.
   - `scripts/navigate.py`, `scripts/store.py`, `scripts/profile_large_project.py`
     and `tests/list_declarations.py` now pass `--full`.
4. `804b706b`: a comment fix only.

## Tests

- `NAVIGATION-SCALE-1` (`src/navigation_scale_test.zig`) is the ratchet. It runs
  in well under a second and checks three things:
  - `Limits{}` carries no cap.
  - A checked project whose tables exceed a small cap the test passes (601
    symbols, 600 rows) is refused only under that cap, while the command path
    (`--full` through the visitor) publishes every symbol and every row.
  - The syntax-failure path recovers 50,001 lexical candidates, past the old
    fixed cap of 50,000.
- Unit tests, all in `src/navigation_scale_test.zig` unless noted:
  - `NAVIGATION-SUMMARY-1`.
  - `NAVIGATION-FULL-1`: the streamed `--full` equals `navigation.render` byte for byte.
  - `NAVIGATION-SELECT-1`: module, dotted symbol with its owned members, kind,
    missing, unknown module and ambiguous.
  - `NAVIGATION-SPELLING-1`: a unit test, plus a `context` case in `context_test.zig`.
  - `TESTS-FOR-SYNTAX-1`: the syntax answer equals the checked answer plus the
    basis line, for alias, domain-member and `@test` cases.
  - `NOMINAL-LAYOUT-WORK-1` in `src/nominal_layouts_test.zig`; it checks the
    derived limit and that 3200 ordinary 16-field records pass the old minimum
    and stay under the new limit.
  - `PROJ-BUDGET-MESSAGE-1` in `src/project_test.zig`.
- CLI tests (`test/integration.zig`):
  - `tests-for`: a type error, dotted spellings, a parse failure.
  - `index-project`: the summary, `--full`, `--symbol NAME`, a missing module
    (exit 2), and `--full --module` and an unknown `--kind` (usage errors).

## Measurements

**Setup.**
- Tiers: `experiments/build-loop-20260924/gen_scale.py` (mylang only), `t50k 120 38`, `t200k 480 38` and `t500k 1200 38`.
- Tier sizes: 60,645, 242,445 and 606,045 lines; 1.7, 6.9 and 17.4 MB of source.
- The 500k tier is over the 16 MiB default byte budget, so it carries
  `mylang.json` = `{"version": 1, "budgets": {"max_total_bytes": 67108864}}`. The
  "before" compiler reads the same file.
- Compilers: before is `/home/epentland/ai/trials/devspeed-20260923-private/compilers/integration-183251a9/bin/mylang` (ReleaseFast; `183251a9` differs from `fd36abc2` only in docs). After is a ReleaseFast build of `e7e92a08`
  (`zig build -Doptimize=ReleaseFast -Dcompiler-only=true`).
- Every run uses `--no-cache` under `taskset -c 0-11` and `/usr/bin/time`. The tables report the minimum wall time of 3 runs, the maximum peak RSS, and the stdout bytes.
- Load average (1 min) at the end of each run: 6.4 (before, green), 4.8 (after,
  green), 6.4 (before, red), 4.5 (after, red; the 200k red row is a re-run at
  load 4.5, because the first pass ran at load 7 and was up to 0.7 s slower
  across the board, `check` included).
- Harness: `measure.py` (lane scratch area) runs each query from the tier
  directory, for example `mylang index-project main.my --module=m060 --no-cache`.
- *Red* is the tier with `+ "red"` appended to one `return` in `m001` (an `E_TYPE`).
- Cold runs are the fair memory comparison: a warm `check` replays a stored
  verdict (0.02 s, 7 MB) and does none of the work the navigation commands do.

**Green:** time · peak RSS · stdout (sizes in decimal KB/MB).

| Tier | Query | Before (`fd36abc2`) | After |
| --- | --- | --- | --- |
| 50k | `check` (reference) | 0.36 s · 310 MB | 0.43 s · 311 MB |
| 50k | `index-project` | 0.52 s · 425 MB · **36 MB** | 0.45 s · 317 MB · **15 KB** (summary) |
| 50k | `index-project --full` | — | 0.55 s · 317 MB · 36 MB |
| 50k | `index-project --module=m060` | — | 0.45 s · 318 MB · 308 KB |
| 50k | `context --symbol=m060::f060_00` | 0.41 s · 396 MB · 7.4 KB | 0.39 s · 321 MB · 7.4 KB |
| 50k | `context --symbol=m060.f060_00` | exit 2, `missing` | 0.39 s · 321 MB · 7.4 KB |
| 50k | `tests-for m060::f060_00` | 0.35 s · 312 MB · 1.0 KB | 0.37 s · 312 MB · 1.0 KB |
| 50k | `tests-for m060.f060_00` | exit 2 | 0.34 s · 312 MB · 1.0 KB |
| 50k | `list-interfaces` | 0.44 s · 281 MB · 493 KB | 0.30 s · 282 MB · 493 KB |
| 200k | `check` (reference) | 1.54 s · 1224 MB | 1.40 s · 1224 MB |
| 200k | `index-project` | **exit 2, host failure: NavigationLimit** | 1.46 s · 1250 MB · **58 KB** (summary) |
| 200k | `index-project --full` | — | 1.87 s · 1250 MB · 145 MB |
| 200k | `index-project --module=m060` | — | 1.64 s · 1251 MB · 308 KB |
| 200k | `context --symbol=m060::f060_00` | **exit 2, host failure: InternalError** (a mapped `NavigationLimit`) | 2.02 s · 1269 MB · 8.0 KB |
| 200k | `context --symbol=m060.f060_00` | exit 2, host failure | 1.66 s · 1271 MB · 8.0 KB |
| 200k | `tests-for m060::f060_00` | 1.55 s · 1234 MB · 6.6 KB | 1.51 s · 1235 MB · 6.6 KB |
| 200k | `tests-for m060.f060_00` | exit 2 | 1.51 s · 1235 MB · 6.6 KB |
| 200k | `list-interfaces` | **4.36 s** · 1110 MB · 1.9 MB | **1.26 s** · 1114 MB · 1.9 MB |
| 500k | `check` (reference) | **exit 1, `E_GENERIC_LIMIT`** | 3.50 s · 3038 MB |
| 500k | `index-project` | exit 2, `E_GENERIC_LIMIT` | 4.12 s · 3108 MB · **144 KB** (summary) |
| 500k | `index-project --full` | — | 4.58 s · 3108 MB · 364 MB |
| 500k | `index-project --module=m060` | — | 3.93 s · 3109 MB · 308 KB |
| 500k | `context --symbol=m060::f060_00` | exit 2, `E_GENERIC_LIMIT` | 4.17 s · 3173 MB · 7.9 KB |
| 500k | `context --symbol=m060.f060_00` | exit 2, `E_GENERIC_LIMIT` | 4.12 s · 3176 MB · 7.9 KB |
| 500k | `tests-for m060::f060_00` | exit 1, `E_GENERIC_LIMIT` | 4.22 s · 3087 MB · 18 KB |
| 500k | `tests-for m060.f060_00` | exit 1 | 4.23 s · 3087 MB · 18 KB |
| 500k | `list-interfaces` | 1.19 s · 1752 MB · 6.2 MB (bodies never checked: `tests(unavailable)`) | 3.53 s · 2790 MB · 4.8 MB (checked, with the tests column) |

Memory against `check` (after): at 50k, 200k and 500k respectively,
- `index-project` (every view): +2.1 %, +2.1 % and +2.3 %;
- `context`: +3.3 %, +3.8 % and +4.5 %;
- `tests-for`: +0.5 %, +0.9 % and +1.6 %.

Before this lane, `index-project` at 50k used +37 % and `context` +28 %.

**Red** (type error in `m001`): time · peak RSS · stdout.

| Tier | Query | Before | After |
| --- | --- | --- | --- |
| 50k | `check` (reference) | 0.30 s · 306 MB, exit 1 | 0.30 s · 307 MB, exit 1 |
| 50k | `index-project` | 0.31 s · 314 MB · 3.3 MB | 0.32 s · 308 MB · 12 KB (summary; `--full` 3.3 MB) |
| 50k | `context --symbol=m060.f060_00` | exit 2, `missing` | 0.32 s · 310 MB · 1.8 KB (partial answer) |
| 50k | `tests-for m060::f060_00` | **exit 1, no answer** | 0.34 s · 309 MB · 1.1 KB, `basis: syntax` |
| 200k | `check` (reference) | 1.23 s · 1208 MB | 1.21 s · 1209 MB |
| 200k | `index-project` | 1.23 s · 1235 MB · 13 MB | 1.22 s · 1214 MB · 44 KB (`--full` 1.25 s · 13 MB) |
| 200k | `context --symbol=m060.f060_00` | exit 2, `missing` | 1.25 s · 1221 MB · 1.8 KB |
| 200k | `tests-for m060::f060_00` | **exit 1, no answer** | 1.29 s · 1222 MB · 6.7 KB, `basis: syntax` |
| 200k | `list-interfaces` | 1.02 s · 1082 MB | 1.00 s · 1082 MB |
| 500k | `check` (reference) | exit 1 on `E_GENERIC_LIMIT` (never reaches the type error) | 3.84 s · 2999 MB, exit 1 on the `E_TYPE` |
| 500k | `index-project` | exit 2, `E_GENERIC_LIMIT` | 3.60 s · 3011 MB · 109 KB (`--full` 33 MB) |
| 500k | `context --symbol=m060.f060_00` | exit 2 | 3.20 s · 3029 MB · 1.8 KB |
| 500k | `tests-for m060::f060_00` | exit 1 | 3.07 s · 3054 MB · 18 KB, `basis: syntax` |

On a red project the `tests-for` answer is identical to the green checked answer
apart from the `basis` line (verified at 50k by `diff`).

**Deterministic counters** (after, green), against the old fixed caps of 50,000
symbols and 250,000 references:

| Tier | Modules | Symbols | References | Summary bytes | `--full` bytes |
| --- | --- | --- | --- | --- | --- |
| 50k | 121 | 23,283 | 182,561 | 15,209 | 36,231,941 |
| 200k | 481 | 93,123 | 730,121 | 58,052 | 144,924,221 |
| 500k | 1201 | 232,803 | 1,825,241 | 144,137 | 364,045,579 |

The summary grows with the module count (about 120 bytes per module); `--full`
grows with every reference (about 200 bytes per row).

## Known gaps and follow-ups

- **The 16 MiB default project byte budget** (`PROJ-6`) still refuses the 500k tier
  (17.4 MB) until `mylang.json` raises it. The refusal is now actionable, but the
  default is a language-level policy that belongs to whoever owns `PROJ-6`. `check`
  at 500k peaks at 3.0 GB against the 8 GiB host ceiling, so a default near 32 MiB
  would still fail cleanly before memory runs out.
- `tests-for` on a project whose **syntax** does not parse still gives no answer
  (it says so, exit 1). A lexical call graph, or the last successful check's stored
  per-function callees (`semantic_summary`), could answer there; I chose the merged
  syntax because it exists for every type error and resolves exactly as the
  checker does.
- On a red project `context` publishes no `tests` section. `navigation_syntax.build`
  could supply one with `basis: syntax`; it is a small follow-up.
- `list-interfaces` output is not bounded (4.8 MB at 500k): it lists every public
  declaration by design. A `--module` filter would mirror `index-project`.
- `index-project --module` is about 308 KB for one 500-line module in this shape,
  because it carries every local and every edge of the module; `--kind=function`
  combined with `--module` is the lighter query.
- Timings were taken on a shared machine (load 4.5–6.7). Memory, output size and
  the counters are deterministic; wall times should be re-measured on a quiet
  machine.

## For the integrator

- **Default output change:** a bare `mylang index-project` now prints
  `navigation-summary-v1`; `navigation-v1` needs `--full`. Every in-tree consumer
  is updated (`scripts/navigate.py`, `scripts/store.py`,
  `scripts/profile_large_project.py`, `tests/list_declarations.py`). The
  `python-free-tooling` lane may port some of these scripts to Zig; the ports must
  pass `--full`. `tests/timings.py` compares two `index-project` runs with each
  other, so it is unaffected.
- **API changes:**
  - `navigation.collect(allocator, compilation, identity, Collect)`: the fourth
    argument is `.{ .limits, .edges }` (it was `Limits`), and it returns
    `VisitError!Facts`.
  - `Facts` gained `symbol_storage`.
  - `tests_index.buildNamed` is new; `build` delegates to it.
- **Conflict risk:**
  - `src/main.zig`: the argument parser (`IndexOptions`, `separateValue`),
    `testsFor`, `checkFailure`, `partialNavigation`/`indexProject`, and the help
    text.
  - `SPEC.md`: 8 new bullets next to `NAVIGATION-FACTS-3`, `TESTS-FOR-1`, `PROJ-6`
    and `NOMINAL-LAYOUT-1`.
  - `src/features.json`: 2 new slugs.
  - `src/interfaces.zig`: `renderFunctionLine` and its helpers.
  - `src/nominal_layouts.zig` and `src/project.zig`: one budget each.
- **Gate at `804b706b`:**
  - `zig build test --summary all --maxrss 8000000000`: 92/92 steps; the 12 root
    shards give 1678 unit tests, the 6 CLI shards 194.
  - `zig build test-qbe --summary all`: 51/51 steps, 390/390 tests.
  - `zig build test-qbe-build --summary all`: 33/33 steps.
  - `zig build fmt-check`: clean.
  - `zig-out/bin/mylang test tests/lang`: 569 passed across 106 programs.
