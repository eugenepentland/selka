# Combined reviewed text changes above integrated readiness and sort

The source base is7e7773e43c934e67e32db3205a9f867049f9b46a, the current
integrated readiness+rotation+join production. Apply only the reviewed runtime
and correctness deltas:52's separate floating parser frames,99's bounded short
comparison/original libc medium path/outlined long endpoint check and exported
always-inline wrapper,570's general64-byte scanner alignment. Existing join,
allocation/root, accounting/refusal and frozen reference policies stay intact.
No benchmark, canonical goal document or contract is edited by this candidate.

The independent source52 frame reduction, rejected99 large equality gain with
search blocker, and570's recovered search cost motivate this combination.
The function attribute also raises whole .text section alignment, so the
combined final code and placement must be inspected afresh. Kernel/register
or loop changes from equality inlining must be retained explicitly, without a
scanner-only causal claim. There is no timing/adoption claim at source commit.

Fresh native C checks cover five text/RC suites under -O3 ASan+UBSan, including
exported-body/function-pointer equality boundaries and every sole-byte mismatch,
exact allocation/unaligned views,31104 independent search slice outcomes, GC
views/index/dictionary roots, join and allocation/refusal semantics. Focused
Zig checks preserve scalar/octet integer/float grammar, signed bounds,
nonzero floating flags and untouched failure output. All builds use private
caches, disk TMPDIR and the reserved build-slot wrapper with at most two jobs.

The primary matched Debug control is accepted638, production-equivalent to7e:
/home/epentland/ai/canopy/mylang-worktrees/goal110-presize-ready-20261004/
.mylang-cache/goal110-presize-ready-debug/runner/manifest.json,
SHA b34888b317276dd7f274332c7d757196583ffc7e003b2f9efa10b0aeac7829bc.
It isolates these three text changes. Prior5a and570 artifacts remain static
context; they omit accepted sort/readiness and are not the primary control.
A source-pinned Debug host,24 actual RF guests, fresh correctness and final
code inspection precede coordinated six-arm search/join/bytes/equality/parse/
format at both sizes and matched638-to-combined checks.

All24 candidate guests and the accepted638 control remain live-verified. Fresh
checks retain384 exact text outcomes,12 refusal probes and4 identities. The
six-arm5r1w screen checks360 samples/720 qualifications; matched638 comparison
checks288 outcomes. An independent targeted15r3w repeat checks216 outcomes:
large equalityLLVM0.355919,QBE0.337863; large searchLLVM1.004706,QBE1.000684;
smalljoinLLVM1.055240,QBE1.042537 (LLVM226.7761 to239.3032ns). Smalljoin
remains open: its initial six-arm point1.118284 exceeds1.10.

All80 medium helper distributions pass: sampled ratios0.92782..1.04779, equal
median1.01278 and middle median1.01078. This portable cc-O3 no-LTO diagnostic
excludes guest ownership/code and is not RF acceptance. Native source/flags/
harness/binary receipts are preserved. No source changed after timing.

Actual LLVM scanner/index instructions remain identical to638; scanner entry
stays64-aligned. The kernel grows11984 to14135bytes, has no direct equality
wrapper calls and12 outlined long-helper calls. The search loop moves from
relative0xb00/mod64=0 to0xd80/mod64=16; numeric exports shrink to410bytes.
These code/placement changes prevent a scanner-only causal attribution.
Archive hashes/identities/raw results/commands are retained in evidence.json.
Smalljoin static review and normal RF validation remain outstanding.

The follow-up join-static-evidence.json retains the actual native join and
score helpers: identical normalized instructions,1229 and1668bytes. Join
entry mod64 stays16; score moves16 to48. Caller preserves six saved registers
and0x258 frame. Its timed outer loop moves mod64=48 to16, span793 to815bytes,
with156 instructions and41 stack-reference instructions in both. Checksum
stack accesses become register operations; no added frame/overall spill-count
burden or join algorithm/allocation/root/check work was found. Changed caller
code/placement and score placement remain possible causes, not proven ones.
