# Read-only review of transferredSlots replacement

P3 reviewed P7's current replacement and all changed call sites without changing
P7 files or launching compiler/native jobs. Reviewed source hashes are in
`replacement-review-inputs.json`. These are static algorithm/IR findings, not
new source-level or native failure reports. P7 owns fixes and qualification.

## What the replacement fixes

The lookup now checks instruction order within a block and block dominance
across blocks. Consequently a future read in the same block and a read confined
to a sibling branch no longer mark an ordinary store taken. It preserves a
legitimate earlier read in a dominating different block, unlike a same-block
restriction. Reachability is checked in the cross-block dominance walk. The
walk terminates after at most the dominator-array length.

`own.zig` builds the bitmap once before consuming the marks; `stores.zig` builds
one bitmap for each dead-store/narrow-store phase; `emit_llvm.zig` builds it once
while initializing function memory state. The emitter and dictionary emitter
use the current instruction index. `elements.storeBack` receives the current
store's already-computed boolean. No remaining caller rebuilds a CFG per store.

## Static classification gaps and required invariants

The helper asks whether **any** earlier dominating read has this key. It does
not establish that the transfer remains pending until this particular store.
For example, with identical resolved owner/index operands:

```
r  = list_get(L, i, place_read)
s1 = list_set(L, i, a)
s2 = list_set(L, i, b)
```

Its bitmap marks both `s1` and `s2` taken. If the old slot owner was transferred
by `r` and restored/replaced by `s1`, `s2` must release the owner now in that
slot. Current matching does not inspect or invalidate at `s1`. A related exact
IR shape is `r` in the preheader followed by `list_set(L, i, ...)` inside a
loop: preheader dominance is true on every iteration, while `r` executed once.
Dominance alone therefore does not prove a fresh pending transfer per dynamic
store execution. Ordinary exchange loops with their read inside the loop are
not themselves problematic.

**Qualification:** frontend lowering normally gives each list-set result and
loop-carried receiver a distinct SSA version. That may make these exact shapes
unreachable for admitted source. This review did not prove that invariant over
all lowering/optimization/ownership rewrites. These are concrete helper
classifications requiring either invalidation/pairing or a documented and
tested IR invariant, not demonstrated public-source leaks.

The key also loses dictionary projection identity:

```
k = dict_entry_key(D, i, dict_take_key)
s = dict_set_value(D, i, replacement)
```

Both keys become `(resolve(D), resolve(i), null)`, so the earlier key read marks
`s` taken. Transferring a key does not transfer the dictionary value that
`dict_set_value` overwrites. A `dict_entry_value` should match the value store;
a `dict_entry_key` should not. The broad `transferredRead` predicate remains
useful for owned-read classification, but store pairing must distinguish the
physical projection and the appropriate take bit.

**Qualification:** current key-pop lowering pairs the key read with
`dict_remove`; a later public value overwrite normally uses the removal's
new SSA receiver. No public-source/native dictionary failure was demonstrated.
Projection-aware pairing would remove dependence on that incidental shape.

## Compile-cost bound

The new hash table and single CFG remove repeated whole-function CFG building.
However `transferPrecedes` scans every read candidate for each same-key store,
and each cross-block candidate can walk the entire immediate-dominator chain.
The pairing work is `O(sum_store candidates(store) * dominator_depth)`, with
worst bound `O(S * R * B)` for stores, same-key reads and blocks. That is cubic
when all scale with function size. Even same-block stores before many future
same-key reads produce quadratic scanning. This is a static asymptotic bound,
not a measured compile-time regression. Copy-chain resolution and CFG shape
construction add their own cost; the stated bound is not a claim that those
are constant-time.

The per-query `idom.len` guard bounds termination, not total work. P7 should
consider constant-time dominance queries plus per-key pending-transfer
tracking, or an explicit conservative bounded-work strategy whose fallback
cannot release a transferred old slot twice. No timing run was made by P3.

Findings were sent directly to P7 (`parity_measure`) and the coordinator, with
native outcome and helper classification clearly separated.
