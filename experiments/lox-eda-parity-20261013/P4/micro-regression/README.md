Prepared six regression cells: string_split, json_transform and csv_aggregate,
each small and large. No candidate build or timing request has been submitted.
Await the coordinator's final integrated installation prefix and compiler hash.

inputs.json pins all historical common-final-002 specs/results, source/control
binaries, benchmark inputs/contracts/oracles and existing text benchmark tools.
All source and control binary hashes matched the historical specs. The workload
source remains 71f5e74e25f894e779c6248b9f52c144e9d53a8c482c0121e4249374dbe05754.
Foreign controls are reused unchanged; no historical samples are pooled.

prepare.py without compiler arguments performs only read-only verification and
creates a fresh inputs.json. With an explicitly supplied final compiler prefix
and hash, it builds runtime and counted guests through shared build admission.
All build outputs/caches use .tmp/lox-eda-parity/P4/micro-regression. Compiler
installation files and original inputs are verified before and after builds.
It then creates new specs with unchanged sizes, seed42, calibration budgets,
three warmups, fifteen rotated/reversed paired rounds, three independent RSS
observations and separately counted checked binaries. CPU8 timing is exclusive
per cell with a fresh read-only host snapshot before calibration/warmup. Seven
arms are original C0 checked-baseline, frozen common002 checked-common, final
integrated checked-candidate and ZigSafe/ZigFast/Rust/Go.

Inspected writes: historical prepare_candidate/prepare_trial/prepare_observed_trial
write beneath the historical bench/runs namespace, so they are not invoked.
The new preparer writes only its own P4 subtree and private scratch. Existing
schedule_observed creates its supplied result directory and opens per-cell logs
with mode w; run.py therefore requires the entire new result destination to be
absent first. observe_cell creates the new host snapshot with mode x. measure
creates new progress/counter/receipt files and temporary RSS files, rejecting
existing receipts/progress/counters. report creates only its supplied new report
directory. All measurement/report inputs remain read-only; host affinity changes
are confined to the measurement process as in the original protocol.

Planned commands (substitute coordinator-supplied PREFIX and SHA):

    source /home/epentland/.config/mylang/dev-env.sh
    export TMPDIR="$PWD/.tmp/lox-eda-parity/P4/micro-regression/tmp"
    mkdir -p "$TMPDIR"
    python3 -B experiments/lox-eda-parity-20261013/P4/micro-regression/prepare.py --compiler-prefix PREFIX --compiler-sha256 SHA

After coordinator authorizes this campaign's timing window:

    python3 -B experiments/lox-eda-parity-20261013/P4/micro-regression/run.py --start-measurement

No nested timing admission: existing schedule_observed acquires one lease per
cell, and observe_cell/measure execute inside that lease. Failed or noisy cells
remain evidence; no trimming, historical-result overwrites or cutoff changes.
The local uncommitted P1 heap dependency remains untouched.
