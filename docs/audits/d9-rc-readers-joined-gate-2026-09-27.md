# Combined readers and write-path correctness checkpoint

Frozen source `c47058f58251211582b6abc0ee5cef5a7bb9a6e0` passes all four gate
commands: main 94/94 steps with 2,351 executed tests, QBE 51/51 with 448 tests,
native builds 29/29 and formatting 2/2. The Debug compiler build passes 19/19
steps. Separate whole-tree Guardian passes all 88 checks without a waiver.
The compiler SHA256 is
`2cbd1f4e6c96ddde0abed71132f5e136618273d45beb276d8f3fa6c9b31041d6`.

Both forced counted-RC sweeps pass **998 assertions across 169 programs**,
with zero failures, skipped, cached, dropped or unloaded cases. LLVM uses
`--release`, including optimization level 3 and full LTO. Source and HEAD
remained frozen through the serialized build, gates and sweeps. Raw receipts,
scripts, summaries and artifact hashes are in the
[evidence archive](../../experiments/d9-rc-readers-joined-gate-20260927/README.md).

The checkpoint adds anchored dictionary keys `a8f852b9`, scalar append readiness
reuse `95121e70` with comment correction `aadf9e80`, named-record scalar writes
`14c73780`, and plain-result read-only helper composition `c62adfb0` to the
previous combined ownership checkpoint. Each branch joined through a real
two-parent merge. The newer dictionary-loop uniqueness proof `88f4e477` and
read-only list-loop version remain separate from this frozen source.

This establishes correctness for the combined source. Component measurements
use their own recorded bases and do not establish combined performance. The
unchanged 43-program-per-backend instruction and peak-RSS acceptance remains
open. GC stays the ordinary runtime, and main remains unchanged.
