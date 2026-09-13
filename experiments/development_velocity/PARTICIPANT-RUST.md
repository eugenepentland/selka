# Matched Rust development workflow

Read `TASK.md` and `PROCESS.md` in `.trial-public`. Implement the requested
behavior in `app.rs` and, where supplied, its sibling application modules.
`main.rs`, `json.rs`, the public materials, and the input contract are protected.
Rust standard-library preparation is complete before timing. Use stable Rust and
the standard library only; report a missing general-purpose prerequisite rather
than quietly implementing another JSON parser, codec, map, sorter, or path library.

All inspection, editing, and execution must use the invocation-only participant
bridge given by the coordinator. Its command tool accepts argv and an optional
purpose: inspect, edit, compile, test, debug, benchmark, or other. Commands run in
`/work`; `/cache` is command-scoped scratch. The frozen Rust toolchain is mounted
read-only at `/tools/rust`. The bridge also has `await-handoff`, taking `{}`, used
only between practice and the timed task.

Do not inspect bridge source, outside workspace paths, hidden packs, prior
solutions, timing reports, other participants, or coordinator files. Do not use
network access, other agents, alternate runtimes, or coordinator code as an
application dependency.

The application interface is:

```rust
pub fn run(request: &crate::json::Value) -> Result<crate::json::Value, ()>
```

Return one JSON value. `Err(())` is converted by the protected transport to
`{"error":"invalid-request"}`. Return explicit error objects for semantic errors
named differently in `TASK.md`. Validate the entire request before performing
state changes or returning a semantic error.

The frozen `json` module supplies `Value::{Null,Bool,Integer,Decimal,String,
Array,Object}` plus `exact_object`, `bounded_integer`, `bounded_array`, and
`identifier`. `Value` has `object`, `array`, `string`, `integer`, and `field`
accessors. Object values use `Vec<(String, Value)>`; `BTreeMap` and `BTreeSet`
provide deterministic ASCII ordering for this corpus's ASCII identifiers.

Compile and run locally with:

```sh
/tools/rust/bin/rustc --edition=2021 -O /work/main.rs -o /work/app
/work/app
```

Supply stdin with a shell pipeline or subprocess. The bridge `check` captures
source, performs the frozen build, and runs the complete public pack with
identical expected outputs across languages. It is the required verification
workload. Targeted local tests are useful, but do not change or skip the public
check. Compiler success alone is insufficient.

Use `finish` with reason `completed` after checking final source. Failed checks,
attempts, and timings are retained; completion does not reveal hidden results. If
unable to finish, seal with reason `abandoned`. During practice, `finish` returns
`ready`; then call `await-handoff` with `{}`, in the same context, until it answers
`phase: "working"`, and follow its message.

Raw stdout/stderr and source changes are retained outside the application tree.
For abbreviated feedback, `output` retrieves a previous operation in pages using
`{"record":0,"offset":0,"limit":8192}`. Record numbers begin at zero.
