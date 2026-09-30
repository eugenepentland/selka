# Frozen A5 / publication invocation attribution

This is read-only Callgrind attribution for invocation30000, using approvedA5
80dd5190 and composed-publication3226f1d6. Both symbol-preserving relinks match
every allocated ELF section of their original measured binary, including
addresses, flags, sizes and payload hashes. Both runs exit0 and print30000.
The profiler ran under a build slot on CPU0. Its simulated counts are not
hardware samples, timings or performance acceptance.

| Function | A5 self instructions |3226 self instructions | Delta |
|---|---:|---:|---:|
| vm::run |600,472,757|621,139,405|+20,666,648|
| vm::load_frame |297,000,330|313,200,348|+16,200,018|
| a838 union loan glue |16,200,018|23,400,026|+7,200,008|

Total simulated instructions are1,485,034,501→1,530,070,906,
+45,036,405. These three functions account for44,066,674 of the net increase.
The exact per-function, instruction-address and call-edge counts are in
`exact-counts.json`; raw profiler records, original and relinked ELFs,
allocated-section receipts, full assembly, weighted hot-function assembly,
input and commands are in the48-member `raw.tar.gz`. Archive member hashes
have been independently re-read and verified against `archive-receipt.json`.
No native cache or duplicate corpus is archived.

`vm::load_frame` executes1,800,002 times. Its three pointer COPY sites each
change unchecked memory increment into load/increment/overflow-branch/store,
adding3 instructions per site:9×1,800,002=16,200,018, its exact net increase.
These MAX guards and atomic refusal are required and are retained.

The hot a838 union-loan path executes900,001 times and changes18→26 self
instructions, exactly+7,200,008. It now admits every acquisition before count
updates/copy, returns status, retains saturation fallback, and shuffles two
arguments for its native slow path. Its7-word conservative multiplicity bound
must still preserve repeated aliases/inactive tags/H-vs-O edges; this report
provides no authority to remove guards or publish before admission.

In `vm::run`, weighted minimum-int MOVabs counts rise120,095→11,490,099,
+11,370,004. A5 keeps INT64_MIN in a callee-saved register across hot checked
subtractions;3226 rematerializes it repeatedly. The comparison/refusal itself
is unchanged. The exact register-pressure or inlining cause is not established.
This measured code shape motivated the separate LLVM constant-overflow
continuation8a1bc3b3, whose proof/functional/source receipt belongs to its own
audit. No recovery is assumed until the root's composed all-row measurement.

Reproduction scripts retain the original isolated-worktree paths and exact
frozen compiler/binary SHA256 values in `inputs.json`. Extract `raw.tar.gz`
into an owned scratch directory before analysis; never reuse a sibling cache.
`analyze.py` re-derives exact totals from the raw records. Rebuilding/running
uses build-slot admission; hardware timing CPUs2,3,10,11 were never claimed.
