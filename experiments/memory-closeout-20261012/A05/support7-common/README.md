# Common Support7 A05 qualification — blocked by warm memo cache

All runs use the completed owned Support7 installation, compiler source
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`, binary SHA256
`540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
`compiler-identity.json` records the installation; `stdlib-inputs.json` proves
all thirteen worker library modules match the frozen source byte-for-byte. No
private compiler or library overlay is used.

The original matrix completed all 192 planned lanes: 36 native cases times five
modes, plus twelve expected source refusals. It contains 171 passing native
cases, four silent memo build failures and five parser refusals in the historical
native clock/entropy fixture. Every original receipt is preserved as `batch-XX.json`.
The two-line source migration documented in `../time-random-provider-migration/`
then passes all five modes and thirty additional native-provider error executions.
`current-input-batch-13.json` explicitly substitutes only that proposed source;
it does not overwrite the original failing receipt.

For proposed current inputs, **176/180 native cases pass and 12/12 refusals pass**.
Release, unoptimized debug, verified release, optimized debug and release without
facts all appear in the same-compiler matrix. All admitted counted runs have zero
observed RC events and zero managed exit-live bytes, with generated LLVM and
linked-symbol audits. Raw counters retain traffic/peak/function data; these
observations are not RSS or uninstrumented runtime/compilation timings. No
performance claim is made here.

The 120 public declarations remain classified. 115 have complete five-mode
executable evidence. `memo.create`, `call`, `clear`, `count` and `capacity` lack
the four failed warm lanes. The strict current-input export gate reports
**0/120 qualified**, because any failing required receipt blocks release
qualification. Complete public qualification is not claimed from partial coverage.
`current-input-export-qualification.json` records the four blockers; the original
export report additionally records the superseded source/parser failures.

The unchanged original borrowed-entry Context passes fifteen actual authority
executions (five modes times granted/missing/denied target), with no stand-in
replacement of entry providers. Nine borrowed-context source negatives pass,
and seven cache/edit/relocation cases pass (six executions plus one refusal).
`entry.json`, `borrowed-negative.json` and `borrowed-cache.json` contain exact
commands and hashes. Wider caller-owned borrowed contexts, provider records and
complete owning tuple unpack all pass the main matrix. Resource/file forwarding,
@ensures, network success/error paths, managed pools, dictionary defaults,
readonly managed get, persistence and binary stream writes also pass.

## Blocking reproducer and remaining work

A08 owns the warm memo semantic-cache defect. Exact original source/failing
commands and independent fresh/warm controls are in `../support7-memo-reproducer/`.
A fresh debug build succeeds; an identical warm build exits 1 with empty
stdout/stderr, while source checking succeeds. No execution or RC/leak result is
claimed for a failed build. A08's copied-cache controls localize the defect to
typed semantic reuse; stage-only replay succeeds. The larger memo guest fixture
passes all five modes, and its receipt remains in batch14 as a separate control.

Fix and regress the cache defect, then rerun affected and required final matrices
on the final common compiler. Support7 is not C1 completion, default promotion,
active RC retirement, complete package qualification or the final registered gate.
The source migrations and evidence are reviewable; no publication was performed.
