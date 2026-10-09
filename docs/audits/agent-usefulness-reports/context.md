# C1 — `mylang context`: one bounded, source-pinned answer about one declaration

Package: **C1 — Answer a focused change-context question** (plan
[`agent-usefulness-implementation-plan-2026-09-20.md`](../agent-usefulness-implementation-plan-2026-09-20.md)
§C1). Acceptance this report answers: useful answers on both real applications;
exact budget adherence; deterministic ordering; ambiguous and missing selectors
handled; partial-source facts labeled; private helper edits invalidate relevant
answers; source changes during collection reject; existing navigation/test
semantics unchanged.

## Status

**Done, verified against the installed binary.** `./zigw build` is green
(`88 check(s) passed`, installs), the seven pre-written `CONTEXT-*` spec bullets
plus one new `CONTEXT-CONFIRM-1` bullet each carry a `// spec:` test, and the
nine C1 CLI tests in `test/integration.zig` pass.

The implementation arrived mid-flight and compiled but did not satisfy its own
spec in four ways, all found by building the tests first and all fixed here:

| Gap found | Evidence before the fix | Fix |
| --- | --- | --- |
| `--symbol NAME` / `--at POS` (the spelling both SPEC bullets, the doc page and the pre-written CLI tests use) did not parse | `mylang context main.my --symbol 'model::validate'` → exit 2 + usage; only `--symbol=` worked | `parseArgs` walks by index and `contextSeparateValue` consumes the next argument for `--symbol`, `--at`, `--context-bytes`, `--against`; the `=` forms are unchanged |
| `--at` resolved only the declaration's **name token**: a position inside a healthy body reported `missing` | `--at model.my:9:12` (inside `validate`) → `status=missing, reason=no declaration or diagnostic covers that position` | a declaration's selection span is the span its published snippet already covers (name → body end); a nested name (parameter, local, field) still wins as the innermost span; a diagnostic is selected only when no declaration covers the position |
| The budget ladder's last rung published an envelope with **no `sections`, no `omissions` and no `continuation`** when the declaration body alone busted the budget | synthetic 200-statement function at `--context-bytes=1200` → 578 bytes, `sections=[]`, `omissions=[]`, no continuation | the ladder gained an identity rung that names every omitted section and keeps the continuation query; only the stale rejection stays bare |
| `CONTEXT-STALE-1`'s rejection path was unreachable: `staleChanged` compared two receipts of the *same* in-memory project, and `receipt.inputs` hashes the digest recorded at load, so the two were always equal | a project whose `module.src.bytes` were swapped under the answer came back `ok` | the check re-derives each digest from the bytes the project holds **and** re-reads every input through the provider the project was loaded from (`Options.sources`); a read failure is `error.RecheckUnavailable`, its own outcome |

## Files changed

- `src/context.zig` — `Options.sources`; `sourcesChanged` + `hashesTo`;
  `coverageEnd` / `bodyEnd` and the `--at`/diagnostic span use; the `Detail`
  depth enum (`full` / `identity` / `bare`), `appendIdentityOmissions`, and the
  `key_contract` constant.
- `src/context_test.zig` — **new coverage, 8 spec-tagged tests** over in-memory
  project fixtures: envelope, selector resolution, `--at`, section order and
  labels, budget/omissions/continuation, stale rejection, partial answers.
- `src/main.zig` — the space-separated context flag spellings; the provider
  wired into `contextOptions` / `contextCommand` / `contextPartial` /
  `partialNavigation`; `error.RecheckUnavailable` and `error.BaselineUnreadable`
  mapped to exit 2 with a message; `receiptStages` extracted out of
  `listModulesWithCache` (cognitive complexity 26 → within 25) and
  `zig fmt`. The `invoke` dispatch line is untouched.
- `test/integration.zig` — C1 region only: `writeContextProject` now returns
  `![:0]u8` (it returned a sentinel allocation as a plain slice, so every
  `testing.allocator.free(path)` aborted the test process with a mismatched-size
  panic); one new test covering the unreadable-baseline path in both flag
  spellings.
- `SPEC.md` — one new bullet, `CONTEXT-CONFIRM-1`, appended at the
  `WS1-CONTEXT-SPEC-APPEND` marker. No existing bullet was edited or duplicated.
- `docs/tooling/agent-context.md` — a `## Source confirmation` section and the
  matching exit-status row. The page already existed in the base commit and
  already passed `doc-coverage`; the selector tables and examples are the ones
  the fixed parser now honours.
- `docs/audits/agent-usefulness-reports/context.md` — this report.

## Commands run, and what they said

```
$ python3 scripts/focused_test.py units context
selected: 33 test(s)
result: PASS - 33 passed, 0 failed, 0 skipped

$ python3 scripts/focused_test.py cli context
selected: 9 test(s)
result: PASS - 9 passed, 0 failed, 0 skipped

$ ./zigw build
guardian: run-all: 88 check(s) passed — diff-scoped vs b8f6ec3f…, 46 file(s) in scope
zigw build exit=0

$ ../guardian-zig/zig-out/bin/guardian-check error-path-test .
guardian: error-path-test: every error path added vs HEAD is named by a test
$ ../guardian-zig/zig-out/bin/guardian-check spec .
guardian: spec coverage 604/604 behaviors covered
$ ../guardian-zig/zig-out/bin/guardian-check formatting .
guardian: formatting: every source file matches zig fmt
$ ../guardian-zig/zig-out/bin/guardian-check repeated-string-literal .
guardian: repeated-string-literal: no repeated literals or duplicate consts
$ ../guardian-zig/zig-out/bin/guardian-check cognitive-complexity .
guardian: all functions within complexity 25
$ ../guardian-zig/zig-out/bin/guardian-check change-classification .
guardian: change-classification: OK vs HEAD (1970 behavioral, 708 test line(s) added)

$ ./zig-out/bin/mylang doc-coverage .
doc-coverage: 166 documented features (109 language, 57 tooling) across 48 pages
doc-coverage: 0 failures
```

`zig fmt` was run on every file this package touched. Every acceptance number
below is from `zig-out/bin/mylang` **installed by the green `./zigw build`**
(mtime 2026-09-20 17:57), not from a staged copy.

## Acceptance results

### 1. Useful, correct answers on two real applications

```
$ mylang context experiments/sexpr-port/main.my --symbol 'sexpr.parser::parse'
  status=ok analysis=checked bytes=3118 sections=declaration,contract,types,dependencies,tests
  signature: parse(src: bytes) -> Result[list[ast.Node], ParseError]
  contract: effects [managed_allocation], mutates [], return_origin fresh, declared_effects null
  dependencies: out sexpr.parser::parse_with_depth_cap, out sexpr.parser::max_parse_depth,
                in main::main

$ mylang context src/schematic/guest/main.my --symbol 'schematic::build'
  status=ok analysis=checked bytes=7466 sections=declaration,contract,types,dependencies,tests
  signature: build(host: Host, nodes: list[sexpr.Node], pinout: list[sexpr.Node],
                   interface: list[sexpr.Node]) -> Result[Schematic, int] effects(host, managed_allocation)
  contract: declared_effects [host, managed_allocation] = effects, return_origin unknown
  types: schematic::Schematic
  dependencies: 7 outgoing calls + main::main incoming
```

Both answers agree with the sources (`parse` delegates to `parse_with_depth_cap`
and `max_parse_depth`; `build` calls the seven validators/collectors named in
`schematic.my`) and with `index-project`'s own tables. Wall time 0.54 s on
sexpr-port (7 modules, 503 symbols) and 0.32 s on the schematic guest
(14 modules, 815 symbols).

### 2. The serialized response never exceeds `--context-bytes`

14 `(project, budget)` pairs over the two real applications, budgets
1024/1500/2048/3000/4096/8192/16384, asserting both `stdout_bytes <= budget` and
`emitted_bytes == stdout_bytes` (JSON escaping and metadata included):

```
budget failures: 0
sexpr.parser::parse budget=1024  stdout_bytes=863   emitted=863   within=True
sexpr.parser::parse budget=2048  stdout_bytes=1942  emitted=1942  within=True
sexpr.parser::parse budget=8192  stdout_bytes=3118  emitted=3118  within=True
schematic::build    budget=1024  stdout_bytes=907   emitted=907   within=True
schematic::build    budget=4096  stdout_bytes=3926  emitted=3926  within=True
schematic::build    budget=8192  stdout_bytes=7466  emitted=7466  within=True
```

Trimming behaves as the spec requires: at `schematic::build --context-bytes=4096`
the answer keeps the declaration, the whole contract and the type, and trims the
lowest-priority section with a per-section count —
`omissions: [source.inputs, dependencies records_omitted=7]` plus a
`continuation` naming `--context-bytes=8192`. At the documented minimum the
identity rung still answers (907 bytes) and still names what it left out. A
budget that cannot carry even the identity is `error.BudgetTooSmall` (an
oversized selector at `--context-bytes=1024`, unit-tested).

### 3. Deterministic ordering

```
determinism sexpr.parser::parse  budget=1024  identical=True sha256=fb80d52d25099340
determinism sexpr.parser::parse  budget=4096  identical=True sha256=d2428a7af0f8db21
determinism schematic::build     budget=4096  identical=True sha256=dfe052ffc718cc42
```

The same query twice is byte-identical at every budget tested.

### 4. Ambiguous and missing selectors are reported, not resolved

```
$ mylang context src/schematic/guest/main.my --symbol build
  exit=2 status=ambiguous candidates=[layout::build, layout_graph::build,
                                       layout_routes::build, schematic::build]
  reason=several declarations carry that unqualified name; use a module-qualified name
$ mylang context experiments/sexpr-port/main.my --symbol 'sexpr.parser::no_such_function'
  exit=2 status=missing  reason=no declaration in this project has that qualified name
```

`--symbol build` is not near-matched to `schematic::build`. Usage errors are
exit 2 with the usage text and empty stdout: no selector, both selectors,
`--context-bytes=1023`, `--format=xml`.

### 5. An incomplete project still answers, and labels what it could not resolve

Real copy of sexpr-port with one broken body (`sexpr/parser.my` returns `True`
where `Result[…]` is required):

```
$ mylang context .tmp/partial-port/main.my --symbol 'sexpr.parser::parse'
  exit=0 status=partial
  analysis: {status: declaration-only, reason: bodies did not check; declarations and diagnostics only}
  declaration: [declaration sexpr.parser::parse, diagnostic E_TYPE "expected Result[…], found bool"]
  contract: signature kept, analysis declaration-only, effects/mutates/return_origin/mutation_writes null
  dependencies: []   tests: []        (the healthy answer has 3 dependencies)
```

The same project with a body that does not parse (`return +`) takes the
lexical-only path: `status=partial`, `analysis.status=lexical-only`, reason
`body syntax failed; only lexical top-level candidates were recovered`, every
section empty, snapshot identity still published.

### 6. A source change during collection rejects rather than mixing versions

Deterministic end-to-end proof. A 48-module / 12 000-function fixture
(`.tmp/big-port`) makes the load→assemble window seconds wide; the command is
started in the background and one already-loaded module is edited (or removed)
0.8 s later:

```
edited-source exit=2 envelope=status=stale sections=0 omissions=0
  reason='the source changed while this answer was being assembled; no facts are published'
unreadable    exit=2 stdout_bytes=0
  stderr='context: cannot re-read every source to confirm the answer'
```

The library-level proof is deterministic and lives in the test suite: a provider
that serves the fixture during `Project.load` and the edited body during the
answer's confirmation pass produces `status=stale` with empty sections and
omissions; a provider that can no longer answer for one input produces
`error.RecheckUnavailable`; a project whose recorded bytes were exchanged in
place is rejected from the bytes it holds.

### 7. Existing `index-project` / `tests-for` / `list-interfaces` semantics unchanged

The files that implement them are untouched: `git diff --stat HEAD --
src/navigation.zig src/interfaces.zig src/tests_index.zig src/project.zig
src/project_compile.zig src/api_diff.zig src/source_receipt.zig` prints nothing.
Behaviourally, against the `mylang-baseline-20260920` binary:

```
src/schematic/guest/main.my  index-project baseline/current:
  checked=True symbols=815 refs=6265 ids_sha=793ec82cd5268fc2 (both)
  list-interfaces: byte-identical (78 lines, 51 exports)
cli list-interfaces  2 passed; cli tests-for  1 passed; cli api-diff  2 passed
```

sexpr-port cannot be compared with that baseline binary at all — it reports
`checked=False symbols=170 refs=0` there, because the working tree moved on for
other packages since the baseline was cut; the installed binary reports
`checked=True symbols=503 references=2341` and `list-interfaces` lists the same
42 exported functions `index-project` calls exported. `main.zig`'s only
behaviour change outside `context` is the extracted `receiptStages` helper,
which is byte-for-byte the block it replaced.

## Spec tags

| Tag | Test |
| --- | --- |
| `CONTEXT-ENVELOPE-1` | `context answers one declaration with a single agent-context-v1 envelope` |
| `CONTEXT-SELECT-1` | `context selects the qualified name and reports ambiguity and absence` |
| `CONTEXT-AT-1` | `context resolves a position to the innermost declaration or its diagnostic` |
| `CONTEXT-SECTIONS-1` | `context publishes its fixed section order with labeled contract and test facts` |
| `CONTEXT-BUDGET-1` | `context never exceeds its byte budget and reports every omitted section` |
| `CONTEXT-STALE-1` | `context rejects an answer when a source changes while it is assembled` |
| `CONTEXT-CONFIRM-1` | same test (the confirmation pass and the unreadable-source outcome) |
| `CONTEXT-PARTIAL-1` | `context answers an incomplete project and never reuses checked edges` |

The `--at` test covers a body position (the enclosing declaration), a parameter
name (innermost `local:box@…`), a field name, a diagnostic-only position
(`W_UNUSED_IMPORT` on an import line) and a declaration whose snippet was cut at
the 16 KiB excerpt limit. The `CONTEXT-SELECT-1` test also asserts the
compile-time half of "exactly one of `--symbol` and `--at`": `Options.selector`
has no default and the union has exactly those two arms; the CLI half is the
usage tests.

## Limits not closed

1. **Re-checking is per invocation.** Every `context` run loads, indexes, checks
   and re-reads the project's sources once more for confirmation. On the two real
   applications that is 0.3–0.55 s; on the 48-module/12 000-function synthetic
   fixture it is 4.5 s. Reusing a checked verdict across a session is what the
   plan defers to a later measurement, and nothing here does it.
2. **The confirmation pass costs one extra read of every module** per answer.
   Measured inside the totals above; not separately instrumented.
3. **A file that changes and changes back between the load and the confirmation
   read is invisible**, and an edit that lands after the confirmation read is
   simply the next invocation's problem. The guarantee is "the answer matches the
   bytes at confirmation time or it is rejected", not a lock on the files.
4. **The budget ladder re-assembles the document** up to nine times plus a binary
   search on one rung. It is correct and bounded, but on a wide answer at a tight
   budget it does more work than a single-pass renderer would; not measured
   separately.
5. **`--at` inside a declaration whose body exceeds 16 KiB** resolves through the
   merged syntax rather than the snippet; that fallback is covered by a unit test
   with a 1200-statement function, but no project in the tree has one, so it has
   no real-application evidence.
6. **`test/integration.zig`'s other commands' cases were left alone**; the
   pre-existing `writeContextProject` sentinel bug happened to crash only the C1
   tests, and only the C1 region of that file is this package's.
