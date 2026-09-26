# Closed fresh constructor field relocation

This independent compiler slice is based on cumulative ABI3 source `19e16e1d`.
It changes only constructor field initialization and adds a bounded certificate;
the runtime ABI, pending fallback, constructor journal and frame accounting stay
unchanged. See `docs/audits/d9-rc-fresh-constructor-proof-2026-09-26.md` for the
linearity and region proof.

Immutable Debug compiler identities:

- Control: `1b705d90e58c6b2b3799c5cbe79da9adbc57913e4c72ebbfa2b54dad044c1bbe`.
- Candidate/final: `1b85b2f80b4b229b7bed0c8a120457df28892501edbd0b4732ebb338cd334f8b`.

`measurement.json.gz` contains exact commands, guest manifests and hashes,
interleaved median-three retired-instruction samples on CPU 2, the unchanged
accepted GC binaries and both counter snapshots. The input is the unchanged
private depth-12 source in `experiments/d9-rc-inert-return-20260926`. Control
binaries were reused from the collections agent's cumulative19e build.

| Backend | Control instructions | Candidate instructions | Ratio |
| --- | ---: | ---: | ---: |
| QBE | 599,762,396 | 524,564,349 | 0.874620 |
| LLVM O3/full LTO | 329,568,532 | 296,064,457 | 0.898340 |

Both outputs match exactly. Counters remain 669,060 heap allocations and
retirements, O acquires/releases 19/669,079, no H traffic or clones, and 33
uniqueness checks. This is narrow instruction evidence, not WP-4 acceptance:
the candidate still costs 4.958x QBE / 5.859x LLVM versus accepted GC.

`path-evidence.json` and compressed SSA show eight admitted handoffs in the tree
and reordered-field builders, three in the recursive variant builder, and none
in the aliased or arena-opening helpers. The inherited-arena caller uses the
same certified tree builder without changing its current region. The SSA dumps
use the command's accounted mode; the main guest and n12 executions are
unaccounted. `*-make.asm.gz` records the actual measured native functions.

`guests.json.gz` contains 78 passing actual assertions per backend across eight
focused aggregate, history, option, recursive, iteration and indexed-mutation
fixtures. `units-rc.log.gz` has 114 passing RC units before the last incoming-owner
refusal test was added; `units-proof.log.gz` verifies all five final proof tests
(16 including the project's unnamed blocks). `guardian-full.log.gz` records all
88 whole-tree checks passing, with no ratchet growth or suppression.

`validate.py` exercises the new five-assertion standalone fixture on both
immutable compilers in GC stress and RC counting modes for both actual backends.
It also probes allocation refusal and frame admission. `arithmetic.py` checks a
checked division failure after an earlier fresh child has been produced; both
compilers retire its one allocation on both backends. Source and raw receipts
are retained beside the scripts. Full gates and corpus acceptance are coordinated
by the parent integration agent, not rerun here.

`validation.json.gz` records all 16 successful expected-outcome runs. Each
standalone RC run balances 299 allocations/retirements, O8/307 and H8/8. The
256 KiB refusal retires all 4,089 allocations; the frame limit traps before any
allocation. Control/candidate vectors are identical on both backends.
