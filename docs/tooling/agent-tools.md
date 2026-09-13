# Agent-facing inspection

Three facilities exist so that a program which failed can be examined without
re-running the world: a bounded instruction trace, a recorded and replayable host
transcript, and named laws that are checked like ordinary tests. The first two
are embedding APIs used from Zig and have no compiler flag; the third is a script
over the guest test runner. The design records are
[execution observations and host replay](../experiments/execution-observations.md)
and [named executable laws](../experiments/guest-laws.md).

## Bounded VM traces

An embedding host sets `vm.Options.memory.trace` to a caller-owned
`vm_trace.Trace` with a fixed event buffer. Each event records the instruction's
source, function and program counter, the instruction name, and the top operand
as it stood before execution, so a branch exposes the Boolean condition that
selected it while an aggregate or owner records only its type identity. The
buffer is a ring of the most recent events: when it fills, the omitted events are
counted rather than silently dropped, and recording changes neither the guest's
instruction budget nor its work accounting and retains no guest allocations. The
compilation that supplied the source mapping must stay alive while the events are
interpreted. A trace is a bounded debugging sample of what ran, not a causal
proof and not a portable replay log. `src/vm_trace.zig` and its unit tests run in
the default Zig test root.

```sh
# src/vm_trace_test.zig runs as part of the default unit-test root
zig build test
```

## In-memory host replay

`host_replay.Transcript.wrap(name, binding)` wraps an explicit provider
registration before it is installed, so recording adds no authority the host did
not already grant. Run once to record, close the session, call `finish()`, then
`replay()` and run again; the adapter compares the ordered call names, argument
fingerprints and the checked record schema, returns deep copies of the recorded
outcomes or callback failures, charges the recorded cooperative work, and never
reinvokes the provider. A missing, extra, reordered or changed call is a
`HostReplayMismatch`, and a recording cut short by its caps or by allocation
failure cannot be replayed at all. Transcripts are single-threaded in-memory
debugging artifacts pinned to one checked schema: they are not portable receipts,
they are not sanitized logs, and the effects performed during the recording are
ordinary effects that replay does not roll back.

```sh
# src/host_replay_test.zig runs as part of the default unit-test root
zig build test
```

## Named executable laws

A law is an exported `test_` function returning `bool` that states a property of
the application, and a JSON configuration gives each qualified law an integer
domain per parameter. `scripts/laws.py` samples those domains with an explicit
seed, runs every sample through the schema-pinned guest test runner on a fresh
VM, and writes a `guest-laws-v1` report retaining the seed, the source snapshot
identity, the inputs, the outcomes and the source locations. A failing sample is
reduced within its supplied domains while preserving the failure category, and a
repeated campaign on the same snapshot draws the same inputs. Passing samples are
evidence, not a proof; reductions are counterexample candidates, not guaranteed
minimal ones. This generator covers bounded integer inputs only, and a source or
compiler change invalidates a campaign rather than mixing evidence across
versions.

```console
$ cat laws.json
{"main::test_sum_is_commutative": {"left": [0, 1000], "right": [0, 1000]}}
$ python3 scripts/laws.py app/main.my --compiler zig-out/bin/mylang \
    --laws laws.json --seed 17 --samples 20 --output report.json
{"passed": true, "cases": 20, "output": "report.json"}
```
