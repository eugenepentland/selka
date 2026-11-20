# D9 WP-4: joined flat-loan and borrowed-loop diagnostic

Source `636524b81562e30285b15e297078fac24ffccb58` combines flat physical loans
`c0a5904a`, borrowed loops `3b867d50`, and the preceding plain-retain/projection/
loop slices. These exact-workload results remain far outside WP-4 acceptance.
No default, threshold, source input or accepted GC baseline changed.

## Immutable comparison

The joined Debug compiler is the parent's `install-flat-borrow-loops/bin/mylang`,
SHA256 `32e272cf75968d2fe913f636739d4b11d83701448e515f057dfa87f1ed8cba46`.
Accepted GC is the immutable f6 compiler, SHA256
`8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`.
The GC binaries and manifests are reused; the archive verifies 42 copied Lox,
schematic and provider source files against that baseline. The Lox program is
the unchanged VM binary_trees input at N10, not a reduced diagnostic. All three
schematic fixtures and provider data match the accepted inputs.

Actual QBE and LLVM O3/full-LTO production binaries run on CPU2, alternating
GC/RC order across three repetitions. Separate counting binaries verify owned
traffic; instrumentation is absent from measured binaries. All 48 production
samples report 100% hardware-counter running. Outputs match the exact expected
Lox text and schematic SVG hashes. These are median retired instructions:

| Input | Backend | Accepted GC | Joined RC | RC / GC |
| --- | --- | ---: | ---: | ---: |
| schematic fixture | QBE | 18,595,110 | 552,778,743 | 29.727103 |
| schematic changed-net | QBE | 18,603,699 | 549,930,411 | 29.560272 |
| schematic changed-value | QBE | 18,594,185 | 551,147,015 | 29.640827 |
| Lox VM binary_trees N10 | QBE | 7,243,231,888 | 851,383,851,938 | 117.541985 |
| schematic fixture | LLVM | 9,058,247 | 433,093,663 | 47.812084 |
| schematic changed-net | LLVM | 9,062,700 | 429,400,212 | 47.381047 |
| schematic changed-value | LLVM | 9,059,035 | 430,645,893 | 47.537723 |
| Lox VM binary_trees N10 | LLVM | 3,433,163,639 | 711,894,883,325 | 207.358273 |

All eight counted runs balance O, H and allocation/retirement. Lox counts match
across backends: 22,906,609 allocations and retirements, 311,200,831 O
acquisitions plus initial owners equal 334,107,440 releases, 736,227,500 H pairs,
1,095,889 clone shells and 20,836,904 uniqueness checks. The fixture/changed-value
schematic counts are 156 allocations/retirements, O 168,193/168,349 and H 343,278
pairs. Changed-net has O 168,165/168,321 and H 343,520 pairs. Each schematic has
one clone. No owner/hold count-limit refusal was recorded.

## Remaining dynamic cost

Sampling is separate from the matched measurements above. It executes the exact
production binaries and checks outputs again. Single schematic captures at a
100,003-instruction period produced only 33–38 samples; they are retained as
insufficient evidence. Corroborating captures repeat the unchanged schematic
process 100 times, checking each output, and use a 20,000,033-instruction period.
Lox captures run the entire unchanged N10 workload at both 1,000,003 and
20,000,033 periods.

The host's maximum sample rate is 1,000/s. Both period settings record throttle
events, with zero lost samples. The archive includes exact throttle counts and
headers. These profiles support qualitative attribution, not exact instruction
shares or acceptance measurements. The two full Lox periods agree on the large
costs: QBE `walk` about 24–25%, `visit` 15%, native unique inspection 11% and
descriptor lookup 10%; LLVM `walk` 26%, `visit` 18%, native unique inspection 12%
and `loan_pointer` 8%. The VM dispatch function itself is roughly 2% of samples.
Repeated schematic captures likewise put generic traversal, unique inspection
and metadata lookup near the top. Physical retain is visible directly and via
its `copy_many`/`retain_pointer` path, but these captures do not isolate the
dynamic fraction of retains whose layouts qualify for flattening.

The next bounded experiment is therefore the reviewed
[small physical-retain plan](d9-rc-flat-retain-plan-2026-09-27.md), followed by
matched measurements to establish its actual benefit. It reuses existing native
admission and preserves sequential failure traffic. It cannot remove generic
loans of Lox's large Runtime record containing a variant; that separate compiler
lifetime/projection audit belongs to the collections worker. No broad traversal
or ownership policy change follows from these profiles.

All commands, source/binary identities, build manifests, individual samples,
counter stderr, SVG verification, sampling records and repeat driver are in
[`experiments/d9-rc-flat-borrow-joined-20260927`](../../experiments/d9-rc-flat-borrow-joined-20260927/).
Only explicit `MYLANG_*` overrides are archived; inherited host environment
values are omitted. Raw perf data remains in the private measurement directory,
with paths and SHA256s in `sampling-metadata.json`.
