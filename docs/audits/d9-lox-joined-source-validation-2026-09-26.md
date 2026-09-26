# Joined Lox source validation, 2026-09-26

Composition `b8fdb39e` preserves the corrected assignment RHS behavior, scalar
instance/class readers, late closure publication and the indexed setter helper.
It is reconstructed from the corrected base port by `apply-lox.sh --optimized`;
all 26 `.my` files match the composed source byte for byte.

The frozen joined compiler is `91d1311e`, Debug, SHA
`d733b14aca8b25b0d4fb2d1becda50c98c2ab0f8cfac342e22a204bc58c9d82c`.
It combines scoped receiver pins with the independently reviewed indexed
payload-return proof. Both modes use that compiler: explicit value semantics,
and its unchanged legacy default with no flag.

| Check | Result |
| --- | --- |
| Port tests, value mode | 65 passed, zero cached |
| Port tests, legacy mode | 65 passed, zero cached |
| 13 scripts × both engines × both backends × both modes | 104/104 matched |
| Error traces × both backends × both modes | 184/184 matched |

The port tests use the native test runner's Debug guest default. The four
standalone smoke/trace executables use ReleaseFast; LLVM additionally uses O3
and full LTO. The trace
checks compare exact observations against the `60b668cf` binaries with native
GC stress enabled and exercise both settings of the Lox collector's stress
mode. The smoke checks use the pinned expected outputs. Builds and validation
run through the shared build-slot wrapper, with disk scratch. The compiler is
Debug throughout.

[Raw evidence](evidence/d9-lox-joined-source-validation.json.gz) contains source
and binary hashes, both uncached port-test logs, all smoke/trace logs and the
validation driver. Scratch is `.tmp-lox-perf/` in `d9-lox-source-perf`.
The integration at `b59cf06f` separately passes all four gates: 93/93 main
steps with 2,119 executed tests, QBE 51/51 with 428 tests, native-build 29/29
and formatting 2/2. Formal performance remains a separate acceptance criterion.
