# Ownership migration and measurement closeout — 2026-10-25

Authorized follow-up to ownership-fixes-20261025. Work in the existing ownership worktree on codex/ownership-closeout; preserve original external projects and prior evidence. Compiler changes land by fast-forward after complete verification and Guardian. External migration changes are delivered as separately reviewable patches. No primary binary rebuild, push, Guardian feedback, SPEC edit or language-rule change.

## Packages

| Package | Work | Completion evidence |
| --- | --- | --- |
| C0 | Freeze/classify the 187-module stage-1 corpus: 182 intended positives, five documented negatives; correct the float-format verifier's staging context. | Source hashes, manifest, baseline diagnostics and harness provenance. |
| C1 | Restrict tuple deferral to provably independent import/declaration groups; retain shared-signature and incomplete-graph safety; explain withholding. | Red/green CLI tests, unchanged shared-consumer safety controls, successful independent tuple migration and fixed point. |
| C2 | Repair ordinary source issues on new scratch copies, apply compiler-certain edits separately, repeat for newly exposed errors. | Reviewed manual/generated patches; positive checks, exact negative refusals and preserved oracle outputs. |
| C3 | Materialize and verify the generated 64-level borrowed-default program; close the two quoted-fragment extraction gaps. | Generated-source check, migration idempotence, native expected output and explicit generator-to-source coverage. |
| C4 | Diagnose and fix multithreaded ASAN startup under the pinned toolchain without weakening resource limits. | Exact startup cause, regression tests, real two/four-thread ASAN and leak-checked task runs with data above1KiB, preserved resource-limit controls. |
| C5 | Re-run final normal/audit census and native workload/probe harnesses; execute juice and juice-runtime collector contracts; report. | 182 positive entries accepted in intended contexts, five expected negatives; no unexpected unmeasured positives/blocked certain repairs; collector-specific execution receipts with performance qualification still explicit, complete gate and concise REPORT. |

C1, C3 and C4 can be developed by disjoint Sol xhigh lanes. They and any compiler defects exposed by C2 integrate as one compiler batch after all lanes freeze, with distinct lane receipts and one complete verification before the batch fast-forwards. No intermediate snapshot is claimed independently verified. C2 source work is private scratch and its final compiler run follows integration. Complete verification and collector qualification own admission; other builds use build-slot after sourcing dev-env and canonicalizing TMPDIR.

The broader long-qualification profile has eight obligations. Selecting juice and juice-runtime executes their collector contracts; the coordinator still leaves performance repeatability qualification pending even when those contracts pass. Preserve all outstanding obligations and its partial overall status. Five negative probes retain their refusal behavior. Refused positives are followed until fixed; new semantics questions are recorded rather than silently changing language rules. Native claims require output evidence, not check success alone.

Keep decisions/status current in experiments/ownership-closeout-20261025. Logs, hashes, receipts and patches go to the sibling evidence archive; full source/build trees stay in private scratch. Preserve failed attempts and distinguish measured results from unknown coverage. Finish with REPORT.md.
