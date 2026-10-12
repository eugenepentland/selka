# A07 ownership, cleanup, and ABI audit

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Worker branch: `codex/memory-closeout-20261012-A07`.

## Integrated-ready commits

- `9459f4049c93dfe1e2f13b7928ec89306e0b14f2`: admit existing scalar-only
  `myl_core_task_item` diagnostic helper. No managed storage is captured,
  returned, retained, or consumed. Task execution saves/restores TLS context.
  Focused test passed (1/1), Guardian precommit passed 88 checks.

## Reviews

A01 chunked map: static ownership/ABI review approved, pending native stress and
ThreadSanitizer evidence. Input list borrows remain live through synchronous join.
Capture payload is a leaf and deliberately does not destroy its source pointer.
Each completed chunk owns a list; payload bytes transfer to final output before
freeing its shell. Untaken task results remain group-owned. Contiguous ranges and
output order agree; empty input avoids division by zero, single worker uses one
chunk, multiple workers use min(length, 4 * workers). Chunk-list element storage
still scales with input size and must be reported separately from wrapper counts.

A02 allocation bounds: static review approved, pending executable tests. Guard
header/alignment addition and capacity multiplication before allocation, signed
capacity doubling before growth, and buffer/list realloc byte sizes. Existing
fatal-OOM policy is unchanged. No deep copies or shrink-on-return introduced.

Test runtime: `read_text` and `read_bytes` allocate independent bounded blocks;
`write_text` only reads its argument. `test_open` synchronously consumes borrowed
path octets in fopen and makes its own native strdup for later output use.
Registration retains static function pointers only. Test execution forks before
running callbacks and quiesces tasks before cleanup/leak checking.

## Narrow fixes prepared for integration

The combined `test-core -Dtest-filter='zero RC'` run passed 72/73. The sole failure
was an unreachable statement in the newly added propagation fixture, removed;
its focused rerun passed 1/1. Production compilation and the other 72 checks
passed, including the Result entry five-mode matrix and dictionary snapshots.
Raw evidence is in `narrow-fixes/`. Full final verification remains coordinator-owned.

The fixes now include direct Result entry direct destruction, safe immediate
dictionary snapshots, exact test transport contracts, recursively locating a
named provider through `try` for scoped file acquisition, and the generic overlap
diagnostic wording `a value` (previously `a list`).

## Original defects

- Direct Core-IR Result entry emits an unconditional RC cleanup for text errors.
  Ordinary source Result main currently passes through an integer-returning
  synthesized wrapper; it is not a demonstrated C0 command blocker. Regression
  now covers to cover both source and direct IR entry paths in five modes.
- Immediate dictionary projection materialization currently expands through a
  retained view record and implicit borrowed-child duplication. A05 reproducer
  `list(values.keys())` refuses under source ownership checking. Reservation for
  `src/dictionary_views.zig` granted; no unsupported escape waiver is proposed.
- Audited test helper contracts requested by A10 are pending registry commit.

## Evidence

Raw test and hook output is currently under `.tmp/memory-closeout/A07/`; relevant
logs and final source/compiler hashes will be copied here after final checks.
No legacy RC retirement is claimed. Default promotion and retirement require
coordinator-approved qualification stages.
