# WP-B2a/B2b: per-module build-chain closeout

The owned module lane implements compilation, scheduling, project builds, background
check seeding, linking and test execution. Its implementation tip is
`d105943ef8f757f3b5683267245e63d0e9e5c322`; compiler and test sources are identical
to `573ce9a4e97d4deb3e874dcaa35beb0eaacbfbb0`. The final commits change only the
ReleaseFast compiler's build reservation. The lane uses native RC **ABI 3**.
This report supplies the module lane's evidence; the integrator must run the final
combined **ABI 5** gate, strict corpus and supplementary fuzz on its own frozen
source before accepting the combined plan. No main-merge claim is made here.

The [identity ledger](evidence/codex-next-modules-20260930/identity.json) records
source and compiler SHA256 values. The [raw manifest](evidence/codex-next-modules-20260930/raw-manifest.json)
indexes every file in the deterministic receipt archive, including raw failures,
corrected attempts, independent review receipts, exact measurement inputs and
replay harnesses. Accepted final receipts also have readable JSON copies beside
the archive. Every archived member was decompressed and checked against its
recorded byte length and SHA256 before publication.

## Implementation and authority boundaries

The port follows the module-compile/schedule/projects/nowait/test/interface chain.
Final links own the canonical semantic descriptor, literal and RC glue union;
archived numeric IDs do not become global authority. Symbolic imported physical
bodies and emission facts feed caller keys. Missing bodies remain unknown, so
the earlier empty-stand-in readonly pitfall does not recur. Runtime choice and
value semantics partition artifacts. Embedded bytes, provider limits and policy
participate in freshness, cutoff and cache identity using the B4 boundary.

Archive admission now validates a decoded function's ID against its reserved
symbol before installing or preferring it. Conflicting declarations reject in
either dependency order, including after an unknown stand-in. A forged
`lib.first` ID naming `lib.second` previously converted a foreign call containing
`print` into apparent self recursion and produced false readonly authority; the
negative regression now rejects before that proof can be consumed.

Declaration comparisons retain explicit `declared_mutates`, effect-bound
presence and its allowed effects. Host or C ABI declarations retain declared
effects. Only ordinary functions' inferred effects, inferred mutation summaries
and body-local facts are normalized away. Source spans are erased by the codec.
The independent admission review passed 8/8 cases after mutation correction and
14/14 after the explicit-effects correction, with zero skipped or failed cases.
Its equal-declaration controls preserve differing local/inferred facts; its
negative controls cover both archive orders and the original malformed inputs.

Six schematic keys differed at the earlier `a3fb19fc` checkpoint even though IL,
metadata and executable bytes matched. They came from the external `io.issue`
declaration: its owner had false parameter-rebinding flags while the imported
stand-in correctly kept all flags unknown/true. `blindCall` refuses an impure
callee before reading those flags. Fragment format v3 therefore always keys the
purity tag, and keys rebinding flags only for pure callees. Pure callees with
different flags still have different keys; all impure flag combinations agree.
Explicit effect/mutation and physical dependency authority remains keyed, and
host/C ABI stand-ins remain conservative. Twelve focused tests passed.

Warm checks now avoid rewriting unchanged state after proving exact previous
own/standard record identity, row order and cardinality, merged unique-row count
and standard-row classification. A zero compile count alone cannot bypass
publication. Both variant locks remain held across load through save; fresh
source/embed capture and policy checks happen before reuse. Removal, rename,
repair, new allocations or ambiguous state take the normal atomic path. A
separate read-only review found no false-positive skip in the requested topology,
row-order, removal, rename, embed, policy or shared-state cases, and bound its
reviewed bytes to frozen `573ce9a4`. That review is inspection evidence, not an
independently executed test claim.

## Executed verification and attribution

| Frozen source | Verification | Actual result |
| --- | --- | --- |
| `573ce9a4` | Strict 43-row corpus, 29 distinct programs | 29/29 equal; 62 modules, 664 unit keys/IL/metadata and 62 interfaces; 29 byte-identical executables; zero reference failures or fallback |
| `573ce9a4` | RC body-summary invalidation | 17 accepted stages and actual runs; 35 compiled, 33 reused; zero byte/behavior mismatches |
| `573ce9a4` | Embed/config/runtime invalidation | 25 stages: 21 accepted actual runs and four intended located refusals; 24 compiled, 30 reused; five runtime/semantic variants; zero mismatches |
| `573ce9a4` | Warm-check state matrix | 16/16 stages with exact whole/module status, stdout and stderr; warm state bytes, mtime and inode unchanged |
| `573ce9a4` | Additional strict check fixtures | 5/5, 21 modules, zero reference failures; all use the module path |
| `573ce9a4` | Native root and state-guard tests | 25/25 build steps, 246/246 tests |
| `a3fb19fc` | Full required lane gate | `test`, `test-qbe`, `test-qbe-build`, `fmt-check` all exit 0 |
| `a3fb19fc` | Broad interface/check/build/compile/test oracles | Interface 316/316; other oracles each 318/318; no unexpected reference failures or unchecked interface entries |
| `a3fb19fc` | Broad compile byte oracle | 622 modules, 3672/3670 units, two shared specializations, 622 interfaces, 318 byte-identical executables |
| `a3fb19fc` | Broad guest test oracle | 1457 actual tests and 97 exact intentional no-test contracts |
| `a3fb19fc` | Lox RC/GC × QBE/LLVM | Four successful project builds; four project runs each 65/65; four driver runs each 13/13; zero cached, failed, skipped or omitted names |
| `62c95a7d` | Supplementary 100-seed fuzz | 98 normal successes, two GC-stress-only findings, zero invalid programs and zero RC divergences |
| `62c95a7d` | Development/smoke guest corpus | Each size: 86/86 output pairs; development QBE/LLVM each 43/43 within 1.3× GC; no development instruction regression over 1% against original m14 |

The RC matrix changes private transitive loop proofs, allocation/sharing, borrowed
versus owned returns, immortal versus allocated returns and mutable parameter
rebinding. Each changed owner emission fact invalidates callers, and each warm
retry compiles zero modules. The embed matrix checks content-only edits, empty
and missing inputs, exact caps, tightened and widened policy, same-module semantic
deduplication, cross-module charging of one physical payload, per-file refusal,
and RC/GC/stats/sites/legacy-sharing partitions. The state matrix additionally
checks completed-neighbor retention across failed repair and held-lock fallback.

The full `a3fb19fc` gate reports 115/115 steps and 2746 selected tests passed;
27894 skips are the shard runner's excluded selections. A separate complete unit
shard run passed 2399/2399 selected tests, and CLI shards passed 301/301. QBE
replays report 51/51 and 29/29 successful steps; cached verdicts in those replays
are not described as fresh guest executions. The subsequent key/state corrections
have the focused results and final corpus above. The integrator's final combined
gate supplies broad coverage of their merged runtime source.

Lox result receipts were checked against the exact names parsed from all nine
test-bearing source modules. The original `--jobs 4` invocations returned usage
status 2 and ran no tests; their logs remain separate from corrected
`--jobs=4` invocations. Fuzz seed 19 had a GC-stress stdout mismatch; seed 87 had
GC-stress exit 139 and a stdout mismatch. Neither had an RC divergence. These
historical lane receipts do not replace the final combined fuzz run.

At `62c95a7d`, the development instruction geomeans were QBE 1.064495× and LLVM
1.069141× GC; worst rows were 1.281420× and 1.255957×. The largest increase against
m14 was 0.929680%. Smoke is output coverage, not the development ratio acceptance
gate. The archive retains both original m14 data and the matching-row comparison.

## Nominal 200k scale measurements

The preserved fixture contains **481 source files, 242445 lines and 6945618 bytes**,
with ordered filename/NUL/content SHA256
`fe3dcb39ca633c8688b38ab7d0439ec44c906542578f3598f9377fce03dfcdbb`.
The final ReleaseFast control is approved main `80dd5190`, compiler SHA256
`747e9584d0eb15afeaf75c6c3d63bce5d1775edbefaa43ad5c7a5753590e9d0c`.
The candidate is `d105943e`, compiler SHA256
`0bbc981a68e58df7df14a8d99f6cf6a18a705e438ca6d2d00f5b423cc4286682`.

Seven pairs per check phase alternate which side runs first, use separate caches
and identical source edits, and pin both sides to reserved CPUs `2,3,10,11`.
Admission, source edits and background seeder settlement are outside the clock.
All 42 warm samples and both cold samples succeeded, matched stdout hashes and
ended with identical fixture identities. All candidate warm samples used exactly
one project state; no-op samples compiled zero records.

| Final paired check phase | Control median | Candidate median | Change |
| --- | ---: | ---: | ---: |
| No edit | 0.099882 s | 0.091288 s | −8.60% |
| Body edit | 0.757658 s | 0.138253 s | −81.75% |
| Interface edit | 0.749255 s | 0.149342 s | −80.07% |

One-minute machine load rose **32.21 → 43.72**. Per-pair loads and every sample
are retained, so these are observed paired results with that limitation. An
outside-clock syscall profile shows no candidate `writev`, `renameat` or
`unlinkat` after the state guard. It supports the avoided-publication mechanism;
it does not attribute every millisecond to that mechanism.

The rejected earlier `a3fb19fc` paired experiment is preserved: its no-op median
regressed from 0.110438 to 0.123591 s (**+11.91%, about 13 ms**) under load
12.83 → 12.92, while edited checks improved about 79–81%. It motivated the
unchanged-state fix and is not silently replaced by the final result.

Earlier serial `62c95a7d` build/check/run samples also remain archived. All 60
samples succeeded, but control load 4.72 versus candidate load 26.21–26.77
confounds their latency comparison. Their minima were build body 4.695238 →
2.415195 s, interface 4.085006 → 2.125315 s; run no-op 1.555619 → 0.191834 s;
and check no-op 0.082987 → 0.135986 s (regression). The final paired check
experiment supersedes that check comparison. The historical 0.025 s check,
0.42 s build and 0.047 s run numbers were not reproduced exactly and are not
claimed as acceptance results.

## Reservations, failures and replay

Unit-shard reservation is now 2 GiB after an observed 1,312,096,256-byte peak
and 199 passing tests exceeded the former 1 GiB estimate. Only the compiler
executable's ReleaseFast reservation becomes 5632 MiB after frozen `573ce9a4`
observed 5,226,618,880 bytes against a 4,831,838,208-byte estimate. Shared compile
reservations and scheduler caps remain unchanged; all guards and test coverage
remain enabled. The successful final ReleaseFast rerun has 12/12 steps, no
reservation overrun and the identical compiler SHA. The initial enum-spelling
failure and prior estimate-overrun/retry logs are retained.

The archive also retains the original malformed-authority failures, explicit
effect failures, schematic key mismatches, early positive-path failures, the
state harness's incorrect terminal count assertion (expected 18 instead of its
actual 16 stages) and all corrected receipts. The embed matrix's original source
label was accidentally formed by replacing an earlier hash prefix; its readable
receipt explicitly corrects the label using the verified compiler SHA while the
raw original remains unchanged. Differential receipts inherit a zero `steps`
counter; stage counts above come from their actual rows and built/run counters.

Replay helpers are checked in at
`experiments/module-scale-20260929/{corpus_byte.py,corpus_programs.json,check_pair.py,measure.py}`.
The corpus driver requires an explicit frozen `--lox-entry`, accepts a portable
index and refuses reference failures, fallback or fewer than 29 equal programs.
The archived original drivers and exact Lox/scale sources preserve the measured
inputs. All builds and heavy suites used `scripts/build-slot.sh`; timing CPUs
were explicitly reserved and released. Guardian whole-tree and commit checks
passed 88/88. The integrator owns the append-only Guardian feedback entry and
its commit, avoiding concurrent writes to the shared feedback repository.
