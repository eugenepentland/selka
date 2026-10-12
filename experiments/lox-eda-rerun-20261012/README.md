# Lox and EDA rerun after the text performance checkpoint

Status: rerun complete. All 60 cases were attempted; 59 checked-ownership cases
hit the calibrated timeout. Only `lox/tree/equality` completed: 0.539886 seconds,
2.791× Zig ReleaseFast, 2.671× Rust and 3.235× Go, with 10.05 MiB median child
peak RSS. All six reference/control arms completed all 60 cases. The timeout
does not establish an exact slowdown or a full-suite checked-ownership ratio.

All 120 RC control counter runs and the one eligible checked counter run passed,
with zero managed exit-live bytes. The checked run recorded zero RC/uniqueness
events, 38,129,545 allocations, 2,700,085,496 cumulative allocated bytes and
7,398,384 peak live managed bytes. The 59 skipped checked counter runs remain
explicitly unavailable. The report revalidated 1,702 unique runtime/counted input
identities and all 12 files in the frozen compiler installation.

[COMPARISON.md](COMPARISON.md) contains the fresh runtime, RSS and managed-memory
tables, plus historical Oct9/Oct12 comparisons. [per-cell.csv](per-cell.csv) and
[results.json](results.json) retain all cases, ranges, statuses and identities.
This run preserves the full 60-case denominator: 13 Lox tree cases, 13 Lox VM
cases, and 34 complete EDA designs. Application sources and workload sizes are
unchanged. No application or compiler optimization is part of this rerun.

The frozen compiler is the qualified common-002 installation from the text
checkpoint: source `8b7d59eba868775b1b8d7f64c54b07abdd23d470`, executable
SHA256 `2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329`.
Production source bytes match checkpoint `473a2c5585f10b208cb55ac43e096ece6b846b41`.
Each application has original RC, migrated RC, and migrated checked-ownership
arms built with that same compiler; separate counted executables supply managed
memory metrics. The original Lox source is reconstructed using the existing
verified archive and syntax patch. All 121 migrated EDA modules and project
configuration match their frozen source manifest.

Fresh qualification passed 65 Lox unit tests and 310 EDA tests, with no failures,
unsupported tests or cached results. Each of the three Lox memory/source arms
passed 974 conformance cases across both engines and normal/stress execution;
the smoke benchmark and Lox GC checks also passed. The fresh checked guests
have no emitted retain/release calls or defined native retain/release symbols;
see `guest-rc-symbol-audit.json`. This audit is scoped to the selected guests.
The timeout harness passed four subprocess regressions, including descendant
termination and preserving a failed case across chunks.

The eight existing Zig ReleaseFast/ReleaseSafe, Rust and Go executables are
hash-verified and freshly executed. They are not rebuilt. Inputs and golden
files are checked against the prior full-run receipts before any measurement.
Every successful measured invocation checks complete output oracles.

Runtime uses the existing application harness: CPU 8, two warmups, nine
alternating rounds, and three separate GNU-time child peak-RSS observations.
Whole-command wall time includes launch/startup; instrumented wall time is not
a runtime sample. Shared exclusive timing admission drains cooperating builds;
the long Lox cases release admission between bounded chunks. The 120-second
per-invocation deadline remains the absolute ceiling. At the user's request,
checked-ownership warmup and wall invocations now stop at three times the
current workload's Zig ReleaseFast median (two calibration warmups and five
calibration samples). The same budget is carried across chunks. A stopped case
has no exact runtime ratio; it is explicitly censored at its recorded budget.
RSS is separately measured and uses the absolute ceiling. A runtime-censored
checked arm skips remaining runtime/RSS work and its expensive counter run;
unavailable memory metrics remain explicit. Completed cases use independent
counter measurements with the absolute deadline, avoiding a comparison of
instrumentation overhead against uninstrumented Zig. Failures remain explicit,
with no full-group ratio for an incomplete group. No timed samples are removed.
Read-only host snapshots accompany each chunk.

This run explicitly sets Go GOMAXPROCS=1, GOGC=100 and GOMEMLIMIT=off.
The older full-application receipts did not pin those override variables;
comparisons across runs are observational. Earlier Oct9 measurements used
CPU 10 and different round counts/artifact identities. Neither historical
timing set is pooled with this run's samples.

`build.py` and `qualify.py` own shared build admission. `schedule.py` and
`count.py` own shared timing admission; invoke them directly after sourcing
the development environment. All generated outputs use new paths under this
experiment and `.tmp/lox-eda-rerun-20261012/`. Historical reports are untouched.
EDA measurements, then Lox tree, then Lox VM are scheduled so the shorter
groups can be reported first.

Verbose raw runtime and counted receipts are stored losslessly in
`raw-evidence.tar.gz`; `raw-evidence-manifest.json` records each member's hash.
To restore them in a fresh checkout, run `tar -xzf raw-evidence.tar.gz` from this
directory. The retained local `runtime/` and `counted/` directories are ignored
by Git. The archive is verified by reading every member back and checking its
original hash. The final report records every timeout threshold without using it
as a completed runtime sample.

Managed allocation traffic, reallocations, cumulative allocated bytes, peak
live bytes and exit-live bytes are recorded separately from process RSS.
Completed checked runs must have zero compiler/runtime/shared RC events,
zero uniqueness tests and zero managed exit-live bytes. Direct destruction
events remain valid. Lox's own object garbage collector remains part of the
application. This run does not change the language default or retire RC.

The wrapper's first EDA preflight excluded `mylang.json` from its source
enumeration. All .my files matched; no guest build ran in that attempt.
`build/eda/preflight-error.json` preserves the setup error, and `build/eda-2/`
uses a corrected complete source/configuration identity check.
