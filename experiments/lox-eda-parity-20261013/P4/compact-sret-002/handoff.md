# Compact INTERNAL sret v2 adopted for combined C3 qualification

Production/test commit: f054387ed2e32b5b1439674b4be5e2fea142c029. Normal cold whole-tree Guardian88 passed. This changes physical internal transport only; guest algorithms and IR tuple semantics are unchanged. See contract.md and compiler.patch. No lifetime markers, share_sret changes, stored views, arenas or RC fallback.

The result transports declared result and non-in-out finals in field order, with field alignment and final padding. Large mut finals remain in parameter homes. Direct/recursive/indirect and cross-unit calls use the same signature mapping; external ABI/noalias/ownership/borrow/error checks remain unchanged. Logical result homes are reconstructed for whole readers. V1's missing-padding defect and its old-size assertion/failure receipts remain in ../compact-sret-001.

Qualification: verified Lox103/103, failed/skipped/cached/unsupported0; canonical zero-RC release+verify, release, unoptimized, optimize-debug, release+no-facts matched native controls, plus RC default/release controls. Controls include negative and out-of-range indices, errors/order, recursive and indirect calls, scalar/managed finals, and bool/u8/u16/u32 alignment. Split-module bool/int and u8/managed-bytes indirect controls pass all5zero modes+2RC. Core7/7 includes full mixed bool/u8/i64/managed-str tuples stored/read as list elements under normal and checked ownership, debug/release, leak-free; independent snapshot assertions remain unchanged. Corpus VM246/tree241 pass normal and GC stress (974 runs). Both generated LLVM files compile atO0 using pinned Zig (verification logs retained).

Native evaluator/get_variable/execute physical result buffers280/216/280→48/24/48B. Evaluator explicitframe1208→488B, execute3816→728B. Evaluator code8636→11603B (+34.4%); execute6019→5959B. These are native storage/code observations, not sampled CPU attribution.

Approved diagnostic protocol: four cases, exact C2 guest source, baseline common0029bed compiler versus candidate fddc compiler; release+zero-RC flags matched. Tree fib28, binary_trees10, string_equality10000 and canonical VMfib34 control. Two warmup rounds, nine alternating paired rounds perarm/case, split into3 ordinary timing leases/case; CPU8, fresh Zig2warmups+5calibrations,3×relative/120sabsolute cap. All12 leases succeeded:108 measured wall samples, no failures/censors/exclusions. Complete outputs, raw receipts, spec hashes and paired summary retained. No extra repetitions.

| Case | Candidate/C2 paired median | 95% bootstrap median interval |
| --- | ---: | --- |
| tree fib28 | 0.958430 | [0.941163, 1.004424] |
| tree binary trees10 | 0.983227 | [0.973438, 0.992231] |
| tree string equality10000 | 1.006090 | [1.000431, 1.015035] |
| VM fib34 control | 0.993357 | [0.979428, 0.997721] |

Adopted as a measured tradeoff: binary trees improve1.68%, VM control0.66%; string control regresses0.61%, fib's apparent4.16% gain is uncertain, and evaluator code grows34.4%. This does not establish uniform speedup or Zig parity. Combined C3 broad native/full gate/apps/final compiler six-micro qualification will assess other regressions; no further prototype work is planned.

Reproducibility: identity.json freezes all installation companions, base source/input manifest, guest files/binaries and compiler patch. Baseline compiler9bedb835438615d79ed8f2985352877a8c844eebeb74cd95a1d276332b6b0c6a; candidatefddc4750738b150cbdd484698ed8668cb638a853f487760b1406dd1b70db295b. Fresh baseline guestd2ad8234c345524de9061d38f530d90e084f973288c0c1bea43de71e638a1aef matches prior C2; candidate742b63ad2c546db42bee28ea8ded678e28695f4296293465af057613fefd4f52. Native inspection and excerpt hashes bind all code/frame claims. qualifier scripts, command receipts and gzipped admission/install/Core/commit logs retain successes and failures. Every native operation used sourced dev-env/shared ordinary admission, private TMPDIR/caches, jobs4/maxrss8GiB. Timing scheduler and exact command receipts record CPU/cutoffs/order.
