# S3-C capability and runner qualification

Status: combined C/M/property-runner compiler and runtime source `9637eb9a1`
passes all Core, strict full conformance, provider-fixture, exact runner-report,
coverage and instruction audit checks. S3-C is qualified for integration.
This is a package record, not the S3 exit report or permission to start S4.

## Behavior

The new core owns its capability, file/network resource and Host runtime objects.
Capability tokens remain ordered runtime-call operands; source `extern` checks its
Host authority before erasing the scalar Host token from the native ABI. Counted
resources retain their authority, complete on lexical exits, and release external
handles once on final drop or fatal cleanup. Fixtures use deterministic native
providers and private filesystem directories; they do not read a real network.

The approved `ENV-NAMES-GRANT-1` correction changes the old runtime's
`myl_qbe_environment_names` to use the parsed grant allowlist rather than a native
provider's opaque callback context. `ENVIRONMENT-NAMES-1` now explicitly says that
context never contributes names. Provider ABI 7 is unchanged. Both primary test
roots build the same native context fixture and assert exactly three controlled
process names without an allowlist and `A`, `B` under `--allow-env=B,A`, with and
without `--restrict`. The native getter verifies that its private context still
reaches the callback unchanged. The old answer of one name is historical evidence,
not a qualification target.

The exactness review also ported the old bounded enumeration algorithm: collect
at most 64 distinct raw names, sort them, then discard invalid UTF-8. Both cores
reject an invalid process name without publishing it. For built-in `get`, an
explicit allowlist continues to filter without `--restrict`, matching the observed
old runtime. The source correction for that behavior is confined to the new core;
the old provider and its `get` semantics are unchanged.

## Source checkpoints

| Commit | Purpose |
|---|---|
| `722fe4851`, `e1cf3e5ae`, `4cfafc8df` | Capability/Host lowering, exact scope ownership, per-family handle limits and cleanup order |
| `4747ad071` | Approved old enum correction, SPEC amendment and context regressions |
| `83d55bf66`, `d82086871`, `65036fe79` | Primary-test argv/environment helpers and supported old build modes |
| `88b11bfc5` | Exact bounded raw-name collection and UTF-8 publication |
| `fee296958` | New built-in `get` preserves actual old unrestricted allowlists |
| `2e9a8f5bd`, `ab8169708`, `12bfafc67` | Combined M source-aware rendering, list/value adapters and compile fixes |
| `18cfe1cf5` | Exact context fixture entries in both cache input manifests |
| `d1b9b094e`, `da61d2973`, `d63257bd8` | Frozen M capture/None-key source and complete authority-test fixtures |
| `3e607848a` | Verified IR resource-owner/reverse-close assertions, replacing stale void-print syntax |
| `c340e2880` | Combined independent generator/shrinker, exact reports, native faults and private stand-ins |
| `9637eb9a1` | M canonical Unit locals across mutable place joins; combined source freeze |
| `e69c9f985` | Evidence-only final 24-report refresh on the identical combined source |

Each normal source commit passed all 88 Guardian checks. The Core IR diff against
`dc1a5831` is empty. Persisted formats remain `module-interface-v5`,
`check-summaries-v6` and `mutation-v2`. No `tests/lang` file was changed by C.

## Qualification evidence

Old full gate run04 is green: command exit 0, `138/138` build steps succeeded,
`3522/34118` tests passed (`30596` skipped), and no RSS overruns or validation
errors. The supported-mode context regression passes in both primary test roots.
The frozen source is `65036fe79`; `resume-context-old-gate-validation.json` records
the exact command, build summary, admission wait and all RSS samples.

The corrected old compiler and QBE are frozen under
`.mylang-cache/s3/env-grants-oracle`. The C package's D2 oracle was refreshed
atomically from that pair; its previous pair is archived in the same private cache.
`resume-context-corrected-oracle.json` records the gate and SHA-256 hashes:

- compiler: `d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`;
- QBE: `b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c`.

The combined freeze is `9637eb9a1aa4af8ee0ecd88838ceed09b228d812`. Its installed
Core SHA-256 is `b966a329e8516ab6b2f875e085d0af6f230ba1ddb1b328079c95ee5bcf77700e`.
`resume-combined-qualification.json` validates all final C result counts and limits
and records SHA-256 hashes of the installed Core, corrected old compiler and each
aggregate evidence file. `resume-combined-source-contract.json` verifies the frozen
IR, public provider header and untouched language corpus. Runner refresh commit
`e69c9f9855ff0d00877f3f279c640a1d3551aa64` changes only evidence. Its independent
installed compiler hash is also recorded; both builds use source freeze `9637eb9a1`.
Command logs are unique per invocation; failed runs remain available. Later runner
SPEC, fixture and cache-manifest additions require the final integrated old gate.

| Check | Result | Evidence |
|---|---|---|
| Exclusive Core rebuild at `d1b9b094e` | `3/3` steps, `1.69 s`; all three build slots and gate held | `resume-core-exclusive-01.log`, `.time` |
| Native provider/Host/grants/handles | `37/37` strict checks, old/debug/release-verify, clean leaks/facts | `resume-fixtures-02/summary.json` and each command's JSON |
| Core context regression | `1/1`, `5/5` steps, all four debug/release/verify modes | `resume-context-core-test-04.log` |
| Scope cleanup structure | `1/1`, `5/5` steps; matching owners close in reverse order before return | `resume-scope-order-test-01.log` |
| Combined exclusive Core rebuild | `3/3` steps, `3.30 s`; all three build slots and gate held | `resume-combined-core-exclusive-01.log`, `.time` |
| Combined full Core suite, 32 shards | `36/36` steps, 254 unique tests, `127.03 s`; longest shard `68.26 s`, zero failures | `resume-combined-test-core32-01.log`, `.time` |
| Combined native provider/Host/grants/handles | `37/37` strict checks, old/debug/release-verify, clean leaks/facts | `resume-combined-fixtures-01/summary.json` |
| Combined strict full conformance | Debug and release each `1518` matching, `0` mismatching, `0` unsupported; clean leaks and verified release facts | `resume-combined-conformance-01.log` |
| Refreshed exact runner reports | `24` full test-report matches, `0` mismatches, `0` unsupported; all 14 actual compiler invocations return their expected status | `../s3-runner/final-03-comparison.json`, `final-03-commands.json` |
| Combined checked coverage | Four complete child reports, all status 0; 3124/3124 language-test and 123/123 parity functions accepted | `resume-combined-coverage-01/summary.json` |
| Combined 35-row instruction audit | All raw diffs retained; zero residual changes after only proved Host scaffolding and semantic IDs | `resume-combined-identity-audit-01/summary.json` |

The fixture suite compares process status, stdout and error codes explicitly.
Malformed-provider and assertion exits record `release=1 live=0` for all three
compiler modes. The 300-deep deterministic resource fixture also completes and
closes every handle. Grant files have a fresh private directory per scenario and
mode, and read/write permissions are checked against actual file state.

## Code identity and the authorized Host changes

The original raw comparison records changed definitions for all 35 rows. Every raw
diff is retained in `resume-identity-audit-02` and the final combined
`resume-combined-identity-audit-01`. The audit's `summary.json` names every
affected function, the two timing-call blocks, the baseline/emitted hashes and any
remaining difference. All 35 have zero remaining instruction differences after
only the following proved changes are normalized:

- Native `main` now obtains its Host token from `myl_core_host_grant`.
- Source `main` has `myl_core_io_at` and `myl_core_host_check` immediately before
  each of its two existing `runtime_bench_now` calls. CFG reachability proves both
  blocks are outside cycles; no check is inserted into a measured inner loop.
- Inserted calls renumber instruction-defined SSA values and debug/site IDs.
  Parameters, labels, types, instructions and flags are preserved. Debug and
  trap/error site IDs resolve to the same semantic metadata. Removing precisely
  the two Host site entries makes each complete site table equal to its baseline.

`identity_audit.py` rejects additional or non-adjacent Host/I/O calls, changed sites,
loop-contained timing checks and any residual instruction change. The final timer
check adds constant overhead before stopping the timer. This audit does not stand
in for the final 40-row operation-count and performance checks against both gates.

The current focused built-in Environment regression passes (`5/5` build steps,
`1/1` test, `2.92 s` test wall in `resume-context-core-test-03.log`). This verifies
the approved new-core port against the separately recorded old status 1 and
`R_CAPABILITY` outcome; it is not a full package qualification claim.

Old full gate run03 completed with two test-harness failures: the new context
fixture paths were missing from the cache input manifest, and the primary test
requested unsupported old mode `ReleaseSafe`. Commits `18cfe1cf5` and `65036fe79`
corrected these before clean full gate run04 admission. Other old suites passed.
Runs01/02 retain earlier Guardian classification and test-helper compile failures.
Waiting for shared slots is excluded from the new-core rebuild budget.

## Limits

Enumeration retains the old limits of 64 names and 128 bytes per name; the built-in
text getter retains its 16 KiB value bound. The scoped providers retain eight
filesystem roots and endpoints, 256 provider handles, 64 KiB snapshot/transfer
bounds and a 4094-byte path bound. The wrapper's external-resource limit remains
1024 handles per filesystem/network family. Host keeps its published bounded
value, depth and payload contracts. User modules, persisted interfaces and
incremental module compilation remain S4 work.

Checked coverage reports 3589/3595 accepted functions over all four corpora.
The six remaining function refusals are declarations: extern `abs`, `floor`,
`main::runtime_bench_now`; Host `io::length`, `io::byte`, `io::put`. Repeated imports
produce eleven raw declaration refusals. Native declarations have no standalone
body to compile; their actual linked calls are qualified by C fixtures and the
benchmark row builds. Seven example module-name failures and four test embed
failures need their original source/module context and remain explicit front-end
coverage caveats. This is function coverage, not an execution or performance claim.

The runner refresh uses the same combined source freeze and corrected old SHA-256.
It compares complete property evidence and reasons, including integer/list
shrinking, discard exhaustion, helper contracts, Result verdicts, buffered output,
stand-in reset, name-derived seeds and native signals/silent exit 17. The runner
source checkpoint remains `d54e3dae0`; only dependency source and evidence changed.
C adds no I/O fuzz kind: deterministic provider fixtures are its qualification.
Final integrated old gate, five applications, 40-row performance/count checks and
200-case fuzz belong to the coordinator's stage exit.
