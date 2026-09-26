# Flat destruction after inert returns

This independent profile uses immutable post-inert-return compiler/binaries from
`e8696c13`. The accepted GC compiler remains `f6bea5d9`, SHA-256
`8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`.
All original compiler and executable hashes match the previous inert-return
evidence. No original source, compiler, binary or accepted baseline was changed.

Five interleaved runs on CPU 2 check every output byte and count retired user
instructions. These are depth-12 diagnostic measurements, not WP-4 acceptance.

| Backend | RC median | Accepted GC median | RC / GC |
| --- | ---: | ---: | ---: |
| QBE | 683,076,733 | 105,803,368 | 6.456096 |
| LLVM O3 / full LTO | 388,745,828 | 50,532,282 | 7.693019 |

The separate frozen counting binaries match their archived counts exactly:
669,060 heap allocations and retirements, 19 O acquires, 669,079 O releases,
33 uniqueness checks, and no H traffic, clones or refusals on either backend.
The outputs and backend/LTO manifests also match.

For attribution, the same frozen compiler builds the existing 240-repetition
source into this experiment's own cache. The accepted GC repetition binaries
remain unchanged. Every output matches 240 copies of the original output.
`perf record -e cpu_core/instructions/u -F 199` gives these approximate global
weighted self shares:

| Site | QBE | LLVM |
| --- | ---: | ---: |
| generated make | 30.79% | 45.93% |
| generated check | 7.72% | 3.57% |
| flat edge release | 5.69% | 18.56% |
| drain | 5.33% | 15.35% |
| slab allocation | 8.96% | 6.05% |
| memset | 10.89% | mostly inlined |
| frame cleanup | 5.40% | inlined into make |

There are 1,764 QBE RC, 310 QBE GC, 1,101 LLVM RC and 264 LLVM GC samples,
with no lost samples. Throttle/unthrottle records occur throughout, so these
shares locate broad costs and do not prove exact component totals. The raw
samples retain global denominators, including startup and shared-library work.
Sampling uses repetition only for attribution; the medians above execute the
unchanged original binaries.

## Bounded candidate

For a dying heap object with exactly one allocation element and an existing
admitted flat binding, avoid the public flat-release helper's repeated extent
check and outer element loop. A private helper can process the same bounded
ordered offsets and call the existing edge-release primitive. Descriptor
admission already excludes H shapes, variants and every custom hook; it is
unchanged. Objects with other counts or shapes retain their existing paths.

The optimization must clear each edge before releasing it, keep the existing
queue order and defer callbacks until all parent edges have been visited. It
must retain the O/H death test, arena/immortal checks before RC-prefix reads,
counter events and allocator retirement. It introduces no new metadata or
runtime ABI. The generic H/LOAN walker, finalizer path, and semantic-history
operations remain outside this change.

Focused tests should include a single-element non-address-ordered flat record,
aliased children, null/immortal/arena/pinned leaves, a held last owner, finalizer
reentrancy, count-zero/count-many fallback, and a million-node bounded-stack
chain. Before/after actual-backend counts and output must remain identical.
The existing two-element flat-body test remains a fallback control. Only measured
instruction improvement would justify retaining the candidate.

Evidence is in `experiments/d9-rc-flat-destruction-20260926`: original binary and
compiler identities, all ten samples per backend, manifests, counters, source,
raw perf records, weighted samples and disassembly. This first commit contains
read-only evidence and the proposal; implementation and validation are separate.
