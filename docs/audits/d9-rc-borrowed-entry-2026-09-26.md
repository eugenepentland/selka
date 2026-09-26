# Strong borrowed-result certificates and measured traffic

`rc_calls.borrowedIn` proves the physical result at every reachable normal
return. Its forward control-flow analysis admits one parameter anchor plus
immortal alternatives, including inline records and variants. A guest helper
call is allowed only after a separate transitive proof establishes an
immortal-only result without mutation or fresh heap allocation. Unknown
instructions, backward edges, fresh heap wrappers, boxes and different
parameter anchors decline the optimization. The canonical ABI remains owned.

The certificate hashes its policy version, runtime ABI, parameter and result
layouts, every accepted instruction payload and the identities of admitted
helper bodies. The existing may-return provenance facts do not grant this ABI.
Tests reject fresh fallbacks, mixed anchors, mutating calls and uncategorized
returns, and confirm that changing an immortal helper changes the dependency
identity.

The compiler patch emits each certified body as a separate native unit after
canonical pass analysis, with its own symbol and source frame map. Function
values and exported calls retain the canonical entry. A borrowed caller copies
physical inline bits and establishes the result's ownership before releasing
its argument anchors. The borrowed body avoids intermediate ownership traffic.
A native-manifest regression checks separate metadata and unchanged canonical
copies. Four lifetime guest assertions pass on both QBE and LLVM, including
anchor destruction, immortal fallback and indirect invocation, with all 22
allocations retired and identical counters.

The actual schematic `sexpr.at` qualifies: its bounds fallback is an inline
`Node` containing the immortal bytes from `text.empty()`. Its additional entry
contains no `myl_rc_native_copy` call. All three required schematic SVG hashes
match before and after on both backends. Each run removes 38,060 acquires and
38,060 releases; fixture and changed-value acquisitions fall from 6,434,873 to
6,396,813 (0.5915%). All 56,314 allocations still retire. Holds, clone counts,
uniqueness checks and outputs are unchanged; no counter saturates.

[Reproduction and complete evidence](../../experiments/d9-rc-borrowed-entry-20260926/README.md)
record Debug compiler hashes, native binary hashes, source hashes, commands and
all twelve output validations. These measurements isolate the certified-entry
patch after the plain-projection correctness fix. Cache invalidation integration
and the combined full gate remain with the compiler/integration owners.
