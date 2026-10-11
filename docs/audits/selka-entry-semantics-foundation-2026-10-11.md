# Selka entry semantics implementation foundation

The new Selka modules port the native entry signature rules and typed entry
adapter. This is an implementation foundation, not a claim of selected semantic
ownership. The installed schema-11 body route and native entry coordinator are
unchanged. Source checks pass; execution and native parity are still pending.

`entry_types` recognizes argv by managed list/string shape, accepts the native
capability kinds, separates out/err Streams, and preserves duplicate/name/type
messages. `entry_signature` selects a free main in the entry module, rejects
generic or nonguest entries, resolves parameters in source order and checks the
return contract. Missing-main remains a separate decision so the coordinator can
preserve prior generic-contract failure ordering. Its current type resolver is
the body checker; broader type coverage remains separately accountable.

`entry_adapter` leaves int entries untouched and appends the native Unit or
checked-result wrapper. It forwards parameters once, preserves their ownership
and origin metadata while resetting usage, retains the original callable
signature, and appends exact call/constant/match/return rows. Result tags come
from the supplied catalog. Int errors become exit statuses; other errors exit
one, and error output uses the error_report sink. Unit success exits zero. The
synthetic function has no source-body range, matching native cache ownership.

Thirteen pure controls cover those rules. A separate development probe and
native oracle require thirty complete typed-program comparisons per guest mode,
including zero/one/three parameters, nonzero entry IDs, unchanged helper bodies
and aliases, both result success types, int/bool error payloads and reversed
result tags. The native oracle canonicalizes the candidate and compares every
field, including local usage/ownership and signature defaults. A changed wrapper
name must fail in each mode. This harness does not register another production
component or change the existing wire schema.

The qualified c4f1ea0b seed accepts both test roots, the signature implementation
and the probe; formatting, whitespace checks and 88 Guardian checks also pass.
The earlier default-field, fallible assignment and local-shadowing source errors
are retained with their corrected preflight. Existing imported body modules
still emit their previously recorded unused-binding warnings.

Required next work is to run the thirteen pure tests and thirty native adapter
comparisons in both guest modes, add source-level signature/diagnostic parity,
then design and validate selected semantic publication with exact failure order.
Only after that can the native entry coordinator/adaptation be replaced on the
selected path. Other semantic passes, Core/LLVM/driver ownership, full bootstrap
and 1.5-times performance acceptance remain open.

[Source checks and identities](evidence/selka-entry-semantics-foundation-20261011/receipt.json)
retain successes and failures without treating source checking as execution proof.
