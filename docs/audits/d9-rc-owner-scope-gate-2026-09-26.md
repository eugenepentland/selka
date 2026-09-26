# D9 generated RC owners and receiver scopes: regression checkpoint

Frozen `3f48de26` passes the full required regression gate with GC still the
default. This checkpoint includes actual RC owner/frame lowering, transactional
collection adapters, captured receiver scopes, iterative arena escape, physical
counters, and the initial borrowed-accessor certificate analysis. It does not
complete WP-4 acceptance.

| Command | Result |
| --- | --- |
| `zig build test --summary all` | 94/94 steps; 2,177 executed tests; 22,090 shard exclusions |
| `zig build test-qbe --summary all` | 51/51 steps; 437 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps; unchanged test verdicts cached |
| `zig build fmt-check --summary all` | 2/2 steps |

The Debug compiler SHA-256 is
`c769fc46547f246fcd02a2ef1e8542675f2499c38b0a953a7054b862fc24941f`.
The [machine-readable evidence](evidence/d9-rc-owner-scope-gate-2026-09-26.json)
contains exact compressed logs and their raw hashes. Source remained frozen;
the four commands held the shared gate serialization lock and used a private
worktree cache and on-disk scratch. All 88 Guardian checks passed.

Included implementation and focused evidence:

- `372b751c`: generated owner frames and canonical owned return publication.
- `1499cbd2`: nested field uniqueness and borrowed identity text casts.
- `c77c3c3b`, `f16dfecc`, `bc5ec7bf`: iterative arena escape and region checks,
  pinned graph memoization, and atomic arena metadata/chunk reservations.
- `8935a919`: transactional optional reboxing bridge.
- `4ce0c9ae`: held and pinned captured receivers across callback mutation.
- `886fad94`: 71 collection cases on each backend, balanced physical counts.
- `766113b0`: strong physical accessor certificates; canonical calls remain owned.

Receiver testing also found a GC snapshot error present in the accepted
`f6bea5d9` compiler: saving an outer list during a nested receiver callback can
expose the subsequent mutation through the saved snapshot. The exact historical
control and RC passing evidence are retained in the
[receiver report](d9-rc-receiver-lowering-2026-09-26.md). Its separate GC fix is
pending at this checkpoint.

The aggregate publication branch and the borrowed-local move correction
`caef759e` were developed while this source was frozen; they are not included
in these results. Iterative unique-resource cleanup, remaining arena compiler
integration, certified borrowed entry emission, schematic count reduction,
and the required 43-program-per-backend performance/RSS comparison also remain
pending. The accepted GC performance artifacts remain unchanged.

Every integration join uses a real two-parent merge. `main` remains `b292660a`;
no push, main merge, or devspeed landing occurred. WP-5 follows WP-4.
