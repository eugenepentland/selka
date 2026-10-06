# S2-X count audit notes

Source: integration `090dabd5a6932a7c3beaec68248f9a35d4c637d7`; native source `b70a6a3f`. The 35-row measurement and corrected optimized-IR/assembly audit are complete: status 0, all 70 row/size pairs valid, 2,800 successful native samples, and no speed-gate misses. All clocks resolve. Native-code reuse is now qualified for repaired integration `996d9baad0e00ef98b4d3e7b59dc3616809fa013`. The source-bound `rows-after-fact.txt`/`.json` proof rebuilds only the 35 new native rows, establishes exact identity of every complete emitted LLVM module, and checks empty runtime/emitter/driver/clock and row-source diffs. The fact repair therefore does not affect these measurements, optimized modules, assembly, static counts or runtime explanations; no measurement or audit was rerun.

The audit counts static caller-visible LLVM stores carrying `myl.count` metadata. It uses the two `runtime_bench_now` calls, CFG dominance and reachability, and instruction boundaries inside shared clock blocks. Timed innermost loops, parent-exclusive timed blocks, timed nonloop blocks and setup/input loops before the clock are separate scopes. Construction repeated inside a timed batch stays in timed scope. Paths that abort without reaching the stop clock are separate. Static sites are not dynamic execution counts.

A literal count-1 store is recorded separately, but its role must be checked: allocation initialization and a release leaving one owner can both store 1. Saturated/immortal header reads are checks, not count stores. Untagged wide stores or memory intrinsics can initialize headers without appearing in the tagged-store total. Runtime and callee bodies are outside this LLVM caller audit, and missing count metadata means unknown rather than a proven zero.

Runtime review uses `src/core/runtime/core_rt.c`, `core_text.c`, `core_number.c`, `core_dict.c`, and `core_sort.c` from the frozen source. The allocator initializes a new block's count to 1. A last-owner release frees directly without storing a final zero; a shared release decrements. List/dict copying can retain children. Recursive freeing can decrement shared children. These effects must remain visible in the explanation even when a caller loop has no tagged stores.

## Static caller sites by row

Entries are `all tagged stores / literal count-1 subset`. The subset is initialization in the manually reviewed allocation blocks below. Parent blocks exclude child-loop blocks; timed nonloop stores occur once per invocation, not once per repeated element. Calls are actual non-intrinsic LLVM call sites, including conditional slow paths. Runtime bodies remain outside these static counts.

| row | inner stores / count-1 | parent-exclusive stores / count-1 | timed nonloop stores | repeated saturated / dynamic count reads | actual opaque timed call sites |
|---|---:|---:|---:|---:|---:|
| record_reads | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 1 |
| tagged_stack | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 3 |
| mutate_unique | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 0 |
| mutate_shared | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 2 |
| record_construct | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 1 |
| record_update | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 2 |
| option_handle | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 1 |
| result_propagate | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 3 |
| list_scan | 0 / 0 | 0 / 0 | 1 | 0 / 0 | 1 |
| list_append | 0 / 0 | 2 / 1 | 0 | 0 / 1 | 3 |
| list_filter | 0 / 0 | 3 / 2 | 0 | 0 / 1 | 6 |
| alloc_short | unknown; manual 0 | unknown; manual 0 | unknown; manual 0 | 0 / 0 | 0 |
| alloc_retained | 1 / 1 | 1 / 1 | 0 | 0 / 0 | 8 |
| mutate_nested | 2 / 0 | 0 / 0 | 0 | 0 / 2 | 4 |
| bytes_scan | 0 / 0 | 0 / 0 | 5 | 0 / 0 | 5 |
| string_equal | 0 / 0 | 0 / 0 | 5 | 0 / 0 | 6 |
| string_search | 0 / 0 | 0 / 0 | 5 | 0 / 0 | 6 |
| string_split | 0 / 0 | 1 / 0 | 5 | 1 / 1 | 8 |
| string_join | 0 / 0 | 1 / 0 | 5 | 1 / 1 | 8 |
| dict_lookup | 0 / 0 | 0 / 0 | 4 | 0 / 0 | 5 |
| dict_lookup_str | 0 / 0 | 0 / 0 | 4 | 0 / 0 | 7 |
| dict_update | 0 / 0 | 1 / 0 | 4 | 0 / 1 | 14 |
| dict_update_str | 0 / 0 | 2 / 0 | 4 | 0 / 2 | 25 |
| set_dedup | 0 / 0 | 1 / 0 | 4 | 0 / 1 | 9 |
| int_parse | 0 / 0 | 0 / 0 | 4 | 0 / 0 | 5 |
| int_format | 0 / 0 | 1 / 0 | 4 | 0 / 1 | 6 |
| call_indirect | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 1 |
| sort_int | 0 / 0 | 1 / 1 | 0 | 0 / 0 | 4 |
| sort_records | 0 / 0 | 5 / 2 | 0 | 0 / 3 | 8 |
| int_math | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 1 |
| float_math | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 1 |
| call_direct | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 1 |
| branch_predictable | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 2 |
| branch_mixed | 0 / 0 | 0 / 0 | 0 | 0 / 0 | 2 |
| binary_search | 0 / 0 | 0 / 0 | 1 | 0 / 0 | 2 |

For `alloc_short`, automatic tagged counts remain unknown because metadata disappeared. Manual inspection of the complete start-to-stop instruction intervals proves no store, atomic update, opaque call, or memory-writing intrinsic; its remaining intrinsics are scalar overflow arithmetic. Thus its completing timed caller has zero count writes despite the missing tags. The `parse_number` C helper is called before timing, and process cleanup follows the stop clock.

Nine natural loops remain conservatively classified as callee scope: six in `string_equal` input construction and one each in `string_search`, `string_split`, and `string_join` input helpers. Every possible direct-call context is before the start clock; none is a hidden timed kernel. Assembly loop annotations map to IR headers for every reported loop. The assembly candidate count is not a count-store proof: packed/vector header writes may combine a tagged count-1 initialization with other header fields.

The initial audit inflated opaque-call totals by treating `%call.i` labels in branch/phi operands as call opcodes. `count-audit-call-labels.json` and `.txt` retain that explanatory failure. The corrected instruction parser admits optional SSA assignment and tail/musttail/notail, rejects decoy labels/comments, and passes the Python smoke suite. The corrected audit uses `--reuse`; no optimizer, native compilation, or measurement was repeated. All store/read totals and clock-region classifications agree with the original audit.

## Arithmetic, promoted aggregates and scalar callbacks

Rows: `int_math`, `float_math`, `call_direct`, `branch_predictable`, `branch_mixed`, `binary_search`, `record_reads`, `tagged_stack`, `record_construct`, `record_update`, `option_handle`, `result_propagate`, `call_indirect`.

Inspect each timed loop for data/stack stores versus heap count operations. Scalar arithmetic, scalar fields and scalar callback results do not inherently need RC. If count metadata is absent, an explicit absence of stores and opaque calls in the optimized timed kernel can establish caller count-store absence; the metadata result itself remains unknown. This RC audit does not establish the S0/S1 code-identity or binary-search layout-noise proof; the coordinator provides those separately.

## Lists, uniqueness, snapshots and nested ownership

Rows: `mutate_unique`, `mutate_shared`, `list_scan`, `list_append`, `list_filter`, `alloc_short`, `alloc_retained`, `mutate_nested`.

Separate pure element loops from allocation/COW construction and parent cleanup. Unique mutations may read count 1 before updating data; that check is not a count update. Forced snapshots in `mutate_shared` require ownership/COW paths. `myl_core_list_copy` initializes a new list and retains referenced children according to its layout. `myl_core_list_grow` may return the same payload, reallocate it, or initialize a new header and copy/move elements. `myl_core_free_block` traverses nested children and decrements only shared children. Scalar-only element layouts avoid child RC, while nested lists need explicit review of those C bodies. Caller static sites alone do not measure those dynamic effects.

## Text and bytes

Rows: `bytes_scan`, `string_equal`, `string_search`, `string_split`, `string_join`.

The byte scan's vector/scalar element loops should be reviewed independently from input encoding/setup. `myl_core_str_eq` and `myl_core_str_find` read payloads without retaining, decrementing or allocating. Split materializes a fresh list and fresh pieces; it initializes headers, may grow/copy list storage, and frees child strings through runtime cleanup. Join allocates a fresh result. A caller `rc.keep` decrement after scoring such a fresh result is conditional: the normal unretained count-1 result takes last-owner free, while a shared result would store a decrement. Report the surviving static arm honestly rather than labeling it initialization or claiming a measured zero execution count. Separator globals may still generate saturated-header checks with no count store.

## Dictionaries and sets

Rows: `dict_lookup`, `dict_lookup_str`, `dict_update`, `dict_update_str`, `set_dedup`.

Distinguish pure lookup/probe loops from insertion/build phases inside each timed batch. Integer keys/values have no child RC. String keys can require retains when inserted into an owning dict, because the input key list remains an owner; later dict cleanup releases those keys. COW dictionary copying can retain children, while rebuilding/growth transfers entries and initializes a fresh header. Hash-cache writes affect metadata, not the reference count. Probe/hash/runtime calls remain explicit opaque sites until their bodies are reviewed; do not infer zero from caller count-store totals alone.

## Numbers in text

Rows: `int_parse`, `int_format`.

Inline SWAR and `myl_core_str_parse_int` parse bytes and write a scalar result without RC or allocation. `myl_core_str_from_i64` creates a fresh string with count 1, then writes decimal bytes. Borrowed encoding/scoring of that temporary should not add a retain. A remaining shared-release store after scoring is conditional; the fresh count-1 result takes last-owner free. The helper's count initialization and allocation remain outside caller tagging.

## Sorting

Rows: `sort_int`, `sort_records`.

Their collection construction occurs inside the timed batch and belongs in the kernel totals. Separate those construction loops and count-1 header initialization from comparison/key/gather loops and parent cleanup. Integer elements and the benchmark record's integer fields do not need child retains. Sort helpers may initialize/copy list storage and allocate temporary work buffers; scalar key callbacks do not inherently need RC. Runtime helper effects remain separate from the caller's static sites.

## Concrete surviving sites and runtime effects

- `result_propagate`: the two `myl_core_err_trace` sites update the error-trace buffer and its scalar counters, not block reference counts. Their state writes remain runtime effects outside the tagged RC audit.
- `alloc_retained`: one inner and one parent count-1 initialization in free-list `pop` blocks. They initialize newly owned list headers, not retain/decrement traffic. Assembly confirms the inner header is written as a 32-byte `vmovups` using `.LCPI1_0 = [0x200000000000001, 0, 4, 0]`, and the parent header starts with `0x100000000000001`. The assembly parser's 32-bit store candidate list omits these packed writes; its zero candidate count must not be read as zero initialization. Slow allocation/growth helper bodies also initialize headers.
- `mutate_nested`: the innermost batch loop contains two variable-count release stores, `rc.keep.96.i.i` for the replaced child and `rc.keep.127.i.i` for the old outer snapshot. Copying the outer list retains its referenced children in C. Replacing the selected old child then releases the copied slot, giving a real shared-child decrement on the normal COW path. The outer snapshot's shared-release arm remains conditional; an unshared last owner frees without storing zero. Freeing the outer snapshot also releases children in C. This row has real repeated ownership work, not merely allocation initialization. Dynamic totals were not instrumented.
- `dict_update_str`: the two parent-exclusive stores are increments in `rc.inc.40.i.i` (initial insertion phase) and `rc.inc.122.i.i` (new-key update phase). They acquire ownership of non-immortal input keys for the dict. They sit outside the innermost equality/probe-candidate loops, so inner-only or deepest-loop-only totals would conceal actual repeated key retains. Runtime map cleanup releases those shared keys. Integer-key update/set rows instead retain one conditional parent cleanup decrement for the fresh map and have no managed key/value child RC.
- `list_append`: parent stores are one free-list header initialization and one conditional final shared-list decrement. Its element push loop has no tagged count store, but may call `myl_core_list_grow`; growth can initialize a new header. `list_filter` has two such parent initializations and one conditional final shared-release store, with two growth call sites in element loops.
- `string_split`, `string_join`, `int_format`: each retains one parent variable-count shared-release arm for the fresh result. The reviewed runtime returns count-1 results and scoring borrows them, so normal last-owner cleanup frees directly rather than executing that arm. Split still performs list/piece allocation, growth and child cleanup in C. Join and formatting initialize their fresh result headers in C. Static conditional sites are reported, not erased by inference.
- `sort_int`: one parent count-1 initialization; comparison/sort code mutates a unique scalar-element list in place without RC updates. `sort_records`: two parent header initializations and three conditional parent release stores for construction/key/sorted buffers. The keyed runtime copies scalar records and scalar keys, gathers a permutation, and releases its key copy; these layouts contain no managed child references, so its copies need no child retains. Header initialization, temporary allocation and conditional cleanup remain separate from comparison/gather loops.
- The five text rows have five timed nonloop shared-release arms for the input record's fields. All five dictionary/set rows and both numeric rows have four; `list_scan` and `binary_search` have one. These are once-per-invocation cleanup after the repeated work but before the stop clock. They are genuine static release sites and runtime cleanup can release children, but they are not repeated element-loop updates. The measurement method subtracts startup samples; it does not instrument which conditional arms execute.

The C review establishes additional algorithm scope without pretending that the caller audit inspects C machine instructions. Equality/search/parse helper bodies contain no RC updates or allocation. Cached text hashing may update kind/hash metadata but not count. Unique numeric sorting changes payload order without RC; copying, formatting, split/join and nested cleanup have the allocation/ownership effects described above. Assembly candidates corroborate placement for variable stores, not dynamic counts or a formal register-allocation proof.
