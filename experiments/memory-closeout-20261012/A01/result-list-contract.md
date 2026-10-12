# Result lists: implementation contract

Private implementation qualification is recorded in `result-evidence-v3/`.
Integrated C1 qualification remains required; this document does not claim rollout.

A list may store a Result with ordinary scalar or managed payloads. Resource and
capability payloads remain excluded. Lists retain the independent storage and
scoped borrow rules used by other managed owners; no ABI or RC operation is added.

Storage eligibility and a pending Result obligation are separate properties.
Pending obligations propagate through list edges, ordinary records, arrays and
variants. Propagation walks a reverse dependency graph once per schema/edge; it
also terminates on recursive ordinary type graphs. Symbolic generic checking
never caches an incomplete active-cycle result; it recomputes those cycles within
the existing 100,000-work budget. Complete acyclic results remain cached. This
preserves bounded checking and may refuse sufficiently large cyclic generic
workloads at the existing limit. Existing restrictions on boxed
pending Results, dictionaries, sets and Cells remain explicit boundaries.

Moving, returning or passing the whole list transfers its obligation. Simply
leaving scope, overwriting the list or returning early with an available pending
list is rejected. `_ = results` explicitly acknowledges all remaining elements
and permits the existing direct cleanup to destroy their owned payloads.

A named owner's `len`, indexing and iteration borrow the list and preserve the
whole-list obligation. A loop binding that is a Result must still be matched,
propagated, transferred or explicitly discarded on every continuing iteration.
After inspecting a loop, write `_ = results` to acknowledge the aggregate. An early
break does not acknowledge the unvisited suffix. Named ownership keeps this rule
local; inspecting a fresh temporary pending list requires binding it first.

Appending a fresh Result transfers it into the list. `pop` transfers one Result
out and its existing handling rules apply. The list remains pending even when the
program knows it has become empty; no length-dependent proof is attempted.
`clear`, indexed replacement, slicing and other operations that would implicitly
drop or copy pending entries are rejected. An explicit list `.copy()` produces
independent storage and a second pending obligation.

`parallel.map` uses `T: storable, R: storable`, allowing callback results and inputs
to be Results. Its generic body handles every callback input and explicitly
acknowledges the input list after its scoped loop. A generic `storable` parameter
without a `copy` guarantee is conservatively treated as potentially pending;
`copy` continues to exclude Result obligations. Builtin Result payload parameters
do not require `copy`; storage eligibility follows their payloads recursively.
User-declared generic requirements retain their existing guarantees. This contract
does not add general
ownership inference or ownership/lifetime source annotations.

Required qualification includes managed results, nested ordinary payloads, empty
and uneven maps, worker counts 1/2/8, explicit copies, popped Results, borrowed
inspection, rejected early return/break/clear/overwrite and resource/capability
exclusion. The final compiler, native cleanup counters and ThreadSanitizer must
agree before this item is shipped.
