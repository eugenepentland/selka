# D9 recursive box path copying and lazy transfers, 2026-09-26

Branch `codex/d9-lazy-box-after-boxfix`, implementation tip `89ca1742`, fixes
collection writes through immutable recursive boxes and makes a box transfer
independent of the number of its descendants. This does not complete the D9
stage 3 performance gate.

## Changes

- `daaf525b` detaches every box crossed by a nested collection write. The
  owning container stays rooted while allocating; the child is reloaded from
  the detached body before testing its shared flag. A fresh unique child is
  stored immediately, with the parent barrier, before another allocation.
  Pure mutable calls also publish roots for their allocating COW preparation.
- `0bde7992` stops descriptor reachability and sharing walks at immutable box
  pointers. Every guest body projection creates private inline storage and
  shallow-shares its directly held mutable children, copying pinned children
  only into that private storage. Projection is a safepoint for root, borrow
  and loop planning. An exposed child remains protected if its parent is
  copied later.
- `89ef2ee6` narrowly cherry-picks the lazy-box documentation and deep-chain
  stress update from `4590cc53`, retaining this branch's explicit switch wording.
- `89ca1742` narrowly cherry-picks `b39deab8`, the previously integrated
  migration-checker class-reachability fix, to make this older branch's gate
  practical. It is independent of box runtime behavior.

The 1,024-edge COW limit still applies to inline record, array and variant
walks. Box hops no longer consume it. Arenas remain supported.

## Validation

All commands ran in `/home/epentland/ai/canopy/mylang-worktrees/d9-box-path-fix`
with a Debug compiler, per-worktree caches and on-disk temporary storage.
The full gate was serialized using `../.d9-closeout-gate.lock` and each build
used `scripts/build-slot.sh`.

```sh
export ZIG_LOCAL_CACHE_DIR="$PWD/.cache-box-path"
export ZIG_GLOBAL_CACHE_DIR="$PWD/.cache-box-path-global"
export TMPDIR="$PWD/.tmp-box-path"
flock ../.d9-closeout-gate.lock bash .tmp-box-path/full-gate.sh
```

The script runs these steps in order:

| Command (after `scripts/build-slot.sh gate`) | Result | Local log |
| --- | --- | --- |
| `zig build test --summary all` | 93/93 steps; 2,104 executed tests passed | `.tmp-box-path/gate-main.log` |
| `zig build test-qbe --summary all` | 51/51 steps; 428 tests passed | `.tmp-box-path/gate-qbe.log` |
| `zig build test-qbe-build --summary all` | 29/29 steps | `.tmp-box-path/gate-build.log` |
| `zig build fmt-check --summary all` | 2/2 steps | `.tmp-box-path/gate-fmt.log` |

The main gate reports 23,427 total shard selections, including 21,323 skipped
selections; those skipped selections are not additional executed tests.
`fmt-check` was also run separately with `--summary all` to record its count.
Guardian's whole-tree commit gate passed all 88 checks without ratchet growth.

Focused checks:

- `zig build test-units -Dtest-filter='copy on write' test-native-heap --summary all`:
  23/23 Zig tests and the native heap/COW/arena tests passed
  (`.tmp-box-path/focused.log`).
- `mylang test tests/value_semantics/recursive.my --value-semantics --gc-stress`
  and the same command with `--release`: 5/5 on QBE and LLVM. These cover
  projections before a later copy, pinned children, arena escape and repeated
  nested writes (`recursive-lazy.json`, `recursive-llvm.log` under scratch).
- Independent direct-box/list/dictionary/mutable-call/arena smoke:
  `mylang build ../d9-stage3f-mode-path/.tmp-mode/box_verify_main.my
  --value-semantics --backend llvm --mode Debug -o .tmp-box-path/verify-llvm`,
  then `MYLANG_OPTIONS=--gc-stress .tmp-box-path/verify-llvm`: exit 0.
- `mylang test ../d9-stage3f-mode-path/.tmp-mode/box_pure_call.my
  --value-semantics --gc-stress`: 12/12 call/root stress cases passed
  (`.tmp-box-path/pure-lazy.json`).
- `mylang test tests/lang/recursive_values.my --gc-stress`: 10/10 passed
  after the migration-analysis prerequisite (`recursive-main-after-alias.log`).

`.tmp-box-path/deep-check.py` builds each of the three committed stress sources
with `--value-semantics --mode ReleaseFast`, on QBE and on LLVM with
`--llvm-opt 3 --lto`. All six native runs exit 0, with a 1 GiB memory ceiling:

| Source under `tests/stress/` | Result on both backends |
| --- | --- |
| `recursive_values_cow_depth.my` | 1,101 collection-bearing nodes copied and traversed under native GC stress; prints `1099` |
| `recursive_values_cow_deep.my` | Million-node immutable chain copied; prints `1000000` and `-1` |
| `recursive_values_deep.my` | Two million-node chains compare equal and hash to one set entry |

The commands and results are retained in `.tmp-box-path/deep-check.py` and
`.tmp-box-path/deep-check.log`. GC stress is used for the collection-bearing
1,101-node case; the million-node cases use the normal collector.

## Gate friction

The first attempt lacked `b39deab8`: the old migration checker spent 3m27s of
CPU compiling `recursive_values.my`. Only that owned compiler PID was
terminated, the failed gate was allowed to exit, and the prerequisite was
cherry-picked before a fresh gate. The first attempt also had one unrelated
CLI comparison failure because a cold Zig global cache printed its
`ar rcs ... libunwind.a` command on stderr. Its focused rerun passed 1/1, and
the fresh full gate passed. The original log remains at
`.tmp-box-path/gate-main-before-alias-fix.log`; the focused rerun is at
`.tmp-box-path/focused-llvm-cli.log`.

## Performance limit and follow-up

The fixed tree N4 workload, frozen `b51cddc1` Lox source and QBE ReleaseFast
still measured 5,182,251,956 instructions against 58,266,095 for the exact
baseline binary, median of three on CPU 11, with matching output. This
88.94× result is a failure of the broad performance target, not acceptance.
[Raw counts and identities](evidence/d9-lazy-box-tree-check.json) record the
compiler, source, binary and script identities; older baseline numbers must
not be substituted for this measurement.

The hot tree code has no recursive-box projections. Profiling attributes its
remaining cost to copying the runtime object list on environment allocation:
`share_at` 37.79%, `scan_payload` 21.26%, with callers predominantly
`heap::allocate <- interpreter::new_env <- interpreter::execute_block`.
The independently validated closed-region ownership proof `9f42e5a9` reduces
the same source/workload to 156,930,989 instructions (2.693× baseline). Its
measurements remain at `.tmp-box-path/tree-region-perf.json`; that proof and
subsequent interpreter source changes are separate work, not part of the
box implementation reported here.
