# Stage 3: owned containers

The zero-RC prototype now covers all **30 original census programs**, plus six
container programs. Dictionaries and sets own inserted keys and values; reads
borrow, replacement destroys the old value, and `pop()` transfers ownership.
Explicit copies duplicate nested owned children. Unions, optional values and
recursive boxes follow the same rules. Pattern bindings borrow their owner.

```text
mut users = {1: "user-" + str(1)}
const saved = users.copy()
const removed = users.pop(1)
# removed and saved have independent owned storage.
```

The only new census migration is
[22_dict_snapshot.my](migrated/22_dict_snapshot.my): its preserved alias becomes
`values.copy()`. The earlier list, text and borrowed-slice migrations remain in
use. Ordinary parameters still borrow; `mut` parameters permit exclusive updates.
No lifetime names or ownership annotations were added.

Recursive copies use a finite compiler-generated type graph and an iterative
runtime worklist. Destruction also walks iteratively. This avoids recursive
compiler expansion and native stack growth proportional to the ownership tree.
The runtime still allocates the explicitly requested copy.

## Results

All **390 candidate executions** passed the strict whole-program RC/leak audit:
360 census runs and 30 focused runs, across release, unoptimized, optimized debug,
verified release and release without facts. Six additional RC baseline runs are
preserved separately. The [results](results.json) contain outputs, counters and
artifact hashes; [candidate-audit.json](candidate-audit.json) excludes the six
baseline runs and includes startup and teardown.

**23/30 census workloads still allocate; 0/30 use RC.** The earlier 20/27 result
is unchanged for those same programs; this stage admits three allocating
dictionary programs. Eliminating RC does not eliminate container storage.

The following comparison uses input 11 and the frozen Stage 2 compiler's default
RC mode, with each original dictionary program. The candidate uses zero-RC mode
and the explicit-copy migration where needed. Both produce identical output.

| Program | Managed allocations, before → after | Allocated bytes, before → after | Peak managed bytes, before → after |
| --- | ---: | ---: | ---: |
| Unique scalar dictionary | 14 → 14 | 1,280 → 1,280 | 1,280 → 1,280 |
| Preserved dictionary copy | 15 → 15 | 1,568 → 1,504 | 1,408 → 1,344 |
| Dictionary of strings | 69 → 69 | 4,800 → 4,800 | 1,952 → 1,952 |

The preserved-copy case saves 64 bytes of capacity at this input. The main result
is broader RC-free coverage, with no general allocation-count reduction. These
are managed-block counters, not process RSS: dictionary index/metadata and copy
worklist allocations are outside their accounting. No new execution-time or
compile-time improvement is claimed in this stage. The Stage 2 text-view timing
regression remains performance work for Stage 6.

## Validation

- 883 full Core tests passed before the final dictionary-iteration origin fix.
- All 50 focused ownership/zero-RC tests passed after that fix, including the new
  mutation-through-parameter and borrowed-key iteration regression.
- 62 frontend match/pattern tests passed.
- Five packaged-compiler lifetime violations were rejected with the expected
  diagnostic: moved keys, borrowed extraction, overlapping mutation, escaped
  pattern bindings and duplicated recursive children. See [boundaries.json](boundaries.json).
- The final compiler passed all 390 counted candidate executions and all 88
  whole-tree Guardian checks. [validation.json](validation.json) records hashes
  and the validation order.

Reproduce from the prototype worktree:

```sh
python3 experiments/zero-rc-containers-20261011/measure.py \
  --compiler .tmp/zero-rc-containers-20261011/candidate-final/bin/mylang \
  --before .tmp/zero-rc-views-20261011/candidate/bin/mylang \
  --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig \
  --output .tmp/zero-rc-containers-20261011/reproduction
```

The [original stage plan](../zero-rc-20261011/README.md) remains authoritative.
Resources/foreign boundaries, scoped concurrency, complete runtime ABI removal,
remaining standard-library coverage and performance evaluation follow in Stages
4–6. Existing unsupported-operation diagnostics remain; passing this census is
not a claim that every language feature is implemented without RC. The default
language mode and earlier experiments retain their existing behavior.
