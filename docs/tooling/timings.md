# Command phase timings

Use `mylang <command> <path> --timings=json` on one-shot commands, or
`mylang-io --project <directory> --timings=json`. Default output and the older
`run --timings` text format remain unchanged. `check-session` rejects this flag;
it needs a separate per-request timing contract. Argument validation failures
occur before profiling starts and do not produce timing records.

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
`build -o`, it is a usage error.

On the new core `run --timings=json` is refused: the old back end's phase profile
it reported was retired (S5-B2). To measure the program itself without the
compiler in the loop, build once and time the binary with the system timer; the
[performance page](../performance.md) shows both.

Each timing is one JSON object on stderr:

```json
{"version":"phase-timings-v1","kind":"timing","tool":"compiler","name":"frontend","duration_ns":123,"inclusive":false,"counts":{"modules":1,"source_bytes":24,"ast_nodes":4,"typed_nodes":3},"exit_code":0}
```

`exit_code` is the **whole command outcome**, repeated on every record. Records
are emitted at command return, including attempted phases on source, host and
runtime failures. Ordinary failure diagnostics remain visible; use compiler
`--diagnostics=json` when the entire stderr stream must be JSON Lines. The byte
host retains its text diagnostics, so consumers should select
`kind: "timing"`. Timing records never go to stdout.

`duration_ns` measures elapsed awake-clock nanoseconds and is nonnegative.
`counts` contains only available observations, shared across that command's
records; missing counts are omitted, not estimated. Source bytes and module
counts describe the loaded source graph; AST and typed-node counts include
expression and statement nodes. Host input bytes are the successfully read
request size; output bytes count successfully published bytes. No instruction
or host-call count is inferred.

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
  header parsing, dependency discovery and hashes. The project path now reports
  the formerly composite `frontend` interval as disjoint phases:
  `syntax_replay` or `syntax_parse` (per-module parse-table acquisition),
  `declarations_interfaces` (module/export indexing and exported signature
  validation, excluding syntax acquisition), `source_merge` (combining relocated
  module syntax), and, when checking runs, `dependency_key_preparation`,
  `symbolic_templates`, `ordinary_body_replay`, `specialization_body_replay`,
  `fresh_body_check`, `entry_adaptation`, `effect_origin_passes`,
  `domain_codec_validation`, `warning_derivation` and `retention_store_io`.
  These records are disjoint (`inclusive:false`). A successful whole-project
  verdict replay may report only `source_load_parse` plus `total` because no
  frontend/check work executed.
- `bytecode_lowering` runs after checking and lowers the checked program to the
  internal bytecode the native backend consumes. `native_emission` covers native
  validation and QBE rendering after that separately measured lowering.
- `run` and `run-project` report `native_execution`: the guest child process plus
  the native build it needed, excluding compiler result output. Compile-time
  constant evaluation happens inside `frontend` and is not reported separately.
- `bytecode_dump_inclusive` includes lowering and disassembly; `format_inclusive`
  includes parsing and formatting. `discovery` measures duplicate analysis.
  `declaration_listing` covers parse-only listing. Other commands may report only
  applicable boundaries.
- Byte host `compilation_inclusive` uses the existing embedded-project API,
  which loads, parses, checks and lowers together. No separate lowering time is
  claimed there. `stdin_read`, `stdout_write` and the guest-execution phase are
  separate; that phase is still emitted under its legacy name `vm_execution`
  although the guest now runs as a native process. Host registry/grant setup
  remains in total. Failed guests publish no output.

Run protocol checks without performance thresholds:

```sh
python3 tests/timings.py --compiler zig-out/bin/mylang --runner zig-out/bin/mylang-io
```
