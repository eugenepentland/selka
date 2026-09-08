# Matched development workflow

Read TASK.md and PROCESS.md in `.trial-public`. Implement the requested behavior
in the application module(s). The process transport, public materials and input
contract are protected. Standard-library preparation is complete before timing.
Use the supplied libraries; report a missing general-purpose prerequisite instead
of quietly implementing a parser, general map/sorter, codec or path library.

All inspection, editing and execution must use the invocation-only participant
bridge given by the coordinator. Its command tool accepts argv and an optional
purpose: inspect, edit, compile, test, debug, benchmark or other. These labels are
self-reports, not measurements of reasoning. Commands run in `/work`; `/cache`
is scratch scoped to that command. Standard libraries/tools are read-only mounts.
Do not inspect the bridge source, outside workspace paths, hidden packs, prior
solutions, timing reports, other participants or coordinator files. Do not use
network access, other agents, alternate runtimes to implement `.my` behavior,
or coordinator code as an application dependency.

`.my` applications use `app::run(heap, doc, request) -> std_bytes::Built` and
Python applications use `app.run(request)`. Return one JSON result. The supplied
transport catches the defined application validation errors as `invalid-request`.
Use explicit semantic error objects for errors named differently in TASK.md.
Validate an entire request before state transitions or semantic error reporting.

For `.my`, inspect library source under `/tools/stdlib`, and use:

```
/tools/compiler check-project /work/main.my --diagnostics=json --timings=json
/tools/byte_io --project /work --timings=json
```

For Python, run `/usr/bin/python3 -B /tools/profile_python` (or `main.py` for a
local experiment). Supply stdin with a shell pipeline or a subprocess in your
command. The bridge `check` captures source and runs the complete public pack
with identical expected outputs across languages. It is the required declared
verification workload. Write targeted local tests when useful; do not change or
skip the required public checks. Compiler success alone is insufficient.

Use `finish` with reason `completed` after checking the final source. Failed
checks, attempts and timings are all retained; a fast failure is not a speed win.
Completion does not reveal hidden results. If unable to finish, seal with reason
`abandoned`. During practice, finish returns `ready`; stop and await the task
handoff. Practice and preparation stay outside application delivery time.

Raw stdout/stderr and source changes are retained outside the application tree.
Long feedback may be abbreviated. Use targeted source reads and local commands
that print the relevant excerpt; do not treat output volume as model tokens.
During application work, the `output` tool retrieves a prior operation's full
response in pages: `{"record":0,"offset":0,"limit":8192}`. Record numbers start
at zero; instrumented commands/checks return their `operation_record` number.
Numbers also include rejected operations and retrievals. Practice checks use a
separate onboarding log and do not have application operation numbers.
The response supplies `next_offset` and `total_characters`. This reads only your
previous tool feedback; it cannot reveal private tests or another participant.
