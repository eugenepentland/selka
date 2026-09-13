# Matched development workflow: Zig without Guardian

Read `TASK.md` and `PROCESS.md` in `.trial-public`. Implement the requested
behavior in the supplied Zig application modules using only Zig's standard
library and the frozen `support.zig` helpers. The JSON transport in `main.zig`
is supplied infrastructure; application behavior lives in `app.zig` and any
task starter modules.

All inspection, editing and execution must use the invocation-only participant
bridge given by the coordinator. Commands run in `/work`; `/cache` is scratch
scoped to that command. Do not inspect coordinator files, hidden packs, prior
solutions, timing reports, other participants, or paths outside the workspace.

The frozen verification adapter runs exactly these phases:

```
/tools/zig/zig test main.zig -ODebug
/tools/zig/zig build-exe main.zig -OReleaseSafe -femit-bin=/cache/app
/cache/app
```

There is deliberately no Guardian phase, policy, binary, or configuration in
this arm. The bridge `check` runs the complete public pack and is the required
declared verification workload. Compiler success alone is insufficient.

Use `finish` with reason `completed` after checking the final source, or
`abandoned` if unable to finish. During practice, finish and then call
`await-handoff` in the same context until the timed task begins.
