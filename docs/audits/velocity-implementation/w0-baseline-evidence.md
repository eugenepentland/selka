# W0 baseline verification evidence

Prepared 2026-09-15 by the W0 verification agent on branch `codex/velocity-w0-verify`.

This is evidence only. No compiler source, test, `SPEC.md`, `src/features.json`, `build.zig`, or frozen shared-contract file was changed. The only non-evidence edit is the conservative scope labeling in [incremental-status-2026-09-15.md](../incremental-status-2026-09-15.md).

## 1. Base and scope

| Item | Value |
| --- | --- |
| Branch | `codex/velocity-w0-verify` |
| Worktree HEAD / base commit | `66e96cebd4f6894757d13d79ea23227804e5b4de` (`66e96ce`) |
| Ledger-selected compiler baseline | `9ce142e98cb22e684622ed1d5678071d6944206e` (audit HEAD plus named-constraint fixes; `66e96ce` adds the W0 ledger/contracts) |
| Auditor source SHA (historical probe record) | `a9e29d4845ab2f8a700eeb238ed03023d2ac701e` |

## 2. Toolchain, compiler and QBE identities

| Item | Value |
| --- | --- |
| Zig version | `0.17.0-dev.1683+5ceec001b` |
| Zig on PATH | `/home/epentland/.local/bin/zig` |
| Pinned Zig | `/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig` (`0.17.0-dev.1683+5ceec001b`) |
| `zig-out/bin/mylang` sha256 | `289f0d40687db20e3902079e4b26fbbb4d3dc8feb201ffb6a2d0d19c5e14ac39` |
| Compiler identity (`mylang --features`) | `fff3e012da1d2ae9e5a60c916245f2479ace96d82d4ba743c21a3733f5b965f4` |
| Historical audit compiler identity | `c54d594e5ad606891c187bfaade3a9bd86270e4c62cc367361b1b74cf2d76dbf` |
| `zig-out/bin/qbe` sha256 | `d487fef310973586a38c35fcbd24d3c4a1e0787b702cdcdf8b9cc3f718da4f9b` |
| QBE vendored version (`.qbeversion`) | `1.3` |
| `vendor/qbe` git identity | not a submodule; `git -C vendor/qbe rev-parse HEAD` resolves to the enclosing repo HEAD `66e96ce` |
| `vendor/qbe` content tree sha256 | `1129930aab91f9e9282189e1d517d6483b92669c02e773b2e765a0634717bd04` |
| OS / arch | Ubuntu 26.04 LTS, `Linux 7.0.0-31-generic`, `x86_64` |
| libc | ldd (Ubuntu GLIBC 2.43-2ubuntu2.4) 2.43 |
| Feature manifest sha256 (canonical JSON) | `0f5a0813e7af41312477d654eaaa5f9300ee4245e1199ed9a2b0327ceff1c34a` |

The rebuilt baseline `compiler_sha256` `fff3e012...` is exactly the identity recorded in the frozen W0 ledger (`docs/audits/velocity-implementation/README.md`), confirming this worktree reproduces the intended baseline compiler. It differs from the historical audit binary `c54d594e...`; the feature manifest is identical and that difference is expected across builds.

## 3. Baseline acceptance gates

All commands were run from the worktree with the pinned Zig; raw logs were captured under `/tmp/w0-evidence/gates/` (ephemeral). No pass is claimed that was not executed.

| Command | Exit | Result | Measured counts | Notes |
| --- | ---: | --- | --- | --- |
| `zig build` | 0 | PASS | no tests; produced zig-out/bin/{mylang,qbe,board-trial,mylang-io,schematic-svg} | Guardian ran diff-scoped vs a9e29d4: 88/88 checks passed. Report-only findings: 4 file-size, 88 line-length. Not a whole-tree Guardian run. |
| `zig build test --summary all` | 1 | FAIL | Build Summary: 37/39 steps succeeded (1 failed); 1054/1054 Zig tests passed (11+7+13+80+943). | Failed step is `run exe mylang failure`: `./zig-out/bin/mylang doctest .` exits 1 because docs/audits/development-velocity-proposals-2026-09-15.md:141 has a fenced block tagged `text` that looks like guest source (1 mis-tagged block). All Zig test roots passed. |
| `zig build fmt-check` | 0 | PASS | formatting check only (no test count) | Clean exit, no output. |
| `zig build test-doc-coverage` | 0 | PASS | 110 documented features (80 language, 30 tooling) across 41 pages; 10 standard modules and 140 exports; 0 failures. |  |
| `zig build test-docs` | 1 | FAIL | 205 files scanned, 409 blocks found, 112 run, 21 checked, 10 skipped, 1 mis-tagged, 0 failed. | The single mis-tagged block is docs/audits/development-velocity-proposals-2026-09-15.md:141 (historical audit file, left unchanged). The gate treats a mis-tag as failure. |
| `zig build test-qbe` | 0 | PASS | 104/104 tests passed: test-c-ffi 23, test-native-tests 43, test-qbe-build 37, test-golden 1. Golden parity checked 231 (source 175, fixtures 56), skipped 373, mismatches 0. | test-native-tests ran here as a dependency and passed 43/43. |
| `zig build test-native-tests` | 0 | PASS | 0 tests re-executed in this invocation (build cache satisfied by the immediately preceding `zig build test-qbe`); that run selected and passed 43/43 native-test tests. | The command wrote no per-test output because the run step was cached. Counts above are the underlying step's counts from the preceding invocation. |
| `zig build test -Doptimize=ReleaseFast --summary all` | 1 | FAIL | Build Summary: 36/39 steps succeeded (2 failed); 1052/1054 tests passed (2 failed). | Two deterministic ReleaseFast unit failures: (1) persist_codec.test.codec rejects truncated and malformed bytes: expected error.InvalidEncoding, found .{ .b = void }; (2) incremental_test.test.materialize, dupModule, dupDeclaration, dupNominal, dupSpecialization and dupFragment release partial copies: expected 41, found 1 (checkAllAllocationFailures). The doctest step also exited 1 on the same mis-tagged block, and one ReleaseFast test compilation reported peak 2.31 GB vs the declared 2.15 GB bound (`compile test fast native failure`). |
| `zig build test-units -Doptimize=ReleaseFast --summary all (supplementary)` | 1 | FAIL (confirmatory) | Build Summary: 20/22 steps succeeded (1 failed); 941/943 tests passed (2 failed). | Targeted re-run confirms the two ReleaseFast unit failures are deterministic and not concurrency artifacts. |

ReleaseFast was run (yes). The Debug `test` and `test-docs` failures share one cause: a historical audit document (not editable under this task) has one mis-tagged fenced block. The two ReleaseFast unit failures are separate and reproducible.

The evidence commit hook additionally ran a **whole-tree** Guardian gate on this documentation change: `run-all: whole-tree run`, 88/88 checks passed, with report-only 4 file-size, 12 function-length and 2937 line-length findings. The `zig build` runs listed above remained diff-scoped.

## 4. Probe methodology

All 42 probes were read from the frozen `development-velocity-proposals-2026-09-15-probes.json`. Fixture sources were written exactly as recorded (the historical fixture tree at `/tmp/mylang-proposals-audit-7usu4hu1/` survives, which let us recover the exact `policy/policy.json` bytes and confirm single-state fixtures). Binary paths were re-pointed at `zig-out/bin/mylang` and fixture/cache paths at a fresh run root. Stateful sequences (selective tests, one-shot, session) were replayed in the recorded order. Output paths are normalized before comparison; native-test receipt keys change with compiler identity and are compared field-by-field excluding `key`.

Two probes (`ordinary_check_ignores_policy`, `explicit_policy_enforced`) could not be reproduced verbatim: their recorded `sources` contain `helper.my` importing `main`, which is an import cycle and would make the recorded command exit 1, contradicting the recorded return codes. The audit's intended valid two-module fixture (helper does not import main) with the exact recovered `policy.json` reproduces both records; that is what is reported for those two rows.

## 5. Per-probe results

Disposition: **verified** = behavior matches the record and is not a gap this plan must change; **still-open** = the recorded behavior reproduces and is the target of a later package; **already-fixed** = behavior changed in the desired direction.

| # | Probe | Orig rc | New rc | Matches record | Disposition | Target | Note |
| ---: | --- | ---: | ---: | :---: | --- | --- | --- |
| 1 | `features` | 0 | 0 | yes | verified | — | Feature manifest is byte-for-byte identical to the audit; only `compiler_sha256` differs (rebuilt baseline identity `fff3e012...`). |
| 2 | `unannotated_output` | 0 | 0 | yes | verified | — | Private helper may still print under inferred effects. E2 adds a distinct exported-helper rejection; this private case is expected to stay valid. |
| 3 | `empty_effects_reject_output` | 1 | 1 | yes | verified | — | Rejection preserved with the same `E_EFFECT_BOUND` location. |
| 4 | `empty_effects_mutate_argument` | 0 | 0 | yes | still-open | M2/M3 | Native run still exits 0 and the caller observes values[0] == 42; `effects()` still permits writes through a shared list. |
| 5 | `empty_effects_reject_append` | 1 | 1 | yes | verified | — | Rejection preserved; append still contributes `managed_allocation`. |
| 6 | `record_nested_alias` | 0 | 0 | yes | still-open | M2/M3 | Native run still exits 0; a write through a copied record's shared list is still invisible in the effect signature. |
| 7 | `missing_parameter_type` | 1 | 1 | yes | verified | — |  |
| 8 | `omitted_return_is_unit` | 1 | 1 | yes | verified | — |  |
| 9 | `int_float_conversion` | 1 | 1 | yes | verified | — |  |
| 10 | `option_direct_field` | 1 | 1 | yes | verified | — |  |
| 11 | `unhandled_result` | 1 | 1 | yes | verified | — |  |
| 12 | `explicit_result_discard` | 0 | 0 | yes | verified | — |  |
| 13 | `exhaustive_union_base` | 0 | 0 | yes | verified | — |  |
| 14 | `exhaustive_union_added` | 1 | 1 | yes | verified | — |  |
| 15 | `wildcard_union_added` | 0 | 0 | yes | verified | — |  |
| 16 | `aliases_are_transparent` | 0 | 0 | yes | verified | — |  |
| 17 | `domains_are_distinct` | 1 | 1 | yes | verified | — |  |
| 18 | `callback_effect_subset` | 1 | 1 | yes | still-open | E1 | Still rejected: a `effects()` implementation does not satisfy a destination declaring `effects(output)` (exact-mask relation). |
| 19 | `formatter_whitespace` | 0 | 0 | yes | still-open | F1 | `fmt` still returns the noncanonical input bytes unchanged (`value=  40+2`). |
| 20 | `formatter_check_whitespace` | 0 | 0 | yes | still-open | F1 | `fmt --check` still exits 0 on noncanonical bytes, so it does not detect differences. |
| 21 | `trap_metadata` | 1 | 1 | yes | still-open | D1 | Bounds trap status, primary location and call stack are preserved, but no index/length values and no structured `trap_detail` are emitted. |
| 22 | `ordinary_check_ignores_policy` | 0 | 1 (verbatim); 0 (intended fixture) | yes | verified | — | Recorded `sources` are self-inconsistent: the recorded cyclic helper makes the recorded command exit 1 (`E_IMPORT_CYCLE`), not the recorded 0. With the audit's intended valid two-module fixture the command exits 0 with no output, matching the record; the adjacent `policy.json` has no magic effect. |
| 23 | `explicit_policy_enforced` | 3 | 1 (verbatim); 3 (intended fixture) | yes | verified | — | Same cyclic-source inconsistency. With the valid fixture and the exact recovered `policy.json` (sha256 `451b4a50...`), exit 3 and stdout are byte-identical to the record, including `config-sha256`. |
| 24 | `cycle_rejected` | 1 | 1 | yes | verified | — | Recorded cyclic fixture reproduced exactly: exit 1, `E_IMPORT_CYCLE` with the same spans. |
| 25 | `default_257_module_limit` | 1 | 1 | yes | verified | — | Regenerated 257-file chain; exit 1, `E_MODULE_LIMIT` at `m255.my:2:8` exactly as recorded. |
| 26 | `selective_tests_cold` | 0 | 0 | yes | verified | — | Both tests executed and passed. Receipt keys differ because the key includes compiler identity; statuses, dependency ids and step counts are identical. |
| 27 | `selective_tests_warm` | 0 | 0 | yes | verified | — | Both cached, 0 executed. Same as record (keys differ with compiler identity). |
| 28 | `selective_tests_helper_edit` | 0 | 0 | yes | verified | — | One test reran/passed, one stayed cached; same as record (keys differ with compiler identity). |
| 29 | `selective_tests_unused_edit` | 0 | 0 | yes | verified | — | Both cached; same as record (keys differ with compiler identity). |
| 30 | `selective_tests_force` | 0 | 0 | yes | verified | — | Both force-executed and passed; same as record (keys differ with compiler identity). |
| 31 | `selective_tests_invalid_edit` | 2 | 2 | yes | verified | — | Setup rejected with exit 2 and identical `E_TYPE` diagnostic; no cached success reported. |
| 32 | `session_ordinary` | 0 | 0 | yes | verified | — | Interactive replies match on statuses and every counter; only `retained_bytes` differ. The edit rechecks 1 body and reuses 2. |
| 33 | `session_generic` | 0 | 0 | yes | still-open | C1/C3 | The edit rechecks all ordinary bodies with 0 reused and 2 bypassed; an unused generic still disables the ordinary body-cache path. |
| 34 | `extern_missing_required_host_annotation` | 1 | 1 | yes | verified | — | Rejection preserved with the same `E_HOST_EFFECTS` diagnostic. |
| 35 | `custom_effect_name` | 1 | 1 | yes | verified | — | Unknown effect `db` still rejects with the same `E_UNKNOWN_EFFECT` list. |
| 36 | `named_constraint_production` | 0 | 0 | yes | verified | — | Named-constraint production example passes at baseline `9ce142e`, which includes the named-constraint fixes. |
| 37 | `named_constraint_fake_test` | 0 | 0 | yes | verified | — | Fake-provider test passes. Receipt key differs with compiler identity; dependencies and step count identical. |
| 38 | `one_shot_cold` | 0 | 0 | yes | verified | — | Cold report counters and `stages` are byte-identical to the record. |
| 39 | `one_shot_warm` | 0 | 0 | yes | verified | — | Verdict hit count 1 and all `stages` are byte-identical to the record. |
| 40 | `one_shot_edit` | 0 | 0 | yes | still-open | C2 | The edited one-shot project misses the verdict and rechecks bodies (`check_body` miss); checked bodies are still not persisted across processes. |
| 41 | `one_shot_invalid` | 1 | 1 | yes | verified | — | Exit 1 with the same `E_TYPE` diagnostic and no verdict stored; identical to record. |
| 42 | `noio_allows_host` | 0 | 0 | yes | verified | — | `noio` still accepts an explicitly declared `effects(host)` call; the documented narrow meaning is preserved. |

## 6. Findings: already fixed versus still open

- **Already fixed in this baseline: 0 of 42.** No probe changed in the direction the plan wants. The baseline is behaviorally identical to the audit record for the 40 verbatim-reproducible probes, and the two policy probes reproduce the record once the missing exact policy fixture is restored. In particular `named_constraint_production` and `named_constraint_fake_test` pass at `9ce142e`, which contains the named-constraint fixes; they are counted as verified, not as newly fixed.
- **Verified / preserved: 34 of 42.**
- **Still open at this baseline: 8 of 42.**
  - `empty_effects_mutate_argument` → M2/M3: Native run still exits 0 and the caller observes values[0] == 42; `effects()` still permits writes through a shared list.
  - `record_nested_alias` → M2/M3: Native run still exits 0; a write through a copied record's shared list is still invisible in the effect signature.
  - `callback_effect_subset` → E1: Still rejected: a `effects()` implementation does not satisfy a destination declaring `effects(output)` (exact-mask relation).
  - `formatter_whitespace` → F1: `fmt` still returns the noncanonical input bytes unchanged (`value=  40+2`).
  - `formatter_check_whitespace` → F1: `fmt --check` still exits 0 on noncanonical bytes, so it does not detect differences.
  - `trap_metadata` → D1: Bounds trap status, primary location and call stack are preserved, but no index/length values and no structured `trap_detail` are emitted.
  - `session_generic` → C1/C3: The edit rechecks all ordinary bodies with 0 reused and 2 bypassed; an unused generic still disables the ordinary body-cache path.
  - `one_shot_edit` → C2: The edited one-shot project misses the verdict and rechecks bodies (`check_body` miss); checked bodies are still not persisted across processes.

## 7. Other baseline findings

1. **Doc example gate fails on a historical audit file.** `docs/audits/development-velocity-proposals-2026-09-15.md:141` has a fenced block tagged `text` that `mylang doctest` classifies as guest source. This makes `zig build test-docs` and the doctest step of `zig build test` fail in both Debug and ReleaseFast. The file is a historical audit record and was not edited here; the integrator owns the decision to retag it or exclude it.
2. **ReleaseFast has two deterministic unit-test failures** that Debug does not: `persist_codec.test.codec rejects truncated and malformed bytes` and `incremental_test.test.materialize, dupModule, dupDeclaration, dupNominal, dupSpecialization and dupFragment release partial copies`. A targeted `zig build test-units -Doptimize=ReleaseFast` reproduces 941/943. This is a pre-existing baseline gap for the plan's ReleaseFast gate.
3. **One ReleaseFast test compilation reported peak RSS 2.31 GB against the declared 2.15 GB bound.** The targeted unit re-run reused the cached compile and did not reproduce it; treat it as a measured baseline build-runner signal, not a confirmed deterministic failure.
4. **`zig build test-native-tests` was cache-satisfied** in this run; the underlying 43-test native-test step had passed 43/43 moments earlier as a dependency of `zig build test-qbe`.

## 8. Limitations

- The historical audit compiler binary (`c54d594e...`) was not re-run; all comparisons use the freshly built baseline compiler. Receipt keys and `retained_bytes` therefore differ while counters and statuses match.
- No large-project scale, latency or memory benchmark was run; no claim is made about speedups.
- The Guardian runs inside `zig build` were diff-scoped (88 checks). The commit hook for this evidence change ran a whole-tree Guardian gate (88/88 passed); see section 3.
- `vendor/qbe` is vendored source without its own git metadata, so an upstream QBE commit cannot be reported; `.qbeversion` and content/binary hashes are the identity.
- Raw gate logs and the reconstructed fixture tree live under `/tmp/w0-evidence/` and are not committed; the commands and counts are reproduced in this document and the JSON.

## 9. Guardian

The required Guardian feedback entry is committed at [guardian-w0-verify.md](guardian-w0-verify.md).

