# Read-only list loop version results

Retain this bounded compiler change. On the unchanged full append workload it
removes 15.59% of QBE instructions; LLVM is unchanged. Sieve improves 9.77% QBE
and 8.37% LLVM. Exact outputs and all ownership counters match. This is an
isolated result, not Stage 4 acceptance: append remains 1.90×/2.30× accepted GC
and sieve 2.96×/3.51× GC. No default, allocator, runtime ABI or corpus change is
included.

## Identity and method

The clean control is real-merge `e130e87ff3df525da7f1e39d0dee9890da8dff91`,
including parent `bd4ea6d3`. Both compilers are immutable Debug installs:

- Before SHA256: `1ca7c30bc906e314613698d402a1fc01dfbd0340869dd0d85575385760b886e2`.
- After SHA256: `f5115e2aa7179bd468dea4fee5ebaffdab9a103572a9569bcb9adbe330ac2126`.

The exact source patch, production file hashes, compiler/binary/input hashes,
commands, sanitized environment overrides and raw receipts are archived in
`experiments/d9-rc-read-list-version-20260927/`. Each actual backend has three
interleaved before/after production runs pinned to CPU3, with separate counted
runs. LLVM is O3 with full LTO. All 72 retired-instruction samples report 100%
running; medians use their raw unscaled integer counters. Guest outputs and the
three mandated schematic SVG hashes are checked on every run.

GC references are completed rows of the original unchanged corpus experiment,
using the immutable accepted compiler; they are not fresh interleaved GC
measurements. The isolated baseline predates root's later readonly composition,
dictionary entry and named-record work. Do not describe these ratios as the
current fully joined source.

## Complete results

Instruction columns are before → after, in millions. The GC columns show
before → after ratios to the archival accepted GC median.

| Workload | Backend | Instructions M | After/before | RC/GC before → after |
| --- | --- | ---: | ---: | ---: |
| parity/suite/sieve | QBE | 2700.751540 → 2436.939610 | 0.902319 | 3.284398 → 2.963575 |
| parity/suite/sieve | LLVM | 851.745563 → 780.412168 | 0.916250 | 3.835003 → 3.513822 |
| parity/micro/alloc_churn | QBE | 7221.232323 → 7094.232529 | 0.982413 | 2.359760 → 2.318259 |
| parity/micro/alloc_churn | LLVM | 4887.233167 → 4917.233261 | 1.006138 | 2.505745 → 2.521127 |
| parity/micro/list_append_sum | QBE | 1334.581045 → 1126.581021 | 0.844146 | 2.253237 → 1.902061 |
| parity/micro/list_append_sum | LLVM | 566.708982 → 566.708896 | 1.000000 | 2.301125 → 2.301125 |
| schematic/fixture | QBE | 325.605634 → 326.950959 | 1.004132 | 17.509616 → 17.581962 |
| schematic/fixture | LLVM | 238.142682 → 237.840342 | 0.998730 | 26.287690 → 26.254316 |
| schematic/changed-net | QBE | 327.058806 → 326.604032 | 0.998610 | 17.579428 → 17.554984 |
| schematic/changed-net | LLVM | 240.247405 → 238.632354 | 0.993278 | 26.506826 → 26.328636 |
| schematic/changed-value | QBE | 326.089989 → 325.691962 | 0.998779 | 17.536482 → 17.515077 |
| schematic/changed-value | LLVM | 238.607795 → 237.838544 | 0.996776 | 26.341579 → 26.256656 |

The small alloc-churn and schematic changes are mixed controls, not claimed
improvements. The complete after/before range is preserved. Schematic has no
admitted new read-loop marker; three functions have emission changes from
attempting then refusing a copied version. No sampling percentages or presumed
address/hash effects are used to explain those small mixed differences.

## Proof and implementation

The existing range/storage loop planner already proves the read interval.
The new bounded admission supplies its missing physical lifetime condition:
private retained journals, exact live O2 or H8 role on entry, and no mutation,
callback, ownership cleanup or arena transition inside the loop. The original
journal remains linked. A hidden iterator may preserve semantic ancestor aliases
while owning its own physical H word; its own metadata is checked, never the
ancestor's. This admits an O0/H1 temporary iterable without inventing an owner.

There are at most eight checked roots, 4096 source instructions, 256 locals and
the existing 200-instruction loop body limit. Proof scratch is a fixed array;
a shared 262144-unit budget bounds detailed scans, and generated-copy scanning
has an independent 1 MiB limit. Missing metadata, place/physical aliases and
unsupported effects refuse. Only integer/Boolean/unit operands and nonboxed
lists of nonzero integer/Boolean elements are considered.

`releasesAt` deliberately checks actual scheduled emission: `edges.after` emits
only eligible straight-line `store_local` releases to PC+1 today. A second
check rejects every actual non-failure call in the generated copy, including
cleanup calls if scheduling expands. This differs from the dictionary proof's
more conservative veto of all planned edges. Existing hoist/scalar admissions
are unchanged and the new certificate supplies no dictionary authority.

The metadata guard runs before the existing ordered range/payload guards.
A cleared guard, LOAN16, unique/construction or mixed role selects the complete
old loop. No new payload-prefix read, count event, descriptor lookup, allocation,
drain, uniqueness check, frame slot or failure point is added. Zero iterations
retain the old range ordering. Step-accounted code stays unversioned; checked
accumulator overflow remains checked.

The exact QBE append machine code explains its measured gain: the successful
fold changes from 44 to 31 instructions per element while warm append remains
39. The 13 saved instructions times 16 million elements account for the
208,000,024-instruction median reduction (the residual is setup/cold execution).
Thirty-one fold instructions still exceed accepted GC's seventeen; operand
stores and checked arithmetic remain. LLVM's whole-workload median is unchanged,
so this slice does not claim the earlier hoped-for vector reduction benefit.

## Controls and limitations

- New focused tests pass 15/15, including real bytecode external backward-head
  routing: external entry goes through `@i<head>`, the fast backedge uses
  `@fi<head>` and original fallback uses `@oi<head>`. Existing scalar and managed
  version groups each pass 12/12. Mutation, callback, managed element and step
  refusal controls retain the original path.
- The actual emitted metadata guard was extracted unchanged and assembled by
  the immutable QBE tool. Twenty-two live/role combinations accept only live
  O2/H8; clear, LOAN16, mixed, unique and construction roles refuse. This is a
  guard-only QBE control, not an additional LLVM whole-program measurement.
- Four standalone fixture drivers run before/after on both actual backends:
  20 assertions per driver set, 80 total assertion executions. Eight new cases
  include empty/short/negative-index paths, fresh held iteration, nested entry,
  inherited and inner arenas, scalar widths, snapshots and unrelated owners.
  Exact counters and outputs match all eight paired runs.
- Fourteen production embedding scenarios run before/after on both backends:
  all 28 pairs match output, counters, trap code and source line. They cover
  long admitted folds, O0/H1 fresh iterable, reentrant finalizer with a queued
  sibling and metadata registration, older/current arenas, a 787680-byte heap
  frame, budget-exhausted allocation-free read, bounds and overflow fallback,
  fast-fold overflow, allocator refusal, H-limit refusal and stack-floor trap.
  The fast-fold overflow remains at line 4 in both versions.
- Six paired accounted step/frame failures match exact diagnostics and counters.
  Heap allocation/retirement and O/H balances hold throughout. No full Lox run
  was added to this bounded slice.
- Whole-tree Guardian passes all 88 checks; formatting and diff checks pass.
  Guardian initially rejected two top-level setup loops in one test; moving the
  setup into a named helper resolved it without changing production behavior.

Rejected harness probes remain in `development/`: zero execution budgets are
invalid API input; setting heap budget to current usage does not make an already
reserved read loop allocate; changing native_stack_limit after entry does not
exercise the stack-floor guard. Those were not counted as trap coverage. The
final stack-floor scenario sets the actual floor and traps. Initial benchmark
emission receipts used accounted emission and therefore are not fast-path
coverage; the separate unaccounted emission archive shows exactly one admitted
loop in each scalar benchmark. Native timing used the intended unchanged
unaccounted build path throughout.

Run `python3 experiments/d9-rc-read-list-version-20260927/verify.py --live` to
recompute every raw median, exact pair and original-file identity. Root owns the
combined full gate, forced RC sweeps and Guardian feedback; no competing full
gate was run from this worktree.
