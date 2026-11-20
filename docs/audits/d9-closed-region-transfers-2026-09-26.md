# D9 closed-region field transfers, 2026-09-26

Status: the compiler change passes its correctness gate, but D9 performance acceptance remains unmet. Commit `9f42e5a9` on `d9/stage3b` extends the existing exact field-extraction/store-back proof to closed loops and match arms. Every explicit edge from the mutation region must remain inside it or enter its final store-back; no external edge may enter the region or that store-back. Source observations, another mutable parameter, early returns, propagation exits and a surviving extracted local still retain the copies.

The Lox marker previously copied its mark bitmap and gray list on every `blacken` call because the old proof rejected its loops and match dispatch. The updated proof removes those artificial shares while preserving independently saved values. On the frozen class-free Lox source, trees N=5 copied 50,879,893 bytes instead of 2,090,704,513. COW copies fell from 410,240 to 196,128; marks from 13,999,514 to 13,387,790. Uniqueness checks were unchanged at 10,477,018.

## Measurement

[Raw measurements and counters](evidence/d9-lox-marker-region-perf.json) contain all 13 VM scripts on both backends, median of three `perf stat` user instruction counts on CPU 10 through `experiments/perf-gc-dict-20260925/scripts/pc.py`. Each side passed the harness exact stdout/status check before timing. The guest source was the frozen deferred-IP version (main SHA-256 `18c1f669b1683123e635256c9f66c6db2766383391371c3822e61df7d9732274`); it excludes the later compact-frame source change.

The baseline is exactly `60b668cf` with the historical class-based source and no value-semantics switch, compiler SHA-256 `48427e9ac1c01b74e60d1b4c098c8fc149a6b5fef3c07e110c7fb4ba16cbb545`. The candidate Debug compiler SHA-256 is `76a141ef6bfb0d9f94759a49a8608d561186c661c172d1288e68d49aeb6b9790`, built from `2b889ba5` plus the compiler change committed as `9f42e5a9`; later test additions did not change compiler code. Guests used ReleaseFast; LLVM used optimization level 3 and full LTO. The raw artifact records both backend binary hashes and a hash of every Lox source file.

Ratios below compare each candidate against that exact baseline. The prior candidate was `2b889ba5` using the same frozen guest source.

| VM script | Prior QBE | Region QBE | Prior LLVM | Region LLVM |
| --- | ---: | ---: | ---: | ---: |
| binary_trees | 1.6634× | 1.5269× | 2.1097× | 1.8153× |
| closures | 1.7458× | 1.7424× | 1.8705× | 1.8627× |
| equality | 1.0834× | 1.0834× | 1.1992× | 1.1992× |
| fib | 1.4343× | 1.4343× | 1.4677× | 1.4677× |
| instantiation | 1.6548× | 1.6522× | 1.5754× | 1.5706× |
| invocation | 1.5660× | 1.5660× | 1.6087× | 1.6087× |
| method_call | 1.5391× | 1.5391× | 1.7883× | 1.7883× |
| properties | 1.4517× | 1.4517× | 1.5167× | 1.5167× |
| string_equality | 1.0616× | 1.0616× | 1.1696× | 1.1696× |
| strings | 1.1840× | 1.1840× | 1.2336× | 1.2336× |
| trees | 2.3944× | 1.3402× | 3.8210× | 1.4540× |
| zoo | 1.4018× | 1.4018× | 1.4978× | 1.4978× |
| zoo_batch | 1.3915× | 1.3915× | 1.4951× | 1.4951× |
| Geomean | 1.47277× | 1.39885× | 1.63346× | 1.49821× |

Ten of thirteen VM programs still exceed 1.30× on each backend. The region candidate maximum is closures: 1.74243× QBE and 1.86273× LLVM. This is a 26-key VM experiment, not a new 43-program acceptance sweep; no acceptance claim follows from it.

## Validation

Focused ownership tests passed 14/14. Eleven field-return guest tests passed on both QBE and LLVM under native GC stress, including snapshots, sibling fields, early returns, loop observations and external control-flow joins. The full gate passed under the shared gate lock:

- `zig build test --summary all`: 93/93 steps, 2,094 selected tests passed.
- `zig build test-qbe --summary all`: 51/51 steps, 428/428 tests passed.
- `zig build test-qbe-build --summary all`: 29/29 steps.
- `zig build fmt-check --summary all`: 2/2 steps.

Guardian passed all 88 checks in both the whole-tree commit check and the build gates. A first commit attempt caught one newly added 256-character test literal; it was split before the successful commit.

The next profile of closures attributes 7.2% of sampled cycles to `heap::function_obj`, 5.7% to `vm::load_frame`, 5.6% to memset and 4.8% to `heap::closure_obj`. The profile and emitted assembly show repeated aggregate temporaries around payload binding and return transfers; these are the next investigated costs.
