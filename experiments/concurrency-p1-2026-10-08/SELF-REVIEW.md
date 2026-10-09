# P1 review before final qualification and measurement

Reviewed the complete implementation against comparison base `94dc1c3a2`, through `9f911528f` plus the measured local-exec substitution. The original P1-0 inventory is retained in [HISTORY.md](HISTORY.md#2-accepted-p1-0-inventory-and-abi-findings). The [fresh typed-AST inventory](r3/final-inventory/inventory.json) finds **128 static declarations and 8 managed count-access lines**, all covered below. It records every included runtime file hash and the source diff hash (the three-file TLS substitution), without replacing P1-0's source facts. The native object compile passes; the pinned wrapper's known AST-only FileNotFound status is retained with the complete parsed AST result, as in P1-0.

## Counts and managed edges

- The 32-byte header and the plain/shared/immortal encoding remain fixed. LLVM count reads use `unordered` with the original count TBAA/range; C uses relaxed atomic loads. Uniqueness remains exactly `count == 1`; shared values cannot enter the unique mutation/free path. No ownership-pass or IR edit was made.
- B2 keeps one unlikely 32:1 branch and one preserve-most slow call. The inline ordinary retain/release path remains non-atomic. Shared retains use relaxed CAS; releases use release CAS, with acquire-release only on the last owner. Every CAS rechecks the immortal sentinel, so saturation is sticky. Actual TSan exposed the prior acquire-fence modeling problem; no annotation or suppression was added.
- All C RC access sites use the common helpers except fresh initialization, helper implementations and pre-publication sharing. Header copies/reallocation require a plain unique block. Free-list writes happen only after exclusive reclamation. The typed source guard distinguishes managed counts from unrelated fields named `count`.
- Text hash, scalar-count and cursor writes require a plain block, including before pool startup: emitted immortal literals are read-only. The ASCII table is initialized fully before worker creation. Shared/immortal missing caches compute without storing.
- Publication and destruction use the same child iterator: list/box guards, alias multiplicity, nulls, view-owner fields, live dictionary entries, provider pairs, task results and group handle lists. The worklist marks before pushing, so repeated edges neither loop nor add ownership. Destruction decrements every owned edge. Dictionary auxiliary storage is finalized after enumeration. Provider pair release moved from its special finalizer into its layout.
- Plain saturation shares descendants before becoming immortal. Otherwise a later stop-at-immortal publication could leave reachable plain children. The separate boundary fixture deliberately retains that immortal graph; ordinary differential cases require zero live blocks.

## Static runtime state

The P1-0 inventory's immutable tables, strings, layout descriptors and linker symbols remain immutable. Its mutable families now have these owners:

| State | Owner and synchronization |
|---|---|
| free lists, chunk cursor, text-walk count | TLS; main registers before allocation/publication and workers at startup; persistent registry preserves retired-thread snapshots under its mutex |
| registry heads/key/once state | registry mutex and pthread_once; reports read after task quiescence |
| heap ceiling / held bytes / live blocks | ceiling frozen before guest execution; held/live atomic; byte charging occurs only with an active ceiling |
| ordinary stream buffers / per-thread staging | before pool, original single-thread buffering; after pool, TLS complete units and one stream mutex; dynamic-print arguments are evaluated before begin/end boundaries |
| error trace, IO blame site, trap capture/line limit, task context | TLS; nested helping saves/restores trace and task context |
| pool-start flag / fatal winner | atomic once-published flag and atomic winner; losing reporters park |
| DWARF map | only the winning fatal reporter initializes it; raw fallback skips it |
| IO tables, scratch, handle counters, provider state | complete operations under the IO mutex, with per-thread nesting depth; options/grants/provider registry frozen before publication |
| Host globals | unchanged and main-thread-only; tasks cannot receive Host under P2's required checker rule; fatal worker cleanup never enters Host |
| test transport/table/trampoline | batch-parent state inherited by forked trials; parent cannot start a pool, and a process with workers cannot fork |
| step/frame counters | unchanged; any active step/frame budget forces one thread |
| main stack setup / worker stack metadata | startup-only idempotent main installation; each worker has TLS bounds and its own alternate signal stack; workers inherit blocked SIGALRM |
| counting section records | immutable identities copied into persistent per-thread slot arrays; atomic global live/peak totals; one aggregate writer after quiescence |
| counting TLS pointers / registry | each thread mutates its own current/copy/push records; registry insertion under a mutex; records survive retirement |
| worker array, ring capacity/previous pointers, configured thread count | initialized before worker publication, immutable afterwards; old rings remain allocated until process exit |
| deque slots/top/bottom/ring pointer | C11 atomics in the Chase–Lev protocol; one owner per deque; thieves only dereference the task after winning the top CAS |
| global/group pending, completion state, epoch, ready count | atomics; task result/trace restoration precede publication; group/global acquire waits precede destruction/reporting |
| group list/closed flag, worker victim cursor | confined to the owning submitter/worker; workers touch the group's pending counter and immutable site only |

The allocator's fast free can only encounter a populated TLS list after that thread's registration/allocation path; scheduler workers register before guest execution. The registry never keeps a pointer into retired TLS after its destructor. Global pending decrements after allocator/counter/trace writes, so observing zero establishes the report barrier; idle workers only touch scheduler atomics afterwards.

## Fatal paths and output

Traps, assertion/contracts, IO failures, OOM/heap exhaustion, refused output, stack-floor faults and run-timeout reporting all reach the winner protocol before their report in parallel execution. It uses 1,024 stream try-lock attempts, then raw fd-2 output if the lock cannot be acquired. The raw path performs no DWARF walk. Parallel fatal exit skips IO/provider/Host cleanup and counting aggregation, then `_exit(1)`; it cannot inspect another thread's changing records. Single-thread cleanup/reporting is retained. Normal `main` error values and malformed internal transport/descriptor assertions are not converted into task errors.

Normal exit quiesces tasks before output/report/cleanup. Every print/write/debug unit is staged in full after pool startup, including units above 64 KiB. A dynamic separator/terminator print uses nested begin/end boundaries so its component writes cannot interleave. Fatal fallback may drop staged output as the plan permits.

## Scheduler and ABI

The lazy pool starts N−1 workers, with the caller as worker zero. Empty groups do not start it. One-thread submission runs synchronously without sharing/retaining the borrowed environment. Parallel submission shares and retains the environment before enqueueing; the result is shared before completion release, and every result read returns an owner. A group owns task references until close/finalization joins; post-close handles no longer need a live group pointer.

Deque growth retains old atomic rings. Signed indices avoid empty-zero unsigned underflow; capacity/index exhaustion fails. Waiting searches the caller's own deque and round-robin victims. Epoch is sampled before testing completion/search; both enqueue and completion wake waiters, avoiding the empty-search-to-park lost-wakeup window. Nested work preserves the active task/item and error trace. No wall clock or RNG chooses victims.

The runtime only calls emitted thunks through the retained `weak_odr hidden` C-to-fastcc bridge. Return PCs identify group/submit sites; the range helper updates the item before each body, so a trap in item 17 does not report its range's first item. The required no-DWARF fallback is tested.

## Build controls, scope and limits

Layout K=4/5/6 is passed to every emitted unit and runtime compile and salts their identities. ThreadSanitizer marks every LLVM definition and instruments C/runtime/foreign sources, linking the same sanitizer. The foreign-source manifest has its own sanitizer salt; it cannot rely on the runtime ABI key. Ordinary/sanitized/replayed builds are tested in both directions. Invalid sanitizer values fail before compilation.

Local-exec TLS was selected from the complete paired row sweep; C and both LLVM emitters agree. At that historical review, no front-end `src/*.zig`, `src/core/ir.zig`, `src/core/own.zig` or `core_host.c` changed. The final integration and user-authorized timing waiver are recorded below. No push or modification of main/Claude occurred.

Remaining phase-1 limits are intentional: workers, old rings, small-allocation chunks and their registry records live for the process; shared marks are permanent; provider operations serialize; fatal workers skip external cleanup; task handles have no user surface until P2. P2 must enforce confinement, Host/resource exclusions, all-exit close lowering and CLI stack/job accounting. [P2-0](P2-0.md) proves the lowering vocabulary and identifies those files; it does not authorize P2.


The first final full gate additionally exposed two pre-existing native-only harnesses in `own_test.zig` that needed the C task adapter. Both now provide it; their focused million-deep release/allocator tests pass. This corrects the earlier incomplete fixture inventory without changing the runtime or the forbidden ownership pass.

## Final merged-source review — c26c95de7

Real merge `1844fcc33` integrates main `35df839be`. Reviewed the resulting emitter diff against that main: upstream scalar TBAA nodes 11–22 and the free-path memory barrier are intact; P1's 32:1 node is 23, fact-node allocation follows it, and the retained task bridge and local-exec declarations remain. The existing emitted-count test now verifies the unique branch-weight node/reference. Incoming `ir.zig` and `own.zig`, plus all `src/*.zig`, exactly equal main; there is no P1-authored change to those frozen files. `core_host.c` also equals main.

The [final typed inventory](r3/selected-inventory/inventory.json) records the committed source with an empty source diff, successful object compile, **128 static declarations and eight managed count-access lines**. The known AST-only Zig wrapper FileNotFound remains separate from the successful native object and complete parsed AST. All new S1 text/span helpers either read input storage or initialize a fresh block; they introduce no shared cache writes. Existing cache guards remain in place, and the new span-materialization counter hook is retained.

Selected candidate C exactly matches its measured core_rt.c hash. Common child and release visitors are forced inline; dictionary enumeration remains ordinary. The TLS registration check is inline, with a cold preserve-most allocation/registration function. `live_blocks` remains atomic: before pool publication only the main runtime thread can update it, so relaxed load/store is sufficient; publication precedes every worker creation, and all subsequent updates use atomic RMW. No transition back to the single-thread mode exists. Byte-budget charging is unchanged. The stronger eight-worker fixture checks 1,024 small/large allocations simultaneously live at a barrier and zero after retirement, so lost increments/decrements cannot cancel unnoticed.

The complete historical C timing sweep is retained, including target misses. By the user's explicit instruction, final merged-source wall-time checks are waived. Allocation/copy counters and emitted-code checks are diagnostic proxies, not a passed overhead gate. All correctness gates remain required. Final results are recorded in REPORT.md.
