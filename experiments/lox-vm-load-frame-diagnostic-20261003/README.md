# Selected VM frame-load cost, read-only

This traces the exact selected QBE RC guest `246f2178…`, unchanged selected AST
source37 and compiler base `3b33df52…`. `inspection.json` binds inputs before
and after; `raw.json.gz` preserves complete helper/caller SSA and actual ELF
disassembly plus exact compiler rules. It runs no guest, builds nothing, and
makes no dynamic path count or speed claim. The reported six-percent profile
motivation is parent-provided, not independently measured here.

The valid activation path is:

1. `run` reads `rt.frame_count`, performs checked subtraction by one, reads
   `rt.frames[frame_index]` with the original signed-negative normalization,
   conditional length-to-int cast/checked addition and unsigned bounds check,
   then copies the plain 24-byte CallFrame. Runtime is passed by address through
   QBE-AGGREF-1; there is no 208-byte Runtime argument copy. The source's mutable
   Runtime remains the caller's root/trace authority.
2. `load_frame` opens the ordinary RC frame (13 slots), obtains heap and current
   region, then reads the object table using `stored.closure`. It preserves the
   negative-index normalization and unsigned bounds check before storage read.
   Object entries have stride **56**, not 208; 208 is generic scratch capacity
   and Runtime size. The checked element pointer is matched by its tag. The
   valid closure is tag four; preceding tags zero through three are compared
   in the current linear match chain. Only its active 16-byte ClosureObj payload
   is copied. No whole 56-byte Obj copy appears on this access path.
3. It reads `closure.function`, performs the second checked object-table index
   read, and matches tag two after comparisons for tags zero and one. Only the
   active 48-byte FunctionObj payload is copied. Wrong-kind paths retain the
   original `object is not a closure/function` assertions; they are not admitted
   into this successful-path account.
4. It projects function.code.constants, function.code.code and closure.upvalues
   in their original order. Each list obtains its owned publication, including
   normal count/capacity/header/region guards and canonical slow fallback. The
   SSA has three typed publish call sites, but they are **slow-path** sites,
   not three unconditional calls. Ordinary non-null non-special lists with
   available count capacity take the inlined acquire/mark/store branch. Null,
   immortal, arena, count-limit and special-header paths differ and remain
   checked. Incoming read-only object projections do not make the returned
   ExecFrame a borrowed result.
5. The helper wholly clears its 40-byte ExecFrame constructor, prepares and
   transfers three managed list handles, writes stored.ip and stored.base, then
   publishes the ordinary owned aggregate result before exiting the frame.
   On admitted ordinary headers, the three handle transfers and aggregate
   transfer use inline checks/copies/clears; other states retain typed glue.
   The complete SSA has two 40-byte blits at the successful constructor/return
   PCs, plus eight-byte field preparation sites, conditional copy/take
   alternatives and guarded cleanup. These sites are static evidence; adding
   both branch alternatives would overcount execution.
6. The actual AMD64 caller supplies hidden aggregate-result storage in rdi,
   ctx in rsi, Runtime address in rdx and CallFrame address in rcx. The helper
   writes the returned aggregate into that hidden storage using five word
   load/store pairs in its native ABI epilogue, then returns its address through
   rax. This ABI copy is additional to the explicit SSA carrier blits. Caller
   SSA has four 40-byte blit
   sites at call/assignment PCs25–26: three straight staging/publication sites
   and one conditional take site. Actual assembly lowers the first staging
   blit to five full-word load/store pairs. It then checks/transfers the three
   managed edges into the live ExecFrame local; the local survives the entire
   recursive activation and is retired on run's return/error paths. Runtime
   frames retain closure/base roots and receive IP publication at the original
   handler/error/call boundaries. This report does not erase those owners or
   infer that an unowned alias would survive later Runtime mutation/collection.

`load_frame` is 664 native instructions with 50 static call sites in this exact
ELF; `run` is 8,606 with 440. These whole-function counts include cold assertion,
trap, count/special-state glue and cleanup paths, not just valid ordinary
activations. The caller/helper successful path has the checked accesses,
active-payload copies, three owned list publications and 40-byte return
carrier work described above. The generic frame scratch allocation, all static
calls and all failure blocks must not be treated as executed overhead.

Generic bytecode inlining refuses this helper independently in several ways.
Its metadata has **142 bytecode positions and no prior inlines**, exceeding the
hard 64-instruction maximum (`bytecode_inline.eligible`). Even a smaller body
with the same operations would refuse: its managed `list[object.Obj]` indexing
is outside the integer/bool/unit-only `indexIsAllocationFree` admission; the
allow-list also lacks the ExecFrame `make_record` constructor and assertion
operation. Raising one size threshold would not make this a certified splice.
The RC scope/glue inline helpers inline runtime protocols; they do not splice
arbitrary guest function bodies. Current canonical owned-return routing is
also visible in the symbol and three-list return transfer; no new borrowed
entry proof has been established by this diagnostic.

A larger carrier-lifetime/ownership or new bounded inlining proof would be
needed to remove this cost safely. The intended snapshot owner lifetimes,
normal indexed error order, closure/function assertion order, GC root authority
and COW behavior must all be retained. This lane implements no such change.

Exact inspection recipe:

```bash
taskset -c 16 python3 experiments/lox-vm-load-frame-diagnostic-20261003/inspect.py
```

The script refuses overwrite and reserved CPUs, rehashes all selected source37
and exact selected ELF/IL inputs, and compares compiler rules against the base
Git archive. Native GC and accounted quota behavior are outside this static RC
inspection; their existing qualification is not rerun or expanded here.
