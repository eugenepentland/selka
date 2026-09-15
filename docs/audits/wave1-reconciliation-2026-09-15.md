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

## Open decisions and blockers

1. **D1 conflict (must be resolved before `bootstrap-v1` freezes).** The plan
   keeps block-scoped locals; commit `8420528` implements function-scoped locals
   with `E_UNBOUND`. The ADR records the plan's decision and the code
   disagreement; reconciling them changes the language and is not part of
   Wave 1.
2. **D2 `record` rename (must be resolved before the grammar freezes).** The ADR
   accepts `record`; the tree still uses `class`. The plan requires an
   agent-idiom comparison and a migration window before the rename is committed.
3. **W4 minimum-versus-probes tension.** The prototype's measured minimum is much
   smaller than the landed prelude. Decide whether the extra builtins stay
   (they are cheap, total, and probe-required) or are removed once the probes
   change.
4. **Wave 2 boundary work.** `edge_main_result`, `edge_option_try`,
   `edge_const_str`, `edge_const_bytes`, plus argv/`eprint`/environment
   operations, are the next plan items and are covered by the four remaining
   program-edge probes.
5. **W9 follow-ups.** `build --run` module auto-detection and the
   restricted-capability stderr mismatch need compiler changes.
6. **Not Wave 1 and still open:** list concat/repeat, the expressions group
   (conditional expression, chained comparisons, tuples, `is None`, `Option`
   equality), and incremental identity/invalidation (Wave 3).

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
