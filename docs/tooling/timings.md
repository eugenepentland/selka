# Command phase timings

Two timing outputs exist. `mylang run --timings` times the program a run
builds. `--timings=json` profiles the compiler's front end on one-shot
front-end commands: `check`, `check-project`, `lint`, `fmt`,
`list-declarations`, `discover-duplicates` and the like. `build`, `build --run`,
`run`, `run-project` and `test` refuse `--timings=json` with status 2: the old
back end's phase profile it reported was retired (S5-B2), and `build --report`
says what the core's caches served instead
([native builds](native-build.md)). `check-session` rejects the flag too; it
needs a separate per-request timing contract. Argument validation failures occur
before profiling starts and produce no timing records.

## Run timings

`mylang run prog.my --timings` writes one text line to standard error:

```console
$ mylang run prog.my --timings
timings: native_ns=21234567
```

`native_ns` is elapsed awake-clock nanoseconds from starting the program's process
to its exit: its own start-up and execution, never the build, which finishes
before the timer starts. `run-project` and `build --run` take the flag too, and
it changes neither the exit status, the output nor a trap's report: a trap still
reports the timing and then exits with the trap status. Given twice, or on
`build -o`, it is a usage error. To measure the program without the compiler in
the loop, build once and time the binary with the system timer; the
[performance page](../performance.md) shows both.

## Front-end phase profile

`--timings=json` writes each timing as one JSON object on stderr, beside the
command's `frontend-cache-v1` and `work-report-v1` lines
([work report](work-report.md)):

```json
{"version":"phase-timings-v1","kind":"timing","tool":"compiler","name":"frontend","duration_ns":123,"inclusive":false,"counts":{"modules":1,"source_bytes":24,"ast_nodes":4,"typed_nodes":3},"exit_code":0}
```

`exit_code` is the **whole command outcome**, repeated on every record. Records
are emitted at command return, including attempted phases on source and host
failures. Ordinary failure diagnostics remain visible; use
`--diagnostics=json` when the entire stderr stream must be JSON Lines, and
select `kind: "timing"` records. Timing records never go to stdout.

`duration_ns` measures elapsed awake-clock nanoseconds and is nonnegative.
`counts` contains only available observations, shared across that command's
records; missing counts are omitted, not estimated. Source bytes and module
counts describe the loaded source graph; AST and typed-node counts include
expression and statement nodes.

Measured intervals are disjoint. `total` is an inclusive parent: **do not add it
to the phases**. It starts after argument parsing, includes command cleanup and
diagnostic/output work, and ends before timing serialization. Phase sums need
not equal total: uninstrumented work remains part of total. An attempted phase
that fails includes error unwinding and diagnostics until the command returns.
`inclusive: true` on other phases indicates a composite operation; it does not
mean their durations should be added to a second measure of their children.

- Single-source `source_load` reads source bytes. `frontend` copies the source,
  lexes, parses, and checks it; it is not a standalone type-check measurement.
- Project `source_load_parse` prepares generated inputs and loads source with
  header parsing, dependency discovery and hashes. The project path reports the
  checking work as disjoint phases: `syntax_replay` or `syntax_parse`
  (per-module parse-table acquisition), `declarations_interfaces`
  (module/export indexing and exported signature validation, excluding syntax
  acquisition), `source_merge` (combining relocated module syntax), and, when
  checking runs, `dependency_key_preparation`, `symbolic_templates`,
  `ordinary_body_replay`, `specialization_body_replay`, `fresh_body_check`,
  `entry_adaptation`, `effect_origin_passes`, `domain_codec_validation`,
  `warning_derivation` and `retention_store_io`. These records are disjoint
  (`inclusive:false`). A successful whole-project verdict replay may report only
  `source_load_parse` plus `total` because no check work executed.
- `format_inclusive` (`fmt`) includes parsing and formatting;
  `declaration_listing` (`list-declarations`) covers parse-only listing. Other
  commands may report only applicable boundaries.

```console
$ mylang check-project main.my --timings=json 2>&1 >/dev/null | grep '"kind":"timing"'
{"version":"phase-timings-v1","kind":"timing","tool":"compiler","name":"source_load_parse","duration_ns":723148,"inclusive":false,"counts":{"modules":2,"source_bytes":271},"exit_code":0}
{"version":"phase-timings-v1","kind":"timing","tool":"compiler","name":"total","duration_ns":1336042,"inclusive":true,"counts":{"modules":2,"source_bytes":271},"exit_code":0}
```
