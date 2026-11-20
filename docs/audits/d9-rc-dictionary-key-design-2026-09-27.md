# Anchored immutable dictionary keys: proposed certificate

Design only; no production implementation or new timing. Source now real-merges
`3c4251e8` and accepted correctness checkpoint `869538de` at `aa452a04`.
The immutable `3c4251e8` compiler remains
`.tmp-rc/install-dict-tail-final/bin/mylang`, SHA-256
`e88d13f4d873a19b05c672c01c22219eb0bd2a730f149e4e370062b3dd682ee4`.
The existing tail's performance/evidence archive remains unchanged. Before any
new comparison, check whether the joined correctness/runtime changes affect the
benchmark; isolate their effect instead of attributing it to this certificate.

## Exact source flow and cost ceiling

Unchanged `dict_count` has the following bytecode, confirmed with that compiler:

```
5       canonical named keys list (local 2); setup appends end at 27
38..39  LOAD keys; STORE compiler read receiver 8
40..55  scalar index arithmetic and forward negative-index normalization
56      list READ receiver 8 -> builtin immutable str
57      STORE named key 10 (currently canonical O publication)
58..63  key load, counts.get(key, 0), scalar addition, completed RHS local 12
64..68  existing certified dictionary tail: first unique(counts), write
74      loop backedge to 34; key has no other use/writer
77..    separate actual iteration of keys; its H protocol must remain
```

Current full two-million-update totals are O acquisitions 2,002,001, H pairs
4,002,001, uniqueness 2,001,000, heap allocations/retirements 2,029, clones zero.
The maximum targeted traffic is two million named-key O pairs and four million
H pairs: six million internal token pairs, or twelve million acquire/release
actions. A fully admitted implementation should leave approximately O 2,001 and
H 2,001 while preserving setup/final iteration, first uniqueness and dictionary
insertion's real key ownership. These are falsifiable counter targets, not a
predicted speedup; allocation and other counters must be measured independently.

The row still costs 4,347,539,492 QBE / 3,254,453,343 LLVM instructions, or
6.5742 / 7.3791 times GC. To meet 1.3 by this slice alone would require saving
3,487,842,961 / 2,681,108,333 instructions: about 1,744 / 1,341 per update, or
581 / 447 per targeted token pair. Counters alone cannot establish that cost.
The two million first-uniqueness checks, hashes/lookups, writes and scalar loop
remain. This ceiling makes the transfer work material, but does not justify a
claim that key borrowing alone will reach acceptance.

## Reuse and one new composition boundary

- Reuse the canonical named-source writer/ref/pattern/redefinition proof from
  `qbe_rc_nonheld_capture`. Extract its role-only part as needed; keep its current
  scalar-list admission at the existing caller. A `list[str]` anchor needs an
  independently validated ordinary O home, not a widened default assumption.
- Reuse `qbe_rc_read_loans`' scalar interval and normalized-index grammar, physical
  storage identity, raw borrowed store and managed-result suppression mechanics.
  Its current child rule intentionally requires compiler temporaries and its
  interval rejects dictionary operations. Do not loosen those rules globally.
- Compose with an already accepted `rc_dictionary_tail.Certificate`, rather
  than discovering a second arbitrary write pattern. Require the same key,
  dictionary root, receiver and terminal write PCs.
- Reuse actual `qbe_rc_edges.releasesAt`, COW sites/captures, field-transfer and
  plain-record-write plans to veto implicit cleanup/publication. Semantic
  liveness and a local's spelling do not establish physical lifetime.

Proposed emission certificate records list storage, capture store, projection,
key storage/store, complete use interval and the existing tail identity. Its
anchor is explicit `rc_model.Anchor.storage` authority backed by the retained
named list owner. It is a zero-token raw borrow, not runtime LOAN16 or H8.

Finalize after ordinary physical planning/COW veto. First discover the ordinary
tail under its existing key-O requirement, then prove the complete composition
and atomically annotate that tail with borrowed-key authority. A failed proof
keeps all current lowering. Initial implementation can retain the conservative
RC plan's journal entries, guards and frame linkage, recording the extra anchor
in the emission certificate; it must not silently rewrite entry roles while
leaving stale edge/cleanup plans. No journal compaction is proposed. If using
`Binding.anchor` instead, rebuild the complete plan before emission and rerun
all final eligibility checks; partial post-plan mutation is not acceptable.

## Physical admission and lifetime

Only builtin unboxed `list[str]` and builtin immutable `str`; no bytearray,
custom key/domain/record, H-view, recursive box or unique contents. The anchor
is a nonparameter, nonreference, independent named canonical O home, defined
once before the interval and never moved, rebound or pattern-written on any
path that reaches it. No mutation/escape of the list or its aliases can occur
inside the closed interval. A preexisting snapshot is allowed only if the
ordinary owner and stable contents are independently proved; exclusivity is
not necessary for a read.

The closed interval is initially capped at 256 bytecodes, with forward branches
only inside it (the existing negative-index normalization). Scan every CFG edge:
external entries into its interior and internal backedges refuse. An enclosing
loop can reenter only through capture. The complete function remains capped at
4096 instructions. The capture and key each have one static definition.
Inventory every explicit
and implicit writer: ordinary/move/ref/drop/pattern, iteration capture,
receiver/place/box, clone installation, inlining origin, field transfer and
plain-record interception. Refuse uncertain or caller storage and alternate
borrowed/readonly entry contexts. Every key use belongs to the proved interval;
no return, aggregate store, alias publication, callback argument, later read or
escaping borrowed key is admitted.

The capture input is an ordinary raw load; the read consumes only a plain index;
the key store consumes only that raw projected string. Both local guards and
the relevant operand guards therefore start and remain empty. All reachable
backedges either reenter before capture or stay outside the interval; no entry
may bypass a required producer or key store. Repeated stores never retire an
old key token because the whole-local proof establishes that none existed.
Reject any separate writer that could install one, including a prior iteration.

The named list O guard remains real and live until after every key use. Its
logical elements own the selected string. Named owner cleanup, planned releases
and alias writes cannot invalidate either object. The projected pointer is a
copied pointer value in private storage, never an address into reallocatable
backing. Dictionary growth only affects a distinct dictionary and keeps the
original write's key acquisition/staging. Do not infer disjointness from two
different local names; enforce the distinct builtin storage/type relationship.

Function-wide `mayHold(list[str])` is true in the benchmark because of the later
real iteration. Thus capture lowering needs the exact ordinary-input proof at
PC38, rather than suppressing all H handling of that type. Actual iterator
capture PC78 and all other H traffic remain. Key `str` held-role uncertainty
refuses initially. Keep all private storage and guard initialization; only
proved publishers become raw stores/reads. Unexpected publication must refuse
the certificate, not be silently discarded.

## Operations, callbacks, history and traps

Permit scalar index/normalization work, the exact list length/read, private
plain scalar stores, the existing builtin dictionary `get` with plain result,
and the already certified final write. The dictionary/key/value restrictions
match the existing tail. Unknown calls, further managed producers, mutation
of the list/aliases, scope transitions, semantic SHARE/read-capture events,
external middle entries and arena entry/exit refuse. First dictionary
uniqueness and original dictionary write stay in place with their failures.

Existing step, bounds, overflow and frame/physical-floor checks remain at the
same source operations. A trap between projection and store, or between store
and write, cleans the real list/dictionary owners; raw key/capture slots own
nothing. Inherited arenas are permitted only with no transition in the interval
and a demonstrably surviving anchor. Dictionary region checks remain unchanged.
Eliminated private count failures follow the existing read-borrow elision
contract; actual insertion/uniqueness/count/region refusals stay.

Immutable string transfer does not publish mutable semantic SHARE history.
Still veto every planned history event rather than guessing from type alone.
Removing the old capture/key cleanup cannot retire its payload while the list
owner survives. Builtin string/plain dictionary children have no guest
finalizers. Audit the unchanged get/first-unique/write drain boundaries, including
guest reentry under an active finalizer drain. Arbitrary C entry with manually
queued work is not silently treated as an ordinary guest boundary. Reuse the
embedding finalizer control and add a borrowed-key-specific assertion.

## First controls and hooks for review

Positive: actual benchmark grammar, negative index, duplicate string elements,
preexisting dictionary/list snapshots, repeated backedge, empty loop, borrowed
key whose dictionary insertion grows, heap and inherited arena. Negatives:
index/RHS callback mutating or replacing the list, root/key parameter/pattern/H
storage, alternate entries, extra key definition/use, managed/custom keys,
alias mutation, branch into projection/store/tail and arena transition. Preserve
exact iteration H counts, malformed/low-budget growth failures and step traps
at both projection→store and store→write boundaries.

Likely narrow hooks: cached emission certificate; `read_loans.borrowedResult`
and `store` consume explicit authority; views' immediate capture input bypass
uses the exact source-role proof; the existing dictionary tail gains a tagged
key authority. Keep canonical local/store paths as complete fallback. Coordinate
read-loan and edges hooks with the adjacent-variant worker before editing.
No runtime, ABI/cache/default or ownership-frame change is proposed. Code limit
4096 and an explicit bounded interval/scan allowance remain conservative; report
candidate accounting separately from total primitive analysis work.

Independent compiler peer review found no blocker in this boundary. It agreed
that the whole-local zero-token induction and stable named-list authority are
necessary beyond the existing terminal-read rule, and that retaining journals
while atomically annotating an admitted tail avoids stale cleanup-plan changes.
Runtime review also found no blocker: the surviving list O edge owns both the
immutable string/view header and canonical backing. Ordinary guest entry has no
pending deaths; nested finalizer entry inherits an active drain. The original
first uniqueness and dictionary write preserve actual insertion, region, count
and growth failures. Keep view-backed strings, inherited arenas, trap gaps and
uncertain named-home release refusals as explicit controls.

Final tail authority is tagged as canonical or anchored. Discovery under the
old canonical-key requirement only identifies a candidate; the anchored tag
requires the complete certificate. The source canonical STORE must dominate
every admitted capture, and all source/drop/ref/pattern and hidden publishers
are checked. Entry-start ownership alone is never proof of an O token.
