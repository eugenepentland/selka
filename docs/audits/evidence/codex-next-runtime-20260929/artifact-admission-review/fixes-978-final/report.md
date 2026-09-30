# Independent module admission fix verification

Final result: **8 passed, 0 skipped, 0 failed**. The direct Zig test process ran all eight selected cases; no cached verdict or broad gate/timing was used.

Source base: root `3fe434c988123753f915bdcc801304f547e6c4d2`. Applied module checkpoints `96b054808c6e9d0889d8ad23a1432d46d3943ff5` then `9789436dd14f1a515f0454961b70311c280bafdc` without committing/merging any shared branch. Root payload/blob correction `4fce2270df8b20a9b641da04b75e9318215ab8a2` is already in that base. Final `module_physical.zig` and `module_physical_inputs.zig` bytes exactly match 9789436d.

Verified cases:

1. Packed list payload plus blob authority rejects.
2. Incompatible return signatures reject for both dependency orders and against the original declaration.
3. Decoded function ID must identify its named archive body.
4. Correctly bound printing-helper control remains uncertifiable; forged ID rejects with emission enabled/disabled and in the dependency path, so it cannot hide the helper behind the readonly recursion exception.
5. Matching declarations with different inferred effects, inferred mutation, return origin, local ownership/usage/mutability/origin/spans and extra body scratch locals accept in both orders and against the original.
6. Parameter type/count, constant arguments, host presence and C ABI conflicts reject in both orders and against the original.
7. Fixed `Array[int,2]` parameter declarations `{}` versus declared mutation `{0}` reject in both orders and against the original. Reference-mut and writesParameter controls establish the caller-storage distinction.
8. Matching declared mutation `{0}` accepts despite different inferred mutation/local usage/mutability/spans and retains writesParameter in both orders and against the original.

Normalization inspection: retained declaration/ABI material includes return type, parameter count/types/names, constant arguments, declared mutation, C ABI, host presence, owner, restriction and conversion policy. It projects out physical markers, executable instructions, body-only locals, local ownership/usage/origin/mutability, inferred signature mutation/return-origin/write facts, source spans, and policy effects/effect bound. The latter effects projection is not a claim to validate source-level effect declarations; actual imported bodies remain responsible for recomputed physical proofs. The reviewed caller-storage omission is closed, and the tested valid duplicates remain accepted. Record default-expression node indexes are source-local; 978 projects them out of physical records while retaining field/layout data. No new actionable physical-authority defect was found in this narrow final verification.

Preserved evidence: original four-case fixture SHA256 `163bbc43a7f175282a72ba561795439d4d53d7076353222f16b7f443ef5852f7` and its failed logs remain byte-identical under `original/`. The intermediate seven-case failure (6 pass/1 fail), normalization snapshot and minimal qualifier repro remain under `fixes-96b-4fce-failing/`. Final fixture, normalization sources, pass log and machine receipt are under `fixes-978-final/`.

Command: `scripts/build-slot.sh build zig test src/review_runtime_contracts.zig --test-filter 'review:' --cache-dir .tmp/review-local`; TMPDIR `.tmp/review`, owned global cache `.tmp/review-global`. Guardian was not exercised by these standalone tests, so no new feedback entry is due. This receipt verifies the listed module-admission cases independently of native count width; it is not combined gate or performance acceptance.
