# Development velocity: implementation status

Status: **core packages integrated on `88691e7b`; release checklist partially met.**
Baseline: `9ce142e98cb22e684622ed1d5678071d6944206e` (post named-constraint fixes).
Integration HEAD: `88691e7b3c5d6dea0a05e82ffadb375bd865981f`.
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
| Follow-up | F1 keeps the space before `mutates(...)`; board-trial/schematic standalone runners accept the driver's trailing `--cache-dir` | `26e8121` |

Still not started from the plan: **C3** (generic/specialization reuse), **C4**
(cached test preparation and lazy lowering) and **D2** (final documentation/feature
reconciliation). The productivity trial is unrun. `S1`'s performance objectives
were measured and not met.

## Final gate evidence

Cold builds in fresh worktrees followed by full gates on `88691e7b`:

| Gate | Result |
| --- | --- |
| `zig build test --summary all` (Debug) | **39/39 steps succeeded; 1153/1153 tests passed; exit 0** |
| `zig build test -Doptimize=ReleaseFast --summary all` | **39/39 steps succeeded; 1152/1153 passed, 1 skipped (Debug-only allocation sweep); exit 0** |
| Guardian whole-tree commit gate | 88/88 checks passed |
| `zig build fmt-check`, `test-doc-coverage`, `test-docs`, `test-qbe`, `test-native-tests` | covered by the `test` graph and independently green |

Pinned toolchain: Zig `0.17.0-dev.1683+5ceec001b`; QBE built from `vendor/qbe`
(1.3). Baseline compiler identity `fff3e012…`.

## Release checklist

| Item | Status | Evidence / gap |
| --- | --- | --- |
| Audit mutation reject under empty effects; declared writes succeed; deep aliases, callbacks and generic bodies cannot bypass | **Met for the required matrix** | Audit `empty_effects_mutate_argument` and `record_nested_alias` reject with `E_MUTATION_PERMISSION`/`E_MUTATION_OVERLAP`; permitted `effects(mutation) mutates(...)` counterparts run natively. Partial transitive generic-call substitution and return-origin-in-API-fingerprint remain. |
| Exported ceilings explicit; effect/mutation subset substitution works | **Met** | `E_EFFECT_CEILING` at declarations with body-derived bounds; E1/E2 relation plus M1/M2 footprint subset. |
| Formatter changes noncanonical source, preserves semantics, idempotent | **Met** | F1 fixtures and native execution-preservation tests. |
| Bounds traps show index/length in native text and JSON with stacks | **Met** | D1 text/JSON trap detail; Debug and ReleaseFast; `run` and native tests. |
| Unrelated ordinary bodies reuse with generics present and across processes | **Met for ordinary bodies** | C1R measures a session edit as `performed=1/reused=2`; C2 measures a genuinely new process as `performed=1/reused=2` and an unchanged rerun as `performed=0/reused=3`. Generic specializations still wait for C3. |
| Symbolic templates and concrete specializations have measured selective reuse | **Not met** | C3 not implemented. |
| Warm/cold/no-cache status, diagnostic, interface and native results agree | **Met for the ordinary-body scope** | C2 tests cold/warm/`--no-cache`, warning relocation, damaged/oversized/foreign entries, contract isolation, concurrency and eviction against fresh checks; C3 specialization and C4 test-result reuse remain. |
| A fake can replace an unfinished production body against a checked contract | **Met** | P1 checks declarations/interfaces first, fully checks only the selected provider graph, validates every replaced public contract with the directional relation, and binds contract/provider/source identities into receipts. |
| Configured architecture policy cannot be skipped by ordinary commands or caches | **Met** | A1 config discovery/enforcement cold and warm, statuses 2/3, cwd-independent, receipts include policy identity. |
| Selective tests retain correctness and skip unnecessary compilation work | **Partial** | Existing deterministic test receipts preserved and measured; C4's lazy lowering/emission and shared test preparation are not implemented. |
| Representative scale limits, latency and memory measured honestly | **Met as measurement; objectives not met** | S1: 100k check p95 2.9–4.9 s vs <500 ms target; forced-test measurement blocked; 500k provisional only; productivity trial unrun. |
| Current documentation and feature claims match the final executable | **Partial** | M3 and F1/D1/C0/E1/E2/C1 docs are current; D2's full reconciliation, historical page redirects and benchmark-script follow-ups remain. |
| Relevant gates and Guardian feedback complete | **Met for the integrated scope** | Both final gates green; consolidated feedback committed to `~/ai/canopy/guardian-zig/FEEDBACK.md`. |

## Known limitations carried forward

- **Build-cache staleness:** after large `src/` edits a warm `.zig-cache` can keep a
  stale generated `qbe_build_assets` module, so `zig build test` may link an old
  runtime archive; a cold build is required. Root cause and a generated-module
  invalidation fix remain open.
- **Conservative overlap:** same/overlapping managed type pairs
  (`list[int]`/`list[int]`, `dict[str,int]`/`dict[str,int]`) reject unless proven
  disjoint; two writable aliases or an explicit snapshot are the repairs.
- **Return-origin API fingerprint:** inferred `return_origin` is published and
  hashed in callable/schema records but is not yet part of the exported function
  API fingerprint.
- **Transitive generic mutation substitution:** abstract generic checking enforces
  attributed direct writes; concrete specializations are fully re-checked.
- **Scale:** the default loader still bounds projects at 256 modules/16 MiB, the
  semantic body cache bypasses at 100k bodies, navigation rejects both 100k
  workloads, and the performance targets are unmet without C2/C3/C4.
- **Documentation:** D2's final pass and the productivity trial are outstanding.

Historical audit documents and probe JSON were not rewritten; where an audit
example now correctly rejects, its fence is marked `notest` so the historical
bytes remain visible without being executed as current behavior.
