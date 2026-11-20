# Stage 4 plain-result read-only helper composition

The compiler now proves a scalar read-only activation across direct helpers
which independently satisfy the same closed grammar and return plain values.
The schematic uses 8–10% fewer instructions; unchanged full N10 Lox uses 2.2%
fewer on QBE and 1.2% fewer on LLVM. These focused results still fail Stage 4's
instruction requirements. They do not include the separately developed named
record, dictionary-key or scalar-readiness changes.

## Proof and emission

`rc_readonly_calls` composes the existing activation grammar with a bounded,
non-evicting dependency proof: depth16, sixteen completed functions and65536
instruction visits. Plain helper calls must independently pass the complete
body proof. Managed or unique returns, allocation, mutation, unknown calls,
host/C/indirect authority, mutual cycles and exhausted bounds refuse the
optional optimization. Existing self recursion remains supported.

Managed returns deliberately remain outside this change. Raw read-only
emission disables its ownership journal; accepting a managed helper without
explicit borrowed-alternate routing could otherwise create an unjournaled
owning result. Core reviewed the exact plain-result boundary and cache identity
before measurement. No runtime, return ABI or general borrow inference changes.

The supplementary RC fragment key includes proof version, ABI, root body and
layouts, every plain dependency identity and success/refusal. A helper edit or
loss of admission therefore invalidates an unchanged scalar caller. GC keeps
its original fragment key. Both measured GC control executables are identical
before and after the compiler change.

Actual emission changes only `layout::nearest` among129 schematic functions.
Its three loan sites, one retain site and RC frame disappear; `pinGroup` was
already raw. `sexpr::form` and managed-return `sexpr::at` retain their existing
behavior. Lox changes only `table::get` and `resolver::resolve_local` among405
functions, which justified the full N10 control below.

## Matched evidence

Before is frozen ownership source `e5d47d20`, whose compiler is byte-identical
to the corrected full-gated `c90c84be` compiler:
`1f3bca2c62180a58fcc54782f9414a2b272e8447f996096a6883dc330774e3c7`.
The candidate starts from evidence head `f9a895c8` plus this change:
`9e1e8c27db108a23c144a88e913f76f381831609ac7f3bee9e5d5d6e9267b1a5`.
Both compilers are Debug. The
[archive](../../experiments/d9-rc-readonly-calls-20260927/README.md) records the
exact source delta, newly added files, compiler/guest hashes, command manifests,
raw counters and output checks. All forty-eight raw instruction observations
report100% event running on CPU2. LLVM is actual O3/full LTO. GC reference
medians are archived accepted observations, not new interleaved measurements.

| Workload | Backend | Before instructions | After instructions | After/before | After/GC |
| --- | --- | ---: | ---: | ---: | ---: |
| schematic/fixture | QBE |328,014,021|298,438,470|0.909834|16.049040×|
| schematic/fixture | LLVM |242,130,494|217,559,020|0.898520|24.016779×|
| schematic/changed-net | QBE |325,795,283|297,105,467|0.911939|15.969871×|
| schematic/changed-net | LLVM |237,660,465|217,567,245|0.915454|24.005931×|
| schematic/changed-value | QBE |325,617,866|296,941,064|0.911931|15.969203×|
| schematic/changed-value | LLVM |237,573,379|219,537,557|0.924083|24.233169×|
| Lox VM binary_trees N10 | QBE |202,214,393,052|197,730,837,111|0.977828|27.298727×|
| Lox VM binary_trees N10 | LLVM |153,840,104,486|151,982,863,531|0.987927|44.269136×|

All full SVG and Lox outputs match. Sixteen separate counted workload runs
balance ownership, holds and allocations. On the schematic fixture, O
acquisitions fall152,897→125,599 and H pairs335,630→294,183; all156 allocations
and the single clone remain. Full N10 removes5,581,203 H pairs, retaining
81,463,495 O acquisitions,4,350,608 allocations and1,095,889 clones. Both
backends have identical counts. No RSS or full-corpus acceptance claim is made.

## Correctness and limitations

The focused suite passes22 tests, including existing readonly-body refusals,
transitive cache identity, managed-return/allocation refusal, mutual recursion,
depth/memo boundaries and actual raw caller/callee emission with checked bounds.
Whole-tree Guardian passes88 checks without a waiver.

Six guest assertions run under every before/after × GC-stress/RC × QBE/LLVM
configuration:48 assertion executions. They cover caller snapshots, subsequent
mutation, empty/repeated input, inherited arenas, self recursion, managed-result
fallback and a mutating helper. Sixteen paired Debug executions preserve exact
bounds, arithmetic, step and frame diagnostics and balance cleanup on each trap.
Warm and cold caches agree after two transitive helper edits, including a change
which removes admission. Four final native cache controls return the expected
value with balanced counters on both backends.

The initial trap harness's unsupported integer entry parameter and subsequent
ReleaseFast finite-step refusal are preserved separately from the final passing
Debug controls. No production behavior was changed to accommodate those probes.
The independent archive verifier recomputes medians from raw perf output and
checks the paired evidence; `--live` also checks immutable local identities.

The combined integration gate is separate. Runtime default, accepted corpus,
thresholds, arenas and `main` remain unchanged. Stage 4 still requires the full
unchanged43-program comparison and every performance threshold to pass.
