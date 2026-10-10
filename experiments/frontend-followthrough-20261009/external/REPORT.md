# External migration and qualification

This package owns new source snapshots and evidence only. Frozen sources, answers, pins, old qualification packages, and protected application branches were read without writes. Sources are archived from Lox `f44302d877dfc8a01b64673e70c44b9e0c49f063` and EDA `7e938b65a880339f0aa0d58f5805cd2cd2bbfe1b`. The per-file snapshot manifests and migration patches/maps bind old and migrated sources.

Initial candidate compiler `af66ae2dba17da5a92906f78d4d377fb0f3de9d764e9e1e7e194940db23715b7` is retained read-only in `artifacts/mylang`; `0bbfeb740:experiments/frontend-followthrough-20261009/external/candidate-source.json` records its production source files. The source-frozen candidate is `b18488cc1cf9573288c43b642df3b828f6903784bb5d3f4b2a094ca2db707472`, retained in `artifacts/mylang-final` and bound by `0bbfeb740:experiments/frontend-followthrough-20261009/external/final-candidate-source.json` and post-run `0bbfeb740:experiments/frontend-followthrough-20261009/external/final-guards.json`.

## Final successor qualification

The final successor compiler is `5e072ee17b825cfbd40ed5533c3bce9f166ce4ae576395020cd5e435cc45ed11`. Its bound production manifest differs from the previous qualified compiler only in `src/arena_fix.zig` and `src/retired_features_test.zig`; 173 application/provider source files contain no retired arena blocks. All 450 saved mode commands rerun successfully, with the six EDA property commands explicitly retaining the frozen seed. Both full report/stderr audits have zero unreviewed differences. Production files, migrated corpora, and compiler bytes remain unchanged after the reruns.

Native proof transfers are evidence based: the successful complete Lox main IR is byte identical; the rebuilt EDA native executable is byte identical. The original 974 Lox and 34 EDA frozen native cases therefore remain covered. EDA dump-ir cannot resolve configured src imports in either compiler, so equal failed dump output is explicitly excluded from the proof. `successor-qualification.json` is the current final verdict.

## Source-frozen results

Lox: 974 native cases match frozen exit/stdout/stderr exactly; 84 saved mode commands preserve all 65 guest and 13 configured tests at debug/release/verify. Complete report and stderr differences are fully audited in `0bbfeb740:experiments/frontend-followthrough-20261009/external/lox-modes-final-difference-audit.json`; source-root and reviewed configured fingerprint changes are explicit.

EDA: 34 native golden cases match frozen exit/stdout/stderr and emitted output files exactly; all 366 saved mode commands pass, including 310 tests in each directory mode. Default property seeds differ because `src.` changes qualified test identity. The six default-seed commands containing the parser property remain supplementary. Their replacements in `eda-property-seed-final` pass with complete frozen property reports and add only the explicit frozen seed `8679566789041942096`. `0bbfeb740:experiments/frontend-followthrough-20261009/external/eda-final-combined-audit.json` closes every complete-report and stderr difference across all 366 commands after the six replacements. Both default seed values and exact command exception are retained in `0bbfeb740:experiments/frontend-followthrough-20261009/external/eda-property-seed-mapping.json`.

## Recorded initial results

* Lox release native: all 974 frozen case/mode identities pass; no exit/stdout/stderr mismatch (`0bbfeb740:experiments/frontend-followthrough-20261009/external/lox-native/answers.json`).
* Lox guest modes: 84 exact saved commands pass functional membership: 26 source files × debug/release/verify, 13 configured cases × these modes, and three complete directory runs. Each mode contains the same 65 guest test identities and statuses. `lox-modes/summary.json` has complete receipts and source guards.
* Lox raw report audit: only source-root relocation and configured contract/provider/settings fingerprints differ; every difference is retained explicitly in `0bbfeb740:experiments/frontend-followthrough-20261009/external/lox-mode-difference-audit.json`. Relocated stderr text otherwise matches byte for byte. All 13 configured cases retain their names, provider filenames, grants, and every non-source configuration field (`0bbfeb740:experiments/frontend-followthrough-20261009/external/configured-contract-audit.json`). Migrated provider source hashes are audited per case. Exact configured fingerprint preimage equivalence is not asserted.
* EDA first native: all 34 cases failed because migration of legacy `int(s)`/`float(s)` to builtin names collided with existing wrappers and introduced recursion. The failed run is retained in `eda-native`; this is not a passing qualification.
* EDA repair native: after audited wrapper renames, all 34 unchanged goldens pass; no exit/stdout/stderr/output-file mismatch (`0bbfeb740:experiments/frontend-followthrough-20261009/external/eda-native-fixed/answers.json`).
* EDA first mode run: all 366 saved commands executed, with failures caused by the recursion above. The compiler production-source guard correctly rejected source changes during this run, so it has no passing qualification summary. Raw receipts and `0bbfeb740:experiments/frontend-followthrough-20261009/external/eda-initial-mode-failures.json` preserve the failures. Final candidate modes must rerun.

## Migration review

`mylang fix` performs the supported syntax migration. Explicit audited source repairs address: independent repeated branch local names; fallible calls nested in enclosing expressions (hoisted to statement declarations); malformed overlapping enum/type and nested comprehension edits found during migration; path-derived EDA imports under `mylang.json` (`src.<module>` with aliases preserving local bindings); the reserved builtin `Unit` name, changing EDA nominal records to `SchematicUnit` while retaining builtin `Result[Unit,E]`; numeric wrappers renamed to `parse_integer`/`parse_real`, with only matching imported references changed and builtin byte parsing methods preserved. Reduced repros are in `0bbfeb740:experiments/frontend-followthrough-20261009/external/blockers`, and parent agents repaired compiler migration defects independently.

EDA's frozen test identities map explicitly from `<module>::<test>` to `src.<module>::<test>` because the existing project configuration is above `src`. The runner preserves every frozen command's mode, force, timeout, budget, leak-check, and test case identity. It records raw diagnostics and full reports rather than treating diagnostics/rendering changes as equivalence.

## Artifact scope

Commit source-only `*-migration.patch`, `*-migration-map.json`, audits, receipts, scripts, and report. Do not commit `artifacts/`, `sources/`, `native-cache/`, mode `cache/` trees, executables, or other build products. The archived EDA tree includes unchanged golden inputs so native output checks require no copies from mutable application branches.

## Archived full evidence

Full captures and the original version of this report remain in commit `0bbfeb740`,
reachable from `main` and `codex/frontend-followthrough-20261009`.
Retrieve any archived path with `git show 0bbfeb740:PATH` (paths are repository-relative).
