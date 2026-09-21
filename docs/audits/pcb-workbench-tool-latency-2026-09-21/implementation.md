# PCB workbench latency fixes

The compiler and workbench workflow now preserve useful warm work rather than
repeatedly forcing the same compilation and test execution.

## Changes

- Project `run` and `run-project` validate the current source graph, policy and
  capability grants, then reuse a checksum-validated emitted manifest before
  lowering or QBE emission. `--no-cache` bypasses this reuse. Explicit
  invalidation explanation still constructs and truthfully reports its lowering
  receipt. Executable identity also covers resolved QBE tools and LLVM adapter
  package, optimization and LTO settings.
- Native test identities use the canonical resolved import graph, configuration
  and policy rather than every neighboring source. Compiler/build environment
  controls remain inputs, while unrelated shell metadata no longer changes the
  frontend/object/result cache directory. Dynamic-loader overrides and tests
  with environmental effects remain conservative. Provider replacement verifies
  the broad inventory because a replacement can introduce new imports.
- Local deterministic mutation now permits positive-result reuse in both checked
  facts and emitted-code metadata. Real external effects still prevent reuse, and
  a declared mutation footprint still excludes signature-pure outcome replay.
- The workbench has one `all_test.my` suite covering 400 public tests across 21
  modules, a reviewed inventory guard, a cached default gate, qualified focused
  tests, and deliberate `--force` final acceptance. Snapshots are immutable and
  verified; each invocation retains separate JSON results and diagnostics and
  propagates the compiler's real exit code.
- A complete compiler/QBE/LLVM/runtime installation is pinned by content.
  `guest/build-app.sh` builds once per immutable source/compiler/tool/mode identity;
  `guest/pcb.sh` executes the resulting binary with preserved argument boundaries
  and the workbench step budget. Agent instructions explain managed background
  jobs and completion notices. Reports stay on disk; tools print compact,
  schema-checked summaries and preserve real exit statuses.

The external workbench has no Git repository. Its source changes are archived in
[workbench.patch](workbench.patch), alongside deployment and verification evidence.

## Cache correctness probes

[`scripts/verify_pcb_latency.py`](../../../scripts/verify_pcb_latency.py) runs in
private copies and preserves command arguments, source/compiler hashes, reports,
exit codes and timings. The original frozen installation is a negative control:
it fails the new reuse assertions exactly where expected. The final installation
passes all ten probes.

| Probe | Frozen compiler | Fixed compiler |
|---|---:|---:|
| Geometry cold, 15 tests | 3.385 s | 3.109 s |
| Geometry warm repeat | 0.392 s | 0.467 s |
| Change unused environment variable | 3.259 s; 15 executed | 0.473 s; 15 reused |
| Edit unreachable `png.my` | 0.468 s; one body checked | 0.458 s; zero bodies checked |
| Tiny project warm `run` | 3 functions lowered/emitted | zero functions lowered/emitted |

Changing the fixture dependency from 3 to 4 still reruns its affected test (which
correctly fails its expectation of 3) and changes the program output to 4.
These are individual wall-time observations on the same shared host, not
statistical estimates. A tiny warm run is dominated by startup; the work counters,
not its wall time, establish that lowering and emission were removed. Snapshot
capture and frontend validation still cost time on warm tests.

See [negative-control observations](verification/baseline-probes-observations.json),
[final observations](verification/final-probes-observations.json), and
[passing assertions](verification/final-probes-summary.json).

The frozen old serial gate completed in **472.494 seconds**, executing **2,085**
test instances for the same 400 unique public declarations. Both the old and new
gate measurements use `MYLANG_JOBS=2` and the same frozen application sources;
the new suite adds only its aggregate entry. See
[baseline result](verification/baseline-gate.json).

## Additional finding from full-suite verification

The first aggregate run passed all 400 cases in 218.553 seconds, but an unchanged
rerun still took 86.078 seconds: 267 cases were marked `external-effects` solely
because their helpers mutate local state. The earlier geometry-only probe did
not expose this. The shared deterministic-effect mask now includes process-local
mutation. A native regression requires a mutating test to reuse its receipt while
a test that writes output executes again; the dedicated native root passed all
150 tests. This preserves the strict signature rule for `--pure-skip`. See
[the discovery summary](verification/before-mutation-fix-suite-summary.json).

## Full workbench suite

The deployed, pinned toolchain passes all 400 unique tests. No application test
declarations were removed or changed.

| Gate | Wall time | Executed | Reused |
|---|---:|---:|---:|
| Original serial forced gate | 472.494 s | 2,085 | 0 |
| New aggregate gate, forced fresh | 208.035 s | 400 | 0 |
| New aggregate gate, first warm | 10.144 s | 0 | 400 |
| New aggregate gate, warm repeat | 5.229 s | 0 | 400 |

The new fresh acceptance is about 2.3 times faster. For an unchanged iteration,
the cached gate is about 90 times faster than the old always-forced workflow.
These measurements ran before the broader compiler checks, using two workers;
they are individual observations rather than a statistical benchmark. Full
fresh execution still takes about 3.5 minutes. See
[suite counters](verification/final-suite-summary.json).

The final compiler pin, after extending the environment input list, was checked
again with the compact-output wrapper. Fresh execution passed 400/400 in 246.622
seconds while the compiler test suite also ran; warm checks reused all 400 cases
in 10.356 and 5.390 seconds. The warm tool output is now **544 bytes**, with the
complete 2,342,216-byte native report retained on disk. The wrapper verifies
nonempty, uniquely named test records and exact status/count agreement before
printing success. See [final deployed suite](verification/accepted-suite.json).

## Compiler acceptance

All required checks pass on the final compiler: `zig build test`, `test-qbe`,
`test-qbe-build`, and `fmt-check`. The native QBE gate reports 263 passing cases.
The standalone audit analyzer passes all 22 tests. See
[compiler checks](verification/accepted-compiler-checks.json).

A final cache-key review retained inherited C search/link controls, Python
adapter controls, Zig installation overrides and reproducible-build settings.
The focused environment regression passes 12 cases, including changed
`C_INCLUDE_PATH` and `PYTHONPATH`. After rebuilding and pinning that final
compiler, all ten private cache/invalidation probes pass again; see
[final-pin assertions](verification/release-probes-summary.json) and
[final-pin identity](verification/release-probes-manifest.json).

## Large application backend

The first full application build exposed a QBE limitation: `extract::report_real`
generates a 10,636,907-byte unit. An isolated reproduction exhausted a 4 GiB
address-space limit in 5.54 seconds; LLVM compiled the same input successfully
at O0 and O3/LTO, using about 916 MiB and 732 MiB peak RSS respectively. The
original full QBE build failed under the compiler's inherited 8 GiB limit.
See [bounded unit probes](verification/large-unit-probes.json).

The workbench application wrapper therefore defaults to LLVM O3/LTO, with
`PCB_BUILD_MODE=debug` selecting LLVM O0. It limits compilation to two CPUs from
the current allowed affinity set (`PCB_BUILD_JOBS` can change that bound),
serializes identical builds, and caches the published executable. Native object
cache directories and executable keys include relevant build-environment inputs;
the latter also include an explicit build-recipe version. The full compiler and
QBE remain pinned for native guest tests.

The complete cold LLVM application build succeeded in **434.492 seconds** with
two CPUs. Subsequent operations used the same executable path, content hash and
modification time:

| Operation | Wall time | Result |
|---|---:|---|
| Reuse application build | 0.115 s | cached executable |
| Help | 0.116 s | usage on stderr; exit 0 |
| Status | 0.115 s | valid JSON; exit 0 |
| Observe | 0.165 s | valid JSON; exit 0 |
| Evaluate | 0.115 s | valid infeasible report; expected exit 3 |
| Unknown command | 0.115 s | expected usage exit 2 |

The CLI checks used a private journal whose path contains spaces. The production
journal was not touched. See [CLI measurements](verification/accepted-cli.json)
and [artifact identity and assertions](verification/accepted-cli-artifact.json).
A separate [concurrent cold-build fixture](verification/concurrent-build-check.json)
issued two simultaneous requests, invoked the compiler once, and returned the
same executable path to both callers.

Cold application builds remain expensive. These changes remove repeated work
from unchanged tool calls; reducing native emission and code generation after
source edits remains a separate performance opportunity. The initial suite
comparison and final acceptance conditions are recorded above so concurrent
compiler-test load is not mistaken for a compiler regression.

All implementation changes are committed. Guardian's whole-tree commit gate
passed all 88 checks; see [gate output](verification/guardian-whole-tree.log).
The external workbench patch was checked against the frozen original files with
`patch --dry-run -p1`. Resume agents using the workbench's updated `AGENTS.md`,
leave `MYLANG` unset for the pin, and use `guest/gate.sh` / `guest/pcb.sh`.
