# Integrated EDA exit-70 diagnosis

The unchanged board-layer module passes all three routes with the pinned
compiler, checked ownership, verified release and `MYL_CORE_LEAKCHECK=1`:

| Route | Result |
| --- | --- |
| Frozen original module, fresh private cache | 10 passed / 0 failed |
| Frozen integrated candidate module, fresh private cache | 10 passed / 0 failed |
| Originally cached candidate binary, ten rows in one native batch | 10 status-zero / true records; parent and children exit 0 |

A single-row replay also passes. The original cached executable was copied
before the coordinator moved its failed qualification into `eda-attempt1`.
Commands, compiler/source/binary hashes, decoded protocol results and raw trace
hashes are in `results.json`; compressed traces and input/response bytes are
retained here. All native invocations used normal shared admission.

The original full attempt had 184 passes and 133 `NativeTestProcessFailed`
exit-70 failures. Its exact cause is unproven. Runtime source distinguishes
those exits from a live-count mismatch: the leak-check branch records status 4
and exits 0; protocol, file-I/O and setup guards can exit 70. The filesystem had
only 518 MiB free during diagnosis, but no failed I/O was observed in the
successful replays, so disk exhaustion is not established as the cause.

These results support retrying the unchanged full candidate with a fresh cache
and more disk headroom. They do not classify all original 133 failures or weaken
the leak-check policy. Production sources and the compiler remain unchanged.
