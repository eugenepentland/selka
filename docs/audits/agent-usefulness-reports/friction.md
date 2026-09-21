# M1 — Opt-in friction log and harvest

Package: **M1** of [`agent-usefulness-implementation-plan-2026-09-20.md`](../agent-usefulness-implementation-plan-2026-09-20.md).
Baseline: [`baseline-2026-09-20.md`](baseline-2026-09-20.md) (correction 4: V2's
solver runner does not exist, so this package harvests real sessions instead).
Ledger decision this report discharges: "Friction record shape — pinned by
`src/friction_log.zig` unit test" and "M1's classifier step needs source text the
log deliberately omits; the resolution is recorded in the friction report".

Status: **mechanism, harvest, fixture, tests and docs landed; the CLI hook is
proposed but not applied** (the lead wires `src/main.zig`, which another agent
was editing). Every acceptance criterion is met at the module/script boundary;
the two that need the hook are named in *Acceptance gaps*.

## What landed

- `src/friction_log.zig` — the whole mechanism as one self-contained module:
  the enable decision, the record shape, JSON-line serialization, the append,
  and the privacy rules. Nothing else in the tree changes for it to compile.
- `src/friction_log_test.zig` — six tests, three of them spec-tagged.
- `velocity/friction/harvest.py` — folds a log into repair rounds per code and
  per idiom; `--json`, `--top N`, `--window N`, `--classifier PATH`.
- `velocity/friction/session-2026-09-20.jsonl` — the hand-built 10-record replay
  fixture; four rounds, two codes at zero.
- `tests/test_friction_harvest.py` — 11 unittest cases replaying it.
- `velocity/friction/README.md` — format, enabling, privacy, harvest usage,
  classifier decision and its limitation.
- `SPEC.md` — three appended bullets `[FRICTION-LOG-1..3]`.
- `src/root_test.zig` — one appended import inside the existing `c_abi_test`
  block: `_ = @import("friction_log_test.zig");`.

## The record shape, verbatim

One JSON object per line, a compiler-written example (captured during the
cross-check in *Verification*):

```json
{"version":"friction-log-v1","invocation":{"command":"check","path":"probe4.my"},"compiler":{"compiler_sha256":"c93df4b88e1bb51e09032a1ff797e8f92626c74d0067d1311d5a47e0bec53cd2","zig_version":"0.17.0-dev.1683+5ceec001b","architecture":"x86_64","os":"linux","abi":"gnu","optimize":"ReleaseFast"},"snapshot":"4dad1352c448f2ce96b7f512b88c02c0e21d89d097de6a654627729da5dd849a","diagnostics":[{"code":"E_ARITY","severity":"error","start":5,"end":9}],"status":1,"wall_ns":250000}
```

The Zig side (`const Record`, seven fields — the struct-field cap is seven, so
`command` and `path` nest under `invocation` and `Compiler` is the receipt
module's own six-field `Implementation`):

```zig
const Record = struct {
    version: []const u8,          // "friction-log-v1"
    invocation: Invocation,       // { command, path }
    compiler: Compiler,           // source_receipt.Implementation
    snapshot: []const u8,         // lowercase SHA-256 of the checked source
    diagnostics: []const Finding, // { code, severity, start, end }
    status: u8,                   // the command's exit status
    wall_ns: u64,                 // the command's monotonic duration, in ns
};
```

`wall_ns` is a duration, not a date: the plan asks for "wall time" and
`docs/tooling/runtime-budgets.md` sanctions `std.Io.Timestamp` deltas, not
calendar reads. The module never reads a clock; the caller measures with
`started.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds` (the
measurement `runNative` already takes) and passes the result to `finish`.

Each `Finding` carries `severity` (`"error"`/`"warning"`) on top of the plan's
"code and span", because a passing `check` still prints warnings: without
severity the harvest could not tell `W_UNUSED_BINDING` on a green check from a
blocking error, and the acceptance requires that warning to earn zero rounds.

## Privacy argument

The module enforces privacy by what a record can *name*, not by filtering text
after the fact:

- A record has no field for source text, message text, or any environment value.
  `addDiagnostic` takes a `diagnostic.Diagnostic` and copies **only** `code`,
  `severity` and the two span offsets; `message`, `related`, `provenance` and
  `stack` are dropped, and the diagnostic message is exactly where source text
  leaks into renderers today.
- The environment is read for one key (`MYLANG_FRICTION_LOG`) and its value is
  used as a destination, never recorded.
- The only path in a record is `invocation.path`, copied byte-for-byte from the
  user's argument; the destination path is not recorded. A relative path stays
  relative — no resolution, normalization or absolute conversion anywhere in the
  module.
- A write failure — including an unwritable destination — is swallowed, so
  logging can never change a command's exit status.

Tests that hold this down (`src/friction_log_test.zig`):

- *pins every JSON field name and type*: asserts the top-level key count (7), the
  `invocation`/`compiler`/finding key counts and every value, so a rename or a
  retype fails.
- *never carries source text or environment values*: writes a source file whose
  text contains `SENTINEL-DO-NOT-LOG-9137`, logs a session over its real bytes
  (snapshot hashed from the file), also puts `SENTINEL-ENVIRONMENT-VALUE-4207`
  in the environment map, and asserts neither sentinel, nor the source path, nor
  the log path, nor the temp root appears in the emitted line.
- *drops a diagnostic message that quotes source*: a diagnostic whose message and
  related note both quote the sentinel still logs only its code/severity/span.
- *stays off until asked*: with no flag and no variable `init` returns null and
  the would-be log file does not exist; an empty variable is off; the flag wins
  over the variable.
- *keeps a relative source path relative*: a relative log destination is written
  relative to the working directory and the record contains no absolute path.

## The harvest

A **repair round** is a failing record for a file carrying an **error-severity**
code, followed within the next `--window` records *for the same file* by a
record whose status is a passing check. One round per (failing record, code)
pair. Warnings never seed (they do not block a check), a passing record never
seeds (it is the fix), a fix that is never re-checked is not counted, and
records for other files never consume the window.

Default window **5**, justified in `harvest.py` and the README: the 2026-09-20
session repairs in one or two commands (`edit → check → fix → check`), so five
covers a repair that also runs or tests in between, while a pass five same-file
commands later is more likely a different repair. It is a flag because long
edit/build loops want more.

On the replay fixture:

```
$ python3 velocity/friction/harvest.py velocity/friction/session-2026-09-20.jsonl
friction harvest: 10 records for 3 files, 4 repair rounds (window=5, skipped=0, uncoded failures=0)

repair rounds per code
  rounds  records  code                       idiom                  named by
       1        1  E_ARITY                    call-arity             code-only
       1        1  E_MODULE_HEADER            module-header          code-only
       1        1  E_SYNTAX                   unclassified           unclassified
       1        1  E_TYPE                     type-mismatch          code-only
       0        1  E_LAMBDA_CAPTURE           lambda-capture         code-only
       0        3  W_UNUSED_BINDING           unused-binding         code-only

repair rounds per idiom
  rounds  idiom
       1  call-arity
       1  module-header
       1  type-mismatch
       1  unclassified
       0  lambda-capture
       0  unused-binding
```

Codes that were observed but earned no round stay in the table with `rounds: 0`
and a `records` denominator, so "reported three times, repaired without a round"
is readable instead of invisible. `--json` emits one `friction-harvest-v1`
document with the same rows plus `records`, `files`, `window`, `skipped`,
`uncoded_failures`; `--top N` keeps the N largest rows per table; a truncated
line is counted in `skipped` rather than aborting the harvest.

## The classifier decision, and its limitation

**Decision: the harvested-log half of the classifier is code-only.** A record
carries a code, a severity and a span — never source — so `harvest.py` first
reads `velocity/friction/classifier.json` and keeps every code whose rows are
*all* wildcard rows (`.`, `.*` or empty) with one idiom: those rows already
answer without source (`E_MODULE_NAME → module-header`, `E_RESULT_UNHANDLED →
unhandled-result`, `E_EFFECT_BOUND → effect-ceiling`, `E_ARENA_ESCAPE →
arena-escape`, `E_PRIVATE_SYMBOL → missing-export`). Codes the classifier cannot
answer without source fall back to `CODE_ONLY_IDIOMS` in `harvest.py`, a
documented code-only extension: `E_ARITY → call-arity`, `E_MODULE_HEADER →
module-header`, `E_TYPE → type-mismatch`, `E_LAMBDA_CAPTURE → lambda-capture`,
`E_UNBOUND → unbound-name`, `E_UNKNOWN_FUNCTION → unknown-function`,
`E_EXPLICIT_DISCARD_REQUIRED → discarded-result`, `W_UNUSED_BINDING →
unused-binding`. Anything in neither place is reported as **`unclassified`,
never guessed**; every row says which of the three named it (`named by`).

This is branch (b) of the choice the brief gives. Branch (a) — record the
matched idiom name at log time, from the in-memory source the compiler holds —
is not implemented: it would grow the pinned record shape and need the
classifier's regexes on the Zig side, where there is no regex engine. The
extension table's canonical home is `classifier.json`; it lives in `harvest.py`
only because that file belongs to another package's owner.

**Limitation, plainly.** A code-only mapping cannot distinguish idioms that share
a code, so harvested idioms are coarser than solver-transcript idioms. The
important case is `E_SYNTAX`: `classifier.json` now distinguishes ternary, tuple,
`is None`, docstring, module constant, method, `from-import`, `union-cases`,
set-literal, nested comprehension, generator argument, exceptions and `del`, and
a log record cannot choose between them — the fixture's union-comma round is
therefore counted under `unclassified` even though the classifier has a
`union-cases` idiom for that source shape. That is deliberate: `unclassified`
rows are the improver's first read (`docs/velocity-loop.md` §Lane A), and a
guessed "ternary" would be worse than an honest unknown. The two ways to fix it
later are (a) above, or adding explicit wildcard rows for harvested codes to
`classifier.json`; neither is in this package's file ownership.

## The proposed `src/main.zig` hook (not applied)

Exact, mechanical sketch. Nothing here is applied; another agent owns
`src/main.zig`.

**1. Import and flag parsing.** Add beside the other direct imports:

```zig
const friction_log = @import("friction_log.zig");
```

In `parseArgs`, next to the `--no-cache` branch:

```zig
        if (std.mem.startsWith(u8, arg, "--friction-log=")) {
            if (parser.friction_log != null or arg.len == "--friction-log=".len) return error.Usage;
            parser.friction_log = arg["--friction-log=".len..];
            continue;
        }
```

Add `friction_log: ?[]const u8 = null,` to `ArgumentParser`, add
`friction_log: ?[]const u8,` to `Parsed`, and add
`.friction_log = self.friction_log,` to `finish()`'s returned literal. The
spelling matches the plan; `mylang test` parses its own options and is covered
below.

**2. Let the diagnostic renderers hand their findings to the recorder.** Add one
field to the private `Context` (it has 7 today; private structs are not under
the `type-size` cap, and `observation` already sets this precedent):

```zig
    /// Set while a command runs so `report` records exactly what it renders.
    friction: ?*friction_log.Recorder = null,
```

In `report` (single-file `Compilation`) and `reportProject` (project
`Compilation`), inside the existing render loops:

```zig
        if (init.friction) |*recorder| recorder.addDiagnostic(diagnostic);
```

`rememberFrontendVerdict` renders the same warnings for cache storage, not for
printing, so it must **not** collect; only the two printing paths do.

**3. Start and finish one record per command in `run(init, parsed)`.** After the
`check-session` early return and before `runCommand`:

```zig
    const started = std.Io.Timestamp.now(init.io, .awake);
    var friction = friction_log.Recorder.init(init.gpa, init.io, init.environ, .{
        .flag = parsed.friction_log,
        .command = @tagName(parsed.command),
        .path = parsed.path,
        .snapshot = "",
        .compiler = try language.source_receipt.implementation(init.gpa, try compilerIdentity(init.io)),
    });
    defer if (friction) |*recorder| recorder.deinit();
    errdefer if (friction) |*recorder| recorder.finish(2, elapsedNs(init, started));
```

Point `command_init` at it where the observation pointer is already set:

```zig
    if (friction) |*recorder| command_init.friction = recorder;
```

and after `runCommand` returns, before `reportMeasured`:

```zig
    if (friction) |*recorder| recorder.finish(status, elapsedNs(init, started));
```

with the helper `fn elapsedNs(init: Context, started: std.Io.Timestamp) u64 { return @intCast(@max(0, started.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds)); }`.
A host failure leaves through the `errdefer` as status 2, matching what
`dispatch` reports.

**4. Set the snapshot digest where the source is actually loaded** (two one-line
assignments, one per loading shape, because `run()` never sees the bytes):

- single file, in `runCommand` immediately after
  `const bytes = try std.Io.Dir.cwd().readFileAlloc(...)`:
  `if (init.friction) |*recorder| recorder.snapshot = try friction_log.snapshotHex(init.gpa, bytes);`
  — the same SHA-256 `source_receipt.Input.sha256` and `project.Module.digest`
  use, over exactly the bytes the command checked.
- module graph, in `listModulesWithCache` right after `loadModules` succeeds:
  `if (init.friction) |*recorder| recorder.snapshot = try init.gpa.dupe(u8, &std.fmt.bytesToHex(project.modules.items[project.order.items[0]].digest, .lower));`
  — the entry module's existing digest, not a new hash.

**5. `mylang test` — not wired, and mostly free anyway.** `dispatch` routes
`mylang test` to `native_test_command.run`, which drives child compiler
processes and maps their exit codes; the children render located diagnostics to
stderr and the parent keeps only exit codes plus rendered text, so a structured
record there would mean either parsing `diagnostic-v1` JSON out of child stderr
or threading a diagnostics sink through the fan-out — restructuring, which the
lead asked me to stop short of. The cheap route is the environment: `mylang test`
spawns children through `fs.Context.bounded`, which **clones the parent's
environment**, so once the `run()` hook above lands, `MYLANG_FRICTION_LOG=PATH
mylang test …` records every child `list-interfaces`/`check-project`/
`native-test-graph`/`emit-project-qbe` invocation with real codes and spans. Two
caveats to state in the user docs: the outer `test` command itself is not
recorded, and `--friction-log=PATH` is *not* forwarded to children (the parent
builds their argv), so `mylang test` needs the environment variable form until
someone forwards the flag. `mylang build` is outside the plan's command list and
never enters `run()`; a record for it would need its own start/finish pair in
`buildCommand`.

**6. Register the Python driver.** `tests/*.py` drivers are not auto-discovered;
`tests/idiom_probes.py` is the only one wired into `build.zig`. Adding

```zig
    const friction_driver = bounded(b.addSystemCommand(&.{ "python3", "tests/test_friction_harvest.py" }), rss.driver);
    friction_driver.setCwd(b.path("."));
    b.step("test-friction", "Replay the friction log and check the harvest").dependOn(&friction_driver.step);
```

to `build.zig` is the natural registration; `build.zig` is not in this package's
file ownership, so it is left to the lead (the driver also runs standalone and
under `python3 -m unittest discover -s tests -p 'test_friction_harvest.py'`).

## The replay fixture

`velocity/friction/session-2026-09-20.jsonl` is hand-built in the pinned shape —
synthetic compiler identity and wall times, real SHA-256 of each probe snapshot.
The ten commands:

| # | command | file | status | diagnostics | snapshot of |
| --- | --- | --- | --- | --- | --- |
| 1 | `check` | `probe4.my` | 1 | `E_MODULE_HEADER` | `probe_headerless` `3d8c89…` |
| 2 | `check` | `probe4.my` | 0 | — | `probe_module` `8f2aeb…` |
| 3 | `check` | `probe4.my` | 1 | `E_ARITY` | `probe_split` `b55cbf…` |
| 4 | `check` | `probe4.my` | 0 | `W_UNUSED_BINDING` (warning) | `probe_split_fixed` `dfd441…` |
| 5 | `check` | `probe4.my` | 1 | `E_TYPE` | `probe_ord` `924bfe…` |
| 6 | `run` | `probe4.my` | 0 | — | `probe_chr` `a4f6d5…` |
| 7 | `check` | `probe4.my` | 1 | `E_SYNTAX` | `probe_union` `39dbe9…` |
| 8 | `check` | `probe4.my` | 0 | — | `probe_union_fixed` `9b72ba…` |
| 9 | `check` | `sexpr/ast.my` | 1 | `E_LAMBDA_CAPTURE`, `W_UNUSED_BINDING` (warning) | `probe_lambda` `de5578…` |
| 10 | `check` | `sexpr/lexer.my` | 0 | `W_UNUSED_BINDING` (warning) | `probe_lexer` `1c036f…` |

Rounds: record 1 → 2 (`E_MODULE_HEADER`), 3 → 4 (`E_ARITY`), 5 → 6 (`E_TYPE`),
7 → 8 (`E_SYNTAX`) = four. `E_LAMBDA_CAPTURE` on record 9 is the last record for
`sexpr/ast.my`, so no passing check follows it: zero rounds. `W_UNUSED_BINDING`
appears only as a warning, twice on passing commands and once beside the
`E_LAMBDA_CAPTURE` failure, and warnings never seed: zero rounds.

The snapshots are the real SHA-256 of these snippets (so the fixture is
reproducible rather than decorative):

```python
probe_headerless = 'import strings\n\n\ndef main() -> int:\n    return 0\n'
probe_module     = 'module probe4\n\nimport strings\n\n\ndef main() -> int:\n    return 0\n'
probe_split      = 'module probe4\n\nimport strings\n\n\ndef main() -> int:\n    parts = "a b".split()\n    return len(parts)\n'
probe_split_fixed= 'module probe4\n\nimport strings\n\n\ndef main() -> int:\n    parts = "a b".split(" ")\n    unused = 1\n    return len(parts)\n'
probe_ord        = 'module probe4\n\n\ndef main() -> int:\n    text = "41" + ord("0")\n    return 0\n'
probe_chr        = 'module probe4\n\n\ndef main() -> int:\n    text = "41" + chr(48)\n    return 0\n'
probe_union      = 'module probe4\n\n\ndef pick(value: int | str) -> int:\n    return 0\n'
probe_union_fixed= 'module probe4\n\n\ndef pick(value: Result[int, str]) -> int:\n    return 0\n'
probe_lambda     = 'module sexpr.ast\n\n\ndef make(offset: int) -> int:\n    shift = lambda x: x + offset\n    return 0\n'
probe_lexer      = 'module sexpr.lexer\n\n\ndef main() -> int:\n    cursor = 0\n    return cursor\n'
```

## Files changed

| File | Change |
| --- | --- |
| `src/friction_log.zig` | **New.** `variable`, `version`, `Compiler` (alias of `source_receipt.Implementation`), `Invocation`, `Finding`, `Request`, `destination`, `Recorder` (`init`/`addDiagnostic`/`finish`/`deinit`), `snapshotHex`, private `Record` and `appendLine`. 7 fields on the two widest structs, ≤4 parameters on every function, `///` on every `pub` declaration. |
| `src/friction_log_test.zig` | **New.** Six tests: record shape, reader rejection, relative path, off by default, sentinel privacy, message-text privacy. |
| `src/root_test.zig` | One appended import in the existing `c_abi_test` block. |
| `SPEC.md` | Three appended bullets, `[FRICTION-LOG-1..3]`. |
| `velocity/friction/harvest.py` | **New.** Round folding, code-only idiom naming, `--json`/`--top`/`--window`/`--classifier`. |
| `velocity/friction/README.md` | **New.** Format, enabling, privacy, harvest usage, window rationale, classifier limitation, fixture. |
| `velocity/friction/session-2026-09-20.jsonl` | **New.** Ten-record replay fixture. |
| `tests/test_friction_harvest.py` | **New.** Eleven unittest cases (fixture shape, the four rounds, the two zeros, window, warnings, `--top`, `--json`, truncated line). |
| `docs/audits/agent-usefulness-reports/friction.md` | This report. |

Not touched: `src/main.zig`, `src/parser.zig`, `src/sema.zig`, `src/lint.zig`,
`src/diagnostic.zig`, `velocity/friction/classifier.json`, `velocity/goal.json`,
`velocity/backlog.json`, `build.zig`, and
`zig-out/bin/mylang-baseline-20260920`.

## Verification

Every command below was run in this tree; output is verbatim except for
truncation marks.

```
$ zig test src/friction_log_test.zig --cache-dir .zig-cache
1/6 friction_log_test.test.friction record pins every JSON field name and type...OK
2/6 friction_log_test.test.friction record readers reject a renamed or retyped field...OK
3/6 friction_log_test.test.friction record keeps a relative source path relative...OK
4/6 friction_log_test.test.friction log stays off until a flag or the environment asks for it...OK
5/6 friction_log_test.test.friction record never carries source text or environment values...OK
6/6 friction_log_test.test.friction record drops a diagnostic message that quotes source...OK
All 6 tests passed.
```

```
$ zig build test-units -Dtest-filter=friction --summary all
guardian/test: 17 test(s) selected by filter: "friction" — 7 match by name, 10 unnamed test block(s) run regardless
guardian/test: PASS — 17 passed
Build Summary: 9/9 steps succeeded; 17/17 tests passed
test-units success
```

Six of the seven name matches are this package's tests; the seventh is
`src/declaration_hints_test.zig`'s "the hinted forms and the friction classifier
name one table", which another package added concurrently. The filter's `10
unnamed test block(s)` are the import blocks of `src/root_test.zig`, the one that
imports this package included.

```
$ python3 tests/test_friction_harvest.py
Ran 11 tests in 0.357s
OK
```

The harvest output over the fixture is quoted in *The harvest* above;
`--json` was also run and re-parsed by the driver.

```
$ zig fmt --check src/friction_log.zig src/friction_log_test.zig
(no output; exit 0)
```

Guardian, run check by check: `spec` reports **533/533 behaviors covered**
(including all three `FRICTION-LOG` bullets); `orphan-files` reports **all 371
source files reachable from 11 roots**; `test-reachability` reports all 195
test-bearing files reachable; `doc-comments`, `function-size`, `type-size`,
`imports`, `import-resolution`, `catch-discipline`, `naming`, `dead-pub`,
`error-discipline` and `ban-time`/`ban-rng` all pass. The first full
`zig build guardian` run in this package failed `error-path-test` on my test
file's helper errors (`WrongFieldType`, `MissingField` had no test naming them);
`friction record readers reject a renamed or retyped field` now names both with
`expectError`, and no guardian finding names `src/friction_log.zig` or
`src/friction_log_test.zig` in any later run.

**Tree state at hand-off.** `zig build` (and therefore `zig build test`) is
currently red on *other* packages' in-flight files, not on this one: the last
run reported 12/88 guardian checks failed, every named finding under
`src/reference*.zig`, `src/declaration_hints_test.zig`,
`src/headerless_import_test.zig` or `src/sema.zig` (unlinked spec tags,
orphan/reachability, formatting, complexity, empty catch, error-path). The
tree-wide `spec` run reads 533/533 covered with 9 unlinked and 2 duplicate tags,
none of them `FRICTION-LOG*`. `zig build test-units -Dtest-filter=friction`
passes (17/17 selected, 6 of them this package's). Whoever greens the tree should
re-run `zig build` and `zig build fmt-check` after those packages land.

Cross-check that the two sides agree (a compiler-written line read by the
harvester, run through a scratch root that was deleted afterwards):

```
$ cat .zig-cache/friction-e2e.jsonl
{"version":"friction-log-v1","invocation":{"command":"check","path":"probe4.my"},"compiler":{"compiler_sha256":"ab",…},"snapshot":"4dad1352…","diagnostics":[{"code":"E_ARITY","severity":"error","start":5,"end":9}],"status":1,"wall_ns":250000}
$ python3 velocity/friction/harvest.py .zig-cache/friction-e2e.jsonl --json
{"version": "friction-harvest-v1", "records": 1, "rounds": 0, …, "by_code": [{"code": "E_ARITY", "rounds": 0, "records": 1, "idiom": "call-arity", "idiom_source": "code-only"}]}
```

The sentinel in that scratch diagnostic's `message` appears nowhere in the line.

`zig-out/bin/mylang-baseline-20260920` was never rebuilt or overwritten; no
`git` state-changing command was run, and no tree-wide `zig fmt` was run.

## Acceptance gaps (until the hook lands)

Met now, without `src/main.zig`:

- the unit test pins the record shape (field names, types and counts, both ways);
- the log is absent unless requested — at the API boundary: `init` returns null,
  nothing is written, and the destination file does not exist;
- the replayed 2026-09-20 log yields exactly four rounds (`E_ARITY` split,
  `E_SYNTAX` union comma, `E_MODULE_HEADER`, `E_TYPE` ord) and zero for
  `E_LAMBDA_CAPTURE` and `W_UNUSED_BINDING`;
- the harvest script is documented beside the classifier;
- the sentinel test proves no source text and no environment value reaches the
  log.

Cannot be met until the `src/main.zig` hook lands, and must be re-checked then:

1. **`--friction-log=PATH` exists and outranks the variable on real commands.**
   Today the flag is unparsed by any command; the decision function is tested,
   but a user cannot pass the flag.
2. **End-to-end absence and end-to-end privacy**: "run `mylang check` with no
   request and observe no file" and "run a real command over a sentinel file and
   grep the log" both need a real command to write through the hook. Once wired,
   the check is `MYLANG_FRICTION_LOG=$PWD/f.jsonl zig-out/bin/mylang check
   probe.my` plus `grep -c SENTINEL f.jsonl` (expect 0), and the same command
   with neither flag nor variable (expect no `f.jsonl`).
3. **A record from a real session**, and therefore a harvest over a real log
   rather than the replay fixture. The fixture pins the contract; it is not
   evidence that a command produces it.

## Derived inputs this package hands on

- The per-code and per-idiom tables are the ranking input D1, D2 and S1 asked
  for; with the hook landed, `MYLANG_FRICTION_LOG` on an ordinary working
  session produces the A3 series from every session rather than a nightly run.
- `velocity/backlog.json` item V2 (`velocity/solve.py`) can consume the same
  `harvest.py` once solver transcripts are logged as commands; this package
  deliberately did not touch `backlog.json` or `goal.json`.
- The `CODE_ONLY_IDIOMS` table should move into `classifier.json` when that
  file's owner next edits it, so a code-only idiom and a source-regex idiom for
  the same code live in one table.
