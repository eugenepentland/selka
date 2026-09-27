# Proposed evaluated dictionary-write tail

This is a read-only proposal after `aca67a7a`; no production change is made.
It is a separate physical lifetime certificate, not a widening of the nonheld
plain-list role proof.

## Evidence and exact boundary

The unchanged `dict_count` workload performs two million updates. Root's exact
joined `d1d8b3c4` measurements are QBE 7841566609 / 661306134 = 11.8577 times
accepted GC and LLVM 5774369900 / 441035727 = 13.0927 times GC. Counted builds
agree across backends: 2002001 O acquisitions, 12001999 H acquisitions,
4001000 uniqueness checks, 2030 heap allocations/retirements and zero clones.
The 249-sample QBE profile is heavily throttled qualitative attribution, not an
instruction estimate. Root preserves the exact production artifacts at
`.tmp-rc/dict-audit/` and in diagnostic commit `9d9be19b`.

The lowered hot path is:

```
38..56  capture keys list, normalize index, read existing str
57      publish key into ordinary named local 10
58..63  counts.get(key, 0) + 1; store completed scalar RHS in local 12
64      LOAD_LOCAL counts(5)        # first unique_local(5)
65      STORE_LOCAL receiver(11)    # second unique_local(5), begin/pin scope
66      LOAD_LOCAL key(10)
67      LOAD_LOCAL value(12)
68      BUFFER_write receiver(11)  # original native_dictionary_write, scope end
```

The existing scopes protect a dictionary header plus its entries header,
entry backing and index backing. They allocate/free scope metadata for each
non-null captured allocation. Two other steady hot H obligations are distinct:
the keys-list capture at39 and the projected string loan at56, followed by
ordinary O publication at57. Those key/read obligations stay untouched in the
first proposed slice. No output/counter inference treats all H traffic as scope
traffic; the new slice must measure the actual delta separately.

The displayed default `emit-qbe` receipt contains step guards. PCs and ownership
order above come from lowered bytecode plus that receipt; final validation must
also inspect the ReleaseFast fragment actually selected by the native manifest.

## First admission

Initially accept only the exact five-instruction tail shown above, in canonical
active RC emission. No alternate borrowed/readonly entry. Require:

- Root is an initialized, independent, nonparameter named dictionary local with
  no caller storage, reference, alias, projected place or pattern binding. Its
  definition must be an audited canonical named publication. Keep its real O
  journal and the first runtime uniqueness call, including snapshots/clones and
  cold refusal. Do not infer uniqueness from type, SHARE history or local name.
- Dictionary value is an ordinary nonzero plain scalar without counted or unique
  edges. Key is initially a builtin plain scalar or immutable builtin `str`.
  Refuse boxes, live views, domains/records with custom behavior and arbitrary
  managed keys or values. Do not equate all byte-storage collection kinds with
  immutable text.
- Key and value have already been evaluated before the tail. The key's physical
  lifetime is anchored through the terminal runtime write by its unchanged
  ordinary named-local journal. For a string key, certify its canonical store
  and all writers; pattern/ref/caller/temporary borrowed roles refuse initially.
  A source-level key callback can occur earlier, but no callback or managed
  publication is allowed after capture and before the write.
- Target is exactly the compiler mutation receiver alias of that root, with one
  static store and one terminal write use. It is never a named binding, actual
  iterator source, H view receiver, parameter or writable reference. Scan every
  writer, including pattern dispatch, implicit COW aliases, unique clone targets,
  projected/boxed places and field-transfer publications.
- Capture starts empty on entry. Its only definition stores raw bits from the
  prepared root. Its only operation mutates via the retained root; it never
  acquires O/H/LOAN in its local journal. Every normal path to a loop backedge has
  passed the terminal write. Failed writes unwind the function instead of
  reentering the tail. Thus a repeated static capture also begins empty. Refuse
  external entries into the tail, jumps/branches within it and reused definitions.
- The LOAD result's operand guard is independently empty: exact ordinary root
  load, no read capture, SHARE, value-copy or alternate publication. There are no
  planned physical edge releases, alias writes or scope transitions within the
  five instructions. Root/key/value and operand addresses remain distinct from
  dictionary backing that can relocate during growth.
- The original COW site at the first LOAD must call uniqueness for precisely this
  root, without alias publication. There is no intervening effect capable of
  changing its pointer, owners, semantic history or region. Only after proving
  this and both empty cleanup guards may the receiver STORE omit its duplicate
  uniqueness call. The first check stays at its original PC, including step/trap
  order; no preheader hoist is proposed.

The complete function is bounded at4096 instructions; candidates have a fixed
five-op shape and a conservative candidate-code scan allowance. Like the prior
slice, that allowance must not be described as every primitive analysis visit.
All uncertain inputs retain current lowering.

## Terminal runtime operation and callback obligation

Keep `myl_native_dictionary_write` unchanged. Existing lookup, overwrite,
insertion, generation/index growth, region validation, allocation/count refusal,
source staging and rollback remain. Key/value arguments are frame copies, not
addresses into dictionary backing. The root owner and key journal keep their
payloads alive; growth therefore may retire old backing without a temporary
receiver hold when no captured interior address exists.

The initial key/value restrictions eliminate unique finalizers from the terminal
write's own children. The source dictionary may be shared before the first
uniqueness call; that call still detaches normally and completes any required
cleanup before capture. Earlier callbacks and named snapshots stay observable.
No semantic SHARE event or actual owned publication is suppressed.

Dropping a scope is also a drain boundary. The existing generated-guest boundary
contract says runtime operations drain before returning; callbacks entered while
already draining remain under that drain, and edge visitors do not enter guests
mid-walk. This is the same bounded obligation used by the accepted plain-value
codegen path, not an assumption based only on element shape. Before implementation,
review the dictionary insertion/overwrite and first-uniqueness paths against that
contract, including callback reentrancy. If an admitted terminal path can leave a
new observable pending death, preserve an explicit drain boundary or refuse that
case. Do not weaken a general C runtime API or assume its queue is empty.

Independent runtime review completed before implementation. The overwrite path's
plain `retain_replace` arm requires an empty dead queue; otherwise its original
staging/drain path remains. Insertion retains staged inputs and retires old
storage through the original public operations before returning. An ordinary
guest boundary has no unrelated queued deaths, while a guest reentered from a
finalizer inherits an active outer drain, making the removed `scope_end` drain
inert until that outer drain resumes. Builtin immutable text/scalar keys and
plain values introduce no guest finalizer when backing or children retire.
This conclusion is limited to generated guest calls; arbitrary C calls with
manually queued work and custom callback-bearing keys remain outside admission.
No key/value address may refer to backing that insertion can relocate.

Removing these unused internal scope holds and the duplicate uniqueness query
can remove their private metadata/count-budget failures. Document this under the
existing inert-scope elision contract; preserve failures of the actual first
uniqueness, key publication and dictionary write. Do not claim all implementation
allocation failures must occur at the same byte count after redundant storage is
removed.

## Proposed hooks and first-stage limits

Use a new pure certificate module rather than broadening `list()` or `plain()` in
`qbe_rc_inert_receiver`. Reserve narrow hooks at receiver STORE's redundant
uniqueness and `qbe_cow.borrowReceiverImpl` / `finishReceiverImpl`. A cached plan
may be preferable to repeated scans; coordinate the plan-build hook with the
separate scalar-record tail work.

Initially retain all frame/private entries, guards and receiver scratch storage.
Only the proved duplicate check and begin/pin/end calls disappear. Root/key
journals, real caller scopes, ownership-frame linkage, physical/logical admission
and step checks remain. No runtime ABI, registry, allocator, GC lowering or
backend-specific instruction change is needed. A later empty-storage omission
requires its own strict writer proof and is outside this slice.

The earlier keys-list capture and projected-string loan need a separate proof.
A tempting direct read-to-named-store handoff would have to retain its containing
anchor across publication and the intermediate step trap, account for pin/history
ordering, and prove the destination's prior drop cannot invalidate the source.
It is not included here.

## Required controls and measurement

- Positive overwrite and insertion, empty/nonempty tables, growth, repeated loop
  tails, literal/plain/string keys and snapshots taken before mutation.
- Negatives for a callback after capture, middle entry, root/key rebinding or
  reference, actual live views/iteration, pattern/H/LOAN roots, unique children,
  projected/boxed dictionaries, managed values and hidden physical releases.
- Exact side-effect observation for key/RHS callbacks evaluated before capture;
  preserve the original GC/RC evaluation order. Keep actual callback-bearing
  pending receiver tests as negative controls.
- Heap and arena roots, an older heap root used under an inherited arena, normal
  exit plus arithmetic/bounds/step traps before publication, and low-budget
  insertion/growth failure with unchanged dictionary/source snapshot.
- A finalizer reentrancy/queued-death control substantiating the drain contract.
- Structural guards prove retained first uniqueness, suppressed second check and
  absent scope calls only in certified tails. Uncertain paths still have all
  original calls; target/operand no-token induction is independently asserted.
- Full unchanged2M dict_count, median3 retired instructions per backend against
  one immutable joined compiler, separate counted runs and exact outputs. Keep
  QBE ReleaseFast, actual LLVM O3/full-LTO, CPU reservation and manifest identities.

No implementation is authorized by this document alone; it is the requested
bounded proposal for parent review.

## Approved key-origin refinement after the first negative measurement

The first candidate left the exact benchmark unchanged. Its key local carries
semantic `collection_copy` provenance because it is initialized by `keys[index]`.
That hint does not select a different named-local RC publication. The approved
refinement admits only builtin immutable string keys with exactly one static
canonical named store immediately fed by list `BUFFER_read`. The existing read
produces a loan; ordinary named store acquires O and drops that loan before the
write tail starts. References, caller/pattern/iterator storage, branch entry into
the key store, non-list projections, repeated definitions and function-wide
`mayHold` still refuse. The dictionary root still requires ordinary `.local`
provenance. The unchanged full benchmark is now a structural regression fixture;
its marker and actual helper changes must be checked before a new measurement.
