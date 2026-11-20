# D9 RC ownership foundations: joined regression gate

Frozen `d0178601` passes all four required commands with GC still the default.
This is a regression gate for the joined RC implementation foundations;
WP-4 guest correctness and performance acceptance remain outstanding.

| Command | Result |
| --- | --- |
| `zig build test --summary all` | 94/94 steps; 2,162 executed tests, 21,925 shard exclusions |
| `zig build test-qbe --summary all` | 51/51 steps; 436 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check --summary all` | 2/2 steps |

The compiler is Debug, SHA-256
`6cea9d427d2bf3323ae7db77f4d7c5e86a189d93304f49d833f8ce5df35a764b`.
The [machine-readable record](evidence/d9-rc-host-staged-gate-2026-09-26.json)
links compressed exact logs and raw hashes. Whole-tree commit Guardian passes
all 88 checks. Gates were serialized, source was frozen during execution, and
scratch stayed under the worktree. `main` remains `b292660a`; no push or main
merge was performed.

The join includes final-liveness RC planning and raw unique-resource
classification (`55f29cd9`), indexed metadata lookup (`e8df2735`), startup
registration (`5a6133a2`), iterative pinned cloning (`3cf5da37`), staged
collection adapters (`43d62e3f`), and copied-codec/host cleanup (`3cf5982c`).
All joins are real two-parent merges. Raw provider resources retain their
existing unique cleanup instead of being treated as prefixed RC objects.

The C evidence uses production allocation and ownership operations. Fourteen
core scenarios include a 32,768-node pinned box chain; sixteen collection
scenarios include a 4,096-list pinned path and nested arena rollback. The
agents ran these under ASan/UBSan and a 256 KiB stack. Eleven codec scenarios
cover partial values, duplicate dictionary keys, rejected domain conversions,
allocation refusal, and real longjmp during decode and encode. The copied
host harness checks independent owned byte publication and node scratch
tracked through callback failure. Codec and host sanitizer runs passed.

Codec temporaries now have an execution-lifetime ownership journal; teardown
releases initialized values and buffers while their context is alive. Domain
results remain rooted across further conversions in GC mode. Normal and trap
paths share cleanup. Host node scratch uses the runtime's existing tracked
frame allocations. Startup tests now also exercise the production sticky
first-failure path, with a separate RC compilation unit for startup rather
than enabling automatic RC initialization in unrelated C fixtures.

The first joined gate failed only the generated host-source snapshot whose
bytes intentionally changed with tracked node scratch. After reviewing that
diff and the real trap-cleanup regression, `d0178601` updated the snapshot.
The complete gate above is the subsequent successful rerun; no expectation,
threshold or baseline was waived.

Compiler ownership lowering, scoped holds/pins, complete arena escape and
teardown, instrumented borrow traffic, and the matched 43-program RC run are
still in progress. In particular, later review identified a fresh arena edit
abort that retained heap children until region close; its correction belongs
to the next runtime slice. This gate does not claim that unfinished RC paths
are ready for guest use. Arenas remain part of D9.
