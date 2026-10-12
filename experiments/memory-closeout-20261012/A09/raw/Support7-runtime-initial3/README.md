# Initial Support7 paired runtime observations

Array, object and record each complete two warmup plus nine measured alternating
pairs:66exact-output runs, with counters disabled, matched inputs and CPU10.
Both artifacts and raw samples are pinned in results.json. Source bed11cf3 is
an intermediate candidate with known release-inventory/cache blockers; these
results do not qualify C1 or any later milestone.

The next cheap-map window never began: its admission wrapper waited180s for a
long build to drain. A08 needed ordinary admission for a critical cache diagnosis,
so A09 stopped the owning orchestrator, verified no measurement/guest child,
and canceled only that unadmitted wrapper. The log is preserved. No guest
sample was interrupted, and no timing request remains queued from this attempt.

These are process-wall observations only. Corrected separate guest RSS runs
have not yet run. Record paired ratios overlap1; it has no firm saving claim.
