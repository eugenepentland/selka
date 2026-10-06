# S3-C capability and runner qualification

Status: source checkpoints are committed; combined final qualification is in progress.
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

Final combined Core/runner checks will be recorded below after their source freeze.
Command logs are unique per invocation; failed runs remain available. Later runner
SPEC, fixture and cache-manifest additions require the final integrated old gate.

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

The strict fixture, runner-report, conformance, leak/fact, coverage, identity and
developer-loop results remain to be filled after combined qualification. C adds
no I/O fuzz kind: deterministic provider fixtures are its qualification.
