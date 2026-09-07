# Workflow planner: `.my` construction baseline

This is an independent, **unscored construction baseline** for
`contracts/workflow-planner-v1.md`. It has not read the coordinator oracle,
other language baselines, or hidden cases.

Run from the mylang repository:

```sh
zig-out/bin/mylang-io --project experiments/application_comparison/baselines/planner/my < request.json
python3 experiments/application_comparison/baselines/planner/my/test_cli.py
```

The installed executable loads these sources on every invocation. No compiler
rebuild is needed. Application dependencies are only the `.my` runtime and the
three raw byte operations in `io.my`: input length, input byte, output byte.
Python is used exclusively for independent subprocess tests; it is not imported, launched, or otherwise needed by the application.

## Structure

- `main.my` validates the entire request before publishing any results.
- `json.my` owns JSON syntax, depth, decoded-key uniqueness, UTF-8 and escapes,
  signed 64-bit integer bounds, finite decimal-number validation, source-offset
  comparisons, and output primitives. JSON values remain as offsets into the
  immutable byte stream; identifiers are compared by decoded codepoints.
- `schema.my` validates exact envelope/manifest/job fields and bounded arrays.
- `planner.my` sorts identifiers with heapsort, resolves names with binary search,
  completes each error phase, detects blocked jobs, and separately computes
  lexicographic topological order, synchronous layers, and critical-path times.
- `output.my` holds fixed report punctuation and error messages.
- `test_cli.py` contains independent expected results and boundary tests.
- `stress_cli.py` preserves upper-bound graph resource reproducers.

The guest intentionally retains no rich host-side representations. Graph storage
is bounded by the contract: six 128-element owned working buffers and a 16,384-element
owned scratch buffer (the maximum number of dependency references). Allocator authority enters through main; checked acquisition and resize failures
return a nonzero status so the host discards buffered output. Schema validation
finishes before graph buffers are allocated. Temporary dependency sorting uses a separate 128-element scratch
buffer; source-order permutations therefore cannot change report order.

Decimal floats are parsed without a floating-point type. A normalized decimal
exponent detects gross overflow; the maximum exponent is compared exactly against
the round-to-nearest binary64 overflow midpoint. Underflow and signed zero remain
finite. Escaped UTF-16 surrogate pairs decode to a codepoint; unpaired escaped
surrogates reject the entire request, following the clarified scalar-value contract.
Raw UTF-8 surrogate encodings, overlong forms, and out-of-range scalars reject.

## Validation and limits

The independent suite covers the public example, empty graphs, all validation
phases, downstream cycle blockage, numeric/UTF-8/escape errors, decoded duplicate
keys, nesting 64/65, 64/65 manifests, 128/129 jobs, and a reversed 128-job chain.
All ten test groups pass using the installed raw byte host. This is construction
validation, not scored evaluation or a claim about unseen cases.

The parser rescans prior object members when checking duplicate keys, which can
be quadratic for large schema-invalid objects. Graph name operations repeatedly
read input bytes through the bridge. These are performance risks for adversarial
near-1-MiB requests; no schema or transport limits have been reduced to hide them.
Coordinator quotas still need feasibility review before a scored cohort is frozen.

## Construction resource evidence

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
