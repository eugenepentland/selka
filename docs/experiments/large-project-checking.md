# Larger-project incremental checking measurements

The deterministic `scripts/profile_large_project.py` generates independently
imported modules containing scalar call chains. Every function participates in a
checked call graph. It measures cold subprocess checks, unchanged successful
verdict reuse in one process, and alternating edits to one module's arithmetic.
It executes no guest code during timing. This is a controlled synthetic workload,
not a claim about all application features or CI throughput.

```sh
python3 scripts/profile_large_project.py --compiler zig-out/bin/mylang \
  --modules 96 --functions 24 --repeats 7 --output /tmp/large-check.json
```

| Workload / retention | Cold median | Exact warm median | Edited median | Edited p95 |
| --- | ---: | ---: | ---: | ---: |
| 49 modules, 1,201 functions; 64 entries | 10.40 ms | 1.29 ms | 5.06 ms | 5.38 ms |
| 97 modules, 2,401 functions; 64 entries | 18.79 ms | 2.40 ms | 15.33 ms | 16.15 ms |
| 97 modules, 2,401 functions; 256 entries | 18.50 ms | 2.31 ms | 11.34 ms | 11.73 ms |

Evidence is in `experiments/large-check-48.json`, `large-check-96.json`, and
`large-check-96-retained.json`, including all samples, source identities, compiler
hashes, and cache counters. Both compiler versions use pinned Zig
`0.17.0-dev.1683+5ceec001b`, x86_64 Linux and ReleaseFast. Other compiler features
also changed between binaries, so timing differences are observations rather than
an isolated causal estimate for one line of implementation.

The cache counters expose a specific issue: loading 97 modules into a 64-entry
oldest-insertion cache continually evicted modules before their next lookup. Every
edited check had 97 parse misses despite only about 1.83 MiB retained under its
16 MiB limit. The default entry capacity is now 256, matching the default project
module limit, with the same 16 MiB byte bound. The edited workload retains at least
96 unchanged-module parses; after both alternating source versions are retained,
all 97 parse lookups hit. Full semantic checking still runs for each changed source
snapshot. The final retained arenas occupy about 2.80 MiB.

A 97-module differential regression compares cached and uncached execution results
and semantic diagnostic codes through successful edits, an invalid edit, and a
repair. It checks unchanged-module parse hits, eviction behavior, and the byte
bound. Allocation-failure and ownership tests for the cache remain in place.

Finer semantic-body verdict reuse remains deferred by measurement: these workloads
check edited projects in roughly 5–15 ms, and the observed avoidable issue was parse
retention capacity. Cross-module contracts, generic constraints, effects, cleanup,
and source locations still need fresh semantic validation after changes. More
complex dependency keys are not justified by these measurements alone. Continue
profiling real projects, especially rich generic instantiations and generated code,
before treating this synthetic result as representative.

> **Current status (2026-09-16):** the "deferred by measurement" conclusion belongs
> to these measurements. C1-C4 have since added per-function checked-body reuse,
> symbolic-template and concrete-specialization replay and receipt-first native-test
> selection; the tables above are preserved as the evidence that justified the
> syntax-cache capacity change. See
> [development velocity implementation status](../audits/velocity-implementation/final-status.md).
