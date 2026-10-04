# Equality inline-linkage revision

This separate source starts at `1c367e95`, which retained the original libc
comparison from17through256 bytes but still emitted hot LLVM equality calls.
The runtime's existing public `inline __attribute__((always_inline))`
convention is applied to the bounded common wrapper. The prior non-inline
header declaration keeps an exported C definition. A volatile function-pointer
probe across the existing separate C translation units checks address-taking
and the exported body at every payload boundary and sole mismatch position.
The long endpoint helper remains noinline. Join and all contracts are unchanged.

No performance benefit, generated-code result or integration is claimed by
the implementation alone. Source-pinned native checks, guest receipt/code and
ordinary equal/mismatch distributions are required. Guest regression controls
include search, bytes and join at both sizes; medium equal ASCII/UTF8 values
and unaligned views remain independent distribution controls.

The source99 candidate is rejected and equality is deferred. Five native O3
ASan/UBSan suites pass, including the volatile exported-body calls. Both text
guests pass128 oracle/control/artifact records; all24 RF guests build with an
official Debug compiler receipt and verified unchanged external references.
Actual LLVM common equality paths inline, with only the bulk endpoint helper
remaining called. The native C helper retains a global exported comparator.

The quiet five-round six-arm screen retains240 samples and720 qualification
checks. LLVM/current-fastest equality is1.391574 small and1.000000 large.
Matched Debug5a-to-Debug99 paired LLVM after/before is1.019031 small equality
and0.354085 large equality, but large search regresses1.163108. Join small is
1.039731 and byte scan small/large is1.029826/1.043991. QBE large equality
is0.336964, and other QBE paired effects range0.983049–1.027971.

Inlining the wrapper therefore does not remove the repeated large LLVM search
regression. The underlying shared lowering/code-layout mechanism must be
understood before another equality revision; no specific layout/alignment cause
is established. Small equality remains above goal. The prepared80-row medium
distribution timing (and340-row optional extension) was skipped because the
guest gains did not present an adoption case. No diagnostic timings are claimed.

evidence.json binds exact source/receipt/manifest, native and guest checks,
commands, raw/archive hashes, actual kernel code and both timing reports.
The code, installed compiler/runtime and measured artifacts remain unchanged.
The coordinator owns independent review and the canonical goal dashboard.
