# Coordinator handoff — in progress

Base: `78b4bb5934748d5942389b12dfe66cb0031cafdc`; integration branch `codex/text-gaps-20261012`.

The current task is to get both sizes of unchanged string splitting, JSON transformation and CSV aggregation below runtime ratio 1 versus Zig ReleaseFast, Rust and Go. Full application benchmarks wait for user review. No target is declared complete yet; prototype binaries are not the final integrated compiler.

Four workers own split lowering/readers, JSON library, CSV append runtime, and independent measurements respectively. The coordinator owns shared dispatch, ownership, emission, cache integration and runtime helper contracts. Sources and foreign ports remain frozen.

Coordinator prototypes expose small scalar readers and snapshot constructors under the existing fixed inline budget, remove copies only when source/child liveness proves transfer safe, borrow validated byte slices and encoded append ranges, and lower immutable byte literals directly into the existing static layout. Local key-copy borrowing is integrated and qualified; copies remain when a key escapes or its input changes. Escaping owners and snapshots across replacement retain independent storage.

The integrated focused suite passed 24 tests. The broader checked ownership suite passed 183 tests after static literals, key-copy borrowing and direct leaf destruction; this includes the supported task stress/ThreadSanitizer checks. Guardian passed 88 checks. Final full verification and common-compiler measurements are pending. Raw logs are in `validation/`; source and final artifact identities will be recorded after integration.

Two literal fixture failures were corrected before qualification: a Zig declaration shadow, and an unsupported byte-buffer indexed assignment (replaced with its supported append operation). These were fixture errors, not successful runtime evidence; failure logs are preserved.

`verify.py` invokes `scripts/verify_cache.py` directly using the unchanged, previously qualified component pin/archive listed in `component-route.json`. The legacy seed provisioning issue remains an explicit package boundary; no immutable seed was repinned and this experiment makes no default/legacy-RC-retirement claim.

The user requested merging this checkpoint into main, then resuming performance work. The user confirmed local main / development line; its pre-merge tip is `4892aaba4e3fa9076cc5f2c8590f3f2f89500cb9`. An isolated candidate worktree preserves the existing main checkout edits. Existing local-main edits are preserved. Full verification precedes the merge. Guardian feedback edits are not requested.
