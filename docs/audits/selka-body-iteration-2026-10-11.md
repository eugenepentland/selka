# Selka statement iteration, 11 October 2026

The body producer now lowers numeric fixed-array iteration, enumeration and tuple
bindings, managed sequence bindings, and the native reversed/zip prelude forms.
Native local order, single evaluation, source snapshots on root rebinding, live
refresh after writes/growth, tuple field extraction, counters and byte promotion
are preserved. List[DictItem] pair bindings use their retained record authority.
Enum tables and unsupported reversed/zip owners retain exact native diagnostics.
Diagnostic serialization now uses UTF-8, including native tuple arity messages.

The strict installed schema10 selection passed 30 fixtures and 228 operations
across reference, shadow and component modes, with zero failures or skips.
The 23 successes additionally compare typed dumps and run generated release
programs with fact verification and leak checks. Shadow's full canonical native
batch/catalog comparison remains the primary graph oracle. Seven diagnostics
retain exact native precedence and repair text. Five supplemental authentic
request/reply captures passed for array enumeration, tuple root rebinding,
DictItem pairs, byte-buffer enumeration and zip over text.

The isolated source base is `f47c2d72f6105123fc3dcd1800bce12525071bb3`.
The final body package key is
`081bddfe70ea5238c22916775ba7cbe0985b82ac30aa964c5d437bb7913cfed2`,
artifact SHA256
`de77e0a536589145aad81a40593789733a0b93ddee42697dd07a035c9216a1ba`.
The corrected native host SHA256 is
`ebf066de525f1940504e4df600a33c9f1e7e0d5be746a94a665c1d5598a52cea`,
built from native donor `aa152f8dd`. Its coordinator SHA256 is
`e9eca2d26a9ddbb541c1eea3e9dd6af55579a94bfe3759e3d41c351d4434c6b9`.
The authentic seed receipt remains
`c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`.

[Evidence](evidence/selka-body-iteration-20261011/receipt.json) archives exact
final producer source snapshot, all three authentic package receipts,
unmodified captured frames and complete raw verdicts. Earlier producer source
snapshots are unavailable because the coordinator removed its temporary build
sources; their authentic binary identities and verdicts remain. The original selected
23 fixtures remain; seven added cases cover tuple-target root rebinding,
DictItem pair bindings, growth, live zip/reversed writes and enum-table refusal.

The first genuine 69-check proof had 59 matches and ten selected failures.
Corrections addressed duplicate binding diagnostic order, UTF-8 diagnostics and
text length typing. The second genuine proof had 67 matches and two byte-buffer
failures. Native replay decoded the authentic exchange and located the rejection
at `body_check_buffer_validate.zig:72`: mutable byte-buffer iteration guards were
rejected despite native lowering emitting them. The parent's native correction
passed 23 selected native tests, including a genuine roundtrip and four forged
result/bound/arity/owner refusals. Historical failures remain archived; no frame
headers were edited. A preliminary private-cache seed discovery failure was
resolved by reusing the unchanged qualified seed authority.

Pure tests passed 17 in each of Debug and release with facts/leaks: three sequence
allocation tests, one UTF-8 diagnostic test and 13 existing list iteration tests.
Main source checking, seven reachable formatter checks and four strict inventory
Python tests passed. The commit command runs the whole Guardian gate.

Reproduce with the pinned Zig, corrected native host and explicit fresh package:

```sh
scripts/build-slot.sh build python3 selfhost/tests/run_body_iteration_admission.py \
  --compiler CORRECTED_NATIVE10_HOST --builder AUTHENTIC10_COORDINATOR \
  --component-dir INSTALLED_LOOP_COMPONENTS --source-root ISOLATED_SOURCE \
  --zig PINNED_ZIG --release --report PRIVATE_REPORT
```

Fixed-array comprehensions and further generator coverage follow separately.
This result does not establish complete compiler bootstrap, whole-language
closure or the requested 1.5x performance objective.
