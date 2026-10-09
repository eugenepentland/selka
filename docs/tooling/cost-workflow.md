# Investigating collection and text costs

Start with a source entry and an observable unit of work. For example, the
[October 9 operation workload](../../experiments/frontend-closeout-20261009/cost/operations/main.my)
processes 32 input records four times, returns a checksum and prints `2144`.
Its [Juice manifest](../../experiments/frontend-closeout-20261009/cost/operations/juice.toml)
fixes the arguments, 128 completed input records and the expected output.

Inspect the emitted function before deciding what to change:

```bash
selka cost entry.selka checksum --json
selka build entry.selka -o counted --release --counters
SELKA_COUNTERS=counts.json ./counted 32 4
selka cost entry.selka checksum --json --counters counts.json
```

Keep the source, compiler and build mode the same when joining these reports.
The standalone counters join matches emitted function names; the caller supplies
the identity relationship. Juice captures source hashes, tool identities,
ordinary and counted executables, their verified outputs and the counter
contract together:

```bash
selka juice record juice.toml --name before --repeats 3 --static
# Make a source change, retaining equivalent completed work and output.
selka juice record juice.toml --name after --repeats 3 --static
selka juice compare BEFORE/record.json AFTER/record.json \
    --mode application --output comparison.json
```

Choose `backend` mode when the source stays fixed and the compiler changes.
Use `combined` when both change. A comparison can refuse mismatched contracts,
inputs or measurement contexts; that refusal preserves the meaning of the score.
Use a larger scenario and `juice validate` before using a quick workload as a
proxy for a long application run. A whole-process instruction count includes
startup, argument parsing and output; these can dominate a small scenario.

The [saved workload](../../experiments/frontend-closeout-20261009/cost/REPORT.md)
illustrates three different quantities. Its release report has six allocation
sites in `checksum`, including two unresolved sites. Four calls to that function
produce 24 managed allocation events. Three further managed blocks are charged
to `<outside>`, bringing the run total to 27. A may-allocate site can execute
many times or avoid allocating on a particular path. Runtime scratch allocations
outside managed blocks are absent from the memory counters, so neither number
is a total count of process heap activity.

The same counting run records 128 list pushes, 128 text appends and eight text
growths moving 124 bytes. Those observations locate exercised work. They do not
establish that a different spelling, collection representation or copy annotation
would improve the application. First use a concrete source edit with the same
result, then compare ordinary instruction counts. Counting executable timings
are not ordinary-program timings.

The selected typed-tree census in the saved report helps find constructs to
inspect. It counts visible checked body instances, including concrete generic
specializations, at typed loop depth. Plain list slices, repetition lowered into
anonymous loops, opaque operands and nominal comparisons whose representation
is unknown remain explicit omissions. A zero row is not proof that the source
contains no such operation. Likewise an unknown LLVM vectorization result is
an unknown result, not evidence that every source loop stayed scalar.

See [static cost fields](cost.md), [counter coverage](counters.md) and
[Juice contracts and validation](juice.md) for the exact definitions.
