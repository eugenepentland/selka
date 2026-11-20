# D9 WP-4: bulk child uniqueness and relocation boundaries

`myl_qbe_rc_unique_elements(ctx, list_type, list)` is the RC bridge for a
compiler-proven unique list whose live elements are ordinary owning managed
pointers. Both the declared element metadata and the runtime list element
metadata must have ordinary POINTER shapes. Holds, raw unique resources and
inline aggregate elements are outside this interface. The compiler remains
responsible for proving the loop does not create extra owners or invalidating
aliases; this bridge does not infer that proof.

Each live slot uses the existing `myl_rc_unique_owned` transaction at the actual
list region, even when the current region is deeper. Null slots need no work.
A failed child leaves that slot unchanged and reports the existing located
count/region/allocation error. Earlier successful detaches remain published and
value-equivalent. The GC helper is unchanged.

Production ASan/UBSan startup/frame fixtures pass 20 scenarios (five startup,
15 frame/bridge). The two new cases cover repeated child aliases, a pinned
source, count-limit refusal after two successful prefix detaches, successful
retry, balanced child ownership, null elements, and outer-arena destinations
while a deeper arena is active. The core contract fixture passes 20 scenarios,
including a new finalizer reentry case with queued siblings and a proven raw
TAKE. All 37 focused RC Zig tests pass.

The public drain contract now states the guest-boundary invariant explicitly:
ordinary guest entry follows a fully drained public ownership operation;
finalizer reentry inherits the active outer drain, where a nested drain is a
no-op. Direct-edge adapters cannot enter guest execution. A proven pure token
relocation introduces no death and requires no drain. C code using internal
enqueue-only helpers must drain before entering guest execution outside an
active finalizer. The regression queues two siblings, relocates an existing
owner without count changes, releases it during callback reentry, and confirms
all deaths remain pending until the outer drain resumes. No private queue-state
ABI is exposed to generated code.
