Resource measurements for the exact final source and guest inventory.

Binary bytes and ELF .text bytes are static file observations. Peak RSS is one whole-process probe per cell,
including fixtures/runtime/teardown; it is neither a repeated distribution nor kernel-live memory.
Compile logs record commands/status/streams but no timed guest compile duration. The host build receipt
records one elapsed build interval with its cache/slot/load state; it is not a comparative compiler-speed result.

| Guest group / arm | Binary bytes | ELF .text bytes | Binary SHA256 |
|---|---:|---:|---|
| legacy/my-llvm | 427640 | 160546 | `0b0b8183a6366d9afb65a2a610ca304ad142f2012d8aa39cc7fbc482249b0b76` |
| legacy/my-qbe | 1216832 | 187718 | `8f58a6f0ae7b571155986a10ba8acf8791516b3c5717506cf6393bcc67a1081e` |
| legacy/rust | 4526224 | 264179 | `cc6488c8f54e33c93e483b78db70d21ef88309bbb38856394a5e94abde17099f` |
| legacy/go | 2382810 | 639953 | `2e8d267a37dd077ba5993c00658197c739750cdde576a3c2b98261c9f133bd17` |
| legacy/zig-safe | 3324424 | 379609 | `ed51d49b2018d1543fff0e80b7d23cb8b941e232fd93033cfc7f4b0175b8b4cd` |
| legacy/zig-fast | 3622152 | 383225 | `5ec59c0266719ed9b4d926a243432a903e66f672034227f3653ca11c41bc81bb` |
| compute/my-llvm | 467344 | 169554 | `366d46cc759592fd6d21f23e5a786d98516c29492b9c55a0c766f126c705f8b3` |
| compute/my-qbe | 1268296 | 204125 | `a170973d4d4661cf496b82943cd366db597c1ef6e94d518a8805c9fbf8eb708c` |
| compute/rust | 4528256 | 265859 | `342de880685aeee869ada3a39ad109b59795221d944b5e0b2089a7eaebc83655` |
| compute/go | 2389034 | 641233 | `9d7e9f9c912eb8f93f2c610023ddad89a52a473f90d569d038947edacbd48b68` |
| compute/zig-safe | 3322064 | 379945 | `807a12c75a50a9e59590e710a84ed874132e3d2e273b83a23475b04f1c8eec2a` |
| compute/zig-fast | 3615680 | 382617 | `eef38971a3afb65f80d611a6d1ab23cec85d5fbac71841d35538e4823dd28928` |
| collections/my-llvm | 647568 | 292002 | `b7ae862d780cdfc4535003f4bf0529e95f583e1b633ba3cbf1de3260899ec1c1` |
| collections/my-qbe | 1540912 | 418166 | `c328445225d6d9dbd820b07698d267f547126d544236ea501196f4919cbf5b00` |
| collections/rust | 4586600 | 298163 | `4b7ee53e36cbc6eefaf6bf2b559906eecf348a18ee2fc5acc90b3aceb9d93d21` |
| collections/go | 2439286 | 659025 | `039eca570573f3fa304e3ec5e3df2976a9256e1ee7af43a9192a58bdd9917da6` |
| collections/zig-safe | 3678912 | 438633 | `77f77faf4a8a3f4f5956b81efc737f598933ff48cd0938f6df3a8d005a2e096b` |
| collections/zig-fast | 4109152 | 466441 | `ab34bafd6a39d4a6fefe32ab4720c6fa6b0c3b322072b9bac55ca1620b095d0b` |
| text/my-llvm | 954584 | 429282 | `6b74952f6efd556a087288086664ef0dc2de827db2d49fb40aa2ac93c8f408fd` |
| text/my-qbe | 2172272 | 770813 | `63ac808ad71028cefdb3b2799c5b74ef212c61c28cfc6dd0f7a75c27ec80401c` |
| text/rust | 687800 | 374595 | `230ff4317181142193c29c7ee5f260fa6866d527fb59caf512aefe33c1a0b7d4` |
| text/go | 3957709 | 1201105 | `afb67832762f3925b772321b0a0ee58101305268d7935eec0669e7c49e9c38d3` |
| text/zig-safe | 3712200 | 437161 | `6ae0410adb082a0a657a5b23ddc24751a9cfbe31763f082b84f7376a01835649` |
| text/zig-fast | 4155512 | 458937 | `aee37be81b0094356f1f4323d6979530082101a1adf368d8792118b5a1447e6f` |

Every cell below reports the recorded single-process peak RSS in KiB.

| Case / size | Rust | Go | Zig ReleaseSafe | Zig ReleaseFast | MyLang LLVM | MyLang QBE |
|---|---:|---:|---:|---:|---:|---:|
| record_reads / small | 2172 | 2044 | 2340 | 2344 | 2600 | 2804 |
| record_reads / large | 2656 | 2244 | 2660 | 2660 | 3268 | 3572 |
| tagged_stack / small | 2188 | 2040 | 2340 | 2348 | 2600 | 2588 |
| tagged_stack / large | 2352 | 2036 | 2344 | 2336 | 2552 | 2632 |
| mutate_unique / small | 2192 | 2056 | 2340 | 2348 | 2656 | 2764 |
| mutate_unique / large | 2184 | 2052 | 2344 | 2348 | 2728 | 2780 |
| mutate_shared / small | 2192 | 6700 | 2344 | 2348 | 2536 | 2588 |
| mutate_shared / large | 2192 | 7680 | 2344 | 2348 | 2556 | 2592 |
| integer_math / small | 2172 | 2040 | 2344 | 2344 | 2788 | 2760 |
| integer_math / large | 2652 | 2292 | 2660 | 2664 | 3396 | 3432 |
| float_math / small | 2196 | 2056 | 2344 | 2344 | 2760 | 2628 |
| float_math / large | 2676 | 2292 | 2664 | 2664 | 3612 | 3484 |
| branch_predictable / small | 2180 | 2052 | 2344 | 2344 | 2812 | 2664 |
| branch_predictable / large | 2660 | 2292 | 2660 | 2664 | 3572 | 3448 |
| branch_mixed / small | 2196 | 2056 | 2344 | 2344 | 2772 | 2680 |
| branch_mixed / large | 2664 | 2292 | 2664 | 2664 | 3560 | 3468 |
| record_construct / small | 2180 | 2040 | 2344 | 2344 | 2772 | 2640 |
| record_construct / large | 2652 | 2292 | 2664 | 2664 | 3400 | 3424 |
| record_update / small | 2164 | 2036 | 2344 | 2340 | 2588 | 2664 |
| record_update / large | 2676 | 2292 | 2664 | 2664 | 3560 | 3440 |
| call_direct / small | 2196 | 2040 | 2344 | 2344 | 2804 | 2640 |
| call_direct / large | 2668 | 2292 | 2664 | 2664 | 3572 | 3424 |
| call_indirect / small | 2196 | 2040 | 2344 | 2344 | 2772 | 2676 |
| call_indirect / large | 2740 | 2292 | 2660 | 2664 | 3388 | 3548 |
| option_handle / small | 2176 | 2056 | 2340 | 2344 | 2580 | 2652 |
| option_handle / large | 2652 | 2292 | 2664 | 2664 | 3612 | 3488 |
| result_propagate / small | 2196 | 2044 | 2344 | 2344 | 2632 | 2676 |
| result_propagate / large | 2676 | 2292 | 2664 | 2664 | 3612 | 3468 |
| binary_search / small | 2196 | 2048 | 2344 | 2344 | 2756 | 2760 |
| binary_search / large | 2220 | 2040 | 2344 | 2340 | 2796 | 2668 |
| packet_decode / small | 2176 | 2040 | 2344 | 2344 | 2772 | 2760 |
| packet_decode / large | 2196 | 2040 | 2344 | 2344 | 2772 | 2652 |
| list_scan / small | 2352 | 2040 | 2340 | 2376 | 2864 | 2912 |
| list_scan / large | 2488 | 2040 | 2340 | 2376 | 2904 | 2984 |
| list_append / small | 2352 | 6968 | 2340 | 2376 | 2888 | 2964 |
| list_append / large | 2384 | 7768 | 2340 | 2372 | 2856 | 2996 |
| list_filter / small | 2272 | 6808 | 2340 | 2376 | 2856 | 3000 |
| list_filter / large | 2432 | 6968 | 2340 | 2376 | 3016 | 2960 |
| dict_lookup / small | 2416 | 2044 | 2356 | 2376 | 2892 | 3016 |
| dict_lookup / large | 2420 | 2328 | 2676 | 2696 | 3112 | 3156 |
| dict_lookup_str / small | 2272 | 2044 | 2548 | 2360 | 2884 | 3016 |
| dict_lookup_str / large | 3232 | 2648 | 4148 | 3960 | 3664 | 3640 |
| dict_update / small | 2272 | 7768 | 2356 | 2376 | 2804 | 2816 |
| dict_update / large | 2896 | 6808 | 2676 | 2576 | 3248 | 3260 |
| dict_update_str / small | 2512 | 7128 | 2548 | 2360 | 2828 | 2820 |
| dict_update_str / large | 4196 | 7288 | 4172 | 4004 | 3816 | 3876 |
| set_dedup / small | 2256 | 6808 | 2352 | 2376 | 2808 | 2976 |
| set_dedup / large | 2392 | 6968 | 2356 | 2372 | 2968 | 2964 |
| alloc_short / small | 2352 | 2036 | 2340 | 2372 | 2828 | 2840 |
| alloc_short / large | 2416 | 2040 | 2340 | 2376 | 2828 | 2984 |
| alloc_retained / small | 2352 | 6924 | 2340 | 2376 | 2856 | 2912 |
| alloc_retained / large | 2432 | 7532 | 2340 | 2376 | 2968 | 3124 |
| mutate_nested / small | 2256 | 6648 | 2340 | 2376 | 2832 | 2976 |
| mutate_nested / large | 2432 | 6968 | 2500 | 2536 | 3000 | 3124 |
| sort_int / small | 2256 | 6808 | 2340 | 2360 | 2800 | 2840 |
| sort_int / large | 2576 | 6648 | 2336 | 2360 | 2856 | 2976 |
| sort_records / small | 2364 | 6648 | 2340 | 2376 | 2860 | 2960 |
| sort_records / large | 2672 | 6648 | 2500 | 2536 | 3020 | 3136 |
| lox_eval / small | 2256 | 2040 | 2340 | 2376 | 2856 | 2836 |
| lox_eval / large | 2352 | 2040 | 2340 | 2376 | 2840 | 2976 |
| bytes_scan / small | 2328 | 2880 | 2336 | 2376 | 2992 | 3188 |
| bytes_scan / large | 2384 | 2880 | 2332 | 2376 | 2812 | 3016 |
| string_equal / small | 2364 | 2664 | 2528 | 2376 | 2988 | 3248 |
| string_equal / large | 2544 | 2664 | 2528 | 2376 | 3048 | 3220 |
| string_search / small | 2392 | 2880 | 2524 | 2392 | 3056 | 3200 |
| string_search / large | 2368 | 2880 | 2528 | 2392 | 3168 | 3068 |
| string_split / small | 2380 | 7904 | 2336 | 2392 | 2964 | 3064 |
| string_split / large | 2708 | 7772 | 2496 | 2552 | 3312 | 3388 |
| string_join / small | 2380 | 8200 | 2336 | 2376 | 2992 | 3028 |
| string_join / large | 2692 | 7868 | 2496 | 2536 | 2972 | 3368 |
| int_parse / small | 2380 | 7784 | 2528 | 2376 | 2988 | 3060 |
| int_parse / large | 2696 | 8072 | 3008 | 2856 | 3160 | 3384 |
| int_format / small | 2396 | 8000 | 2400 | 2376 | 2972 | 3208 |
| int_format / large | 2524 | 8000 | 2400 | 2376 | 2944 | 3068 |
| word_count / small | 2376 | 7904 | 2532 | 2380 | 3120 | 3232 |
| word_count / large | 2372 | 7904 | 2536 | 2380 | 3128 | 3208 |
| csv_aggregate / small | 2416 | 8160 | 2536 | 2380 | 3104 | 3192 |
| csv_aggregate / large | 2700 | 8000 | 2696 | 2536 | 3276 | 3372 |
| json_transform / small | 2404 | 8224 | 2536 | 2380 | 3116 | 3196 |
| json_transform / large | 2724 | 8544 | 2856 | 2700 | 3596 | 3848 |

38 of 80 plans hit a calibration limit; reasons: {'iteration_cap': 5, 'slowest_arm_budget': 32, 'pilot_limit': 1}.
Limited rows retain their original calibration policy and are not silently recalibrated.
Tiny or optimized-away kernels, host interference, CPU frequency and unequal original ISA policies remain measurement limits.
