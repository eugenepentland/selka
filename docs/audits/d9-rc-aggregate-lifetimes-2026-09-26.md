# D9 RC aggregate construction, replacement and propagation

`codex/d9-rc-aggregate` adds transactional aggregate publication in `acee0c9d`
and joins guarded borrowed-local moves in real merge `9ba2c925`. Record and
variant constructors register zeroed partial values before a field transfer can
fail. Record/array replacement prepares the incoming field before releasing the
old one. Managed body updates check physical uniqueness after establishing their
owning slot. Match bindings and `Option`/`Result` propagation own the selected
payload before releasing its wrapper, including wrapped errors and preceding
constructor operands on an early return. Managed bodies containing unique
resources register their close finalizer.

The Debug compiler at `9ba2c925`, SHA-256
`f133602b58e3e2151c6556a48498b5495f360802dc730a1e41faf02d5d4957e8`,
passes these actual ReleaseFast guest executions on both QBE and LLVM:

| Probe group | Cases per backend | Heap allocate = retire | Owner acquire | Owner release |
| --- | ---: | ---: | ---: | ---: |
| Aggregate construction, snapshots, replacement, matching, propagation | 12 | 346 | 523 | 869 |
| Existing optional-layout and propagation cases | 15 | 967 | 4,901 | 5,868 |
| Real assertion unwind through 33 aggregate-owning frames | 1 | 132 | 198 | 330 |

All counters match exactly across backends. Each process emits one unsaturated
statistics record; owner and hold accounting balances. The trap exits 1 with
`R_ASSERT` and the expected message. The
[reproducible driver and evidence](../../experiments/d9-rc-aggregate-probes-20260926/README.md)
retain exact source hashes, commands and complete process output. The extra
regression fixtures are identified by source hashes because they were executed
before their evidence commit. The existing optional arena-escape case is
explicitly excluded pending the separate arena compiler integration.

Two focused Zig regressions verify partial-construction journal ordering and
unique-body finalizer metadata (13/13 tests including 11 unnamed blocks). The
Debug install and whole-tree commit gate pass all 88 Guardian checks without
ratchet changes. The required combined full gate remains the parent integration's
responsibility; these probes do not claim WP-4 performance acceptance.

The first expanded result-propagation execution aborted on both backends. It
exposed a separate physical ownership error: semantic `move_local` unconditionally
took a readonly parameter whose physical guard was clear. The compiler agent's
`caef759e` makes that path copy a borrowed local and take only an owned local,
including by-reference storage. After joining it, every probe above passes.
The code and regression remain in the final branch; no test was weakened.

Remaining work includes combined arena and receiver/reboxing probes, borrowed
entry code generation and schematic traffic measurements, and the mandated
performance/RSS comparison. GC remains the default. `main` and the accepted GC
benchmark artifacts are unchanged.
