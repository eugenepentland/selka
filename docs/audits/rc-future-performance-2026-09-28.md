# RC runtime: design notes and future performance work, 2026-09-28

A reference note for later work on the reference-counting runtime (D9 WP-4),
written after the RC performance rounds of 2026-09-27/28
([close-out report](rc-perf-closeout-2026-09-27.md)). It explains one design
choice that is easy to question (two counts per object) and lists the
performance work that remains, ranked, with the evidence behind each item.
Nothing here is scheduled: the user accepted a geomean of about 1.08x the
tracing GC's instructions, with every corpus row at or below 1.3x, made RC the
default runtime (RC-DEFAULT-1; `--gc-runtime` is the opt-out) and paused.

## Where things stand

- Corpus (43 programs x QBE/LLVM, full size, retired instructions vs the
  accepted GC binaries): geomean 1.072 (QBE) / 1.082 (LLVM), every row at or
  below 1.3x (worst: sort_records 1.28 QBE, sort_quick 1.28 LLVM). Median peak
  RSS is about 40% below GC's.
- Tools that make the work below cheap:
  - `experiments/rc-perf-20260927/quick.py`: the whole corpus on both
    backends in seconds, every output checked against GC.
  - `--rc-runtime=sites` (docs/tooling/ownership.md): ownership events per
    call site, sorted, with source lines.
  - The differential fuzzer, `experiments/rc-fuzz/` (`zig build test-rc-fuzz
    -Dfuzz-seeds=N`): GC vs RC modes on generated programs. It found four real
    bugs the suites missed.
- The acceptance rule D9 set for WP-4 asks for a geomean of at most 1.0x; the
  items below are what it would take.

## Why each object has two counts

Every RC object carries a 32-byte prefix before its payload: `owners`,
`holds` (one machine word each), then the 16-byte common header the GC also
uses (type descriptor, mark bits, region).

| Count | What increments it | What it decides |
|---|---|---|
| `owners` | A stored value: a variable, a record field, a collection element | Uniqueness. Copy-on-write mutates in place only when `owners` is at most 1 and the mark bits say the payload is not shared, pinned, arena-owned or immortal |
| `holds` | A lifetime-only token: a temporary loan (a borrowed read the compiler could not prove safe), a receiver pin while `a.b[i] = f(...)` runs, an iterator, a view | Nothing about sharing; it only keeps the memory valid |

An object dies when both reach zero.

**The reason.** mylang has value semantics: after `b = a`, a mutation of
`a` must not be visible through `b`. With copy-on-write, "mutate in place" is
legal only if nobody else semantically holds the value. If temporary borrows
incremented the same counter, every borrow would make the value look shared,
and the next mutation would copy the whole collection even though no other
variable holds it. Typical cases are reading an element to pass it to a
function and then appending to the list, and iterating a list while updating
a field of the record that owns it. A separate `holds` count keeps the
borrowed object alive without defeating in-place mutation.

**How other RC languages avoid the second count.** Koka (Perceus) and Lean 4
prove borrows safe at compile time and emit no count operation for them, so
one count suffices. Swift passes arguments at +0 ("guaranteed") where it can;
its extra counts (unowned, weak) exist for cycles, not borrows. mylang's
`holds` is the runtime fallback for borrows the compiler cannot prove safe.

**How much it is used now.** On 2026-09-27 the fallback was hit constantly
(Lox binary_trees N8: 27M hold acquire/release pairs). Later rounds proved most
of those borrows statically (read-only parameter anchors, interval anchors,
element borrows, transient field reads, inert receivers), so they now emit
nothing, as in Koka. Holds remain for receiver pins and for borrows the proofs
refuse.

**What it costs.**

- Memory: one word per object. With `owners` it makes the RC header twice the
  GC's 16 bytes, and RC size classes round to 16 bytes. This is the whole
  reason `scan_split` (about 660K small strings) is the one corpus program that
  still uses more memory than GC (76 vs 66 MB).
- Complexity: every emitted operation must pick the right token kind; a hold
  released as an owner (or the reverse) is a bug class, and several findings
  of the adversarial review sat in the proofs that decide when a loan can be
  skipped.

## Future performance work, ranked

Estimates are rough and come from the lane reports and profiles of the RC
rounds; "Lox" means the Lox VM corpus rows. Measure every change with
`quick.py` (full size for acceptance), rank sites with `--rc-runtime=sites`,
and run the fuzzer plus the adversarial repros before merging any new proof.

### 1. Object layout (memory, and some instructions)

| Item | Evidence | Expected effect | Effort / risk |
|---|---|---|---|
| **Collapse to one count** | Holds are now rare; Koka/Lean show one count suffices when borrows are static | 8 bytes less per object; simpler protocol; fewer token-kind bugs | Large. Needs a replacement for the remaining holds: receiver pins could use an owner plus the existing PINNED mark bit (the pin already restores the prior bit), and unproven loans could become owner retains with a "loan" flag that uniqueness ignores. Every hold site must be audited |
| **Smaller counts** | Counts are `uintptr_t`; no program nears 2^32 references to one object | 32-bit `owners` + 32-bit `holds` in one word: header 32 -> 24 bytes without changing the protocol | Medium. Needs overflow handling at 2^32 (trap or saturate-and-leak, as some runtimes do) and an ABI version bump; size classes then round to 8 |
| **Fold counts into the common header** | GC and RC share a 16-byte header whose mark word has spare bits | Header 16 bytes, matching GC: fixes scan_split's memory | Large: touches the shared header ABI and the GC |

### 2. Remaining ownership traffic (instructions)

| Item | Evidence | Expected effect |
|---|---|---|
| Callee summary "writes only scalar fields" | OWNERSHIP-MUT-RECORD-WRITE-1/2 (the review's GC value-semantics fix, narrowed by lane M) still makes real copies when a callee receiving a `mut` record only writes scalar fields, e.g. `frame.constants[read_byte(mut frame)]` in 29 Lox functions. Free under RC today but real copies under GC | GC-side copies; guards RC against the same regression class (lane M measured 1.18 -> 1.37 on Lox method_call before WRITE-2) |
| No-alias fact for `mut` parameters | RC-INTERVAL-ANCHOR-3/4 refuse anchors when two `mut` parameters could alias. Lane M measured zero cost on this corpus, but any multi-`mut` API pays; a per-call-site proof that callers pass disjoint roots would recover it soundly | Other programs, not the corpus |
| Receiver scopes whose root is a `mut` list parameter | Lox `heap::set_object_field`'s element write and `set_instance_field`'s call scope keep their pin/scope (lane K) | A few % on Lox rows that set fields |
| `mut` list argument pins per call | nbody and sort_quick pay scope begin/pin/end for every `mut` list argument (lane F); needs a summary that the callee never shares its `mut` parameter | nbody LLVM 1.26 and sort_quick LLVM 1.28 toward 1.0 |
| Per-call frame copies in Lox | `frame = load_frame(...)` copies the three-list ExecFrame on every call and return (lanes G, K) | Lox call-heavy rows (method_call, invocation, closures) |
| Borrowed-call result copies | Schematic copies 128-byte `Pin` records returned by borrowed calls; GC points at the call's result buffer (lane J) | Schematic 1.23/1.19 toward 1.1 |
| General last-use move | RC-LAST-USE-MOVE-1 was tried by lane K: +1% on Lox LLVM but alloc_churn LLVM +3.2%, list_records +1.1%; reverted | Worth revisiting with a cost model (move only where the source would otherwise be retained) |
| Hoisted uniqueness checks on dictionaries | knucleotide still checks `counts` uniqueness every iteration (about 3%) (lane L) | Small |
| `byte_buffer(list)` treated as fresh | str_build clones once at loop entry because the cast result is marked shared; treating a list->bytes cast as fresh in `value_semantics.classify` removes it in GC too (lane L) | Small, both runtimes |

### 3. Runtime and code generation (instructions)

| Item | Evidence | Expected effect |
|---|---|---|
| Dense compiler-assigned type ids | Metadata lookups still hash type-descriptor addresses (e.g. `drain_one`), which costs instructions and makes rows move 1-3% with binary layout alone (lanes C, J, L) | Removes layout noise and a lookup per death |
| Scope protocol inline in IL | A pin+unpin is still 150-180 instructions after forced inlining; emitting it in IL with alias classes for the RC state would let LLVM cut 20-40 per pin (lane I) | About 2-4% LLVM geomean |
| Skip the exit-time teardown walk | Schematic spends about 0.5M instructions (22% of its LLVM gap) walking the heap at normal exit (lane J). GC has an `exit_without_sweep` mode; RC could free extents wholesale at exit in non-counting builds, as trap teardown already does | Schematic LLVM; any program with a large live heap at exit |
| `myl_qbe_heap` inline | Still an out-of-line call wherever `%heap` is used; computing `%ctx + offset` needs the compiler to know the context layout (merge-B note) | Small, broad |
| Role/owner drop paths | Static drops of one-word copyable values emit both paths inline; routing the role path out of line shrinks code (merge-B note) | Code size, i-cache |
| RC startup cost | Tiny inputs are dominated by startup: at smoke size Lox rows read up to 2.4x on LLVM although full size is under 1.3x. Module/metadata registration at startup could become static tables or lazy registration | Short-running programs and tests |
| ThinLTO | Under ThinLTO the metadata unit stays machine code, so glue never inlines (lane I) | Matters only if ThinLTO becomes a supported release mode |
| QBE register allocation artifacts | spectral_norm QBE moved +5.5% when slots stopped escaping (identical IL); fannkuch LLVM +4% from GEP addressing | Small; mostly QBE-side |

### 4. Compile time (dev speed)

| Item | Evidence | Option |
|---|---|---|
| Generated glue as C | Metadata unit for the Lox port grew 317 -> 742 KB (about 570 glue functions); its -O2 compile adds about 0.9 s to a cold Lox build | Emit glue as IL, or cache compiled glue per type content hash across builds |
| Forced inlining under LTO | LLVM relink of the Lox port +2.5 s, linker peak memory 375 -> 460 MB (lane I) | An ordinary inline hint keeps base cost but loses 8-16% on Lox instructions; a per-function hotness heuristic could split the difference |
| Stand-in emission reuse is off under RC | A body-edit rebuild of the 5.5k-line Lox port: 0.94 s under RC vs 0.86 s under GC (lane N, single run) | Make stand-in reuse RC-aware |
| GC runtime no longer prebuilt | The installed runtime archives are RC's now, so the first `--gc-runtime` build compiles its runtime once (lane N) | Prebuild both if GC stays a common opt-out |

### 5. Concurrency (D9 WP-5, design committed)

Counts are non-atomic today. The WP-5 design makes only values that cross a
task boundary atomic (as Lean does by marking shared objects), so
single-threaded code keeps today's costs. The two-count protocol interacts
with this: a value shared across tasks needs both counts (or the collapsed one)
updated atomically, which is another argument for collapsing first.

## Correctness items that bear on performance work

Found by the adversarial review, fuzzing and the default flip; each needs
fixing or a proof before more aggressive elision is safe (repros in the review
branch's `.tmp-review/repros/`):

- Language-level, both runtimes: collection-typed arguments are lent and see
  later in-place changes (`lst(xs, xs.pop())`); two `mut` arguments naming one
  value break copies (`nested(mut a, mut a[0])`); the `mut` collection form of
  the WRITE-2 case, `hold(box.names, mut state.boxes)`, still diverges (GC 2,
  RC 1).
- GC only: `--gc-stress` crashes (a `mut`-argument clone case; an arena case)
  and "a descriptor's scan plan disagrees with its fields" under stress, which
  suggest missing roots (every fuzz run finds a few, all reproducing on the
  pre-RC compiler); a false `R_LIST_ITERATION_MUTATION` trap when a field is
  moved while an iteration source still shares it (RC-DEAD-FIELD-MOVE-1 made
  RC match that wrong behavior).
- Unproven assumptions in merged proofs: element borrows (RC-ELEMENT-BORROW-1)
  assume no finalizer runs during an unrelated release inside the borrow;
  RC-ELEMENT-TAKE-1 and RC-INERT-COUNTED-RECEIVER-1 assume dropping an element
  never runs guest code (resource types are excluded).
- VALUE-SEMANTICS-13 and OWNERSHIP-MUT-RECORD-WRITE-1/2 change GC copy
  decisions as well as RC's.
- Many SPEC bullets still say "Experimental RC"; RC is now the default.

## Suggested order

1. Dense type ids and the exit-time teardown skip: cheap, broad, low risk.
2. The open language-level copy bugs (collection arguments, aliasing `mut`
   arguments), since they block further elision in both runtimes.
3. The `mut`-parameter summaries (scalar-only writes, never-shares, no-alias):
   they remove whole classes of pins, anchor refusals and GC copies.
4. Header work: 32-bit counts first (mechanical), then decide on collapsing to
   one count once hold traffic is measured near zero with the sites tool.
5. Compile-time items when dev speed work resumes.
