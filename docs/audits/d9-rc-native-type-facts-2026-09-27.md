# Stage 4 native type-fact cache

The bounded native type-fact cache removes repeated type-only walks from generic
loan and physical retain. On the unchanged full N10 Lox binary-trees workload,
matched median-three retired instructions fall **10.32% on QBE and 12.01% on
LLVM**, with identical output and exact ownership counters. The result remains
**31.23× and 51.20× accepted GC** respectively. This is an isolated improvement,
not Stage 4 performance acceptance; the mandatory full corpus remains open.

## Measured identities and method

The control is joined source `5b87601297f01810968b9f7ac554c484d5848cca`, including
the corrected field-snapshot admission, scalar-record publication, private
append descriptor-repeat cache and nonheld capture proof. Its immutable Debug
compiler SHA256 is
`f87393b249f45699d63a1f5a81dc47fb59faa41d1396fc8035131d7b2533b120`.
The candidate Debug compiler is
`2db0563ac88bfacebbe5b7c7c599069b8b80b1e7c8acc9e1cdb3d53f9fe0f54a`.
[The archive](../../experiments/d9-rc-native-type-facts-20260927/README.md)
records compiler paths, every guest binary and manifest, input hashes, the exact
production patch and all raw samples. LLVM guests are actual LLVM O3 with full
LTO; no QBE override follows the LLVM selection.

All matched production measurements run on CPU2, alternate control/candidate
order, and use the median of three unscaled retired-instruction observations.
Counts run separately from production timing. The complete mandated N10 script
and expected output are unchanged. The GC denominators are archival accepted-GC
median-three observations from completed rows of the original corpus experiment, built
with immutable accepted Debug compiler `8c813407…` / source `f6bea5d9`; they are
not fresh interleaved GC measurements. Their exact identities and selected raw
reference medians are included without inherited host environment data.

| Backend | Control instructions | Candidate instructions | Candidate/control | Control/GC | Candidate/GC |
|---|---:|---:|---:|---:|---:|
| QBE | 252,227,750,356 | 226,186,229,764 | 0.896754 | 34.822562× | 31.227270× |
| LLVM O3/full LTO | 199,778,336,716 | 175,793,374,664 | 0.879942 | 58.190853× | 51.204583× |

All twelve Lox production observations report 100% event running. Each of the
four counted runs has 4,350,608 heap allocations and retirements, 81,463,495 owner
acquisitions, 85,814,103 owner releases, 276,752,828 hold acquisitions/releases,
1,095,889 clones and 20,836,904 uniqueness checks; no arenas, limit events or
counter saturation. Counts match exactly before/after on both backends.

## Non-target measurements

The same immutable pair ran six unchanged comparison workloads. All 72 raw
instruction observations report 100% event running; the 24 separate counted
runs match exactly. Scalar append and sieve are neutral, allocation churn
improves modestly, and all schematic cases improve. Guest emission hashes match
before/after for all four build keys; output/SVG checks pass. GC ratios use the
same archival reference convention as Lox.

| Workload / backend | Control instructions | Candidate instructions | Candidate/control | Control/GC | Candidate/GC |
|---|---:|---:|---:|---:|---:|
| parity/suite/sieve / qbe | 4,180,751,883 | 4,180,751,819 | 1.000000 | 5.084234× | 5.084234× |
| parity/suite/sieve / llvm | 1,671,745,440 | 1,671,745,473 | 1.000000 | 7.527070× | 7.527070× |
| parity/micro/alloc_churn / qbe | 8,014,233,062 | 7,972,232,944 | 0.994759 | 2.618898× | 2.605173× |
| parity/micro/alloc_churn / llvm | 5,320,233,640 | 5,297,233,677 | 0.995677 | 2.727750× | 2.715957× |
| parity/micro/list_append_sum / qbe | 2,518,577,597 | 2,518,577,785 | 1.000000 | 4.252235× | 4.252235× |
| parity/micro/list_append_sum / llvm | 1,222,706,883 | 1,222,706,901 | 1.000000 | 4.964809× | 4.964809× |
| schematic/fixture / qbe | 349,813,882 | 325,554,267 | 0.930650 | 18.811427× | 17.506854× |
| schematic/fixture / llvm | 245,971,748 | 237,622,749 | 0.966057 | 27.151912× | 26.230297× |
| schematic/changed-net / qbe | 347,943,521 | 325,697,966 | 0.936066 | 18.701983× | 17.506283× |
| schematic/changed-net / llvm | 245,483,810 | 237,764,181 | 0.968553 | 27.084566× | 26.232849× |
| schematic/changed-value / qbe | 345,939,686 | 325,620,552 | 0.941264 | 18.603960× | 17.511237× |
| schematic/changed-value / llvm | 245,857,567 | 237,591,770 | 0.966380 | 27.141932× | 26.229413× |

## Attribution and implementation

The preceding scalar-record compiler slice removed all 36 broad Runtime loans
in `vm::run`. The remaining 58 sites there already qualify for flat loans. Fresh
sampling of the corrected joined binary instead identifies repeated
`myl_rc_native_has_unique` in generic object-variant loan/retain paths: about
11.4% of QBE sample weight and 12.8% of LLVM weight. QBE hardware branch records
identify direct native-loan and physical-retain callers and recent guest calls
in string-object, object-field, frame and property helpers. The hot string-object
loan uses a 56-byte variant descriptor. These are observed branch records, not
complete reconstructed call stacks.

The original validator traverses native inline type metadata, including every
variant arm and a typed box's body-finalizer obligation even for a null value.
It does not traverse actual managed payloads. The candidate stores its completed
answer in a three-state byte within existing private binding padding, queried
using the descriptor binding the generic loan/retain path already found. It adds
no hash lookup, public ABI field, reservation bytes or allocation. Unregistered
root types and direct validator callers retain the uncached walk. Semantic
publication is deliberately unchanged.

The first query preserves the authoritative iterative walk and idle-walker
invariant; every warm hit preserves that invariant too. Missing typed-box body
registration still fails before a negative answer can be cached. Bindings remain
at stable addresses through registry growth, and completed answers remain valid
because their consulted native type identities and descriptor callbacks cannot
change. Separate heaps and destroy/reinitialize do not share facts.

More precisely, the descriptor prefix and structural metadata are immutable;
the whole private binding is not, because its cache byte is lazily updated under
the existing serial heap-local contract. The older introductory comment in
`native_rc_values.c` still says “immutable private bindings.” That wording is
clarified here and intentionally left untouched in this frozen measured source;
it can be corrected at the next naturally rebuilt source checkpoint.

Dynamic payload-finalizer refusal, regions, pins, owner/hold counts, rollback,
clear-before-callback and final drain remain on their existing paths. In
particular, caching an opaque pointer's false type predicate cannot legalize a
loan of a dynamically finalized payload; physical retain of that payload remains
legal. The cache does not remove the separate transfer-stack allocation or its
refusal for deeper values. Flat size remains 72 bytes, binding size 128, count
and loanable offsets 64/68; the cache occupies offset69. Ordinary/counting heap
and RC-state layout comparisons are unchanged.

The candidate's after-profile no longer samples the type validator/cache helper.
Descriptor lookup, generic walk/visit and loan work remain substantial; this
supports the attribution without implying that the remaining generic transfers
may be omitted. Profiles contain throttle records, no lost samples, and are
qualitative. The archive also preserves the earlier historical `6a75eb2a`
profiles and a failed DWARF-unwind attempt as separate negative evidence.

## Correctness and integration boundary

Root and the collections agent reviewed the design and concrete diff without a
blocker. All 150 production C scenarios pass with ASan/UBSan and counting:
loans19, semantic history42, holds12, arenas10, contract25, collections42. The
same scenarios also pass against the old authoritative runtime sources; the new
private test query uses a documented uncached adapter in that comparison. It is
not the measured control binary, which uses the original complete baseline.

The five new scenarios cover inactive variant arms containing all raw unique
kinds, deep records/arrays, warm/cold workspace refusal, null typed boxes,
missing/late body registration, different finalizers in separate heaps,
destroy/reinit, dynamic finalized payload refusal, idle-walker enforcement,
exact-budget failed registration and reentrant successful index growth. Existing
suites retain duplicate near-limit prefix rollback, sticky status, arena/pin and
queued-sibling finalizer controls. Assertions preserve size and offsets; explicit
ordinary/counting layout probes agree before and after.

Both immutable compilers pass all 66 guest assertions on each actual backend
(264 total), uncached, spanning scalar appends, semantic history, live views,
aggregate ownership, iteration identity, scalar-record writes, record-field
snapshots and boxed write-back. The focused Debug wrapper passes 12/12; Debug
installation passes 19/19 and Guardian88. Root owns the later full integration
gate and serialized Guardian feedback. This slice does not change ratchets,
language main, runtime selection defaults or the Stage 4 acceptance threshold.
