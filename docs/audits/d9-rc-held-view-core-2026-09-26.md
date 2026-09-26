# WP-4 live-view lifetime tokens

The live dictionary-view contract remains DICT-VIEWS-1: ordinary in-place
updates are visible through existing views, and rebinding the dictionary owner
does not retarget a view. A view therefore carries a nonsharing hold H rather
than an ordinary owner O. This slice supplies the runtime shape and frame-token
support; compiler construction/projection lowering is a separate joined slice.

Ownership metadata ABI 2 appends `MYL_RC_SHAPE_HOLD_POINTER` with value 5. Its
physical extent is one pointer, its descriptor depth is one, and its pointee is
not inline metadata. Registration reserves the same iterative walker capacity
as an owning edge. Copy acquires H without changing O, marking shared or copying
a pinned referent. Take transfers H without a count increment. Seed clears held
fields; drop releases H; region checks inspect held pointers. O=0,H>0 remains
live, and O=H=0 queues ordinary destruction. No release allocation is added.

Explicit escape copies a younger arena dictionary through the existing staged
clone memo, acquires H on the fresh shell, then releases its initial O. Repeated
held edges use the same copied shell. Same/older-region held edges retain live
identity. Later child refusal rolls back both the held shells and any acquired
logical child owners. Generic slot copy/take requires source and destination
token kinds to match; it does not implicitly convert O to H.

`MYL_QBE_RC_HOLD_POINTER=8` is an exclusive journal flag for a hidden borrowed
receiver whose lifetime token is H. The guarded slot holds exactly one pointer;
cleanup clears the guard and slot before releasing H. Stale module ABI 1 is
rejected by the execution registration bridge as R_INTERNAL before any module
metadata becomes visible. Counting schema remains version 1; the runtime policy
identity advances to rc-v2 / rc-v2-counting in the integration identity slice.

Validation completed on the edited runtime:

- Six production-allocator C scenarios pass strict warnings, ASan and UBSan:
  pinned identity and live mutation; ownerless lifetime; H-limit refusal and
  take; aggregate rollback; memoized dictionary escape; escaped-child count
  refusal; and a 100,000-edge held chain released under a 256 KiB native stack.
  The first scenario combines identity, mutation and lifetime assertions.
- The focused Debug Zig wrapper passes 12/12 (one selected test and 11 import
  blocks), with no live allocations after each scenario.
- Existing strict C ASan/UBSan regressions remain green: core 18, arenas 9,
  collections 22, and startup/frame cleanup 17. Startup includes stale ABI
  rejection; frame cleanup includes clearing the final H-only receiver.
- Guardian 88 checks pass after wiring the new C fixture and Zig wrapper into
  the existing production unit closure. No rule or ratchet was changed.

This is runtime evidence, not a completed WP-4 performance or guest acceptance
claim. The compiler still needs the explicit H construction/projection schedule
before the live-view guest cases can validate the joined implementation.
