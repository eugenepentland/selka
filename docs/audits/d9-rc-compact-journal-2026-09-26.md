# Compact RC journal: implementation and measured result

The bounded optimization is retained for integration. On the unchanged private
binary-trees n12 diagnostic, median retired instructions fall 2.44% on QBE and
6.38% on LLVM, with identical ownership traffic and correct full output. This
is a focused result; the parent still owns the combined full gate, native trap
replay and WP-4 corpus acceptance.

## Representation and safety boundary

The [approved design](d9-rc-compact-journal-design-2026-09-26.md) is implemented
in `qbe_rc_journal.zig`. An emission-only wrapper pairs the semantic local plan
with a prefix-count layout. `rc_plan.Plan` stays runtime-independent, and emitter
State still has seven fields. There is no runtime ABI or Guardian baseline
change.

Logical order remains locals, operand positions, pending result, internal
construction. A local is omitted only when its finalized shape has neither
counted edges nor unique cleanup. Operand eligibility unions **all reachable
stack types** at that position. This retains O and H obligations, borrowed
managed parameters and aliases, read loans, unique resources, and positions
reused for different managed roles. Pending and internal entries always remain.
Payload buffers are unchanged. This does not make path-sensitive claims about
currently null managed fields or an empty guard.

The prefix count maps every retained logical index to its physical index,
preserving reverse cleanup order. Guard/metadata requests for an omitted slot
fail internally; they cannot alias its next neighbor. Explicit drop and
clear-already-empty operations are no-ops for omitted plain slots. Plain record
updates still stage physical bits through the retained pending slot without
asking for an input ownership guard.

All raw entry/guard arithmetic now lives in `qbe_rc_frame`. Held view/iterator
flags and internal construction flags use its shared `entryField` helper.
Dynamic by-reference local addresses and internal construction addresses remain
dynamic. Stable operand/work entries preserve descriptor/role-before-guard
publication. Arena cleanup translates the logical local watermark to the prefix
count; source local validation and zeroing keep their original indices. Both
scratch entries remain after the translated local prefix.

## Focused validation

* Compact-layout units: 13/13, including two named mapping tests. Omitted guard
  requests fail; plain gaps, unique cleanup, exact watermarks and both retained
  scratch entries are asserted.
* RC admission units: 14/14. Debug install succeeds; Guardian passes all 88
  checks without a waiver. The first install caught a duplicate primary spec
  tag in the new guest fixture; it was corrected to `spec-case` before validation.
* Twenty language groups cover 125 assertions per actual backend with forced
  execution. They include constructors, mixed plain/managed records, recursion,
  nested arenas and escape, views and iterator identity, resource capabilities,
  callback captures, read loans, mutable parameters, and physical COW hoists.
* Six standalone programs per backend check successful mixed journal/arena/H
  use, successful file cleanup, and `R_FILE`, `R_LIST_BOUNDS`,
  `R_LIST_ITERATION_MUTATION`, and recursive `R_ASSERT` unwind. All twelve have
  allocation/retirement balance, `O release = allocation + O acquire`, matching
  H acquisition/release, and no counter saturation.
* Zig and guest formatting and `git diff --check` pass. Actual LLVM commands
  use `--release` or explicit LLVM backend flags; none contains an overriding
  `--qbe` option.

## Frozen before/after measurement

The before compiler was built from `b7e33441663d7f6eb23fc9e67b721677214a2c44`.
Its metadata-only replacement is `c31666341191f490caba5fb9b172320d0aea5509`;
both have source tree `b73534705ca67916633ae27ed205d3be4797c3e1`. Full compiler
and binary SHA-256 hashes, complete candidate source, commands and raw samples
are in the [evidence archive](../../experiments/d9-rc-compact-journal-20260926/README.md).
Both compilers are Debug builds. Both guest backends use ReleaseFast; LLVM uses
optimization level 3 and LTO. Sampling alternates before/after order on CPU 3.

| Backend | Before median instructions | After median instructions | After / before |
| --- | ---: | ---: | ---: |
| QBE | 1,076,836,926 | 1,050,518,876 | 0.975560 |
| LLVM | 628,481,547 | 588,393,429 | 0.936214 |

All eight before/after, backend and counted/uncounted binaries match the full
independently calculated output. All four counted runs have exactly 669,060
allocations and retirements, 19 O acquisitions, 669,079 O releases, zero H
traffic and clones, and 33 uniqueness checks. The optimization changes only
generated journal bookkeeping.

Recursive `make` emits four runtime entries instead of six. Its entry table
shrinks from 192 to 128 bytes and guards from 48 to 32 bytes, saving 80 bytes
per frame. The manifest's implementation hash changes; the canonical function
symbol and source metadata remain stable. Payload buffers and scratch storage
are unchanged. Neither this measurement nor the focused suite substitutes for
the combined gate or full-corpus performance check.
