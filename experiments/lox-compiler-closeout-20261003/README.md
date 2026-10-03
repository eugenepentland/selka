# Compiler measurement closeout and archive

This independent helper validates the frozen 223-guard compiler-only protocol.
It requires smoke coverage of 156 cells and a counter screen of 104 cells.
Completed three-round wall/counter matrices contain 468 cells each; absent
optional matrices are explicit. An incomplete matrix or wrapper fails
validation. Source maps, original qualification, copied RC ELFs and sidecars,
runtime objects, command/log hashes, complete tuples, output hashes, diagnostics
and all four PMU running percentages are checked. Smoke stats must be one exact
line and equal across all six arms. Existing paired analyses are recomputed
from saved samples with a declared numerical tolerance; no workload is rerun.
Wall receipts use the `timed` size tier, while counter receipts use the `tree`
size tier for both engines; cardinality alone does not imply equal workload
sizes between those protocols. Every case is checked against the pinned size
map, generated input contents and expected-output path for its declared tier.
The separately named focused diagnostic may contain exactly VM equality and
string equality across four baseline/candidate arms and three rounds (24 cells).
Its paired results are explicitly partial and provide no full-matrix or
selection claim. Every other phase receipt is refused, including completed
unknown scopes; evidence is never silently classified as an unvalidated extra.

Run with `taskset -c 16 python3 -B closeout.py --check WORK` for read-only checks.
After reviewing the helper, use `--archive DEST --work WORK --extra FILE_OR_DIR`
with each explicit external qualification review, tracked author qualification,
archive manifest, or historical failed preparation. Extras are retained evidence
and contribute no successful measurement rows.

The new archive contains all work files except generated build-cache trees,
every guarded original even if it is in a cache, all extra evidence and this
helper. Object names are SHA-256; identical content shares one object. Original
paths, content identities, symlink targets, completed coverage and verified
analysis metrics are retained. Copies and originals are rehashed before and
after sealing; changed or newly added files fail sealing. Failed staging output
is marked and retained, and an existing archive is never overwritten.
The work/guard inventory is also bound before and after validation and before
archiving, so a newly arrived receipt cannot bypass protocol checks.

`--verify ARCHIVE` checks relocated archive objects without executing anything.
Add `--originals` to require that every absolute original path still matches,
and `--expected-manifest SHA` to bind the verification to an independently saved
manifest identity. Without those flags the report explicitly omits original
identity and external manifest authenticity claims. Neither validation nor
archiving infers compiler selection, performance significance or parity.

The measurements retain stdout hashes and stderr tails, rather than complete
raw process streams. Full stdout comparison occurred in the guarded runner.
ELF section/layout comparisons are reproduction evidence; measured executable
bytes remain the exactly copied, separately qualified RC artifacts.
Validation re-runs the frozen guarded read-only ELF comparer against the actual
rebuilt and measured files, including every allocated section, and binds the
saved evidence to those files. The comparer executes no guest or subprocess.

The host test suite covers receipt refusals, arithmetic, cache exclusions and
private synthetic archive creation, deduplication, relocation, changed originals,
corruption, missing/extra objects, symlink changes and failed staging retention.
Run `taskset -c 16 python3 -B -m unittest discover -s . -p 'test_*.py' -v`
from this directory. These tests execute no compiler, guest or performance tool.
