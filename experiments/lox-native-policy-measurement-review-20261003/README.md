# Independent native backend policy measurement review

The completed trial passes independent host-only provenance, coverage, arithmetic and archive checks. All 1,196 successful rows are accounted for: smoke156, screen104, full wall468 and full counters468. The two full matrices cover 13 cases × two engines × six original frozen arms × three paired rounds. All statuses, output hashes, diagnostics, workload sizes and command/source/binary bindings match. Smoke collector stats match across all six arms; all 2,288 screen/full PMU event rates are100%.

| QBE candidate against QBE control | Tree | VM |
| --- | ---: | ---: |
| Wall reduction | 7.70888% | -0.48683% |
| Instruction reduction | 2.66068% | approximately0% |
| Cycle reduction | 8.52995% | -0.37788% |

Negative reductions mean slower or more expensive. All13 QBE tree wall medians improve, ranging1.52549–27.13387%; three round aggregates improve7.82163/7.64406/7.66692%. Nine13 VM medians slow, including fib2.2802%, string equality1.3447% and trees1.5321%. Their paired spreads are preserved in `review.json`. LLVM wall changes of -0.02835% VM/-0.10512% tree accompany unchanged allocated LLVM code. Observed spreads and three paired rounds do not establish statistical confidence or absence of regressions. The candidate remains slower than Rust/Go; this review makes no parity, selection or main-merge claim.

Preparation's exact1,038-input before/after map binds author core878, selected37, current owned16-file compiler prefix, actual four qualified RC/GC guests and reviewed packages. The performance protocol reconstructs the exact252 guards and six native runtime roles from actual measured/rebuilt manifests. Measurements use whole-file-exact qualified RC guests and sidecars. Fresh rebuilds have equivalent ELF header/program layout and all26 allocated sections, with nonallocated debug/symbol metadata differences retained as reproduction evidence. Guarded runtime objects override cache exclusions; shared objects are deduplicated while all six roles remain recorded.

The strict closeout report equals the sealed archive's validated report. Archive MANIFEST `431b64aca839ef7514c0f388815cc8d0bf29b0b69dcc4f9b6710af155250b18b` passes an independent complete inventory and object check:375 current original identities and276 content-addressed objects. The archive lives at `/home/epentland/ai/canopy/evidence/mylang-lox-compiler-screens-20261003/native-backend-policy`. Every original/copy hash, size, symlink identity, guard, explicit extra and allowed cache exclusion is checked; archive extras add no successful rows.

Historical observations remain separate. `partial-check.json` records completed smoke/screen only; `wall-check.json` adds the completed wall before counters were finished. Neither subtotal adds extra observations to the final total. The initial strict check correctly refused an unfinished `wall.command.json`; the original35-file protocol review correctly refused the later final37-file package until its append-only supplement. Both refusal logs are archived. Native author qualification retains its previously reviewed prospective/retrospective prefix and helper limits; the core878/full-prefix preparation window is not relabeled a whole native/performance-window guarantee. Performance receipts retain stdout hashes and stderr tails rather than full stdout.

`inputs.json.gz` preserves47 reviewed metadata/log inputs, including the archive manifest. The independent readers recheck current source/prefix/ELF/runtime identities and recompute all five analyses without executing compiler, guest, native test or performance payloads. Run:

```sh
taskset -c 16 python3 -B verify.py
```

Root owns performance selection, integration and consolidated Guardian feedback. This review changes only its own experiment files.
