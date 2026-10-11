# Native body parity corrections — 2026-10-11

Implementation: `aa152f8dde460855b7d6075013ce312c35e72a26`, based on
`2a1f92edc1c962bc03d628bb132e0d93aa475187`.

The native boundary rejected an authentic Selka byte-buffer iteration reply
because its iteration-guard validator excluded the mutable buffer identity.
The native checker already emits that guard for both ordinary iteration and
enumeration. The validator now admits the canonical buffer identity while
requiring a unit result and one signed 64-bit bound. New native graph tests
round-trip ordinary iteration and enumeration, and reject forged results,
bounds, arities, and scalar owners.

The focused runner passed all 23 reported tests: 21 buffer tests, the captured
producer reply replay, and its test-root entry. The original rejection and its
exact native stack trace remain in the evidence archive.

## Complete graph diagnosis

A temporary, isolated native probe loaded each captured project through the
native loader and checker. Before checking bodies, it required exact equality
between the complete native Input and the authentic captured request. It then
saved the native body outcome before entry adaptation and later passes.
All four Inputs matched. The native outcome frames retain the original
request identity and pass native reply validation.

| Capture | Complete outcome difference |
| --- | --- |
| Dynamic signed range | Hidden stride local declaration used binding span `52..53` instead of step span `69..73`. |
| Descending dynamic range | The same two declaration-span fields differed. |
| Dynamic unsigned range | Hidden stride declaration used `51..52` instead of `72..76`. |
| Enum-table copy and write | The producer omitted three checked enum-key nodes from the table initializer, shifting later node references and the function range. |

The three range outcomes have exactly two differing scalar fields each; their
nodes, statements, other function metadata, ranges, diagnostics, recipes, and
import observations match. The table result explains why a readable typed dump
and successful generated execution did not establish complete graph parity.
Producer corrections and their installed qualification belong to the numeric
and array-write workstreams. These diagnostic captures alone do not qualify
those corrected producers.

The probe's source and patch are archived. No probe hook remains in the native
checker. Its initial missing-link-object and missing-callback failures are also
retained, separately from the successful native captures.

## Gate repairs and fresh native host

The integrated `2a1f92edc` full gate exposed a synthetic record fixture missing
the array-shape field introduced by structural checking. Adding its absent
value restores the intended recursive-layout tests: all six pass normally and
with release facts and leak checks. The comparison donor is formatted, its
pinned inventory digest updated, and all four chain inventory self-tests pass.
The fresh native formatter checks all 1,080 live files with zero failures and
the existing 209 deliberate exclusions.

The CLI bootstrap shard passed its 43 tests but exceeded its declared memory
reservation: 3,181,240,320 bytes observed against 2.5 GiB reserved. The sharded
and unsharded CLI runners now reserve 4 GiB. Separately, earlyoom terminated
that gate's Core test compilation at 17:01:56 UTC. These findings require a
subsequent complete gate; this audit does not declare the integrated gate green.

Full Guardian verification passed all 88 checks. A fresh ReleaseFast native
installation from `aa152f8dd` completed all 14 build steps and verified all
seven packages:

- Prefix: `/home/epentland/ai/canopy/.selka-agent-cache/body-structural-b10/buffer-iteration-native-prefix`
- Native compiler SHA-256: `ebf066de525f1940504e4df600a33c9f1e7e0d5be746a94a665c1d5598a52cea`
- Coordinator SHA-256: `e9eca2d26a9ddbb541c1eea3e9dd6af55579a94bfe3759e3d41c351d4434c6b9`
- Qualified seed SHA-256: `c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`

The loop workstream uses this native compiler with its own genuine component
installation. The default package bundled with this native host contains the
earlier integrated producer.

The [evidence receipt](evidence/selka-native-body-parity-corrections-20261011/receipt.json)
binds every archived artifact and the fresh installation. Whole-language body
coverage, subsequent semantic ownership, backend and driver ownership,
stage-to-stage bootstrapping, and the 1.5× performance requirement remain open.
The broader gate log in this archive is explicitly a running snapshot; its
terminal result must be recorded separately.
