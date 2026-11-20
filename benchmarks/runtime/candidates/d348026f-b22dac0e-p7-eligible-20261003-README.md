The corrected P7 public eligibility witness improved with exact compiler/runtime
source `b22dac0ed3a2c0cc941328790f66a055a091ad41`, compared with its prior source
`d348026f52eb02792e8c0c1d07dae7f6c8e26bd7`. Both host compilers use independently
recorded Debug build receipts. All four guests use ReleaseFast; effective
backend manifests verify QBE and LLVM O3/full LTO. RF/Debug emitted guest
byte equivalence is not assumed.

The same committed MyLang/C sources and one shared C object are used on each
side, with separate guest caches. Source hashes are
`b0712cc25c1e254c97d414404c3228b84e9f927bdfc8cee65289d175847e7654` (MyLang) and
`2815fd2935246477b5398e115f787fb150e4de12f70f332533eabdd2894cbf07` (C).
The Host-only public entry reads independently supplied integer environment
inputs before the timer and has no retained argv/list input owners. The timed
input is `LOCAL_LIST_ITERATIONS=1000000`, `LOCAL_LIST_SEED=17`; the oracle is
101999913. Six iteration boundaries and three additional seeds qualify all
four guests (72 checks).

CPU2 measurements use the global timing flock, 15 randomized paired rounds
and three warmups (60 samples, 12 warmups). Independent replay passed all four
groups, checksum coverage, medians and bootstrap calculations. CPU3 averaged
4.37% busy, powersave was active, and no frequency warning was recorded;
average busy counters cannot exclude short interference.

| Backend | Before ns/call | After ns/call | After/before | Paired exploratory 95% interval |
|---|---:|---:|---:|---:|
| LLVM O3/LTO | 59.973780 | 22.570537 | 0.376340 | 0.361968–0.403073 |
| QBE | 78.205294 | 36.874141 | 0.471504 | 0.446186–0.505560 |

This is one isolated eligibility diagnostic, not an acceptance-row replacement
or independent confirmation of faster-than-reference performance. Intervals
are uncorrected for tuning and multiple comparisons. The original alloc_short
row remains open; this witness supports the eligible local-list mechanism.

Separate instrumented admission relinks each observed 999999 hot admissions
and one cold fallback at the same input. The QBE relink uses the exact timed
guest's recorded objects. The LLVM companion is separately built at O3,
ReleaseFast **without LTO**, because the timed LTO frame-map link deletes its
final scratch objects/receipt. Its result establishes admission for that
companion, not an exact relink of the timed LLVM binary. Both instrumented
guests passed the checksum and exact wrapper counter-line assertions; elapsed
values are omitted from their diagnostic receipt. The wrapper counts helper
admissions, not allocation, epoch or RC events. All four timed guest hashes
were unchanged afterward.

The archive retains the admission capture script, complete build commands/logs,
raw wrapper stdout/stderr, link and artifact hashes, source copies, and failed
validation log. An initial diagnostic validator rejected the expected wrapper
stderr; the corrected capture validates the exact counter line separately.
An earlier superseded P7 build passed `--qbe` after `--backend llvm`, which
changed the effective backend; that failed invocation is excluded and preserved
where available. The final P7 tool puts `--qbe` first and checks emitted backend
metadata. Neither failure is a guest semantic regression.

Exact timed JSON SHA256: `63dfd82939cf856f764cfd500699c11ac75bae5894d84c1b1f11a70d3a1dd990`.
Admission JSON SHA256: `bafd978be379b77bc092c55ac18f91dc20cfb8b57eece89fdfc213a6e5b00482`.
The gzip preserves the exact timed JSON; compiler receipts, source/object hashes,
backend/runtime-archive receipts, build commands, raw samples and round order
are embedded. Frozen ports, checksums, baseline measurements and 80 targets are
unchanged. Cross-language common-ISA timing is not established by this witness.
