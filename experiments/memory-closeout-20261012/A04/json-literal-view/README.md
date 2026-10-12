# Borrowed JSON literal comparison

The library now compares a literal's byte range inside a private read-only helper
that returns a Boolean before `read_literal` updates its scanner. Ordinary
parameters already borrow under checked ownership. This keeps the comparison's
lifetime local and lets the existing read-only slice optimization remove its
temporary. No ownership syntax, helper whitelist or general liveness analysis is
added. Scanner bounds checks, malformed/truncated errors and independent Json
result copying remain unchanged.

The Support7 compiler is fixed at source
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`, SHA256
`540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
`readonly-helper-01/results.json` records twelve successful native lanes: original
and changed library sources, each in all five checked modes plus ordinary release.
The full existing JSON fixture and every assertion remain unchanged except its
local module import alias. Both source versions are archived with their hashes.
All checked runs are RC0/live0 with clean LLVM/symbol audits. This is a controlled
source refactor on one compiler, not a compiler-only performance claim.

| Mode | Allocations before → after | Cumulative allocated bytes before → after |
| --- | --- | --- |
| Release / verified release / optimized debug | 541 → 538 | 38,912 → 38,720 |
| Release without facts | 542 → 539 | 39,008 → 38,816 |
| Unoptimized debug | 542 → 542 | 39,008 → 39,008 |
| Ordinary release control | 446 → 446 | 32,032 → 32,032 |

Managed peak and exit-live bytes are unchanged in every pair. The optimized
checked `read_literal` and new helper both allocate zero. The source-matched C0
release fixture historically used 538 allocations; this change recovers the
three temporary allocations introduced by the conservative slice-lifetime safety
repair. That safety repair remains unchanged. No RSS or uninstrumented runtime
claim follows from these counters. `comparison.json` keeps metrics separate.

An earlier explicit `.borrow(...) != word` experiment is retained in
`source-checks.json`. Checked source compilation correctly rejects it with
`E_ZERO_RC_VIEW_UNSUPPORTED`, since view binary comparisons are outside the current
API. Its ordinary source-check success is not a native qualification claim. The
rejected patch is evidence only; production uses the ordinary read-only helper.
`source-probe-used.txt` preserves the exact initial probe adapter, whose later
Python import cleanup did not change any experimental source.

The coordinator authorized a separate worker-owned checkout at
`mylang-memory-20261012-A04-json`, based on Support7, to commit this change without
modifying the ongoing A04 common-artifact inputs. The next integrated compiler
must consume the new library source and rerun affected qualification; Support7's
original installed library and reports remain immutable.

The replay adapter now takes explicit compiler path/hash, source commit and a new
`--phase`, and reads the archived original/helper sources. It cannot accidentally
turn the original control into the adopted implementation. The exact adapter used
for the twelve measured lanes is preserved in `qualify-helper-used.txt`; its hash
is the one recorded in those results. This adapter-only portability change does
not relabel or rerun the existing evidence.
