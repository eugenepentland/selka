# Workflow dependency planner — small baseline v1

Status: implementation contract, pending independent review and cohort freeze.
This defines the same application behavior for `.my`, Python and Zig. The oracle
is coordinator tooling, never an application dependency or participant tool.

## Transport and schema

Read one UTF-8 JSON request from stdin; write one JSON response to stdout and exit
zero for both valid plans and defined input errors. Stderr may contain diagnostics.
Object key order and whitespace are immaterial; array ordering is contractual.
The request is `{"cases":[manifest,...]}` with at most 64 manifests. The response
is `{"results":[result,...]}` in input order. An invalid envelope produces
`{"error":"invalid-request"}`. No partial results accompany an invalid envelope. All decoded JSON string values
and object keys must consist of Unicode scalar values: unpaired UTF-16 surrogate
escapes produce whole-request `invalid-request`; a valid surrogate pair is accepted
by transport (and may subsequently fail the application schema). JSON container nesting is
limited to 64: the root object counts as depth 1, each nested object/array adds 1,
and delimiters inside strings do not count. Exceeding this limit produces
`invalid-request`, including in content that would otherwise fail manifest schema.

A manifest has exactly `version` and `jobs`; version is integer 1. Jobs is an array
of at most 128 objects, each having exactly `id`, `duration`, and `needs`.
Identifiers match `[a-z][a-z0-9_-]{0,31}`. Duration is an integer in [0,1000000].
Needs is an array of at most 128 identifiers. JSON booleans and floats are not
integers. Extra keys, missing keys and wrong types are schema errors. Duplicate
JSON object keys, nonfinite numbers, invalid UTF-8, malformed JSON, or an input
larger than 1 MiB produce `invalid-request` for the whole request. Input integers
outside signed 64-bit range also produce `invalid-request`, wherever they occur.
No external files, subprocess domain helpers, network or third-party libraries.

## Validation order

Each manifest independently returns the first applicable error below. Complete
one validation phase before the next, irrespective of source job order.

1. Schema: `{"error":"invalid-manifest"}`.
2. Repeated job IDs: `{"error":"duplicate-id","ids":[...]}` listing distinct
   repeated IDs in ASCII ascending order.
3. Repeated dependencies within a job: `{"error":"duplicate-dependency","jobs":[...]}`
   listing affected job IDs once in ASCII order.
4. Missing dependencies: `{"error":"unknown-dependency","ids":[...]}` listing
   distinct referenced IDs absent from the manifest, in ASCII order.
5. Cycles: `{"error":"cycle","blocked":[...]}` listing all jobs that cannot be
   removed by repeatedly removing jobs with no remaining prerequisites, in ASCII
   order. This includes downstream jobs blocked by a cycle; self-dependency is a
   cycle. Do not return a partial successful plan.

The order of jobs and dependencies in an otherwise equivalent input cannot
change its result.

## Successful result

Return `{"order":[...],"layers":[[...],...],"timings":[...],"makespan":N}`.

- [PLANNER-ORDER] `order`: a topological order choosing the ASCII-smallest *currently ready* job
  after each individual removal. It is not necessarily flattened `layers`.
- [PLANNER-LAYERS] `layers`: synchronous dependency rounds. Each round contains all currently
  ready jobs, sorted by ID. Remove the whole round before selecting the next.
  Durations do not affect these layers.
- [PLANNER-TIMINGS] `timings`: one `{"id":ID,"start":N,"finish":N}` per job, sorted by ID.
  With unlimited parallel workers, start is the maximum finish of prerequisites,
  or zero for a root; finish is start + duration. A zero-duration job is legal.
- [PLANNER-MAKESPAN] `makespan`: maximum finish, or zero for the empty graph.

Example: jobs `z` (duration 5, no needs), `b` (2, no needs), and `a` (3, needs
`b`) yield order `["b","a","z"]`, layers `[["b","z"],["a"]]`, timings
`[{"id":"a","start":2,"finish":5},{"id":"b","start":0,"finish":2},
{"id":"z","start":0,"finish":5}]`, and makespan 5.

The small product owns parsing, schema validation, name resolution, graph
validation, ordering, layered planning, critical-path timing and report encoding.
Organize these into idiomatic maintainable code; there is no file/line-count quota.
Later resource scheduling, cancellation, artifact caching and version migration
are explicit product changes, not implicit features of v1.

## Grading and freezing

Public examples explain the contract. Hidden cases are generated from a frozen
coordinator-only seed after baselines are reviewed; public test seeds are never
used as hidden trials. Pin this contract, generator, oracle, seed and concrete
case payloads in the cohort receipt. Keep expected answers outside participant
mounts. Independent tests must challenge the oracle before scoring; passing this
oracle alone is not evidence of oracle correctness. No trial is launched by
writing this document or generating fixtures.
