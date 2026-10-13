# Lox and EDA: five performance priorities

Status: all five fixes are integrated in the
[implementation run](../../experiments/lox-eda-improvements-20261012/README.md).
The complete registered verification gate passed all 46 selected actions.
Combined application qualification and both five-mode matrices pass. Full-workload
comparisons remain in progress; the performance acceptance criteria below are
not yet a completed-results claim.
Audit base: `5f1701b13f243ca1fcc05c0b38ce73b8c9c3cd4d` on the development lineage.

Repeated independent copies in the application migrations are the strongest
targets. Start with the EDA overlap loop for a small, isolated change, then
remove Lox frame/object copies and both applications' AST traversal copies.
Keep checked ownership, independent `.copy()` semantics, and Lox's own object
garbage collector. No RC fallback, escaping borrows, new arenas, ownership
annotations, or whole-program ownership inference are needed by this plan.

## Evidence and limits

The [fresh rerun](../../experiments/lox-eda-rerun-20261012/README.md) attempted
all 60 cases. Checked ownership hit the calibrated 3× Zig deadline during warmup
in 59; only tree equality completed (0.539886 s, 2.791× Zig ReleaseFast).
There is no current complete-group checked runtime ratio. Missing runtime,
RSS and counter measurements must remain missing, not become timeout values.

Fresh tree equality allocated 2,700,085,496 bytes cumulatively, with 7,398,384
peak live managed bytes and 10,296 KiB median process peak RSS. These are
different metrics. Zero managed bytes remained at exit; this is allocation
churn, not evidence of a leak.

Fresh compiler: source `8b7d59eba868775b1b8d7f64c54b07abdd23d470`, executable
SHA256 `2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329`.
Historical profiles use source `e2893d2707cbe057a09abf94e04c4b12d16b7b8b`,
executable SHA256 `6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d`.
The rerun preserved the migrated application sources and frozen workloads.
Historical counters help locate surviving source costs; they are not new
measurements of the current compiler.

[Reproducible attribution](../../experiments/lox-eda-improvement-audit-20261012/attribution.json)
checks 55 completed profiles: one fresh, 13 historical tree, seven historical VM,
and 34 historical EDA. Six historical VM profiles timed out and stay in the
26-case Lox denominator. Function allocation bytes plus reallocation-added
bytes sum exactly to each profile's traffic total. Source copy-event bytes
can overlap and are not added. Corpus shares weight the fixed workloads by
allocated bytes; they are not average case shares or CPU-time percentages.

## Ranked priorities

| Rank | Improvement | Evidence | Initial scope / difficulty |
| --- | --- | --- | --- |
| P1 | Stop copying managed VM frames per instruction | Historical VM Fibonacci: `vm::run` allocates 621.86 GB, 93.52% of traffic | Frame representation and instruction readers; large |
| P2 | Borrow the tree interpreter's immutable AST | Fresh equality: `evaluate` allocates 2.09 GB, 77.51%; with statement/block execution, 90.41% | Separate program from mutable execution state; medium–large |
| P3 | Read selected Lox object fields without whole-payload snapshots | Historical 13-case tree corpus: class/instance/environment/string getters allocate 58.35 GB, 64.41% | Scoped query helpers, then selected updates; medium |
| P4 | Remove EDA subtree copies in traversal and fresh construction | Historical 34 designs: `as_list` + `node_list` allocate 10.13 GB, 41.65% | Borrowed traversal, then parser construction; large breadth |
| P5 | Remove EDA overlap-loop suffix allocations | Historical 34 designs: `overlaps_of` allocates 2.53 GB, 10.41%; 43.41% in `rds3+flat` | Indexed scanning, then optional index sorting; small first patch |

GB above is decimal cumulative allocation traffic. Function buckets also
include legitimate allocations; these shares are opportunity indicators, not
promised savings. P2 and P3 describe different workloads and must not be added.
The ranking considers severity, coverage, and source evidence, not just bytes.

### P1 — Make VM frames cheap to read and publish

In the frozen [heap source](../../experiments/lox-eda-zero-rc-20261012/lox/migrated/heap.my),
`CallFrame` (line 22) owns a function, bytecode list and upvalue list. The
[dispatch loop](../../experiments/lox-eda-zero-rc-20261012/lox/migrated/vm.my)
copies it at entry (431), after fetching each opcode (434), and at the bottom
of each iteration (545). Calls also clone function/code/upvalue payloads (123–134).

1. Prototype a frame containing existing object handles and scalar `ip`/`base`.
   Keep code, constants and upvalues in their existing rooted objects. Use P3
   readers to borrow storage for each access and return only the selected value.
2. End each borrow before mutating/allocating/collecting through `Runtime`.
   Preserve frame publication points required by error reporting and GC.
3. Measure lookup overhead. If needed, retain a bounded per-call cache, but
   establish that it is never deep-copied per instruction.

The previous migration encountered unsupported nested record/list field
writeback. First compile a small current-revision reproducer; do not assume
`rt.frames[i].ip = ...` is supported. Whole scalar-frame replacement, or separate
scalar frame arrays, avoids relying on arbitrary partial managed moves.

Acceptance: arithmetic dispatch performs no frame/code/constants/upvalue deep
copies per opcode. Validate recursion, closures, open/closed upvalues, classes,
stack overflow, error locations, return cleanup, and GC stress. Report per-opcode
and per-call allocation slopes separately. Existing handle roots must protect
objects across collections and object-table growth/reuse.

### P2 — Separate immutable program storage from mutable execution state

The [tree interpreter](../../experiments/lox-eda-zero-rc-20261012/lox/migrated/interpreter.my)
matches `it.program.exprs[id].copy()` in `evaluate` (318), clones statements in
`execute`/`run_block` (543/604), and copies function bodies in `run_body` (617).
Recursive calls mutate all of `Interpreter`, including the object that owns
the AST, so the migration takes independent snapshots before descending.

Pass the resolved program as an ordinary borrowed parameter alongside mutable
runtime, output and small control state. Match nodes through scoped borrows;
pass scalar IDs or selected fields into recursive calls. Remove the full
runtime snapshot used by printing (570) once runtime and output can be borrowed
independently. Keep parser/resolver mutations before execution.

Acceptance: evaluating an already-resolved expression or statement does not
clone its AST payload or body list. Fresh equality is the paired counter/runtime
control. Also cover recursive calls, repeated execution of one program,
short-circuiting, return/error propagation, printable values, and GC stress.
No AST reference may survive program destruction or become a stored view.

### P3 — Replace whole-object reads with scoped queries

In [heap.my](../../experiments/lox-eda-zero-rc-20261012/lox/migrated/heap.my),
`string_obj`, `function_obj`, `closure_obj`, `class_obj` and `env_obj` return
independent payload copies. `string_hash` (192) clones a string just to read a
`u32`. `instance_of` in the tree interpreter (84) similarly copies a payload.
Environment/class/instance updates also reconstruct snapshots of managed fields.

Add query helpers for hashes, arity, parent handles, slots, methods, fields,
instructions, constants and upvalues. Inspect the original payload during the
call and return a scalar, `Value`, or existing `ObjRef` as appropriate. Copy
selected text only when the caller needs an independent owner. Preserve the
existing snapshot accessors for callers that require independent results.

Land read helpers first. Audit mutation helpers separately with minimal
move/writeback probes before changing them; arbitrary mutable union payloads
are not assumed supported. Do not retain native addresses across allocation or
GC. `ObjRef` remains the application's established identity, not language RC.

Acceptance: query traffic no longer scales with the size of an unselected object
payload. Repeated scalar reads perform no payload copies. Cover missing keys,
table growth/rehash, aliases observing writes, inheritance, reused slots,
retained snapshot independence, and normal/stress collection. This work shares
`heap.my` with P1 and needs one owner or sequential commits.

### P4 — Borrow EDA ASTs when reading; move fresh children when constructing

[sexpr_ast.my](../../experiments/lox-eda-zero-rc-20261012/eda/source/src/sexpr_ast.my)
explicitly promises an independent children copy from `as_list` (81–84).
Read-only consumers repeatedly call it and then slice/scan the copied tree;
for example `scan_wire` in `kicad_sch_verify.my` (291 onward). The two main
buckets are `as_list`: 27.10%, and `node_list`: 14.55% of historical EDA traffic.

Land two independently measured changes:

1. Convert read-only visitors to scoped `match node.tag` traversal and scalar
   query helpers. Use indices for subranges so removing an accessor copy does
   not leave a copied slice. Keep owned `as_list` semantics for callers retaining
   or mutating results; a general returned/stored borrowed list is outside scope.
2. At the private parser's fresh-list construction boundary
   ([parse_list](../../experiments/lox-eda-zero-rc-20261012/eda/source/src/sexpr_parser.my),
   211–224), construct `Node(Tag.list(children))` locally by transfer if admitted.
   Today `node_list` borrows and recursively copies the completed children before
   the original is destroyed. Preserve the public copying constructor contract.
   If transfer is refused, capture the small reproducer before proposing a
   bounded compiler lowering change; do not introduce general parameter inference.

Acceptance: read-only traversal has no whole-subtree copies, and fresh parser
construction does not recopy descendants at every ancestor. Measure increasing
width and depth separately, allowing real output storage and container growth.
Cover empty/malformed/deep input, early cleanup, source replacement/destruction,
and independent owned-accessor results. Run all 310 EDA tests, 34 complete golden
designs and the existing error-path corpus. Split module edits into reviewable
batches; preserve formatting and diagnostic behavior.

### P5 — Scan overlap candidates without materializing suffixes

[overlaps_of](../../experiments/lox-eda-zero-rc-20261012/eda/source/src/kicad_sch_textbox.my)
(131–147) sorts a copied list, then loops over `ordered[i + 1:len(ordered)]`.
That suffix is an independent list with copied managed elements; it is created
even when the first candidate triggers the early exit. Current
[slice lowering](../../src/core/build_list_methods.zig) uses `sliceCopy` (274).

First replace the inner slice with indexed iteration over the existing sorted
list. Preserve the exact 10-unit boundary, stable order, overlap count and first
reported pair. Next, if counters still implicate sorting, stably sort integer
indices with borrowed item context, and copy text only into the retained report.
The existing generic sort copies managed values through its merge buffer, so
sorting indices also deserves a controlled comparison. Keep slice semantics.

Acceptance: scanning creates no suffix lists or item/text copies per candidate.
Compare 0/1 items, stable ties, sparse/dense overlaps, long text and negative
coordinates against an oracle. Index-sort auxiliary storage should grow linearly
with item count; dense pair comparisons may still be quadratic. This is a
storage fix, not a claim of universally linear overlap detection.

## Delivery and verification

1. Freeze a new working source pair and complete compiler installation from the
   audited development line. Leave historical experiment sources/evidence intact.
   Start with tiny ownership probes and bounded versions of VM Fibonacci, tree
   equality, AST parsing/traversal, and EDA overlap inputs. Label reduced inputs
   separately; they are not replacements for the 60 full benchmark cases.
2. Land P5's scan patch first. Land P3's read helpers before P1's frame refactor;
   P2 can follow with one coordinated interpreter owner. Stage P4 traversal and
   construction separately. One owner coordinates `heap.my`; P4/P5 also reserve
   their respective sections of `kicad_sch_textbox.my` before concurrent edits.
3. Qualify each patch with outputs and allocation attribution. Keep original RC,
   migrated RC and checked source identities separate. A changed source migration
   is an application improvement, not a compiler-only speedup. Inspect emitted
   copies, direct cleanup and guest RC symbols for affected paths.
4. Run the complete Lox conformance corpus (974 existing cases), 65 Lox unit tests,
   smoke/GC checks, EDA coverage above, and the affected ownership mode matrix:
   release, unoptimized debug, verified release, optimized debug, release without
   facts. Add focused positive/negative regressions for any compiler changes.
   Such changes also require cache invalidation/edit checks and preservation of
   bounded ownership-checking/compile scaling.
5. Measure unchanged full inputs with the existing 3× fresh Zig timeout and
   absolute ceiling. Keep every cutoff visible. Use at least two warmups and nine
   alternating runtime pairs under shared exclusive timing admission; separately
   collect three child-RSS samples and instrumented managed counters for eligible
   cases. Compare candidate to the pinned checked baseline and foreign arms;
   do not compare instrumented runtime to uninstrumented Zig. Tiny probes may use
   separately labelled bounded counter runs; never silently uncap full runs.
6. Report wall time, allocation/reallocation traffic, managed peak/exit-live,
   process RSS and compilation separately. Investigate repeatable regressions
   above 5%. Aim first to complete all 60 within the requested budget; only
   completed groups earn full-group ratios. A reduction in allocated bytes does
   not establish an equivalent runtime or RSS reduction. Below-1 foreign parity
   remains a measured goal, not a promised outcome of these five patches.
7. Run `verify_cache.py` directly on frozen integrated inputs and required Guardian
   checks. Keep native work in the shared admission queue. At a green gate,
   deliver commits and the measured differences for review; further optimization
   is a separate decision. Do not push or advance branches as part of this audit.

The [text microbenchmark checkpoint](../../experiments/text-gaps-20261012/README.md)
already puts splitting and CSV below their fastest foreign controls. JSON's
remaining 1–4% gap to Rust is smaller than the application copy costs here.
General allocator tuning, broad sort rewrites and additional JSON tuning should
follow new profiles after these changes, unless a concrete regression intervenes.
