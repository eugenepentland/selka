# Nested COW joined validation — 2026-09-26

The resolved integration at `b6328bcd` preserves the nested collection and fixed-array receiver fixes from `426d201e`, the pure-box read guard, rooted transfer fallback, and legacy failure-result initialization. Review found no lost requirements. No integration source was edited during this validation.

A fresh **Debug** compiler was installed through `scripts/build-slot.sh build zig build --prefix .tmp-closeout/install-scopes --summary all`, using the integration worktree's own Zig cache and temporary directory. Installation passed 19/19 steps and Guardian's 88 checks. The compiler and QBE executable were then copied to isolated scratch before testing.

Compiler SHA-256: `7509c8733b37eaef9da45e06ef6ca41b6048f236664e3aa7727e23d45964f32d`.

| Check | Result |
| --- | --- |
| Historical legacy IL, value semantics off | 44/44 byte-identical; both compiler invocations succeeded for every file |
| QBE native guest tests, GC stress | 55/55 passed, zero cached |
| LLVM native guest tests, GC stress | 55/55 passed, zero cached |

The IL comparison uses the historical parity sources retained from the stage-3b comparison and the baseline compiler from `perf-gc-dict`. It clears inherited `MYLANG_*` variables, disables compiler caches, and compares emitted function IL, entry code, and runtime data without normalization. `sort_records` and `text_ops` use `emit-project-qbe`; the other 42 files use `emit-qbe`. Every source hash, compiler hash, exit status, and IL hash is retained in the [raw evidence](evidence/d9-nested-cow-joined-validation.json).

The three guest suites are `nested_collections` (18), `nested_arrays` (18), and `nested_array_callbacks` (19). Each runs with value semantics enabled and `--gc-stress --force --jobs 2`; the LLVM runs additionally use `--release` (guest ReleaseFast, LLVM O3, full LTO). The 110 executed cases cover repeated collection and array wrappers, replacement and deletion during index evaluation, equal shared versus fresh replacements, rehashing and hash collisions, ancestor snapshots, boxed paths, the 1,200-node recursive sibling, nested pending receivers, early Option propagation, retained borrowed keys, and arena escape. The evidence includes each suite's complete native runner output and fixture hashes.

This is focused validation of the joined compiler. The root integration agent owns the full joined gate. Earlier full gates and deep recursive runs are separate evidence, not implied by these results.
