# Correction-pass review — 2026-09-16

## Decision

**Ready to start C3.** The original R1–R4 reproductions are corrected, and
the public-contract fingerprint fix behaves as intended. The WARM change
addresses the identified build dependency gap; the recorded combined gate
results match the completion report.

One remaining R2 performance defect should be fixed before C4 acceptance:
identical provider maps with different JSON key orders do not share preparation.
It does not produce an incorrect test result and does not block C3.

This is approval to continue implementation. C3/C4, S1 performance acceptance,
D2 reconciliation and the productivity trial remain open.

## Scope and provenance

- Reviewed committed changes from `6a99ef4b` through `81cd79bb`.
- Ran focused probes with a pinned ReleaseFast executable from the clean
  `final-release` worktree at `216965ce7d1b50b38254e78c7980ef1d19bbb1a9`.
  Its implementation sources match `81cd79bb`; later commits only update docs.
- Binary SHA-256:
  `99f2f80dca105868ecd08f9ac4c3d2893a1991883625c61400bc2bc29faacd8e`.
- Advertised compiler identity:
  `3a58ef0525ca632ceb976a191661787292a24fb9bb72e2ba154baec7bc611351`.
- Used private fixtures/caches. Concurrent uncommitted cache-performance work
  in the main checkout is outside this review.
- Reviewed existing full-gate logs and WARM source/regression/package evidence.
  Did not rerun the full Zig/Guardian gates or repeat the source-mutating warm
  rebuild experiment. No implementation files were edited.

Commands, outputs, fixtures, child-process traces, hashes and copied gate logs
are in [the probe evidence](development-velocity-correction-review-2026-09-16-probes.json).
Single-run timings in that evidence are diagnostic observations, not S1 benchmarks.

## Finding

### P2 — canonicalize provider-map order before memoizing graphs

Locations: `src/native_test_command.zig:40-43` and
`src/native_test_contracts.zig:62-66`.

The new graph memoization uses `contracts.providerIdentity`. That helper hashes
JSON serialized in insertion order. Two cases replacing the same files with
identical source bytes therefore acquire different identities when their
`providers` keys appear in a different order.

A fixture imports `first` and `second`. Both test cases select identical
replacement sources:

| Configuration | Native builds, forced | Total QBE emissions, forced | QBE emissions, cached |
| --- | ---: | ---: | ---: |
| Both maps list `first.my`, then `second.my` | 1 | 2 | — |
| Second map lists `second.my`, then `first.my` | 2 | 4 | 2 |

All cases pass; the cached run executes zero tests. The difference is redundant
declaration checking, graph preparation and native building. Thus R2's ordinary
case regression is fixed, but its claim that identical provider graphs always
share is too broad.

**Repair:** derive graph identity from a canonical sequence of provider path and
source pairs, sorted by path with unambiguous field boundaries. Reuse that
normalization for the selected contract-module ordering where appropriate.
Retain distinct identities when any replacement path or source changes.

**Acceptance:** add a two-provider, two-case integration regression with reversed
map order. A forced run must prepare one graph and build one native library;
changing either replacement's bytes must still produce a distinct graph.
Track this with C4 or land it as a small prerequisite; it need not delay C3.

## Independently reproduced results

| Area | Result |
| --- | --- |
| R1 unrelated edit | 0 executed / 2 cached; dependency keys unchanged |
| R1 used helper edit | 1 executed / 1 cached; only the dependent case's key changes |
| R1 genuinely failing edit | Changed helper returns the wrong value: 1 failed / 1 cached; no stale green receipt |
| R2 ordinary cases | Cached: 1 emission. Forced: 1 build / 2 total emissions |
| R2 identical provider maps in the same order | Forced: 1 build / 2 total emissions |
| R3 aliases | Boolean alias and imported, recursively expanded boolean alias both discover and pass |
| R3 substitution | Production `int` accepts fake `i64`; `u8`, `str`, and a different nominal domain reject |
| P1 unfinished production | Fake passes with production `todo[int]()` and with a production body type error; invalid production interface rejects |
| P1 real production | Actual native build rejects the body type error with `E_TYPE` |
| C2 new processes | Body checks/reuse: seed 3/0, private edit 1/2, unchanged 0/3 |
| C2 damage and fresh control | Corrupt one current entry: 1 checked / 2 reused; `--no-cache`: 3 checked / 0 reused |
| HASH mutation contract | `mutates(a)` → `mutates(b)` changes function and project interface hashes |
| HASH canonical order | `mutates(a, b)` and `mutates(b, a, b)` produce equal interface hashes |
| HASH body-only edit | Interface hashes remain equal; body hash changes |

The C2 body probes use `project-dependencies`, which reconstructs the checked
program and therefore exercises body decoding. Earlier `check-project`
unchanged/damage controls hit the whole-project verdict cache; those controls
are retained in the raw evidence but are not counted as body-decoding proof.

### R4 inventory growth

Re-ran the committed population benchmark with fresh independent namespaces:

| Bodies | `statx` calls |
| ---: | ---: |
| 128 | 262 |
| 256 | 518 |
| 512 | 1,030 |
| 1,024 | 2,054 |

Doubling ratios are 1.98, 1.99 and 1.99. This confirms linear filesystem
inventory work for this workload. The two-call difference from the completion
report is constant overhead; it does not change the scaling result. This does
not establish end-to-end 10k/100k latency or memory acceptance.

### Recorded full gates and WARM

The preserved logs and exit markers report:

- Cold Debug: 39/39 steps, 1167/1167 tests, exit 0.
- ReleaseFast: 39/39 steps, 1166/1167 tests, one skipped, exit 0.
- Warm Debug: 39/39 steps, 1036/1036 uncached tests, exit 0.
- Documentation: 436 blocks, zero failed.

Source inspection confirms per-file `dependOnFileContents` registration for
the inputs used by the generated asset identities, with directory dependencies
retained for entry changes. The added regression recomputes the bundled runtime
content hash from the embedded bytes. The separate in-place-edit experiment
remains evidence supplied by the implementation pass, not independently rerun
evidence from this review.

## Next-stage acceptance

1. **C3:** implement symbolic-template reuse and concrete-specialization reuse as
   separate changes. Require fresh-process selective reuse and cold/no-cache
   equivalence across named constraints, concrete providers, nominal identities,
   effects/mutation, const lengths, recursion and diagnostic relocation.
2. **C4:** include the provider-order repair above. An unchanged cached test must
   perform zero unnecessary lowering/emission/linking, while invalid selected
   projects and invalid original public contracts still reject.
3. **S1:** obtain a corrected baseline once the concurrent cache-performance fixes
   land, then evaluate the integrated C3/C4 result. Report actual work, wall time
   and memory separately; receipt/body reuse counts alone are insufficient.
4. Complete D2, the productivity trial and the combined release gate. The full
   performance and general invalidation claims remain open until these pass.
