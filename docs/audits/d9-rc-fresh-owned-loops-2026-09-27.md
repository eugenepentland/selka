# D9 RC fresh-owned loop checks — 2026-09-27

This compiler-only change retains one actual runtime uniqueness check at each
proved loop entry, then reuses that result across the loop. It admits additional
plain-list construction and mutation loops only after proving that the physical
root is still the sole owner of a fresh allocation. The ordinary owner journal,
trap cleanup, frame admission and outgoing ownership remain intact.

This is a component performance result, not Stage 4 acceptance. The GC default,
legacy compatibility lane, runtime ABI and C uniqueness implementation are
unchanged.

## Physical proof

`qbe_rc_fresh_root` traces at most eight local handoffs back to an exact fresh
list `make_record` or `acquire_buffer`. The element shape must have neither
counted edges nor unique drop obligations. Every family local has one store;
parameters, caller storage, by-reference storage, places, aliases, pattern
bindings and rebindings refuse the proof.

Producer freshness is a lowering invariant, not inferred from the type name.
`qbe_aggregate` routes list `make_record` to `qbe_managed.emitConstruct`, which
always calls `myl_native_list_new` and appends the supplied plain elements.
Only string/bytes constructors use frozen literals. A list constructor never
wraps an existing header or backing block. `acquireBuffer` independently calls
the same new-list producer with a capacity. The structural test checks both an
empty list and a nonempty list literal and observes the actual new-list call.

A handoff requires the adjacent load, optional value-copy already proved to be
a semantic move, and store. Crucially, semantic move classification does not
establish physical exclusivity. The exact store edge must really discharge the
source owner through `qbe_rc_edges.releasesAt`, using the same eligibility and
retained-parent veto as actual emission. The unchanged receiver-ancestry lookup
is factored into `qbe_rc_receivers` to share this rule without an import cycle.

A branch may enter the initial load, as a comprehension exit does. Entry at the
middle copy or store is refused. All family uses through the selected backedge
are audited. Other loads must be separately certified no-token receiver captures,
with no semantic sharing or captured-read publication. Existing read-loan proofs
cover the complete descendant use chain. External entries after the fresh
producer are refused, including an enclosing loop that could re-enter after a
previous iteration published an alias. Re-executing the fresh producer is safe.

Bounds are conservative: at most 4,096 instructions, eight family locals,
1,024 instructions in the selected loop, and fixed 262,144-instruction analysis
budgets. Unknown, inlined or unsupported paths retain the original checks.

The existing physical loop whitelist then applies. New cases admit plain-element
append, plain inline record construction and plain returns. It still rejects
callbacks, calls, managed publication, rebinding and explicit arena transitions.
Constructor inputs and outputs must all be plain and nonunique. The resulting
place/alias graph must be identical before the refined plan is installed.

## Allocation and zero-iteration ordering

The existing preheader executes before the loop condition. Newly admitted roots
therefore must be physically fresh and exclusive, not merely free of a semantic
SHARE. Their entry check cannot clone, retain, allocate or introduce a new
observable refusal. A shared or uncertain root keeps its original in-loop check,
including zero-iteration loops. Internal uniqueness-check counts are deliberately
reduced; owned edges and cleanup remain unchanged.

The native append audit found that growth replaces raw backing storage while
preserving the list header, region and logical element ownership. Borrowed input
offsets are remapped before publication. For these plain inputs no child owner,
history or loan is introduced. A failed reserve or append retains the existing
logical prefix; permitted capacity changes and the ordinary failure path are
unchanged. The paired memory-budget control reaches allocation refusal after
successful growth and compares the exact output, code, trace and balanced tokens.

Inherited arenas remain legal. There is no region transition in the certified
interval, and append/uniqueness use the existing payload region. Explicit arena
entry or exit in that interval refuses admission.

## Evidence

Evidence and reproducible drivers are in
[`experiments/d9-rc-fresh-owned-loops-20260927`](../../experiments/d9-rc-fresh-owned-loops-20260927/README.md).

Both compiler executables are Debug. The baseline is immutable joined source
`e926d1e13bf61ae3125102b46309225ca963a38d`, SHA256
`aee67f9abfe65b61a960eaf3390082d9c338553e5b086ad1cfc7723b933ab475`.
The measured candidate SHA256 is
`7e5f02708fde642dc5b9583a661f5b65e432e0e58d0b2c5d43e5216f66bc3386`.
Guests use QBE ReleaseFast or LLVM `-O3` with full LTO. Measurements use CPU 10,
three complete executions per arm, raw `perf stat instructions:u`, unchanged
mandatory source sizes, and exact checked stdout. Runtime counters come from
separate counted binaries and are never used as timing binaries.

| Workload (unchanged size) | QBE instructions before → after | Ratio | LLVM instructions before → after | Ratio |
|---|---:|---:|---:|---:|
| fannkuch_redux n10 | 87,097,715,955 → 10,039,232,885 | 0.115264 | 49,534,617,215 → 2,029,153,632 | 0.040964 |
| sieve 20,000,000 | 25,210,942,036 → 20,570,941,243 | 0.815953 | 17,389,449,784 → 14,769,448,887 | 0.849334 |
| list_append_sum 16,000,000 | 17,782,525,444 → 14,214,574,270 | 0.799356 | 11,718,703,769 → 10,294,703,525 | 0.878485 |

Unique checks fall from 354,444,268 to 10 for fannkuch, 20,000,006 to 6 for sieve, and 16,000,000 to 1 for list_append_sum. Every other physical counter is identical between arms and both backends. All allocations retire and owner/hold balances close. Fannkuch retains six static uniqueness calls in its body (three construction and three outer-loop root checks), plus four calls in main. Sieve already had a valid mutation hoist; its gain here comes from construction.


The proof test keeps an actual entry check and linked owner journal, admits the
comprehension exit/handoff and plain terminal path, and rejects snapshots,
callbacks, surviving aliases and earlier enclosing-loop publication. Permanent
nine-case guest coverage includes post-loop snapshots, sorted receiver ancestry,
zero iterations, callbacks and inherited arenas. Broader existing suites cover
physical read loans, iteration holds, nested mutation, augmented field updates,
array places, semantic history and closed-field transfers.

Final validation: 12 focused proof tests, 68 RC unit tests, whole-tree Guardian
88/88, formatting 2/2, and Debug install 12/12. Actual uncached guests pass 340
assertions across QBE and LLVM, GC stress and counted RC. The 32 paired standalone
controls preserve exact status, stdout and source traces for append growth
refusal, shared zero-iteration loops, overflow and bounds traps. All counted
control executions balance; all non-uniqueness counters agree between arms.

After local cache regeneration, the final compiler SHA256 is
`b40af87109be68b0b5144c548ad4a26f1d9d9e3964cf7e2a9a42a5d92412fe8f`.
All three emitted function arrays and all twelve normal/counted native guest
binaries are byte-identical to the measured candidate. Both immutable compiler
prefixes and all measured binaries remain on disk. The verifier checks archived
receipts without rerunning workloads.

The only runner corrections were a local Python name collision between compiler
and counter values, and the diagnostic spelling `R_OVERFLOW`. Original receipts
are retained. Clearing old, inactive local Zig object-cache entries required
invalidating their stale local metadata before the next focused build; no
immutable compiler, guest binary or measurement was removed.
