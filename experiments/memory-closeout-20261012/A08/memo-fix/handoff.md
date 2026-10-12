# A08 memo cache restoration fix

Base `69f797479707dba0fbca18aad5c4fb5d3acbffb7`; private A08-memo worktree.
Owned production change: `src/semantic_type_recipe.zig`. Coordinator authored the
`src/root_test.zig` registration; A08 owns `src/a08_memo_cache_test.zig`.

An ordinary cached caller can contain a callback passed to `memo.create[str[]]`.
Raw parsed calls retain the bracket application in `call.name` with an empty
`type_arguments` list until ordinary dispatch splits it. Callable recipe replay
only checked the latter, passed the bracket spelling to plain name resolution,
and returned InternalError. The warm CLI build exited1 without a diagnostic.

Recipe replay now conservatively misses for an unsplit bracket application,
matching its existing generic dispatch boundary. Normal fresh checking remains
responsible for specialization, callback contracts, effects and ownership. No
stored schema, validity check, or error propagation contract was weakened.
Unrelated bodies still reuse their cache entries. Compiler identity changes
invalidate prior revision artifacts through existing keys.

The registered regression checks durable cold/warm requests, an earlier source
declaration, invalid callback rejection, and recovery. Warm successful requests
must observe both an interned-record miss and independently reused bodies. The
new regression and eight existing A08 wire/copy controls pass9/9. Existing portable
callable controls pass10/10 through the registered test-units route. `tests.json`
and `logs/` retain commands/results, the original failing trace, and two corrected
test-invocation/fixture mistakes.

`compiler-identity.json` identifies a private Debug compiler with this exact
production hunk. Its copied tools/libexec come from Support7's actual-owned
installation. The build-time test-only source snapshot is retained; the final
registered regression adds no production behavior. This compiler is correctness
evidence, not a final C1 artifact or a performance comparison.

Native qualification passes all12 rows under `native-02/`: original full memo
program cold/warm in release, unoptimized debug, verified release, optimized
debug and release without facts, plus the minimal debug cold/warm pair. Exact
output/exit, independent frontend reuse, clean LLVM RC audit and clean compiler
allocator reports pass. These runs are uncounted guests, so this report makes no
new guest peak/live-memory claim. Final common-artifact repetition remains due.
The first matrix supplied conflicting release/debug mode flags and is retained
under `native-01/`; it is not a passing matrix. The corrected harness supplies
exactly one mode flag and checks actual guest output and frontend reuse.

Final integrated C1 qualification, default promotion, RC retirement, and final
matched scaling remain coordinator-owned stages. This fix does not close them.
