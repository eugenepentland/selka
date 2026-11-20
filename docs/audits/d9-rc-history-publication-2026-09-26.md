# Transactional semantic publication runtime

Private API3 slice, before compiler event emission. `myl_rc_native_publish`
implements direct semantic COPY/TAKE and child/source-child publication.
Ordinary mutable payloads reused by a successful semantic transfer receive the
sticky SHARED mark. A journal defers every new mark until all acquisitions and
pinned clone filling succeed. Refusal discards that journal before cleanup and
leaves source bytes, ownership tokens and history unchanged.

Pinned snapshots preserve the source's older region. Fresh snapshot shells stay
unmarked; their reused mutable children receive the committed marks. A later
uniqueness check detaches a semantically shared heap payload even when O=1, while
a physical O>1-only clone does not manufacture child history. Whole-view H edges
keep their identity and never trigger a mark or pinned clone.

Child-only operations scan direct logical elements/entries without changing the
source. Unpinned children are marked at commit. Protected children require a
fresh outer shell whose replacements belong only to the result. The fresh-result
mode currently uses the same conservative source-preserving algorithm.

Semantic pinned occurrences of a mutable list/dictionary produce separate fresh
shells. Reusing one unmarked shell for two outputs would give it O=2, and a later
live view could observe a physical detach absent from GC's separate snapshots.
Immutable-box DAG memoization and physical region escape retain the existing
memo; their prior C fixtures still pass.

The new suite has 17 cases, including exact view/snapshot/original observations:

| Scenario | Expected values |
|---|---|
| Snapshot then original mutation | `7, 11, 13` |
| Original then snapshot mutation | `7, 11, 13` |
| Loan, then pinned publication | `13, 11, 13` |
| Publication before pinning | `7, 11, 13` |

Other cases cover count/metadata refusal, failed clone prefixes, ownerless H,
TAKE, child marking, whole views, arena mark rollback and older-region pinned
snapshots. ASan/UBSan pass these 17 plus the existing 21 core, 27 collection,
10 arena, 12 live-hold, seven loan and 23 startup/frame scenarios: 117 checks.
The focused Zig C harness passes 12/12; Guardian passes 88 checks. Runtime mutable
classification uses native list/dictionary header predicates, so the standalone
core fixture now links the existing native-heap source closure.

This is not a completed semantic-history integration. No compiler loans or
semantic events are emitted yet. Existing helper physical COPY paths still mark
arena aliases and can clone pinned children before a later semantic event;
the helper/publication audit must resolve that ordering before enabling this
slice. Box receiver write-back and unconditional body detachment are separate
compiler work. The parent owns the cumulative gate after the cohesive change.

Run `scripts/build-slot.sh build python3 experiments/d9-rc-history-publication-20260926/check.py`
for the sanitizer matrix. Source identities and full verdicts are in
[evidence/d9-rc-history-publication.json.gz](evidence/d9-rc-history-publication.json.gz).
