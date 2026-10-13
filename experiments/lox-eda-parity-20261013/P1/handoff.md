# P1 heap mutation and fresh construction

Base: `2525a66f61838086f5327d74db7412926ce4a221`.
Compiler: `/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang`.
SHA256: `2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329`.

Changes underway:
- `reserve_object` centralizes original GC charging, collection, free-slot choice and allocation counters.
- `allocate_instance`, `allocate_class`, and `allocate_env` publish fresh payloads directly rather than cloning constructor results in `allocate`.
- `set_instance_field`, `set_class_method`, and `inherit_class_methods` provide scoped caller APIs and currently retain one payload snapshot. This is a reduction, not elimination, of mutation snapshots.
- Public `allocate` and owned payload snapshot APIs retain independent-copy contracts.
- `p1_heap_test.my` exercises fresh constructors with GC stress, exact accounting, stable handles, snapshot independence and alias-visible writes.

Ownership probes:
- `bound-owner-extraction-refusal.my`: `dict.pop` to local owner followed by enum match rejects `E_SINGLE_OWNER_OVERLAP` at `mut updated = payload`.
- `allocate-probe.my`: storing an ordinary `Obj` parameter without `.copy()` rejects `E_SINGLE_OWNER_BORROW`; ordinary parameters borrow.
- `extraction-probe.my`: direct fresh `match objects.pop(index)` under qualification; dictionary representation remains a probe only. Candidate `Runtime.objects` stays `Obj[]`.
- Requested bounded owned exchange API from coordinator: immediate match on exchange old element, free placeholder installed before return, mutate owned fresh payload, restore same stable index. No collection may occur while extracted.

Commands (run in P1 worktree after sourcing `/home/epentland/.config/mylang/dev-env.sh`; `TMPDIR=$PWD/.tmp/lox-eda-parity/P1/tmp`, private caches, shared slots):

```sh
scripts/build-slot.sh build "$compiler" build experiments/lox-eda-parity-20261013/P1/extraction-probe.my -o .tmp/lox-eda-parity/P1/extraction-probe --experimental-zero-rc --release --counters --cache-dir .tmp/lox-eda-parity/P1/caches/probe
scripts/build-slot.sh build "$compiler" test experiments/lox-eda-parity-20261013/source/lox --experimental-zero-rc --release --force --cache-dir .tmp/lox-eda-parity/P1/caches/core
scripts/build-slot.sh build "$compiler" build .tmp/lox-eda-parity/P1/probe-source/p1_allocation_probe.my -o .tmp/lox-eda-parity/P1/allocation-probe --experimental-zero-rc --release --counters --cache-dir .tmp/lox-eda-parity/P1/caches/allocation
```

`--force` is accepted for `test`, not `build` (first build invocation with it printed usage and was retried without it). Raw logs/counters and qualification results will be appended after admitted jobs finish. The allocation probe compares 100 fresh width1024 environments against public snapshot allocation; it is reduced allocation evidence, not a 60-case performance result.

Qualification progress:
- Direct fresh dictionary-pop match BUILD PASSED with the pinned compiler. This qualifies payload transfer syntax only; runtime/counters remain queued. No dictionary representation change was adopted.
- First fallback suite (raw `fallback-first-tests.log`) exposed `E_SINGLE_OWNER_OVERLAP` while writing `rt.objects[ref]` inside a borrowed match. Corrected `set_instance_field` by returning its independent snapshot from internal `instance_snapshot` and publishing outside that borrow scope. P2/P4 refreshed their local API copy.
- `set_class_methods` and `set_instance_fields` now query only the scalar name/class and independently copy the supplied replacement table; they do not snapshot the previous payload.

P2 coordinated query patch (reservation returned to P1): `function_instruction`, `function_line`, and `function_constant` now put wrong-kind assertions after the match rather than in the wildcard arm. The same assertion and fallback remain; this avoids duplicating cold assertion sites for every unmatched enum variant and enables smaller hot query bodies. P2 provided the exact three function patch; no other P2 files are included in P1 source ownership.

Direct fresh extraction runtime qualification PASSED:
- `extraction-run.stdout`: live 2, snapshot 1.
- Raw `extraction-counters.json`: allocations 4 / frees 4, allocated/free bytes 576, live bytes at exit0, list copies1/8bytes and dict copies 1 / 32 bytes (the explicit saved snapshot), runtime retain/release 0, shared retain/release 0. Setter was inlined, so no per-setter row is asserted.
- Command: `scripts/build-slot.sh build env MYLANG_COUNTERS="$PWD/experiments/lox-eda-parity-20261013/P1/extraction-counters.json" .tmp/lox-eda-parity/P1/extraction-probe`.

Second fallback suite:75 existing tests PASSED; P1 test compile failed because `heap.string_hash(rt,name)` borrowed runtime after the earlier `mut rt` argument to a setter. Hoisted the scalar hash before both mutable calls. Raw `fallback-second-tests.log` preserves the failure; final suite rerun queued. This was test call ordering, not a runtime API failure.

Fresh environment construction allocation counter probe PASSED (100 environments, 1024 slots; raw arm counters and allocation-summary.json):

| arm | allocations | allocated bytes | list copies | copied bytes |
|---|---:|---:|---:|---:|
| fresh |131|1,651,544|2|63|
| public snapshot allocation |232|3,297,240|102|1,638,463|

Per-helper evidence isolates the change from setup: `heap::allocate`100 calls adds100 allocations/1,645,600bytes and100 list copies/1,638,400copied bytes; `heap::allocate_env`100 calls adds0 allocations and0 list copies. `object::new_env`100 calls/100 allocations is identical in both arms. The snapshot arm also has one extra command-line argument allocation; no claim attributes that setup difference to the helper. Both arms print `100 True`, retain/release 0, and live bytes at exit0. These are reduced allocation counters, not timing or full 60-case parity.

Exact run: `scripts/build-slot.sh build python3 experiments/lox-eda-parity-20261013/P1/run-allocation-probe.py .tmp/lox-eda-parity/P1/allocation-probe`; raw build/run logs are preserved. Staging copies the candidate `.my` modules into `.tmp/lox-eda-parity/P1/probe-source/` and the checked-in allocation-probe to `p1_allocation_probe.my` for relative imports.

Constructor domain correction after the positive-width counter run: existing `object.new_env` with negative slot count creates an empty row, so `allocate_env` charges32+16*max(slot count,0) rather than charging negative slots. The final suite includes a regression for this contract. Positive-width reduced counters were obtained before that clamp; `allocation-build-input-sha256.json` records the exact measured heap input reconstructed by reverting that one subsequent clamp, plus imported-source/compiler/binary hashes. No claim presents the clamp as separately counter-measured.

Final fallback qualification PASSED: **82 passed,0 cached,0 failed,0 skipped**, using the pinned compiler, checked zero RC, release, force and private cache. This includes all75 existing cases plus7 P1 regressions. Exact final source hashes are in `fallback-source-sha256.json`; raw successful suite output is in `fallback-final-tests.log`. Positive-width allocation counters and direct fresh-extraction probe both passed as recorded above. The constructor/scoped-helper/cold-query fallback is ready for integration; eliminating the remaining payload snapshots remains a separate checked-exchange change after compiler qualification.

No compiler source, historical experiment source/reports, peer-owned caller files, or Guardian feedback log was changed by P1.

Fallback implementation/evidence commit: `fef914d0d774a25586499dece4c42a014172ba53`. The normal Guardian hook passed88 checks (raw `fallback-commit.log`, copied after the implementation commit). No feedback-log write was made. Checked-exchange work starts from this preserved fallback commit.

# Separate checked-exchange candidate (green002 evidence; final qualification pending)

Compiler installation: `/home/epentland/ai/canopy/mylang-lox-eda-parity-20261013-p7/.tmp/lox-eda-parity/P7/green-install-002/bin/mylang`.
SHA256: `d51abcb0b2cefc6922e4a90afbf0822ecfe01151f8c7e1b89fdb82481b0b3273`.
The entire immutable prefix includes bin/libexec/tools. The first three queued jobs targeting mutable `/P7/install` were cancelled before admission, only P1's wrappers were stopped, and their queue logs were preserved. No mixed-prefix result is counted.

`set_instance_field`, `set_class_method`, and `set_env_slot` now immediately match the owned result of `rt.objects.exchange(ref, object.Obj.free)`, mutate the transferred payload and restore the same stable slot. Handle bounds, expected kind and environment index bounds are validated before extraction. There is no Lox allocation/collection, callback or return while the placeholder is active. Returns follow restoration; wrong-kind assertions are outside the match to avoid duplicating cold sites. `inherit_class_methods` validates both classes, treats self inheritance as a semantic no-op, extracts the child and borrows the parent table only into the independent local child methods, then restores the child before returning. Public snapshot accessors and replacement-table contracts retain independent copies.

Green002 full candidate suite **84 passed,0 cached,0 failed,0 skipped** (`exchange-tests-green002.log`). It includes the prior82 tests plus self inheritance/snapshot and negative environment index/snapshot regressions. Both counted probes compiled successfully (`mutation-build-green002.log`, `mutation-failure-build-green002.log`). Exact compiler/imported-source/binary hashes: `exchange-input-sha256-green002.json`.

Reduced mutation evidence:100 writes each to the environment, instance and class, starting with1024 populated table keys and1024 environment slots. Both arms share owned setup; the snapshot arm reproduces the preserved fallback one-snapshot setters. Raw counters and selected per-function evidence are in `mutation-*-counters.json` and `mutation-summary.json`.

| arm | allocations | allocated bytes | list copies | copied bytes |
|---|---:|---:|---:|---:|
| checked owned exchange |5,181|747,632|0|0|
| snapshot fallback |5,482|15,514,928|300|14,745,600|

The owned setter counter rows report0 copies/0 allocations across1,124 instance writes,1,124 class writes and100 environment writes, including the common setup writes. In the snapshot arm, the instance snapshot and class/environment snapshot accessors each perform100 full array copies:6,553,600 bytes each for instance/class tables and1,638,400 bytes for environment slots. Overall totals include setup and an extra command-line argument allocation in the snapshot arm; no claim treats every allocation difference as helper traffic. Both arms print `True True True`, have retain/release0 and live bytes at exit0. This is reduced allocation evidence, not runtime timing or full60-case parity.

All9 invalid-input subprocess checks passed with exit1 and the expected pre-extraction validation message: negative/high handle, wrong instance/class/env kind, positive/negative out-of-bounds environment index, and wrong inheritance parent/child kind. Exact stdout/stderr/counters and summary are retained in `failure-*` and `mutation-failure-summary.json`. Fatal assertions terminate before normal scope cleanup and each reports269,344 setup bytes live at process exit; no zero-live or unwound-cleanup claim is made for those fatal failures. These failures occur before any payload is removed, so no placeholder or transferred payload exists when they terminate. Normal paths and Lox error behavior remain covered by the full suite.

Commands, with the compiler above, private P1 caches/TMPDIR and shared build slots:

```sh
scripts/build-slot.sh build "$compiler" test experiments/lox-eda-parity-20261013/source/lox --experimental-zero-rc --release --force --cache-dir .tmp/lox-eda-parity/P1/caches/exchange-core
scripts/build-slot.sh build "$compiler" build .tmp/lox-eda-parity/P1/exchange-probe-source/p1_mutation_probe.my -o .tmp/lox-eda-parity/P1/mutation-probe --experimental-zero-rc --release --counters --cache-dir .tmp/lox-eda-parity/P1/caches/mutation
scripts/build-slot.sh build "$compiler" build .tmp/lox-eda-parity/P1/exchange-probe-source/p1_mutation_failure_probe.my -o .tmp/lox-eda-parity/P1/mutation-failure-probe --experimental-zero-rc --release --counters --cache-dir .tmp/lox-eda-parity/P1/caches/mutation-failure
scripts/build-slot.sh build python3 experiments/lox-eda-parity-20261013/P1/run-mutation-probes.py .tmp/lox-eda-parity/P1/mutation-probe .tmp/lox-eda-parity/P1/mutation-failure-probe
```

**Integration dependency: the final P7 compiler must finish its cleanup-matching and explicit-route qualification. Full integrated tests and counters must repeat on that final compiler. These green002 results are prototype evidence, not final compiler qualification or a60-case benchmark result.** The coordinator requested committing the source and honest green002 evidence now to prepare the common candidate; final integration qualification remains pending.

Exchange implementation/green002 evidence commit: `b0d6034c8617b32f7f8ff799ab54f9b3080c81bc`. The normal Guardian hook passed88 checks (`exchange-commit.log`, copied after the implementation commit). The worktree was clean after that commit. This receipt does not change the explicit pending final-compiler/integrated qualification above. No Guardian feedback log was written.
