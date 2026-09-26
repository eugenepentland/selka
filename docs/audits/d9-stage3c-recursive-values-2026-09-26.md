# D9 stage 3c: recursive values

The compiler accepts finite recursive records and unions and stores edges that
close a value cycle in immutable managed boxes. The checked type and `.api`
surface remain the declared value type. Source construction, reads, matches,
`replace`, equality, hashing, printing, arena escape and typed JSON treat the
box as transparent. A cycle with no finite value still reports
`E_RECURSIVE_RECORD`.

## Tree comparison

`binary_trees_recursive.my` has the same workload and output as the existing
`class` version. The existing `binary_trees_arena.my` was also migrated from a
class to a recursive record; its output is unchanged. The perf result is in
[`d9-stage3c-binary-trees-2026-09-26.json`](d9-stage3c-binary-trees-2026-09-26.json).

| Backend | Program | Instructions, median of 3 | Peak RSS, median of 3 (KiB) |
| --- | --- | ---: | ---: |
| QBE | class | 2,187,878,860 | 16,512 |
| QBE | recursive union | 2,173,386,674 | 13,784 |
| LLVM `-O3` + LTO | class | 1,317,783,219 | 16,372 |
| LLVM `-O3` + LTO | recursive union | 1,131,572,127 | 13,972 |

The union is 0.993× class instructions on QBE and 0.859× on LLVM, with
lower RSS on both. There is no large performance gap to explain. These are
guest binaries built by the same Debug compiler; only the guest backend
differs. The host was shared, so instructions are more reliable than wall time.

To repeat from this worktree, first run `scripts/build-slot.sh build zig build
-Dcompiler-only=true`. Then run:

```bash
export PC_WORK="$PWD/.tmp-d9-stage3c-pc"
python3 experiments/perf-gc-dict-20260925/scripts/pc.py build \
  --side stage3c="$PWD/zig-out/bin/mylang" --only binary_trees \
  --arms qbe,llvm --jobs 1
python3 experiments/perf-gc-dict-20260925/scripts/pc.py measure \
  --sides stage3c --only binary_trees --arms qbe,llvm \
  --phases perf,rss --perf-reps 3 --cpu 10 \
  --out .tmp-d9-stage3c-results.json
```

The harness recognizes the recursive variant through its checked-in `.expected`
file and checks output during `build`. The arena migration was checked with
`mylang run` against the same expected output.

## Boundary checks

- `tests/lang/recursive_values.my` covers direct, mutual, generic, Option,
  tuple, fixed-array and collection recursion; match, mutation, `replace`,
  equality, hashing, printing and arena escape. Its generated recursive `Expr`
  property was run for 30 inputs. A nested `Expr.neg(Expr.num(42))` also passed
  through an explicit typed JSON test case. A deliberately failing recursive
  property shrank from a larger expression to a small nested `Expr.neg` tree.
- `mylang api --write` followed by `--check` rendered the recursive public
  `Expr` case signatures and reported the interface current.
- `tests/stress/recursive_values_deep.my` builds two million-node chains and
  compares and hashes them. It exits 0 on both QBE and LLVM with a 4 GiB guest
  budget; measured peak RSS was 175,164 and 175,192 KiB respectively. The
  guest test runner's step budget rejects that much construction, so this is a
  standalone native stress program; the regular guest regression uses 3,000.
- A 200-node copy of that program passed under `--gc-stress`. The recursive
  rendering test checks the clean depth cap (`...`). An 80-deep recursive
  typed JSON argument was rejected cleanly as `TestValueLimit` (exit 2).

The hidden box descriptor is `collection_kind == 5`, with its `element` naming
the one-field record body. A future copy-on-write transfer must mark mutable
collections reachable through that body as shared. If a pinned descendant
needs a private copy, it must clone each enclosing box and redirect the copied
value; mutating an existing box would change another holder's value.
