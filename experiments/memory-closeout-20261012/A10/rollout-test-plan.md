# C2 and C3 test-path inventory

This is a source inventory and test plan, not rollout qualification. Raw file/
line matches and immutable fixture hashes are in `rollout-test-inventory.json`.
Categories overlap; lexical RC names alone do not determine whether a test is
obsolete. Direct destruction and task counters remain required.

## Actual inheritance boundaries

- Ordinary build/run/test reach `pipeline.Codegen` through `cli_args`, core
  developer `main`, and test-runner options. Native end-to-end tests which spawn
  those commands inherit C2's defaults. The external compiler references in the
  JSON inventory identify the source drivers; their generated inline programs
  also need ownership migration, beyond the 356-file guest survey.
- `test/core` contains another 175 `.my` files; `test/fixtures` contains 44.
  Neither set was included in the 356 denominator. Some are intentional syntax/
  diagnostic failures or module fragments. Run ordinary-vs-owned source admission
  first and retain both statuses rather than counting every refusal as a new bug.
- Shared `test_support.buildSource` calls `build.buildModule` directly, and
  `runOwned` emits and links its supplied IR. These helpers **do not inherit
  pipeline.Options**. Their current RC behavior is a C3 migration obligation,
  not evidence that changing the CLI default removed legacy IR/runtime paths.
- `pipeline_emission_test` and `backend_owned_test` build IR directly and then
  pass default pipeline emission options. C2 must keep the module's actual ABI
  and the requested verifier/emitter mode consistent; never silently report the
  RC module as checked ownership. Preserve source lifetime and split/whole
  emission assertions while selecting the owned module contract explicitly.
- Production `cost_command` likewise built directly before constructing
  pipeline options. This concrete bypass is assigned to A10: eager source
  validation, selected lowering flags and emission flags must agree. The same
  path serves `list-interfaces --cost`.

## Test contracts to preserve and transitions to make explicit

Already-owned suites (`zero_rc*`, owned records/payloads, transfer, borrowing,
explicit-copy, views, replacement, chunked tasks) retain their positive and
negative cases. Cache mode-isolation tests remain useful during C2; C3 replaces
RC execution controls with refusal/invalidation of frozen old identities.

`single_owner_test`'s ordinary-parser assertion and `zero_rc_test`'s distinction
between historical experimental selectors describe the opt-in rollout, not the
new default. C2 must assert normal checked ownership; C3 must assert retired
selector diagnostics. Single-owner snapshot sharing and hand-built retain/
uniqueness tests are active legacy contracts: migrate the supported value/result
behavior to explicit independent copies or an explicit unsupported-boundary
assertion. Do not keep an RC selection in a helper to make the gate pass.

Frozen original source/compiler comparisons remain historical evidence. Their
identities and outputs must stay available, but the current compiler need not
execute an old memory mode to preserve a historical measurement.

## Required staged verification

1. Before C2, run the source admission delta for the additional fixture roots and
   classify intentional negatives, explicit-copy migrations and production
   defects. Assign inline source fixtures to their current file owners.
2. On actual C2, run A10 normal-command matrices without flags, the all-export
   inventory, original 30 cases, expanded corpus and four application shapes in
   all five supported build configurations. Repeat owned negative/cache/session/
   doctest cases through installed commands and installed components.
3. Run focused CLI/source/emission suites, then the complete registered
   `verify_cache.py` coordinator and Guardian against frozen inputs. Focused
   passes and the first source diagnostic never replace the full gate.
4. During C3, remove the active RC selection/implementation from core test
   builders too. Audit IR, LLVM, runtime preprocessing, symbols and installed
   component manifests. Then repeat the complete gate and affected measurements
   using exact C3 artifacts; no earlier binary is relabeled.
