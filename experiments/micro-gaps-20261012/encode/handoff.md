# Local read-only encoding

C0: `399013af36d41b78610e5ede22a9102ec5b17ffe`.

The zero-RC optimizer converts an encoding to an SSA octet span only after checking its complete local use set: byte length, scalar byte reads, and the audited negative-index normalizer. It follows forwarding copies, rejects all returns/storage/opaque calls/bytes mutation/phis, and uses the existing slice source-stability proof to reject consumed or mutated owners and their borrowed parents. The existing ownership pass keeps the source live through every span read. Public escaping/retained encodings still create independent owned bytes. This is a compiler transformation; benchmark and history sources are unchanged.

At most 32 candidates in a function with at most 4096 instructions are inspected. Larger functions/candidate suffixes fall back to owned encoding. Runtime helper recognition/reuse requires exact linkage, parameter/result layout, ownership, view and consumption contracts; malformed existing span declarations disable the pass rather than producing a duplicate native declaration.

The emitter reads scalar bytes from the span pointer and checks physical byte bounds with the existing located `R_LIST_BOUNDS` trap and original written negative index. It widens integer operands according to their signedness. The normalization helper uses unsigned modulo arithmetic and cannot overflow signed arithmetic. Vector loads extract the span pointer; scalar remainder checks and verifier guards admit only u8 elements. Compiler-introduced physical list_len also reads the span length.

Shared uncommitted parent overlays: passes.zig runs fuse_encode.runRecording before fuse_slice_key, sharing fusion_requests; root_test.zig imports tests; zero_rc.zig audits `myl_core_span_bytes_index_offset` with views 1, owned 0, scalar return. These overlays are required and are deliberately excluded from the worker commit.

Native regressions exercise release, unoptimized debug, verified release, optimized debug and release without facts: Unicode UTF8, empty encodings, invalid raw octets, a 1027-byte fold with vector bulk/tail, negative indexing, early returns, source replacement, escaped returned/stored bytes after source update, positive/negative extreme located-OOB errors and leak-free exact cleanup. Structural tests reject escaping/opaque consumers and forged/malformed runtime signatures, including preexisting span helpers. The original encode ownership unit remains selected.

Candidate provisioning copies the complete frozen qualified package (bin/libexec/tools) and replaces only the host with the current `seed-compiler` output. `frozen-package.json` records every reused file identity. Pins/seeds remain unchanged. `qualify.py` records checksum and counter probes at both case sizes against the existing C0 counted executable, using the independent text oracle. Probe elapsed output is not timing evidence. Parent performs integrated matched timings, cache verification and the full gate.

Qualification source: `experiments/micro-ownership-20261012/expanded/migrated/text.my`, SHA256 `71f5e74e25f894e779c6248b9f52c144e9d53a8c482c0121e4249374dbe05754`.
Frozen C0 compiler SHA256: `8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa` (rechecked unchanged).

At 1000 int_format iterations: large allocations 2017→1017, text copies 1002→2, cumulative allocation bytes 130856→66856; small 2016→1016,129792→65792. At 17 string_split iterations: large allocations 143462→73830,text copies 143362→73730,bytes 9284480→4828032; small 2342→1254,180968→111336. Word_count large 9474→9389 allocations and 648848→643408 bytes; small 800→715 and 58784→53344. Its 85 removed score copies are separate from retained dictionary/tokenization costs. All 12 C0/candidate probes have matching oracle checksums, zero RC/uniqueness events and zero exit-live bytes. Raw counters are adjacent; no matched wall-time result is claimed here.

One discarded setup attempt used the still-read-only copied baseline host and a default admission directory before the outer shell sourced dev-env. Its results were overwritten; the valid probes use the replaced current host and the shared admission directory. The frozen compiler itself remained unchanged.

Final candidate compiler SHA256: `71aed254efe432ce00f97d06103710b0d3b4451f8d1aeab4f056d8e7124f08a5`.

Final checks: `core-test-binary seed-compiler -Dtest-filter='encode borrow' -j4` compiled with the pinned Zig; the registered focused binary selected 8 tests and passed 8/8, including five native emission lanes. The qualification compiled the unchanged migrated text.my with `--release --experimental-zero-rc --counters --link benchmarks/runtime/ports/native_clock.c --emit-llvm`; all 12 probes passed. Guardian `all . --gate` passed 88/88 whole-tree checks. All admissions used the shared build slots for these valid results, four jobs and the unchanged 8 GiB limit. The package and guest caches are private to `.tmp/micro-gaps/encode`.
