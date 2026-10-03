# Closed scalar list admission, encode refusal and sorting evidence

This is a bounded P7 prototype plus the remaining P6/P8 evidence from the
2026-10-03 performance campaign. It changes no frozen benchmark port, target or
reference result. Production selection requires the separately serialized
eligible-path timing; correctness alone is not a speedup claim.

## Exact admission

The public source shape is an ordinary helper with scalar parameters/results,
one nonconstant fixed `list[int-width]` or `list[bool]` literal (one to sixteen
elements), scalar evaluations, aliases, length/index reads and scalar arithmetic.
The actual lowering is `push capacity; acquire_buffer; store builder; append...`.
The initialization must be straight-line and fill exactly the declared capacity
before any builder alias, read, drop or move. Later forward branches are allowed.

The certificate examines the complete activation, not just the literal. It
rejects every second constructor, backedge, call/callback, managed parameter or
result, publication, mutation after construction, capture, arena/scope record,
caller-owned local or by-reference local. It bounds instructions at 512 and
locals/operand slots at 32. It is cached once per emitter after ownership, COW
and stack planning finish; heap-frame relowering always refuses separately.
Unit element lists remain original: their zero-size descriptor carries a runtime
uniqueness flag. Unit scalar parameters/results are otherwise harmless.

A runtime guard then requires ordinary production RC, no stress/counting/sites,
custom allocator hook, pending failure, active walk/death drain, RC scope,
registered cleanup callback, live resource or unrelated managed object. The
ordinary CLI provider table may be present: without a callback/resource it is
not invoked on the activation's trap cleanup path. A missing or pending type
binding is examined without activation and refuses unchanged.

Both already-charged header/backing slab slots must be cached. Admission consumes
and retires real tickets, preserving allocation totals, reuse epoch (including
saturation), trim accumulation and free-list order. Header-first retirement swaps
the first two slots when header and backing share a class; the test checks that
swap and its unchanged tail. There is no refill, metadata allocation or budget
charge on the admitted path. A refusal executes the original located constructor,
COW preparation, append and failure checks.

The private value occupies the existing counted frame scratch: a 16-byte immortal
prefix, the complete 72-byte native header and the fixed scalar backing. Appends
write the original scalar width, length and generation. Ordinary aliases and
reads retain their existing bounds, overflow, instruction and frame checks. Heap
alias annotations are suppressed for the certified frame because its header and
backing may be on the native stack.

Early ticket retirement is safe only for this closed region. An executable
counterexample holds a first list alive under an exact allocation ceiling: a
second literal refuses originally but succeeds if the first tickets were returned
prematurely, because reserve can trim the newly empty slab. The certificate
therefore rejects overlapping literals and every later possible allocator,
including callbacks and managed trap cleanup. It does not admit `alloc_short`:
that unchanged target has a backedge and surrounding managed lifetimes. Its
whole-pass target remains open.

## Executable evidence

Run from the worktree, with private disk temporary directories and Zig caches,
and wrap all builds in `scripts/build-slot.sh build`:

```sh
python3 experiments/runtime-parity-local-list-20261003/run_checks.py --output PRIVATE/checks
python3 experiments/runtime-parity-local-list-20261003/run_native.py \
  --compiler ABS/zig-out/bin/mylang --qbe ABS/zig-out/bin/qbe --output PRIVATE/native
python3 experiments/runtime-parity-local-list-20261003/run_failures.py \
  --compiler ABS/zig-out/bin/mylang --baseline BASE/zig-out/bin/mylang \
  --qbe ABS/zig-out/bin/qbe --baseline-qbe BASE/zig-out/bin/qbe --output PRIVATE/failures
```

`run_checks.py` compiles the exact runtime C unit list with `-O3 -UNDEBUG
-Wall -Wextra -Werror`, including live assertions. Production and counting RC
cover warm/cold/tight-budget/same-class tickets, narrow/bool/unit boundaries,
all custom hooks, pending registration, failure/drain/arena/context refusals,
saturated accounting, trim and overlapping lifetime refusal. Counting admission
refuses and its statistics remain unchanged. Both encode witnesses pass under
production RC and GC.

The native witness relinks recorded objects with an admission counter, runs
ordinary public helpers in QBE and LLVM, and checks that each call settles exactly
two allocation/retirement tickets. Both backends execute 28 hot and two cold
calls across the five admitted type/capacity groups (30 calls total). It covers shared header/backing class, u8
maximum, i16 endpoints, booleans and unchanged unit results. The language contract
also covers aliases, negative indices, escaped/overlapping lists and COW snapshots.

`run_failures.py` has 128 byte-exact baseline/candidate comparisons across QBE and
LLVM: success, overflow, upper/lower invalid indices, instruction/depth ceilings
and seven memory ceilings. The baseline compiler is the parent's read-only
pre-P7 validation build at `6111ce9e`; every comparison uses identical guest paths
and independent caches.

All 15 compiler certificate/selected tests pass using `zig build test-units install
-Dtest-filter='local list stack' -Dcompiler-only=true -Doptimize=ReleaseFast -j2`.
The public guest is `tests/lang/local_stack_list.my`: one public contract passes
in each of ordinary RC/QBE, GC stress/QBE and LLVM release. Full Guardian checks
pass all 88 checks over the entire tree.

## P6 encode consumer feasibility

`encode-borrow-proof.c` consumes a 140,000-byte ASCII string immediately. After
warming then releasing the encoded copy and lowering the heap limit to its exact
current charge, the ordinary encode refuses while a bare borrowed UTF-8 scan
succeeds with score 16,800,000. Refusal happens at 209,424 charged bytes under RC
and 163,840 under GC. Thus nonescape alone does not permit removing encode's
allocation observation.

The successful retained-copy case uses non-ASCII UTF-8, releases/collects its
source owner, churns 100 source allocations/collections, and verifies the encoded
copy remains independent and correct. Borrowed consumption still needs a source
owner/root lifetime proof as well as compatible variable-extent allocation
tickets. This P7 guard refuses an already-live source and provides neither proof.
Encode consumption remains open; the existing public encode API is unchanged.

## P8 sorting, snapshots and retained values

[sorting-evidence.json](sorting-evidence.json) records actual shared emitted IL
for the unchanged collections benchmark: one scalar native sort call, one keyed
RC sort call, a typed `(ctx, record-address) -> i64` `row_key` ABI, a stored static
function symbol followed by an indirect typed key call, and no direct calls or
inline origins for that key. The plain record has three 8-byte fields; its ABI is
already unboxed. This is IL evidence, not a machine-code frequency attribution.

Existing native sorting already reuses eight-byte key storage for packed/counting
order, uses specialized small-span and wide-key paths, and gathers plain RC
records directly. No duplicated sort path or unmeasured threshold change was
introduced. Static callback devirtualization is a concrete follow-up; this
campaign scope does not implement it.

`stable_sorting.my` (13 tests) and `keyed_sorting.my` (18 tests) pass all 31 tests
in each of RC/QBE, GC stress/QBE and LLVM release. They include every integer
width, Unicode, NaNs/signed zeros, explicit snapshots, duplicate ordinal
stability, reverse order, exact once-per-element key evaluation, lengths through
1025, i64 extrema, wide keys and packed-boundary keys. Escaping/retained lists and
mutated snapshots use the original lifetime/COW paths.

## Eligible diagnostic for selection

`eligible-bench.my` is separate from all acceptance ports. Build its C helper and
the same guest with both the pre-P7 compiler and candidate:

```sh
cc -O2 -c experiments/runtime-parity-local-list-20261003/eligible-bench.c -o PRIVATE/clock.o
mylang build experiments/runtime-parity-local-list-20261003/eligible-bench.my \
  --mode ReleaseFast --backend qbe --qbe ABS/qbe --link PRIVATE/clock.o \
  --cache-dir PRIVATE/qbe-cache -o PRIVATE/qbe-guest
mylang build experiments/runtime-parity-local-list-20261003/eligible-bench.my \
  --mode ReleaseFast --backend llvm --llvm-opt 3 --lto --qbe ABS/qbe \
  --link PRIVATE/clock.o --cache-dir PRIVATE/llvm-cache -o PRIVATE/llvm-guest
env LOCAL_LIST_ITERATIONS=1000000 LOCAL_LIST_SEED=17 PRIVATE/qbe-guest
env LOCAL_LIST_ITERATIONS=1000000 LOCAL_LIST_SEED=17 PRIVATE/llvm-guest
```

All value guards stay enabled. The public entry accepts Host and reads scalar `iterations` (1..10,000,000)
and `seed` (1..1,000,000) through typed Host externs from the named environment
variables before starting the kernel timer. It has no retained argv/list input. Each iteration constructs the same general closed list and consumes its
aliases/indices; input varies by `i % 31`. Output is `checksum elapsed_ns`.
The authoritative independent checksum is
`N*(3*S+6) + 3*((N//31)*465 + (N%31)*(N%31-1)//2)`; at N=1,000,000, S=17 it is
101,999,913. Builds finish before timing. The harness owns randomized paired
rounds on CPU 2 under the global timing flock; this directory makes no timing
or acceptance-target claim.
