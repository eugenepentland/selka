# Private scalar LLVM reader inlining trial

No compiler or application source change. Baseline is an unchanged relink of the previously qualified scalar-only LLVM; trial adds only alwaysinline to definitions my.vm::read_byte and my.vm::read_constant. The scoped roundtrip guard verifies removing those two added attributes reproduces the original LLVM byte-for-byte. The two reader bodies, checked fetch/IP order, fatal check sites, full frame publication and GC source remain identical.

build.py uses exact pinned common955, Zig toolchain and P7 frozen baseline runtime object plus exact common955 number provider. P7 method/receipt was inspected read-only. It copies those providers privately and relinks both arms with identical native flags/object order. The unchanged relink differs in ELF bytes/layout from the original scalar binary; timing will compare the two matching relinks, avoiding that confound. All paths/hashes/flags/argv are in receipt.json and commands.json. LLVM attribute patch is in inline-attributes.patch; private full LLVM remains pinned in .tmp/lox-eda-parity/P2/reader-inline-001.

Initial build ticket2943 admitted immediately; the guard accidentally stripped pre-existing alwaysinline attributes on unrelated definitions and failed before trial compilation. Failed script/commands retained. Corrected scoped guard, ticket2947 admitted immediately, completes. Baseline-original32 CLI/GC/error comparisons pass; inline-baseline32 comparisons pass;13 standalone legacy/scalar result/IP/fatal-order probes pass after applying only analogous two scalar-reader LLVM attributes. Probe full private source manifest is retained; no production source changes.

Native structure:

| Metric | Unchanged relink | Inline trial |
|---|---:|---:|
| read_byte native callsites |10|0|
| read_constant native callsites |12|0|
| read_byte native body bytes |169|0|
| read_constant native body bytes |238|0|
| vm.run bytes |12896|15464|
| .text bytes |377094|379462|
| ELF bytes |865176|870320|

Both intended readers are inlined with no remaining native symbol or call. .text grows2368bytes (0.63%); vm.run grows2568bytes (19.91%). structural.json contains these exact measurements; nm/size/disassembly retained.

Fresh compile-only ordinary admission ticket2955, wait5s, compiles each arm once with separate new Zig local/global caches. Baseline wall1.56s,user1.48s,system0.07s,maxRSS130628KiB; inline wall1.58s,user1.51s,system0.07s,maxRSS133924KiB. This is a single diagnostic pair, not a statistical compilation-time claim. Initial cached builds are explicitly unsuitable for estimating cost. compile-cost.json pins complete commands and outputs.

Prepared timing (not yet executed) compares identical newly relinked baseline/inline arms using private inline-fib-001 and inline-closures-001 harnesses. Each case has three resumable CPU8 timeout58 timing chunks, each fresh Zig2warmups+5measurements and3xmedian cutoff,2warmup pairs plus3globally alternating measured pairs (nine total). Full existing inputs and expected stdout are pinned. Guest-group timeout cleanup, exact stdout/stderr checks, script/native/compiler hashes and all samples are checkpointed. Awaiting coordinator scheduling release.

Existing bounded Core reader policy currently rejects both wrappers: inline_reader requires scalar return and zero owned/consumes/views bits, whereas these readers return mut-result records and have mut integer IP. Their internal getter calls are also outside the single runtime offsetReader exception. inline_cfg supports mutable return projections but rejects all call instructions. If paired timings support implementation, prefer extending the existing fixed CFG/origin/caller budget for locally verified small checked readers with a single mutable scalar and ownership-free scalar/result fields; bounded locally qualified read-only callees only, no names or whole-program ownership inference. No compiler policy edit is authorized or made here.
