# Zero-RC prototype: Stage 6 and final results

The prototype has a separate count-free runtime ABI, statically checked moves
and borrows, direct destruction, scoped resources, and a backend task prototype.
The final compiler passes 48 sample programs / 470 executions across five
pipelines, with zero observed language/runtime RC and no managed leaks. All 30
original census workloads run; 23 still allocate in their measured workload and
7 do not. Startup may allocate even for those 7. Eliminating RC does not
eliminate heap allocation or ordinary destruction.

The runtime object structurally excludes the count member and legacy RC
implementations. Compilation rejects attempts to access that member or use
legacy helpers. Every measured executable also passes a symbol audit, and
emitted LLVM has no RC declarations, calls, count loads or count stores.
The supported language subset therefore does not rely only on observing zero
counter events. This remains an opt-in prototype, not complete language support.

Prototype qualification is complete: **898 Core tests, 83 frontend tests and
88 whole-tree Guardian checks pass**. [Validation](validation.json) pins the
packaged compiler, source snapshot and evidence hashes. The matrix, ABI proof,
cache/library survey and timing measurements are recorded below.

## Stages

| Stage | Implemented behavior | Evidence |
| --- | --- | --- |
| 2. Views | `TextView`/`BytesView` borrow owners; returned views tie to one input; escape and invalidation are rejected. | [Stage 2](../zero-rc-views-20261011/README.md): 385 clean executions; 10,000 slices avoid 10,000 allocations and 640,000 cumulative managed bytes. |
| 3. Containers | Owned dictionaries, sets, options/unions and recursive boxes; explicit deep copies and ownership-preserving extraction. | [Stage 3](../zero-rc-containers-20261011/README.md): all 30 census cases; 390 clean executions. |
| 4. Resources | Owned roots and lexically scoped dependent capabilities/files; explicit foreign borrow/transfer contracts. | [Stage 4](../zero-rc-resources-20261011/README.md): 25 executions and 5 refusals; native fixtures assert exactly-once cleanup on normal, early, propagated-error and loop exits. |
| 5. Tasks | Groups own task storage; captures move; results move out; scope exit joins. | [Stage 5](../zero-rc-tasks-20261011/README.md): 212 counted executions and 206 ThreadSanitizer executions. Backend prototype; no source task syntax or borrowed captures. |
| 6. Runtime/caches | Count-free ABI, audited text/byte/environment helpers, mode-separated persistent caches, resource-copy and text-view improvements. | [Final matrix](results.json), [ABI proof](abi.json), [cache/library survey](qualification.json), [task requalification](tasks.json), [performance](performance.json). |

Earlier stage reports and binaries remain frozen. Stage 6 repeats the original
census and extends it with 18 focused samples. It also repeats the task matrix
against the new ABI: 212 counted executions and 206 ThreadSanitizer executions
pass, including 100 repetitions of each of the four release/TSan fixtures.

## Language and runtime contract

- A dynamic allocation has one owner. Managed assignments/stores move;
  `.copy()` creates independent owned storage. Explicit sharing and snapshots
  are refused in zero-RC mode.
- Immutable literals are static storage. Views and read-only accesses borrow;
  they do not retain. A live borrow prevents invalidating its owner.
- Compiler-generated destruction walks owned children and frees blocks
  directly. Its work is real runtime work, but it does not decrement counts or
  test dynamic uniqueness. Synchronization atomics remain for task coordination.
- A root provider owns its native provider state. Dependent capabilities and
  files borrow a named parent through a `with` scope. Cleanup closes a child
  while its parent is still live. Managed values cannot cross arbitrary C calls.
- Unsupported ownership shapes or unaudited runtime calls refuse compilation.
  There is no fallback to RC. `check` validates source ownership; `build` also
  validates backend/runtime support.

`mylang-zero-rc-v2` marks emitted LLVM. The runtime's `kind` field moves to byte
zero and the count field disappears. The header is still **32 bytes** because
of alignment; this change alone saves no bytes per allocation. Static constants,
stack headers, allocator paths, dictionary hashes and text operations agree on
the new layout. Ordinary RC builds retain their own ABI and behavior.

Lowering and emission keys include ownership mode. Optimizer snapshots include
ownership mode and shared-list families; generated copy identities bind the
copied type by structure. Native objects bind runtime ABI. Artifact metadata
carries the mode even where cached LLVM text can be omitted. Zero-RC source and
Core body checking intentionally remain eager; deferred-body/native-handle-only
restoration is not enabled for this mode. Development builds reuse emitted
module units; release builds still emit a whole-program LLVM unit.

## Memory results

The following comparisons use the frozen Stage 4 zero-RC compiler and the final
compiler. Counters include complete execution, including startup and cleanup.

| Resource sample | Allocations before → after | Cumulative managed bytes before → after | Peak managed bytes before → after |
| --- | ---: | ---: | ---: |
| Native scoped exits | 31 → 28 | 2,304 → 2,112 | 608 → 608 |
| Nested propagated error | 22 → 21 | 1,760 → 1,696 | 800 → 800 |
| Early return | 7 → 7 | 576 → 576 | 416 → 416 |
| Native read-only file | 4 → 4 | 352 → 352 | 352 → 352 |
| Scalar foreign call | 0 → 0 | 0 → 0 | 0 → 0 |

Transferring an already-owned capability scope avoids copying it a second time.
The native scoped-exit sample still allocates more than its original ordinary-RC
baseline (24 allocations, 1,824 cumulative bytes, 576 peak bytes). Copies at
scope and managed `try` boundaries are part of that cost. Removing RC alone does
not guarantee lower memory use.

The 64-task fixture uses 623 managed allocations and 42,752 cumulative managed
bytes. Its peak depends on worker scheduling (roughly 17–20 KB in the frozen
runs); every run exits with zero live managed bytes. No paired RC task baseline
was measured, so no task-memory saving is claimed.

Managed counters exclude raw dictionary metadata, provider buffers, allocator
bookkeeping, task stacks and other native allocations. They are not total process
memory. Borrow-only view creation still allocates zero in its measured workload.
The original slice experiment's 640,000-byte saving is cumulative traffic, not
peak memory.

## Runtime and compile timings

Identical sources were compiled by the frozen Stage 4 and final compilers, both
in zero-RC release mode. Each runtime number is the median of nine alternating
paired runs after two warmups, pinned to CPU 2. Counters and leak checks are
disabled. The host is shared; these are microbenchmarks, not a general speedup
claim. Five million iterations are used except for large text (500,000).

| Workload | Previous runtime | Final runtime | Change |
| --- | ---: | ---: | ---: |
| Borrowed text | 165.73 ms | 106.31 ms | 35.9% faster |
| Borrowed bytes | 20.95 ms | 20.91 ms | effectively unchanged |
| Borrowed text, larger source | 17.14 ms | 11.46 ms | 33.1% faster |
| Owned text control | 129.24 ms | 137.52 ms | 6.4% slower median |

The owned-text ranges overlap (124.86–134.80 ms before, 125.24–142.35 ms after).
No performance improvement is claimed for it. The final borrowed-text variant
also runs about 22.7% faster than the final owned-text variant on this workload.
Text-view lookup skips bounded words of ASCII and retains the Unicode fallback;
61 mixed-Unicode/negative-index boundary combinations pass in all five modes.
RSS is approximately 2 MiB in these runs, with no demonstrated memory reduction.

| Workload | Cold project build before → after | Median warm stage build before → after |
| --- | ---: | ---: |
| Borrowed text | 91.92 → 106.10 ms | 32.62 → 33.04 ms |
| Borrowed bytes | 90.85 → 99.57 ms | 30.98 → 32.69 ms |
| Large text | 91.24 → 109.15 ms | 38.39 → 44.77 ms |
| Owned text | 88.83 → 107.87 ms | 27.18 → 36.96 ms |

Each cold build uses a fresh project cache; toolchain/runtime caches are shared.
Nine warm builds use `--emit-llvm`, disabling whole-build replay so stage work
is measured. Persistent caches add hashing and serialization costs to these
tiny programs; they do not improve these compile times. Larger-project compile
benefits remain unmeasured. The separate development-mode cache test restores
lowering, optimizer, emission and native artifacts, takes about 64–65 ms through
warm stages, and about 12.45 ms through whole-build replay. Changed valid source
rebuilds; changed invalid ownership is rejected. RC, single-owner and zero-RC
builds alternate safely in one store.

## Supported features and remaining work

| Area | Prototype status |
| --- | --- |
| Strings, bytes, buffers, lists, records, fixed arrays | Owned construction, mutation, direct destruction and explicit copies covered. |
| Dictionaries, sets, options, recursive trees | Covered by census and mixed/recursive samples; no shared owner cycles. |
| Text and byte helpers | Case/trim/search/predicates, split/join, replacement, formatting, encoding/decoding and hex covered by focused samples. |
| Views | Local views, call borrowing and a return tied to one input; no stored/escaping views or general lifetime parameters. |
| Resources | Root providers plus `with`-scoped dependent capabilities/files; native normal/error/early/loop exit fixtures pass. |
| Tasks | Backend moved-capture prototype with mandatory join and owned results; recoverable errors are Results. No source task syntax, borrowed captures, escaping handles or detached tasks. Fatal traps still end the process. |
| Foreign code | Scalar C signatures and audited native provider callbacks; no arbitrary retained managed pointers. |
| Allocation strategy | Ordinary heap allocation remains. Arenas, fixed capacity and broader automatic stack placement are separate work. |

The unmodified standard-library fixture survey is deliberately recorded as well
as the curated successes: **3 of 10 fixtures pass** (byte builder, integer
extrema, math). All 10 pass in ordinary RC mode. The other 7 fail explicitly:

| Fixture | First zero-RC refusal |
| --- | --- |
| `codecs`, `strings` | Returning a borrowed error-detail field needs an owned copy. |
| `json` | Returning a borrowed error-detail field needs an owned copy. |
| `path` | Returning a borrowed input needs an explicit copy or a view API. |
| `pool` | The fixture keeps using an owner after a move; its snapshot/sharing example needs migration. |
| `sort` | Generic minimum/comparison code preserves an implicit managed alias. |
| `time_random` | The fixture preserves an implicit generator snapshot, then uses the moved owner. |

This survey reports the first diagnostic, not proof that fixing one line makes
the whole module supported. Numeric parsing helpers not yet admitted by the
runtime contract also remain unavailable. A provider-injection-only fixture is
outside this ten-fixture survey; resource qualification covers injected provider
lifetimes separately. Broader library migration, source-level tasks and
borrowed captures remain work before a general language rollout.

## Reproduce and inspect

Candidate: `.tmp/zero-rc-final-20261011/candidate/bin/mylang`, SHA-256
`b8a00892fcc41313ff1589447766d84496db6f53099edc56a10afc34710cceb7`.
The compiler implementation is in the main-derived
`codex/borrow-call-stack-20261010` worktree. It is not merged into main.

Use the pinned Zig toolchain from `.zigversion`. All harnesses accept `--zig`:

```sh
python3 experiments/zero-rc-final-20261011/measure.py \
  --compiler .tmp/zero-rc-final-20261011/candidate/bin/mylang \
  --zig /path/to/pinned/zig --output .tmp/zero-rc-final-reproduction
python3 experiments/zero-rc-final-20261011/qualify.py \
  --compiler .tmp/zero-rc-final-20261011/candidate/bin/mylang \
  --zig /path/to/pinned/zig --output .tmp/zero-rc-final-cache-reproduction
```

`benchmark.py` additionally takes `--before` pointing at the frozen Stage 4
compiler. `abi.py` compiles/preprocesses the assembled runtime and audits its
symbols. `boundaries.py` checks five resource/foreign lifetime refusals.
Run guest build harnesses through `scripts/build-slot.sh build` on a shared host.
Use a fresh output directory; reports are written beside each harness.

Raw final artifacts live in `.tmp/zero-rc-final-20261011/`: `measurements-final`,
`qualification-final`, `benchmarks`, `abi`, `refusals`, `task-fixtures` and
`task-repetitions`. Source hashes are in [source-sha256-final.json](source-sha256-final.json).
The preliminary `measurements` run stopped on a sample filename colliding with
its imported module; the corrected sample is `environment_owned.my`. The first
cache harness incorrectly expected split emission reuse in release mode; the
final harness tests development-mode stage reuse. Neither preliminary harness
failure is included as a passing final result.
