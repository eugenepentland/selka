# Stage 4 adjacent variant-read proposal

This records the pre-implementation compiler design and source audit.
The implementation and measurements are reported separately in
`d9-rc-adjacent-variant-read-2026-09-27.md`. It uses the corrected joined source
`5b87601297f01810968b9f7ac554c484d5848cca` and immutable Debug compiler
`f87393b249f45699d63a1f5a81dc47fb59faa41d1396fc8035131d7b2533b120`.
The accepted historical GC baseline and the complete Lox workload remain
unchanged. The runtime worker owns new profiling and the independent native
type-fact cache; this audit ran no benchmark or compiler build.

## Evidence and priority

The 58 remaining `vm::run` native-loan sites are all eligible for the existing
flat runtime path. Their exact native layouts are 26 pointers to `list[Value]`,
22 pointers to `list[CallFrame]`, two pointers to `list[int]`, and eight copies
of the 40-byte `ExecFrame` with three list pointers. The variant-valued `Value`
element does not make a loan of its containing list pointer traverse elements.

Source operations account for those sites as follows:

| Sites | Source operation | Current proof boundary |
| --- | --- | --- |
| 28 | Fourteen list-field reads; each loans the projected list and loans it again into a private receiver | Read-loan roots currently require a direct local collection, not a record-field projection |
| 22 | Ten value-stack stores and twelve call-frame `ip` stores | Inert receiver ancestry permits list-element ancestors, not enclosing record fields; some stack stores also evaluate calls |
| 8 | Four `ExecFrame.ip` assignments, each capturing its three-list record twice | The plain-record-write certificate currently admits caller storage, not an ordinary owning record local |

These static counts are not dynamic weights. The fresh joined QBE hardware
branch sample instead identifies generic native loans in `heap::string_obj`,
`heap::set_object_field`, `vm::load_frame` and `vm::get_property`. The runtime
worker's sample attributes roughly 8.4% of total sampled weight to
`native_has_unique` reached directly from native loan, and roughly 2.2% from
physical retain. Throttle events make these qualitative directions, not
performance acceptance measurements or complete reconstructed stacks.

The dominant string accessor loan passes native type
`myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14`:
the 56-byte `object.Obj` variant, with ten payload descriptions. Its generic
loan validates all native arms, seeds the active value, acquires its active H
edges, and later walks those edges again to unloan. The immediately following
ordinary variant switch independently retains only its selected payload.

| Function and source | Exact Object-read PC | Following operation |
| --- | --- | --- |
| `heap::string_obj`, `heap.my:130` | 15 | Match, retaining the 16-byte `StringObj` into an ordinary owning arm local |
| `heap::set_object_field`, `heap.my:220` | 14 | Match, retaining `InstanceObj` before extracting and mutating its table |
| `vm::load_frame`, `vm.my:32` | 16 | Match, retaining `ClosureObj` |
| `vm::load_frame`, `vm.my:34` | 37 | Match, retaining `FunctionObj` |
| `vm::get_property`, `vm.my:350` | 24 | Match, retaining `InstanceObj` before calls and possible pool mutation |

The five functions have 28 native-loan sites in total; the table isolates five
generic Object reads. The whole linked program has 43 static Object-loan sites
in 38 functions. Some are constructor/store paths and will not qualify for
this proposal. No count of admitted or dynamically executed sites is claimed.

`heap::set_instance_field` also retains two broad 208-byte Runtime captures
during its existing ordinary storeback. Its closed-field extraction already
moves the list owner correctly; optimizing its managed-field publication is a
separate proposal. It is not justification for relaxing this read certificate.

Exact current IL is copied under
`.tmp-lox-projection-audit/current/` in the collections worktree. Its
`il-identity.json`, `hot-loan-classification.json`, `object-loan-sites.json` and
`audit-identity.json` retain source paths and hashes. The immutable upstream
artifacts are in the runtime worker's
`.tmp-mut-argument/lox-post-record/current/`, including `builds.json`, the QBE
manifest and `qbe-branch-analysis.json`. The IL is from that actual build's
fragment cache. Source-location hints were cross-checked with the earlier
emission of the identical guest files; that earlier emission's IL is not
claimed byte-identical to the current binary.

## Proposed bounded certificate

The first slice eliminates only the intermediate whole-variant loan in an
exact checked list `READ` followed by the immediately adjacent ordinary
`SWITCH_VARIANT`. It keeps the existing list capture, tag dispatch, selected
payload retain, arm-local ownership and subsequent semantic SHARE events.
Nothing remains borrowed from the list after the arm's ordinary publication.

Admission records the read PC, switch PC, receiver local and exact variant
type. It requires all of the following:

1. The read is an ordinary list read of an inline variant, with a single plain
   index operand and no older stack operands. The next instruction has that
   one variant operand, the same variant type, and no external CFG entry.
   Bounds normalization and the bounds check remain at the original read PC.
2. The list receiver has concrete, private, retained local storage. Reject
   by-reference/caller storage, place aliases, inert/empty locals, borrowed
   storage anchors, iterator/live-view roles and scoped receiver projections
   in this first slice. Resolve physical representation after all existing
   proofs. A runtime guard check selects the fast path only when this exact
   local journal entry is initialized; a clear guard uses the complete old
   Object-loan path. This avoids inferring physical lifetime from semantic
   liveness or an optimistic initialization assumption.
3. No COW capture/fill/uniqueness/share/read-capture, scope begin/end,
   receiver completion, planned local cleanup or other publication may occur
   after the read obtains its interior pointer and before the selected payload
   has finished retention. Inspect actual emitter hooks at both PCs, not just
   their opcodes. Existing edge cleanup currently runs only at store edges;
   the proof must continue to fail closed if that scheduling changes.
4. The switch is an ordinary snapshot binding. Reject contract-borrowed
   dispatch and compiler Option-narrowing aliases. All arms must use the
   ordinary owned publication or a payload-free branch. A selected local may
   be reused, but its old value is released only after the incoming value is
   completely staged. Its descriptor, role and initialized guard are reset
   exactly as today.
5. The variant and all reachable payload types are copyable, with no unique
   resource, finalized typed box, live view/H field, opaque handle, callable
   authority or managed record identity. Use a bounded native/typed shape
   check, conservatively declining unfamiliar or excessively deep layouts.
   The ordinary list/bytes fields in Lox Object satisfy this intended grammar.
   This excludes dynamic finalizer-bearing payloads whose old loan validation
   would reject them and whose callbacks could observe a changed boundary.

Implementation should use a small dedicated pure certificate/emission helper,
with a narrow hook in operand result publication and an explicit cooperation
point in ordinary switch lowering if needed. It must not add a State field or
change runtime uniqueness. Bound functions at 4096 bytecode instructions,
scan at most 64 preceding instructions per candidate read, and bound authority
traversal separately at 256 distinct nodes/work items. Thus the dedicated index
scan performs at most 4096 × 64 = 262144 instruction visits per function; this
is a composed bound, not a global work counter. Representation, iteration-owner,
and existing COW-plan queries have their own function/local bounds and are
additional work. This clarifies the initial design, which proposed a cumulative
allowance without distinguishing those queries. Exhaustion declines the
optimization. The actual hot helper bodies fit these limits; final admission
must still be demonstrated against their lowered plans.

## Physical algorithm and failure proof

The original checked read produces the interior element address. On a proven
fast path, leave that address on the operand stack with its journal guard
clear. The index being consumed is plain; it owns no cleanup, and the helper
must not blit this address into storage that subsequent operand cleanup zeros.
The source is the anchored list backing, not operand scratch. On the slow path,
run the existing complete native loan and publish its normal LOAN16 guard.

The two bytecode PCs stay distinct. Step/stack failures between them unwind
the existing list capture. The raw fast operand has no token to drop. A loop
cannot enter the switch independently or reuse an old initialized operand
guard: the exact input shape and normal plain operand invariant must be checked,
with an emitted guard control as a permanent regression.

Ordinary switch lowering reads the same tag and retains the selected payload
into pending storage. The native retain path seeds and acquires all incoming
edges before its final `dispose_walk` drain. It performs no guest callback
between reading the first and last source field. The resulting pending owner
is journaled before dropping an old arm-local token. Only then are the staged
bytes published to that local and its ordinary role/guard installed. The
consumed variant operand is finally dropped: a no-op on the fast path, the
existing unloan on the fallback path. The arm can now call arbitrary code or
mutate/reallocate the object pool without retaining an interior borrowed value.

This ordering is important even with an old arm value still initialized.
The initial certificate transitively excludes finalizers and callback authority
from that old value as well as the new payload. Its release cannot reenter guest
code. Selected incoming bytes are not subsequently read from the pool.
On partial retain failure, the runtime rolls back the acquired prefix while
the list still owns the source's child edges; ordinary status/trap handling
then clears the pending result and releases existing frame obligations.

Omitting the temporary H does not change O counts, PIN bits, SHARED history or
the uniqueness predicate. That fact alone is insufficient: allocator resize
separately refuses H. The no-callback interval is essential, since hypothetical
reentry could replace the source pool, release its child O, and then expose a
resize difference between an O1 child with and without the former temporary H.
Transitive exclusion of old and new payload finalizers, plus the public drain
boundary, prevents that reentry before the former H drop. List loans hold the
header while resize acts on its raw backing; bytes/text payloads are immutable.
The unchanged list token keeps its logical
child owners alive even when its own O count is zero. Arena anchors still live
within the same region, with no arena close between the two PCs. Payload
retention uses the original destination region and preserves its refusal and
pin/arena behavior. No pin-aware copy replaces ordinary physical retain.

Public ownership helpers drain before returning to ordinary guest code, as
documented in `native_rc.h`. Guest reentry from a finalizer inherits an active
outer drain, so nested drains do nothing. The admitted interval releases no
real owner before payload retention. Therefore removing the intermediate
loan's otherwise-empty drain introduces no new callback boundary. The
unchanged selected retain and old arm-local release keep their original
callback order. Arbitrary internal C callers that enter a guest with queued
deaths outside an active drain violate this existing boundary and are not
used to justify admission.

The optimization intentionally eliminates redundant H acquisitions and their
temporary bookkeeping; their eliminated count/budget work is not promised to
remain observable. All required selected-payload ownership and its failure
cleanup remain. Failure controls must distinguish a removed redundant hold
from a broken required retain rather than requiring identical H traffic.

## Required validation before retention

- Emitted-code tests for a direct match, nested matches, empty and managed
  payloads, repeated arm-local reuse, negative indices, and a loop. Prove the
  ordinary selected retain and guard/role reset remain while the Object loan
  disappears only on the certified path. Cover a clear list guard taking the
  old path and a branch entry or intervening hook refusing certification.
- Guest tests that save the selected payload, then mutate or grow the source
  list, reuse its slot with a different variant, rebind the source, call a
  mutator, or retain an independent snapshot. Include heap and caller-arena
  storage, nested inline records and duplicate child pointers. The arm must
  observe the original selected snapshot throughout.
- Unique/finalized/opaque/live-view/boxed payloads, borrowed contract switches,
  narrowing aliases, unsupported source representations, callback index
  expressions and effectful gaps must retain ordinary lowering. Index
  callbacks may finish before the checked read; the first implementation can
  conservatively refuse their scoped receivers.
- Bounds and step traps at the read/switch boundary; selected-retain count or
  workspace refusal after an acquired prefix; old initialized arm cleanup;
  callback-bearing old-payload refusal; pool replacement and large backing growth
  from a later arm callback; and nested guest entry under an already active drain. Preserve balanced
  counted cleanup in both actual backends. A C helper probe may separately
  inspect the atomic retain boundary; it must be labeled an internal probe.
  A forged finalized payload is outside admission, never an admitted positive.
- Matched reduced Lox controls first, then unchanged full N10 median-three
  instructions and RSS, actual QBE and LLVM O3/full-LTO, exact output, no lost
  accounting and balanced ownership counters. O traffic, allocation and clone
  counts should remain unchanged for this narrowly physical removal; H traffic
  should decrease. Investigate any other change before attribution. Include
  snapshot, variant, arena and callback suites before the root's combined gate.

## Larger follow-up, deliberately separate

After measuring this slice, extending the every-return borrowed certificate
with correct variant CFG successors could remove whole read-only accessor
activations' temporary ownership, including `string_obj` and parts of
`load_frame`. That requires a new fixed-point arm-payload anchor model, every
return/abort proof, immutable-literal admission and proof that fallback
constructors introduce no hidden owner. Existing v6 refuses `switch_variant`,
and whole-body readonly lowering requires a plain return. Neither refusal may
be bypassed based on source appearance alone. The adjacent-switch slice is the
largest currently bounded compiler target supported by the dynamic evidence;
it does not borrow payloads across a pool mutation or change canonical return
ownership.
