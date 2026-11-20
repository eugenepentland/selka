# Independent plain-readiness inlining review

No actionable source correctness defect found in frozen
`79fd7e25635a21813f41d8038832f41a0154d56c`, based on
`3226f1d66b08734824e5c799c25a9c7ed4a69438`. The helper body and public header
are byte-identical to the base. The implementation adds only `inline` and
`always_inline` to the existing externally callable function definition.

`native_collections.c` includes `native_rc_collections.h` before the definition;
that header's declaration has external linkage and is not an inline declaration.
The later inline definition therefore supplies an external definition under
the C99 inline rules retained by the production C11 mode. It is not a header-only
inline definition that requires a separately supplied external body.

The independent probe compiles the complete unchanged production translation
unit and a separate caller using only the public declaration. That caller loads
a volatile function address and calls it. Fifteen cases pass in each mode:

| Build mode | Independent cases | Callable symbol |
| --- | --- | --- |
| No LTO, O0 | 15/15 | External T |
| No LTO, O3 | 15/15 | External T |
| Full LTO, O3 | 15/15 | Defined local t; address callable |
| ThinLTO, O3 | 15/15 | External T |

The cases cover null heap, absent RC state, null list/element, positive cached
identity, pending-death refusal before that cached identity, managed/wide
element refusal, unknown binding refusal without state/allocation changes,
owned-leaf and native-unique descriptor refusal, positive binding admission,
positive cache reuse, and a different scalar type. Production readiness and
static binding/cache helpers are real; the external cold binding lookup is a
precise assertion-bearing stub. This isolates the callable ABI and query
semantics. It does not replace the actual-runtime tests.

The existing native receipt and raw log report all 47 actual collection cases
passing under UBSan for no/full/ThinLTO. The tests include cold metadata,
pending finalizers, full capacity, generation overflow, alias growth, older
receiver regions and memory-budget refusal. The independent source inspection
confirms that no guard or query side effect was removed or reordered.

The four existing allocation-churn guest binaries, disassembly hashes and
stored output were independently verified against their receipt. All stored
outputs equal `999739\n`; direct query call-site counts are 2 for QBE, 2 for
LLVM without LTO, and 0 for full/ThinLTO. Those four executions and the native
47-case matrix belong to tooling's evidence; this review did not rerun them.

One small documentation correction was reported and acknowledged: the layout
audit says one retained QBE/non-LTO call site, while its authoritative receipt
and assembly show two. Tooling will correct this prose separately without
changing the frozen source or binaries.

The first probe-driver attempt specified C99 for the entire production TU.
Existing `native_heap.h` requires C11 `max_align_t`, so it failed before linking
or execution. The preserved `initial-c99/` log records this fixture error.
Only the driver's flag changed to production C11, which uses the same inline
linkage rules. No production source or header changed.

All compiler/runtime/vendor source bytes remain frozen. This read-only source
review invoked no Guardian gate, broad acceptance gate, guest timing or shared
repository mutation. Parent owns archival and quantitative acceptance.
