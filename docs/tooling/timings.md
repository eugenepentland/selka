# Command phase timings

Two timing outputs exist. `selka run --timings` times the program a run
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

`selka run prog.selka --timings` writes one text line to standard error:

```console
$ selka run prog.selka --timings
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
  `entry_adaptation`, `origin_passes`, `domain_codec_validation`,
  `warning_derivation` and `retention_store_io`. These records are disjoint
  (`inclusive:false`). A successful whole-project verdict replay may report only
  `source_load_parse` plus `total` because no check work executed.
- `format_inclusive` (`fmt`) includes parsing and formatting;
  `declaration_listing` (`list-declarations`) covers parse-only listing. Other
  commands may report only applicable boundaries.

```console
$ selka check-project main.selka --timings=json 2>&1 >/dev/null | grep '"kind":"timing"'
{"version":"phase-timings-v1","kind":"timing","tool":"compiler","name":"source_load_parse","duration_ns":723148,"inclusive":false,"counts":{"modules":2,"source_bytes":271},"exit_code":0}
{"version":"phase-timings-v1","kind":"timing","tool":"compiler","name":"total","duration_ns":1336042,"inclusive":true,"counts":{"modules":2,"source_bytes":271},"exit_code":0}
```

## Saved developer history

Enable recording once, then use ordinary compiler commands:

```console
selka profile on
selka check app/main.selka
selka run app/main.selka
selka profile history
selka profile trends --command check --entry app/main.selka
selka profile trends --json --limit 10000 > trends.json
selka profile off
```

`profile on [--dir DIRECTORY]` persists the choice for this user. The configuration
lives in `$XDG_STATE_HOME/selka/profile/config.json`, or
`~/.local/state/selka/profile/config.json` when no absolute XDG state home is set.
That directory also holds history by default. `SELKA_PROFILE_DIR=/path` selects
an archive for one environment without changing configuration; an explicitly
empty value disables recording, even when the saved setting is on. `profile
status` shows the effective setting. `off` preserves history. No automatic
pruning occurs, and cleaning compiler caches leaves the archive intact.

Completed `check`, `check-project`, `check-module`, `build`, `run`, `run-project`
and `test` invocations are recorded, including failures and cache replays.
A failed command retains the observations collected before the failure;
unreached producers contribute no report. Recording is local and does not add
report output to otherwise quiet commands.
Each invocation writes a flushed, atomically published JSON file under `runs/`,
so concurrent commands cannot overwrite one another. Aborted processes cannot
publish a completed record. Storage failures warn without changing the command's
exit status. `profile` itself and long-running `check-session` are not recorded.

The `compiler-profile-v1` envelope retains:

- Timestamp, command and entry, exit status, in-process elapsed nanoseconds,
  and metadata setup cost. The elapsed interval covers command dispatch and
  instrumentation; it excludes process startup, initial metadata collection and
  final archive publication. Use the external profiler below for wall time.
- Exact compiler binary SHA-256 (memoized by executable filesystem generation),
  compiler source identity, Git commit, tracked changed paths from `git diff
  --name-only HEAD`, tracked diff digest, and entry-file digest when readable.
  Git metadata is unavailable outside a repository. Untracked dependency files
  are not included in the Git snapshot; these are observations, not replay proofs.
- CPU model, host, affinity, normalized arguments, compilation-environment digest,
  and cache directory selections. Guest arguments after `--` are hashed rather
  than stored verbatim; environment values are not dumped wholesale.
- Existing work, native cache, guest-test and phase timing reports collected
  internally, including available native per-unit intervals. Replayed work never
  acquires the previous invocation's compile durations.

`history` shows the newest 20 matching records, or full documents with `--json`.
`trends` considers the newest 1000 matching records by default. Both accept
`--limit N`, `--command NAME`, `--entry PATH` and `--dir DIRECTORY`; these only
select what is read and never delete older observations. Unreadable, malformed or
foreign records are counted and skipped. Failed and incomplete records remain in
history but do not enter latency distributions.

Trend rows show count, median, nearest-rank p95, min and max. Rows separate UTC
day, compiler hash, revision/dirty snapshot, entry content, workload, host/CPU,
environment, parallelism and observed cache counts. Compare rows across revisions
with the same workload and cache conditions. The JSON view includes their
identities, per-command native unit-count distributions, and `intervals` with
phase/native-unit distributions. Interval counts count measured intervals; one
command can contribute several matching intervals (for example, test roots).
They are never summed into wall time. These are ordinary developer observations: CPU contention, OS page
caches and hardware caches are uncontrolled, and short warm commands can be
noticeably affected by instrumentation. Metadata collection, especially a new
compiler's first binary hash, adds separately reported overhead.

## Isolated external matrix

`scripts/dev_loop_profile.py` remains an unregistered standalone profiler. Run it
from a separate linked worktree with an already built compiler:

```console
python3 scripts/dev_loop_profile.py --compiler /path/to/selka \
  --output /tmp/dev-loop-profile --repeats 5
```

It emits `profile.json`, `summary.md` and raw command logs for cold/warm checks,
uncached/cached runs, builds, build-and-run, filtered guest tests, filtered Zig
unit tests and a Zig rebuild after a temporary stdlib mtime touch. Each case and
repeat has private caches, with an explicit untimed warm-up for warm cases.
Automatic compiler history is disabled inside this controlled matrix so its
metadata collection does not contaminate the measurements. It uses the existing
bounded measurement admission workflow and never invokes the gate or corpus B.
`--dry-run`, `--case NAME` and `--self-test` allow inspection and focused use.

Legacy compiler reports still provide aggregate counts and phase costs. When the
producer supplies `unit_timings`, JSON also maps native units to their reported
source ownership and changed paths, retaining measured compile distributions.
Neither path estimates frontend milliseconds per source file. The stdlib touch
restores atime/mtime and never changes file contents; ctime cannot be restored.
