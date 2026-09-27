# Named record-field list reads, 2026-09-27

This isolated compiler change borrows a scalar-list field from a proved retained
private named record home through one complete checked scalar-read interval.
It keeps every journal slot and frame allocation. Caller-storage roots, managed
results, callbacks, aliases, extra capture writers and uncertain emitted effects
retain the existing lowering. The late proof and private trial emitter are
specified in `docs/audits/d9-rc-record-field-read-design-2026-09-27.md`.

The control is source `49c6ca07bbba8b35cda4436b831327ac40c8fc87`, immutable Debug
compiler `49a8df2d575b65b16d3e7b455a8b0d6a3aa11ac4eccc13ad34dc3eeb8b54ebd5`.
The final candidate Debug compiler is
`6f83d9e54b2ad207d6360cc6c8ea9daf83b9da582e53f804258619e1a4d516c1`.
`identity-after.json` and `implementation.patch` identify its exact production
and test source changes; `head_before_patch` is the predecessor plus attribution
docs, not a claim that the candidate source was already committed.

The workload is the unchanged full Lox VM binary_trees N10 script. Both sides use
actual QBE or LLVM O3/full LTO. Production binaries run interleaved median-three
on CPU3; separate counted binaries preserve counter evidence. All 12 production
observations ran at 100%, with no counter scaling. Every output equals the
archived oracle. The complete samples and commands are retained.

| Backend | Before instructions | After instructions | After / before | Before / GC | After / GC |
|---|---:|---:|---:|---:|---:|
| QBE | 170,218,083,305 | 154,804,551,022 | 0.909448 | 23.500308 | 21.372315 |
| LLVM | 128,350,769,417 | 118,368,631,962 | 0.922228 | 37.385639 | 34.478071 |

GC denominators are archival medians from completed rows of the original corpus
experiment, not fresh interleaved GC observations: 7,243,227,886 QBE and
3,433,157,037 LLVM instructions. Compiler, benchmark source, input and binary
identities accompany those raw observations. These results remain far outside
Stage 4 performance acceptance. They are isolated results, not measurements of
subsequent integration branches.

Both backends reduce H acquisition/release pairs from 184,812,386 to 160,905,294.
Every other recorded counter is unchanged: 44,407,747 owner acquisitions,
48,758,355 owner releases, 4,350,608 allocations and retirements, 1,095,889 clone
shells and 20,836,904 uniqueness checks. There is no saturation or limit event.
Exact VM emission changes 50 native-loan sites to 48, with one admitted interval
at PC22..39 (`frame.code[frame.ip]`). Static site counts are not dynamic weights.
The earlier qualitative profile and full attribution remain in the separate,
unchanged `d9-rc-record-field-read-20260927` archive.

Validation includes 208 focused RC checks on the measured candidate and
209/209 after the final proof-budget/OOM correction, including six new proof
checks. Guardian 88 passed both installs without ratchet changes. Nine guest
assertions run in before/after RC and candidate GC stress on both actual backends
(54 assertions). They cover negative indexing, loop reentry/rebinding, snapshots,
callback fallback, float-helper refusal, parent and nested arenas, older-region
roots, scalar widths and successful spans followed by ordinary publication.
The complete floating/callback function IL, including labels and temporary
numbers, is byte-identical before/after in accounted and unaccounted modes.

Four production shared libraries run 14 embedding modes each: normal reads,
real finalizer A queuing B while reentering the guest, successful and refused
callback metadata registration, regions, heap-frame and logical-frame admission,
allocator and memory-budget refusal, bounds, steps and arithmetic traps. Twenty-
six matched pairs preserve stdout exactly (result/status/location/hook counters),
and all 56 runs balance ownership. The remaining four runs exercise a deliberate
near-H-limit distinction: the old temporary loan refuses, while the proved raw
read succeeds. Removing unnecessary temporary hold admission is intentional;
this archive does not claim identical reference-count-limit exceptions.

Preliminary negative harness receipts are preserved. A tiny leaf did not perform
its own physical-floor check; the final probe uses a real heap frame. A zero
configured frame budget was invalid; the final logical-depth probe uses a valid
limit and an already active depth. Neither rejected assumption is counted as
validation of the corrected probes. Earlier seven-test prototype receipts and
sources remain distinct from the final nine-test controls.

Verify all archived observations and original live identities with:

```
python3 experiments/d9-rc-record-field-read-implementation-20260927/verify.py --live
```

Without `--live`, verification uses only the archive. `archive.py` is the one-shot
collector used on the staged candidate before commit; it does not rebuild or
rerun measurements. Production compilation and the controls used the build-slot
wrapper, dedicated cache/TMPDIR and the immutable final compiler. Root serializes
the full joined gate and Guardian feedback separately.

Final review found that the scalar stack scan charged PCs but not individual
stack entries, and field/layout lookups hid allocator failure. The separate
`proof-accounting.patch` charges the complete stack before inspection and
propagates OutOfMemory while retaining ordinary non-OOM refusal. An additional
focused test checks exhausted budget before any catalog query and both catalog
and layout allocation failures. `proof-accounting-identity.json` identifies the
new immutable Debug compiler; the measured compiler was not overwritten.
The corrected compiler rebuilds all four production/counted N10 binaries and
six guest/library controls byte-for-byte identical to their measured originals.
The controls are executed again with exact output, trap and counter comparison;
whole fixture emissions are identical in both accounting modes. This explicit
identity chain supports reusing the original hardware measurements. Both source
patches, compiler identities and raw build receipts are retained.
