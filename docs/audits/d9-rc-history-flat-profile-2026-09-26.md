# ABI3 corpus checkpoint and nbody profile

The immutable cumulative `19e16e1d` Debug compiler builds all 58 native binaries
for the required 43-program-per-backend corpus. All 60 parity and schematic output
checks pass. The first Lox check, QBE binary trees at the required size 10, times
out at 600 seconds. The owned driver and its next LLVM child were then stopped;
the remaining 25 checks are interrupted or unrun. No instruction/RSS acceptance
run was started. This checkpoint is negative performance evidence, not a completed
corpus gate. The accepted GC compiler and all 58 GC binaries retain their hashes.

The [archive](../../experiments/d9-rc-history-flat-profile-20260926/README.md)
contains original build/check manifests, input hashes, exact commands and the
stop receipt. The corpus sources are fixed at `a1efa5f6`; the compiler is fixed at
`19e16e1d`, SHA-256
`1b705d90e58c6b2b3799c5cbe79da9adbc57913e4c72ebbfa2b54dad044c1bbe`.
Every original output expectation remains unchanged.

## Five-second nbody sample

A five-second instruction sample was taken while the actual full nbody QBE output
check was running. Its 5,016 leaf samples have total weighted period 501,600,000;
the recording reports no lost samples. The original stripped program and a
symbol-preserving build from the identical compiler/source have identical `.text`
bytes and virtual addresses. The decoder uses exact symbol extents and only the
leaf PC, so the percentages are self time and do not double-count call stacks.

| Function | Sampled instruction share |
|---|---:|
| generated `advance` | 13.52% |
| `myl_rc_shape_resolve` | 10.29% |
| `myl_rc_native_retain_replace` | 7.95% |
| `myl_rc_descriptor_find` | 7.44% |
| `myl_rc_native_has_unique` | 5.68% |
| external/unresolved | 4.94% |
| `memcpy` | 4.39% |
| `myl_rc_loan_copy` | 3.49% |
| generic `walk` | 3.37% |
| `myl_rc_value_seed` | 3.33% |
| `myl_rc_drain` | 3.29% |
| `myl_rc_meta_free` | 3.25% |

The source uses a plain record containing seven floats. The profile motivates
auditing needless ownership reflection during record updates and private list
captures; it does not establish a full-program instruction ratio. A separate
single accepted-GC diagnostic run prints the exact expected two lines and counts
32,990,207,453 instructions on CPU 2. It is not a median-three acceptance result.

## Artifact caveat

The diagnostic `objcopy --dump-section` invocation omitted a separate output
binary and rewrote ELF metadata in the inspected nbody file. Its full-file hash
therefore differs from the original build manifest, which is preserved unchanged.
An independent rebuild reproduces the original manifest hash exactly. Direct ELF
parsing verifies that every allocatable section of that rebuilt binary equals
the inspected file, including `.text` bytes and addresses. The archive records
both hashes, the reconstruction command and section-level evidence. The rewritten
artifact must not be reused for an acceptance run. This limitation does not affect
the original timeout receipt or the sampled instruction-address attribution.
