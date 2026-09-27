# Joined managed helpers and dictionary word overwrites

The joined `c07016f308422b76cfe55607b26243efe0b4257e` compiler preserves the
isolated gains: unchanged dictionary counting improves 5–7% against the prior
joined `49c6ca07` compiler, and the three schematic workloads improve 24–28%.
All eight workload/backend rows produce the exact accepted output. Every row
still exceeds the Stage 4 per-program instruction limit of 1.3× accepted GC.

| Workload | Backend | Prior RC instructions | Joined RC instructions | Joined/prior | Joined/GC |
| --- | --- | ---: | ---: | ---: | ---: |
| dict_count | QBE | 979,548,715 | 913,581,841 | 0.932656 | 1.381481 |
| dict_count | LLVM | 644,371,445 | 612,385,509 | 0.950361 | 1.388517 |
| schematic fixture | QBE | 296,628,267 | 226,310,431 | 0.762943 | 12.170259 |
| schematic fixture | LLVM | 222,512,201 | 159,638,419 | 0.717437 | 17.622799 |
| schematic changed-net | QBE | 295,767,529 | 224,658,215 | 0.759577 | 12.075693 |
| schematic changed-net | LLVM | 216,519,534 | 159,888,531 | 0.738449 | 17.641553 |
| schematic changed-value | QBE | 296,127,716 | 224,743,829 | 0.758942 | 12.086324 |
| schematic changed-value | LLVM | 216,774,765 | 159,159,136 | 0.734214 | 17.571440 |

This is a focused four-program diagnostic, not a new 30- or 43-program result.
The [preceding 30-program measurement](d9-rc-loops-joined-parity-2026-09-27.md)
remains bound to its earlier compiler. No Lox program was measured here, and
component improvements must not be multiplied into an assumed corpus result.

The source combines managed readonly helpers `b6ff7788` and registered plain
dictionary overwrites `0efd82ad` through real two-parent merges. The only merge
conflict retained both independent emission-plan fields and their initializers.
The Debug compiler SHA256 is
`db9d8791fb56a9c07e5db529b5abe54b2689966364095de89e2abcaca4409b2b`;
the prior Debug compiler is `49a8df2d575b65b16d3e7b455a8b0d6a3aa11ac4eccc13ad34dc3eeb8b54ebd5`.
Accepted GC remains the original immutable compiler and binaries. Both RC
source and HEAD remained fixed throughout measurement.

The [archive](../../experiments/d9-rc-helpers-word-joined-20260927/README.md)
contains 72 raw instruction observations at 100% counter running on CPU2,
72 separate peak-RSS observations, exact-output checks and sixteen counted RC
executions. Each side uses median three; ordering alternates between repetitions.
Native manifests establish actual QBE or LLVM O3/full-LTO execution, including
separate stats binaries. The verifier recomputes measurements from raw stderr,
checks accepted output hashes, compiler/binary identities and cross-backend counts.

Dictionary counters are unchanged: 2,001 O acquisitions, 2,001 H pairs and
2,029 allocations/retirements. Schematic fixture and changed-value O acquisitions
fall 124,879→93,402 and H pairs 292,743→248,006. Changed-net O falls
124,851→93,402 and H pairs 292,985→248,296. Schematic allocation and retirement
counts remain 156; both backends have identical counters on each side.

All four programs use more peak RSS than accepted GC in this focused sample.
This does not contradict the earlier lower corpus median: these are different
sets of programs. Neither the complete-corpus memory requirement nor its
instruction geomean can be decided from this diagnostic. GC remains the default,
and full unchanged 43-program acceptance remains open.

The evidence change passes documentation coverage and all 88 whole-tree
Guardian checks. The separate integration checkpoint owns the full correctness
gate and forced backend sweeps for this compiler.
