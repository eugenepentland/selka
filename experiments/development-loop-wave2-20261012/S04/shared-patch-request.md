# S04 safe copy and validation reductions

B0 `c1857310e0bf623545380c8de24515f1b9970021`; owned Snapshot.selected_files
returns copied selected records using a predicate receiving only immutable paths.
No watch, metadata, membership, mutation or authority check changes.

Coordinator action_payload patch:

```python
files = snapshot.selected_files(lambda path: any(
    matches_recipe(path, recipe, root) for recipe in group['inputs']))
```

Pass `files` to qualified_identity instead of `snapshot.identity['files']`.
Exact declared closures still authenticate. If a group accidentally omits a
producer source, selected-source authentication must retain whole artifacts.
Add an omitted-closure fixture using a full source snapshot and narrowed group
recipes, proving conservative fallback. Existing full source watches remain live.

Measured actual 46-group/4,639-file union: baseline file-record copies 213394,
candidate 14021, avoided 199373 (93.4%). Projections and canonical digests are exact;
selection generates no metadata/hashes/enumeration. This counts selection copies,
not timing, and excludes two extra baseline full-union copies during native
producer authentication. Raw actual-selection-profile.json.

Second coordinator patch: remove only `or not tools.unchanged()` from the immediate
provider-resolution equality condition following tools acquisition. Acquisition
has already validated retained authority. Every path to execution, receipt
publication or reused complete verdict then performs a complete global validation:
prepare admission/publication on cold paths, cache lookup before reuse/gate,
gate admission, final execution validation and publication. Keep provider path
resolution equality and every later global check unchanged. The result safely
rejects a tool mutation later, before execution/success, rather than granting a
longer lease or memoizing observations.

Exact B0 lifecycle reconstruction matches 175816 metadata / 31 calls / 6 retained reuse.
Removing that single redundant tool scan yields154025 metadata / 30 calls / 6 reuse;
21791 observations avoided (12.4%), with 0 hash/enumeration preserved. Tool scope
alone accounts130746 / 175816 observations. Raw validation-scope-profile.json and
validation-scope-candidate.json. These reproduce snapshot work; no gate was run.

Port three actor fixtures from verification_revalidation_test into existing
coordinator tests **without** its B0-only scoped first-check suppression wrapper:
- Prime a retained warm request, mutate then restore tool bytes during second
  tool_contract call, assert RETRY before any admission and no success report.
- Repeat cold, assert preparation admission rejects and creates no success receipts.
- Unchanged warm request still returns complete reuse and0hash/enumeration.

The standalone wrapper models the old caller's removal for evidence only; it
must not suppress the first remaining global check after production code changes.
Initial tool-byte mutation watch remains sticky even after byte restoration.

Register only meaningful new production tests through existing cohorts. Profiling
scripts are developer evidence tools and do not belong to install graph. Add
new profile helper dependencies if root elects to register its tests. Snapshot
loaded-code integration remains S08/helper and coordinator-owned; this patch
avoids identity integration lines. Final changed configuration consumers/pin need
explicit final audit, not automatic digest replacement.
