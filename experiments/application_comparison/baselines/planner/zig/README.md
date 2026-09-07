# Workflow planner — independent Zig baseline

Implements `workflow-planner-v1.md` with the pinned Zig standard library only.
Constructed directly from that contract without reading the coordinator oracle,
coordinator fixtures, or another baseline implementation. This is construction
validation, not a scored trial or a claim about comparative language quality.

Pinned compiler: `0.17.0-dev.1683+5ceec001b` at
`/home/epentland/.local/bin/zig`.

From this directory:

```sh
/home/epentland/.local/bin/zig build-exe main.zig -O ReleaseSafe -femit-bin=planner
/home/epentland/.local/bin/zig test main.zig -O Debug
printf '%s\n' '{"cases":[{"version":1,"jobs":[]}]}' | ./planner
```

The executable reads one complete JSON byte stream from stdin and writes one
JSON response followed by a newline. Defined request and manifest errors exit
zero. Operating-system I/O failures and allocation failures are operational
errors and may exit nonzero. No files, subprocesses, or network are used by the
application.

A string-aware structural scan enforces maximum container depth 64 before
parsing. The JSON parser rejects duplicate keys and retains numeric lexemes. A separate
iterative traversal enforces whole-request numeric limits before envelope and
manifest validation. Each manifest completes schema, duplicate-ID,
duplicate-dependency, and unknown-dependency checks in order. Jobs are sorted
once by ASCII ID; a bounded adjacency matrix supports deterministic ready-node
removal, critical-path timings, and a separate synchronous-layer pass. A failed
removal pass reports every remaining blocked job, including cycle descendants.

All input, parsed values, and output values live in a per-request arena until
encoding completes. `respond` expects an arena allocator and borrows identifiers
from its parsed input storage. Graph storage is bounded by the contractual 128
jobs; the input limit is 1 MiB. Parsing and whole-request number validation are
iterative, including when schema-invalid JSON contains deep nested structures.

Independent Debug tests cover parsing errors, decoded duplicate keys, Unicode,
i64/float limits, type distinctions, validation precedence, sorted distinct
findings, zero-duration critical paths, cycle descendants, input/case/job limits,
container-depth boundaries, and maximum-chain timings. CLI smoke checks also exercise the actual byte-stream
transport. Guardian wiring and comparative evaluation belong to the coordinating
workflow and are not included in this standalone baseline.

Guardian integration now lives in `guardian.toml` and `SPEC.md`; implementation
is under `src/` with the original root compile/test entry retained. The main trial
uses the coordinator [trusted adapter](../../../guardian_policy/README.md), which
passes Guardian, Debug tests, ReleaseSafe compilation and isolated conformance.
The standalone commands above remain language-only commands.
