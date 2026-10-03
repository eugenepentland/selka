This archive binds the final ReleaseFast compiler and guests to exact source
`730a86e62b47c922dc1411d24b5868c3bd2132f3`. Compiler SHA256:
`579856466e5d30e77887c9435fd2eb07af82b84792905d78cd926a004cd6eaa3`.
The receipt records source hashes before/after, installed runtime/QBE assets,
private Zig/cache/TMPDIR, ReleaseFast host mode, compiler-only build, `-j2`,
build-slot wrapper and complete build streams. The observed build interval
includes cache state and slot/load effects; it is not comparative compiler speed.
Guest build logs record commands/status/streams, but do not measure compile time.
Sixteen reference binaries were reused only after their original source/tool
and executable hashes verified; their reuse is not a new build measurement.

All eight emitted native backend manifests verify the effective backend,
LLVM O3/full LTO or QBE, and native runtime archive hash. Same-source Debug and
ReleaseFast host builds produce byte-identical LLVM guests for all four groups;
all four QBE executable hashes differ. No general guest-equivalence claim is
made from this result. Final acceptance and independent confirmation use the
ReleaseFast guests.

The actual published final QBE compute IL is 510,140 bytes with SHA256
`1e3b75fa69d1d46395a1cdb4cff088ba9cfd282adcad967e10dc804f6076f51d`.
Its bound cache manifest has no loop-unswitch marker and no specialized-entry
label. The corrected fixture admits no P2 specialization; the safe capability
and compute performance gap remain. The prior 12-copy prototype is superseded.
Whole-function QBE entry: 43,823 bytes, 9,429 static instructions, 2,366 stack
references, 2,968-byte frame. LLVM entry: 20,050 bytes, 4,148 instructions,
728-byte frame. These include untaken paths and runtime glue and are not
executed kernel costs or causal shares. Assembly/IL, commands, symbol sizes,
binary/manifest hashes and explicit scope limitations are preserved.

This build/static archive contains no accepted timing result. The complete
six-arm timing capture and independent confirmation are separate artifacts.
Original checksum contracts, source ports and exact 80 frozen targets remain
unchanged. All-arm common-ISA timing remains unestablished.
