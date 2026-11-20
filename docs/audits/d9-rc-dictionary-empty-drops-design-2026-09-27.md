# Dictionary zero-token cleanup proposal

Design originally reviewed from `0efd82ad683f23d175288f19316a5420b7960cf5`.
The prototype uses the explicit two-parent merge `0f5e4d0f` of that source and
joined `c07016f3`; its matched control is the immutable c070 compiler.
The [ordinary-find result](d9-rc-dictionary-plain-overwrite-2026-09-27.md),
its immutable compiler and all receipts remain unchanged. No new descriptor
cache, runtime layout, native helper or loop-version admission is proposed.

## Exact remaining cost

The full, unchanged two-million-update workload currently measures median-three
913,572,796 QBE and 612,383,229 LLVM O3/full-LTO instructions. Accepted GC
denominators are 661,305,029 and 441,034,616. The ratios are 1.381469603 and
1.388515111. Reaching 1.3 requires another 53,876,258 / 39,038,228 instructions,
or 5.8973% / 6.3748% of current RC work. This is one program, not corpus or RSS
acceptance.

Inspection of the exact ordinary-find native binaries and unchanged emitted
guest body finds five hot cleanup checks whose successful dictionary proofs
already imply empty tokens:

| Bytecode boundary | Logical journal | QBE first instruction | LLVM first instruction |
| --- | --- | --- | --- |
| key STORE at PC57, edge after it | captured list local8 | `0x101027d` | `0x10194ba` |
| dictionary GET at PC60 | operand0 | `0x10102f8` | `0x101950d` |
| receiver STORE at PC65, input cleanup | operand0 | `0x1010356` | `0x101954c` |
| receiver STORE at PC65, prior local cleanup | receiver local11 | `0x1010377` | `0x1019564` |
| dictionary WRITE at PC68 | operand0 | `0x10103e9` | `0x1019e02` |

The source debug locations printed beside calls are one-based and therefore
show 58, 61, 66 and 69. These addresses identify the fixed measured binaries;
they are not compiler admission inputs.

Each false QBE branch executes a load, comparison and conditional jump. LLVM
uses a memory comparison and conditional jump. Five checks over two million
iterations therefore account for a source-conditioned 30M QBE / 20M LLVM
instructions. This is a static successful-path count, not a new measurement or
a dynamic trace. Two local checks alone account for 12M / 8M. Removing all five
without any other code-generation change would predict ratios 1.336104758 and
1.343167197, still requiring 2.70% / 3.21% more reduction for the row cap.

There may be secondary register/allocation improvements after unreachable
cleanup calls disappear, but no saving beyond those instructions is claimed.
The QBE loop also retains a wide checked-multiply sequence; LLVM already
reduces that expression to one multiply. Expanding loop versioning is a
separate proof and is explicitly excluded here.

The private native word path still performs necessary ordinary descriptor,
queue and actual-region validation. The rejected shared-repeat variant's
mixed-client regression remains a negative result. This proposal removes no
such native checks and introduces no replacement cache.

## Admission reuses completed physical proofs

Use only an already accepted anchored key certificate together with the
successful late fresh-dictionary loop certificate. Do not rediscover the tail
with another pattern matcher or infer emptiness from a type, local name,
semantic borrow, zero measured counters or presence of a loop-entry check.

The late loop pass currently discards its proved constructor definition,
header and backedge after appending the uniqueness entry. Retain that accepted
range as a small optional annotation on the existing dictionary certificate.
Install it only after the existing bounded lifetime, CFG-entry, every-planned-
release, implicit publisher and metadata checks succeed. Keep all original
site metadata and the late ordering after loop-version veto. An annotation
must neither imply `permitsVersion` nor create a fast loop.

For this first slice require a direct empty dictionary MAKE_RECORD followed by
the ordinary canonical named STORE_LOCAL that the loop proof already admits.
Explicitly validate its input stack is exactly one dictionary at operand0 and
its successor stack is empty. The store may not be a view/iterator, receiver,
plain-record write, field-transfer, by-reference/caller-storage, alternate
borrowed-entry or other intercepted publication. The dictionary type must
retain the existing no-mayHold, counted/nonunique and private ordinary-home
requirements. A stored operand in position other than zero is refused.

This reset point is essential: on normal return from that ordinary store,
`prepareOperand` has transferred or retained the input and disarmed/dropped its
operand journal. The direct owned-constructor arm runs `prepareOwned`, which
clears the source guard only after successful transfer. The guarded fallback
also clears the input through TAKE or `frame.drop` before commit. A failed
transfer traps before reaching the loop and keeps the current journal protocol.
The constructor is not assumed allocation-free, and its live guard remains.

Additional proof is limited to this physical reset and the exact operand-zero
instruction effects described below. Reuse the original key/loop branch
traversal and whole-local writer proofs. Charge the added stack/effect scans
against the existing bounded candidate allowance; refuse partial admission on
exhaustion. The existing code<=4096 and loop<=1024 bounds remain.

The implementation shares the late-loop `Budget`: it charges one unit before
visiting each corridor PC and each actual stack element, plus the canonical
borrowed-store metadata rows. It reuses the finalized tail's no-mayHold root
fact and the completed late-loop reset-inclusive interceptor scan instead of
repeating those potentially larger scans. Shape lookup preserves OutOfMemory;
other unavailable shape information conservatively declines this annotation.
The allowance measures explicitly charged candidate/metadata/stack rows, not
every primitive operation inside shape resolution or inherited proofs.

## Empty-token induction and access inventory

Start immediately after the successful ordinary constructor store, not merely
at a semantically empty operand stack. The accepted loop proof prevents an
external entry skipping that store, an internal entry skipping its header,
or an enclosing backedge reusing a formerly published dictionary. Outside the
closed key interval only scalar operations and scalar stacks are admitted.

Inside the interval the only managed values at operand0 are:

1. The exact list anchor LOAD_LOCAL followed by its raw receiver store. The
   existing `rawCapture` interception precedes function-wide H handling and
   explicitly proves this named list's ordinary authority.
2. The list READ's immutable string result and adjacent raw named-key store.
   The already accepted key certificate suppresses its LOAN publication and
   proves all key/capture definitions, uses and implicit writers over the
   entire function, including later loop iterations.
3. Raw key LOAD_LOCAL before dictionary GET/WRITE, and raw dictionary root
   LOAD_LOCAL before the tail receiver STORE. Existing type-wide mayHold and
   writer refusals remain mandatory for these loads. The exact receiver store
   remains raw under the existing tail certificate.

Every other operand in the interval must be an edge-free, nonunique scalar.
GET produces the existing plain value and WRITE produces unit; neither
publishes an operand owner. The index is captured before its read and the
dictionary scalar result before any cleanup. The original native GET and
WRITE calls, arguments, status handling and scratch result storage remain.

The first loop-entry uniqueness operation uses the dictionary local's guard
and can only publish that local. It cannot address operand0. Existing proof
already excludes another uniqueness/pin, COW/read capture, semantic SHARE,
field transfer, record-write interception, arena transition, callback or
managed producer in the body. Direct runtime guard writers in admitted
lowerers must be reviewed explicitly; a bytecode-only writer inventory is
insufficient.

Thus operand0 stays empty from the constructor-store commit through every
loop path/backedge. On the actual body the relevant consumers are GET at PC60,
receiver STORE at PC65, and WRITE at PC68. A query may suppress only these exact
recorded `(PC, operand0)` drops. It must not suppress setup constructors, a
later iterator/read result, another tail or an arbitrary drop inside the range.

The captured list local and dictionary receiver local have the stronger
whole-local empty-token proofs already established by key/tail admission.
Their relevant hot consumers are an existing early-release edge at PC57 and
receiver cleanup at PC65. The named key local is also empty, but its frame entry
and cold cleanup need not be changed to obtain this hot-path saving.

## Initial emission keeps all storage and trap protocol

Keep every journal entry, guard word, receiver scratch allocation, role field,
entry initialization, root/key owner, linked ownership frame, native/logical
frame admission, watermark and normal/trap frame cleanup. The globally shared
operand0 journal remains real because setup and later code do own values there.
This isolates false-branch removal from further frame compaction.

Add an emission-independent exact-drop query to the existing dictionary
certificate model and a narrow early return in `frame.drop`. The query receives
the actual PC and logical journal index; it must match one of the saved local
or operand consumers and the completed annotation. `values.drop` continues to
perform its ordinary physical input-type checks. No raw offset arithmetic is
added. Every unmatched drop uses the original path.

Also add a strict publication refusal for the certified operand-zero interval
and certified raw local writers. `initialized(true)` and an attempted direct
operand guard address for a helper which could install a token must fail
compilation inside that interval. Initial frame metadata setup and the reset
constructor store remain outside it. Review raw runtime guard-address users,
not only calls to `initialized`. If the current API cannot distinguish a
legitimate metadata setup from a possible guard publisher, keep the optimization
refused rather than silently deleting a newly live drop.

The existing empty-local layout mechanism could later consume the same
whole-local authority to remove slots, but this initial slice deliberately
does not change layout or synthesize roles. The separate byte-loop proposal
uses a runtime zero guard and active-fast-copy context; this proposal has an
explicit canonical-store base case and ordinary-loop induction. They share
the requirement to identify exact physical consumers, not a general rule that
all managed reads are borrowed. No new branch analysis is copied from it.

## Failure, callback and finalizer boundaries

Bounds, arithmetic, finite-step and physical/logical frame failures stay at
their original points. On a trap, the retained frame scans actual guard words;
the dictionary/list roots and any enclosing caller scopes remain owned. Native
WRITE still handles growth, region/count refusal, pending-death drain and staged
publication. No success or error is synthesized by this compiler proof.

A finalizer may call a guest using another frame. It cannot address these
private operand/local guards. The native dictionary write receives pointers
to the ordinary source words, not their separate RC journal/guard storage.
Plain values and immutable string keys introduce no guest finalizer in this
interval. Even under a real pending-death fallback, the suppressed drop was
already a false guard and performed no drain, so removal does not move a
finalizer boundary. Inherited arenas are allowed as before; crossing an arena
boundary inside the interval remains refused.

## Focused verification and ownership

Proposed production scope: dictionary certificate model/late pass, small
frame drop/publication guards, and focused tests. No native runtime, descriptor
cache, qbe_loop_version, common branch traversal or plain-record/field-read
certificate edits. Coordinate the frame/value guard API with the byte-loop
worker before implementation.

Required structural controls include the exact unchanged benchmark with five
fewer drop branches; retained real setup/later operand publications and linked
frame; nonzero stack reset, noncanonical/intercepted store, middle entry,
preexisting snapshot, enclosing publication/reentry, callback, new managed
producer, direct runtime guard writer, pattern/ref/iterator and H-capable
dictionary/key refusals. A real later list[str] iterator must keep its H guard
and cleanup while the certified earlier raw capture stays empty. Test strict
unexpected publication refusal directly.

Actual backend controls reuse the focused dictionary key/loop positives and
their bounds/overflow, inherited-arena, growth/refusal, step and finalizer-entry
cases. Check exact outputs/status/trace points and unchanged complete counters,
not only balanced totals. Do not repeat the known unrelated GC stress timeout
or a broad trap sweep. If a branch cannot be proved empty, original emission
is the fallback; no speculative runtime mutation is allowed.

After concrete review and source freeze, inspect both native binaries and run
the unchanged full2M workload on CPU11, interleaved median-three against the
immutable ordinary-find compiler. Require 100% instruction event running;
counted builds remain separate. Preserve all existing receipts and report the
new distance from the 1.3 cap even if secondary savings are absent.
