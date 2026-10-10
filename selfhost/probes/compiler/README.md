# Qualified compiler library probes

These ordinary Selka modules use only the frozen component-v1 operations in
`docs/bootstrap-v1.md`. This is reusable algorithm evidence, not production
frontend routing or an extension of the qualified profile.

From this worktree, configure private disk scratch and local cache:

```sh
export TMPDIR="$PWD/.tmp/compiler-probes"
mkdir -p "$TMPDIR"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
scripts/build-slot.sh build zig build component-builder
scripts/build-slot.sh build python3 selfhost/tests/run_compiler_probes.py --zig /home/epentland/.local/bin/zig
```

The driver obtains its seed only through the coordinator's receipt-verifying
`--seed-only` command, prints the executable digest and executes both uncached
forced test modes. Release includes `--verify-facts` and `MYL_CORE_LEAKCHECK=1`.
No arbitrary development compiler option is accepted as qualification evidence.

Eleven tests cover byte-offset lookup, UTF-8 interior positions, EOF, empty source
and invalid offsets; retained source/slice snapshots; token records and nested
node children after COW mutation; insertion IDs and deterministic cyclic BFS;
stable sorting with tied keys; byte diagnostics and sizes 16, 128, 1024, 4096.
`locate` returns one-based byte columns: byte offset 6 in
`a\xc3\xa9\n\xf0\x9f\x98\x80z\n` is line 2, column 3, even though it is
inside the emoji. Diagnostic location fragments are preformatted byte values;
integer-to-text rendering is outside this probe.

## Ownership and bounds

Nodes and tokens are indexed values, with no identity sharing. A retained
snapshot stays independent through nested mutation. Name IDs are insertion
positions in an immutable logical snapshot. Traversal order follows adjacency
order. `walk`/`traverse` require a nonempty graph, a root in `[0,len(edges))`,
and every edge target in that range. The callers own validation; these are pure
algorithm helpers, not a hostile-input decoder. Invalid `locate` offsets return
an explicit checked failure. `growing` requires size >= 1. The largest tested
size is 4096, not a declared maximum. Empty diagnostics and empty sort work.

## Evidence and ranked gaps

1. **Confirmed qualification limit: dictionary operations are not enumerated
   component-v1.** Minimal additional requirement: `mut ids: dict[str, int] = {}`
   followed by `ids["name"] = 0` and lookup. This is not run or declared a seed
   compiler rejection: current development acceptance cannot qualify it. Required
   behavior is a qualified bounded name lookup/insert API. Workaround: `Names`
   uses bytes[] insertion positions, returning existing IDs for duplicate names.
   Its worst-case comparison count grows quadratically for distinct names; keep
   tables small or follow up with a profile-safe sorted/bucketed index. Hashing
   and dictionary qualification remain separate tasks.
2. **Confirmed qualification limit: native sort is not explicitly enumerated.**
   Minimal additional requirement: `mut keys: bytes[] = [b"b", b"a"]` followed
   by `keys.sort()`. Existing cache-plan source uses this API, but that observation
   does not amend the written profile. This is a written-profile versus existing
   qualified-closure discrepancy, not proven missing seed functionality. Workaround: `sort_names` and `stable_order`
   use admitted indexed updates and comparisons. Strict comparisons preserve
   ties, observed as IDs `[1,3,0,2]` for keys `[b"b",b"a",b"b",b"a"]`.
   Insertion sorting has quadratic worst-case comparisons; a merge sort or
   separately qualified native sort is needed for large compiler tables.
3. **Unmeasured allocation/copy cost.** The growing probe asserts exactly 2*N
   token/node construction/update iterations, N dequeues, N-1 inspected edges,
   N diagnostic append calls and N appended octets. Diagnostic construction
   first computes total size and reserves once, then appends fragments without
   prefix concatenation. Queue traversal advances a cursor without prefix
   slicing. These are operation counters, not runtime allocation counters or
   a proof of linear physical copying. COW snapshots are tested separately from
   the unsnapshotted size workload. Seed allocation/copy instrumentation is not
   available in this probe; accidental internal copies and sort performance
   remain suspicions, not confirmed runtime defects. No timings were measured.
4. **Location lookup repeats source scans.** `locate` scans offset bytes on each
   request. This is a confirmed property of this helper; bulk diagnostics should
   use `line_starts` once and binary-search that table in a follow-up. It remains
   correct for arbitrary byte positions, including UTF-8 interior offsets.

## Integration and validation handoff

Add a standalone test step dependent on `component-builder`, running this driver
with the pinned Zig path. Declare `selfhost/probes/compiler/blocks.my`,
`tests.my`, this README and `selfhost/tests/run_compiler_probes.py` in the step's
repository input closure, alongside the seed pin/coordinator qualification
inputs. Preserve normal plus release fact/leak modes and require the coordinator
receipt verification. Shared build files are intentionally owned by integration.

Validation performed: component-builder build, verified seed receipt, 11 normal
and 11 release fact/leak passes, all uncached with zero failures/skips. First
build failed because the worktree lacked its sibling Guardian dependency; adding
an external sibling symlink fixed it. First test check exposed empty-list
comparison inference; the expected empty list now has an explicit int[] type.
The first fmt-check also found two new modules with formatting differences;
formatting them through the current compiler corrected both. Those failures were
fixed, not exclusions. Full gate is coordinated by the parent
in the combined integration worktree; no independent full gate or timings claimed.


## Bounded declaration primitives

The declaration pilot's [indexed.my](../../components/declaration_index/indexed.my)
replaces the quadratic probe workaround with a bounded batch index, without
qualifying native dictionaries or native sorting. `make(bytes[])` preserves
original IDs and stable duplicate ordering in `Index.order`; `lookup` returns
the first original ID or -1. `bounds` returns an interval in that permutation,
so a declaration consumer can inspect every duplicate and apply its own scope
and prior-declaration rules. Inputs are capped at 65,536 names and 1,048,576 total
name bytes; queries are capped at 1,048,576 bytes. Checked failures carry
`Problem{code:str,message:str}`. Index names and order must remain logically
immutable after construction. Retained inputs and nested index snapshots are
independent through ordinary COW mutation.

Bottom-up merge sort builds once, with at most N*ceil(log2(N)) name comparator
calls and exactly N*(ceil(log2(N))+2) ID-slot writes for nonempty input (zero for
empty input). `octets` counts paired byte positions compared, not allocator
traffic or machine instructions. Each merge comparison can be charged to the
winning name, bounding construction octets by total_name_bytes*ceil(log2(N)).
Lookup uses at most ceil(log2(N+1))+1 comparator calls; duplicate bounds use at
most twice ceil(log2(N+1)). Comparisons inspect raw unsigned bytes, including
empty names, NUL, invalid UTF-8 and prefix ties. No growing sorted insertion,
dictionary, native sort, Unicode decoding or native hashing is used.

`source(bytes)` records LF line starts once, under a 1 MiB source cap.
`locate(Source,offset)` binary-searches that table and reports one-based byte
line/column plus its comparison count. Interior UTF-8 positions, CRLF, lone CR,
no final newline, empty source and EOF have explicit tests. Offsets outside
[0,len(raw)] fail `E_OFFSET`; source construction fails `E_SOURCE_LIMIT` above
the cap. Sources must come from `source` and their line tables stay immutable;
these pure helpers do not repeatedly validate user-constructed index records.

Qualification obtains the immutable seed through the native coordinator:

```sh
scripts/build-slot.sh build zig-out/tools/selka-components --root "$PWD" --zig /home/epentland/.local/bin/zig --seed-only
scripts/build-slot.sh build "$verified_seed" test selfhost/components/declaration_index/indexed_tests.my --force --no-cache --max-steps=100000000
MYL_CORE_LEAKCHECK=1 scripts/build-slot.sh build "$verified_seed" test selfhost/components/declaration_index/indexed_tests.my --force --no-cache --max-steps=100000000 --release --verify-facts
```

The explicit step budget is necessary for the exact 65,536-name and 1 MiB
boundary tests; the default budget traps three such tests. Tests check work
bounds at 16, 128, 1024, 4096 and 65,536 names, with exact limit acceptance and
first-excess rejection. These counters and forced debug/release fact/leak tests
are algorithm and ownership evidence; physical allocation/copy cost and elapsed
performance still require isolated measurement.
