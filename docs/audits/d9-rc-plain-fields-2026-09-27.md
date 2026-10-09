# Immediate plain field reads in RC

The schematic's hot list reads were acquiring lifetime holds for whole inline
records just to inspect one scalar field. `Part` contains three immutable bytes
edges and `Pin` contains two. The unchanged `partPin` body had 12 static
`native_loan` call sites; the scalar `depth` helper had another three because the
canonical read-only body grammar refused list length operations.

This slice removes those obligations only where their physical lifetime is
proved. It changes no runtime helper, allocator, ownership count convention or
GC lowering. The matched exact schematic workloads use 29–31% fewer retired
instructions than the joined RC baseline. This is an isolated optimization
result; WP-4 corpus acceptance is still pending.

## Boundaries

The existing canonical scalar-result body proof now accepts list length reads.
Its existing restrictions on mutation, allocation, callbacks, unique resources
and owning results remain. Bounds checks, arithmetic/step checks and native
frame admission remain present. Managed local bits stay borrowed from immutable
caller inputs throughout that activation.

A separate `qbe_rc_plain_projection` helper recognizes a checked list read
followed by at most eight immediately adjacent `get_field` instructions. Each
intermediate layout must be an inline record. Unique contents, live views,
managed record/box hops, branch targets and any intervening instruction refuse
the proof. The final field must be plain and scalar; no aggregate result can
escape this interval.

The analysis extends the existing stable receiver binding; emission requires
its finalized `.borrowed.storage` role before omitting an operand obligation.
No new loan, hold, scope or publication is introduced. The source is a stable
named root, with existing alias/callback invalidation checks. Its hidden receiver
is a no-token borrower. The checked read consumes a plain index, so that operand
position starts with a clear ownership guard. Each intermediate field projection
keeps it clear; the scalar result is copied normally before the next instruction.
No call, scope transition, local store or cleanup can intervene. Existing early
local release runs only after `store_local`, which is absent from the exact
chain. This preserves the physical anchor without changing edge cleanup.

Named or returned record values still use ordinary ownership. A mutating index
callback retains the original receiver snapshot. A record carrying a live
view takes the existing path. Both eight-field admission and nine-field refusal
are permanent structural regressions, alongside escaped-record, callback and
live-view negatives.

## Matched result

The base is real merge `a1fd4043`, joining frozen integration
`e926d1e13bf61ae3125102b46309225ca963a38d` with the committed closed-field transfer.
The baseline Debug compiler SHA-256 is
`aee67f9abfe65b61a960eaf3390082d9c338553e5b086ad1cfc7723b933ab475`;
the candidate is
`dedb995e15316f70b472faa4d80c7d3dd1ce35c1ddc552feaef567811acd2cc5`.
Both actual backends use the unchanged source/provider, project inputs and
`pc.py` build/run/check commands. LLVM explicitly uses `--backend llvm
--llvm-opt 3 --lto`.

Uncounted binaries run three times on CPU 3 with
`perf stat --no-scale -x, -e cpu_core/instructions/u`. Every raw event reports
100% running; the archive preserves event runtime, percentage, counters and
stdout/stderr. Counting binaries are separate. All 24 baseline/candidate,
backend, counting-mode and workload checks match the complete expected SVG
hashes; measured executions also verify the SVG.

| Backend | Exact workload | Before instructions | After instructions | After / before |
| --- | --- | ---: | ---: | ---: |
| QBE | fixture | 1,363,065,319 | 961,459,843 | 0.70537 |
| QBE | changed-net | 1,363,024,523 | 962,589,958 | 0.70622 |
| QBE | changed-value | 1,369,597,046 | 961,618,324 | 0.70212 |
| LLVM | fixture | 1,137,364,040 | 796,537,317 | 0.70034 |
| LLVM | changed-net | 1,139,230,189 | 792,934,086 | 0.69603 |
| LLVM | changed-value | 1,143,692,184 | 792,782,813 | 0.69318 |

Fixture and changed-value counts agree between backends: hold pairs fall from
604,122 to 361,686; owner acquisitions fall from 169,777 to 168,193, with releases
169,933 to 168,349. Changed-net hold pairs fall from 604,364 to 361,928 and owner
acquisitions from 169,749 to 168,165. Every run has 156 heap allocations and
retirements, one clone and no count refusal or saturation. Uniqueness counts are
unchanged. Allocation/owner/hold equations balance throughout.

`partPin` now has four static loan sites, five retain sites and eight generic
take fallbacks, versus 12/5/12 before. `depth` has none of these calls, versus
3/0/2. `innerPin` is unchanged. This leaves substantial record-return and caller
materialization work, motivating the separate
[borrowed-loop design](d9-rc-borrowed-loops-design-2026-09-27.md).

## Validation

- Focused tests pass: 14/14 for plain field chains (three named tests), 12/12
  for canonical scalar list lengths (one named test); both include 11 common
  unnamed tests.
- Six standalone assertions pass in GC stress and counted RC on actual QBE
  and LLVM: 24/24. They cover nested fields, negative indexing, scalar loops,
  callback snapshots, escaping records, live views and caller arenas. RC counts
  agree: 74 allocations/retirements, O18+74=92, H37 pairs and eight arena objects.
- Positive and negative out-of-bounds indices inside a caller arena preserve
  `R_LIST_BOUNDS`, the preceding output marker and balanced counted cleanup.
- Debug compiler build passes all 88 Guardian checks. No baseline or ratchet
  changed. An initial test-local name shadowed an existing helper; renaming the
  local fixed the compile error before the green validation.

The [archive](../../experiments/d9-rc-plain-fields-20260927/README.md) includes
exact commands, identities, emitted IL, source patch and an independent verifier.
The integration parent owns the joined full gate and complete corpus runs.
