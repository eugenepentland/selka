# PCB warm gate: compiler build mode

The 5.75-second cached PCB gate was using a **Debug build of the compiler**.
Even when every native test receipt hits, Mylang still discovers interfaces,
validates the project, plans each test's dependencies, verifies receipts and
source stability, and writes its report. Debug compilation makes this CPU work
expensive. It is separate from the guest application's LLVM O3/LTO setting.

The same compiler source built with `-Doptimize=ReleaseFast` reduces warm PCB
gates to approximately **0.85 seconds** in the initial comparison. A second real
Git worktree reused all 400 test receipts in **0.823 seconds**. Final alternating runs after the background builds finished measured
**0.811, 0.676 and 0.739 seconds** in the deployed checkout, versus **5.183 and
5.213 seconds** for the old Debug pin. This is approximately seven times faster
in the same comparison. No result-cache rules or compiler source code changed.

## Diagnosis

The original pinned executable is byte-identical to `zig build`'s default Debug
output; [the build summary](verification/debug-build.log) and
[binary hashes](verification/debug-binary-hashes.txt) establish its build mode.
The Debug and ReleaseFast generated source-asset manifests differ only in the
optimization-dependent compiler and native-driver identities. Both use production
source commit `69260c329b9ffee914f934374bcf8e31c2311532`.

A process trace of the Debug gate recorded:

| Traced phase | Wall time |
|---|---:|
| Entire wrapper | 6.180 s |
| Mylang test process, including children | 5.664 s |
| Interface discovery child | 1.288 s |
| Cached project-validation child | 0.509 s |
| Parent after validation: planning, receipts, verification and report | 3.215 s |

These trace timings include tracing overhead and should only be used to locate
work. Untraced interface discovery alone measured 0.615–0.618 seconds with Debug
and 0.075 seconds on the second ReleaseFast run. The native work report records
22 modules parsed, zero checked bodies, zero lowered/emitted functions, zero
links, zero executed tests and 400 reused tests.

The parent also repeats avoidable work per test:

- `native_test_plan.plan` rebuilds the complete function-symbol index for each
  case, then traverses and hashes its dependency closure.
- `native_test_command.planSelectedCases` serializes/hashes the same module's
  contract for each test in that module.
- Schema and exported-symbol lookups scan arrays again for each selected case.

These remain opportunities for invocation-local indexing and memoization. The
optimization in this rollout is the compiler build mode; the validation and
receipt checks continue to run.

## Verification

The first run under the new pin executed and passed all 400 PCB tests in
183.492 seconds. Subsequent warm measurements were 1.624 seconds immediately
after the cold run, then 0.848 and 0.854 seconds. Alternating Debug control runs
took 7.138 and 7.188 seconds while other validation/build work was active.
These are observations on a shared host, not statistical performance guarantees.

- All 150 native-test runner checks passed in ReleaseFast mode.
- All ten private cache/invalidation probes passed, including changed dependency
  behavior and unchanged-source/environment reuse.
- The required `test`, `test-qbe`, `test-qbe-build` and `fmt-check` targets passed
  together: 96/96 build steps succeeded. The large skipped count in the combined
  Zig report includes nonselected cases repeated across test shards.
- A separate actual Git worktree reused all 400 receipts without local compiler
  installation or test execution.

## Rollout

The optimized installation is registered in the existing shared store as
`18971074cb0b1993a57482a93776ce94f9dc39efe30f63de496d66c8fb22df12`.
The live PCB checkout now uses this pin. Its LLVM O3/LTO application was rebuilt
successfully in 379.869 seconds before deployment, then verified with help,
status, observe, evaluate (expected exit 3 for the infeasible board), and an
unknown command (expected exit 2), using private journals. The deployed wrapper
reuses that new executable immediately. Cold native builds still take minutes.
The old Debug installation and its cache remain available to old pins. Agent
instructions now require building application toolchain installations with
`zig build -Doptimize=ReleaseFast --prefix /path/to/install`, verifying them,
then registering that complete installation. Default developer builds retain
their existing Debug setting.

Evidence is in [verification/](verification/), including complete compressed
native reports, the process trace, alternating gate timings, compiler build logs,
the ReleaseFast native-runner acceptance, and the ten-probe results.

The external PCB folder has no Git repository. Its pin and instruction changes
are archived in [workbench.patch](workbench.patch); apply after the shared-cache
changes with `git apply --unidiff-zero workbench.patch`. The deployment manifest
records the exact live hashes. Mylang's `CLAUDE.md` also documents the optimized
compiler installation command for future application-agent toolchains.
