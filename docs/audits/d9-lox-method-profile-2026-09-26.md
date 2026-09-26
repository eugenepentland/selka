# D9 Lox method-call profile and rejected frame caches, 2026-09-26

The remaining LLVM method-call overhead includes table-copy allocation and frame
reloads. The profile justified examining both, but two return-side frame caches
failed the matched measurement and are not part of the optimized source patch.

## Profile

Both guests were rebuilt with symbols, ReleaseFast, LLVM optimization level 3
and full LTO. The baseline uses the historical 60b source and Debug compiler
`48427e9a…`; the candidate uses frozen `5bdd99ea` compiler `ceb38b6e…` and the
composed compact-frame, instance-reader and late-closure source. This predates
the indexed setter and global-hash hoist. CPU 11, mandated `pc.py`, calibrated
method_call N50,000 and three alternating instruction samples give
5,202,602,530 baseline versus 7,570,389,146 candidate: **1.45512×**. Outputs match.

Ten launches per profile with instruction sampling produce 4,553 baseline and
5,979 candidate samples. Candidate self costs include `vm::run` 27.53%,
`table::get` 16.27%, `vm::load_frame` 9.37%, allocator `alloc_object` 8.88%,
`table::find_entry` 6.59%, list cloning 2.69%, `slot_take` 2.61%, and `prepare`
1.81%. Allocation/COW stacks beneath `table::set` account for 1,282 of the
5,979 samples. These are sampled shares, not exact exclusive attribution.
`load_frame` reloads object payloads and marks three collection leaves shared
on both calls and returns. This suggested a return-side frame cache; global
table copying suggested the independent hash-hoist candidate.

## Rejected experiments

The experiments preserve compact persistent frames and late closure publication.
One pushes the active `ExecFrame` on calls and pops it on returns. The second
retains cache slots by frame index and reuses them on later calls. Both compare
against the same corrected-RHS, composed source, using frozen Debug `5bdd99ea`,
ReleaseFast LLVM O3 full LTO, CPU 11 and median-three `pc.py` instruction counts.

| VM case | Push/pop / before | Indexed reuse / before |
| --- | ---: | ---: |
| method_call | 1.00242× | 1.01588× |
| closures | 1.00659× | 1.02084× |
| binary_trees | 0.99925× | 1.00767× |
| fib | 1.00393× | 1.03708× |
| trees | 1.00422× | 1.01962× |

Every measured output passes. The extra cache traffic does not justify either
change; neither variant is applied to the tracked migration patch.
[Raw evidence](evidence/d9-lox-method-profile-frame-experiments.json) records
all samples, identities, profile tables, scripts and both rejected source deltas.
Large raw perf files remain in `d9-nested-cow/.tmp-nested/method-profile/`;
frame experiment scratch is `d9-lox-frame-return/.tmp-frame-return/`.

## Baseline artifact recovery

After these measurements and profiles completed, a section-extraction command
incorrectly used `objcopy --dump-section` without an explicit output binary.
It rewrote ELF metadata in the shared historical baseline and local symbolic
baseline. The instruction sections remained equal, but their whole-file hashes
changed. The formal integration sweep correctly stopped on its baseline hash
assertion. This incident is not treated as an equivalent baseline artifact.

Both binaries were rebuilt into private scratch from the frozen original
compiler, source and flags, and their expected whole-file hashes were verified
before restoration. The shared baseline was restored to
`61621ee380e5562967b53d6ba81c54fe28ceb2adc22ad6fa943e6772b7887fa0`;
the symbolic copy to
`7d590eea34ad9e6ed166d309ce17fd92055672c0099e547e4a4a3a162bcb53b9`.
The independent formal sweep then resumed with private copies. All profile and
frame results above were obtained before the metadata rewrite; no measurements
were taken against its altered artifact. The evidence retains recovery logs and
commands. Future symbol extraction uses private input copies and explicit outputs.
