# Feature audit implementation progress

Authorized baseline: `1db5520` (all pre-existing updates committed). Implementations
are developed in independent worktrees and integrated through normal Guardian gates.
This table separates delivered scope from conditional extensions and remaining work.
The original audit remains a historical baseline, not a current feature inventory.

| Item | Delivered scope | Remaining work / limits |
| --- | --- | --- |
| F01 current reference | Current reference and installed feature/compiler identity | Refresh acceptance receipts after final integration |
| F02 diagnostics | Independent ordinary/generic function errors with safe recovery | Invalid graph prerequisites remain fail-fast |
| F03 containers | Generic copyable buffers/pools; bounded map/set/queue and algorithms | Owned elements intentionally deferred |
| F04 owned borrowing | Shared/exclusive whole owners and owner-bearing record inspection | Result obligations cannot be discharged by borrowing |
| F05 text/JSON | Typed checked accessors, byte/UTF-8 helpers, bounded escaped builder | No universal Unicode string abstraction |
| F06 standard errors | Option/Result conventions, named categories, owned error context | Generic owned payload constraints remain bounded |
| F07 value/control syntax | Unit, constants, break/continue, range-for, value matches, aliases | Aliases nonparameterized; iteration ascending half-open |
| F08 bulk I/O | Copied blocks, partial-write semantics, configurable budgets and benchmark | Borrowed host ABI separate |
| F09 scoped providers | Directory/endpoint providers and CLI grants | Synchronous numeric TCP; no TLS/DNS/async |
| F10 guest tests | Discovery, structured expected values, filters/skips, locations and deterministic source-provider fixtures | Real host ABI/provider tests remain separate |
| F11 safety campaigns | Retained seeded Debug/ReleaseFast generated/mutated campaigns | Ongoing assurance; broaden host/JSON interactions |
| F12 split borrows | Checked nested/empty disjoint partitions, suspended parents, VM/native cleanup | No arbitrary overlap theorem proving |
| F13 lifetimes | Direct and selected-field immutable return provenance | Stored views/multiple-origin lifetimes remain conditional |
| F14 generic contracts | Composite fields/operations and owner-reference parameters | Explicit const N:u64 lengths implemented; no inferred/expression arguments |
| F15 callbacks | Typed noncapturing guest callbacks, owned value contracts and collection algorithms | Borrowed signatures/captures deferred |
| F16 numerics | All-width bitwise/shifts/wrapping/saturation; nominal binary64 math | Named F64 operations; no primitive decimal float syntax |
| F17 packages | Offline local locked roots, source hashes and nominal namespaces | No registry/version solver |
| F18 memory budgets | Nested byte limits; logical capacity, backing and bookkeeping reports | Child budget API is host-facing; no source quota syntax |
| F19 agent tools | Typed holes, bounded VM traces, in-memory host replay, named sampled laws | Tools implemented; separate feature-treatment benefit unmeasured; sampled laws are not proofs |
| F20 semantic reuse | Function-body reuse, fresh global checks, equivalence tests and p50/p95 benchmark | Modest synthetic improvement; generics/constants/callback schemas fall back |
| F21 native coverage | Host ABI and ordinary/typed/domain JSON through existing C backend | 22-step native acceptance passed before latest callback/length integrations; final combined run pending |
| F22 concurrency | Bounded isolated process workers, copied typed messages, cancellation/join | Host-facing API; no guest shared-memory threads |
| F23 source evaluation | Bounded scalar source functions in constants; fixed-width semantics | No aggregate generation or unrestricted macros |
| F24 maintenance trials | Prior records preserved; two new fresh-agent three-stage owner/generic sequences, 960 private observations | Tiny same-language calibration; no comparative advantage established |

Integration evidence so far: the earlier combined core run passed 896 tests;
subsequent changes have focused Debug/optimized/native and allocation-failure checks.
Every integrated commit passes Guardian's 88 checks. A later broad acceptance run
found a reserved `split` compatibility regression (fixed with contextual syntax),
obsolete native rejection expectations, and scheduler timing failures under load.
A fresh full pass is still required; historical/partial runs do not constitute it.
No comparative agent productivity advantage has been established.
