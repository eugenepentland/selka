# R follow-on review (read-only, before binding X timing)

R reviewed accepted source 09ed227098f3b5447643317ab640eec85c4f6772 and retained final LLVM/counters. These are candidate investigations, not timing attribution or exit-failure claims.

## Fixed arrays

The array arm's full-copy loop is already vectorized in the executable. LLVM lines 353–368 copy perm1 to perm then reload perm[0]; executable main+0xdb through +0xfe performs the copy, +0x107 reloads the destination. Tuned LLVM lines 324–326 instead loads perm1[0] before memcpy and reuses the value for rotation. Existing CPU8 medians show array has 3,628,836 extra L1 loads for 3,628,800 permutations, only 362,915 extra instructions, nearly identical branches/stores, but 62,218,811 extra cycles. Source-value forwarding across a proven full fixed-array copy is a concrete probe; store-to-load dependency latency remains a hypothesis. The copy remains necessary because perm is mutated while perm1 is live. src/core/forward.zig:42 currently handles record fields only.

Both arms: facts.zig:1004 provides array element intervals, but emit_fn.zig:44 uses generic loadValue (emit_llvm.zig:2707) without the loadRange metadata attached by listLoad (emit_llvm.zig:2508). First expose trusted integer ranges on scalar array loads, respecting verification mode, then inspect whether LLVM removes reversal k-i normalization/bounds checks. If needed, add relational proof: 1<=k<=9 and 0<=i<(k+1)>>1 imply 0<=k-i<=9. Tuned LLVM:374 and machine main+0x130 retain lea +10, test, cmovns, comparison and trap branch. Preserve all 290,304,000 bytes of genuine tuned snapshots.

Secondary: index_checks.zig:153 and index_keys.zig:173 restrict dominating-check reuse to lists. Array counters contain 12,470,600 additional checks at repeated count[r] set/read sites. LLVM already removes several in native code, so counter reduction alone is not a timing result.

Exact LLVM: R/llvm/final-*.ll.gz and R/final-llvm.json; originals in R worktree .mylang-cache/rp3/ce/cache/r-final-ir/parity-fannkuch_redux_{array,tuned}-plain.ll.

## CSV

Current counters for csv_aggregate 4096 40 7: csv_rows line39 str_code bounds 5,910,680; field append uniqueness line71 2,268,680, line59 2,167,440; escaped-quote append line43 163,840. Source test/core/row_csv_aggregate.my:39. fuse_text.zig:53 computes cursor width, fuse_text_scalar.zig:62 emits checked str_code, core_text.c:340 recomputes width for str_append_char. Probe sharing one validated UTF-8 cursor decode/width among comparison, advancement and append, preserving aliasing and trap behavior. These frequencies do not prove the roughly 1.13x baseline reference gap is decoding cost.

Two hot append sites report 819,200 zero-byte copies, mainly materializing empty field builders; treating the copy count as byte traffic would mislead. Missing evidence: a current merged-compiler sampled instruction/cycle profile at /64 and /4096, dividing cost among decode/checks, append/uniqueness, allocation/release, dictionary updates and integer parsing. The retained sampled CSV profile belongs to 6df58b025 and the old myl_native_* runtime, so it cannot establish current cost shares.
