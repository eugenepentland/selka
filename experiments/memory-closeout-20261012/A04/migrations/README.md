# Guest source migrations: interim evidence

The coordinator reserved these 19 guest sources after A10's complete source
survey. `sources.json` keeps the C0 hashes, exact original snapshots, migrated
hashes, line counts, copy counts and every original public test name. None of
the 133 public test functions or their value assertions was removed.

The current source migration changes 18 files: 115 added and 112 removed lines,
with 61 additional explicit `.copy()` calls. Copies preserve independently used
owners and borrowed managed return values. Captured receivers are copied before
nested mutations when the assertion requires their earlier contents. Retained
byte `.view(start,end)` calls become owned slices with the coordinator's explicit
approval; this preserves the existing value assertions, not allocation or shared
identity behavior. These are source migrations, not compiler-only savings.
The separate A04 borrowed-view fixtures and existing negative retained-view
regressions remain intact.

`check-02.json` records 14 admitted source files and 5 refused ones on C0.
`execution-01.json` runs the 13 admitted files containing tests, plus the imported
format helper through its original parent. On A10's interim support compiler
SHA256 `8a4f53e6202bd25c44f0b7a65851b281188a6921630b5862ec6aaa6725e798f9`,
all 74 ordinary test executions pass; 72 checked-ownership executions pass and
2 refuse native lowering. Guest tests use release with verified facts, forced
execution and managed leak checks. The five source-refused files remain in
the 19-file denominator. This is not final C1 qualification.

Remaining compiler regressions, sent to the relevant owner:

- A07: `temporary_encode.my` reproduces the fresh `str(float)` receiver inside
  a loop incorrectly inheriting the numeric local's ownership origin. A08
  identified the cast-origin cause; outside-loop encode succeeds.
- A04/A07: `repeat_temporary.my` reproduces text repetition gathering the same
  owned operand repeatedly. A04 is replacing the unnecessary gathered-list
  lowering with the existing fresh-result octet repetition helper; A07 owns
  its explicit runtime contract.
- A08: `sorted_bytes.my` and `list_dict_keys.my` reproduce generated iteration
  moving borrowed managed elements into independent results.
- Coordinator/A07: `tuple_borrow.my` destructures an ordinary borrowed tuple
  containing text. The current tuple API has neither `.copy()` nor indexing,
  so no source-only migration preserves the existing helper's signature.
- A07: `rc_plain_update_paths.my` passes source checking but nested
  `frame.rows[0].append(5)` and `push(mut frame.rows[0])` refuse native lowering.
  The mutable-field-only test succeeds. Original assertions remain unchanged.

Run `check.py --compiler COMPILER --phase UNIQUE` under shared build admission;
it preserves original source entrypoints and adds an inert main only to an
isolated survey mirror when necessary. `run_tests.py` acquires bounded shared
leases internally and records command results, compiler/source hashes and every
test name. Reports are never overwritten. Final qualification must rerun these
sources after the integrated compiler fixes land.

The support4 survey (`check-support4.json`) now admits 18/19 sources after the
integrated compiler repairs. `first_word` in `python_expressions` additionally
copies either borrowed string return; this keeps its existing generic ordering
assertions. `sources-support4.json` records the resulting source hashes and
burden separately from the earlier immutable manifest. The sole remaining source
refusal is the borrowed tuple destructure owned by A07. Native support4 execution
is recorded independently; source admission is not its pass criterion.

`execution-support4.json` completes the admitted subset: all 128 ordinary guest
tests pass, and checked ownership passes 124 with two native-lowering failures
and two unsupported float-formatting helpers.
The failures are the unchanged nested-element/nested-write tests in
`rc_plain_update_paths.my` (`E_ZERO_RC_LOWERING`, lines 28 and 53). A07's prepared
path reconstruction work owns these reproducers. All nineteen assigned files
remain in the report: seventeen executed, one helper exercised through its
importer, and `tuples.my` with five tests source-refused. The resulting 133-test
denominator is preserved. These are support4 results, not final qualification.
The two `python_text_surface.my` repr tests refuse the unaudited helper
`myl_core_format_float`; A07 owns its contract audit. The guest runner exits zero
for an unsupported-only file, so command status alone is insufficient evidence.

The guest-test harness can resume a queued checkpoint while preserving completed
file/mode results, only with matching compiler identity, survey and source hashes.

Support6 (`check-support6.json`, `execution-support6.json`) completes the next
source/native survey on compiler source 5167c588be79dd43d21d5013c36db15110bf239b,
SHA256 bc6432a75fc1fa0dbcbd2048a5c8dbe2909d7590e90ae729688ed4f6e69978d4.
Source admission is 18/19; the admitted subset executes 128 original tests in each
mode. Ordinary passes 128/128; checked ownership passes 127 and retains one native
failure. There are no unsupported tests in the admitted subset. Both numeric
repr tests now pass, and the nested-write regression now passes.

The remaining native failure is `push(mut frame.rows[0])` at line 28 of
rc_plain_update_paths.my, with E_ZERO_RC_LOWERING. A07 owns that path; the original
assertions and explicit captured snapshot are unchanged. The five tuple tests
remain in the 133-test total: Support6 fixes the tuple.copy frontend panic but
refuses the narrowed optional tuple unpack `const number, letter = found.copy()`
at line 26. A01 owns complete unpack support. The candidate tuple source is kept
in `tuple-copy-repro/source-support6.my.txt` and remains unqualified; this evidence
commit does not integrate it into the shared source. `sources-support6.json`
records 116 added lines, 115 removed lines and 63 extra explicit copies against C0
for the complete current 19-source candidate. All original assertions remain.
The Support5 source survey is retained independently, not relabeled as Support6.

No active A04 guest jobs remain after this run. Final C1 and affected C2/C3
qualification must consume exact new compiler/source identities and must keep
both blockers visible until their original cases pass.
