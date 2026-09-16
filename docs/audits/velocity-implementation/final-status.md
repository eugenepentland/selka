# Development velocity: implementation status

Status: **core packages plus the R1–R4/HASH/WARM and C3/C4 correction passes integrated on `610656cf`; release checklist partially met.**
Baseline: `9ce142e98cb22e684622ed1d5678071d6944206e` (post named-constraint fixes).
Integration HEAD: `610656cf` (correction-pass code gate; later commits are status documentation only).
Plan: [development-velocity-implementation-plan-2026-09-15.md](../development-velocity-implementation-plan-2026-09-15.md).
Ledger and frozen contracts: [README.md](README.md), [contracts.md](contracts.md).

## Integrated packages

| Package | Result | Integration |
| --- | --- | --- |
| W0 | baseline, frozen contracts, execution ledger | `66e96ce` |
| W0Q | 42 audit probes re-run; gate record; incremental-status reconciliation | `1c79941` |
| F1 | canonical formatter; `fmt`/`--check`/`fmt-project --check`; comment/literal/execution preservation | `0594e61` |
| D1 | bounded structured native trap detail in text and JSON; stderr record transport | `5591945`, `20a8938` |
| C0 | `work-report-v1` actual work/reuse counters separate from fingerprints | `3d505be` |
| E1 | directional callable effect assignability; canonical callback diagnostics | `55aee27` |
| E2 | explicit exported effect ceilings; declared bounded API fingerprints; corpus migration | `2c0e270` |
| M1 | `effects(mutation)`, `mutates(...)`, write/return-origin metadata, `effects-v3`, shared classifier | `44a0bfe` |
| M2 | deep origins, call-permission enforcement, conservative overlap rejection, return aliases | `8d5b84b` |
| C1 | per-function body eligibility, stable identity remapping, negative lookups | `b8a512a` |
| A1 | required entry-anchored `mylang.json` import policy in ordinary commands and caches | `5988575` |
| S1 | repaired workload harness; 10k/100k/maintained cold/warm/edit samples | `21d104e` |
| M3 | corpus repair/activation, navigation exposure, runnable mutation docs | `75bb69a` |
| C1R | module-qualified stable keys, resolved-declaration dependencies, callback/function-value eligibility, contract-bound reuse context; check-session bypass lifetime fix | `86ffbb7c` |
| C2 | durable `semantic-cache-v1` checked bodies: atomic publication, validated remap-or-miss decoding, contract isolation, eviction, `--no-cache` correctness | `88691e7b` |
| P1 | declaration-first provider selection: replacements validated against every public contract, receipt contract/provider/source identities | `354c0e8` |
| C3a | symbolic-template reuse (`symbolic-template-v1`): durable direct abstract results, selective invalidation, whole-graph effects rerun | `8b212f7e` |
| C3b | canonical specialization-key engine (template/positional/provider/constraint/contract/build dimensions) | `b0b156e8` |
| C3S | validated concrete-specialization replay (`specialization-v1`) with typed remap and effect-rerun discipline | `f444ddc5` |
| C4 | receipt-first test selection with a durable reduced preparation graph (`native-test-graph-v1`); warm unchanged reruns execute zero tests with no lowering/emission/linking | `aea9b525` |
| G1 | reduced graph bound to its requested input key (v2 envelope + structural validation); a copied entry is a miss | `0c420fbc` |
| N1 | directory fan-out forwards `--no-cache`; seeded/empty caches execute every case and write zero durable files | `0c420fbc` |
| Retention | bounded-prefix ordinary retention, reference-sized ordinary remap, clear releases all three entry kinds, shared `reuse.max_bytes` budget with per-kind reporting | `9699895b`/`610656cf` |
| R3 | canonical declaration type descriptors; manifest `interface-contracts-v2` | `bc462aa6` |
| R1/R2 | receipt acceptance bound to selected dependency closure; one checked project/prepared library per selected provider graph | `1ed663b9` |
| R4 | batched semantic-store inventory: statx 128/256/512/1024 → 260/516/1028/2052 | `d54cc302` |
| HASH | declared `mutates` positions + exported return-origin bound in the public API fingerprint | `4e2d1600` |
| WARM | per-file content dependency removes the cold-build requirement for runtime edits | `70eecedf` |
| Follow-up | F1 keeps the space before `mutates(...)`; board-trial/schematic standalone runners accept the driver's trailing `--cache-dir` | `26e8121` |

Still open from the plan: **D2** (final documentation/feature reconciliation), the
**S1** remeasurement on this corrected tree, and the productivity trial. C4's
per-function lazy lowering/emission boundary also remains: a changed snapshot
performs one whole-project preparation emission and an uncached selection builds
the whole selected-provider library, while fully cached selections skip all
lowering/emission/linking.

## Final gate evidence

Gates on the corrected C3/C3S/C4 tree (`610656cf`, worktrees rebuilt from the C3/C4 tree):

| Gate | Result |
| --- | --- |
| `zig build test --summary all -j8` (Debug) | **39/39 steps succeeded; 1199/1199 tests passed; exit 0** |
| `zig build test -Doptimize=ReleaseFast --summary all -j1` | **39/39 steps succeeded; 1198/1199 passed, 1 skipped (Debug-only allocation sweep); exit 0** |
| Retention batch (ReleaseFast at the retention commit `92218ee2`) | **39/39 steps; 1198/1199 passed, 1 skipped; exit 0** |
| WARM end-to-end probe | in-place bundled-runtime edit refreshed `content_hash`, installed archive names and materialized runtime bytes without cleaning |
| Guardian whole-tree commit gate | 88/88 checks passed |
| `zig build fmt-check`, `test-doc-coverage`, `test-docs`, `test-qbe`, `test-native-tests` | covered by the `test` graph and independently green |

The ReleaseFast test-root compile peaked at 2.55 GiB on this tree, above the old
2.15 GiB `rss.compile` bound, so `build.zig` now declares 3 GiB with a measured
comment. ReleaseFast still runs at `-j1` on this host for memory stability. This
is a bounded host-build ceiling, not a project size limit.

Pinned toolchain: Zig `0.17.0-dev.1683+5ceec001b`; QBE built from `vendor/qbe`
(1.3). Baseline compiler identity `fff3e012…`.

## Release checklist

| Item | Status | Evidence / gap |
| --- | --- | --- |
| Audit mutation reject under empty effects; declared writes succeed; deep aliases, callbacks and generic bodies cannot bypass | **Met for the required matrix** | Audit `empty_effects_mutate_argument` and `record_nested_alias` reject with `E_MUTATION_PERMISSION`/`E_MUTATION_OVERLAP`; permitted `effects(mutation) mutates(...)` counterparts run natively. Partial transitive generic-call substitution remains; the declared mutation footprint and the exported return-origin bound now participate in the public API fingerprint (HASH), while inference stays body-local. |
| Exported ceilings explicit; effect/mutation subset substitution works | **Met** | `E_EFFECT_CEILING` at declarations with body-derived bounds; E1/E2 relation plus M1/M2 footprint subset. |
| Formatter changes noncanonical source, preserves semantics, idempotent | **Met** | F1 fixtures and native execution-preservation tests. |
| Bounds traps show index/length in native text and JSON with stacks | **Met** | D1 text/JSON trap detail; Debug and ReleaseFast; `run` and native tests. |
| Unrelated ordinary bodies reuse with generics present and across processes | **Met for ordinary bodies** | C1R measures a session edit as `performed=1/reused=2`; C2 measures a genuinely new process as `performed=1/reused=2` and an unchanged rerun as `performed=0/reused=3`. Generic specializations still wait for C3. |
| Symbolic templates and concrete specializations have measured selective reuse | **Met for template and specialization bodies** | C3/C3S persist `symbolic-template-v1` and `specialization-v1` and measure real reuse: a fresh process after an entry-body edit reports `checked_bodies performed=1/reused=2`; template/argument edits invalidate only dependents. Ordinary bodies that *reference* a specialization still conservatively miss (`.generic_specialization`), and nested refs whose instance is not yet materialized miss. |
| Warm/cold/no-cache status, diagnostic, interface and native results agree | **Met for the implemented reuse scope** | C2/C3/C3S test cold/warm/`--no-cache` for ordinary bodies, symbolic templates and concrete specializations, including damage, contract isolation, concurrency and eviction; WARM proves in-place runtime edits refresh identity/archives without cleaning. C4 shows a warm unchanged native-test run executes zero tests with no lowering/emission/linking and that `--report` reconciles `executed_tests.performed/reused` with `native-tests-v1`. |
| A fake can replace an unfinished production body against a checked contract | **Met** | P1 checks declarations/interfaces first, fully checks only the selected provider graph, validates every replaced public contract with the directional relation, and binds contract/provider/source identities into receipts. |
| Configured architecture policy cannot be skipped by ordinary commands or caches | **Met** | A1 config discovery/enforcement cold and warm, statuses 2/3, cwd-independent, receipts include policy identity. |
| Selective tests retain correctness and skip unnecessary compilation work | **Met for fully cached selections; per-function lazy lowering remains** | R1/R2 bind receipts to the selected closure and share one prepared graph/library per provider identity; C4 skips all lowering/emission/linking for a warm unchanged selection (zero executions) and executes only dependent tests after an edit. Any snapshot change still pays one whole-project preparation emission and an uncached selection builds the whole selected-provider library. |
| Representative scale limits, latency and memory measured honestly | **Met as measurement; objectives not met** | S1: 100k check p95 2.9–4.9 s vs <500 ms target; forced-test measurement blocked; 500k provisional only; productivity trial unrun. |
| Current documentation and feature claims match the final executable | **Partial** | M3 and F1/D1/C0/E1/E2/C1 docs are current; D2's full reconciliation, historical page redirects and benchmark-script follow-ups remain. |
| Relevant gates and Guardian feedback complete | **Met for the integrated scope** | Both final gates green; consolidated feedback committed to `~/ai/canopy/guardian-zig/FEEDBACK.md`. |

## Known limitations carried forward

- **Conservative overlap:** same/overlapping managed type pairs
  (`list[int]`/`list[int]`, `dict[str,int]`/`dict[str,int]`) reject unless proven
  disjoint; two writable aliases or an explicit snapshot are the repairs.
- **Return-origin declaration syntax:** the public API fingerprint now hashes the
  declared mutation footprint and the exported return-origin bound (HASH), but the
  language has no syntax for a narrower declared return-origin, so exported
  declarations hash the conservative `unknown` bound; inferred private precision
  remains a body-local fact.
- **Transitive generic mutation substitution:** abstract generic checking enforces
  attributed direct writes; concrete specializations are fully re-checked.
- **Scale:** the default loader still bounds projects at 256 modules/16 MiB, the
  in-memory semantic body cache bypasses at 100k bodies, navigation rejects both
  100k workloads, and the performance targets are unmet without C3/C4. `S1` has
  not been remeasured after C2/R4; the persistent cache now populates with linear
  filesystem work (statx 260/516/1028/2052 for 128/256/512/1024 bodies).
- **Documentation:** D2's final pass and the productivity trial are outstanding.

Historical audit documents and probe JSON were not rewritten; where an audit
example now correctly rejects, its fence is marked `notest` so the historical
bytes remain visible without being executed as current behavior.
