# What stands between the LLVM-O3 arena arm and Zig — 2026-09-20

The benchmark chart puts the whole-module LLVM-O3 arena arm at 1.67× Zig on
census and 2.81× on render. This audit asks what the *language or the ABI*
would have to change for that arm to reach parity, prices each candidate on
the arm itself with one-edit guest probes, composes the priced changes into
one binary, and says where that binary lands.

**Headline.** The gap is not code generation. The arm already retires Zig's
instruction count on census (155.3 M against 155.0 M) and its tokenizer is at
parity in cycles. What separates it from Zig, in order of measured size:

0. **An experiment defect.** The arm's "root-free" lowering removes only the
   store that publishes each GC root record; the 32-byte records themselves —
   4,580 static store sites, 223 of them in `push_node` alone — survive into
   optimized machine code because their addresses pass through integer
   arithmetic LLVM cannot see through. The parallel audit
   [`llvm-zig-parity-2026-09-20.md`](llvm-zig-parity-2026-09-20.md) found this;
   it reproduces here and its removal is worth **9 M cycles on census and 41 M
   on render** before any language change. Everything below is measured on top
   of that fix. The production lesson is a lowering contract, not a flag: a
   non-collecting mode must not emit root records at all, and a collecting one
   should publish them only at safepoints.
1. **Bytes touched.** The arm faults 2.3× (census) to 3.8× (render) as many
   pages as Zig. Kernel zeroing plus the user-side TLB and fault-entry stalls
   are **46% of the census gap and 36% of the render gap**. Huge pages do not
   help; the cost is proportional to bytes, not faults. The bytes are a 96-byte
   header on every allocation, a `list` that is a header object plus a
   separately growing backing array, `bytes.view()` allocating a 168-byte heap
   object per call, and an output buffer that doubles and is then copied once
   more by `finish`.
2. **An opaque runtime boundary.** Every list element read, list append, byte
   append and heap lookup is a call into a separately compiled C object.
   Putting the runtime in the same LTO unit is worth 8–10% of user cycles.
3. **Aggregate copies.** Much smaller than earlier audits assumed, because
   LLVM's inliner already deletes most of the chain: the whole
   `Result[Node, ParseError]` wrapper on the parse path is worth 5% of census
   user cycles, and the 56-byte token snapshot the parser reads `kind` through
   is already a four-byte compare in the machine code.

**Where it lands.** With the defect fixed, headers gone, views as values, no
`Result` wrapper, the runtime in the LTO unit and the output buffer not
regrowing, one binary produces byte-identical output at **1.25× Zig on census
and 1.37× on render** (15 interleaved rounds), retiring *fewer* instructions
than Zig on census (121.6 M against 155.0 M) and the same count on render
(182.1 M against 181.6 M). Its profile shows the tokenizer, the parser and the
tally at parity with Zig's. What remains is memory: two thirds of the census
residual and half of the render residual are kernel cycles, and most of the
rest is fault-adjacent user stalls. The list representation's growth garbage
and header objects, the arena's chunk granularity and the `finish` snapshot
copy are the last items, and one language change — a frozen slice with
in-place growth — covers most of them.

Every number is a fresh measurement on this machine (i7-12700H, CPU 6,
`cpu_core` PMU) against `.tmp/runtime-audit-20260919/input8.sexp` (7.42 MB),
with output verified byte-identical to the Zig reference on every arm and run.
Evidence, scripts, probe diffs and hashes:
[`experiments/parity-audit-20260920`](../../experiments/parity-audit-20260920/README.md).

## 1. Where the chart arm stands

`chart` is the binary the chart measured (`.tmp/bench/armsset/maxperf/whole-o3.bin`):
one LLVM module at O3, invocation arena with the production 96-byte object
headers, root publication and safety checks removed. `ctl` is the same arm
rebuilt from an unmodified copy of the port by this audit's harness, so every
probe below differs from `ctl` by one guest edit. Nine `perf stat` rounds each.

| census | task-clock ms | cycles user M | cycles kernel M | total M | instructions M | page faults | total / Zig |
|---|---:|---:|---:|---:|---:|---:|---:|
| zig | 13.28 | 41.6 | 19.5 | 61.1 | 155.0 | 4,132 | 1.00× |
| chart | 21.77 | 63.3 | 38.1 | 101.4 | 155.3 | 9,685 | 1.66× |
| ctl | 21.52 | 62.3 | 38.0 | 100.2 | 155.3 | 9,684 | 1.64× |

| render | task-clock ms | cycles user M | cycles kernel M | total M | instructions M | page faults | total / Zig |
|---|---:|---:|---:|---:|---:|---:|---:|
| zig | 18.83 | 52.3 | 34.3 | 86.6 | 181.6 | 5,528 | 1.00× |
| chart | 48.99 | 139.8 | 84.3 | 224.1 | 360.4 | 21,128 | 2.59× |
| ctl | 48.88 | 139.6 | 84.3 | 223.9 | 360.4 | 21,128 | 2.59× |

Peak RSS: 32.6 MiB against 16.6 MiB on census, 77.6 MiB against 21.9 MiB on
render. The arm's own heap statistics: 80,881 allocations on census, 236,158 on
render, zero collections.

**Census.** Instructions are equal; cycles are not. Of the 40.3 M cycle gap,
18.6 M is kernel time. A further 13.9% of the arm's *user* samples land on the
kernel entry address (Zig: 2.8%) — user cycles lost around page faults, about
7.5 M more than Zig. That leaves roughly 14 M cycles of genuinely slower user
code, at IPC 2.50 against 3.75, with 2.3× the L1 misses and 6× the LLC misses;
the dead root stores of item 0 turn out to be most of it.

**Render.** 137.5 M cycle gap: 50 M kernel, about 17 M user fault-adjacent,
about 70 M in code. Subtracting census from render leaves 205 M render-only
instructions against Zig's 26.6 M — 1,700 instructions per node against 220 —
of which 111 M are the dead root stores.

Where the user cycles go (self cycles, `cpu_core/cycles/u`, 20 runs, ×100 k):

| census, chart arm | share | | Zig | share |
|---|---:|---|---|---:|
| `bytes.find_any` (string bodies) | 17.7% | | `Tokenizer.next` | 58.5% |
| kernel-entry skid | 13.9% | | `parseNode` | 23.8% |
| `next_raw` | 11.6% | | `tally` | 6.1% |
| `parse_node` | 11.1% | | `ArenaAllocator.alloc` | 5.0% |
| `advance` | 7.6% | | kernel-entry skid | 2.8% |
| libc `memcpy` (three entry points) | 9.9% | | | |
| `read_string`, `tally`, `parse_list`, `parse_leaf`, `read_atom` | 14.6% | | | |
| `heap_alloc_at`, `qbe_heap`, `list_append` | 4.4% | | | |

| render, chart arm | share | | Zig | share |
|---|---:|---|---|---:|
| `push_node` (self) | 14.9% | | `Tokenizer.next` | 45.3% |
| kernel-entry skid | 13.3% | | `parseNode` | 17.5% |
| `bytes.find_any` | 8.0% | | `printNode` | 9.7% |
| libc `memcpy` | 8.9% | | `estimateWidth` | 9.5% |
| `next_raw`, `parse_node`, `advance` | 13.6% | | `memcpy` | 3.9% |
| `bytes_buffer_append_range` + `buffer_grow_rooted` | 5.9% | | | |
| `estimate_width`, `is_short_list` | 4.9% | | | |
| `qbe_heap` (one call per function entry) | 3.3% | | | |
| `bytes_scalar_count_range`, `bytes_view`, `heap_alloc_at` | 6.7% | | | |

Inclusive (LBR call chains, render): `push_node` 57%, `is_short_list` 23%,
`estimate_width` 19%, `append_range` 12%, `scalar_len` 10.5% — of which only
1.4% is the count itself; the rest is allocating a view object to count through.

## 2. The gap is bytes first

**Huge pages do not close it.** `GLIBC_TUNABLES=glibc.malloc.hugetlb=1` makes
the arena's `calloc`'d 4 MiB chunks THP-backed (`transparent_hugepage` is
`madvise` here). Faults fall from 9,684 to about 2,500 on census and from
21,128 to about 3,400 on render; user cycles fall 9% and 7.5% (the TLB walks
and fault entries); **kernel cycles do not fall** — zeroing a 2 MiB page costs
what zeroing 512 small ones did, and `defrag=madvise` adds compaction stalls
with 36–44% run-to-run variance. Wall time is unchanged. The kernel cost is
proportional to bytes touched, so the fix is to touch fewer bytes. From the
counters, each extra 4 KiB page costs about 3,350 kernel cycles plus roughly a
third of that in user-side stalls: **about 1.1 M cycles per MiB**.

**Where the bytes come from.** Counting the input's forms (32,400 forms,
120,760 children, a median of 3 children per form) and applying each
representation's rules:

| census tree storage, 7.42 MB input | MiB touched |
|---|---:|
| mylang today: 64-byte `Node`, 96-byte object header, 72-byte list header, capacity 4 then doubling | 21.3 |
| same without object headers (the compact arm) | 14.8 |
| no object headers and no list-header objects | 12.6 |
| 16-byte header, children as an inline slice, 56-byte node | 12.1 |
| final node storage alone (64-byte nodes) | 7.4 |
| Zig `ArrayList` growth if every growth copied (upper bound) | 16.3 |
| Zig after `toOwnedSlice` and in-place arena `remap` (what RSS shows) | 6.5 |

The arm's reserved chunk bytes (35.1 MiB, less the 7.1 MiB source) and its RSS
agree with the first row; Zig's RSS of 16.6 MiB (7.1 MiB of it the source)
agrees with the last. Three things separate them: the object header (7.8 MB
over 80,881 allocations), the per-form list-header object and the pointer
chase it adds (32,400 of them), and the growth garbage an arena cannot reclaim
unless the youngest allocation grows in place and a finished list is shrunk
to fit.

Render adds two more. `bytes.view(start, end)` — the port's way of counting an
atom's scalars for the width estimate — allocates a 72-byte view header plus
the 96-byte object header per call, and the width estimate revisits each node
from up to four ancestors: about 125,000 view objects, 20 MiB, on a workload
that keeps none of them. The output builder starts at 64 bytes and doubles to
8 MiB (16 MiB of blocks for a 5.6 MB result), and `finish` copies the result
once more into an immutable snapshot. Zig's `Writer.Allocating` grows one block
in place inside the arena and hands the slice over.

## 3. Probes: one edit each, priced on the arm

Every probe is a copy of `experiments/sexpr-port` with one edit that emulates a
language or ABI change from inside the language, built through the same
harness as `ctl`, verified byte-identical on both workloads, and measured in
the same batch. Diffs are in `experiments/parity-audit-20260920/probes/`.

| probe | emulates | edit |
|---|---|---|
| `pa` | views as values; a range scalar count that allocates nothing | `scalar_len` returns the byte length instead of allocating a view to count through (an upper bound: it also removes the count loop) |
| `pb` | reading a scalar field through a class field without snapshotting the aggregate | `Cursor` gains a scalar `kind` written in `advance`; the eof/rparen checks read it |
| `pc` | return-slot forwarding / an error-union ABI with no wrapper copies | the parse path returns a bare `Node`; a failure is recorded on the cursor and a placeholder node returned (valid input takes the same path as before) |
| `pall` | all three | |
| `pres` | in-place buffer growth (no doubling garbage) | `pall` plus `render_bytes` reserving the final size up front (a fixture constant; pricing only) |
| `*-compact` | a small object header | the existing headerless compact arena on the same closure |
| `*-rootclean` | root records not emitted | the parallel audit's `root_stores` transformation applied to this audit's arms (`scripts/rootclean.py`) |
| `zlink` / `lto` | the runtime inside the optimization unit | every runtime C unit compiled to bitcode and linked with the guest module by `zig cc -flto`; the `--wrap` shim replaced by renaming, because this toolchain's linker rejects `--wrap`; `zlink` is the same objects linked the same way without LTO |

Batch 1 (nine rounds each, `ctl` as the base):

| census | cycles user M | cycles kernel M | total M | Δ total | instructions M | page faults |
|---|---:|---:|---:|---:|---:|---:|
| ctl | 62.3 | 38.0 | 100.2 | | 155.3 | 9,684 |
| ctl-compact | 57.8 | 31.3 | 89.1 | **−11.1** | 151.2 | 7,789 |
| pa | 62.8 | 38.0 | 100.9 | +0.7 | 155.3 | 9,684 |
| pb | 67.2 | 38.0 | 105.2 | **+5.0** | 155.9 | 9,684 |
| pc | 60.0 | 37.2 | 97.2 | **−3.0** | 153.8 | 9,684 |
| pall-compact | 58.2 | 30.9 | 89.1 | −11.1 | 150.5 | 7,788 |

| render | cycles user M | cycles kernel M | total M | Δ total | instructions M | page faults |
|---|---:|---:|---:|---:|---:|---:|
| ctl | 139.6 | 84.3 | 223.9 | | 360.4 | 21,128 |
| ctl-compact | 129.2 | 64.8 | 194.0 | **−29.9** | 349.2 | 15,591 |
| pa | 121.7 | 64.5 | 186.2 | **−37.7** | 310.0 | 16,009 |
| pb | 142.6 | 82.6 | 225.2 | +1.3 | 361.0 | 21,128 |
| pc | 136.5 | 83.2 | 219.7 | **−4.2** | 358.9 | 21,128 |
| pall-compact | 116.3 | 55.5 | 171.8 | **−52.1** | 303.6 | 13,267 |
| pres (on pall) | 116.0 | 54.3 | 170.3 | **−15.5 vs pall** | 309.2 | 13,957 |
| zlink (pall-compact) | 111.0 | 54.9 | 165.9 | | 317.6 | 13,264 |
| lto | 101.3 | 54.6 | 155.9 | **−10.0 vs zlink** | 276.4 | 13,265 |

(`lto` against `zlink` on census: 82.8 against 88.4 M, −5.6 M.)

`pb` and `pc` were re-measured over 15 interleaved rounds: `pb` is +4.6 M user
cycles on census every time (median 66.7 M against 62.1 M) for +0.6 M
instructions; `pc` is −3.1 M on census and −2.4 M on render. The disassembly
explains `pb`: in `ctl`, `parse_list`'s eof and rparen checks are already
`cmp $0x8,%eax` and `cmp $0x1,%eax` on a four-byte load — LLVM's scalar
replacement narrowed the 56-byte snapshot away — so the probe adds a store
next to the token store and removes nothing. On this arm, aggregate-field
snapshots through a class are not a lever. The header and view savings overlap
by the views' own headers (15.5 M), which is why `pall-compact` is −52 M and
not −68 M.

**The root-record defect, and the composition.** Applying the parallel audit's
transformation to this audit's arms removes 4,580 private root-record stores
from `ctl` and 4,485 from `pall-compact`; `push_node`'s machine code shrinks
from 2,752 lines to 362. The final batch runs the composition against Zig, 15
interleaved rounds in random order, medians:

| census | task-clock ms | cycles user M | cycles kernel M | total M | instructions M | page faults | total / Zig |
|---|---:|---:|---:|---:|---:|---:|---:|
| zig | 14.13 | 41.4 | 21.6 | 63.0 | 155.0 | 4,133 | 1.00× |
| chart | 23.42 | 62.6 | 39.1 | 101.6 | 155.3 | 9,685 | 1.61× |
| ctl-rootclean | 20.95 | 53.5 | 38.9 | 92.4 | 133.3 | 9,684 | 1.47× |
| pallc-rootclean | 18.92 | 50.9 | 32.1 | 83.0 | 129.1 | 7,788 | 1.32× |
| lto-rootclean | 17.98 | 46.5 | 32.4 | 78.8 | 121.6 | 7,785 | 1.25× |
| final (+ pres) | 18.32 | 46.5 | 32.2 | 78.7 | 121.6 | 7,785 | **1.25×** |

| render | task-clock ms | cycles user M | cycles kernel M | total M | instructions M | page faults | total / Zig |
|---|---:|---:|---:|---:|---:|---:|---:|
| zig | 19.71 | 52.5 | 31.3 | 83.8 | 181.6 | 5,529 | 1.00× |
| chart | 52.27 | 138.5 | 83.5 | 222.0 | 360.4 | 21,129 | 2.65× |
| ctl-rootclean | 42.35 | 98.5 | 82.8 | 181.3 | 249.7 | 21,128 | 2.16× |
| pallc-rootclean | 31.57 | 79.3 | 54.8 | 134.1 | 203.5 | 13,267 | 1.60× |
| lto-rootclean | 29.77 | 71.3 | 54.9 | 126.3 | 182.1 | 13,264 | 1.51× |
| final (+ pres) | 27.34 | 67.5 | 47.6 | 115.2 | 182.1 | 11,212 | **1.37×** |

## 4. What to change, ranked by measured price

Prices are total cycles (user plus kernel) on this input; each is the step
from the row above it in the final batch unless a batch-1 probe is named.

**0. Root records: a lowering contract, not a store to delete.** Compiler.
−9 M (census) and −41 M (render), 24% and 29% of the respective gaps, and
−22 M / −111 M instructions. The record's `previous`, `address`, `type` and
inline-value words are written to the stack through integer-typed addresses,
so LLVM keeps every store even after the publishing store is gone. In a
non-collecting or arena mode the emitter must not produce them; in the
collecting mode they belong at safepoints (calls that can collect), where the
existing effect analysis already knows which calls those are. The fix also
means the chart's arm was mislabelled as root-free.

**1. Object header: 96 bytes to 16 or fewer.** ABI. −11 M (census) and
−30 M (render) in batch 1, plus −1,900 / −5,500 page faults.
`myl_native_object` carries two list links, a descriptor pointer, two sizes,
three flags and 16 bytes of alignment padding; a mark word plus a
descriptor-and-size word is what the collector needs per object, and the
`next`/`pending` links belong in a side table or per-chunk map. The production
GC arm gains the same bytes.

**2. Byte views are values.** Language and ABI. −38 M on render in batch 1
(about −33 M once the count loop's own 4.6 M is set aside). `bytes.view(a, b)`
returns a heap object today; a view is three words and should cross as one,
and the runtime entry points that operate on a range — `scalar_count`,
`parse_int`, `parse_float`, equality, `find`, `append_range` — should take
`(bytes, start, end)` and never see an object. The 2026-09-20 language audit
asked for this surface; this is its price. `parse_leaf` pays the same
allocation for every integer and float literal on census (10,160 of them).

**3. A frozen slice, and an arena that grows the youngest allocation in
place.** Language and runtime. This is now the largest *remaining* item, see
§5. A finished `list[T]` should be freezable into a 16-byte `{ptr, len}` value
that lives inline in a record or union payload, is indexed and iterated by
address, and is shrunk in place when frozen; `Node.form` would hold that slice,
not a pointer to a 72-byte list object with its own header and separately
growing storage. `myl_native_list_append` should ask the arena to extend the
current block before allocating a new one. Modeled: the census tree goes from
14.8 to about 7 MiB in the headerless arm; measured: the final arm still faults
3,650 more pages than Zig on census (14 MB) and that memory is this.

**4. The runtime inside the optimization unit.** ABI / build. −4.2 M (census)
and −7.8 M (render) on top of root-clean; −5.6 M / −10.0 M against `zlink`
before it. Ship the runtime as bitcode for the LLVM backend and link with
`-flto` (the toolchain rejects `--wrap`, so a shim has to be applied by
renaming as here). Independently of LTO, three helpers deserve inline lowering
because they are one compare in the common case: the reserved-capacity path of
`list_append`, the capacity-sufficient path of `bytes_buffer_append_*` (today a
call into `buffer_grow_rooted` per append), and `myl_qbe_heap`, a function
call that adds a constant to `ctx` and costs 3.3% of the chart arm's render.

**5. Output buffer: grow in place, write without a snapshot.** Runtime and
language. −11.1 M on render in the final batch (−15.5 M in batch 1) for the
doubling garbage alone; the `finish` copy of the 5.6 MB result is another
5.6 MB of touching plus the copy. Item 3's in-place growth covers the first
half; a `Stream.write(buffer)` that writes the live storage covers the second.
`byte_builder.finish` keeps its snapshot semantics.

**6. Return-slot forwarding, or an error-union ABI.** Compiler and ABI.
−3.1 M (census) and −2.4 M (render). Today `Ok(node)` blits the 64-byte node
into a 72-byte `Result` scratch, `ret` copies that into the caller's `sret`
buffer, and the caller's `?` reads the payload in place; LLVM's inliner folds
much of it, which is why the whole wrapper is worth 5% of census user cycles
and not the 20% earlier IL blit counts suggested. What is left is letting the
callee construct the payload directly in the caller's buffer.

**7. Aggregate list elements by reference.** Compiler. Not probed (it cannot
be expressed in the language); from the final arm's profile, `list_get` plus
its `memcpy` are 2–4% of render user cycles: `entries[i]` and `for child in
entries` call `myl_native_list_get`, which copies 64 bytes into a scratch slot
the by-address call convention then passes on. The rule QBE-AGGREF-1 applies
to parameters — a read-only consumer gets the address — applies unchanged to
`storage + i * stride`, with the generation check hoisted out of the loop.

**Not levers on this arm, measured:** the class-field snapshot (`pb`, a 7%
regression; LLVM already narrows it), the tokenizer (26 M against 24 M cycles;
`bytes.find_any` is a `memchr`-style scan already), safety checks (removed in
this arm), and whole-module inlining (already on). The scalar `match` payload
bindings that copy the whole payload before extracting one field (`tally`'s
24- and 56-byte blits) are real in the IL, but the same inliner removes them
here; they matter for the QBE backend, not for this arm.

## 5. Where parity lands, and what is left

The final arm — items 0, 1, 2, 4, 5 and 6 applied, item 3 not — is **1.25× on
census and 1.37× on render**. Its residual against Zig:

| residual, final − Zig | user cycles M | kernel cycles M | page faults | instructions M |
|---|---:|---:|---:|---:|
| census | +5.1 | +10.6 | +3,652 (14 MB) | −33.4 |
| render | +15.0 | +16.3 | +5,683 (22 MB) | +0.5 |

The final arm's census profile: `find_any` 24%, `next_raw` 14%, `advance` 9%,
`read_atom` 3% — 23.4 M cycles of tokenizing against Zig's 24.2 M; `parse_node`,
`parse_leaf`, `list_append`, `number_parse` and the libc `memcpy` entries —
10.1 M of tree building against Zig's 12.9 M; `tally` 1.9 M against 2.5 M; and
**16% of the user samples on the kernel entry address**, 7.5 M cycles against
Zig's 1.2 M. The user residual on census is entirely fault-adjacent stall; the
code is at parity. The kernel residual is the 14 MB the tree still touches
beyond Zig's: the 32,400 list-header objects (2.3 MB), the capacity-4-then-
double growth garbage (about 5 MB), 64- against 56-byte nodes (1 MB), the
4 MiB chunk granularity and the runtime's own tables. That is item 3.

Render's residual is the same story plus 22 MB: the tree, the 5.6 MB `finish`
snapshot, and the float spellings the printer still formats through `str`.
Its user residual is 13 M of fault-adjacent stall and about 6 M in the printer
proper — `push_node` 4.7%, `estimate_width` 3.2%, `append_range` 5.1%,
`list_get` 2.1% and their `memcpy`s, against Zig's `printNode` 9.7%,
`estimateWidth` 9.5% and `memcpy` 3.9% — which is items 4 (inline append fast
path) and 7.

So the honest answer to "what would parity take": items 0–2 and 4–6 are
priced and take the arm from 1.61×/2.65× to 1.25×/1.37×; item 3 plus a
snapshot-free write covers most of what is left, and the arm's user-side code
is already at Zig's speed. The remaining risk is not a hidden codegen gap but
the memory contract: an arena that grows and shrinks its youngest block in
place, a slice type that lets a finished list live inline, and a runtime that
does not touch 168 bytes to look at three words.

## 6. Method and limits

- Harness: `scripts/probe.sh` builds the LLVM-O2 closure through
  `mylang build --qbe=qbe_llvm.py`, joins the IL manifest and runs
  `maxperf/build.py` for the requested arms exactly as `.tmp/bench/arms.sh`
  does; `scripts/rootclean.py` regenerates an arm's merged IR with the
  parallel audit's `root_stores` transformation after asserting the arm's own
  lowering reproduces its IR byte for byte; `scripts/lto.sh` builds the
  `zlink`/`lto` pair; `scripts/measure.py` runs nine `perf stat` rounds per arm
  and workload on CPU 6 after byte-comparing every output with the Zig
  reference. The final batch is 15 rounds in random interleaved order.
- Counters are `cpu_core` events; kernel cycles are `cycles/k`. Cycle counts
  are the comparison; task-clock is reported for scale. One batch
  (`measurements/rootclean.json`) ran while the machine was loaded — Zig's own
  census user cycles read 48.9 M there against 41.4–41.6 M elsewhere — so its
  ratios are not quoted; its within-batch deltas agree with the final batch.
- Profiles are `cycles:u`, period 100 k, 20 runs (12 for LBR call-chain
  profiles). Samples on the kernel entry address inside a user-only profile
  are reported as "kernel-entry skid" and read as fault-adjacent user cycles.
- `pa` over-prices item 2 by the count loop (4.6% of render user cycles) and
  `pc` under-prices item 6 for invalid input, which it does not exercise;
  `pres` uses a fixture constant and is a price, not a design. The `lto` arms
  compile the runtime with `zig cc -O2` rather than `zig build-obj
  -OReleaseFast`, so they are compared with `zlink`, built the same way. The
  root-clean transformation is the parallel audit's and inherits its proof
  obligations; it is diagnostic and must never be linked to a collecting heap.
- The compact arena's writer reads a header the compact arena does not
  allocate (`buffer_frozen`, noted in the 2026-09-20 next-steps review); every
  compact arm here produced byte-identical output, but the arm stays an
  experiment. The unchecked shim and the `--wrap` renaming were verified by
  output identity, not by a trap matrix.
- No production source changed, no Guardian gate ran, and nothing here is a
  QBE-backend result: the production QBE arm carries the GC, roots and checks
  the arena arm drops, on top of everything measured here.
