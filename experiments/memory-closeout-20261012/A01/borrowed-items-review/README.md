# Borrowed dictionary item iteration review

Read-only production review requested by the coordinator. No production file was
changed, and the patch is a proposal, not a tested implementation.

`dictionary_views.at(.items)` builds a typed `.record` from `.key_at` and
`.value_at` of one mapping and index. `Checker.origin` does not recognize that
record. Initialization therefore requests a move; `recordFields` tries to move
the managed key/value even though each projection borrows the dictionary.

Named loop fields already carry `.iteration` origin. Existing iteration guards
establish a loan on the dictionary. The proposed direct two-name projection
preserves both contracts without constructing an owning intermediate record.
It addresses `for key, value in mapping.items()` and dict comprehensions that
lower through that statement path. It does not resolve single-item iteration,
enumeration of items, or single-item comprehensions. Those need a narrow borrowed
synthetic record contract, including backend ownership, not a blanket relaxation
of ordinary record constructors.

A03's materialized `entries = list(mapping.items())` two-name loop is already
admitted: its actual Support5 diagnostic is the following single-item loop at
line 59, not the preceding destructuring loop.

## Required qualification

Positive controls: string keys and managed list values; reads through two-name
bindings; explicit key/value copies retained after mapping replacement; discarded
key or value; empty mapping; early return; comprehension with copied output keys;
materialized DictItem list destructuring as the unchanged control.

Negative controls: return a key or managed value directly from the loop; append
one directly into an owning output list; mutate/rebind/clear the dictionary while
its iteration loan is live; mutate the borrowed list-valued field. These remain
borrow/overlap errors. Copying the chosen field is the positive owning counterpart.

For the single-item path, a correct follow-up must additionally classify the
backend synthetic record as borrowed from the common dictionary owner and avoid
consuming its borrowed fields. `own.classify` currently defaults `record_make`
to owned, and `consuming(record_make)` consumes all child operands. Merely relaxing
the source checker would leave that ownership mismatch unresolved. Ordinary source
record construction must retain its existing move contract.
