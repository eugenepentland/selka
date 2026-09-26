# RC journals for physically empty compiler locals

The bounded emission proof removes 34 permanently empty local journal entries
from `nbody.advance`. Its table shrinks from 1,216 to 128 bytes and guards from
304 to 32 bytes. The parameter, reusable operand, pending value and internal
construction entries remain, as does the linked trap frame. This changes neither
semantic ownership nor runtime ownership actions.

Against cumulative `685e2631`, the unchanged 5,000,000-step program retires 6.3%
fewer QBE instructions and 18.0% fewer LLVM instructions. Both outputs and all
physical counters are identical. This is incremental evidence, not WP-4
acceptance; the full corpus remains outside its performance target.

## Physical proof and emission boundary

`qbe_rc_empty_locals.finalize` runs after final COW liveness and physical loop
refinement, before frame sizing. It only considers nonparameter compiler
temporaries with counted, nonunique shapes. A candidate must have exactly one
store, no alternate entry at that store, and an existing anchored read-loan or
`emptyLocal` inert-mutation proof. Anchored stores must immediately follow their
raw source load or an already certified child read, without a planned capture
snapshot or sharing event.

An independent writer scan refuses reference/move instructions, pattern payload
bindings, by-reference and caller-storage locals, H-capable types, uniqueness
targets and aliases, loop-entry clone targets, mutable alias parents, place
parents and rebox owners. Those helpers can install ownership without an
ordinary store instruction. The existing interval proofs reject callbacks,
mutations, arena transitions and uncertain operations during the borrow. Whole
functions above 4,096 instructions or candidates exhausting the 262,144-step
budget retain their original journals.

The semantic `rc_plan` and its physical anchors remain unchanged. The compact
journal carries a separate certified-local mask: an ordinary plain omitted slot
does not imply this certificate. Only these certified locals can synthesize an
empty O/H/LOAN role read. A later publication through `guard`, `entryField`,
`entry`, `stableEntry`, role copying or `initialized(true)` still requires an
actual entry and reports an internal error if the proof has been violated.

| Journal consumer | Treatment |
| --- | --- |
| Prologue entries, `drop`, `initialized(false)` | Existing omission-aware behavior |
| `loans.owner`, `loans.local`, `holds.held`, `local_roles.owning` | Empty answer only for a certified local |
| `prepareGuarded` / `preparePrivate` | Existing borrowed copy/loan publication; no owning token is invented |
| Uniqueness/rebox helpers that write a guard directly | Their possible destinations are refused by the proof |
| Pattern binding, H iteration, local rebinding | Entries retained |
| Operands, pending/internal construction, parameters | Entries retained regardless of this proof |
| Arena watermark and reverse trap cleanup | Original logical ordering through compact prefix mapping |

No count acquisition or semantic SHARE event is newly removed: each omitted
guard was already permanently clear. Therefore callback/finalizer ordering,
count-limit behavior and arena lifetime stay unchanged. The mask is immutable
across native-stack/heap-frame emission retries. Receiver-scope scratch allocation
and the four remaining entries are deliberately outside this change.

## Validation

The focused structural test passes all 12 selected tests, including the standard
11 unnamed blocks. It checks the four-entry linked frame and retained uniqueness,
callback, H-iteration, by-reference and pattern-binding paths. A separate layout
test distinguishes a certified local from a plain omission, preserves the arena
prefix and both transactional entries, and verifies that publication lookup for
an omitted local fails. The broader `RC ` selection passes 59 tests.

Ten existing guest suites execute 436 assertions across native GC stress and
counted RC on actual QBE and LLVM. They include read loans, inert receivers,
semantic publication/history, iteration identity, indirect mutation places,
augmented fields, array places, plain aggregates and Option narrowing. All four
bounds-trap controls pass. Eight standalone runs execute 31 assertions per
backend and have balanced allocation/retirement, O and H totals. Guardian passes
all 88 checks; formatting passes. The parent performs the next cumulative full
gate after integration.

Two invalid test-driver inputs are preserved separately: the first matrix named
a nonexistent `rc_place_loans.my`, then reran completely with `array_places.my`;
the added structural `mut Holder` negative initially declared mutation without
performing one, and was corrected to append before reading. Neither was a
compiler regression or a passing validation receipt.

## Matched measurements

Debug compilers generate all guests. QBE uses `ReleaseFast`; LLVM uses the
ordinary `--release` O3/full-LTO lane. CPU 10 instruction medians use three runs,
and every run checks exact stdout. Historical compilers and binaries are frozen.

| Input | Backend | Before instructions | After instructions | After / before |
| --- | --- | ---: | ---: | ---: |
| 10,000 steps | QBE | 153,781,707 | 143,931,346 | 0.935946 |
| 10,000 steps | LLVM | 52,915,728 | 43,435,616 | 0.820845 |
| 5,000,000 steps | QBE | 76,685,257,976 | 71,840,257,670 | 0.936820 |
| 5,000,000 steps | LLVM | 26,335,250,633 | 21,595,250,058 | 0.820013 |

Both full-size counted arms record two heap allocations/retirements, O 1/3,
10,000,005 balanced H pairs and 10,000,007 uniqueness checks. All other counters
also match. Before compiler SHA-256 is
`ed3dc4a72024b855272981ada0c4ff46e36bc7a6d3e58fd784a9835dfb5326fd`;
after is `078f6fa9af82b43f660a84525a11933c646ed75871c712c0dc198e88833e8944`.

Remaining `advance` IL contains 34 receiver-scope scratch allocations and their
zeroing calls despite the existing inert proofs. Nine plain field replacement
sites also publish a temporary pending guard before immediately clearing it.
These are observations for later bounded work, not changes in this slice.

Raw receipts, compiler/binary hashes, commands, failures, tests and emitted IL
are under [the experiment directory](../../experiments/d9-rc-empty-locals-20260926/README.md).
