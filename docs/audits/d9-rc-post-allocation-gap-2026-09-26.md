# Instruction gap after cached production allocation

This read-only diagnosis freezes RC source at `b5ee54bc`, a real merge of
integration `dab80d845760ed3282322925203b8f0afb487d23` with allocator `16ecdc50`
and documentation. The baseline is the immutable accepted `f6bea5d9` Debug
compiler, SHA-256 `8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`.
It does not substitute the current compiler's GC mode for that accepted baseline.
No production source changes accompany this profile.

## Matched control

Both arms build the unchanged private depth-12 binary-trees source. QBE uses
its normal optimization; actual LLVM uses O3 and full LTO. Manifests verify the
backend and LTO setting. Three interleaved runs per arm on CPU 2 measure user
instructions, preserve all samples and check every output byte.

| Backend | RC median instructions | Accepted GC | RC / GC |
| --- | ---: | ---: | ---: |
| QBE | 907,370,651 | 105,803,346 | 8.576011 |
| LLVM O3 / full LTO | 465,150,743 | 50,532,263 | 9.205025 |

The independent counting binaries retain 669,060 heap allocations and
retirements, 19 O acquires, 669,079 O releases, 33 uniqueness checks and no
holds, clones or refusals. The difference from the allocator slice's final QBE
sample median is retained, not replaced or explained as a demonstrated cause.
This private diagnostic remains far outside WP-4 acceptance; the full matched
corpus and its criteria are unchanged.

## Remaining work

The sampling source repeats the same complete workload 240 times inside one
process. `perf record -e cpu_core/instructions/u -F 199` samples instructions on
CPU 2, and the entire output matches 240 copies of the original output. Global
weighted self shares are approximate:

| Site | QBE | LLVM |
| --- | ---: | ---: |
| generated `make` | 35.85% | 47.54% |
| generated `check` | 4.90% | 4.76% |
| memset | 11.13% | mostly inlined |
| frame cleanup | 8.53% | inlined into `make` |
| slab allocation | 7.77% | 7.55% |
| flat edge release | 3.79% | 17.32% |
| drain | 3.51% | 11.00% |

`check` remains the same code size in RC and accepted GC: 455 bytes on QBE and
152 on LLVM. `make` is 5,446 versus 739 bytes on QBE, and 3,741 versus 518 on
LLVM. These sizes include cold paths and are not dynamic instruction totals.

The QBE `make` PC ranges attribute 7.54% of all sampled instructions to entry,
19.46% to the nonleaf body, 8.81% to its leaf-only body and 0.04% to the shared
epilogue. Runtime helper work is separate. LLVM entry through the depth branch
accounts for about 7.63% globally. LLVM's binary-filtered samples exclude 2.36%
of the global period; the raw analysis preserves both denominators.

The fixture enters `make` 674,518 times, including 339,988 all-null leaves.
Those leaves still initialize the six-entry journal, construct and publish
two empty Options and their record, test dynamic TAKE conditions and scan the
journal on exit. The pending compact-journal experiment reduces this function
from six to four entries; its type-union proof does not eliminate the empty
branch protocol. Normal body destruction is also substantial: LLVM's flat
release and drain together account for 28.32%, despite negligible retain
traffic. Optimizing just retains cannot address this workload.

## Bounded next experiment: an inert early return

Recognize a conservative early-return prefix whose parameters are scalar and
whose returned value has only statically-null managed leaves. Keep ordinary
native stack-floor, frame-limit and step accounting. On that proved inert path,
produce the typed zero-edge result without initializing or cleaning an RC
journal. Before the ordinary path becomes effectful, run the unchanged journal
initialization, publication and cleanup protocol.

Initial admission must exclude incoming O/H/unique obligations, managed or
resource parameters, heap-backed execution frames, calls, allocations, scopes,
arena changes, semantic SHARE, hidden read captures, unboxing, borrowed-result
loans and all new history/LOAN operations. The recognized prefix must have
bounded control flow with no alternate entry or loop. Scalar evaluation and
diagnostic/step behavior must retain their original order. A null aggregate is
still returned under the canonical owned ABI; its lack of physical edges makes
cleanup inert, not optional ownership of a nonempty value.

The proof must be expressed in a separate compiler helper and reject unsupported
instructions. It must not infer emptiness merely from the result's type or from
currently clear guards. The compiler's semantic-history owner must be able to
veto the proof when an event is introduced, and sparse journal addressing must
remain authoritative on the normal path. Positive and refusal unit cases,
actual QBE/LLVM output and count checks, trap/frame-limit cases and matched
before/after medians are required before retaining the experiment.

This can remove a meaningful part of constructor work, but its profile share
does not establish a speedup or promise to close the remaining gap. A subsequent
runtime opportunity is to specialize already-validated, one-element flat object
destruction, avoiding repeated generic extent/loop/descriptor work while keeping
ordered clear-before-release, O/H death, queued-sibling order, counters and the
generic finalizer/arena fallback. That work is deferred while semantic-history
runtime changes are in progress.

## Evidence and limits

`experiments/d9-rc-post-allocation-gap-20260926` retains both sources, expected
output, compiler/binary hashes, commands, all original-run counts, weighted
samples, per-function assembly and sampling metadata. There are 2,451 QBE RC,
320 QBE GC, 1,317 LLVM RC and 273 LLVM GC samples; no lost samples are reported.
Throttle/unthrottle records remain at the host's sampling limit, so the profiles
locate broad costs rather than prove exact component totals. Repetition allows
GC collections between workloads and is used only for attribution.

The cumulative Debug install passes 12/12 build steps and Guardian's 88 checks.
No full regression gate or acceptance corpus was run for this read-only slice;
the parent coordinates those gates and the Guardian feedback log.
