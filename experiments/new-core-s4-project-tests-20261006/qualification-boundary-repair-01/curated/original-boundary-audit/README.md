# Qualification boundary audit

This is a read-only tooling audit. It launched no compiler, native guest, build,
gate or fuzz harness. `audit.py` calls existing metadata/report predicates and
the inherited strict monitor with explicitly synthetic `CompletedProcess`
results. Synthetic results are reducer fixtures, never qualification evidence.
Only this F experiment directory was written. The M worktree and audited source
bytes stayed unchanged at `0acc9d1a70316d8b9e5ee3218f62fcafaf26a5c9`.

Command: `taskset -c 0,1,4-9,12-19 python3 experiments/new-core-s4-frontend-20261006/qualification-boundary-audit-01/audit.py`

## Concrete findings

1. **Source labels are not bound to artifacts.** The actual old oracle
   `d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`
   is bound by the retained S3 `resume-context-corrected-oracle.json` to
   `65036fe792ef540392d0eb00c41c9ec71c7b2c82`. Its corrected Environment gate,
   installed/frozen paths and SHA are recorded there; commit `51e641fa3` retained
   that receipt. Later S3/S4 source-freeze receipts prove its subsequent use and
   copies, not a different production origin. The same actual binary can be
   passed to `support.manifest` with the unrelated valid revision
   `a16a324e629c1c68e0180017f6d2faf20364b13d`; this is accepted and
   `support.unchanged` returns true. The correct-label control changes only the
   declared old source. E private-02's 1518 comparisons per mode are historical
   behavior evidence, with a provenance error in the old-source label.

2. **Generated project live inputs are not guarded.** `snapshot` records the
   retained copies, not the live paths. Editing `leaf.my` and adding a case file
   after snapshot leave `support.unchanged` true. The actual project wrapper's
   `run` and final qualification predicate do not re-inventory the live phase.
   This permits old and Core to compare different inputs or a receipt to claim
   retained source bytes that were no longer the command's inputs.

3. **Strict fuzz tracks path identity across compiler modes.** The reducer feeds
   the actual S3 monitor an old source with a loop, removes that loop before all
   three Core mode builds, and supplies equal synthetic native results for all
   five argument sets. `s2.qualify`, the S3 native completeness check and the S4
   `qualified_kind` predicate all accept; the retained source is the first old
   version. This proves a bookkeeping false pass, not an actual compiler result.

4. **Optional report counters can contradict verdicts.** The actual parser
   accepts passed=1/executed=0 and accepts dropped=1 or unloaded=1 with exit 0.
   The old report producer defines executed as passed+failed and its directory
   producer returns setup failure for dropped/unloaded inputs. The current
   parser only bounds executed and ignores the other two fields.

5. **Generic qualified does not mean the full S4 gate ran.** Full all-file
   selection/coverage accepts debug+release/1518 with leakcheck=false and
   verify=false. Both flags are retained, so a caller can enforce them today.
   Similarly fuzz explicitly allows package=50 and final=200; no count confusion
   was found in `qualified_kind`, which checks exact integers and native totals.
   A final consumer must inspect these fields rather than use qualified alone.

## Smallest corrections proposed

* Require an immutable source/build receipt for each oracle. Validate its binary
  hash against the actual executable and require any source assertion to equal
  the receipt's production source. Record the receipt path/hash in the new
  qualification manifest. For the existing old artifact, use the genuine S3
  corrected-oracle receipt and its retained build/gate chain. Do not manufacture
  a fresh build receipt or relabel it to the evidence HEAD. For future builds,
  capture the actual command, mode/flags/tool identities, production commit,
  complete consumed source/generated-input inventory and before/after source
  checks when the build runs. Keep production source, build-evidence commit and
  qualification/evidence HEAD as separate fields. Bump receipt interpretation.
* Bind each generated project phase to a complete live relative-path inventory
  plus content hashes. Check it before and after every old/Core command and once
  more before accepting the case/final aggregate. Explicit harness mutations
  advance the phase only after the previous phase checks. Outputs/caches are
  outside those input roots, so do not exclude arbitrary new input members.
* In the S4 local monitor subclass, capture source bytes at first encounter and
  check them before and after every build, across all modes, and at final
  acceptance. Include any imported/provider/embedded/config inputs actually
  allowed by a generator. Keep the inherited S3/S2 harnesses frozen.
* If present, require executed == passed+failed. Reject nonzero dropped/unloaded
  counters for these comparisons, with strict integer/schema checks.
* Distinguish diagnostic/package/final scope explicitly. A full S4 conformance
  result requires both leakcheck and verify; a final fuzz result requires all nine
  kinds at 200 accepted cases and the already-enforced exact native totals.

## Reviewed limits

The conformance adapter checks the full tests/lang inventory against the retained
baseline before and after its run; no corresponding live-corpus gap was found
there. Its exact coverage rejects missing/duplicate files, missing modes, empty
aggregate selections and count differences. The earlier CLI forwarding repair
is present and its four-combination regression remains meaningful.

Timeout cleanup was reviewed against the retained 12-test pure suite and the
dedicated per-command supervisor implementation. This audit did not rerun
process/timeout actions. Fuzz workers acquire normal build slots; the entire
old/fuzz exclusion lock remains an external invocation contract, not a manifest
assertion. No additional lock-loss defect was found in that worker path. Package
and final admission/old-gate receipts still need their existing independent
review. This audit does not qualify any compiler package or timing gate.
