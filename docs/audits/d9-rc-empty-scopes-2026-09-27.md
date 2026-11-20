# Omit unused receiver-scope storage

The existing physically empty local certificate also proves that 34 receiver
scope buffers in `nbody.advance` are never addressed or linked. This slice removes
their allocation and zeroing, saving 1,088 bytes from its reserved frame storage.
The four retained ownership entries, their guards, frame admission, logical
frame, step checks and trap linkage remain unchanged. Scalar pending-value
publication is outside this change.

## Use audit and strict boundary

All `rcborrow` addresses come through `qbe_rc_scope.borrowAddress`. The only
consumers are receiver begin/pin and receiver end, including the end performed
after a mutable argument call. For certified inert mutation captures, both
consumers already skip their scope operations under the same inert proof. For
certified read captures, the anchored raw store bypasses receiver setup; the
existing writer and alias-parent veto prevents a later mutable scope walk from
reaching that local. These buffers cannot be linked into runtime cleanup.

`qbe_rc_frame.receiverStorage` now excludes only locals with that explicit
certificate. It controls both frame byte accounting and actual allocation.
`borrowAddress` rejects any later request for an omitted local before emitting
an instruction, so a missed use cannot become an undeclared or stale pointer.
Uncertain aliases, callbacks, reference arguments and noncertified receivers
retain their original buffers and cleanup. The proof mask remains immutable
across native-stack and heap-frame emission retries.

There are five added product lines, including comments, across these two
functions. No new ownership analysis, runtime API, count operation, publication,
or scope lifetime decision is introduced. The emitted `advance` now contains no
`rcborrow` references and one `memset` for its guards, down from 35 total.

## Validation and measurements

The structural test checks absent buffers in `advance`, preserved four-entry
frame/admission and retained callback scope storage. A direct emitter test proves
that an omitted address refuses before emitting anything while a retained address
continues to work. All 61 selected `RC ` tests pass. Ten guest suites execute 436
assertions across GC stress and RC on actual QBE and LLVM; four bounds traps also
pass. Eight standalone executions run 31 assertions per backend and balance
their O, H and allocation/retirement counters. Guardian passes all 88 checks and
formatting passes. The parent will run the next cumulative integration gate.

Measurements compare immutable Debug compilers at base `597cdcf9` and this slice.
Guests use QBE `ReleaseFast` or ordinary LLVM `--release` O3/full-LTO. Each number
is a CPU 10 median of three instruction counts with exact stdout checked.

| Input | Backend | Before | After | After / before |
| --- | --- | ---: | ---: | ---: |
| 5,000,000 steps | QBE | 71,840,268,228 | 67,510,266,974 | 0.939727 |
| 5,000,000 steps | LLVM | 21,595,254,557 | 21,595,254,793 | 1.000000 |

The reduced 10,000-step control gives QBE 0.939832 and LLVM 1.000001. QBE gains
about 6.0%; LLVM is neutral. Full-size counted before/after executions have
identical counters: two heap allocations/retirements, O 1/3, 10,000,005 balanced
H pairs and 10,000,007 uniqueness checks, with all remaining counters matching.

Before compiler SHA-256 is
`078f6fa9af82b43f660a84525a11933c646ed75871c712c0dc198e88833e8944`;
after is `821b0e21c445559fbfb079735d18cbcc32dee594a41f33c3ff7303addfaf84fa`.
This remains an incremental improvement, not RC performance acceptance.
Complete receipts and emitted IL are in
[the experiment directory](../../experiments/d9-rc-empty-scopes-20260927/README.md).
