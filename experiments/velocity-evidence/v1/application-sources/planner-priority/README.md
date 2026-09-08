# Workflow planner: `.my` construction baseline

This is the **unscored, library-prepared baseline** for
`contracts/workflow-planner-v1.md`. Its original construction was independent;
the 2026-09-07 parity migration reviewed comparator source and public contracts.
No timed trial or hidden-task acceptance is implied. Historical construction and
calibration evidence remains under its original source/compiler identities.

Run from the mylang repository:

```sh
zig-out/bin/mylang-io --project experiments/application_comparison/baselines/planner/my < request.json
python3 experiments/application_comparison/baselines/planner/my/test_cli.py
```

The installed executable loads these sources on every invocation. No compiler
rebuild is needed. Application dependencies are only the `.my` runtime and the
three raw byte operations in `io.my`: input length, input byte, output byte.
Python is used exclusively for independent subprocess tests; it is not imported, launched, or otherwise needed by the application.

## Structure after library preparation

- `main.my` reads bounded bytes with `std_text::read`, parses once using
  `std_json::parse`, and validates the envelope before publishing results.
- `json.my` contains application identifier predicates, thin standard-library
  query/output adapters and quoting for schema-approved ASCII identifiers.
  It no longer implements a JSON parser, UTF-8 decoder or decimal formatter.
- `schema.my` validates exact envelope/manifest/job fields and bounded arrays
  through checked `std_json_view` required fields, integer/count bounds, and
  subtree-skipping cursors. Parser errors still precede schema validation.
- `planner.my` resolves names, completes ordered validation phases and computes
  priority-aware ready-job order, synchronous layers and critical-path times.
  Its bounded scratch buffers use `std_collections::filled`; borrowed-context
  `sort_by`/`lower_bound_by` order JSON node IDs directly, while `std_graph` handles
  dependency readiness.
- `output.my` holds the fixed application report punctuation and error messages.
- `test_cli.py` retains independent construction expectations and adds migration
  boundaries; `stress_cli.py` preserves upper-bound resource reproducers.

The immutable JSON tape keeps decoded strings and typed numbers. General
transport validation is supplied by the standard parser: strict scalar UTF-8,
paired surrogate decoding, decoded duplicate-key rejection, signed 64-bit integer
bounds, depth 64, and finite binary64 decimals including extreme underflow.
The bounded `std_format` decimal parser is not used here. This migration does not
move any planner policy into a native host bridge.

Six owned graph buffers cover up to 128 jobs and 16,384 dependency references.
A `Job` record groups each duration, needs node and earliest finish. Whole slices
and grouped borrows acquire the six independent buffers in one lexical block.
IDs and sorting scratch hold plain JSON node indices. Readonly document context
supplies comparisons without per-ID text descriptors. State is sized to the
actual job count, and `std_graph::Edge` storage to the actual reference count.
`std_ascii::matches` recognizes the exact bounded identifier pattern. The input is capped at 1 MiB; JSON tape storage is separately bounded
by the standard parser. Allocation failure remains a nonzero application status
for scratch allocation so the host discards buffered output. Input/parser errors
produce the contract's whole-request error before any result publication.

## Validation and limits

The independent suite covers the public example, empty graphs, all validation
phases, downstream cycle blockage, numeric/UTF-8/escape errors, decoded duplicate
keys, nesting 64/65, 64/65 manifests, 128/129 jobs, and a reversed 128-job chain.
The original ten groups passed after the parser migration using the installed
raw byte host; current migration evidence is recorded in
[the parity audit](../../../../../docs/experiments/planner-stdlib-parity.md). This is construction
validation, not scored evaluation or a claim about unseen cases.

The historical parser's quadratic duplicate-key rescanning no longer applies.
The current baseline still needs the full coordinator resource/isolation review
and a frozen library-readiness matrix before timing. Passing public checks alone
is not evidence of speed, low defect rates or scored readiness.

## Historical construction resource evidence (pre-migration)

The preserved `stress_cli.py` maximum-distinct-unknown case contains 128 jobs with
128 distinct missing references each (16,384 report IDs). During the initial
fixed-array implementation, it timed out after 180 seconds; a subsequent run was
killed with exit -9 and no guest diagnostic. Dense-cycle sorting on the original
16,384-element fixed scratch backing was also killed (-9). These observations
motivated replacing graph storage with owned buffers and mutable slices rather
than reducing any contract bound. Concurrent construction activity makes these
initial timings unsuitable as comparative benchmark measurements.

An initial `probes/buffer/main.my` omitted `import io` and its declarations and
returned `mylang-io: HostUnknownFunction`, exit 1. That result did **not** establish
an allocator limitation: the coordinator identified that the raw host requires
its registered `io` declarations. The corrected probe includes them, accepts
allocator authority, acquires/resizes a 16,384-element owned buffer, mutates a
slice, and exits zero. The application now uses this supported allocation path.
No compiler or bridge changes were made.

After the owned-buffer change, the same stress driver passed both cases:
dense 128×128 cycle in 9.747 seconds (all 128 blocked IDs), and all 16,384 distinct
unknown references in 17.222 seconds (147,508 response bytes). Both exited zero
without stderr. The ten independent test groups also passed in 2.809 seconds.
These runs resolve the observed graph-storage feasibility failure; pathological
JSON-object rescanning remains a documented performance risk.


## Development workflow migration

The current v1 source uses direct byte-string arguments for fixed JSON output,
checked schema queries and cursors, and whole/grouped borrows. These edits remove
output-string borrow blocks and the eight-level storage borrow staircase. JSON
node IDs sort through an explicit readonly document context using in-place
heapsort (O(n log n)); binary lookup uses the same comparator. No per-ID text
descriptors remain. Across the six application `.my` files, source shrank from
661 to 619 lines: output 135→78, planner 346→319, schema 54→96; io/json/main
retain their original line counts. This is a source-change inventory, not a
productivity measurement. The
planner retains explicit validation phases and scheduling policy; input limits,
ASCII ordering, output fields, error precedence and unlimited-worker scheduling
are unchanged. This baseline accepts string dependencies only; delayed edges,
latest starts and slack remain separate product changes. The original
`std_text::read(heap, 1048576)` transport-limit site is preserved in `main.my`.

`verify.json` declares the portable CLI contract suite and complete resource
checks. The existing launcher uses `MYLANG_IO` when explicitly supplied, then
`/tools/byte_io` in isolation, or the nearest built checkout. Run from the language
checkout:

```sh
python3 scripts/verify.py experiments/application_comparison/baselines/planner/my/verify.json
```

In a workflow trial container, one command checks the project and runs the
manifest while retaining source/compiler identities and verification output:

```sh
python3 /tools/workflow/project.py --compiler /tools/compiler \
  --entry /work/main.my --manifest /work/verify.json \
  --cache-dir /cache/project --report /cache/attempt-001.json
```

Choose a fresh report path for each attempt. Stress checks fail on nonzero host
status, timeout, or any difference in the complete blocked/unknown ID list. The
additional schema regression cases cover absent required fields, null/wrong
kinds, nested values, and schema precedence over graph errors. Historical
construction measurements above remain separate from this migration.

## Optional job priority

Jobs accept an optional integer `priority` in [-1000, 1000], defaulting to zero.
Every original field remains required and other fields are rejected. Priority
uses strict JSON integer validation; transport still rejects duplicate keys.

The planner selects the highest-priority ready job after each removal, breaking
ties by ASCII ID. Dependencies always constrain readiness. Layers, timings,
makespan and error report arrays preserve their original semantics.

Run `python3 -B /work/test_priority.py` for priority regressions, or select
`cli*` in the combined workflow to run both CLI suites.
