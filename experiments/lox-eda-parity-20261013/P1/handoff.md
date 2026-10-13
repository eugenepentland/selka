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
