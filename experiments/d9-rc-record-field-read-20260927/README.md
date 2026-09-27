# Joined Lox field-list attribution, 2026-09-27

This is design evidence, with no production optimization. Fixed source is
`49c6ca07bbba8b35cda4436b831327ac40c8fc87`; the immutable Debug compiler is
`49a8df2d575b65b16d3e7b455a8b0d6a3aa11ac4eccc13ad34dc3eeb8b54ebd5`.
Full unchanged Lox VM `binary_trees` N10 was built for actual QBE and LLVM O3
with full LTO. Original sources, manifests, compiler/binary/input hashes and
commands are recorded. Existing compiler and build caches were reused.

| Backend | Median3 retired instructions | Archival accepted GC | RC / GC |
|---|---:|---:|---:|
| QBE | 170,830,570,344 | 7,243,227,886 | 23.584868 |
| LLVM | 128,311,807,042 | 3,433,157,037 | 37.374290 |

These are current-source observations, not an isolated before/after optimization.
Accepted GC references are from completed rows of the original corpus experiment,
not fresh interleaved executions. All six current hardware observations ran at
100%. All outputs equal `expected-n10.txt`. Separate counted binaries agree on
184,812,386 H acquire/release pairs, 44,407,747 O acquires, 48,758,355 O releases,
4,350,608 heap allocations/retirements and 1,095,889 clone shells.

Both fixed-period profiles throttled: 335/335 QBE and 253/253 LLVM sample/throttle
records; no lost records. **All sampled attribution is qualitative only.**
`branch-attribution.json.gz` counts presence of each distinct guest call site in
each sampled branch stack; it is neither dynamic call count nor runtime cost.
The two prominent VM loans map to the same `list[int]` descriptor at the named
ExecFrame code-field projection/private capture. QBE call offsets are
`+0x240a`/`+0x2515`, LLVM `+0x1658`/`+0x16f8`. The descriptor arguments and source
data flow were checked in the preserved disassembly, independently of whole
function call order (which can change during backend block layout).

Current emission has 50 VM loan sites. PC23/24 correspond to
`vm.my:473`, `frame.code[frame.ip]`. The exact unaccounted interval and a separate
accounted emission are included. `dbgloc` records use PC+1; the verifier derives
all 50 site PCs directly. The 28 static read loans comprise 14 pairs; one pair
uses the named ExecFrame home, and 13 use caller-storage Runtime fields. The
remaining 22 VM calls concern write receivers. Static counts do not weight cost.

`builds.json.gz` preserves the initial rejected `emit-qbe --project` invocation;
the corrected project command produced the recorded emissions. It did not affect
any of the four successful native builds or measured binaries.

Run `python3 experiments/d9-rc-record-field-read-20260927/verify.py --live` to
verify raw events, hashes, outputs, counts and site mapping. The proposed proof
and negative controls are in
`docs/audits/d9-rc-record-field-read-design-2026-09-27.md`.
