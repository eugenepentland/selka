# Isolate word operands of an already accepted fast loop

Status: design only, on `d9/rc-loop-operand-isolation-astra` after PC fix
`238db806` and evidence `d4933f53`. No production changes or timing. This does
not broaden loop admission or alter the immutable dictionary measurements.

## Evidence and expected mechanism

Root's `.tmp-rc/byte-private-operands` diagnostic in the integration tree has
GC and RC fast bodies with the same operations modulo SSA numbering. RC's
ordinary `%s0` and `%s1` addresses escape elsewhere in the function, so QBE
cannot promote their accesses inside the fast copy. Replacing only that
copy's word slots with existing `%s62` and `%s63` produces a register loop.
The receipt records all six SSA/assembly hashes and QBE identity. These are
archived diagnostic inputs with accounting checks, not the exact timed native
build, and there is no runtime speed claim yet.

One correction matters to admission: `%s62` and `%s63` are not globally
unmentioned. Each has one existing `alloc8 8` and one literal `storel` during
byte construction, with no load or address escape. The initial production
rule therefore permits existing **write-only, unescaped** word slots as well
as unreferenced ones. It does not select a destination from its numeric index,
the source benchmark, a presumed maximum stack height, or absence of a live
typed value at one PC.

In the saved QBE assembly, a successful byte iteration executes 23 instructions
when unequal and 27 when equal; the diagnostic private-slot loop executes 12
in either case, excluding the final exit test. Its loop also changes branch
selection to a conditional move. This is a static path count, not measured
retired traffic or a guarantee that production compilation will match. The
unchanged workload scans 8 MiB sixteen times; its 64-byte pattern has four
matching bytes. The potential is much larger than the remaining dictionary
micro-slice, but exact full-size normal builds on both backends must establish
the effect and accepted-GC distance.

## Existing storage and authority

`native_ir.analyze` computes `stack_capacity` from maximum validated operand
depth. `qbe_frame.allocateStorage` already allocates every eight-byte `%sN`
below that capacity. `frameBytes` counts the same capacity before native/heap
frame choice. The RC journal separately refers to `%rcsN` and keeps logical
operand numbers; it does not interpret `%sN` as its owned-value storage.

The proposal reuses only an already declared eight-byte slot. It neither adds
allocations nor changes capacity, execution-frame bytes, guard indices,
metadata entries, `%rcsN`, `%rcwork`, `%rcinternal`, or local storage. The
diagnostic destinations already survive `dropUnusedSlots` because of their
setup stores. An actually unreferenced existing destination might now survive
that pass, but it was already included in the conservative frame budget; it
cannot silently extend the budget.

Initial admission is RC native-stack frames only. Heap-frame lowering retries
with the original slots and original offsets: it gains no useful QBE entry
promotion from this first experiment, and refusing it avoids expanding the
proof to aliases derived from `%frame_memory`. GC output, step-enabled
compilation and all previously rejected fast loops remain unchanged.

## Closed instruction and control-flow proof

Reuse an actual accepted `qbe_loop_facts.Loop` after the existing ownership
admission and generated `copyAllocates` veto. Require the stronger existing
`qbe_rc_read_version.quietCopy` veto even when another existing rule admitted
the loop. All calls other than the existing nonreturning failure helpers
refuse isolation; they need not refuse the already valid unisolated fast copy.

Verify the validated stacks at head, backedge and every outgoing ordinary
successor are empty. Recheck explicit edges with
`ownership_sources.targetsSatisfy`, including switches/try edges in the whole
function, and fallthrough separately. Outside edges may enter only the header;
no ordinary interior edge may leave with operands or skip into the fallback.
The original facts already impose a single header and final backedge; do not
replace them with a new loop detector. Dead actions must have no reachable
incoming edge under the existing action facts; otherwise refuse isolation.

Initially every reachable operand is a normalized integer/bool/unit word,
except the exact borrowed immutable-byte pointer states already certified by
the active read-loop proof. No by-address aggregate, unique value, mutable
managed result, pending ownership publication or unsupported representation
is admitted. Read-only list operations keep the original guarded local owner;
they do not put a managed receiver on the operand stack. Existing metadata,
history, COW and release proofs still authorize the loop itself.

Within this region each logical word is defined before its first read on
every path by the validated instruction stacks. Empty entry means no word
needs copying into the isolated bank. Empty normal exits and backedge mean no
word needs copying out, including zero iterations, repeated outer iterations,
early forward exits and later use of the original slots. Locals and heap
stores carry exactly the same values at their original operations.

## Emitted proof and whole-function slot selection

Prefer a bounded post-emission rewrite over changing every direct `%s{d}`
format string. Existing scalar/collection emitters contain both shared
load/store helpers and direct formats; changing only the helpers would split
one logical word between two physical places. Do not change numeric slot
arguments passed into ownership helpers.

An accepted source proof plus accepted generated body may emit internal exact
begin/end comments around only the fast body, after all guard setup. Guard
code, original-loop text and every other instruction remain outside. A final
optional pass runs on the complete function before existing IL cleanup. It
first validates all markers and slot uses, and only then rewrites bytes.
Malformed/unsupported input or lack of a destination bank leaves the original
complete function unchanged; allocation failure remains OutOfMemory.

For each source operand occurrence in the marked body, permit only the exact
address position of a full-word `loadl` or `storel`. Reject its address as a
stored value, `copy`, arithmetic operand, call argument, `blit`, narrow access,
annotation or any unrecognized use. Use complete identifier tokens, so `%s1`
cannot match `%s10`, `%scratch`, `%rcs1`, quoted data or a comment. Require all
body `%sN` references to be covered; do not partially rewrite one word.

Additionally refuse any actual RC journal/pending/scope-storage reference in
the body. This explicit emitted check complements the source proof: quiet
calls alone do not rule out direct guard writes or metadata publication. The
exact byte-loop guard remains outside and tests the original logical journal
before the body. A failed guard selects the untouched original loop.

Whole-function destination admission requires exactly one existing native
`alloc8 8` definition and **zero reads or address-taking uses**; the only other
allowed occurrences are full-word direct stores into that address. Select a
deterministic bank from these slots, disjoint from all source slots. No cached
descriptor or runtime admission is involved. An unsupported use anywhere,
including setup, a later real H/O publication, another loop, failure cleanup
or an apparently dead block, makes that slot unavailable.

One bank may serve multiple disjoint accepted fast bodies because their
entry/exit stacks are empty and they cannot call each other or reenter this
frame. Original write-only stores elsewhere remain as emitted; their old
values are never observed. Avoid sharing the bank if marker ranges overlap.
Exact source/destination maps are reported by an internal comment for tests,
without changing source/debug positions.

Use explicit initial caps: code at most 4096 instructions, loop body at most
the existing 200-instruction bound, at most eight word positions and 32 marked
copies. Charge each candidate's instruction, actual stack-element and complete
explicit-edge visits against 262144 logical visits before scanning; this is
a per-candidate source allowance, not a total primitive-operation promise.
At most 32 such candidates are examined. Bound each generated body by the
existing 1 MiB quiet-copy limit and the final function by 4 MiB; classify
whole-function slot references in one pass, not one rescan per destination.
Any further parser/representation bound is a conservative refusal.

## Tokens, traps and reentry

Only raw evaluation words move. Every ownership count, lifetime anchor,
original metadata query and actual write remains unchanged. The selected
bank is never exposed by address, and the copied region performs no journal
publication. A failure helper receives the same already loaded scalar SSA
arguments, uses the same source position and unwinds the same journals. It
never returns into the abandoned evaluation stack. Nested finalizer guests
use their own execution frame; they have no pointer to this private bank.
There is no new cleanup or drain boundary. Inherited arenas stay held by the
unchanged local/caller authority, and transitions inside a candidate refuse.

The PC wrapper committed separately remains essential: guard queries run at
the actual head, while the rewrite starts only after those queries. A refused
speculative copy cannot leak a bank map or consume a candidate slot; native
retry and heap fallback reconstruct ordinary text as today.

## Controls and measurement gate

- Structural positives use two slots, conditional scalar joins and two
  disjoint loops; setup write-only stores and later real owner publications
  remain present. Check exact original fallback/guard bytes and logical RC
  metadata, not only the number of calls.
- Refuse nonempty entry/exit/backedge, an interior incoming edge, unknown or
  address-taking slot use, narrow accesses, direct guard writes, hidden
  publishers, calls/callbacks, incomplete destination banks, and caps.
  Identifier-prefix tests must protect `%s1`/`%s10` and `%rcs1`.
- Actual guests cover zero/one/many iterations, both scalar branches, outer
  reentry, real iterator H tokens, snapshots, inherited arenas and an adjacent
  dictionary loop. Traps cover guard fallback bounds/overflow, frame/physical
  admission, step-mode refusal, and public finalizer reentry. A forced heap
  frame proves unchanged fallback behavior and allocation accounting.
- Compare actual QBE and LLVM O3/full-LTO output and complete counted records;
  no O/H/clone/allocation deltas are expected. Verify the measured native loop
  uses the admitted isolated slots and that native/backend identities match.
  Only after review and freeze run unchanged full `bytes_scan`, median three
  retired instructions at 100% running on CPU11, against an immutable matched
  before and accepted GC. No full corpus. Root owns the combined four-command
  gate; this tree runs focused controls and Guardian88.

Expected source scope is a new bounded helper/test module, tiny accepted-copy
marker hooks in `qbe_loop_version`, and one optional complete-function pass in
`qbe.zig`. No runtime, descriptor, journal-layout or default changes. Confirm
shared-file reservations before implementation.
