# Pinned retirement implementation checklist

Source: `44947e6967d8eb0deeaa86b25ca2bb44bc58803d`. Every item below is unapplied. C1 and C2 qualification remain prerequisites.

Root froze one mandatory `guest_abi.Abi.checked_owned_v1` contract. Remove optional modes and shared-list state; reject missing or foreign ABI at restored-artifact and native-link boundaries. Bump formats/keys so old numeric zero cannot become the new enum accidentally.

## mandatory-abi

**Owner:** A07; coordinator shared declarations.

Remove optional Module/build.Input ownership modes and shared_lists. Add core/guest_abi.zig Abi { checked_owned_v1 }. Make checking, helper contracts, owned map/sort/resource lowering and invalid retain/is_unique refusal unconditional. No implicit unchecked-source entry.

Preserve: Direct destruction represented by IR release; deep-copy, ownership checks, source spans and invalid-IR diagnostics.

Dependency: Exact agreed API: enum(u32) checked_owned_v1=0x4f574e31 (OWN1), guest_abi.current and identity="mylang-checked-owned-v1"; mandatory validate/check replace validateMode/checkMode. Every direct build/hand-IR caller in internal-api-calls.json must migrate. Negative old IR can remain only as refused input.

| File | Pinned hunk anchors |
| --- | --- |
| `src/core/ir.zig` | 599, 600, 603, 612, 613, 617, 618 |
| `src/core/build.zig` | 29, 71, 100, 101, 194, 195, 218, 222, 278, 327, 373, 374, 684, 805, 823, 841, 851, 911, 1073, 1142, 1231, 1238, 1342, 1651, 1743, 1813, 2311, 2452, 2466, 2544, 2584, 2585, 2586, 2588, 2709, 2739 |
| `src/core/zero_rc.zig` | 196 |
| `src/core/verify_ir.zig` | 97, 191, 205, 439, 447, 583, 584, 585, 652 |

## ownership-pass

**Owner:** A07.

Remove lists-only/RC source contract, snapshot-family opt-in and count/uniqueness execution paths. Retain diagnostics for forbidden IR; never generate executable retain/is_unique. Simplify independent copies and transfers under one ABI.

Preserve: Owned phi copies, direct cleanup at returns/branches/replacements, recursive box-shell traversal, source borrow and provider checks.

Dependency: Atomic with mandatory-abi and emitter/runtime groups. Counting IR may not escape through hand-built, cached or unoptimized emission.

| File | Pinned hunk anchors |
| --- | --- |
| `src/core/own.zig` | 15, 88, 147, 161, 162, 191, 453, 462, 797, 872, 878, 880, 1307, 1371, 1376, 1394, 1439, 2154, 2160, 2166, 2223, 2246, 2258, 2325, 2350 |
| `src/core/single_owner.zig` | 3, 8, 37, 64, 66, 82, 92, 93, 94, 95, 97, 117, 127, 128, 133, 150, 151, 189, 205, 216, 220, 228, 236, 239, 246, 252, 258, 311, 335, 339, 372, 534, 535, 546, 555, 573, 597, 673, 693, 717, 722, 726, 736, 831, 861, 862, 864, 867, 905, 911, 912, 929, 979, 981, 1035, 1043, 1114, 1118, 1130, 1132, 1136, 1137, 1138, 1140, 1141, 1146, 1148, 1167, 1171 |
| `src/core/single_owner_copy.zig` | 4, 12, 13, 14, 17, 18, 48 |
| `src/core/runtime/core_owned_copy.c` | semantic audit: no active matching branch |

## llvm-runtime-boundary

**Owner:** A07; extra emitter files require coordinator assignment.

Delete counted header emission/RC helper declarations, countedValue, uniqueness and legacy descriptor callback generation. Emit one kind-at-zero ABI and owned entry/Result cleanup. Invalid RC operations always refuse.

Preserve: Static-storage kind bit, home/stack destruction, child-layout metadata and direct owned drop calls. Release names are not automatically RC.

Dependency: A02 header and A05 dictionary layout walkers; A08 mandatory artifact marker before native linking.

| File | Pinned hunk anchors |
| --- | --- |
| `src/core/emit_llvm.zig` | 10, 13, 33, 75, 76, 78, 125, 141, 142, 199, 200, 202, 203, 206, 207, 208, 237, 240, 270, 271, 334, 341, 351, 373, 374, 402, 403, 482, 483, 484, 497, 617, 618, 625, 627, 628, 629, 636, 656, 663, 664, 665, 709, 755, 793, 969, 989, 999, 1000, 1001, 1003, 1004, 1054, 1080, 1081, 1144, 1182, 1247, 1249, 1250, 1251, 1252, 1253, 1256, 1269, 1279, 1296, 1460, 1483, 1487, 1514, 1515, 1517, 1694, 1695, 1696, 1702, 1713, 1718, 1725, 1727, 1728, 1731, 1735, 1736, 1737, 1762, 1765, 1771, 1988, 1989, 2024, 2026, 2166, 2167, 2169, 2185, 2187, 2188, 2189, 2192, 2193, 2197, 2215, 2320, 2553, 2572, 2636, 2654, 2868, 3079, 3091, 3093, 3124, 3125, 3127, 3151, 3154, 3227, 3283, 3286, 3293, 3301, 3313, 3320, 3404, 3405, 3411, 3439, 3440, 3447, 3448, 3450, 3452, 3454, 3458, 3460, 3487, 3519, 3521, 3523, 3529, 3532, 3533, 3536, 3538, 3540, 3546, 3547, 3549, 3554, 3555, 3563, 3564, 3565, 3566, 3568, 3569, 3573, 3574, 3579, 3586, 3592, 3593, 3595, 3597, 3606, 3616, 3618, 3622, 3625, 3722, 3723, 3728, 3731, 3732, 3770, 3787, 3788, 3803, 3853, 4114, 4115, 4122, 4123 |
| `src/core/emit_release.zig` | 1, 11, 17, 68, 72 |
| `src/core/emit_cap.zig` | 5, 14 |
| `src/core/emit_text_split.zig` | 144, 148 |
| `src/core/emit_homes.zig` | 32, 494, 918, 1122, 1126, 1127 |

## container-lowering

**Owner:** A07 proposed; A02 owns build_list_methods; A04 owns build_values.

Select existing independent copy/take/default/provider/view paths unconditionally. Remove old alias-producing text/bytes copy and dictionary key/value reuse alternatives. Make owned update-fusion proof mandatory.

Preserve: Borrow selection and aggregate provider validators; scalar operations, take flags, selected-copy semantics, deliberate direct-root-rebind iteration snapshots.

Dependency: Confirm reservations with coordinator. Source .snapshot() remains explicitly refused; physical fresh copies required for supported independent returns.

| File | Pinned hunk anchors |
| --- | --- |
| `src/core/build_bytes.zig` | 1, 103 |
| `src/core/build_cap.zig` | 24, 292, 308 |
| `src/core/build_dict.zig` | 97, 167, 188, 189, 203, 245, 260, 379 |
| `src/core/build_text.zig` | 1, 79 |
| `src/core/build_borrowed_view.zig` | 37 |
| `src/core/fuse_slice_key.zig` | 69, 136 |

## list-runtime

**Owner:** A02; coordinator shared header approval.

Keep count-free header/static marker and direct traversals. Delete count storage/helpers/saturation/COW arms and conditional buffer_own. Preserve owned rotate/reverse/same_block and deep-child copies; simplify list method forks.

Preserve: Growth/reserve/overflow guards, allocator live statistics, child visitor, task/provider finalization and counted instrumentation hooks for allocation traffic.

Dependency: A07 emit descriptors, A05 child walkers, A09 count_runtime anchors must change together. Shared layout remains 32-byte aligned; count-free does not imply zero allocation.

| File | Pinned hunk anchors |
| --- | --- |
| `src/core/runtime/core_rt.c` | 96, 108, 109, 110, 112, 115, 122, 123, 127, 131, 132, 133, 134, 141, 142, 143, 146, 154, 155, 156, 159, 161, 166, 168, 169, 170, 174, 176, 177, 182, 183, 189, 193, 194, 201, 203, 204, 205, 208, 211, 394, 704, 749, 750, 751, 756, 765, 774, 815, 816, 836, 837, 843, 847, 862, 863, 865, 871, 873, 874, 885, 893, 894, 896, 909, 910, 918, 919 |
| `src/core/runtime/core_bytes.c` | 145, 148, 150 |
| `src/core/build_list_methods.zig` | 36, 55, 133, 163, 276, 311, 313 |

## parallel-runtime

**Owner:** A01.

Remove five RC branches and make owned submit/take/end/map available without selector. Privatize or remove old result/group-close aliases after all generated callers migrate. build_parallel already contains owned chunks only.

Preserve: Pending-work/ready/futex atomics, mandatory joins, ordered output, environment lifetime and exactly-once untaken-result destruction.

Dependency: A01 retirement/integration-44947 owns exact three-patch set; A07 build.zig map selector request must integrate. Native stress/TSan after real application.

| File | Pinned hunk anchors |
| --- | --- |
| `src/core/runtime/core_tasks.c` | 9, 38, 52, 56, 63, 64, 66, 71, 72, 73, 76, 77, 81, 82, 83, 84, 85, 87, 90, 92, 94, 99, 100, 101, 103, 104, 105, 128, 134, 135, 143, 144, 146, 153, 156, 216, 217, 218, 234, 239, 240, 241, 250, 270, 272, 274, 275, 276, 278, 282, 284, 292, 293, 294, 300, 302, 303, 304, 309, 315, 324, 327, 331, 335, 341, 351, 368, 390, 391, 392 |
| `src/core/build_parallel.zig` | 114 |

## text-render-runtime

**Owner:** A04.

Keep static-literal append copy, fresh text encode bytes, owned float-render cleanup and independent list repetition; delete legacy count/share alternatives.

Preserve: Unicode/invalid-input behavior, round/format helper contracts, rendering caller-destination work and numeric runtime ABI.

Dependency: A02 header and A07 emitter/contract agreement; rerun text/JSON allocation controls on exact C3 compiler.

| File | Pinned hunk anchors |
| --- | --- |
| `src/core/runtime/core_text.c` | 310, 313, 595, 600, 688 |
| `src/core/runtime/core_values.c` | 337, 340 |
| `src/core/build_values.zig` | 53 |

## collections-providers-runtime

**Owner:** A05.

Delete counted dictionary child copies/descriptors, legacy keyed sort, provider retain/root-sharing branches and now-useless cap retain calls. Retain owned transfer paths.

Preserve: Resource closes, direct cleanup, persistence snapshots as independent storage, filesystem locks and native provider buffers. Host file snapshots are not COW.

Dependency: A05 retirement previews; A07 lowering selects owned keyed sort; A02 traversal callbacks/header; resource support and protocol gates remain mandatory.

| File | Pinned hunk anchors |
| --- | --- |
| `src/core/runtime/core_dict.c` | 200, 203, 220, 221, 331, 337, 341, 367, 368 |
| `src/core/runtime/core_sort.c` | 827, 841, 844, 850, 854 |
| `src/core/runtime/core_io.c` | 151, 152, 182, 225, 279, 319, 365, 367, 368, 409, 415, 431, 434, 437, 455, 578, 618, 619, 727, 748, 749, 751, 755, 756, 757, 758, 764, 766, 831, 832, 833, 853, 871, 992, 995, 999, 1000, 1006, 1007, 1012, 1040, 1055, 1063, 1170, 1176 |
| `src/core/runtime/core_host.c` | semantic audit: no active matching branch |
| `src/core/runtime/core_durable.c` | 194 |

## cache-link-abi

**Owner:** A08 with A07 mandatory ABI.

Use mandatory checked_owned_v1 in fresh text and compact native receipts. Remove OR aggregation of per-unit mode bits and runtime RC selection. Reject missing/old/foreign/mixed ABI; bump persisted layouts and keys so old false/zero cannot decode as owned.

Preserve: Complete compiler/source identities, invalid-marker cache misses, no stale green-source replay, debug source origins, counters choice independent of memory ABI.

Dependency: Root newly assigns driver/emit_units/ir_snapshot to A08; additional key files require exact reservation confirmation. Retained C0 caches must remain frozen for negative transitions.

| File | Pinned hunk anchors |
| --- | --- |
| `src/core/lowering_cache.zig` | 302 |
| `src/core/optimization_cache.zig` | semantic audit: no active matching branch |
| `src/core/emission_cache.zig` | 49, 74 |
| `src/core/emission_key.zig` | 44, 45 |
| `src/core/canonical_ir.zig` | 173, 174, 231, 232 |
| `src/core/ir_snapshot.zig` | 113, 114, 115 |
| `src/core/emit_units.zig` | 13, 14, 15, 176, 195, 259, 266, 327, 343, 344, 349, 350, 356, 399, 404, 421, 499 |
| `src/core/driver.zig` | 189, 191, 326, 327, 330, 338, 520, 818, 1088, 1093 |

## commands-and-analysis

**Owner:** A10; A07 owns allocation_contract narrow validation; coordinator compiler declaration.

C2 enable checked ordinary commands only after qualification. C3 remove selectors and internal mode bypasses, keep eager checking across sessions/receipts/portable keys, remove RC encode-noalloc exception, update docs/help and directory/doctest forwarding. Retired flags exit2 including =value; tokens after guest -- remain data.

Preserve: Diagnostic dump-ir --facts can show failing intermediate IR; its status is not executable qualification. Unsupported-only guest test status0 remains existing contract; qualify only unsupported==0.

Dependency: CLI patches regenerated at44947 are narrower than full C3 API deletion and must combine with A07/A08 contract. Internal modes cannot remain writable escape hatches.

| File | Pinned hunk anchors |
| --- | --- |
| `src/main.zig` | 676, 830, 831, 847, 852, 853, 905, 906, 1230, 1231, 1999, 2072, 2448, 3178, 3182 |
| `src/core/main.zig` | 5, 21, 22, 28, 29, 44, 78, 79, 83, 84, 85, 86, 87, 90, 120, 126, 128, 133, 213, 214, 215, 216, 217, 368, 369, 370, 486, 487, 488, 489, 490, 505, 510, 516, 520, 525 |
| `src/core/cli.zig` | 16, 27, 160, 161, 162 |
| `src/core/cli_args.zig` | 169, 170, 171, 172, 173 |
| `src/core/check_command.zig` | 4, 19, 20, 36, 41, 57, 91, 92, 93, 94, 95 |
| `src/core/pipeline.zig` | 4, 79, 80, 154, 162, 189, 196, 228, 249, 251, 262, 318, 319, 499, 500, 501, 548 |
| `src/core/frontend.zig` | 105, 106, 286 |
| `src/core/allocation_contract.zig` | 10, 108, 109 |
| `src/core/cost.zig` | 12, 37 |
| `src/core/cost_command.zig` | 18, 32, 60, 116, 117, 118, 138, 146, 257, 258, 267, 276, 283, 301, 318, 326, 328, 329, 341, 364, 371, 373, 406, 408, 426, 432, 434 |
| `src/core/test_runner.zig` | 210, 342, 367, 369, 570, 682, 1734, 1735, 1752, 1754 |
| `src/core/test_runner_affected.zig` | 35, 104, 105 |
| `src/core/test_runner_directory.zig` | 540, 983, 984, 985, 987 |
| `src/doctest_command.zig` | 49, 61, 160, 172, 184, 185, 285, 864, 867, 997, 1715, 1716, 1717, 1719 |
| `src/compiler.zig` | 4 |

## runtime-instrumentation

**Owner:** A09; coordinate emit_count with A07/root.

Remove active RC instrumentation anchors and legacy helper declarations as runtime disappears. Preserve counters-v1 zero RC telemetry fields; direct release_unique is destruction, not a reference decrement.

Preserve: Allocation/growth/copy/peak/exit-live hooks and exact recursive managed-copy traffic; static cleanup site labels are separate from dynamic RC events.

Dependency: A09 count runtime/test previews; counter replay adapter must be re-reviewed/requalified for changed C3 runtime recipe, never relabel Support6 controls.

| File | Pinned hunk anchors |
| --- | --- |
| `src/core/count_runtime.zig` | 63, 67, 71, 75, 105 |
| `src/core/emit_count.zig` | 3, 30, 31, 32, 33, 70, 189, 190 |
| `src/core/cost_dynamic.zig` | 9, 14, 78, 94, 95, 96, 97, 98, 120, 121, 122, 123, 124, 137, 140 |

## installed-components

**Owner:** A10; root build/verify files.

Select a real independently qualified checked-default source pin by default. Pin and manifests require memory_mode=zero-rc-v1, ownership_selection=checked-default-v1 and guest_abi=mylang-checked-owned-v1. Retire legacy fallback and selector forwarding in installed tools/selka-components. Validate these fields at both launch and verification inventory boundaries; refuse stale MYLANG_COMPONENT_DIR deployments.

Preserve: Immutable historical component-seed.json/commits, independent seed-compiler target, reviewed toolchain, source/hash/protocol evidence, installed bin/libexec/tools layout and newly added build.lock.

Dependency: Support6 opt-in pin is real and qualified, but is not a selector-free C3 pin. Need actual C3 source commit/archive, RF seed, both fresh protocols/ABI audits and fresh installed package proof.

| File | Pinned hunk anchors |
| --- | --- |
| `selfhost/components.zig` | 11, 99, 100, 103, 120, 121, 176, 294, 325, 347, 367, 378, 384 |
| `selfhost/test_component_native.py` | 42, 51, 55 |
| `selfhost/test_components.py` | 54, 90, 109, 110, 111, 112, 118, 119, 124, 125, 129, 135, 137, 142, 143, 145, 161, 166, 362, 376, 378, 381 |
| `build.zig` | 178, 552, 553, 559, 588, 591, 831 |
| `build_test_inputs.zig` | semantic audit: no active matching branch |
| `src/component_launch.zig` | 131, 134, 139 |
| `src/component_adapter.zig` | 52, 115 |
| `src/cache_plan_adapter.zig` | 152, 157 |
| `scripts/verify_cache.py` | 516, 536, 678, 693, 744 |
| `scripts/affected_tests.py` | 451, 556 |
| `scripts/fuzz_campaign.py` | 450 |

## source-boundary-wording

**Owner:** coordinator; exact helper reservations as needed.

Update recursive owning-provider diagnostics to owned boxed values; preserve refusal. Remove executable list snapshot lowering/offerings or retain syntax solely for a clear retired/unsupported diagnostic; never permit a COW path.

Preserve: Persistent/durable semantic snapshots and root-rebinding entry copies retain their independent-storage contracts.

Dependency: SPEC current clauses and public export documentation must match tested source behavior; historical diagnostics/reports remain immutable.

| File | Pinned hunk anchors |
| --- | --- |
| `src/record_layouts.zig` | 171, 173 |
| `src/buffer_operations.zig` | 191, 240, 317, 500, 586, 611 |
| `src/collection_lower.zig` | 121, 400 |

## Registered tests and internal callers

`retirement-inventory.json` preserves every current selector site, enclosing test/helper, owner suggestion and importing registration file. It also lists every test name in the legacy-control suites; this is a review obligation, not permission to drop a suite. `internal-api-calls.json` includes the remaining inline-source and hand-IR drivers even when their text has no RC word.

C2 must run ordinary guest commands across the full registered suite and repair source semantics/expected default diagnostics. C3 removes the selector from positive tests, replaces counted/COW assertions with owned/refusal assertions, and migrates all direct API constructors. Preserve every existing output, error-path and trap oracle unless the retired source contract itself is the negative assertion. Never set an active test back to RC to make the gate pass.

High-risk suites: own_test, row_cow_test, single_owner_test snapshot families, shared_counts/runtime_threads/share_walk, consume_test borrowed-alias controls, count_test snapshot comparison, cost_test RC sites, f1/CE record/result/iteration/dictionary controls. Keep zero_rc negative snapshots, borrow_summary invalid count-op cases, and wrong-ABI tests as explicit refusals.

The raw site/call totals are inventory sizes only. They are not remaining-bug counts or measured test completion.

## Package blockers beyond flags

The pinned default component builder still reads historical component-seed.json when no owned override is supplied. tools/selka-components is installed and therefore that route itself must retire. Root build and native component test forwarding are optional today; affected-compiler and verification preparation inherit that choice. scripts/affected_tests.py and fuzz fallback component directories must observe the resulting installed owned package.

Both component adapters call component_launch.artifactSnapshot, whose current Manifest ignores memory_mode and ownership_selection. MYLANG_COMPONENT_DIR can therefore choose a digest-valid legacy package. The prepared C3 launch patch rejects missing/legacy/opt-in markers and revalidates warm planner bindings. Synthetic manifest tests are boundary tests, never ABI proof.

scripts/verify_cache.py artifact_paths/artifact_providers currently admit filename-only component manifests; coordinator must add matching owned package proof and fixture coverage. Component reference/shadow modes select host Zig oracle implementations and remain legitimate; they are not guest memory modes.

Support6 independent RF seed/compiler and both exact component sources have real protocol/count/ABI evidence, but still select ownership with a prototype flag. A real selector-free C3 source pin, archive, compiler, component receipts/binaries and installed layout must be freshly qualified. Historical seeds remain unchanged. Preserve the newly integrated components build.lock.

## Deliberate non-RC matches

- Zig allocator retain_capacity/retained analysis trees are compiler memory, not guest RC.
- Protocol/cache snapshot digests and sealed byte snapshots are not COW.
- Task pending/ready counters synchronize work.
- IR release/direct owned destruction and resource release remain necessary.
- Independent persistence snapshots and literal static storage remain supported.
- counters-v1 zero RC labels are telemetry compatibility; release_unique counts direct destruction.
