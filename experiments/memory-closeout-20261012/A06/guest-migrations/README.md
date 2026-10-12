# A06 guest source migration

C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`. The coordinator initially reserved
65 sources, then transferred `tests/lang/frontend_type_helpers.my` to A01. This
batch retains all other 64 source identities. `originals.json` preserves the initial
reservation; `ledger.json` and `original-sources/` cover exactly the final 64.

At this checkpoint, 54 files changed, with 307 additional explicit `.copy()` sites,
521 added lines and 334 removed lines. These counts are source burden, not runtime
copy counts. Thirty-eight current sources pass exploratory ownership checking;
26 remain refused pending compiler fixes. This is not native qualification.
Every assertion line and public test function remains unchanged and in order;
`record.py` enforces both invariants and freezes lossless deterministic C0 archives.
No failing source is removed from the denominator.

## Evidence and reproduction

`before.json` selects the 64 sources from A10's original 356-source survey. Its
compiler hash differs from A09's frozen C0 installation; some libraries received
an inert main in A10's checked mirror. The complete original-source hashes remain
separate. `C0-before/` preserves the first ten direct C0 checks, including its
incorrect no-main refusal, before the coordinator directed reuse of A10's survey.

The `after-*` directories preserve every completed check, source hash, compiler
hash, diagnostic and automatically applied copy edit. Later reports supersede
prior source revisions only when the hashes agree. `ledger.json` explicitly
reports whether the latest check matches each current source. Source checks use
A10's command-support compiler, without the later A07/A01/A08 fixes.

```sh
scripts/build-slot.sh build python3 -B \
  experiments/memory-closeout-20261012/A06/guest-migrations/probe.py \
  --compiler /absolute/integration/compiler \
  --output /new/evidence/directory --start 0 --limit 10
python3 -B experiments/memory-closeout-20261012/A06/guest-migrations/record.py
```

Repeat bounded batches at starts 10, 20, 30, 40, 50 and 60 for the entire reservation.
Use a fresh output directory. `--migrate-copies` was used only during exploration;
final qualification must freeze sources and omit it. Native execution of the
unchanged assertions, cleanup, all five pipelines and the complete registered
gate remain coordinator integration requirements.

## Migration choices

Borrowed parameters, projected managed values and match payloads copied into
independent storage now use `.copy()`. Aliases retained across owner mutation get
explicit independent copies. Calls that mutate an earlier argument's owner use a
named snapshot established at the original evaluation point. Scalar work may be
bound before a later move when this preserves order and avoids an unnecessary
managed copy. Fresh nested projections that need an owner across `.copy()` are
bound to named locals; `load_made` preserves both original constructor calls.
`applied-first.json`, `manual-*.json`, `site-migrations.json` and each probe report
record these changes. The final source diff and hashes are authoritative.

`immutable_equal.retained_bytes` returns `source[7:26]`, an independent owned byte
slice with exactly the original contents. The C0 source is frozen. The registered
A06 regression module retains both the original `.view()` refusal and a borrowed
ByteView escaping its local owner. No retained view is admitted silently.

The coordinator explicitly approved the following traversal migrations. Each
exact changed loop and function name is recorded in `live-iteration-rewrites.json`.
Additional `rc_pin_elide` traversal uses the same current-index rule. No source in
this A06 subset asserts a structural-shrink trap; no such test was weakened.

| Contract / functions | Explicit traversal and preserved behavior |
| --- | --- |
| Element writes, mutable callees, current fields, fixed arrays; `rc_pin_elide.walk`, `rc_nonheld_captures.test_named_source_iteration_sees_element_changes` | A while cursor compares against the current length and reads the current element before the original body. Later element writes are visible. |
| Append growth, enumerate, byte-buffer growth | Current length is checked on every visit. Cursor advancement happens before the body, so `continue` cannot repeat or skip the visit. Enumerate captures the old cursor as the original index. |
| Zip growth and element writes | The loop continues only while the cursor is below both current lengths. Both current scalar elements are read before either collection changes. |
| Indexed/compound/negative-index places | Evaluate the original index expression once, normalize negative indices once against entry length, then re-read that same child place. Original side-effect counters stay unchanged. |
| Nonstructural dictionary writes and live values | An explicit owned key list preserves the tested unchanged key order; each visit reads the current mapping value. This rewrite does not assert behavior under key insertion/deletion. |
| Root-rebinding and immutable-source snapshot tests | An explicitly named `.copy()` retains the original entry storage, exactly as those original contracts require. These are the only whole-iterator snapshots introduced for live-loop migration. |
| Field writeback loops | Read the current field each visit. Explicit local copies make the reconstructed owner independent before storing it back, preserving the next visit's updated field values. |
| List/set comprehensions and nested clauses that mutate their source | Build the same result container with a current-length loop. Filters run before produced values, with the original side effects and visits. The always-true filter has no side effect to preserve. |
| Sum / any / all generators with mutation | Explicit reduction loops preserve current-place reads. Any/all stop at the first decisive result; subsequent side effects are not executed. |
| Managed fixed-array child comprehension | Copy the current managed child before passing it beside a mutable parent, preserving independent ordinary-parameter semantics. The next child is read after the preceding mutation. |
| Unicode text / bytes field replacement | Index the current field on each visit, preserving Unicode scalar versus octet interpretation and independently owned character results. |
| `root_liveness` enumerated record replacement | Read the current record into an explicit independent copy, retain its original index, then execute the unchanged calculations and replacement. |

These migrations preserve the requested observations and make ownership choices
local. They change source allocation behavior; comparisons against original source
must not be described as compiler-only improvements. The original borrowed live
list/dictionary mutation and growth shapes remain rejection tests in
`src/core/a06_nested_write_test.zig`.

## Pending compiler fixes

Every concrete current reproducer is retained in `ledger.json`, with its exact
source and diagnostic. The coordinator owns final assignment and integration:

- A07: ordinary nested record and list-slot writes; narrowed Option generated
  `<collection>` availability; ownership/lowering transfer agreement.
- A01: tuple `.copy()` parser exception; dictionary view/construction helper paths
  and other collection lowering when assigned by the coordinator.
- A08/A01 integration: managed comprehension iteration origins (A08 commit
  `78e2eeee9`) and subsequent constructor/reducer checks.
- Coordinator with runtime/helper owners: remaining sorted/dictionary/Option
  cases. These are in-scope support blockers, not measured tradeoffs.

A06's exact field and slot writeback proposals are in `../nested-write/`. Their
registered counted tests cover independent storage and cleanup. Source admission
or a prepared patch alone does not close those implementation items.
