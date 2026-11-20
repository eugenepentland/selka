# RC journal review and next optimization candidates

## Scope and verdict

This is a read-only review of immediate-owner proof `2ad450cd` and stable
operand metadata `0b47cfcf`, followed by proposed work. No journal ABI or
compiler implementation accompanies this document. The review found no
conflicting address writer or admitted nonowner producer in those changes.
This conclusion is tied to the current emitter hooks and token-publication
contracts, not an assertion that later lowering changes inherit the proof.

The [stable metadata report](d9-rc-stable-journal-2026-09-26.md) records actual
QBE/LLVM validation and a modest instruction reduction. The older
[flat release profile](d9-rc-flat-release-2026-09-26.md) attributes substantial
remaining work to generated `make`, entry/cleanup and zeroing. Its percentages
are historical, not measurements of the complete current combination. The core
agent is measuring the new combination and implementing direct completed
constructor publication separately.

## Address and guard invariants

[Frame entry](../../src/qbe_rc_frame.zig) initializes all guard words before
linking the journal into the context. The optimized indices exclude local and
internal-construction entries.

| Journal position | Initial payload address | Later writers | Review result |
| --- | --- | --- | --- |
| Operand N | `%rcsN` | `values.publish`, terminal-H publication | Same address and guard word throughout the activation |
| Pending result | `%rcwork` | copied/adopted/taken values, aggregate replacement, terminal-H acquisition | Same address and guard word throughout the activation |
| Local | local or referenced caller storage | local replacement, held receiver storage | Excluded from `stableEntry` |
| Internal construction | initially `%rcinternal` | pointer construction or inline `%aggPC` | Address can change; excluded from `stableEntry` |

`typedEntry` restores both the type descriptor and ordinary flags before
publishing a live guard. Held publishers use complete metadata publication and
then flag 8. Construction pointers use flag 4. Ordinary publication therefore
does not inherit a previous held or construction role. The
[iteration identity correction](d9-iteration-identity-2026-09-26.md) broadens
terminal-H types while retaining the same operand/pending addresses.

The runtime's slot drop clears the guard before cleanup, then clears/releases
the represented value. It never rewrites the address or guard pointer. Arena
preparation closes relevant scopes and drops journal entries above its
watermark; it also does not rebind metadata. Trap unwind unlinks before resource
callbacks can reenter guest execution. A reentrant guest activation owns a
different frame, so callback execution does not change suspended-frame address
identity. These checks concern metadata stability; they do not permit moving a
live token between addresses without a guarded handoff.

## Immediate-owner proof

`producedOwner` examines only the immediately preceding completed producer and
the current top operand. It declines a branch target, borrowed-entry body,
scoped producer, terminal-H-capable type, plain result and unique resource.
The branch-target map includes jumps, conditional jumps, Result error targets
and every variant-dispatch arm.

| Admitted producer | Why the next operand has an ordinary token |
| --- | --- |
| Guest call | Canonical result is owned; a certified borrowed alternate is copied before normal result publication |
| Record/variant constructor | Transactional construction completes and publishes the result before advancing |
| Value copy | Guarded copy/take publishes an ordinary result; H-preserving cases are declined by `mayHold` |
| Local move | A borrowed local copies before publication; initialized owners transfer; H-preserving cases are declined |

Read-capture hooks preserve this invariant by preparing and republishing an
ordinary token. Mutation-place filling can replace an operand with a borrowed
receiver, but that store follows the receiver-specific lowering rather than
`prepareOperand`. Scoped projections are excluded by the previous capture
state. Local early release runs at local-store boundaries, not between an
admitted producer and its next consumer. The fast proof still uses pin/arena
aware TAKE; it does not authorize raw relocation of a pinned payload.

Future producers, capture hooks, fusion and journal-role extensions must be
reviewed at these same boundaries. Semantic value provenance alone is not a
physical initialized-owner certificate.

## Recommended order of further work

1. **Coalesce completed constructor publication.** Keep the partial internal
   journal while fields can fail, and keep existing transactional field staging.
   After all fields commit, write directly to the stable destination operand,
   publish its ordinary typed guard, and disarm the internal token in a stretch
   containing no failure or callback. Avoid complete-result
   `aggregate -> pending -> operand` staging and drops of proved-empty consumed
   operands. The core agent owns this slice. Payloadless variants may eventually
   use the same rule; a null payload does not by itself prove the old destination
   guard is empty. Unique resources stay on the existing path initially.
2. **Compact entries that can never own.** A scalar local with neither counted
   nor unique cleanup needs no runtime slot. An operand is removable only when
   the union of all reachable physical types and roles at that position is
   plain. Entry-time `unit`, an initially borrowed parameter, or one plain branch
   is insufficient. Keep pending/internal entries initially. Use an explicit
   logical-to-physical slot map and preserve reverse logical cleanup order and
   arena-watermark translation. This can retain the current C journal ABI; its
   benefit must be measured after constructor coalescing rather than assumed.
3. **Reconsider static typed metadata only if the remaining profile warrants
   it.** The design below removes more per-frame storage and publication writes,
   but introduces a larger ABI and runtime proof surface.

## Static metadata alternative

A function-owned immutable table could describe each cleanup position's
payload offset and admitted type/role records. Dynamic state would retain the
active type/role and whether an obligation is initialized. Runtime cleanup
would interpret that table in the same reverse order as today. Fixed-type
ordinary locals need less dynamic information than polymorphic operands and
pending results.

This is not simply a table of native descriptors indexed by bytecode PC:

- One bytecode constructor can put several child types through pending storage;
  a callback or refusal must see the current physical child, not merely the
  instruction's final output type.
- Ordinary owners, terminal holds, unique cleanup and fresh construction abort
  have distinct actions. Their role must remain explicit. Views inside an
  aggregate also retain the aggregate's actual H-aware shape.
- Independently emitted QBE/LLVM stack allocations have no promised relative
  offsets. Static payload offsets require a deliberately aligned contiguous
  storage slab, or one-time dynamic address cells. Local references and the
  internal `%aggPC` construction address need a dynamic fallback initially.
- A combined zero/dead and nonzero/type-role tag could replace guard plus type,
  but current uniqueness helpers write literal `1` to a guard. Those helpers
  cannot receive an encoded tag pointer unchanged. A first version can retain
  a Boolean guard and separate role index, or redesign the complete slot bridge.
- Clearing the active obligation before reentrant cleanup, preserving scope
  unwind before value drops, and aborting fresh arena construction immediately
  are required. The table must not reconstruct these rules from logical COW
  annotations.

The static format would require a versioned runtime/compiler/cache contract,
C offset/layout assertions, both backend declarations, budget/frame-size
accounting and independent malformed-layout tests. No State field or Guardian
baseline increase is proposed by this document. The current seven-field State
limit makes a cohesive existing planning object preferable to unrelated new
emitter flags.

## Required evidence before adoption

Each slice needs matched frozen compilers and both actual backends, with full
output validation and unchanged O/H/allocation counts where it only moves
bookkeeping. Record retired instructions, emitted stores/calls, stack/frame
bytes, text size and cleanup work. Separate leaf `make`, nonleaf `make`, frame
entry and cleanup; short sampling runs may overrepresent one phase. Include
the exact acceptance corpus after focused measurements, not just binary trees.

Correctness must include polymorphic operand reuse; H-to-O and O-to-H reuse;
inline and boxed partial construction; failure after each committed managed
field; arena construction abort; pin-aware clone refusal; nested callback and
unique finalizer reentry; normal return, Result propagation, bounds traps and
frame-admission refusal. Newly restored iteration mutation traps belong in the
trap replay as well as positive guest tests. The whole regression gate,
Guardian and cache invalidation checks remain required. No performance or
WP-4 acceptance threshold is claimed here.
