# Shared scanner alignment diagnostic

This isolated candidate starts from unintegrated parser source
52e6d0740da7e29a4bf95ad2e04e73c85dbfdf79. It adds a general aligned(64)
attribute only to myl_native_octets_find. Its search algorithm, candidate budget,
libc calls, load bounds, ABI, accounting and refusal behavior stay unchanged.
No benchmark source, contract or reference setting is changed.

Read-only Debug5a-to-Debug52 evidence in the parser worktree establishes
identical normalized instructions and relative offsets for the shared scanner,
index_walk and actual shared kernel. The scanner and timed caller loop move
from a 64-byte boundary to offset32, while index_walk moves in the other
direction. Multiple placements changed, so scanner alignment is a bounded
causal diagnostic rather than an established fix. Final ELF entry and loop
addresses must be recorded before any coordinated timing. A negative result
must remain evidence rather than justify arbitrary padding.

The native method suite adds an independent first-match oracle over31,104
exact-allocation slices:27 lengths0..4097 (including63/64/65,255/256/257 and
4095/4096/4097),9 needle widths0..32,8 offsets,4 haystack distributions and
4 needle positions/patterns. Distributions include repeated first octets,
late-only matches, embedded NUL and UTF-8 octets. Needle allocations are also
unaligned and end exactly at the payload. Existing text/index/view/dictionary
and RC suites retain scalar-index, GC/root, allocation/refusal and join checks.
Native builds use cc C11 -O3 with ASan+UBSan, two jobs, private disk TMPDIR and
scripts/build-slot.sh build.

No timing or adoption is claimed by this implementation commit. A source-bound
Debug compiler and actual LLVM O3/fullLTO/QBE guests will follow. Fresh text
checks include nearby search sizes; later quiet comparison uses exact52 and
Debug5a controls under coordinator authorization.

The official Debug host and all24 RF guests build. Five native sanitizer suites
pass; fresh guests retain192 exact text outcomes,6 refusal probes and2 identity
records. Invalid defaultCPU2 build-only affinity and seed0 argv attempts are
retained with their corrections; neither changes guest contracts.

Final ELF scanner remains772 bytes with identical normalized instructions and
entry mod64=0. The attribute raises whole .text alignment16 to64, moving its
start48 bytes. The unchanged kernel/index bodies also move, so this evaluates
the full placement change. A six-arm5r1w screen checks360 samples and720 fresh
qualifications. A same-plan three-artifact comparison checks432 outcomes.
LLVM570/52 large search=0.859573,570/5a=0.999352,52/5a=1.162615. The repeated
regression is reproduced and recovered in this session. LLVM570/5a parsing
=0.981410/0.987917,formatting=0.965964/0.969439; other controls range
0.971276..1.009330. QBE570/5a controls are all<=1.0300; QBE join is slower
than isolated52 but faster than accepted5a. This is exploratory Debug-host
evidence; no RF adoption or scanner-only cause is claimed. A fresh combined
text candidate on integrated63 must determine its own code/performance.
