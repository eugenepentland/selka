# Managed memory-phi initialization proof

The original record LLVM allocates an uninitialized 40-byte phi slot and skips
its entry undef operand, then releases four pointer fields on the zero-trip
exit. The isolated comparison changes only a zero-global plus one 40-byte copy
on b0->b1; every runtime/program phase uses pinned Zig, normal build slots and
fresh local/global native caches. Runtime source bytes are archived separately.

| LLVM | target | native status |
| --- | --- | --- |
| original | x86_64-linux-gnu.2.31 | 232 |
| zeroed entry | x86_64-linux-gnu.2.31 | 0 |
| original | default | 0 |
| zeroed entry | default | 0 |

All compile/link phases succeeded. Per-case receipt.json captures exact argv,
status and wall time including slot admission; separate stdout/stderr files
retain every phase and native execution. These are correctness reducers, not
performance gates. LLVM/native/runtime hashes are in artifact-manifest.json.
Native caches, objects and binaries are retained on disk without being staged.

The fix preserves unspecified unmanaged undef and initializes only managed
memory operands through existing undefValue zero semantics. Staged phi copies
are unchanged. managed-undef-phi.patch records the formatted three-file change
subsequently committed as ebb4cf2826f9148c591a3bb051a7fe15cacd1539.

Fresh focused04 passed 3 tests: four inherited zero-trip native cases, two new
parallel-record-swap native cases (output 7 and no leaks), and a verified emitted
unmanaged memory-phi case with no poison-address copy. Whole Guardian04 passed
88 checks. ../undef-phi-qualification-04.json proves exact pre/post hashes of all
nine combined source inputs were unchanged; IR remained frozen. Focus03 was
green but overlapped a disjoint naming correction and remains supplemental;
Guardian03's runner error-path findings are retained. Final combined package
gates remain required.
