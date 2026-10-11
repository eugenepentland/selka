# Remaining allocation and reference-counting census

Thirty small programs passed **180 executions**: two runtime inputs, each run
as an ordinary release build, a counting release build, and a release build
with fact verification. All outputs match independently derived expectations;
every run enables the leak checker, and all counted runs finish with zero
managed live bytes. This experiment adds programs and evidence; it changes no
compiler or runtime code.

The compiler is the borrowed-call stack-promotion prototype on LLVM main
`1d202d41bfff888ee91354f706cb74e860dc4b94`, on branch
`codex/borrow-call-stack-20261010`. Its executable SHA-256 is
`5ca393ede35337754edf06c0cf5551f491dc87037d3988ea4d410b0422e3db2d`.
The pinned Zig is `0.17.0-dev.1683+5ceec001b`. The compiler's production sources
still match the preceding prototype measurement. This is a census of that
candidate, not a before/after comparison with an unmodified compiler.

[All sources](samples), [per-program evidence and source locations](DETAILS.md),
[CSV](summary.csv), and [machine-readable results](results.json) are preserved.
The three input manifests include the independent output derivations:
[lists](lists.json), [composites](composites.json), [containers](containers.json).
Every program prints an integer checksum using `n = len(args)`. Inputs consist
of four or eleven copies of `x`, so the compiler must handle runtime values.
The checksums observe both versions in snapshot cases.

## Findings

Six cases have no observed managed heap or RC work at either input: scalar
arithmetic, the local bounded list, the borrowed-reader list, the caller-created
mutable destination, the read-only list alias, and the scalar record.
The other 24 allocate managed storage. Six execute retain sites; many of the
remaining cases have releases or uniqueness tests without introducing sharing.
The unique dictionary, filter, and sort cases free known-unique storage directly.
These are different optimization problems, even though all use runtime storage.

The caller-created destination comparison is particularly useful:

| Equivalent eight-value sum | Managed blocks | Retains | Releases | Promoted lists |
| --- | ---: | ---: | ---: | ---: |
| Local construction | 0 | 0 | 0 | 1 |
| Local construction, separate reader | 0 | 0 | 0 | 1 |
| Helper constructs and returns list | 2 | 0 | 1 | 0 |
| Caller creates list, helper fills it | 0 | 0 | 0 | 1 |

The last row benefits from **inlining the mutating helper**, which exposes its
fixed eight-element fill to the local stack pass. The returned constructor
remains a call. This demonstrates an optimization opportunity around result
placement; it does not establish that caller initialization should be mandatory
or that arbitrary non-inlined mutating helpers already support stack lists.

The clearest avoidable-sharing candidate is
[20_loop_carried.my](samples/20_loop_carried.my): the caller replaces its old
list with `append_batch`'s result and immediately releases the old value. The
callee nevertheless retains its ordinary argument before mutating it. At
`n=11` this executes **11 retains, 33 uniqueness tests, and 11 list-copy calls
copying 1,320 element bytes**, plus growth. The first copy is an empty list.
The [optimized IR](evidence/20_loop_carried/core.ir) preserves this call boundary.
No source snapshot needs the previous version. This is a concrete candidate for
an inferred consuming argument or specialized internal calling convention.

Both the indirect-reader and recursive-reader cases retain their call boundaries
and allocate one four-element list, with no retain but one release. The current
strict borrowing proof cannot establish either case. In contrast, the ordinary
borrowed-reader control has no managed allocation or RC operation.

The managed-composite examples show where cleanup moves into the runtime:
at `n=11`, nested lists allocate 25 blocks and execute 11 runtime releases;
records containing dynamic strings and lists allocate 45 blocks and execute
22 runtime releases. The records themselves are value aggregates containing
managed fields, not necessarily separate heap objects.

Copies in the saved-record, branch-alias, returned-field, dictionary-snapshot,
and text-snapshot cases preserve old values that the checksums explicitly read.
Those semantics need preserving even if a compiler can eliminate RC bookkeeping
or choose a different representation. A zero retain count also does not imply
zero copying: the list snapshot and returned-field cases each copy once without
retaining.

## Reading the evidence

The table below uses the `n=11` execution except for its two-input block column.
`R+ / R- / F` means Core retain sites, Core release sites, and direct frees of
known-unique blocks. Runtime count operations have their own column because
they include recursive cleanup and out-of-line operations. **Do not add the
Core and runtime release columns:** they can describe overlapping work.
Copy hooks count instrumented collection-copy helpers; they are not a complete
count of all bytes copied. Aggregate copy sites appear separately in DETAILS.
Uniqueness counts are Core sites only. Runtime helpers also perform uncounted
uniqueness and range checks, including byte-buffer append checks; zero in that
column does not establish that no uniqueness check occurred anywhere.

The reported kernel totals sum emitted functions and exclude `<outside>`.
Startup/teardown matches the scalar control for every sample: five blocks and
320 managed bytes at `n=4`, twelve blocks and 832 bytes at `n=11`. Raw JSON
retains those totals and whole-program peak/live measurements.

Counters describe executions of the **instrumented build**. Core site hooks
are inserted before LLVM optimization; they can count operations LLVM would
otherwise remove or rearrange. Matching ordinary-build outputs validates
behavior, not equal operation counts or performance. No timings were used.

Static `cost` allocation sites indicate possible allocations, not allocation
executions. Its totals can retain standalone definitions whose calls were
inlined; case 05 still has static allocation sites in `fill_values` despite no
dynamic allocation. Case 19 similarly retains an uncalled accessor definition
with a static retain. Use executed sites and function calls to distinguish these.
Ownership-inserted cleanup may be attributed to the function declaration rather
than a specific source statement. Allocated blocks are attributed to emitted
functions, while RC/copy site records also preserve the source function and line.

Managed allocation bytes are size-class/usable block bytes, not process RSS.
They omit dictionary side tables, sorting scratch, and other raw C allocations.
In particular:

- Dictionaries allocate metadata, hash arrays, and indexes separately from the
  counted entry block in [core_dict.c](../../src/core/runtime/core_dict.c#L155).
  Four and eleven entries fall on opposite sides of the eight-entry small-map
  threshold. Copy-byte counters include hashes even though managed allocation
  bytes omit that side storage.
- The sort sample sorts 304 or 311 nonmonotone integers. The runtime's scalar
  radix path allocates scratch with `malloc(count * sizeof(uint64_t))` in
  [core_sort.c](../../src/core/runtime/core_sort.c#L359). That implies 2,432 or
  2,488 requested scratch bytes from the source path; **these are inferred, not
  dynamically measured by this census**. The table's one block is the managed
  list only.
- `bytes(buffer)` in case 28 allocates a fresh managed block and copies the
  buffer payload. It is not hooked as `buffer_copy`; the zero copy-hook count
  therefore does not mean the snapshot avoided copying. The source implies
  12 or 33 copied bytes. This materialization's allocation is counted.
- Text concatenation and other materializations can also copy bytes outside
  the named copy hooks. Case 26's returned substring copies through
  [core_text.c](../../src/core/runtime/core_text.c#L365) without a text-copy hook.
  Its `ord(part[0])` also materializes a non-ASCII character at `n=4`, while
  `n=11` uses a cached ASCII character; the two inputs are not pure size scaling.
  Growth-copy counters remain separate from copy events.

These are 30 curated examples at two inputs, not an exhaustive language test or
an application performance distribution. They cover both parity branches in
the selection examples but do not cover all sizes, empty inputs, concurrency,
foreign calls, or every container operation.

## Measurements

| Program | Managed blocks n=4 → n=11 | Core R+ / R- / F | Runtime R+ / R- | Uniqueness tests | Copy-hook events |
| --- | ---: | ---: | ---: | ---: | ---: |
| [01_scalar](samples/01_scalar.my) | 0 → 0 | 0 / 0 / 0 | 0 / 0 | 0 | 0 |
| [02_local_list](samples/02_local_list.my) | 0 → 0 | 0 / 0 / 0 | 0 / 0 | 0 | 0 |
| [03_borrowed_reader](samples/03_borrowed_reader.my) | 0 → 0 | 0 / 0 / 0 | 0 / 0 | 0 | 0 |
| [04_returned_list](samples/04_returned_list.my) | 2 → 2 | 0 / 1 / 0 | 0 / 0 | 0 | 0 |
| [05_mut_destination](samples/05_mut_destination.my) | 0 → 0 | 0 / 0 / 0 | 0 / 0 | 0 | 0 |
| [06_dynamic_list](samples/06_dynamic_list.my) | 1 → 1 | 0 / 1 / 0 | 0 / 0 | 0 | 0 |
| [07_large_list](samples/07_large_list.my) | 1 → 1 | 0 / 1 / 0 | 0 / 0 | 0 | 0 |
| [08_snapshot_read](samples/08_snapshot_read.my) | 0 → 0 | 0 / 0 / 0 | 0 / 0 | 0 | 0 |
| [09_snapshot_mutate](samples/09_snapshot_mutate.my) | 2 → 2 | 0 / 2 / 0 | 0 / 0 | 0 | 1 |
| [10_loop_snapshots](samples/10_loop_snapshots.my) | 5 → 12 | 11 / 11 / 1 | 0 / 11 | 11 | 10 |
| [11_record_scalar](samples/11_record_scalar.my) | 0 → 0 | 0 / 0 / 0 | 0 / 0 | 0 | 0 |
| [12_record_list](samples/12_record_list.my) | 1 → 1 | 0 / 1 / 0 | 0 / 0 | 0 | 0 |
| [13_record_snapshot](samples/13_record_snapshot.my) | 3 → 4 | 1 / 3 / 0 | 0 / 0 | 11 | 1 |
| [14_nested_lists](samples/14_nested_lists.my) | 10 → 25 | 0 / 1 / 0 | 0 / 11 | 0 | 0 |
| [15_managed_elements](samples/15_managed_elements.my) | 17 → 45 | 0 / 12 / 0 | 0 / 22 | 0 | 11 |
| [16_branch_alias](samples/16_branch_alias.my) | 3 → 3 | 1 / 4 / 0 | 0 / 0 | 1 | 1 |
| [17_indirect_reader](samples/17_indirect_reader.my) | 1 → 1 | 0 / 1 / 0 | 0 / 0 | 0 | 0 |
| [18_recursive_reader](samples/18_recursive_reader.my) | 1 → 1 | 0 / 1 / 0 | 0 / 0 | 0 | 0 |
| [19_return_field](samples/19_return_field.my) | 2 → 2 | 0 / 2 / 0 | 0 / 0 | 0 | 1 |
| [20_loop_carried](samples/20_loop_carried.my) | 5 → 18 | 11 / 23 / 0 | 0 / 0 | 33 | 11 |
| [21_dict_unique](samples/21_dict_unique.my) | 1 → 2 | 0 / 0 / 1 | 0 / 0 | 0 | 0 |
| [22_dict_snapshot](samples/22_dict_snapshot.my) | 2 → 3 | 1 / 3 / 0 | 0 / 0 | 11 | 1 |
| [23_dict_managed](samples/23_dict_managed.my) | 21 → 57 | 0 / 11 / 1 | 0 / 22 | 0 | 22 |
| [24_text_builder](samples/24_text_builder.my) | 2 → 3 | 0 / 2 / 0 | 0 / 0 | 11 | 1 |
| [25_text_snapshot](samples/25_text_snapshot.my) | 4 → 5 | 1 / 4 / 0 | 0 / 0 | 22 | 2 |
| [26_text_slice](samples/26_text_slice.my) | 4 → 4 | 0 / 4 / 0 | 0 / 0 | 13 | 1 |
| [27_buffer_builder](samples/27_buffer_builder.my) | 4 → 6 | 0 / 2 / 0 | 0 / 0 | 0 | 0 |
| [28_buffer_snapshot](samples/28_buffer_snapshot.my) | 5 → 7 | 0 / 3 / 0 | 0 / 0 | 0 | 0 |
| [29_list_filter](samples/29_list_filter.my) | 3 → 4 | 0 / 0 / 2 | 0 / 0 | 0 | 0 |
| [30_sort_scratch](samples/30_sort_scratch.my) | 1 → 1 | 0 / 0 / 1 | 0 / 0 | 0 | 0 |

## Questions for the subsequent compiler audit

1. Can last use at a call select a consuming internal parameter or specialization,
   eliminating the artificial sharing and copies in case 20?
2. Can a fresh-return summary place case 04's construction in the caller's
   destination, and preserve that optimization across non-inlined calls?
3. Can recursive borrowing proofs and finite indirect-target sets safely admit
   cases 17 and 18? Recursive proof cycles must be validated as a group.
4. Which nested allocations can be flattened, scalar-replaced, or assigned a
   common bounded lifetime? Cases 12, 14, and 15 isolate fields and children.
5. Which unique builders still need dynamic storage but could use known capacity,
   direct cleanup, or compiler-provided scratch? Cases 06, 07, and 21–30 separate
   this from snapshot preservation and expose counter coverage gaps.

These are audit questions supported by the probes, not claims that all observed
allocations or copies can be removed. The language does not need new ownership
annotations to investigate them.

## Reproduction

From the implementation worktree, use the same candidate compiler and toolchain.
The output directory must be fresh, or use `--resume`. Resume requires matching
sample, compiler, runner, and toolchain hashes, plus expected outputs.

```bash
scripts/build-slot.sh build python3 experiments/rc-census-20261010/census.py \
  --compiler .tmp/borrow-stack-20261010/candidate/bin/mylang \
  --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig \
  --output .tmp/rc-census-20261010/reproduction \
  --publish
```

Use `--case 20_loop_carried` to qualify one sample without `--publish`.
Publishing requires the complete suite and regenerates results, CSV, detailed
tables, and preserved static/counter evidence. This report contains the curated
interpretation. Commands, output, ordinary LLVM, executable hashes, and binaries
from the original run are in `.tmp/rc-census-20261010/run1/`.
