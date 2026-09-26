# WP-4 mutation through a held dictionary edge

An exposed `view.mapping` slot carries H, even though its expression type is a
dictionary pointer. Applying ordinary owned-slot uniqueness could release an O
that the slot never held. With an existing dictionary snapshot this aborted or
corrupted the original ownership. The compiler now has a distinct runtime bridge
for its tracked held-origin cursor; this commit supplies that bridge and the core
operation for the separate compiler lowering slice.

`myl_rc_unique_held` accepts an initialized HOLD_POINTER slot. A referent with at
most one ordinary owner is reused, including O=0/H=1. A shared referent is cloned
using the same staged pin-aware transaction as ordinary uniqueness. The fresh O
is converted to H before publication, then the old H and the fresh O are released.
Failure leaves the original held slot intact; unpublished arena clones immediately
drop their acquired heap-child edges. Arena bytes remain reserved until close.
Scope preparation dispatches held leaves through this operation before pinning.

`myl_qbe_rc_unique_held(ctx, type, address, container)` accepts the exposed native
dictionary POINTER type and preserves the physical H token. A real container
supplies its region; a local uses the current region. Its H metadata registration
is fallible before any ownership change. The compiler keeps the existing guard
and held-token flag through a successful replacement.

Twelve production hold scenarios pass ASan and UBSan, including the existing
100,000-edge bounded-stack teardown and new ownerless reuse, pinned shared-source
snapshot isolation, heap/arena child-count refusal, held scope preparation and
shared arena mutation. The startup/frame suite passes 18 C checks, including
registration refusal with unchanged H/O counts and ordinary held-guard cleanup
after detachment. Focused Debug wrappers and the joined actual guest mutation
probes are reported separately by the runtime and compiler owners.
