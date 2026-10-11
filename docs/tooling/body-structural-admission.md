# Structural body admission candidate

`selfhost/tests/run_body_structural_admission.py` selects 30 immutable inputs:
22 successful tuple/fixed-array/enum-table programs and 8 exact source errors.
It preserves the original 12 array controls and the original collection-extension
`dictionary_generator_pairs` input byte for byte. Each successful program checks,
dumps typed output, and runs in release with fact verification and leak checking.
Native reference controls execute 74 operations; installed schema10 admission must
execute 222 across reference, shadow and component modes and verify the seed receipt.
Historical native controls cannot satisfy selected admission.

The frozen schema8 cf2 native host passed all 74 operations with zero failed and
zero skipped; exact identities, outputs and source digests are retained in
`docs/audits/evidence/selka-structural-native-20261011/native.json`.
Schema10 installed selected admission remains pending.

`run_body_structural_hostile.py` prepares 13 request-bound tuple/fixed-array typed
reply mutations. It binds inferred tuple recipes, positional tuple fields, array
literal shape, index types, replacement types/values, mutable root assignment and
cross-function operands, requiring exact ComponentProtocol rejection for each.
This harness is not yet qualified against an authentic schema10 installed capture.
Array recipe mutation cases are intentionally outside this installed inventory:
the authentic historical request retains constructor array Type22 `[2]i64` with
element Type0, length2 and null enum key inside catalog.records.shape.array.
There is no inferred tuple record in that initial catalog.
The authentic schema8 request for the hostile source was captured and its selected
producer returned ComponentProfile; that historical refusal proves no schema10
support and supplies no fabricated successful reply.

Run all commands through `scripts/build-slot.sh build`, with an isolated disk
TMPDIR and Zig local cache. No timing or compiler/bootstrap claim follows from
these controls.

Synthetic construction selftests build a realistic two-function tuple/fixed-array
reply graph with a same-type readonly snapshot. Every one of the 13 mutations
changes exactly its intended single row field; all other rows, node order and
function ownership remain identical. Missing tuple authority, a wrong-type
readonly candidate and a non-element assignment are rejected before mutation.
These synthetic tests supply no authentic capture or runtime rejection evidence.
Nine structural harness unit checks pass (five inventory checks, four construction
checks); genuine schema10 installed hostile verdicts remain pending.
