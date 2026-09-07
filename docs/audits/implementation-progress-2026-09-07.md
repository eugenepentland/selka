# Feature audit implementation progress

Authorized implementation baseline: `1db5520` (all pre-existing updates committed).
Work proceeds in independent worktrees; integration uses normal Guardian gates.
A staged implementation does not mark its larger audit item complete.

| Item | State | Evidence / remaining work |
| --- | --- | --- |
| F01 current reference | In progress | Current reference and installed feature report; acceptance running |
| F02 diagnostics | Agent implementing | Safe independent function recovery |
| F03 generic containers | Agent implementing | Generic buffers/pools and collection library |
| F04 owned borrowing | Pending | Static/runtime ownership changes required |
| F05 text/JSON | Agent implementing | Typed accessors, text helpers and writer |
| F06 standard errors | Agent implementing | Reusable result/option and error adapters |
| F07 value/control syntax | Pending | Unit/constants/loop exits then iteration/match/aliases |
| F08 bulk I/O | Queued | Copied blocks and configurable budgets |
| F09 scoped providers | Pending | Directory/endpoint grants and integration |
| F10 guest tests | First stage committed | c89ad5a: discovery/assertions/filtering/inputs; custom provider injection remains |
| F11 safety campaigns | Pending | Reproducible feature interaction campaigns |
| F12 split borrows | Pending | Checked partition static/runtime protocol |
| F13 lifetimes | Pending | Return provenance before stored views |
| F14 generic contracts | Agent implementing subset | Container ownership contracts; length parameters remain |
| F15 callbacks | Pending | Effects and runtime indirect calls |
| F16 numeric extensions | Pending | Integer extensions, then specified float behavior |
| F17 packages | Pending | Local locked roots and nominal identity |
| F18 allocator budgets | Pending | Accounting and attenuated child quotas |
| F19 agent experiments | Pending | Holes/explanations/replay/contracts and outcome measurement |
| F20 semantic reuse | Pending | Dependency-correct semantic cache and fresh equivalence |
| F21 native coverage | Pending | Current-language parity through C backend |
| F22 concurrency | Pending | Bounded isolated execution design and implementation |
| F23 compile-time source | Pending | Bounded explicit source evaluation |
| F24 maintenance trials | Pending | Repeated independent measured tasks |
