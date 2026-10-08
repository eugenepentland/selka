# Bounded medium equality prototype

This separate source starts from accepted production6cf7bdce. Seventeen through
thirty-two octets compare complete first/last sixteen-byte blocks; thirty-three
through sixty-four compare complete first/last thirty-two-byte blocks. Overlap
covers every octet, including unaligned views ending at an allocation boundary.
Portable memcpy into integer arrays permits ordinary compiler vectorization.
The comparator preserves the short path, libc65..256 and outlined large path.
It avoids additional endpoint checks followed by the same libc comparison.

Focused GCC-O3 ASan+UBSan suites pass structural equality, allocation accounting,
text dictionaries, views and indexing. Existing exact-payload tests now cover
every byte length0..64 and every offset0..15, every mismatch position, exported
function-pointer calls and unchanged long boundaries. Another90,048 outcomes
cover valid two-, three- and four-octet Unicode scalars, owned/view combinations
and scalar differences at eighteen boundary lengths through257 octets.

Matched ZigLLVM-O3 fullLTO helper executables use the same defaultnative target
policy and private caches, without an ISA override. Actual linked code inlines
the comparator and uses bounded XMM/YMM loads/reductions for17..64, with libc
remaining for65..256. These native helper artifacts are exploratory: generated
guest code, layout and controls require a source-pinned official compiler build
after review. No guest performance or goal acceptance is claimed here.

The completed80-row paired screen covers17/32/33/64 owned/view ASCII/Unicode,
equal/early/middle/late differences, plus65/128/256/4096 negative controls using
equal/middle owned ASCII and Unicode views. It keeps all pilot, warmup and timed
checksums, status and process streams, fixed paired inputs, randomized arm order,
UTC/session identity and CPU2 timing locks. All322 pilot,160 warmup and800
measured invocations passed their checksum/status/stream checks. The10M-iteration
cap stopped427/800 measured invocations below the nominal30ms calibration target;
the minimum retained duration was19.83ms. This remains exploratory evidence.

| Byte length | Rows | Geometric mean after/before | Individual median ratios |
| --- | ---: | ---: | ---: |
| 17 | 16 | 0.6364 | 0.6092..0.6834 |
| 32 | 16 | 0.7863 | 0.6957..0.8452 |
| 33 | 16 | 0.8024 | 0.7055..0.8708 |
| 64 | 16 | 0.7621 | 0.7032..0.8643 |
| 65 | 4 | 1.0074 | 0.9862..1.0286 |
| 128 | 4 | 1.0315 | 1.0080..1.0534 |
| 256 | 4 | 0.9988 | 0.9887..1.0092 |
| 4096 | 4 | 1.0000 | 0.9850..1.0090 |

All64 affected median ratios improve;63 pointwise paired empirical-bootstrap95%
intervals lie below1.0. The64-byte equal owned/view cases improve16.9..25.8%,
and middle mismatches improve24.6..29.4%. Earlier portable GCC/noLTO scalar
endpoint diagnostics had64-byte equal view regressions near47%; the changed
compiler/control prevents an absolute or causal comparison. The historical
raw-archive hash and selected rows are retained in prior-scalar-context.json.

The128-byte middle ownedASCII control costs5.34% with pointwise interval
[1.03991,1.05617]; the viewUnicode control costs3.97% [1.02479,1.05403]. These
controls require the prepared independent15-round/3-warmup repeat alongside
64-byte equal/middle positive controls. Five-round pointwise intervals do not
cover between-session noise or multiple-comparison selection. No source or
helper changes follow these medians.

An official fresh ReleaseFast compiler receipt binds source3dcbe723 and all24
frozen guests. Fresh200 text checks and516 holdouts pass. Actual linked LLVM
code has bounded XMM/YMM comparisons in the timed17..64 equality path, with
bcmp retained only for65..256 and the outlined helper beyond256. The shared
text kernel grows14135 to15668 bytes and its frame grows0x258 to0x268;
instruction/layout interactions therefore remain part of the guest controls.
The scanner keeps its772-byte body and64-byte entry alignment; short join keeps
its1605-byte body. The native8-row15r3w repeat preserves the gains but confirms
a128-byte middle owned cost4.68% [1.04200,1.05310], view cost2.43%
[1.01240,1.03674]. Every pilot/warmup/timed stream and checksum is retained.

The six-arm guest5r1w screen passes360 samples and720 qualifications. Small
LLVM equality4.02140ns remains1.35326 times the current six-arm minimum. The
matched G4 comparison passes288 outcomes: small LLVM equality improves3.65%
[0.95177,0.99334], QBE26.94% [0.72424,0.73290], but LLVM large search costs5.64%
[1.03834,1.07565]. The candidate stays unintegrated, pending the prepared
independent15r3w small-equality/large-search repeat; no source changes follow
measurement. Other paired LLVM controls span0.99506..1.02146.

Read-only Rust/MyLang loop audit finds both still using constant-divisor
magic-multiply remainder. MyLang retains four additional negative-result
correction instructions, periteration list metadata loads and header/view
checks. These unchanged costs dilute the64-byte comparator gain; instruction
counts alone do not establish dynamic dominance. The frozen sources/binaries
and exact checksum loop excerpts are archived without modifying either port.
