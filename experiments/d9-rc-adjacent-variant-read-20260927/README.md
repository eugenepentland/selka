# Adjacent variant-read evidence

`identity.json` binds the Debug compiler to merged source `680b857e` plus the
exact `source.patch.gz`. The patch includes production code, SPEC coverage and
permanent tests. The before compiler is immutable joined `5b876012`. Both use
the same runtime; the separate native type-fact cache is not present here.

Run `python3 experiments/d9-rc-adjacent-variant-read-20260927/verify.py` to verify
archived evidence. Drivers preserve original absolute compiler, cache, source
and binary paths. They are reproduction records, not portable turnkey scripts.
Actual LLVM builds explicitly select `--backend=llvm --llvm-opt=3 --lto`.

`validation-ordinary-gc.json.gz` is retained with corrected labeling: the first
driver used unrecognized `MYLANG_GC_STRESS=1`, so those four GC runs were ordinary
GC. `validation.json.gz` reruns all eight combinations using the supported
`MYLANG_OPTIONS=--gc-stress` for GC. Neither historical receipt is relabeled.

The step sweep contains 1,440 native executions (704 actual step traps, with
remaining budgets completing normally); eight more executions check bounds.
The before/after status and stdout match for every budget within each runtime
and backend. The fixed trap driver expected the wrong diagnostic spelling on
its first bounds row (`R_INDEX` instead of actual `R_LIST_BOUNDS`); the completed
step receipts were preserved and only the pending bounds matrix resumed.

The deep retain probe is an internal C ABI test. It calls the generated pool
constructor, owns that returned list in a construction journal, clamps the
existing heap budget, then calls an admitted deep variant match. Workspace
allocation for the selected-payload retain refuses on the candidate; the
baseline refuses its earlier redundant whole-value loan. Both report
`R_MEMORY_BUDGET` and unwind the pool with balanced counts. No forged resource
or finalizer-bearing value is admitted. Existing ordinary payload publication
and generic runtime partial-retain rollback are unchanged.

`reduced.json.gz` covers N4/N5 diagnostics. `full.json.gz` uses the original
mandated N10 script and expected output unchanged. Each includes counted runs
and interleaved median-three production instruction runs on CPU10, preserving
raw `cpu_core/instructions/u` event runtime and 100% running fractions.
The outer timing wrapper's RSS includes the perf process and is kept as raw
process-tree evidence only. No separate direct guest RSS run was performed:
root explicitly deferred that matrix to the combined full-corpus candidate,
since this slice does not change allocation counts/layout. There is no guest-RSS
acceptance claim here.

No full-suite acceptance or default transition is claimed. The accepted GC
baseline is unchanged; this slice must be integrated and measured with the
other independent work before judging whole-corpus requirements.
