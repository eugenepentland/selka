# Full SVG slowdown audit

See [findings and priorities](../../docs/audits/svg-slowdown-drivers-2026-09-21.md).
This directory contains isolated probes; production code is unchanged.

The audit reuses the qualified inputs and original binaries from
[`full-svg-benchmark`](../full-svg-benchmark/README.md). Candidate executables
are under `.tmp/svg-slowdown-20260921`; `audit_run.py` records their exact paths
and verifies expected original/changed SVG hashes on every execution.

| Evidence | Purpose |
|---|---|
| `measurements.json` | 13 arms × 31 randomized rounds, output qualification, medians and paired intervals |
| `phases.json` | Coarse CPU phase timings, allocations, collections, logical steps and relink calibration |
| `sampling.json` | Unchanged-binary self-PC samples, exact hot addresses and explicit outside/unmapped counts |
| `raw-samples/`, `provenance.json` | Compressed raw PC samples, input/binary verification and machine state |
| `sample.c` | Userspace SIGPROF sampler, no allocations in the signal handler |
| `host/` | Scalar boundary probe, exact host counts, qualified control and source/build provenance |
| `algorithms/` | Source analysis, pin-index diff, bounded/unbounded build recipes and qualification |
| `lto/` | Guest/runtime isolation, diagnostic target-feature adapters and disassembly evidence |

The final measurements supersede the agent directories' explicitly labeled
exploratory timing records. Do not compare independently sampled exploratory
numbers as though they came from the final paired batch.

After restoring the recorded baseline and diagnostic artifacts:

```sh
python3 experiments/svg-slowdown-20260921/audit_run.py time
python3 experiments/svg-slowdown-20260921/build_phases.py
python3 experiments/svg-slowdown-20260921/audit_run.py phases
cc -shared -fPIC -O2 experiments/svg-slowdown-20260921/sample.c \
  -o .tmp/svg-slowdown-20260921/sample.so -ldl
python3 experiments/svg-slowdown-20260921/audit_run.py sample --samples 200
```

Run each sequentially after all builds finish; scratch SVG/issue paths are
shared. Profiling does not change CPU governor, affinity policy, or perf
permissions. `audit_run.py` pins child processes to CPU 6 and uses seed
20260922. This seed is an arbitrary repeatable value, not the audit date.
The original full benchmark remains a separate retained artifact.

`build_phases.py` links original per-function objects and the original runtime
archive, adding wrappers only around six selected guest functions (the parser
is called three times) and heap teardown. The release entry point skips the
final heap sweep, so the usable heap statistics come from the main-function
wrapper before exit. C ABI wrappers use the original result shapes. The phase
build uses the system linker; its control timing drift is recorded rather than
silently treating it as the original executable.

`sample.c` loads only into dynamic mylang binaries. It requests a 500 µs
process-CPU timer; kernel tick granularity limits the effective rate. The
first expiration varies by PID to reduce repeated-start alignment. PC data
are mapped against each binary's own symbol addresses and manifest names.
This is self-PC sampling without call stacks, hardware events or cycle counts.
SVG hashes are checked after all 1,000 profiled runs. Raw PC records are retained
in `raw-samples/*.gz` and `.tmp/svg-slowdown-20260921/samples-*.txt`; summaries retain every function
count and the 25 hottest individual instruction addresses.

No diagnostic adapter should be installed as the production compiler. In
particular, the AVX2 experiments establish the target-feature mechanism only
on this CPU; production must honor an explicitly selected portable/native
target and include that selection in cache identity.
