# Live results

Native B0 / verification-v1: all 17 bounded real-cohort cases completed. Later verification-v2 candidate qualification is separate. Operational waits and action totals are not isolated performance measurements.

| Case | Expected verdict | Executed | Reused |
| --- | --- | --- | --- |
| 01-cold | PASS | fixtures, format, text_scalar_unit, tooling_unit | none |
| 02-warm | PASS | none | fixtures, format, text_scalar_unit, tooling_unit |
| 03-oracle-failure | FAIL | text_scalar_unit | fixtures, format, tooling_unit |
| 04-oracle-failure-repeat | FAIL | text_scalar_unit | fixtures, format, tooling_unit |
| 05-oracle-revert | PASS | text_scalar_unit | fixtures, format, tooling_unit |
| 06-test-add-failure | FAIL | format, text_scalar_unit | fixtures, tooling_unit |
| 07-test-revert | PASS | text_scalar_unit | fixtures, format, tooling_unit |
| 08-helper-semantic-failure | FAIL | format, text_scalar_unit | fixtures, tooling_unit |
| 09-helper-revert | PASS | text_scalar_unit | fixtures, format, tooling_unit |
| 10-member-add | PASS | fixtures | format, text_scalar_unit, tooling_unit |
| 11-member-rename | PASS | fixtures | format, text_scalar_unit, tooling_unit |
| 12-member-delete-revert | PASS | none | fixtures, format, text_scalar_unit, tooling_unit |
| 13-member-cached-pass-to-failure | FAIL | fixtures | format, text_scalar_unit, tooling_unit |
| 14-member-failure-repeat | FAIL | fixtures | format, text_scalar_unit, tooling_unit |
| 15-member-revert | PASS | none | fixtures, format, text_scalar_unit, tooling_unit |
| 16-compatible-second-tree | PASS | fixtures, format, text_scalar_unit, tooling_unit | none |
| 17-second-tree-warm | PASS | none | fixtures, format, text_scalar_unit, tooling_unit |

Guest repaired source `5e6180689b5b837aa60bd5a43f60b0981c58b638`, compiler `abc4663ecc3356557a8238185005f79486343fe2ecde9258b82a266458781040`: all 20 exact-inventory/verdict cases completed. Each guest test executed with native receipt reuse unavailable (`uncacheable-toolchain`); per-test timing remains unknown. Companion components were copied from a previously qualified prefix, so complete current bootstrap provisioning is not qualified.

Native failed action keys never receive a local success receipt. Repeated oracle and fixture failures execute under the same failing key. Reverted membership source recovers the original success key. Native source reverts conservatively execute when rebuilt executable bytes change; implementation identity is preserved.

The independent native tree has identical source files, executes all four actions under its separate root context, then reuses all four in its own warm run. Shared cross-tree portability remains unavailable by design.
