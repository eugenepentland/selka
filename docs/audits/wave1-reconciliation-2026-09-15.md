# Wave 1 reconciliation — self-hosting plan (15 September 2026)

This records the state of the self-hosting plan after Wave 1 landed. It is the
"reconciliation report" asked for by Wave 0 item 1, written against one green
commit rather than against a moving set of worktrees.

## Baseline and result

- **Baseline:** `8420528` on `main`. `zig build test --summary all` passed
  36/36 at that commit.
- **Wave 1 integration:** `wave1/integration`, branched from `8420528`, merging
  `wave1/frontend` (surface), `wave1/lambda`, `wave1/docs`, `wave1/prototype`,
  and `wave1/fixup` (migration fallout plus two semantic repairs).
- **Final gate on the integration tree:**
  - `zig build test --summary all -j8` — 39/39 steps, 942/942 tests.
  - `zig build test-qbe --summary all -j8` — 36/36 steps, 100/100 tests,
    golden parity 231 checked / 0 mismatches.
  - `zig build test-qbe-build --summary all -j8` — 22/22 steps.
  - `zig build fmt-check` — pass.
  - `python3 tests/idiom_probes.py --compiler zig-out/bin/mylang` — 57
    selected, 46 at target, 11 not yet, **zero regressions**.
  - `selfhost/prototype/{lexer,parser,bench}.my` run through the installed
    compiler.
- **Final gate after Wave 1.1:** commit `039a4a4`.
  - `zig build test --summary all` — 39/39 steps, 850/850 unit tests.
  - `zig build test-qbe --summary all` — 36/36 steps.
  - `zig build test-qbe-build --summary all` — 22/22 steps.
  - `zig build fmt-check` — pass.
  - Focused parse probe: 4,000 ordinary expressions 0.03 s, 4,000 `len`
    calls 0.05 s, with no quadratic growth.
  - Guardian feedback: `run-all: 88 check(s) passed` in the `zig build test`
    gate, with the Wave 1.1 files in the diff-scoped review set. No Guardian
    findings remained.
- **Final Wave 1.2 baseline:** commit `f232b71`.
  - `match` arms now start from the same pre-match definite-assignment state.
    Continuing arms are intersected, terminating arms contribute no
    continuation, and payload bindings stay arm-scoped.
  - Reader-facing docs teach `record`, while `class` compatibility remains.
  - The self-hosting plan now records function scope instead of block scope.
  - The three 14 September audit plans, the handoff, and the concurrency
    proposal are committed as planning inputs.
  - Final gate after Wave 1.2: `zig build test --summary all` — 39/39 steps,
    944/944 tests; `zig build test-qbe --summary all` — 36/36 steps;
    `zig build test-qbe-build --summary all` — 22/22 steps;
    `zig build fmt-check` — pass.
  - Guardian feedback: the Wave 1.1 and Wave 1.2 commits both passed the
    whole-tree commit-hook Guardian run (`run-all: 88 check(s) passed`), and
    the post-commit `zig build test` gate passed its own Guardian step. No
    Guardian findings remained.

## Simplification workstream state (W1–W9)

| Stream | State after Wave 1 | Where |
| --- | --- | --- |
| W1 `len`, shadowing, source scan | **Landed.** `len(x)` answers `int` for lists, dicts, strings, bytes and fixed arrays (concrete and generic). A declared `def len`/`def replace` shadows the prelude. The raw-source prelude scan is gone; `str`/`dict`/`bytes`/`float` register unconditionally, and a declared type of the same name still wins. | `wave1/frontend`, `wave1/fixup` |
| W2 one spelling / stale rejection | **Landed.** `E_REMOVED_SPELLING` for `.len()`, `push`, `d.contains`, `List`, the `*_cap` names, the fifteen `f64_*` spellings, `codec_encode`/`codec_decode`, `&` and `=>`, with canonical replacements. Repository fixtures/examples migrated. | `wave1/frontend`, `wave1/fixup` |
| W3 everyday collections | **Minimum met and proved.** The prototype needed and used list construction/append/index-write/iteration, dict literal/membership, string index/slice/classification/`""`.join, `int(text)` parsing, `range`, `Some`/`None`. List concat/repeat and `dict.remove` are not in the measured minimum (`pop` covers removal); they are not implemented. | `wave1/prototype` |
| W4 prelude builtins | **Measured.** `sum`/`min`/`max`/`sorted`/`abs`/`round`/`any`/`all`/`zip`/`reversed` already exist and satisfy the idiom probes, but the lexer/parser workload needed only `len`, `int`, `print`, `range`, `Some`, `None`. No speculative operation was added in Wave 1; removing the landed set would fail the probes, so it is left for a policy decision. | `wave1/prototype`, landed earlier |
| W5 program edge | **W5a lambda landed.** Expression-bodied, contextually typed, non-capturing lambdas over the existing callback value, including `sorted(xs, key=...)`. W5b (`main -> Result`), W5c (`const` bytes/str) and W5d (`?` on `Option`) are Wave 2 boundary work and remain probes. | `wave1/lambda` |
| W7 docs and examples | **Landed.** Guide/reference/performance pages reconciled, examples migrated to the canonical surface, legacy history moved out of the reader's path. | `wave1/docs`, `wave1/fixup` |
| W8 idiom harness | **Landed and honest.** The driver no longer treats `main`'s integer result as a false regression; classifier self-test added; `test-idioms` back in `zig build test`. | `wave1/docs` |
| W9 one `run` command | **Verified.** `mylang run <file.my>` auto-detects `module`/`import`/`export`; `run-project` remains the explicit alias. Two real W9 gaps are recorded: `build --run` does not auto-detect a module entry, and restricted-capability stderr differs between `run` and native execution. | `wave1/docs` |

## Wave 0 paper trail produced

- `docs/adr/D1-block-scope.md` … `docs/adr/D7-feature-delay.md`
- `docs/bootstrap-v1.md`
- `selfhost/README.md`
- `selfhost/prototype/api_report.md`
- this report

## Open decisions and blockers after Wave 1.2

1. **D1 resolved.** `docs/adr/D1-block-scope.md` now records function-scoped
   locals with sound definite assignment. `sema.zig` snapshots initialization
   around every `while`, ordinary `for`, `range`, `reversed` and `zip` loop and
   conservatively restores it on exit. Native regressions cover all five loop
   forms.
2. **D2 `record` migration started.** `record Name:` is a contextual declaration
   head, `record` remains an ordinary name outside declaration position, and
   repository examples plus standard-library sources use the new spelling.
   `class` remains accepted during the compatibility window; the structured
   replacement diagnostic and final removal are still pending.
3. **W4 prelude decision resolved.** The public prelude stays as landed. The
   compiler is not required to use every public helper.
4. **Wave 2 boundary work remains.** `Cell[T]`, `main -> Result`, argv,
   `eprint`, restricted-capability stderr parity, `build --run` module
   detection, constant `str`/`bytes`, and optional propagation are still the
   next plan items.
5. **Not Wave 1 and still open:** list concat/repeat, the expressions group
   (conditional expression, chained comparisons, tuples, `is None`, `Option`
   equality), and incremental identity/invalidation (Wave 3).
6. **Match definite assignment resolved in Wave 1.2.** Every arm starts from the
   pre-match initialization state, continuing arms are intersected, terminating
   arms contribute no continuation, and payload bindings remain arm-scoped.

## Wave 1.1 stabilization

The first green Wave 1 gate missed two release-blocking correctness paths and
three follow-up surfaces. The stabilization pass changed:

- **Loop definite assignment** in `src/sema.zig`. A name assigned only in a
  potentially zero-iteration loop body is `E_UNBOUND` after the loop instead of
  reading uninitialized native storage.
- **Lambda preservation** in project merging (`src/project_syntax.zig`),
  canonical AST copies (`src/ast_copy.zig`), and project export roots
  (`src/project_compile.zig`). A module program with a lambda checks and runs,
  and the in-memory syntax cache matches a cold parse.
- **Prelude shadowing cost** in `src/parser.zig`: top-level `def len`/`def
  replace` declarations are indexed once at parse start instead of rescanning
  the complete token stream for every call. A 4,000-call probe dropped from the
  reported quadratic path to ordinary-expression cost.
- **Private intrinsic spelling**: ordinary source now receives
  `E_INTERNAL_NAME` for `__float_sqrt`; only embedded `@stdlib/` sources may use
  it. The public `sqrt` operation remains the canonical user spelling.
- **Planning metadata**: D1, D5, `features.json`, `bootstrap-v1`, and this
  receipt now agree with the implementation.

## Notes on the migration

The surface change was invasive by design: removing the raw-source scan changed
catalog selection for every program, and canonical capability names had to
reach nominal aggregate positions. The first integration exposed 112 failing
tests and three doctest blocks; the fixup commit migrated 57 fixture, golden,
example and inline-test files, and the follow-up repaired capability resolution
in nominal expressions, restored signed `len` in generic bodies, and updated the
tests that encoded the old pre-simplification behaviour. One cache correctness bug surfaced
and was fixed here: the persisted syntax payload (`frontend_cache.zig`) did not
carry the new `Program.lambdas` field, so a cold `run` of a lambda program
passed and every warm run failed with `E_UNKNOWN_NAME`. The payload now
round-trips lambdas and the cache identity is bumped to `v2`
(`FRONTEND-CACHE-3`).
