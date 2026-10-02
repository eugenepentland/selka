# Lox stack arithmetic fusion, 2026-10-02

`stack.patch` reconstructs a source-only candidate from the unchanged
`apply-lox.sh --optimized` port. It changes only VM `numeric`, `add`, and
`negate`, plus four regression tests and their existing provider fixtures.
It uses the frozen audit compiler, without changing compiler semantics,
backend defaults, optimization flags, or source migration scripts.

The numeric handlers inspect each tagged scalar once and store the result
in the left slot. Binary numeric operations write `stack_top` once instead
of the two pops and one push, while unary negation leaves it unchanged.
This removes repeated scalar reads, discriminant checks, and helper calls.
The ordinary indexed list write still performs its COW uniqueness check;
this patch does not claim to prove general uniqueness-check elision.

## Safety and scope

- `Value` holds only nil, a boolean, a binary64 number, or an integer ObjRef.
  Accepted operands of these handlers are numbers. Their arithmetic and
  comparisons allocate nothing. Computing the result before reducing the
  root interval cannot expose an unrooted object to the Lox collector.
- Right-before-left type checks remain, with the same Lox error messages and
  `runtime_error` reset/trace behavior. The dispatch loop still publishes the
  original instruction IP before calling each handler.
- String addition keeps its existing concatenation/allocation/root path.
  IEEE division, NaN, infinity, negative zero, comparison, and negation keep
  their ordinary operations. No arithmetic, bounds, capacity, or COW check
  is disabled. Stack representation and capacity remain unchanged.
- The stack snapshot and full-capacity tests exercise the standard guarded
  list write and negative-index behavior. New VM tests cover IEEE edges,
  string allocation with Lox GC stress, and a three-frame type-error trace.
- This proof concerns VM-generated arithmetic instructions, whose operands
  are checked values on the runtime stack. It does not establish a new
  compiler proof for arbitrary mutable receiver or lifetime borrowing.

## Preliminary measurement

Three interleaved counter rounds on CPU 14 use the unchanged D9 `tree`
calibrated sizes for all 13 **VM** scripts. Every one of 156 executions
matches complete expected stdout; input and executable hashes are checked
again after the sweep. CPU 14 is a diagnostic lane, while the integration
agent owns official counters on CPU 10 and timing on CPU 2.

| Script | Candidate / baseline LLVM instructions | Candidate / baseline QBE instructions |
|---|---:|---:|
| binary_trees | 0.9696× | 0.9777× |
| closures | 0.9517× | 0.9651× |
| equality | 0.9466× | 0.9742× |
| fib | 0.8780× | 0.9150× |
| instantiation | 0.9943× | 0.9979× |
| invocation | 0.9861× | 0.9967× |
| method_call | 0.9726× | 0.9862× |
| properties | 0.9861× | 0.9975× |
| string_equality | 0.9947× | 0.9991× |
| strings | 0.9408× | 0.9644× |
| trees | 0.9625× | 0.9754× |
| zoo | 0.9443× | 0.9629× |
| zoo_batch | 0.9391× | 0.9591× |
| Geometric mean | 0.9585× | 0.9744× |

These are 4.2% fewer LLVM instructions and 2.6% fewer QBE instructions on
average. Fibonacci improves 12.2% / 8.5%. All 13 instruction ratios improve.
Wall time on this diagnostic CPU is noisy under concurrent builds and is
not an acceptance claim. No tree-engine speedup is claimed.

## Validation and identities

Both guests build with explicit RC default, retained symbols and a private
cache/output/TMPDIR. LLVM uses O3 and full LTO; QBE uses the same frozen
ReleaseFast compiler. The 104 smoke runs cover 13 scripts, both engines,
both backends, and baseline/candidate, checking exact stdout **and** equal
Lox allocations/collections/freed/live. All eight new test executions pass
(two heap and two driver tests per backend), with native `--gc-stress`; the
driver tests also enable Lox collector stress. The test runner's default
one-million instruction budget was raised to ten million for full-capacity
stack coverage; production guest checks are unchanged. An initial test
binding shadowed `run` and was renamed `observed` before successful runs.

- Base compiler source: `6df58b02554401f9d37564cceffd14277a835ae1`.
- Experiment checkout: `bbefb77f711076b036bb581b0986ac91eec05ca9` (audit docs
  added above that source).
- Frozen compiler SHA-256:
  `45d05b554849bf3c12553549d9138556ba0204f9d59ba3aaa2ecb2327eb39ac4`.
- Candidate LLVM executable:
  `1b77f1d75499b42e37589fe76391fb432f70008f299183a45086beb8c3633f22`.
- Candidate QBE executable:
  `f45aaec98c5ce3857daa4bfb85f83a28875592458aca9a8160e6c7a2ebadd071`.
- Changed VM source:
  `854030da9d4ad3b0b6833b1a651181325f55820aaa8b802a0e47b886764613c2`.

Patch replay matches all 26 `.my` modules and `driver_cases.json` exactly.
The durable receipt records exact argv, wrapper, cwd, compiler/source/guest
hashes, all test results and counter samples. Raw evidence is outside Git:
`/home/epentland/ai/canopy/evidence/lox-perf-improvements-20261002/stack/`,
sealed by `MANIFEST.sha256`. The original private build workspace remains at
`.tmp-lox-stack/` in this experiment worktree. The central integration must
validate the combined candidate before accepting it.
