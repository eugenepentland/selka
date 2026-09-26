# D9 RC-v1 shared C interface — 2026-09-26

This is the executable serial interface foundation for WP-4 on `266d9d5a`,
following the accepted stage-3/default and WP-4pre prerequisites. It does not
activate RC, migrate collections, or claim WP-4 correctness/performance acceptance.
The default and legacy runtimes remain under the integration branch's selector.

`native_rc.h` freezes the 32-byte ordinary RC prefix, preserved 16-byte common
GC/arena/immortal prefix, independent ownership shapes, module/import/binding
registration, allocator hooks, separate owner/hold/pin semantics, and iterative
release/drain interfaces. `myl_native_heap.rc` is appended, preserving generated
root/inline-window/arena-window offsets. Because `MylQbeContext` embeds the heap,
its subsequent fields move eight bytes: externally linked C artifacts require
a new native ABI identity as well as the explicit runtime/ownership contract.

The implemented foundation includes checked and budget-charged atomic metadata
registration, dynamically copied ownership shapes, reserved descriptor frames,
owner and nonsharing hold counts, nested individual pins, direct-edge walking,
intrusive DYING queues, allocation/retire hooks, explicit value drop and proven
nonoverlapping relocation. `myl_rc_descriptor_register` accepts a temporary
binding structure with a stable native type identity and registered shape;
`myl_rc_shape_import` retains no source-address identity. Static module identities
remain immutable and valid through teardown. Pointer-free subtrees are reduced
to NONE shapes. The common native GC descriptor layout is unchanged.

Registration uses fallible temporary workspace, validates native extents, and
computes maximum inline depth without recursion. Managed pointers are terminal
edges. Metadata and replacement frames commit only after every reservation
succeeds. Existing values remain releasable after refusal. Runtime collection
adapters enumerate logical edges while their header is alive; raw backing cannot
borrow dictionary-embedded descriptors. No release walk allocates or invokes
callbacks. Explicit unique finalizers run at idle descriptor depth before final
retirement; reentrant releases enqueue and the outer drain owns progress.

The same header declares the later semantic copy/take/replace/uniqueness,
receiver scope and arena escape interfaces. Their implementation belongs to the
next coordinated changes. Copy and semantic take must both preserve pins;
relocation requires a separate proof. A uniqueness slot contains one managed
payload pointer; a borrowed edit returns either borrowed reuse or one detached
owned token, and failure leaves the zero-initialized edit empty. A scope restores
all pin states before releasing any hold. Unique resource cleanup remains a
separate obligation: ordinary sharing must not duplicate a resource close, and
an RC finalizer is used only when the unique cleanup path explicitly delegates
that obligation exactly once.

Validation completed for this foundation:

- Nine C contract scenarios pass with ASan and UBSan, including exact prefix
  offsets/alignment, 16-byte-only literal and arena guards, count-limit rollback,
  O=0/H>0 receiver lifetime, nested pins, repeated reservation refusals, temporary
  metadata lifetime, 32,768 nested inline records, checked array overflow, nested
  inactive variants, 100,000 shared array edges, one million heap nodes, and a
  finalizer that grows metadata and releases another allocation reentrantly.
- The million-node destruction and deep-inline walk run at their exact managed
  byte ceiling under a 256 KiB native stack limit; final object accounting is zero.
- One real Zig test invokes the nine C scenarios and asserts the returned count.
  This provides Guardian spec evidence because the spec check does not discover
  C `// spec:` comments.
- Guardian whole-tree `all --full` passes all 88 checks, without a ratchet update.
  The first run identified only the four new C-only spec tags; the executable
  Zig wrapper resolved that mismatch.

The root integration owner supplies the build wiring and runs the joined full
four-command gate. No full-gate result or guest RC coverage is claimed here.

## Scope, trap and arena runtime follow-up

The shared runtime now implements pin-aware copy/take/replace, iterative staged
cloning, multi-slot construction rollback, borrowed edit tokens, and receiver
scope journals. Guarded compiler frame journals reserve storage in the frame,
clear initialized bits before callbacks, and clean owners before `longjmp` can
invalidate their storage. A prefix unwind preserves a suspended outer frame.

Arena close detaches the closing chunk lists before callbacks, restores receiver
scopes, visits each allocation's logical ownership descriptor while all detached
chunks remain live, then releases the chunks. Raw collection backing is never
interpreted as a second owner. Aborted arena allocations carry the DYING bit so
their unique hook cannot run again at region close. RC retained chunks and the
depth table remain charged, with reuse allowed at the exact budget ceiling.
Runtime teardown closes logical arena ownership and ASCII cache owners before
the optional counting report, including the executable exit-without-sweep path.

Focused validation is now 16 core contract scenarios, eight startup/frame
scenarios, 20 production collection scenarios, and four arena scenarios. Core,
collection and arena suites pass ASan/UBSan; the startup/frame fixture exercises
the real runtime longjmp through its Debug Zig wrapper. The arena tests include
cross-chunk list/dictionary ownership, tombstones, nested regions, exact-budget
cache reuse, reservation refusal, and a finalizer that opens another arena.
Escape graph copying and complete compiler ownership lowering remain separate
work; this runtime evidence does not claim WP-4 guest or performance acceptance.
