# Incoming record lifetime: unchanged Lox N10

Paired median-three retired instructions on CPU3:

| Backend | Before | After | After/before | After / archival accepted GC |
| --- | ---: | ---: | ---: | ---: |
| QBE | 154,847,125,432 | 146,597,270,007 | 0.946723 | 20.2392× |
| LLVM O3/full LTO | 118,761,080,254 | 112,536,573,744 | 0.947588 | 32.7793× |

All twelve raw events report100% running; output is exact. H pairs fall
160,905,294→146,041,398; all other counters remain unchanged. This is an isolated
bounded improvement, not Stage4 performance acceptance.

`identity.json` and `implementation.patch` preserve the measured compiler and
source. `proof-correction-identity.json` and `final-source.patch` describe the
reviewed removal of a redundant type traversal. All ten corrected binaries are
byte-identical to their original measured/control counterparts;36 after-control
runs repeat exactly. Original artifacts remain untouched.

Controls include48 actual guest assertions and64 embedding executions, comprising
30 exact before/after status/output/location/hook pairs plus4 explicit removed
H-limit admissions. O0/H1 caller authority, forwarded references, nested arenas,
queued-sibling finalizer reentry, metadata/allocator refusal and all mandatory
traps are covered. Rejected fixture assumptions are retained separately.

The GC observations are completed rows of the original corpus experiment,
not fresh interleaved executions. The full report is
`docs/audits/d9-rc-caller-field-read-implementation-2026-09-27.md`.

```sh
python3 experiments/d9-rc-caller-field-read-implementation-20260927/verify.py --live
```
