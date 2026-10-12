Base: `07f16c65415819c36c46eb0657530abce734e395`, authorized A02 integrated branch.

Production: three-line early checked-mode `mergeFieldReads` in
`own.functionWithScratch` before `elements.fieldStores`. Existing late merge remains.
No new equivalence, source acceptance change, runtime helper, header, or COW fallback.
A07 approved the exact patch; A08 notified to use changed compiler for final scaling.
Root authored only new root-test import; existing NEW-CORE-CE-LISTS-1 spec applies.

Qualification: focused1/1 covering15 native cases; separate durable15/15 zero-RC
native cases with RC0/live0 and LLVM/symbol checks; ordinary controls6/6; bounds
trap/side-effect order7/7; borrowed-parent overlap refusal5/5. Frozen original and
reduced source identities, exact outputs/compiler/commands are preserved.
Compressed native JSON carries raw counters and command results; summary identifies
both compressed and uncompressed hashes. A source-only typo in the independent
control fixture was corrected before final focused test; original sources unchanged.

The component pin/archive/cache use A10's actual independent owned Support6 pin.
The manual focused runner uses the corresponding component install directory.
Neither this patch nor these local results promote defaults or retire legacy mode.
The coordinator must integrate and run its complete final gate.
