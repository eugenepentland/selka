# Fresh text-gap measurement

This track measures the unchanged `string_split`, `json_transform`, and
`csv_aggregate` contracts at both canonical sizes. It changes no production,
benchmark fixture, port, compiler policy or reference build. The initial checked
baseline compiler is `ec423f5ff7dba37f5d39489fec12b9c851754c0ad69125fc8aaafe85e31ea44e`.
Foreign executables are reused only after checking original binary hashes,
source hashes against the reference manifest and canonical port, and exact
recorded build flags. Candidate preparation additionally pins all text reference
sources, including Cargo metadata, and every linked native clock.

Each cell takes one shared exclusive timing admission, pins its children to CPU8,
and releases admission before queuing the next cell. The measurer never acquires
another lock. Runtime policies match the prior harness: optimized default foreign
builds, Go GOMAXPROCS1/GOGC100/GOMEMLIMIToff, cleared override variables, kernel
clock excluding setup, independent registry checksum oracle, three warmups,
fifteen measured paired rounds and three separate child-process RSS runs.
Counted native binaries run separately and never supply timing/RSS samples.

The new deterministic order rotates each n-arm block through every position,
reversing the base order every block. Five arms over fifteen rounds occur exactly
three times in each position; six arms occur two or three times. Carryover pair
ordering is not perfectly balanced with fifteen rounds. All raw execution orders,
ranges, load snapshots and per-arm drift remain visible. No samples are trimmed.
Calibration targets50ms fastest, limits slowest1s, uses at most ten pilots and
10million iterations. The inherited near-target growth stop is retained but
accurately labeled `near_target_growth` rather than `slowest_arm_budget`.

Baseline runs contain checked baseline plus ZigSafe/ZigFast/Rust/Go. Candidate
runs remeasure these five arms alongside the candidate, with the same iteration
count within each cell. Reporting uses the ratio of medians and a deterministic
10,000-resample paired bootstrap, resampling matching round indices jointly.
Below-one point estimates and CIs must be read per foreign arm and per cell;
there is no aggregate language score and no pooling with historical samples.
Managed peak/traffic are reported separately from process RSS. Managed counters
include setup and exclude allocator overhead; foreign managed counters are
unavailable. CIs are exploratory single-session evidence, not independent-run
confirmation.

Create a new baseline using `tools/prepare.py --run UNIQUE`. For a candidate use
`tools/prepare_candidate.py --run UNIQUE --candidate-runtime PATH
--candidate-counted PATH --candidate-manifest PATH`. The manifest must contain
compiler/hash and runtime/count entries with binary/hash/source/source_hash,
flags and build commands. All candidate benchmark source bytes must match the
baseline. These commands validate everything before reserving a new destination.
Never overwrite a run or report; use a new suffix.

Run `tools/schedule.py RUN/specs RUN/results --cpu 8` after sourcing the shared
dev environment. It acquires one timing lease per cell; do not wrap it in another
lease. Use `--cell csv_aggregate.large --cell csv_aggregate.small` for a focused
trial. `tools/report.py RUN OUTPUT --check-artifacts` requires all six cells;
`--case csv_aggregate` explicitly reports a two-cell trial. Report validation
rejects changed artifacts, incomplete/misordered rounds, oracle mismatches,
changed counter hashes and nonzero checked RC/uniqueness/exit-live counters.
The first baseline report's exact reporter source is archived as
`tools/report_baseline.py`; `tools/report.py` adds explicit trial subsets.

`baseline-001` is a fresh five-arm run; its raw receipts, journals, counter files
and per-cell admission logs are in `runs/`. Source/compiler/binary identities
are embedded in specs and checked before and after each cell. Its six measured
cells all validated. Harness tests6/6 and report tests2/2 passed, including
mutation rejection for six corruption classes. Stored earlier evidence remains
unchanged.

Root-authorized exploratory screens use `tools/screen.py`: three arms (checked
baseline, candidate, fastest immutable reference), one warmup and five paired
rounds, fixed fresh-baseline iteration counts, no RSS/count phase.
`tools/screen_report.py` validates them under a separate schema. They cannot
replace or be pooled with full fifteen-round final evidence.

CSV01 initially supplied mutable working artifact paths. Before subsequent
builds, the exact six measured CSV inputs were archived by SHA256. Its explicit
`artifact-relocations.json` maps original measured identities to byte-identical
archives. Revalidate with `--artifact-map PATH`; hash mismatches are still fatal,
and the report records every relocation. Future candidates start with immutable
archive paths. The initial trial reporter is retained as
`tools/report_trials_initial.py` to preserve its recorded source identity.
