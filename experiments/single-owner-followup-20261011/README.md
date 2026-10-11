# Single-owner migration and nested cleanup

The next [explicit-snapshot prototype](../shared-snapshot-20261011/README.md)
adds `.snapshot()` alongside eager `.copy()` and measures their tradeoffs.
The measurements and compiler recorded below remain the frozen earlier stage.

This follow-up migrates the seven rejected list/record census programs and
emits direct destruction of nested owned collections. The flag remains
`--experimental-single-owner`; ordinary compilation keeps snapshot semantics.
The work is in the main-derived `codex/borrow-call-stack-20261010` worktree,
on top of the earlier destination, replacement, and single-owner experiments.

## Try it

From `/home/epentland/ai/canopy/mylang-borrow-stack-20261010`:

```sh
python3 experiments/single-owner-followup-20261011/try.py 10_loop_snapshots x x x x
python3 experiments/single-owner-followup-20261011/try.py nested_copy x x x x
```

Add `--default` before the sample name to use ordinary snapshot semantics.
The wrapper searches migrated samples first, then the original focused samples
and census, and also accepts a source path. It uses the pinned Zig installation
unless `ZIG` is set. `nested_copy` needs at least one argument.

Rebuild and reproduce the measurements:

```sh
scripts/build-slot.sh build /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig build install --prefix .tmp/single-owner-followup-20261011/candidate
scripts/build-slot.sh build python3 experiments/single-owner-followup-20261011/compare.py --before .tmp/single-owner-20261010/candidate/bin/mylang --compiler .tmp/single-owner-followup-20261011/candidate/bin/mylang --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig --output .tmp/single-owner-followup-20261011/measurements
```

The `--before` executable is the frozen first prototype, SHA-256
`1749c0630b02142b86145af329870556f815ab9f8ec3fcaf029c4592e3be0a80`.
The measured follow-up executable is
`1a8e90a961cf6e9bc5b12b40e8c618699681b89654e841ee6b65c969a9bfcbdf`.

## Source migrations

Original census files remain intact. Every migrated program preserves the
original outputs at both census inputs, under both language modes.

| Program | Change | Why |
| --- | --- | --- |
| [08_snapshot_read](migrated/08_snapshot_read.my) | Pass the same list to both readers. | The list never changes between reads; both calls borrow it. |
| [09_snapshot_mutate](migrated/09_snapshot_mutate.my) | `snapshot = values.copy()` | Preserve the old version while appending to the current one. |
| [10_loop_snapshots](migrated/10_loop_snapshots.my) | `history.append(values.copy())` | Each history entry must remain independent of later appends. |
| [13_record_snapshot](migrated/13_record_snapshot.my) | Construct the second record with `items=saved.items.copy()`. | Preserve the original record and its child list. |
| [16_branch_alias](migrated/16_branch_alias.my) | Copy the selected argument before returning it. | Returned storage escapes the borrow and is later mutated. |
| [19_return_field](migrated/19_return_field.my) | Return `packet.values.copy()`. | The caller keeps the packet while modifying the extracted list. |
| [20_loop_carried](migrated/20_loop_carried.my) | Make `append_batch` a `mut` helper. | Only the current list is needed; there is no saved version. |

No ownership or lifetime annotations were added. Five examples need explicit
copies; the other two use existing call borrowing and `mut` parameters.

## Compiler change

For a uniquely owned list whose elements contain other lists, the LLVM emitter
now generates a loop over the live elements. Existing typed cleanup handles
record and fixed-array fields and directly frees each owned child list. Shared
immutable leaves still use RC. Once the children are destroyed, the emitter
detaches the element descriptor before freeing the parent, preventing a second
runtime child walk. Verification builds assert count one at nested frees too.

This uses the established source contract and element type; no new escape
inference or source syntax is needed. The allocator, runtime layout, and default
semantics are unchanged. Destruction still executes at runtime; the compiler
determines which storage can be freed without count updates or count tests.

## Results

The migrated census runs **27 of 30 programs**: **20 still allocate managed heap
storage and 7 do not**, at both inputs. The other three use dictionaries and
remain explicitly unsupported. Previously, only 20 original programs were
accepted unchanged; comparing those denominators would overstate progress.

All **21 numeric/list-only census programs** now execute zero Core retains,
counted releases, uniqueness tests, runtime retains, and runtime releases in
counted release builds, excluding startup/teardown. The other six exercise
strings or text/byte buffers and retain their existing memory management.

At the larger input, the cleanup compiler change alone produces:

| Workload | Runtime child releases before → after | Direct frees before → after | Peak managed bytes before → after |
| --- | ---: | ---: | ---: |
| Loop snapshots | 11 → 0 | 2 → 13 | 2,176 → 2,176 |
| Nested-list census | 11 → 0 | 1 → 12 | 2,080 → 2,080 |
| Large nested-copy sample | 2,200 → 0 | 2 → 2,202 | 159,312 → 159,312 |

Allocation counts, allocated bytes, reallocations, copies, and peak managed
memory are unchanged by the cleanup change for all 33 measured programs at
both inputs. The gain is eliminating RC work. No speedup is claimed.

The language's copying tradeoff remains visible when comparing original
default semantics with the migrated single-owner programs:

| Workload | Default peak bytes | Single-owner peak bytes | Change |
| --- | ---: | ---: | ---: |
| Small snapshot then append (census 09) | 1,056 | 1,216 | 15.2% more |
| Loop snapshots (census 10) | 2,048 | 2,176 | 6.3% more |
| Large snapshot then append | 312,016 | 224,032 | 28.2% less |
| Copy nested lists, change one child | 89,008 | 159,312 | 79.0% more |
| Read-only explicit copy | 135,960 | 224,032 | 64.8% more |

The other five migrated census cases have unchanged peak memory relative to
their original default programs. Using `mut` in case 20 also removes its 11
uniqueness tests under default semantics, demonstrating that the source API
change helps independently of the experimental mode.

Peak bytes include program startup and managed storage only; these are not RSS,
stack usage, or all allocator scratch/reserved storage. Operation counters are
instrumented Core/runtime events, not final machine instructions. Core and
runtime RC columns can overlap and must not be added. In the mixed managed-record
census (15), remaining string releases now appear as Core releases when emitted
cleanup visits the record, so zero runtime releases does not mean zero string RC.

## Validation and boundaries

[results.json](results.json) records **476 comparative executions** with exact
output checks and zero live managed bytes at exit. Each updated single-owner
program runs at inputs 4 and 11 in release with counters, fact verification,
unoptimized, optimized debug, and release without facts. Separate lanes compare
original default code, migrated default code, and migrated code on the before
and after single-owner compilers.

Regression tests cover three-level trees, owning-variable replacement, `pop()`,
`clear()`, empty lists, early exits, wide records with shared strings, and fixed
arrays containing lists. [validation.json](validation.json) records compiler
and source hashes and the completed Core/Guardian checks.

The first prototype's unsupported source/lowering forms remain unsupported,
including some indexed replacement forms, dictionaries, recursive owning types,
and partial field moves. The regression tests use supported replacement forms;
this batch does not broaden the language contract. Shared strings/buffers still
use their previous memory model. See the [original rules and limitations](../single-owner-20261010/README.md).
