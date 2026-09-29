# Development-speed lane: `mylang fix` and a stability contract — 23 September 2026

Lane: recommendation 4 of `docs/audits/development-speed-2026-09-23.md` §9, with the
owner's choice "fix tool, no editions". Branch `devspeed/fix-tool` from
`base/devspeed-impl-20260923` (`371dbd17`); code-complete and gated at `665f0b2f`,
then merged with `devspeed/integration` `243a7b62` on 24 September (see
[After the merge](#after-the-merge-with-devspeedintegration)).

## What changed

**Structured fixes in `diagnostic-v1`** (`DIAGNOSTIC-FIX-1`, `DIAGNOSTIC-FIX-2`).
`diagnostic.Diagnostic.provenance` gained `fix: ?Fix` (the struct stays at seven
fields; the first edit is stored inline so a one-edit fix allocates nothing).
`diagnostic_output` renders it as
`"fix": {"edits": [{"path", "bytes": {"start", "end"}, "text"}]}` with UTF-8 byte
ranges into the named original file, mapped per module through the merged
project source; a fix with any unlocatable edit is dropped whole, and a
diagnostic without a fix keeps its exact bytes. `project.Problem` carries an
optional edit for loader diagnostics. Fixes now attached:

| Code | Edit | Where |
| --- | --- | --- |
| `E_MUTATION_MARKER` missing call-site marker | insert `mut ` at the argument | `sema_calls.checkMutationMarkers` |
| `E_MUTATION_MARKER` superfluous call-site marker | delete `mut ` | same |
| `E_MUTATION_MARKER` written parameter not `mut` | insert `mut ` before each written parameter's type (not for an unattributed write, whose message lists every position) | `origins.checkMutDeclarations` |
| `E_MUTATION_MARKER` `mut` never written / on a scalar | delete the marker | `origins`, `sema.bindParameters` |
| `E_MODULE_NAME` | replace the declared name | `project.header` |
| `E_REMOVED_SPELLING` | renames (`push`, `List`, `*_cap`, `f64_sqrt/floor/ceil/trunc/abs`), `&x` in argument position → `mut x`, a declaration's `mutates(a, b)` → `mut` on `a`, `b` | `removed_names`, `lexer`, `parser`, `generic_bodies` |
| `E_EXPLICIT_DISCARD_REQUIRED` | insert `_ = ` (never for a result, which would drop its error) | `sema_statements`, `generic_bodies` |
| `E_KEYWORD_ONLY` | insert `name=` before each operand the message's paste names | `call_arguments` |
| `W_UNUSED_IMPORT` | delete the import line when it holds only that import | `sema.warnImports` |

A symbolic-template note that carries a fix is refused by `generic_cache.captureNote`
so a replay can never silently drop it.

**Every marker in one check** (`MUT-PARAM-8`). A missing or superfluous call-site
`mut` no longer ends its function's check: the checker records the diagnostic and
continues, and the check loop fails the function once its body is done. On the
unmarked Lox port one `check` now reports all 957 markers instead of 183 (one per
failing function), which is what makes `mylang fix` converge in one round.

**`mylang fix [--check] [--diagnostics=text|json] [--cache-dir=DIR] [--no-cache] ENTRY.my|DIR`**
(`FIX-COMMAND-1`, `src/fix_command.zig`). Each round runs this executable's
`check --diagnostics=json`, applies every fix whose edits collide with no chosen
edit (duplicates apply once; a colliding fix waits a round), and repeats until no
fix is published (cap 200 rounds). It prints `fixed PATH: N edits (CODES)` and a
total on stdout, then the remaining diagnostics on stderr, each once across
entries. Exit 0 = everything checks, 1 = errors remain or `--check` found a change,
2 = usage/host failure. A directory fixes every `.my` beneath it: `main` files,
then `*_test.my`, then modules not reached by an earlier entry's imports.

**`check` on library and test entries** (`CHECK-LIBRARY-1`). A module-syntax entry
without `main`, or a headerless `*_test.my`, gets the stub `main` `mylang test`
projects, appended after its last line (an overlay in `ModuleFiles`, or the unit
bytes), so diagnostics keep their offsets and lines. A headerless non-test file
still needs `main` (the existing `E_MAIN` fixture is unchanged).

**`mylang test --diagnostics=text|json`** (`NATIVE-TEST-DIAGNOSTICS-1`): one option
in `native_test_options`, forwarded by `appendPolicyFlags` and by the directory
fan-out. Nothing else in the test runner changed.

**Migration proof in the gate** (`FIX-MIGRATION-1`). `test/fixtures/fix-migration/lox/`
pins nine modules and tests of the Lox port byte for byte from `bench/lox-20260922`
(`4e48a092`), before call-site markers were required. `test/fix_cli_test.zig`
copies them to a temporary directory, requires 7 of 9 to fail `check`, runs
`mylang fix` on the directory, and requires `fix: 89 edits in 6 files`, every file
checking clean and `fix --check` reporting nothing. `CLAUDE.md` gained the rule
"Breaking changes land with their `mylang fix` migration"; `docs/tooling/fix.md`
documents the field, the command and the rule; `scripts/migrate_mut_arguments.py`'s
docstring points at `mylang fix`.

## Acceptance

The acceptance rule: on a copy of the Lox port with its call-site `mut` markers
stripped, `mylang fix <copy>/main.my` restores every marker and reports only the one
`E_MUTATION_OVERLAP` in `vm.my`; C3 in `velocity/score.py` does not drop; the full gate
is green. All three hold, first at `665f0b2f` and again on the merged head.

### Lox port

```bash
T=/home/epentland/.cache/mylang-tmp/fixlane
git archive bench/lox-20260922 benchmarks/lox/ports/mylang | tar x -C $T/unmarked
mv $T/unmarked/benchmarks/lox/ports/mylang $T/unmarked/lox
cd $T/unmarked
mylang check lox/main.my --diagnostics=json 2>&1 | grep -c '"code":"E_MUTATION_MARKER"'
mylang fix lox/main.my --cache-dir=$T/cache            # the program and every module it imports
diff lox/vm.my /home/epentland/ai/trials/devspeed-20260923-private/lox-mylang-full/vm.my
mylang fix lox --cache-dir=$T/cache                    # the directory: test files too
```

| Step | `665f0b2f` | merged head |
| --- | --- | --- |
| `check lox/main.my --diagnostics=json` | 957 `E_MUTATION_MARKER`, each carrying a `fix` | same |
| `fix lox/main.my` (cold cache) | `fix: 957 edits in 13 files over 1 round`, exit 1, 1.9 s | same, 2.1 s |
| diagnostics left | one: `vm.my:395:19: error[E_MUTATION_OVERLAP]` | same |
| against the hand-marked port (`lox-mylang-full`), non-test modules | identical except the 3-line aliasing rewrite at `vm.my:395` | same |
| `fix lox` (directory) | 67 more edits in 7 test files; each one identical to the hand-marked port | same |
| markers restored | 957 + 67 = 1,024, the count in audit §5 | same |

The directory run also reports `E_EFFECT_BOUND` (`clock`) in `driver_tests.my`. That is
the Clock problem from audit §3; the `devspeed/test-capabilities` lane owns it and is not
in `devspeed/integration`, so `mylang test driver_tests.my` rejects the file the same
way.

**The hand-marked port on the current rules.** `mylang fix --check` on a copy of
`/home/epentland/ai/trials/devspeed-20260923-private/lox-mylang-full`, for `main.my` and
for the whole directory, prints `fix: nothing to fix`: the port needs no migration on
the merged head. What is left is the 13 `driver_tests.my` `E_EFFECT_BOUND` (`clock`)
errors above; there are no warnings.

### Velocity lane C

```bash
python3 velocity/score.py --binary $T/base/bin/mylang --jobs 4 --write $T/score-base.json
python3 velocity/score.py --binary $T/final/mylang    --jobs 4 --write $T/score-final.json
```

`$T/base/bin/mylang` is the lane base `371dbd17`, built from `git archive` with `qbe`
next to it. `$T/final/mylang` is the merged head as installed. Both runs cover the same
110 probes in the same environment, and every probe builds natively.

| | base `371dbd17` | merged head |
| --- | --- | --- |
| C1 first-try fidelity | 0.313 (21/67) | 0.313 (21/67) |
| C2 strict / undeclared | 1 / 0 | 1 / 0 |
| **C3 rejections with a fix** | **0.575 (42/73)** | **0.603 (44/73)** |
| C3_text_any | 0.479 (35/73) | 0.479 (35/73) |

Two more probes' diagnostics carry a structured `fix`: `e04_generic.my`
(`E_MUTATION_MARKER`) and `e08_format_float.my` (`E_MODULE_NAME`). No probe's verdict or
primary code changed. The 23 September draft's 0.592 → 0.620 (x/71) came from runs where
no probe could build (`ToolNotFound` for `qbe`), so those numbers are not comparable with
the ones above.

## After the merge with devspeed/integration

`git merge devspeed/integration` (`243a7b62`) conflicted in eight files:

- `sema.zig` was split into `sema_*.zig` on integration. The lane's checker changes now
  live in these places:
  - `sema_calls.zig`: the call-site marker fixes, which report and keep checking.
  - `sema_statements.zig`: the `_ = ` discard fix.
  - `sema.zig`: the scalar-`mut` fix in `bindParameters`, `warnImports`, and the
    `reportedError` guard in `checkInstance`. The guard sits before a body is recorded
    in the new per-function check summary, so a body that reported a marker is never
    stored as clean.
- `Parser.arena` became `Parser.storage`.
- `removed_names.zig` gained the integration's comptime index.
- The `--help` first screen lists `mylang fix` next to integration's `mylang docs`.

`mylang docs fix` now prints `docs/tooling/fix.md` (new topic in `src/user_docs.zig`),
so a project outside the repository can read the migration guide.

The merge commit's pre-commit Guardian run was diff-scoped against the pre-merge
`git merge-base HEAD main` (`371dbd17`). Against that base it flagged a catch block in
`src/qbe_fragments.zig`, which comes from integration and is byte-identical to it. The
merge was therefore committed with `GUARDIAN_AGAINST=720fcbcf`: the merge-base once the
merge lands, and the one every later commit and `zig build` use. Those runs pass all 88
checks.

## Gate

The full gate ran twice: at `665f0b2f` on 23 September, and on the merged head
`ea06d096` on 24 September. The second run used `~/capbuild` and the gate slot, with
the load average around 8 on 20 cores.

| Step | `665f0b2f` | `ea06d096` (merged) |
| --- | --- | --- |
| `zig build test --summary all --maxrss 8000000000` | 80/80 steps; doc-coverage 0 failures, doctest 0 failed | 92/92 steps, 1,974 tests run; doc-coverage 0 failures, doctest 0 failed (989 blocks) |
| `zig build test-qbe --summary all` | 312/312 | 47/47 steps, 413/413 |
| `zig build test-qbe-build --summary all` | 31/31 steps | 29/29 steps |
| `zig build fmt-check` | clean | clean |
| `zig-out/bin/mylang test tests/lang` | 569 passed | 569 passed, 0 cached, across 106 programs |

The lane's own tests:

- `src/diagnostic_fix_test.zig`: 10 tests covering the rendering, every fix site and
  MUT-PARAM-8.
- `test/fix_cli_test.zig`: 5 CLI tests for `fix`, `--check`, the directory form,
  deduplication, library and test `check`, `test --diagnostics=json` and the
  FIX-MIGRATION-1 corpus.
- `src/docs_command.zig`: one test for `mylang docs fix`.

All of them pass on the merged head.

## Known gaps

- A headerless `*_test.my` that imports project modules still reports
  `E_MODULE_HEADER` under `check`; `mylang test` projects a `module NAME; ` prefix
  on line 1, which `check` avoids because it would shift byte offsets.
- Lexer-level `E_REMOVED_SPELLING` stops lexing at the first removed spelling in
  a file, so a file with many (`&` markers) takes one round each; the 200-round
  cap bounds it. Parser- and checker-level fixes batch per function.
- `fix` runs one child `check` per round; an in-process loop would save the
  process start, but the Lox port settles in about 2 s.
- No fix yet for `E_OUTPUT_CAPABILITY` (bare `print`): the repair threads an
  `out: Stream` parameter through callers, which is not a single certain edit.
- Only the Lox corpus is pinned; the sexpr and schematic ports are not.
- `W_UNUSED_IMPORT` removal can leave two blank lines where one import was;
  `mylang fmt` normalizes them.

## For the integrator

- Shared-file edits:
  - `SPEC.md`: six bullets next to DIAGNOSTIC-JSON-1, CHECK-PROJECT-ENTRY-1,
    NATIVE-TEST-9 and MUT-PARAM-1; CLI-HELP-1 now lists `fix`.
  - `src/features.json`: three tooling slugs before `unused-import-warning`.
  - `CLAUDE.md`: one new section, next to the SPEC-merge section.
  - `test/integration.zig`: one `test { _ = @import("fix_cli_test.zig"); }` at the end.
  - `docs/current-language.md`: one link.
  - `src/user_docs.zig`: one topic.
- `src/main.zig`: the single-unit tail of `runCommand` is now `runUnit`, so that a
  headerless `*_test.my` can be checked from projected bytes. `ModuleFiles` gained
  `entry`, `Parsed` gained `library_entry`, and `fix` is dispatched next to `doctest`.
- `sema_calls.zig checkMutationMarkers` appends the diagnostic and continues, and
  `sema.zig checkInstance` fails a body that reported an error without returning one.
  Any other check that wants to report and keep checking can use `Sink.appendFix` and
  that guard.
- Test-runner lane overlap is three lines: `Flags.Output.diagnostics_json`, one
  `appendPolicyFlags` line, one directory-argv line.
- A lane that ships a breaking change should attach a `fix` to its new diagnostic
  and add a pre-change corpus beside `test/fixtures/fix-migration/lox/`.
