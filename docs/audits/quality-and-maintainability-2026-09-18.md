# Code-quality and maintainability: audit and implementation guide — 18 September 2026

**Question asked:** what should be added to the language and its tooling so that programs
written in it stay high quality and cheap to maintain as they grow, taking
[guardian-zig](../../../guardian-zig/README.md) — the gate that already polices this
compiler's own Zig source — as the source of ideas; and how to balance that against the
development-speed goal in `velocity/goal.json`.

**Scope.** Guest (`.my`) code and the tools that judge it. The Zig compiler is already
gated by Guardian and is out of scope. Every claim is a source citation against the
working tree at `328502c8` plus uncommitted edits. Earlier audits are not repeated: the
[velocity audit](agent-velocity-2026-09-17.md) and the
[scorecard](agent-audit-guide-scorecard-2026-09-17.md) cover speed and Python idioms;
`velocity/backlog.json` items are referenced by id (`C-5`, `D-1`, …) and not re-proposed.

**How to use this document.** Section 1 is the audit verdict. Section 2 fixes the
policy that decides what gets built and how it behaves by default. Section 3 is the
decision table for every candidate. Sections 4 to 7 are the work packages, in order,
each with the rule, the mechanism, the files to touch, the repository gates it must
satisfy, and acceptance criteria. Section 8 says how to measure whether a rule earned its
place. Sections 9 and 10 hold the advisory, deferred and dropped items with the
condition that would revive them.

---

## 1. Verdict

The language already makes several quality properties *impossible to skip*, which is
stronger than anything a linter can do, and stronger than what Guardian achieves on Zig:

| Property | Mechanism | Guardian equivalent |
| --- | --- | --- |
| Every match is exhaustive | `E_INCOMPLETE_MATCH`; `E_WILDCARD_ARM` refuses to swallow a `Result` | none (Zig `else` is not policed) |
| Errors cannot be ignored | `Result` handling obligation, `E_RESULT_UNHANDLED`, `E_EXPLICIT_DISCARD_REQUIRED` | `catch-discipline`, `unwrap-discipline` |
| No hidden I/O, time, randomness or environment | capabilities are parameters; `effects(...)` is inferred and verified against emitted bytecode | `ban-time`, `ban-rng`, `ban-fs`, `ban-net`, `ban-env` — textual, exemptable |
| Dependency direction | `mylang.json` `import_policy`, exit 3, no inline suppression | `import-layering` |
| No import cycles | `E_IMPORT_CYCLE`, cannot be disabled | `imports` |
| Private types never leak through a public signature | `E_PRIVATE_SYMBOL` | `pub-exposes-private` |
| Shadowing, unreachable statements, writes to a dropped record copy | `E_SHADOWING`, `E_UNREACHABLE`, `E_DEAD_RECORD_WRITE` (`src/sema.zig:4661`) | Zig compiler errors |
| Every feature has a runnable documented example | `mylang doc-coverage`, `mylang doctest` | `doc-comments` (presence only) |
| An empty test selection is not green | `mylang test` exit 3 | `guardian.testRunner` |
| Unfinished code cannot ship | `E_TYPED_HOLE` blocks publication | `stub-body-ban` |

What is missing is what Guardian calls the *project-verification layer*, which
`docs/plan.md:294` reserves for "tests, mutation testing, benchmarks, and change-history
policies" and which does not exist for guest code:

1. **No lint tier with teeth.** The compiler emits two warnings (`W_UNUSED_BINDING`,
   `src/sema.zig:4669`; `W_MUTATES_MISSING`, `src/origins.zig:26`), with no deny mode,
   no suppression and no configuration. Function length, parameters, nesting, decision
   points, dead exports and duplicate bodies are measured by `report-project-quality`
   and `discover-project-duplicates`, but "threshold findings do not change exit status"
   (`docs/experiments/module-quality.md`).
2. **No test-coverage rule.** Nothing requires an exported function to be exercised by a
   test; no `tests-for` query, no spec-to-test link, no assertion check on tests.
3. **No metadata surface.** No attribute syntax, so no `@deprecated`, no lint waiver, no
   stability marker. Test discovery is by the `test_` prefix: exported tests always, and
   unexported ones only when parameter-free and `bool`-returning (`SPEC.md`
   NATIVE-TEST-1).
4. **No docstrings** (`C-5`), so exported APIs carry no machine-extractable intent.
5. **No immutability below module scope.** `mutates(...)` is the only contract and
   omitting it is advisory "for this version" (`docs/effects.md:362`).
6. **No API-evolution tooling.** `schema-project` fingerprints every export
   (`interface_sha256`), but nothing diffs two fingerprints or marks a symbol deprecated.

---

## 2. Policy: how quality and speed are balanced

These decisions apply to every work package below. Changing one of them is a separate
commit that touches nothing else, the same rule `velocity/goal.json` sets for itself.

**P1. A rule pays when the repair it prevents costs more than the friction it adds.**
For an agent, friction is a turn: every block is one more turn, and every false positive
is a turn with no payoff. The velocity loop already measures turns to green and repair
rate; a lint rule is a candidate in that loop and survives only if it lowers total
turns (section 8).

**P2. Report during development, block at commit.** Guardian's `[gate] on_build =
"report"` default. `mylang check`, `run`, `build` and `test` never refuse on a lint
finding. Blocking happens in `mylang lint --gate`, which is what a pre-commit hook and CI
run. Nothing in the inner check-run-test loop refuses to produce a binary.

**P3. The default profile is `agent`, not `strict`.** A project with no `lint` object in
`mylang.json` gets every exact correctness rule as a report and every style rule
silent. A project opts up. This keeps quality as something the tooling reports
continuously and enforces at the one moment it matters.

**P4. Only exact rules may block.** A rule is *exact* when it is computed from the
checker's resolved identities (call graph, effect sets, declaration hashes) and has no
false positives by construction. Textual heuristics (naming, literal patterns) and
style proxies (size budgets) are report or ratchet, never block, until section 8
evidence says otherwise.

**P5. Infer, then display; do not require annotation.** Where the checker already
knows a fact (mutation footprint, effects, callers), the fix for a missing annotation is
to show the inferred value in `list-interfaces`, not to make the programmer write it.
This is why promoting `W_MUTATES_MISSING` to an error is dropped (section 10).

**P6. Ratchets, not walls, on existing code.** Threshold rules record a per-declaration
ceiling that may only shrink. A new project starts at zero debt; an existing one never
breaks on adoption.

---

## 3. Decision table

| Candidate | Bucket | Reason |
| --- | --- | --- |
| `mylang lint` command, `lint` config, profiles, `L_*` codes, ratchet store | **Implement (W1)** | Infrastructure every other item needs; cheap |
| `warnings: deny` | **Implement (W1)** | The missing `-Werror`; one flag |
| Directive-comment waivers with mandatory reason | **Implement (W1)** | Needed so any block can be reviewed rather than fought |
| `untested-export` | **Implement (W2)** | Untested helpers are the most common agent defect; exact via call graph |
| `test-has-assertion`, `test-no-conditional` | **Implement (W2)** | Fake-green tests; exact; trivial |
| `dead-private` | **Implement (W2)** | Leftovers from repair loops; exact |
| `tests-for` index, `mylang test --affected` | **Implement (W2)** | Selection, not verdict; speeds the loop and feeds W3 |
| `W_UNUSED_IMPORT` | **Implement (W2)** | Only obvious warning the compiler lacks; exact |
| `change-without-test` (`--against REF`, gate only) | **Implement (W3)** | Guardian's highest-leverage rule for agents; exact via body hashes |
| `api-diff` report | **Implement (W3)** | Fingerprints exist; report-only so no friction |
| `@deprecated`, `@test` attributes | **Implement (W4)** | Remove ceremony rather than add it |
| Docstrings + `undocumented-export` (report) | **Implement (W4)** | `C-5` already scheduled; rule is the cheap follow-on |
| Error unions in stdlib + `?` conversion | **Implement (W4)** | Removes a hand-written translator per boundary |
| Re-export | **Implement (W4)** | Removes internal-layout coupling |
| Assert messages with values, record field defaults | **Implement (W4)** | Fewer lines written; fewer helpers to test |
| `dead-export` | **Advisory** | Exact but ambiguous for libraries; report |
| `function-length`, `record-size`, `file-length`, `nesting`, `decision-points`, `bool-ops` | **Advisory (ratchet opt-in)** | Style proxies; promote only with section 8 evidence |
| `naming`, `repeated-literal`, `same-type-adjacent-params` | **Advisory** | Textual; false positives cost turns |
| `duplicate-body` | **Advisory, never block** | Metz caveat; already reported by `discover-project-duplicates` |
| `output-in-library` | **Advisory** | Real but rare; report |
| Spec tags for guest projects, `spec-init` | **Deferred** | Double bookkeeping for task-driven programs; opt-in only when a project has a SPEC.md |
| `error-path-test` | **Deferred** | Wait until `untested-export` proves coverage rules change outcomes |
| Mutation testing | **Deferred** | Needs `B-1`; expensive |
| Effect-direction policy, literal bans, secrets | **Deferred** | Capabilities cover the important cases |
| `Final` locals, `@frozen`, `@must_use` | **Deferred** | Annotation ceremony; velocity audit ranks it the second largest cost |
| Promote `W_MUTATES_MISSING` to error | **Dropped** | Violates P5; show inferred footprint instead (`D-4`) |
| `L_UNNECESSARY_MUTATES` | **Dropped** | Same; an over-wide footprint is displayed, not policed |
| `line-length` rule | **Dropped** | The formatter owns layout (`D-2`) |

---

## 4. Wave 1 — the lint command and its configuration

Everything else hangs on this. Ship it with zero rules if necessary; the value is one
verdict, one config file and one baseline store.

### 4.1 `mylang lint`

**Command.** `mylang lint <entry.my|dir> [--gate] [--against REF] [--json] [--profile
NAME] [--accept]`. Loads the project once through the shared frontend (the step that
already applies `import_policy`; see `docs/tooling/import-policy.md`), runs every
enabled rule over the checked program, prints findings, exits:

| Exit | Meaning |
| --- | --- |
| 0 | Language valid; no blocking finding (reports may be present) |
| 1 | Source, type, effect or ownership error; rules not evaluated |
| 2 | Usage, configuration or host failure |
| 3 | Language valid; at least one blocking finding |

Without `--gate`, every rule runs in its configured mode but the exit is 0 unless the
profile says `on_build = "block"` (P2). With `--gate`, `block` rules exit 3, ratchets
that grew exit 3, and the run reads the whole project (never diff-scoped).

**Findings** are ordinary diagnostics with a fourth code family, `L_*`, so
`--diagnostics=json` (`diagnostic-v1`, `src/diagnostic_output.zig`) carries them with
byte ranges and related spans. Severity stays the existing two-value enum
(`src/diagnostic.zig:25`): a blocking finding is `.err`, a report is `.warning`. The
rule name appears in the message prefix (`L_UNTESTED_EXPORT: untested-export: …`) so
`mylang explain` (`D-5`) can document both.

**Files.**
- `src/main.zig:529` — add `lint` to `Command`; dispatch beside `check-policy`
  (`src/main.zig:264`, `:395`).
- New `src/lint.zig` (driver: load config, run rules, render, exit) and
  `src/lint_rules/*.zig` (one file per rule, each exposing `run(ctx) !void`). Add both
  to `guardian.toml` `orphan_files.roots` reachability by importing them from
  `src/main.zig`; add `src/lint_test.zig` to `test_reachability.roots`.
- `src/project_config.zig:61` — extend `Document` with a `lint: LintConfig` field
  (Guardian caps structs at 7 fields; `Document` has 3 today).
- `report-project-quality` and `discover-project-duplicates` stay as inspection views;
  `lint` calls `quality.analyzeWithExports` (`src/quality.zig:51`) for its call graph.

**Gates.** SPEC bullets `- [LINT-1] …` (command, exits, JSON), `- [LINT-2] …` (config
parsing and profile precedence), `- [LINT-3] …` (ratchet store) with matching
`// spec:` tests in `src/lint_test.zig` and CLI tests in `test/integration.zig` next to
the `check-policy` tests (`test/integration.zig:1904`). Feature slug `lint-command`
(`kind: "tooling"`) in `src/features.json` pointing at a new `docs/tooling/lint.md`
with a ```console example. `///` on every `pub` declaration; ≤ 6 parameters per
function, so pass a `LintContext` struct.

**Acceptance.**
- `mylang lint examples/modules/main.my` on a project with no `lint` object exits 0
  and prints nothing but a summary line.
- A source error exits 1 and evaluates no rule; a malformed `lint` object exits 2 with
  the same location reporting `mylang.json` already uses (`project_config.Failure`).
- `--json` emits one `diagnostic-v1` line per finding with `code` starting `L_`.

### 4.2 The `lint` object in `mylang.json`

```json
{
  "version": 2,
  "import_policy": "policy.json",
  "lint": {
    "profile": "agent",
    "on_build": "report",
    "warnings": "deny",
    "block":   ["untested-export"],
    "ratchet": ["function-length", "record-size"],
    "report":  ["dead-export"],
    "rules": {
      "test-coverage":   {"exempt": [{"name": "cli.usage", "reason": "exercised by the binary's own CLI tests"}]},
      "function-length": {"max": 80, "hard_max": 200, "recover_pct": 20}
    }
  }
}
```

- `profile` ∈ `agent` (default) | `strict` | `safety`, with Guardian's meaning
  (`../guardian-zig/src/config.zig:345-463`): `strict` blocks everything blockable,
  `agent` demotes style rules to report, `safety` also demotes size budgets. Per-rule
  `block`/`ratchet`/`report` lists override the profile with precedence block > report
  > ratchet, as Guardian does.
- `on_build` ∈ `report` (default) | `block`. Only `block` makes a plain `mylang lint`
  (no `--gate`) exit 3.
- `warnings` ∈ `report` (default) | `deny`. `deny` makes `W_*` diagnostics exit 1 in
  `check`, `check-project`, `build`, `run`, `run-project` and `test`. This is the one
  setting that touches the inner loop, and it is opt-in.
- Every `exempt` and `allow` entry carries a `reason`; a missing reason is a config
  error (exit 2). Strict JSON as today: unknown keys and duplicate keys reject.
- `version: 2` — bump because the document shape grows; `version: 1` documents keep
  parsing with `lint` absent.

**Files.** `src/project_config.zig` (parse), `docs/tooling/lint.md` (shape and
precedence table), `docs/tooling/import-policy.md` (note the version bump).

**Acceptance.** Profile precedence table in the doc has one CLI test per row. Config
identity participates in verdict caches exactly as `import_policy` does
(`project_config.Config.cacheIdentity`, `src/project_config.zig:109`), so changing a
rule mode invalidates a cached green.

### 4.3 Ratchets and baselines under `.mylang/lint/`

Two shapes, both copied from Guardian and both keyed on the checker's resolved
declaration identity (qualified name plus `interface_sha256`), not on message text:

- **Per-item ratchets** (`../guardian-zig/src/ratchet.zig`) for threshold rules:
  `.mylang/lint/ratchet-<rule>.txt`, one `qualified.name <ceiling>` row per offender.
  A measurement above its row fails under `--gate`; below it, the row shrinks only on
  `--accept`. Hysteresis: a row at the hard cap must fall to `cap − recover_pct%`
  before it is rewritten, so a function sitting on the line does not flicker.
- **Identity baselines** (`../guardian-zig/src/baseline.zig`) for everything else:
  `.mylang/lint/baseline-<rule>.txt`, rows `<module>|<qualified-name>`; a finding whose
  row exists is *accepted debt* and reported at lower severity; a finding without a
  row blocks under `--gate`. `deny_growth` per rule refuses new rows even on
  `--accept`.

Only `--accept` writes the directory. A diff-scoped run (4.4) never writes, prunes or
lowers anything, because from a partial view a missing violation may be an unread
declaration. `.mylang/lint/` is committed; the store is line-oriented and merge-friendly,
and `lint` refuses to run on a file with conflict markers (Guardian `merge-state`).

**Acceptance.** Adopting `lint` on `src/schematic/guest` (2186 lines, 14 modules) with
`--accept` produces a baseline and a subsequent `--gate` is green; adding one
over-threshold function then fails; shrinking an existing offender and running
`--accept` rewrites exactly its row.

### 4.4 Waivers and scoping

**Waiver syntax now.** There is no attribute syntax until W4, so a directive comment
on the line above a declaration, in the family the doc gate already parses
(`# doc: …`, `src/doctest_command.zig`):

```text
# doc: not-mylang
# lint: allow function-length reason="exhaustive opcode table, split hurts review"
def dispatch(op: Op, frame: Frame) -> Result[Frame, VmError]:
    ...
```

A waiver without `reason=` is itself a finding (`L_WAIVER_REASON`, always block).
Waivers are counted in the summary line so accepted debt stays visible. When W4 lands,
`@allow("function-length", reason="…")` replaces the comment and the comment form is
removed with `E_REMOVED_SPELLING`.

**Diff scoping.** `--against REF` classifies rules as *per-declaration* (size budgets,
naming, docstrings, test hygiene) or *whole-program* (untested-export, dead-private,
change-without-test, api-diff) and runs per-declaration rules only on declarations whose
`body_sha256` differs from `REF`. `REF` is resolved by spawning `git` for the file
contents at that revision; the compiler already spawns children for native builds, so
this adds no new capability. `--gate` ignores `--against` for per-declaration rules
(whole tree) but still needs it for the `.change`-subject rules of W3.

---

## 5. Wave 2 — tests as a gate

All four rules read the call graph `src/quality.zig` already builds
(`Analysis.functions[*].calls`, incoming counts, `reachable-from-exports` roots).
Nothing here executes guest code.

### 5.1 `untested-export` (`L_UNTESTED_EXPORT`)

**Rule.** Every exported function, and every public method of an exported `domain`,
must be the *direct* callee of at least one call site inside a discovered `test_*`
function in the same project. Transitive reachability is reported as a note on the
finding ("reached from `test_end_to_end` through `main`") but does not satisfy the rule;
a test that reaches `parse` only through `main` proves little about `parse`.

**Exempt by construction:** `main`, `test_*`, `bench_*`, `extern def`, declarations in
`input-module` generated output, and functions called from a runnable doc example
(`mylang doctest` builds every fenced block; have it emit the same call-site facts to a
sidecar the lint driver reads, so a documented example counts as a test).

**Exempt by config:** `lint.rules.test-coverage.exempt[]`, qualified names, `reason`
required.

**Mode.** Report under `agent`; block under `strict`. Guardian's version is opt-in with
forty exemptions (`../guardian-zig/guardian.toml:233`) because its reference is textual;
this one is exact, so `strict` can afford it on by default.

**Files.** `src/lint_rules/untested_export.zig`; test discovery reuses the native test
discovery in `src/native_test_command.zig` (NATIVE-TEST-1 shape rules) so `lint` and
`test` never disagree about what a test is.

**Acceptance.** On `examples/testing/main.my` the rule finds nothing. Removing
`test_square` produces one finding naming `square` with the export's span. A doctest
that calls `square` restores green. The rule costs under 50 ms on `src/schematic/guest`
beyond the check itself (`--timings=json`).

### 5.2 Test hygiene (`L_TEST_NO_ASSERTION`, `L_TEST_CONDITIONAL`, `L_TEST_EMPTY`)

Straight translations of Guardian `test-has-assertion`, `test-no-conditional`,
`test-skip-ban` (`../guardian-zig/src/cli/registry.zig:591-605`):

| Rule | Violation |
| --- | --- |
| no-assertion | A `test_*` body with no `assert` statement, whose result is `bool` returned as the literal `True` on every path, and which has no `expected` in `--cases`. |
| conditional | `if`, `while` or `match` at the top level of a test body, or more than one top-level `for`. Table-driven cases belong in `--cases`. |
| empty | An empty body, or a `--cases` skip without a `reason`. |

**Mode.** Block under every profile: these are exact, and a test that cannot fail is
worse than no test.

**Add one Zig cannot have:** `L_TEST_CAPABILITY` — a test whose signature requests
`Filesystem`, `Network`, `Clock` or `Entropy` is an integration test and must live in a
module matching `lint.rules.integration-tests.modules` (default `["*_integration",
"integration.*"]`). Report under `agent`. This is Guardian's mystery-guest rule enforced
by the type system.

### 5.3 `dead-private` (`L_DEAD_PRIVATE`)

**Rule.** A non-exported function, or a `private def` domain method, with no call site
anywhere in its module (or, for domain methods, anywhere in the project) and not named
`main`/`test_*`/`bench_*`. `report-project-quality` already prints the fact as a review
note (`src/quality.zig:145-150`); this is the same query with a code.

**Mode.** Block under `strict` and `agent` (exact; the fix is a one-line deletion that
an agent can apply from the diagnostic). `dead-export` stays advisory (section 9).

### 5.4 `tests-for` index and `mylang test --affected`

**Index.** For every declaration: the set of `test_*` functions from which it is
reachable, with direct callers distinguished. Compute it once per project load from
the same call graph and expose it three ways:

- `mylang lint --json` findings carry it as related notes.
- `mylang list-interfaces` gains a `tests` column (alongside the effects and mutation
  columns of `D-4`).
- A `tests-for <qualified-name>` subcommand answers the scorecard's "not answerable"
  query (`agent-audit-guide-scorecard-2026-09-17.md:170`) and is the first half of
  `D-3`.

**`mylang test --affected --against REF`.** Runs only tests whose reachable set
intersects the declarations whose `body_sha256` changed. A selection, never a verdict:
it prints the selected count and the tests it skipped, exits 3 when the derivation is
empty (as `--filter` does today), and `lint --gate` and CI always run the whole set.
This is Guardian's `test-filter` (`../guardian-zig/README.md`, "test-filter"), exact
rather than file-granular.

**Files.** `src/navigation.zig` (index), `src/native_test_options.zig`,
`src/native_test_command.zig`.

### 5.5 `W_UNUSED_IMPORT`

An `import` whose alias or dotted name is never referenced in the module. The import
table and the resolved reference index both exist; emit next to `W_UNUSED_BINDING`
(`src/semantic_entry.zig:133`). Subject to `warnings: deny`. Note `import_policy`
already evaluates unused imports (`docs/tooling/import-policy.md`, "including imports
whose declarations are unused"), so the warning and the policy agree on what an import
is.

---

## 6. Wave 3 — change-time rules

Both rules are `.change`-subject in Guardian's sense: they judge a diff, never the
tree's standing state, and the baseline layer must refuse to adopt them
(`../guardian-zig/src/cli/registry.zig:920-925`).

### 6.1 `change-without-test` (`L_CHANGE_WITHOUT_TEST`)

**Rule.** Every non-test function whose `body_sha256` differs between `REF` and the
working tree must satisfy one of:

1. it is the direct callee of a `test_*` whose body also changed or was added in the
   same diff;
2. it is exempt under `test-coverage.exempt`;
3. the diff adds a `# lint: allow change-without-test reason=…` above it.

Guardian counts behavioural lines against test lines
(`../guardian-zig/src/checks/change_classification.zig`); this is the same intent made
exact by the call graph and declaration hashes.

**Mode.** Evaluated only under `--gate --against REF` (commit hook and CI). Never in a
plain `lint` run, never in the inner loop (P2).

**Acceptance.** Editing a helper's body and running `lint --gate --against HEAD`
without touching a test fails with the helper's span and the list of tests that
currently call it (so the agent knows which test to extend). Extending one of those
tests turns it green.

### 6.2 `api-diff`

**Command.** `mylang api-diff <entry.my> --against REF|FILE [--json]`. Compares the
`schema-project` fingerprints of every exported declaration and classifies each change:

| Class | Examples |
| --- | --- |
| additive | new export, new optional (defaulted) parameter, new union variant on a non-exhaustively-matched type |
| compatible narrowing | fewer effects, fewer `mutates` parameters, narrower return-origin bound — the directional subset relation `--cases` providers already validate (NATIVE-TEST-5) |
| breaking | removed export, changed parameter or return type, wider effects, new required parameter, new variant on an exported union (callers' matches become incomplete) |

**Mode.** Report only in this wave. `lint.rules.api-break: "block"` becomes available
once `@deprecated` (W4) exists, because until then there is no compatible way to remove
anything. This is the "publishing-time API-break check" the 15 September plan lists as
absent (`development-velocity-implementation-plan-2026-09-15.md` §11) and needs no new
analysis.

---

## 7. Wave 4 — language surface

Each item removes lines a programmer would otherwise write and test, which is why they
are in the implement bucket despite touching the parser.

### 7.1 Attributes: `@deprecated` and `@test`

Python decorator syntax parses without new lexer state. Restrict to a fixed vocabulary
checked at parse time (`E_UNKNOWN_ATTRIBUTE`); no user-defined decorators.

```text
# doc: not-mylang
@deprecated("use parse_v2; removed after api_version 3")
def parse(text: str) -> Result[Doc, ParseError]:
    ...

@test
def square_of_three() -> bool:
    return square(3) == 9
```

- `@deprecated(reason)`: a call from outside the defining module is `W_DEPRECATED`
  (deny-able). `api-diff` treats removing a symbol deprecated in the baseline as
  *compatible*. Attributes are part of the interface fingerprint.
- `@test`: discovered by `mylang test` and by the W2 rules regardless of name or
  export. Keeps the `test_` prefix working; lets `D-1` stop special-casing it.
- `@allow(rule, reason=…)`: replaces the W1 directive comment (4.4).

Not in this wave: `@frozen`, `@must_use` (section 10).

**Gates.** Feature slug `attributes` (`kind: "language"`) with a ```mylang example in
`docs/functions.md`; SPEC bullets `- [ATTR-1]`…; formatter round-trips the line
(`src/formatter.zig`); `list-declarations` reports attributes so the index sees them.

### 7.2 Docstrings and `undocumented-export`

`C-5` delivers the syntax. Follow with `L_UNDOCUMENTED_EXPORT`: an exported function,
record, union or domain with no docstring, or one under `min_chars` (default 12, as
Guardian `doc-comments`), or one that merely restates the name. Report under `agent`,
block under `strict`. `list-interfaces` and `api-diff` show the first line.

### 7.3 Error unions in the standard library, and error conversion for `?`

The library returns `Result[T, str]` everywhere and the docs say "do not match on them"
(`docs/standard-library.md:616`). Two changes (feature-completeness **F06**):

- Each standard module gets an error `union` (`json.Error`, `path.Error`, …) carrying a
  `message` payload, so callers match on category and `api-diff` sees a new variant as
  breaking.
- `?` gains conversion: a union variant that wraps another error type converts
  implicitly (`union AppError: Json(json.Error) | Io(io.Error)`), so a module boundary
  no longer needs a hand-written `translate_*` helper per call site — the helper that
  W2 would otherwise flag as untested.

### 7.4 Re-export

`export shared.units.Distance` (imported name in an `export` directive). A package can
then present one facade module; `import_policy` denies direct imports of the
internals; `api-diff` tracks the facade, not the layout.

### 7.5 Smaller items

- **Assert messages with values**: `assert n > 0, f"n was {n}"`. Messages are string
  literals today (`docs/statements.md:76`); a failed invariant that cannot say what it
  saw costs a turn every time.
- **Record field defaults** and a functional update (`replace(cfg, retries=5)`):
  today every module writes a constructor helper to get defaults, which is exactly the
  untested helper 5.1 flags.
- `Option`/`Result` combinators (`unwrap_or` is `C-3`; add `map`, `and_then`, `ok_or`)
  and match guards (`case x if x > 0:`) — both reduce decision points honestly rather
  than by threshold tuning. Schedule with the `C-*` idiom work.

---

## 8. Measuring whether a rule earned its place

Each blocking rule is a candidate in `velocity/` and is judged on the same numbers as a
language change:

| Metric | Source | Keep the rule when |
| --- | --- | --- |
| Turns to green, task pack | `velocity/solve.py` transcripts (`V2`) | not worse than baseline by more than the tolerance in `goal.json` |
| Repair rate after first green | same | lower than baseline |
| Findings per 1000 lines on the corpus and `src/schematic/guest` | `mylang lint --json` | nonzero (a rule that never fires is dead weight) |
| False-positive rate | manual review of a 30-finding sample per rule | 0 for block rules; under 10% for report rules |
| Wall time added to `lint` | `--timings=json` | under 10% of the check itself |

Promotion path: report → ratchet → block, one step per measured iteration. Demotion is
immediate on a false positive in a block rule. Section 9's advisory rules enter the
loop the same way; none of them is promoted without a row in this table.

---

## 9. Advisory rules (ship as report; promote only with section 8 evidence)

All are measured today by `src/quality.zig` (`Options` at `src/quality.zig:15`:
`function-lines 80`, `parameters 6`, `nesting 4`, `decisions 10`, `line-bytes 100`).
Turning them into `ratchet` rules costs a mode flag under 4.3.

| Rule | Default | Note |
| --- | --- | --- |
| `function-length` | report; ratchet opt-in, `max 80`, `hard_max 200` | hysteresis applies |
| `parameters` | report; ratchet opt-in, `max 6` | capability parameters count; they are real coupling |
| `nesting-depth` | report, `max 4` | |
| `decision-points` | report, `max 10` | rename to `cognitive-complexity` once nesting-weighted like `../guardian-zig/src/checks/cognitive_complexity.zig` |
| `record-size` | report, `max 7` fields per `record`/`class` | Guardian `type-size`; the guest "data clump" |
| `file-length` | report, `max 1000` code lines | `budgets.max_file_bytes` is a parse limit, not a design signal |
| `bool-ops-per-condition` | report, `max 3` | |
| `dead-export` | report | exported, called from no other module, not `main`/test/bench; ambiguous for libraries |
| `naming` | report | PEP 8 casing plus Guardian's vague-name list (`tmp`, `data`, `info`, `obj`, `mgr`, `Helper`, `Util`, `Manager`) |
| `repeated-literal` | report | same literal three times in a module, or the same `const` value in two modules |
| `same-type-adjacent-params` | report | keyword arguments are the fix; Guardian roadmap item |
| `duplicate-body` | report, **never block** | `discover-project-duplicates` near-v3 output; Metz caveat |
| `output-in-library` | report | `output` effect in a module outside `lint.rules.output.modules`; a stray `print` in a domain module breaks `mylang test` capture |

---

## 10. Deferred and dropped

**Deferred, with the trigger that revives each:**

- **Spec tags and `spec-init` for guest projects** — when a guest project checks in a
  `SPEC.md` and asks for it. Then: `mylang.json` `"spec_file"`, `# spec: TAG` above
  `def test_…`, the matcher from `../guardian-zig/src/spec/matcher.zig`.
- **`error-path-test`** — when 5.1 shows a measurable repair-rate drop. Then: every
  added `return Err(...)` site must be observed by a reachable test's error arm.
- **Mutation testing (`mylang mutate`)** — when `B-1` lands and `test --affected` is
  in use; the per-function object cache and per-test receipts make it cheap only then.
  Operators: flip comparison, swap `and`/`or`, delete `assert`, swap `Ok`/`Err` arms,
  perturb a literal by one, drop a `mutates` write. Ratchet in `.mylang/lint/mutation.txt`.
- **Effect-direction policy and literal bans** — when a project reports a leak the
  capability system did not catch. Then: `import_policy` gains `effects` rows;
  path/URL/secret literal patterns become a report rule.
- **`Final` locals, `@frozen` records, `@must_use`** — when the velocity loop shows
  aliasing bugs that `E_DEAD_RECORD_WRITE` and the `class` reference type do not
  catch. Each is annotation ceremony (velocity audit §2, cost group 2) until then.

**Dropped, with the reason:**

- **Promoting `W_MUTATES_MISSING` to an error, and `L_UNNECESSARY_MUTATES`.** The
  checker infers the footprint; requiring it written is ceremony (P5). Do `D-4` instead:
  show the inferred `mutates` and effects in `list-interfaces`.
- **`line-length` as a lint rule.** The formatter owns layout (`D-2`); a second opinion
  only adds findings that `fmt` will erase.
- **Guest-project `pub-api-surface` snapshot** as a blocking gate. `api-diff` gives the
  same information as a classified report; a snapshot that fails on every additive
  change would cost a turn per new export.

---

## 11. Documentation drift found during the audit

Fix alongside W1 (they mislead an agent reading the docs today):

- `docs/named-constraints-proposal.md:3` says "proposed feature, not implemented";
  `src/features.json` lists `named-constraints` as implemented and `SPEC.md:173` has its
  section.
- `domain`, the language's only encapsulation mechanism, has no page under
  `docs/current-language.md`; it is reachable only via `docs/experiments/domains.md` and
  `examples/domains.my`.
- `docs/current-language.md:100` advertises value-producing `match`;
  `docs/match-expressions.md` shows only the statement form.
- No diagnostic catalogue exists for the ~204 `E_*` codes (`D-5`); W1's `L_*` codes
  should land in the same `explain` command.

---

## 12. Wave summary

| Wave | Delivers | Depends on | Blocking by default (`agent`) |
| --- | --- | --- | --- |
| 1 | `mylang lint`, `lint` config, profiles, `warnings: deny`, `L_*` in `diagnostic-v1`, ratchet/baseline store, waiver comments, diff scoping | nothing | nothing (P2/P3) |
| 2 | `untested-export`, test hygiene, `dead-private`, `tests-for`, `test --affected`, `W_UNUSED_IMPORT` | wave 1; `src/quality.zig` call graph | test hygiene, `dead-private` (under `--gate`) |
| 3 | `change-without-test`, `api-diff` | wave 2; git `--against` plumbing | `change-without-test` (under `--gate --against`) |
| 4 | `@deprecated`, `@test`, `@allow`; docstrings + `undocumented-export`; stdlib error unions + `?` conversion; re-export; assert values; record defaults | parser work; `C-5` | nothing new |
| — | Advisory rules (section 9) | wave 1 | never, until section 8 says so |

Guardian's own history argues for starting narrow: its first `test-coverage` needed
forty exemptions and is still opt-in because the reference is textual. The guest side
gets a resolved call graph, an inferred effect set and a stable declaration identity for
free, so the same rules can be exact, on by default under `strict`, keyed for baselines
without a message skeleton, and cheap enough to run on every commit. That asymmetry,
plus the discipline of never blocking the inner loop, is how quality and speed stop
being a trade-off.
