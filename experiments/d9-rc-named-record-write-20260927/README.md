# Named owning record scalar writes

This archive compares frozen Debug compilers on the unchanged Lox VM and full
`binary_trees.tree.lox` N10 workload. It is an isolated Stage4 performance
experiment, not acceptance or a default-runtime change. Run `python3 verify.py`
inside this directory to validate the receipts without rebuilding or running
benchmarks.

`identity.json` records the real-merge base plus the exact source patch, both
compiler identities and every evidence artifact hash. The before compiler is
joined c90c84be (e5d47d20 plus unit-fixture wiring only); the candidate adds the
bounded named-record ownership proof. The original compiler installations and
binaries remain in the paths recorded by the build manifests. Both actual
backend manifests and LLVM LTO flags are checked.

`admission-final.json` and the paired IL show four newly admitted `vm::run`
updates, eight fewer ExecFrame loans, and one additional scalar update in
`compiler::init_compiler`. Other VM loan descriptors remain unchanged. The
independent counter source verifies three O pairs and six H pairs removed per
committed update at 1, 2 and 10 updates on each backend.

`validation.json.gz` holds 64 standalone assertions, covering snapshots,
rebinding, forwarded mut calls, complete RHS evaluation and arenas. All GC
controls use `MYLANG_OPTIONS=--gc-stress`. `traps.json.gz` contains exactly 48
executions: 40 expected step/allocation/overflow traps and eight success controls.
The final store's publication point remains unchanged. The memory fixture's
first draft used unsupported list multiplication; the exact rejected source
and original failing log are preserved. Only its syntax changed to a legal
comprehension, and completed step receipts were reused. That harness failure
is not represented as a compiler correctness failure or a passed guest.

Guardian initially rejected the new managed AutoHashMap API usage and one
241-column test literal. The source now uses AutoHashMapUnmanaged and wraps the
literal; `build-initial.log.gz` preserves the failure and the final whole-tree
Guardian log passes all 88 checks. Two focused filters each pass 15 tests,
including 11 mandatory unnamed tests (do not sum those as distinct tests).

`reduced.json.gz` and `full.json.gz` retain every raw perf instruction row,
100% event-running fraction, output/hash, command and balanced counted run.
Each production binary gets three matched instruction samples per input and
backend; counted binaries are separate. `wrapper_max_rss_kib` is the outer
`time(perf)` wrapper maximum, not direct guest RSS, and establishes no RSS
acceptance claim. Direct guest RSS belongs to root's joined corpus measurement.

`accepted-gc-reference.json` preserves the exact older immutable accepted-bin
samples used for denominators (7,243,231,888 QBE; 3,433,163,639 LLVM). Those are
not relabeled as the subtly different old-corpus sample set. The accepted GC
baseline and the 1.3 cap remain unchanged.
