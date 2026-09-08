# Command phase timings

Use `mylang <command> <path> --timings=json` on one-shot commands, or
`mylang-io --project <directory> --timings=json`. Default output and the older
`run --timings` text format remain unchanged. `check-session` rejects this flag;
it needs a separate per-request timing contract. Argument validation failures
occur before profiling starts and do not produce timing records.

Each timing is one JSON object on stderr:

```json
{"version":"phase-timings-v1","kind":"timing","tool":"compiler","name":"frontend","duration_ns":123,"inclusive":false,"counts":{"modules":1,"source_bytes":24,"ast_nodes":4,"typed_nodes":3},"exit_code":0}
```

`exit_code` is the **whole command outcome**, repeated on every record. Records
are emitted at command return, including attempted phases on source, host and
runtime failures. Ordinary failure diagnostics remain visible; use compiler
`--diagnostics=json` when the entire stderr stream must be JSON Lines. The byte
host retains its text diagnostics and optional runtime memory JSON records, so
consumers should select `kind: "timing"`. Timing records never go to stdout.

`duration_ns` measures elapsed awake-clock nanoseconds and is nonnegative.
`counts` contains only available observations, shared across that command's
records; missing counts are omitted, not estimated. Source bytes and module
counts describe the loaded source graph; AST and typed-node counts include
expression and statement nodes. Host input bytes are the successfully read
request size; output bytes count successfully published bytes. No VM instruction
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
  header parsing, dependency discovery and hashes. `frontend` builds interfaces,
  combines syntax and checks the project. These phases are disjoint.
- `bytecode_lowering` runs after checking, before `vm_execution`. VM execution
  includes VM validation, setup and cleanup, and registered host callbacks;
  compiler result output is outside it. `evaluation` labels compile-time
  evaluation rather than ordinary VM execution.
- `native_emission` covers native validation and C rendering after the separately
  measured `bytecode_lowering`. `bytecode_dump_inclusive` includes lowering and disassembly;
  `format_inclusive` includes parsing and formatting. `discovery` measures
  duplicate analysis. Other commands may report only applicable boundaries.
- Byte host `compilation_inclusive` uses the existing embedded-project API,
  which loads, parses, checks and lowers together. No separate lowering time is
  claimed there. `stdin_read`, `vm_execution` and `stdout_write` are separate;
  host registry/grant setup remains in total. Failed guests publish no output.

Run protocol checks without performance thresholds:

```sh
python3 tests/timings.py --compiler zig-out/bin/mylang --runner zig-out/bin/mylang-io
```
