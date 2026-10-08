# P9 guarded bulk byte reduction prototype

This is an untimed compiler/runtime experiment. It recognizes a complete
canonical `for value in immutable_bytes: total += value ^ mask` or plain sum
from checked bytecode, without source/function-name patterns. The existing RC
read certificate first proves lifetime, physical quietness and stable storage;
the existing loop range guard proves the indices. Extra operations, interior
entry edges, mutable buffers, callbacks, aliased scalar storage and accounted
steps/frames refuse bulk replacement.

Additional guards require `0 <= mask <= 255`, a positive count no larger than
`MAX_I64 / 255`, and `seed <= MAX_I64 - count*255`. Every increment is then
nonnegative and every prefix sum fits signed i64. The runtime scans exactly the
certified range without allocation, callbacks or ownership traffic. It uses
SSE2 when the target supports it and a portable scalar path otherwise, with
short scalar tails. The compiler publishes the final sum, counter and raw last
element, then enters the original loop exit. A failed guard enters the original
checked loop at its header, preserving arithmetic trap details and effects.

`add_octets` and `xor_octets` now contain one bulk call; the indexed control is
unchanged. Before, scalar prerequisite and bulk SSA/assembly are retained here.
The actual QBE executable's O2 C helper and baseline x86_64 O2 object both show
XOR/SAD vector reduction. LLVM release uses O3/full LTO and inlines the helper;
`reduce-bulk-llvm.asm` retains the resulting vector instructions. The separate
O3 C-object assembly is labeled separately in `p9-byte-bulk.json`.

Validation: 17 focused Zig tests passed, including exact accounted/unaccounted
boundary outcomes, numeric guards, frame-accounting refusal and refusal after
every individual opcode mutation of the canonical body. The runtime matched
the scalar oracle for every mask and 16 alignments with short/vector/tail/long
lengths. Independent SSE2 and portable UBSan guarded-page scans each passed
266,752 length/mask cases with checksum 17702663040, including an empty null
range and every end alignment immediately before a protected page.

The standalone fast native source exits zero under both QBE and LLVM across
views, lengths 0..1041, byte/out-of-byte masks and MIN/high positive seeds.
Five QBE/LLVM overflow cases produce identical return codes, diagnostics and
prefix output. `byte-reduction-boundaries.py` reproduces those checks; receipts
record source/executable/tool hashes and build flags.

This prototype does not certify arbitrary reductions or indexed slice loops.
Its performance, including the effect on LLVM's existing vectorization, must
be decided by coordinated source/flag timing. No timing or parity claim is
made here.
