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
  through standard JSON tape queries. Node zero represents a missing field.
- `planner.my` resolves names, completes ordered validation phases and computes
  the contractual lexicographic order, synchronous layers and critical-path times.
  Its bounded scratch buffers use `std_collections::filled`; `std_order` handles
  descriptor sorting/name lookup and `std_graph` handles dependency readiness.
- `output.my` holds the fixed application report punctuation and error messages.
- `test_cli.py` retains independent construction expectations and adds migration
  boundaries; `stress_cli.py` preserves upper-bound resource reproducers.

The immutable JSON tape keeps decoded strings and typed numbers. General
transport validation is supplied by the standard parser: strict scalar UTF-8,
paired surrogate decoding, decoded duplicate-key rejection, signed 64-bit integer
bounds, depth 64, and finite binary64 decimals including extreme underflow.
The bounded `std_format` decimal parser is not used here. This migration does not
move any planner policy into a native host bridge.

Eight owned graph buffers cover up to 128 jobs and 16,384 dependency references.
IDs and sorting scratch use `std_order::Item` descriptors, state is sized to the
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
