# Live-view mapping snapshots

The compiler now preserves a mapping snapshot extracted from a live view, including
when the extraction is the last read of the view or an aggregate containing it.
Copying the view itself still preserves its mapping identity. This fixes the
missing GC copy; the separate GC/RC sharing-history difference below remains open.

## Evidence and scope

The unchanged minimal reproducer constructs `HeldFields(live, live.mapping)`, writes
11 through its snapshot, then writes 13 through the original mapping. Accepted
stage-3 compiler `f6bea5d9` and the pre-fix compiler both print `[13] 13 13` under
GC stress on QBE and LLVM: the snapshot was lost. The pre-fix RC result is
`[13] 11 13`.

The final corrected Debug compiler is SHA256
`f94d79ab9370df6a84e0dec750e89ae8c476ce1703be4606e9796097800f1b08`.
Both actual backends produce these exact final results:

| Mutation history | GC stress | RC counted |
| --- | --- | --- |
| Snapshot to 11, then original mapping to 13 | `[7] 11 13` | `[13] 11 13` |
| Original mapping to 13, then snapshot to 11 | `[7] 11 13` | `[11] 11 13` |
| Share, change snapshot and original, then create view and change original again | `[17] 11 17` | `[17] 11 17` |

These are printed observations of the view, snapshot and original, not conclusions
inferred from a Boolean test. GC retains its semantic shared mark after the other
owner detaches. RC's remaining physical owner can reuse the object held by a view.
No runtime policy is changed here, and this report does not claim runtime parity.

## Compiler rule

`ownership_classify.sharedProjection` follows local alias paths and recognizes
externally held identity. A last read cannot move a mapping through a live view.
The same rule serves ownership explanation and explicit `value_copy` decisions.
The recursive live-view predicate covers records, domains, fixed arrays, variants,
collection elements/keys and physical boxes. Cycles stop at the current path;
128 levels or 4,096 visited nodes conservatively refuse copy elision.

Independent publications use this rule. Internal receiver temporaries retain their
existing loan/callback analysis: forcing `list(view)`'s hidden mapping receiver to
copy would break live-view behavior. An initial candidate did exactly that; the
broader dictionary-view test caught it, and the final classifier excludes those
nonpublishing captures. Explicit copy sites remain strict.

Lowering also recognizes `mapping.values().mapping` as a place despite the fresh
view wrapper. Deep-copy independence no longer claims that a live view duplicates
its mapping. The class/Cell predicate used for mutation checking is unchanged.
Both field-return and indexed-payload-return eliders reject live-view-bearing
sources, so a later optimization cannot undo the required snapshot.

## Validation

The focused run passes 22 tests, including ownership explanation, recursive
reachability and the existing positive field/index-return optimization tests.
Whole-tree Guardian passes all 88 checks. The permanent fixture adds nine cases
covering direct and nested record/array/list/variant projections, fresh wrappers,
field/indexed payload store-back and ordinary view identity.

The full regression run passes 45 assertions per backend/mode (180 total):
GC stress and counted RC on QBE and LLVM O3/fullLTO. RC counts match between
backends: 5,388 heap allocations/retirements, 3,662 acquisitions/9,050 releases,
2,320 holds acquired/released, 26 arena allocations and 29 cloned shells.

[Compressed raw evidence](evidence/d9-live-view-snapshots.json.gz) preserves
the complete results. The exact three-history probe and full regression driver are preserved in
[`experiments/d9-live-view-snapshot-20260926`](../../experiments/d9-live-view-snapshot-20260926).
The raw evidence retains the rejected candidate's failure, the corrected runs,
commands, compiler/source hashes, stdout/stderr and RC traffic. The parent branch
owns the combined full gate and the subsequent semantic-history correction.

## Bounded reachability corpus audit

The bounded type walk was checked for loss of optimization on the frozen migrated
Lox corpus and both recursive-tree parity sources. Before/after ownership
explanations have byte-identical per-function copy-site decisions: lox (400 functions, 382 sites), binary_trees (3 functions, 0 sites), binary_trees_recursive (3 functions, 0 sites).
The Lox checks took 0.654 and 0.662 seconds. This establishes that the new
conservative reachability boundary does not suppress a copy elision in these
corpora; it is not a general guarantee for arbitrarily large type DAGs. If a
future corpus reaches the bound, use memoized graph reachability rather than
raising the path budget. [Raw comparison](evidence/d9-live-view-copy-audit.json.gz).
