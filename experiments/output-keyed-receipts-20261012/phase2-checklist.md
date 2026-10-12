# Lane F phase 2 checklist

What changes once Lanes B to E are merged, from the plan's Lane F bullet
(Section 3) and its rollout (Section 7). Phase 1 changed only `CLAUDE.md`
(gate cost, admission directory, `stage.sh`, prune schedule, configure cache),
`docs/README.md` and this directory. Every item names a proposed owner file; an
item marked "verify" may already be done by its lane and only needs the
cross-document consistency pass.

Order on the merged tree: build it, run `matrix.py --dry-run` (the feature
probes must flip to true for the landed lanes), run the cheap rows (1 without
`complete`, 6, 8, 9, 10, 11 `same-compiler`), then the heavy rows one at a time
in a scheduled window, then the cohorts. Update documents only to what the
matrix shows.

## Documents

| Document | Owner lane in phase 1 | What must change |
| --- | --- | --- |
| `docs/tooling/guest-tests.md`, "Reusing unaffected results" (line 532 on; the plan's 536-620) | B | Two receipt tiers: the IR receipt (unchanged meaning) and the execution receipt keyed on `program_key`, `runner_identity`, settings, cases, configuration, policy and keyed environment; whole-program execution receipts; `cache.reason` values `exec-receipt-hit` and `whole-exec-receipt-hit`; the `exec_receipts {hits, saves}` field of `--json`; fact and leak runs now keyed (D1) and the integration gate's forced run; `--force`, `--no-cache`, `MYLANG_TEST_EXEC_RECEIPTS` while opt-in; v3 namespaces; root-relative entry paths (private and portable keys merged); default shared test store location and how to disable it. Verify the line 582 "the test's program" paragraph no longer says compiler identity decides reuse. |
| `docs/tooling/native-build.md`, "The caches" (223) and "Shared compiler artifacts" (274) | E | Shared program key without `compiler_identity` (`core-shared-program-v2`); default store locations (`~/.cache/mylang/compiler-artifacts`, `$XDG_CACHE_HOME` first); a determinism mismatch is a miss, counted in `cache-report-v1` and logged to `<store>/mismatches.log`; an unusable default store warns, an explicit one errors; `--no-cache` and an empty variable disable. "Reports" (308): the mismatch counter field. |
| `docs/tooling/caches.md`, "Shared compiler artifacts" (139), "Native build cache" (448) | none (phase 2) | Same facts as native-build.md, stated once and linked rather than repeated; remove "opt-in" wording; v3 namespace names. |
| `docs/tooling/many-agents.md`, "Reuse verification evidence before admission" (133), "Per-worktree environment" (252) | C | The environment projection (keyed, host, placement, dropped classes; link `environment-identity.md`); `CODEX_THREAD_ID`, `TERM`, `PWD`, `TMPDIR` no longer change identities; sharing is the default for one user on one machine (D2); the shared evidence store default `~/.cache/mylang/verification-shared` and `--shared-cache-dir` override; one admission directory via `dev-env.sh` (matching the phase 1 `CLAUDE.md` text). |
| `docs/tooling/development-loop.md` | D | The measured C1 to C5 results from `cohorts.md` with their manifests, replacing any pre-plan figure; what still reruns after a compiler edit and why. |
| `docs/tooling/cache-retention.md`, "What can be shared" (22), "Native compiler artifacts" (50), "Native cache retention" (67) | D, E | v3 namespaces and their retention budgets; default store locations; the prune job's new directories (`scripts/prune-caches.sh`); the sweep no longer holds the exclusive lock across `open` (SHARED-STORE-5); `mismatches.log` retention. |
| `docs/tooling/environment-identity.md` | A (landed) | Verify: `build-env project` and `build-env digest` usage once Lane C lands the host tool; `MYLANG_ENV_PROJECTION=off` as the keyed diagnostic switch (plan Section 6). |
| `CLAUDE.md` "Caches and worktrees", "Fast loops", "Full gate" | F | After C1: replace "about 34 to 37 s" with the measured unchanged complete verification. After Lane B: "Results are reused per test (receipts keyed by the test's Core IR)" in Fast loops becomes "keyed by the test's Core IR, then by the linked program". After Lane E: the shared-store bullet ("Optional shared compiler artifacts ... v2 namespaces") becomes default-on v3. After Lane C: re-check the two `.zig-cache` sentences (Build and Caches) once test option paths are relative; the build-root realpath in `build_identity.zig` still pins the configure cache unless Lane C removes it. Lane C's own edit to "Test steps always run in the live environment" is not touched. |
| `SPEC.md` | coordinator | Bullets for every new tag: `EXEC-RECEIPT-1` to `-4`, `SHARED-PROGRAM-2`, `RECEIPT-PATHS-1` (B); `ENV-PROJECTION-1`, `TEST-PATHS-1` (C); `SHARED-STORE-3` to `-5` (E). `ENV-IDENTITY-1`, `ENV-IDENTITY-2` and `RUNNER-IDENTITY-1` already have bullets at `f6971a623`. Verify each bullet's test carries `// spec: TAG`. |

## Feature slugs (`src/features.json`, owner: coordinator)

Every slug is `kind: "tooling"`, so its `doc` anchor needs a section with a
runnable ```bash or ```console example (`mylang doc-coverage .` checks it).

Existing slugs whose summaries become wrong:

| Slug | Today | Change to |
| --- | --- | --- |
| `affected-native-test-result-reuse` | "reuses receipts for cases whose sources and compiler identity did not change" | sources unchanged, or the linked program and runner unchanged |
| `native-test-preparation-reuse` | "replays result receipts keyed by each test's Core IR" | the IR tier first, then the program-keyed tier |
| `shared-project-test-results` | "Opt-in native test storage ..." | on by default for one user on one machine; explicit empty value disables |
| `shared-compiler-artifacts` | "Opt-in native storage ..." | on by default; mismatch is a miss |
| `native-cache-retention` | v2 stores | v3 namespaces and default locations |

Slugs to add (names proposed; anchors are in the owning lane's document):

| Proposed slug | Summary | Doc anchor | Runnable example |
| --- | --- | --- | --- |
| `program-keyed-test-receipts` | A test whose linked program and runner are unchanged reuses its verdict after any compiler edit (`exec-receipt-hit`) | `docs/tooling/guest-tests.md#execution-receipts` | `mylang test tests/lang --json` piped to a `cache.reason` count |
| `test-execution-receipt-report` | `mylang test --json` reports `exec_receipts {hits, saves}` | same section | `mylang test app.my --json` showing the field |
| `fact-and-leak-test-receipts` | `--release --verify-facts` and `MYL_CORE_LEAKCHECK=1` runs reuse receipts keyed on their mode; neither hits the other's | `docs/tooling/guest-tests.md#fact-and-leak-runs` | two identical runs, the second `cached` |
| `build-env` | One host tool computes the environment digest and runs a command in the projected environment | `docs/tooling/environment-identity.md#build-env` | `build-env project -- env` |
| `shared-store-mismatch-counter` | A determinism mismatch in a shared store is a miss, counted in `cache-report-v1` and logged to `<store>/mismatches.log` | `docs/tooling/native-build.md#determinism-mismatches` | `mylang build app.my -o app --report` |
| `default-shared-stores` | The shared program, test and evidence stores are on by default under `~/.cache/mylang` (or `$XDG_CACHE_HOME`), with an empty variable or `--no-cache` disabling them | `docs/tooling/cache-retention.md#default-locations` | `MYLANG_TEST_SHARED_CACHE= mylang test app.my` |
| `path-free-test-identities` | Receipt keys and test binaries carry root-relative paths, so two worktrees at one commit share them | `docs/tooling/guest-tests.md#execution-receipts` | the row 11 two-root build compared with `sha256sum` |

## Integration-gate additions (D1, D3)

| Addition | Proposed owner | Notes |
| --- | --- | --- |
| One forced fact/leak run per integrated commit (D1): `MYL_CORE_LEAKCHECK=1 mylang test tests/lang --release --verify-facts --force`, and the same for `tests/value_semantics` | coordinator's integration script; documented in `docs/tooling/many-agents.md` (gate section) | Runs once per integrated commit, not per agent; its verdicts must equal the receipt-served ones (compare with matrix row 6). |
| Fail when the shared-store mismatch counter is non-zero over the window (D3) | `scripts/verify_cache.py` (a check over every store's `mismatches.log` since the last integration), with its test in `scripts/verify_cache_test.py`; documented in `docs/tooling/cache-retention.md` | `matrix.integration_mismatch_check` is the harness's stand-in; row 10 judges it. The production check needs a window definition (log offset or timestamp recorded at the previous integration). |
| Receipt shadow verification (plan Section 6) `MYLANG_TEST_VERIFY_RECEIPTS=1`, keyed | Lane B follow-up; `docs/tooling/guest-tests.md` | Not in any lane's deliverables; list as open if absent. |
| Row 4 as a standing test | `src/core/test_runner_test.zig` or a `test/core` fixture (Lane B) | A runner-source change must miss every execution receipt; keep beyond the qualification. |

## Matrix rows that need the merged tree

| Row | Needs | Feature probe |
| --- | --- | --- |
| 1 `lang-facts-leak`, 6 | Lane B, D1 | `fact_leak_receipts` |
| 2, 3, 4, 5 | Lane B execution receipts | `exec_receipts` (`exec_receipts_opt_in` sets `MYLANG_TEST_EXEC_RECEIPTS=1`) |
| 3 per-test program key | Lane B reporting `cache.program_key` (not in the plan; ask Lane B) | `program_key_report` |
| 7 coordinator | Lanes C, D (path-free identities, projection) | `coordinator_path_free` |
| 7 binaries, 11 | Lane C (`TEST-PATHS-1`), Lane B (root-relative emission) | none; judged directly |
| 8 `projection`, 12 | Lane C `build-env` | `build_env` |
| 10 | Lane E (D3) | `mismatch_counter` |
| 11 `program_key` | `cache-report-v1` exposing `program_key` (not in the plan; ask Lane B) | none; reported as not judged |
| 13 | Lanes B, D namespace bump (D4) | `test_v3_namespaces`, `coordinator_v3` |

Open questions for the coordinator: whether `cache-report-v1` or the test
report will expose `program_key` (rows 3 and 11 judge it only if present); the
mismatch counter's field name (row 10 searches for any key containing
`mismatch`); where the `build-env` binary is installed (row 8 and 12 search
`zig-out/bin`, `zig-out/tools`, `zig-out/libexec`, or take `--build-env`);
whether the shared-store record layout changes in Lane E (row 10's forger reads
the v2 header and refuses anything else).
