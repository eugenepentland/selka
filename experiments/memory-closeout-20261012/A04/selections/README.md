# Borrowed text extrema and Optional defaults

The feature admits two-text `min`/`max` and aggregate `Option.unwrap_or` without
turning the selected value into an owner. Inputs evaluate once, eagerly and in
source order. The first input is loaned during evaluation of the second; both
possible owners remain borrowed through the result's last use. Independent
storage requires `.copy()`. Generic branch and loop ownership joins are unchanged.

`typed.BorrowSelection` records the exact operation and its two source expressions.
Frontend walking, effects, origins, value semantics, duplicate fingerprints and
typed dumping handle the new node. Core uses the existing octet comparator or
borrowed Optional payload read, then A07's exact versioned three-argument choice
marker preserves both owners across the join. The marker is validated and erased;
it has no runtime allocation. Optional boxed payloads use `box_get`, never a take.
Live type validation rejects wrong string/Optional shapes, out-of-range operands
or record identities, affine ownership and pending Result obligations.

This contribution requires A08's atomic typed-schema/semantic-cache-v9 commit
`779ea9a62d0bdbe6f62f7fa1cb2fc243cb9ba33f`. A08 separately qualifies decoding,
publication, specialization and relocation. The exact root-authored schema and
A08 semantic files were validation overlays in this worker tree; they are not
duplicated in the A04 feature commit. Root authored SPEC and test registrations;
A07 authored and reviewed the marker utility, source checker and Core API hooks.

## Qualification

The frozen worktree overlay on base `07f16c65415819c36c46eb0657530abce734e395`
built compiler SHA256
`70525285968f79d1bd3e78705b189763ea015d4ac9073676eb0eaa1ed6667d5e`.
`source-manifest-prototype-04.json` records every source digest; the base commit
alone does not identify this compiler. `prototype-04/provenance.json` connects
the manifest, compiler and guest fixture. No production code or guest assertions changed after this build.

- Core 5/5: exact marker signatures/producers and live logical type refusals.
- Frontend 11/11: four selection cases plus seven always-run unit blocks. These
  check evaluation order, noalloc effects, both writable origins, independent
  named copies and exact duplicate fingerprints.
- Native 6/6: release, debug, verified release, optimized debug, release without
  facts, and ordinary RC release control. All return zero with empty stdout.
- Source negatives 8/8: invalidation during second evaluation, invalidation of
  either parent during a later argument, escaping a fresh selection, retained
  derived view, affine Optional carrier and pending Result Optional carrier.

The guest covers dynamic Unicode, empty/equal values, nested extrema, both fresh
inputs, eager Some/None fallbacks, discarded results, repeated owner replacement,
scalar controls, lists and wide managed record payloads. Explicit copies survive
destruction/replacement of every original owner. All five checked lanes have
zero RC events, zero exit-live managed bytes and clean LLVM/linked-symbol audits.
The ordinary control preserves behavior and releases all managed storage.

The complete counters appear in `prototype-04/results.json` and its raw records;
`metrics.md` separates traffic from managed peak. Checked release uses 114
allocations/7296 cumulative bytes and peaks at 768 managed bytes for this complete
fixture. These are absolute fixture observations, not a speedup or allocation
improvement claim. Ordinary RC's sharing has different copy/storage behavior;
its 76 allocations are a semantic control, not a competing checked-ownership
implementation. No RSS or timing conclusion is drawn from these counters.

An initial frontend origins assertion incorrectly expected a returned list to
retain parameter origins. Ordinary return semantics require an independent
copy, so the correct test changes only a named home into a compiler temporary
and verifies both write origins. `build-01.log` retains that failed test attempt;
`build-02.log` records the corrected pass. Guardian then requested mechanical
formatting, shared import, condition-layout and test-helper changes.
`guardian-01.log` preserves that attempt. After those changes, `build-03.log`
and `prototype-03/` repeat those checks after the first mechanical changes. The complete earlier native result in `prototype-02/`
retains its own compiler and source identities. Initial no-cache source checks also
passed all nine outcomes and remain in `check-prototype-01.json` with their own
older compiler hash. They are not relabeled as native or v9 evidence.

Run `qualify.py --compiler PATH --source-commit SHA --phase FRESH_NAME` with the
shared development environment. The harness owns admission; do not wrap it in
another build slot. Add `--default-ownership` only for the promoted compiler;
checked ABI/counter audits remain mandatory. Final integrated C1/C2/C3 reruns,
full verification and package qualification remain coordinator work. Current
prototype ordinary mode still contains RC; this is not retirement evidence.

The earlier checked builds in phases02/03 also emitted compiler SafeAllocator
reports despite returning status0: 112 allocations/23476 bytes per build. The
ordinary compiler stderr was empty. `compiler-leaks.json` separates these from
the guest counters; those earlier results certify guest behavior, not clean
compiler storage. A08/root identified the omitted already-integrated verifier
scratch-arena fix `522e66671`. After applying it as a validation dependency and
finishing the remaining Guardian condition split, `build-04.log` again passes
all16 focused tests and `prototype-04/` repeats the complete14-case matrix. The
strengthened harness requires empty compiler stderr, which every final native
lane satisfies. The arena fix is already present in coordinator integration and
is not duplicated in this feature commit. Final prototype source hashes include
that dependency. No new compiler leak defect remains from this observation.
