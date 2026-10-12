# Unapplied C3 counter-runtime patch request

Base: `bed11cf3bf3102ffec44487e431a1573fdf02ad5` (Support7). These four files
are unchanged from the earlier coordinated `c749ad5a9` snapshot. The generated
`counters.patch` is an exact request for the coordinator, not an applied change.
`manifest.json` pins every before/after file and the patch. Apply it together
with A02's runtime retirement and A07's owned LLVM templates; neither C2 nor C3
is claimed complete by this draft.

The patch removes five dead RC instrumentation hooks and their slot constants,
plus counted LLVM declarations for retain/release/free-block and the obsolete
free wrapper. The counted allocation template already calls the runtime and
has no count-word initialization to remove. A07 supplies direct `drop_owned`
destruction and the `mylang-checked-owned-v1` marker on every emitted LLVM unit.
Its emitter rejects retain/uniqueness operations. `release_unique` remains the
historical name of the active direct-destruction counter.

The JSON format remains `mylang-counters-v1`, with the same names and ordinals.
Historical RC fields remain explicit integer zeros for compatibility. No RC
event instrumentation remains after the coordinated removal, so these zeros
must not be described as measured RC events. `contract.py` requires every old
field, all zero-valued bytes/extra slots, the checked-owned ABI context and no
obsolete RC sites. It removes the old `observed_rc_free` classification. Its
qualification helper also requires separate successful structural ABI evidence
and no managed leaks. It never treats a missing field as zero. Historical C0
parsers and the approved C0 native replay adapter remain untouched.

All allocation, reallocation, growth, semantic-copy, free, live-byte and peak
instrumentation is preserved. The counter writer changes only comments. Its
thread-local aggregation, mutex, live/peak atomics and quiescent dump remain;
those atomics measure instrumentation state and are not guest memory RC. Task
pending-work synchronization is outside this patch and remains intact.

`parser-controls.json` records 20 synthetic parser controls using a preserved C0
counter fixture. These exercise classification, not retired-runtime execution.
Missing fields, nonzero reserved slots, wrong ABI, obsolete sites, managed leaks
and absent structural proof all fail; positive direct-destruction counts pass.

`native-controls.json` records 12 native scratch executions: selected-owned
Support7 runtime before the patch versus A02's combined selector-free runtime
SHA-256 `ca2ded335995f2d6f76c9900b172d74c20800cbe2885af4f3d39bf72a1eb7ca1`,
with the prepared counter sources. The combined runtime includes the A01/A02/
A04/A05 coordinated drafts. Both standalone `count_runtime.source` exporters
apply all anchors successfully. Small/large lists grow, copy independently,
validate checksums and drop with 1/2/8 native pthread workers joined before dump.
The control explicitly supplies emitter-like site records; it is not a guest
compiler or a final linked-package qualification.

All twelve runs have zero exit-live managed bytes, matching allocation/free
events, positive growth/copy/direct-destruction counters, expected output and
no linked legacy RC helper symbols. The 128-element runs use 7 allocations and
3,280 allocated bytes per worker, and no reallocations. The 65,537-element runs
use 7 allocations and 10 reallocations per worker. Event counts and element-copy
traffic match across both runtime versions; small and serial-large byte traffic
also match exactly. Actual allocator usable sizes, realloc placement and
thread scheduling can change large concurrent allocation bytes and peaks. Every
individual run still balances allocation plus realloc-added bytes with frees.
There is no timing, RSS or allocation-saving claim from these native controls.

Two initial harness failures are preserved. Attempt v1 omitted the guest-emitter
task trampoline, causing native link failure; the native-only control now has
an aborting trampoline because it does not submit scheduler tasks. Attempt v2
completed all twelve executions but its initial comparison incorrectly required
equal allocator usable bytes for concurrent large allocations. The corrected
audit checks deterministic traffic and per-run byte balance, preserving the
same raw executions without rerunning them. `raw-archive.json` pins 72 compressed
raw files; the logs retain both failures. Final integrated C3 still needs guest
LLVM, layout, runtime and installed-symbol audits and the registered counter tests.

Commands use `python3 -B .../check_contract.py`, then one ordinary shared build
lease around `check_native.py --combined-runtime PATH --zig "$ZIG" --output NEW`.
`--audit-existing` only reads preserved executions, verifies unchanged source
inputs and writes a previously absent result; it does not compile or rerun them.
