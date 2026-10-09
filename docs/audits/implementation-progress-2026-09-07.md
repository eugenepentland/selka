# Feature audit implementation progress

Authorized baseline: `1db5520` (all pre-existing updates committed). Implementations
are developed in independent worktrees and integrated through normal Guardian gates.
This table separates delivered scope from conditional extensions and remaining work.
The original audit remains a historical baseline, not a current feature inventory.
This table records the audit-stage checkpoint. Subsequent [standard library work](../standard-library.md)
adds owned collections, text/data utilities, buffered I/O, directory inspection and time/random APIs.

| Item | Delivered scope | Remaining work / limits |
| --- | --- | --- |
| F01 current reference | Current reference and installed feature/compiler identity | Pinned current examples/rejections and acceptance receipts retained |
| F02 diagnostics | Independent ordinary/generic function errors with safe recovery | Invalid graph prerequisites remain fail-fast |
| F03 containers | Generic copyable buffers/pools; bounded map/set/queue and algorithms | Owned elements intentionally deferred |
| F04 owned borrowing | Shared/exclusive whole owners and owner-bearing record inspection | Result obligations cannot be discharged by borrowing |
| F05 text/JSON | Typed checked accessors, byte/UTF-8 helpers, bounded escaped builder | No universal Unicode string abstraction |
| F06 standard errors | Option/Result conventions, named categories, owned error context | Generic owned payload constraints remain bounded |
| F07 value/control syntax | Unit, constants, break/continue, range-for, value matches, aliases | Aliases nonparameterized; iteration ascending half-open |
| F08 bulk I/O | Copied blocks, partial-write semantics, configurable budgets and benchmark | Borrowed host ABI separate |
| F09 scoped providers | Directory/endpoint providers and CLI grants | Synchronous numeric TCP; no TLS/DNS/async |
| F10 guest tests | Discovery, structured expected values, filters/skips, locations and deterministic source-provider fixtures | Real host ABI/provider tests remain separate |
| F11 safety campaigns | Retained seeded Debug/ReleaseFast generated/mutated campaigns | Expanded Debug/ReleaseFast JSON/host/split campaigns pass; coverage-guided fuzzing remains ongoing assurance |
| F12 split borrows | Checked nested/empty disjoint partitions, suspended parents, VM/native cleanup | No arbitrary overlap theorem proving |
| F13 lifetimes | Direct and selected-field immutable return provenance | Stored views/multiple-origin lifetimes remain conditional |
| F14 generic contracts | Composite fields/operations and owner-reference parameters | Explicit const N:u64 lengths implemented; no inferred/expression arguments |
| F15 callbacks | Typed noncapturing guest callbacks, owned value contracts and collection algorithms | Borrowed signatures/captures deferred |
| F16 numerics | All-width bitwise/shifts/wrapping/saturation; nominal binary64 math | Named F64 operations; no primitive decimal float syntax |
| F17 packages | Offline local locked roots, source hashes and nominal namespaces | No registry/version solver |
| F18 memory budgets | Nested byte limits; logical capacity, backing and bookkeeping reports | Child budget API is host-facing; no source quota syntax |
| F19 agent tools | Typed holes, bounded VM traces, in-memory host replay, named sampled laws | Tools implemented; separate feature-treatment benefit unmeasured; sampled laws are not proofs |
| F20 semantic reuse | Function-body reuse, fresh global checks, equivalence tests and p50/p95 benchmark | Modest synthetic improvement; generics/constants/callback schemas fall back |
| F21 native coverage | Host ABI and ordinary/typed/domain JSON through existing C backend | Full native steps passed with callbacks/lengths in combined run |
| F22 concurrency | Bounded isolated process workers, copied typed messages, cancellation/join | Host-facing API; no guest shared-memory threads |
| F23 source evaluation | Bounded scalar source functions in constants; fixed-width semantics | No aggregate generation or unrestricted macros |
| F24 maintenance trials | Prior records preserved; two new fresh-agent three-stage owner/generic sequences, 960 private observations | Tiny same-language calibration; no comparative advantage established |

Validation is retained in [the acceptance receipt](../../experiments/validation/audit-20260907/receipt.json).
The combined VM/native run passed every area except one obsolete diagnostic
expectation after function values became supported. Commit `3f3b773` updates
that expectation; the entire current core suite then passed all 938 tests,
including an additional malformed-callback regression. The other 97 Zig CLI/host
tests and every Python/native acceptance step passed in the combined run. A
separate ReleaseFast callback run passed 22 tests. This is verification across
those recorded runs, not a claim that the earlier combined command exited zero.
All normal Guardian gates passed 88 checks.

The earlier reserved `split` compatibility regression was fixed with contextual
syntax; scheduler lease contention was fixed and all 45 verification tests pass.
Debug and ReleaseFast campaigns each retain 480 source/mutation cases and 60
host/JSON cleanup cases. The new [maintenance trial](../experiments/direct-agent-maintenance-20260907.md)
retains two fresh participants, six sequential stages and 960 passing private
observations, plus independent source review. No comparative agent productivity
advantage has been established; feature-specific treatments remain future experiments.
