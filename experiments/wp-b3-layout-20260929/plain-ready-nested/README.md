# Nested scalar-append readiness hint

Source checkpoint `c28530b0a3f0f5e4e9f12a6f2cbed73702a0351d`, based on root `40bd74a0c52939c5f92d56f3a447269592077bd3`.

Forcing every readiness query inline fixed alloc_churn's hot query calls but changed fannkuch's register allocation, adding 73,732,151 simulated instructions over the exact publication predecessor. Fannkuch executes its three cached queries only once each during list initialization. Alloc_churn executes the same emitter's cached query 3,000,000 times, after capacity-growth calls invalidate admission. The original attribution remains frozen in the owned fannkuch review worktree; its receipt SHA256 is `5ab31c41a1a28fde4dfff8537442c485d94c402c431b2e8f469fbba5e2142624`.

This continuation chooses a hot alias only when an already accepted closed scalar-append certificate is strictly enclosed by another physical loop's head/back interval. Missing or refused certificates and first-level loops use ordinary compiler inlining. This is a frequency hint, never an admission proof: the room/generation checks, queue and binding authority, entry reset, successful-result cache and slow-call invalidation are unchanged. Presized queries retain the ordinary function. Both native entry points use one private query body, byte-exact to the previous ordinary query body. The hot entry point carries `always_inline`; both entry points stay callable through the existing public header in non-LTO builds.

The native prototype is additive. Neither count widths, object layouts nor runtime ABI identities change. Runtime source/header content hashes and compiler/function cache identities account for the new declaration and emitted call name. LLVM derives its declaration from the embedded native header; the actual QBE and LLVM executables below verify declaration/link compatibility. Old ordinary-query callers remain compatible with the current runtime.

| Verification | Actual result |
|---|---|
| Nested selection and strict interval boundaries | 2 named tests, 14/14 including 12 unnamed import tests |
| Cached append/reset/fallback behavior | 3 named tests, 15/15 including import tests |
| Ordinary room guards | 1 named test, 13/13 including import tests |
| Presized emitter retains ordinary query | 1 named test, 13/13 including import tests |
| Real native collections, both aliases compared | 47/47 each under no/full/ThinLTO with UBSan |
| Separate caller/header/function-address probe | 15/15 per alias under no-LTO O0/O3 and full/ThinLTO: 120 cases |
| Actual fannkuch binaries | QBE and LLVM3/full-LTO outputs match |
| Actual alloc_churn binaries | QBE and LLVM3 no/full/ThinLTO outputs are `999739` |
| Guardian | Whole-tree 88/88 |
| Formatting and explicit input coverage | 27/27 build steps |

The independent caller probe links the whole production collections translation unit, with a stub only at the slow binding-lookup boundary. It tests nulls, missing RC state, pending-death refusal before the cache hit, wide/nonplain descriptors, unregistered and edge/unique bindings, cold successful binding, both cache levels and no allocation. The native collections suite supplies real-runtime registration, queue, alias, arena, generation and budget coverage.

Fresh normal emission selects three ordinary cached queries and no hot query for fannkuch, versus one hot cached query and no ordinary query for alloc_churn. Actual QBE builds contain versioned copies as well: fannkuch has six ordinary machine-code sites; alloc_churn has two hot sites. LLVM full-LTO fannkuch retains three ordinary sites. Alloc_churn has two hot sites without LTO and zero query calls with full or ThinLTO.

The LLVM full-LTO fannkuch candidate is **identical in every one of its 26 allocated ELF sections** to the symbol-preserving counterpart of the exact publication predecessor. Addresses, offsets, types, flags, sizes, alignment and payload hashes all match; raw `entry_run` disassembly is also identical. This removes the new fannkuch machine-code regression exactly for this binary, without a new timing or corpus measurement. It preserves alloc_churn's observed hot-query inlining; the integrator still owns the combined corpus and broad acceptance gates.

Installed compiler SHA256: `8cbef1e83b229c74f21924065edce57e5c50f07eb26598f0189b12eb13a76905`. QBE SHA256: `dedfe18608c0617d290779b1ed657f9e6429975cdfa4c90ee1204c857522ce3e`. The installed prefix and all generated runtime snapshots are frozen in the owned `.tmp/plain-query` directory. `body-and-source-proof.json` pins source, query body and runtime-snapshot digests; `fannkuch-section-comparison.json` retains the complete equal section manifest. `receipt.json` hashes every durable artifact and binary. Original installed binaries, object/cache snapshots and uncompressed logs remain in the owned worktree.

Three initial verification mistakes are preserved: Guardian rejected two primary declarations of the new spec tag (the interval model now uses `spec-case`); the first tag filter named no test (corrected names now select two); and the first guest harness expected only three QBE fannkuch sites, overlooking the three versioned guard copies. The corrected site assertion passes. These were annotation/filter/harness errors, with no source behavior failure or waiver.

Guardian feedback was centralized and committed in `guardian-zig` as `7dc405f907c4d42e775559641e35ac7259b69501`. Independent read-only source review by the module lane found no actionable defect; it made no duplicate test or timing claim.

Reproduction uses the repository-pinned Zig, an owned install/cache/TMPDIR, and `scripts/build-slot.sh build` around every build or probe. `probe/abi-matrix.py` expects `caller.c` and `oracle.c` copied to `.tmp/plain-query/abi/probes/`; `probe/native-matrix.py` runs the real 47-case suite; `probe/guest-matrix.py` retains the exact root corpus paths used here and emits only the two guests. No Python is used in compiler build/runtime code. No timing CPU was claimed, no shared source tree was edited and no main merge or push occurred.
