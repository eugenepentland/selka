# Single-owner language prototype

The [migration and nested-cleanup follow-up](../single-owner-followup-20261011/README.md)
adds direct child-list destruction and brings the migrated census to 27/30
supported programs. Measurements below describe the frozen first prototype.

This experiment runs in the main-derived `codex/borrow-call-stack-20261010`
worktree, on top of the caller-destination and repeated-replacement prototypes.
Default compilation still uses the existing snapshot semantics.

## Try it

From `/home/epentland/ai/canopy/mylang-borrow-stack-20261010`:

```sh
python3 experiments/single-owner-20261010/try.py snapshot x x x x
python3 experiments/single-owner-20261010/try.py nested_copy x x x x
python3 experiments/single-owner-20261010/try.py --default snapshot x x x x
```

Both snapshot runs print `7998000 7998003`. The nested copy prints
`240600 240609`. Available samples are `mutate`, `snapshot`, `records`,
`nested_copy`, `callback`, and `unused_snapshot`. At least one argument is
needed by the samples that index their input.

The wrapper uses `.tmp/single-owner-20261010/candidate/bin/mylang` and the
pinned Zig installation, unless `ZIG` is already set. The compiler flag works
directly with `run`, `build`, `check`, and `dump-ir`:

```sh
.tmp/single-owner-20261010/candidate/bin/mylang check experiments/single-owner-20261010/rejected/use_after_move.my --experimental-single-owner
.tmp/single-owner-20261010/candidate/bin/mylang dump-ir experiments/single-owner-20261010/samples/snapshot.my --experimental-single-owner --facts
```

The first command intentionally reports `E_SINGLE_OWNER_MOVED`. Other rejected
examples demonstrate returning borrowed storage and overlapping read/mut arguments.
The experimental flag is not yet supported by `mylang test`.

To rebuild the compiler:

```sh
scripts/build-slot.sh build /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig build install --prefix .tmp/single-owner-20261010/candidate
```

## Rules being tried

```mylang
mut values = [1, 2, 3]
const saved = values.copy()  # independent storage, copied explicitly
const moved = values        # transfers storage; values is now unavailable
```

- Lists, including nested lists and records containing lists, transfer at source
  assignments, constructor arguments, container insertion, and returns.
- Ordinary parameters borrow for the duration of a call. `mut` parameters allow
  exclusive mutation and replacement. Neither kind of parameter can be moved into
  another owner or returned directly; an explicit copy can be returned.
- A function can return a newly constructed list or record normally.
- `.copy()` eagerly copies list storage, recursively copying owned list children
  inside records and lists. Immutable strings/bytes keep their existing sharing.
- A field/element read can be passed to a helper. Moving a field directly out of
  an existing record is refused; copy it explicitly. `pop()` can transfer an
  owned list element out of its parent.
- A list cannot be mutated/moved while an argument or iteration borrows its root.
  The prototype conservatively treats all fields/elements of that root as
  overlapping. Moves inside loops must be balanced by reinitialization, including
  before `break`/`continue`.

No ownership types, lifetime parameters, or borrow markers are added. Move
availability and call exclusivity are still checked by the compiler.

## Boundaries

This is an experimental contract over existing Core lowering and cleanup.
It does not remove all compiler liveness analysis or the runtime count header.
Strings, bytes, byte buffers and external resources retain their existing
memory model. Generic destruction of nested list children still uses runtime
releases, even though their unique ownership is known.

Dictionaries/sets, recursive records, unions containing lists, `match`/resource
scopes, some argument-evaluation forms, partial record moves, and some nested
list methods are refused. These are prototype limitations, not proposed permanent
language rules. `.copy()` is currently a list method; copying a standalone
record can be written as a constructor with explicit copies of its list fields.

The source checker runs before optimization, with complete typed bodies.
Prototype builds bypass persistent lowering/optimization/emission stage caches;
frontend tree caches remain usable and executable replay includes the mode.
A final guard rejects Core lowerings that would retain an exclusively owned
list-containing value. Verification builds deliberately keep uniqueness assertions.

## Measurements

`results.json` compares the same six source programs, using the same compiler,
with and without the flag. Each runs at two inputs under release, fact verification,
unoptimized, optimized debug, and release without facts. Leak checks are enabled.
The default comparison includes our previous destination/replacement optimizations.

At the larger input:

| Workload | Default peak managed bytes | Single-owner peak managed bytes | Change |
|---|---:|---:|---:|
| Grow a list | 135,960 | 135,960 | unchanged |
| Return a record containing a list | 135,960 | 135,960 | unchanged |
| Copy a snapshot, then append | 312,016 | 224,032 | 28.2% less |
| Copy nested lists, then change one child | 89,008 | 159,312 | 79.0% more |
| Copy a snapshot that is never mutated | 135,960 | 224,032 | 64.8% more |
| Callback and recursive readers | 896 | 896 | unchanged |

The snapshot/append case removes one retain, three counted releases and three
uniqueness tests, replacing cleanup with two direct frees. It also avoids one
buffer reallocation. The nested-copy case removes 1,100 runtime retains and its
uniqueness test, but copies all 1,100 child lists; default COW copies only the
modified child and outer list. All six focused programs have zero emitted list
retains, counted releases and uniqueness tests in counted release builds.
Nested child destruction still executes runtime releases.
RC totals are instrumented Core events, not counts of final machine instructions.

Peak numbers cover the entire program's managed storage, including startup.
Allocation/RC counts in `kernel` exclude startup. They are not RSS or stack
measurements, and allocator scratch/reserved slabs are not fully counted.
Direct frees still happen at runtime. Dynamic storage remains heap-allocated.

The unchanged 30-program census is a separate admission check: 20 compile and
run under the prototype, of which 14 allocate and 6 do not. Ten are deliberately
rejected (implicit snapshots/borrow escapes, or unsupported dictionaries).
This is not a reduction from the previous 23/30 allocating count: the accepted
subset has changed. We have not rewritten the full census to the new rules.

Reproduce:

```sh
scripts/build-slot.sh build python3 experiments/single-owner-20261010/compare.py --compiler .tmp/single-owner-20261010/candidate/bin/mylang --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig --output .tmp/single-owner-20261010/measurements
```

The result is a simpler ownership contract and less RC bookkeeping, with a
substantial copying cost for workloads that benefit from cheap snapshots.
The prototype is useful for evaluating that language tradeoff; the measurements
do not establish a general memory or speed improvement.
