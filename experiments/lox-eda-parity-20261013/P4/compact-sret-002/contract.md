# Compact internal sret contract

Base compiler source commit: fbeba4eed7b549a3feef14c8b8dd620e41494139. Baseline compiler is the exact common-002 9bedb835 installation; its inputs manifest matches this checkout except the emitter prototype and coordinator's test registration.

Physical transport retains declared result and each non-in-out mut final in logical field order. Each retained field starts at its Module.alignment, and transport ends at a multiple of the maximum retained alignment. Large mut finals continue to update the original pointer. IR tuple types, field indices and offsets remain unchanged.

Direct, recursive, cross-unit declarations and indirect calls derive physical size/offsets from the same signature and InOutAbi. Function pointers remain opaque. External ABI and supported main entry adapters are unchanged. Compact tuples are unpacked into normal logical homes; whole readers additionally receive final in-out values. Whole-return tuples snapshot before updating argument homes to preserve overlapping final reads. Planner construction in logical `%ret` is disabled only for compact-return functions.

Ownership, borrowing, parameter order, noalias, error traces and bounds checks remain unchanged. No lifetime intrinsics or share_sret changes. Stage caches include compiler identity and native object caches include exact emitted LLVM; no object-format bump is required.

V1 omitted padding and is blocked, retained in ../compact-sret-001. V2 includes bool/u8/u16/u32 results paired with i64/float/managed bytes pointer finals, physical16B and offset8 emission assertions, and the required five explicit zero-RC modes plus RC controls.
