# Language wave 1 cleanup: coordinator plus six workers (2026-10-15)

Prepared 15 October 2026 after the review of
[language wave 1](language-wave1-10-agent-plan-2026-10-14.md). Wave 1 passed its
complete verification and rejects every removed form with a `mylang fix`
rewrite, but the review found problems the gate does not see. This run fixes
them, closes acceptance criterion W2 with a compiler-backed audit, and removes
stale prose and process records from the product. It is sized for about half a
day of six workers.

Out of scope: retiring the fix machinery and the retained typing paths for
removed forms (about 3,700 front-end lines, review item 5). That waits for its
own decision. Wave 2, the tooling proposals and the ownership program are also
out of scope.

## Base and constraints

`C0` is local `main` once it contains language wave 1 and the caching
follow-up with a passing complete verification; the merge is prepared on
`claude/main-merge-20261015`. If `main` does not contain both, or the merge's
complete verification has not passed, stop and ask the user.

- Source `~/.config/mylang/dev-env.sh` in each worktree. Builds and focused
  tests go through `scripts/build-slot.sh build`; `scripts/verify_cache.py`
  owns its own admission.
- No timing admission, no load qualification, no measurement cohorts. The one
  number this run records is a deterministic instruction count (K1).
- No pushes, no shared-cache clearing, no edits in other sessions' worktrees.
- **Evidence budget.** Each worker writes one handoff of at most a page
  (`experiments/wave1-cleanup-20261015/KN.md`) naming its commits, the commands
  it ran and their results. The coordinator keeps one ledger,
  `experiments/wave1-cleanup-20261015/status.md`. Do not commit logs, receipts,
  archives, hash manifests or review records. There are no independent review
  commits: the coordinator reads each diff before integrating it.

## Ownership

The coordinator alone edits `build.zig`, `build_test_inputs.zig`, `CLAUDE.md`,
`guardian.toml`, `src/features.json` and the cache format versions
(`frontend_cache.zig`, `semantic_summary.zig`, `module_interface.zig`). K6 owns
`SPEC.md` and `README.md` for this run; other workers put the SPEC text they
need in their handoff and K6 applies it. Each worker adds tests in its own new
file, `test/wave1_cleanup_kN_test.zig` or `tests/lang/wave1_cleanup_kN*.my`,
registered by the coordinator.

| Worker | Owns |
| --- | --- |
| K1 | `src/collection_lower.zig` index and slice-bound guards, `src/negative_index.zig`, the negative-position paths in `src/core/runtime/*.c` |
| K2 | The 19 former-domain files listed under K2, `src/domain_migration.zig` messages |
| K3 | Numbered generated names in live sources and docs, except K2's files |
| K4 | Declaration rules in `src/sema_statements.zig`, the unused-capability rule (`src/sema.zig` around 1958–1976), `src/mutation_check.zig`, `src/origins.zig` |
| K5 | `scripts/audit_removed_forms.py`, its allowlist and test, the stale files listed under K5 |
| K6 | `SPEC.md`, `README.md`, `docs/` other than `docs/managed-memory.md`, the ceremony files, effect-named leftovers outside K4's files, `src/core/runtime/core_values.c` blank lines |

## Six workers

### K1: negative positions trap in the runtime, not by accident

Today the front end guards a negative index or slice bound by emitting a checked
read whose result is discarded (`src/collection_lower.zig:285` and
`checkedIndex`, 446–462); the read traps because its index is negative. Under
that guard the runtime still floors negatives to 0: `core_text_clamp`
(`src/core/runtime/core_text.c:384`), used by `myl_core_ir_str_slice_span` and
`myl_core_view_slice`; `core_search_endpoint` (879–883); and
`core_text_step_bound`. A pass that drops a discarded read restores silent
clamping.

- Replace the discarded read with an explicit trap that no optimization may
  remove: a Core trap or a call to a `noreturn` runtime bounds function,
  reporting `R_LIST_BOUNDS` or `R_TEXT_BOUNDS` with the index and length.
- Make every runtime function that receives a start, end or position trap on a
  negative value instead of flooring it. The upper bound still clamps.
- Drop "in language wave 1" from the messages (`src/core/runtime/core_rt.c:1509`
  and 1521, `src/negative_index.zig:12`): "negative indexes are not allowed".
- Tests: a computed negative (not a literal) for each path (list read, list
  slice start and end, `str` slice, `bytes` slice, search start and end) traps
  with the right code; non-negative paths are unchanged.
- Record the list-read diagnostic instruction count once, against wave 1's
  7,807,605. More than 0.5 % above it needs a reason in the handoff.

### K2: former domains keep their guarantees

Wave 1 turned 23 domains in 19 live files into public one-field records.
Records have no private fields, so a domain that confined construction behind a
private function lost that guarantee: in
`examples/interface-files/shop/money.my`, `Cents(value=-5)` gets past the
`@requires(value >= 0)` that guarded `Cents.of`, and typed JSON now decodes
`{"value": -5}` straight into the record.

The files (`C0` paths; the six marked * had a private constructor or a guard):

```text
examples/corpus/invoice/money.my            examples/named-constraints/production.my
examples/corpus/invoice/quantity.my         examples/structural-constraints.my
examples/domain-codecs/data.my *            test/core/m_recursive_values.my
examples/domains.my *                       test/core/v_domain.my *
examples/generic-arrays.my                  tests/lang/contracts.my *
examples/interface-files/shop/money.my *    tests/lang/migrated/domain_equality_case_1.my
examples/modules/shared/units.my *          tests/lang/migrated/structural_constraints_case_{5,6,8,10}.my
examples/named-constraints/fakes.my         tests/lang/rc_scalar_replacements.my
```

- Where a domain guarded construction, state the guard as a record `@invariant`
  (CONTRACT-INVARIANT-1), which every construction and field write checks:
  `Cents` gets `@invariant(self.value >= 0, "an amount is never negative")`.
  Remove bypass helpers such as `raw` when nothing else needs them.
- Confirm that typed JSON decoding constructs through the invariant, so
  `{"value": -5}` is refused. If it does not, make decoding check invariants and
  add the test. Document the wire change (a former domain is now
  `{"value": n}`, not a bare number) in `docs/` and the persisted-shapes notes.
- Clean the migration's spelling in these files: `(amount).value` and
  `(self).value` lose their parentheses; accessor functions that only return the
  field (`Cents_value`) go, and callers read `.value`; names like
  `domain_op_T_score` get ordinary names.
- `src/domain_migration.zig:49`: when other errors are present the primary
  message must still say that domains were removed, not that migration is
  deferred.

### K3: migrated code reads like code a person wrote

The wave 1 fixes introduced 616 numbered names in live sources and docs:

| Where | Pairs |
| --- | --- |
| `tests/lang` | 241 |
| `test/core` | 191 |
| `test/fixtures` | 57 |
| `bench`, `benchmarks` | 81 |
| `tests/ported`, `tests/guest` | 30 |
| `docs`, `examples` | 14 |

To list them, take the added lines of `git diff b6d989fa3 9b301cdea -- '*.my'
'*.md' ':!experiments' ':!docs/audits'` and match identifiers of the form
`[a-z][a-z_]*_[0-9]{3,}`.

- **Comprehension accumulators** (`gather_result_N` and `gather_value_N`, 207
  each). Rewrite the exact generated shape

  ```text
  mut gather_result_N: T = []
  for <header>:
      const gather_value_N: E = EXPR
      gather_result_N.append(gather_value_N)
  mut NAME = gather_result_N
  ```

  to accumulate into `NAME` directly (`mut NAME: T = []`, then
  `NAME.append(EXPR)` in the loop). Refuse, and rename by stem instead, when
  `NAME` occurs in the loop header or in `EXPR`, or is already bound in scope.
- **Lambda functions** (`lambda_fn_N`, 28): name them for what they compute,
  such as `by_length` or `score_key`.
- **Everything else** (`repeat_*_N`, `tuple_result_N`, `selection_N`,
  `gather_key_N`, and so on): drop the number, keep the stem, and make the name
  unique in its scope.
- Do this with a script that matches the generated shapes exactly. Check each
  file afterwards. A benchmark program must emit the same LLVM apart from local
  names, so recorded baselines stay valid. Rewrite `docs/managed-memory.md`
  540–551 by hand.
- Do not change the fixers themselves; they are retired separately.

### K4: declaration and capability rules

- **`const name: T` without an initializer**, with the same definite-assignment
  analysis as wave 1's `mut name: T`: assigned exactly once on every path before
  any read, otherwise an error naming the path. Then turn every declaration that
  wave 1 introduced as `mut name: T` and that is assigned exactly once per path
  into `const`. Do this on the integrated tree in R2, after K3's rewrite, so the
  two corpus passes do not conflict.
- **Unused capability parameters.** `E_UNUSED_CAPABILITY` (`src/sema.zig`,
  around 1958–1976) currently forbids a callback implementation that takes a
  `Stream` it does not need in order to match `func(Stream, int) -> int`. Exempt
  a parameter whose name starts with `_` (`_out: Stream`), and have the message
  offer that spelling as its fix.
- Fold `src/mutation_check.zig` (a 38-line pass-through) into `src/origins.zig`.
- Add a native test for a managed local (`str`, `int[]`) declared without an
  initializer that is assigned on some paths and returns early on others. It
  must show no leak and no double release under the leak checker, both by
  default and with `--experimental-zero-rc`.
- `x in d.values()` stays an error: `values()` is a list, and proposal 15
  removed `in` on lists. K6 states this in SPEC.
- `@noalloc` stays a build-time warning in this run. It becomes an error with
  the ownership default, where allocation sites stop depending on reference
  counting.

### K5: the removed-forms audit and stale files

Acceptance criterion W2 ("zero uses") contradicted W1, which needs about 450
old-syntax inputs for its rejection tests, and a lexical tool could not prove it.
The right criterion is that no source the repository treats as valid uses a
removed form, with every intentional use listed.

- **`scripts/audit_removed_forms.py`** (about 200 lines) gathers these sources:
  - every `.my` file outside `experiments/`;
  - the blocks `migrate_embedded.extract_sources` finds in Zig and Markdown;
  - Selka strings in Python files, found with the `ast` module.

  It runs the installed `mylang check` on each one in a temporary working
  directory with parallel jobs. It fails when any of the wave 1 codes appears
  outside an `expect-error` or skip marker or an allowlist entry:
  - `E_DOMAIN_REMOVED`, `E_EFFECTS_REMOVED`, `E_LAMBDA_REMOVED`;
  - `E_CONDITIONAL_EXPRESSION_REMOVED`, `E_MATCH_EXPRESSION_REMOVED`;
  - `E_COMPREHENSION_REMOVED`, `E_GENERATOR_REMOVED`, `E_TUPLE_REMOVED`;
  - `E_REPETITION_REMOVED`, `E_LIST_MEMBERSHIP_REMOVED`, `E_NEGATIVE_INDEX_REMOVED`.

  It also fails on an allowlist entry that matches nothing, and on present-tense
  prose for removed syntax in `SPEC.md`, `README.md` and `docs/` (outside
  `docs/audits`, `docs/design` and the dated history).
- **The allowlist** (`tests/removed_forms_allowlist.json`) is keyed by path, the
  source's SHA-256 and the code, each entry with a one-line reason. The starting
  set: about 23 `.my` files (preserved witnesses, `tests/fixtures/idioms`, the
  fix-migration fixtures, the velocity oracle), about 49 untagged embedded
  blocks that assert a removal, and the Python strings in
  `scripts/language_wave1_migration_test.py`.
- **Stale files:**
  - `.mylang-mut-modules/json.my` carries 20 `effects()` clauses in a tracked
    generated file the compiler skips. Regenerate it from its producer, or stop
    tracking it if nothing reads it.
  - `tests/native_cases.py` (removed domain strings and a negative index) is not
    in the gate. Delete it if nothing imports it; otherwise migrate it.
  - `tests/schemas.py:21`: migrate it.
  - `selfhost/lexer.my:608` belongs to the paused whole port and already fails
    `E_MODULE_HEADER`. Allowlist it with that reason rather than editing it.
- **Tests whose subject was removed**, at `test/integration.zig:6191-6240`
  (domain privacy): delete them. Tests that use old syntax only incidentally get
  current syntax:
  - `src/type_aliases_test.zig:88`;
  - `src/contracts_test.zig:94`;
  - `src/interfaces_test.zig:1343`.
- The audit must pass on the integrated tree in R2. The coordinator then
  registers it as a gate driver (`build.zig`, `build_test_inputs.zig`).

### K6: prose and process records

- `SPEC.md` (applying the other workers' SPEC text as well):
  - about 40 lines still describe live domain features: WIRE-4, PY-GENERIC-1,
    the domain clauses of CONTRACT-SYNTAX-1 and CONTRACT-INVARIANT-1, and lines
    near 767, 1078 and 1325. Restate these for records, or retire them with
    a dated history note.
  - Fold the round-named rules (WAVE1-CACHE-R2-1, WAVE1-CACHE-R3-1,
    WAVE1-CACHE-R4-1, WAVE1-DOC-HISTORY-1) into ordinary rules named for what
    they state.
  - Retire historical fixture bullets that describe removed clauses, such as
    FMT-CLAUSE-SPACE-1.
  - `README.md` 335–337: domain lines.
- Delete these files, which only pin wave 1's starting behaviour:
  - `src/wave1_c0_negative_captures_test.zig` (655 lines);
  - `src/core/r3_effect_fixture_before_test.zig` (502 lines).

  The `test/fix_wave1_*_test.zig` files already keep one diagnostic test per
  code. `src/tuple_retirement_before.zig` and
  `src/core/a02_public_constructors_original.my` stay until the fixes are
  retired.
- Rename the leftovers named after the effect system:
  - the `effects` axis in `src/cache_key.zig:18,28`; the coordinator bumps the
    affected cache format version;
  - the `effect_origin_passes` timing label (`src/sema.zig:1848-1852`);
  - the "transitive effect mask" comment on `declaredMasks` (`src/sema.zig:1386`);
  - "Effects may shrink" (`src/callables.zig:60`);
  - the `_ = source;` stubs at `src/core/allocation_contract.zig:42,52`.
- The triple blank line at `src/core/runtime/core_values.c:8-10`.

## Rounds

| Round | Work | Verification |
| --- | --- | --- |
| R1 | K1, K2, K3, K4 (rules, fold, test), K5 (script and allowlist), K6 | Focused tests per worker; the coordinator integrates in the order K6, K1, K2, K4, K3, K5, then runs one complete verification |
| R2 | K4's `mut` to `const` pass and K5's audit on the integrated tree; the coordinator registers the audit in the gate | One complete verification, `fmt-check`, `doctest .`, `doc-coverage .`, the audit |

If an R1 complete verification fails, fix the failures with focused tests and
carry them into R2; do not rerun R1. At the end, fast-forward `main` to the
integration commit if R2 passed and `main` has not moved.

## Done criteria

| Id | Criterion |
| --- | --- |
| K1 | Every runtime path given a negative position traps with `R_LIST_BOUNDS` or `R_TEXT_BOUNDS`; computed-negative tests pass for each path; the list-read instruction count is recorded |
| K2 | Every former domain that guarded construction has the guard as an `@invariant`; `Cents(value=-5)` and JSON `{"value": -5}` both trap with `R_INVARIANT` |
| K3 | No numbered name introduced by wave 1 remains in live sources or docs; benchmark LLVM is unchanged apart from local names |
| K4 | `const name: T` with definite assignment works; migrated single-assignment declarations are `const`; `_`-prefixed capability parameters are exempt; the managed-local test passes in both modes |
| K5 | `scripts/audit_removed_forms.py` runs in the gate and passes, and every allowlist entry has a reason |
| K6 | `SPEC.md` and `README.md` describe no domain feature as live; no rule is named after a round; no product string names wave 1; the two ceremony files are gone |
| K7 | The final commit passes complete verification, `fmt-check`, `doctest .` and `doc-coverage .` |

## Copy-and-paste instruction for the coordinator

```text
Use docs/audits/language-wave1-cleanup-plan-2026-10-15.md as the execution plan.
C0 is local main; it must contain language wave 1 and the caching follow-up
with a passing complete verification, or stop and ask the user. Run one coordinator and workers K1-K6, each in its
own worktree and branch from C0 (codex/wave1-cleanup-20261015-kN), integrating
on codex/wave1-cleanup-20261015-integration.

Keep the evidence small: one handoff of at most a page per worker and one ledger;
do not commit logs, receipts, archives, hash manifests or review records, and do
not add independent review commits. Do not take timing admission or qualify
load. Builds go through scripts/build-slot.sh after sourcing
~/.config/mylang/dev-env.sh.

Enforce the ownership table: the coordinator alone edits build.zig,
build_test_inputs.zig, CLAUDE.md, guardian.toml, src/features.json and the cache
format versions; K6 alone edits SPEC.md and README.md. Do not change the fixers
except for the domain message in K2, and do not delete the fix machinery.

Integrate in rounds R1 and R2 with one complete verification each. At the end,
fast-forward main to the integration commit if R2 passed and main has not moved.
Report each done criterion K1-K7 as passed or failed with the command and
result. Do not push, do not clear shared caches, and do not edit other sessions'
worktrees.
```
