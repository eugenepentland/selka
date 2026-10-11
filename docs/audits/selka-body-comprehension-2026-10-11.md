# Selka comprehensions and generator folds, 11 October 2026

The schema10 body producer now lowers fixed-array comprehensions and generators,
including filtering, enumeration, tuple bindings and nested sources. Managed
list/text/reversed/zip paths retain their existing lowering. Scalar generator
consumers `sum`, `min`, `max`, `any` and `all` preserve native local order,
single evaluation, inferred integer widths and float operations. Early boolean
settlement exits the outer generator loop. Text joins accept a generated list;
min/max retain their native empty-input assertion. Mutating yielded expressions
refresh managed source authority. Native restrictions and diagnostics remain.
The ordinary sequence builtin implementation is a separate workstream.

The final genuine installed proof passed all 36 selected fixtures and 294
operations across native reference, shadow and component modes: 31 successful
sources and five exact diagnostic sources, with zero failures or skips. Full
canonical batch/catalog comparison in shadow remains the primary graph oracle;
exact typed dumps supplement it. Every successful source also ran its generated
release program with fact verification and leak checks, producing exactly status
7, stdout `7\n`, and empty stderr. Original selected cases were preserved.

The original statement selection passed again against this package and corrected
host: 30 fixtures, 228 operations, zero failures and skips. Seven additional
accepted authentic request/reply captures cover fixed tuple pairs, nested arrays,
dictionary pair bindings, floats, exact short circuiting, joins and mutation.
A separate nine-operation native/shadow/component proof passed the unchanged
original `body_collection_extensions/dictionary_generator_pairs.input`, including
full typed comparison and generated release/facts/leak behavior. These groups
remain separately counted.

Producer code commit `fbcb3f665d55c032a7ba8ae66cf43aa48d2f4573` has parent
`358e187a9db4227ae340769e874b81ba711dd497`. The frozen body package key is
`8c8a9ba7faf5260b29e948490b33390853f1d8d1276a9cab232ebf4e5c070e24`,
artifact SHA256
`d0a43425c0c7cea795e8233d815f62a270e3727662673a0f33f9c78d6ca6800f`.
The corrected native host, built from `93a4f2bc8562b61501cb486a4b6de251e2598fca`,
has SHA256
`4ce5f9ab80f5829973aceed8645b1edb122af048348a1ca62d3e4cb968cce5fc`.
Its coordinator SHA256 is
`d0ea4c4afa0ffa9c48162f182c9bc72c7d2cd968bacb1dbb4181514ef39781ab`.
The unchanged qualified seed SHA256 remains
`c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`.

The final pure tests passed 28 per guest mode: two fixed-array lowering tests,
three scalar gather tests, ten existing collection comprehension tests and
thirteen existing iteration tests. Both Debug and release with facts/leaks
passed, without failures or skips. The native main check and seven touched source
format checks passed; four Python closed-inventory harness tests passed.
Whole-tree Guardian passed all 88 checks. No Guardian feedback log was edited.

The authentic failure sequence is retained. The first installed proof stopped
after 62 operations at the unimplemented scalar generator profile. The second
stopped after 89 operations at a join shadow mismatch: the producer consulted a
nominal-only catalog subset and rejected the storable string element. Complete
materialized catalog authority corrected that diagnostic. The next proof stopped
after 179 operations at a float shadow graph mismatch: generic numeric lowering
allocated two operand spill locals per fold. Direct float lowering and a focused
no-extra-local regression corrected the graph.

The frozen direct-float package then stopped after 193 operations in native
reference runtime compilation: nested `any` generated malformed LLVM PHIs.
The same source reproduced an invalid optimized Core edge before emission.
The separate native correction audit, `selka-native-nested-gather-2026-10-11.md`
in evidence commit `4e8c501dd`,
records the region-cloning fix, regression, install and intentional stopped
Guardian commit-helper run. The producer package stayed unchanged during the
corrected-host 294-operation replay.

A supplemental pre-direct checker replay completed 108 operations with one
float mismatch. An accidental earlier replay used the old statement package and
recorded 60 mismatches in 108 operations; it remains labeled with its real
package identity and is not qualification. The separate original dictionary
helper initially failed setup before executing any operation; the corrected
helper's nine successful operations are separately archived. Failed captures,
raw diagnostics, package metadata and verdicts were never relabeled as success.

[Evidence receipt](evidence/selka-body-comprehension-20261011/receipt.json)
binds complete raw verdicts, all four installed package metadata sets, final
source snapshot, authentic unchanged frames, historical join/float frames, pure
logs and helper scripts to exact byte hashes. Earlier producer source snapshots
are unavailable after coordinator temporary-source cleanup; their package
identities and actual receipts remain. The final snapshot contains the exact
committed producer sources, and the capture artifacts match the frozen binary.

This is selected installed body capability qualification. Full self-hosting,
complete compiler bootstrap and the requested at-most-1.5x native Zig performance
remain unqualified by this evidence.
