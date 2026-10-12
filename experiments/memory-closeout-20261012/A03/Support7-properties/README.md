# Support7 generated properties

The real supported guest `test` command executed all 16 public contracts in
`tests/lang/properties.my` in all five checked ownership modes. Every mode reports
16 passed, zero failed, skipped, cached or unsupported tests, and `execute` for
every test receipt. Seed 7 and 12 successful runs per property produced 192 passed
generated cases and 25 discarded inputs per mode. Discards are recorded separately;
none is counted as a passing input. `MYL_CORE_LEAKCHECK=1` was enabled.

The exact source is SHA-256
`633f6ed79183d22d2732bbb6c6632b176ac4fde70c221122e1e7323970cfa4a6`
from frozen `bed11cf3bf3102ffec44487e431a1573fdf02ad5`; the full Support7 compiler
is SHA-256 `540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
These are uninstrumented command-contract executions, not measured RC events or
performance results. They are separate from the 81-case counted census and six-case
supplement, and do not qualify the recursive property's separately blocked module.

`results.json.gz` preserves each exact command, JSON report and stderr. The report
retains every generated-test receipt and property count. Bounded shared admission
used at most 50 completed actions or 30 admitted seconds before yielding. Raw
admission and command receipts are in `raw-json.tar.gz`; queue waiting is not guest
runtime or compiler work. This is intermediate Support7 evidence, not final C1,
default promotion or legacy retirement qualification.
