# Support7 normal-path size-aligned counters

All eight builds and fifteen exact-input counted executions pass with zero RC
events, zero managed exit-live bytes and selected-owned LLVM/symbol audits.
Source bed11cf3 and compiler540283317 identities are pinned in results.json.

After ten runs, only the unadmitted next source-group request was canceled;
no active native compile or guest execution was interrupted. The unchanged
counted_inputs.group helper resumed the remaining three sources/five runs in
one bounded lease. The previous result snapshot, helper/hash checks and both
admission logs are preserved. Queue time is excluded from compiler/guest work.

This normal path supplies source checking and a control for the exact same
Support7 inputs replayed through the v2 adapter. Matched C0 comparisons use
the two v2 arms rather than mixing methods. This is an intermediate candidate,
not a qualified C1/default/retired implementation.
