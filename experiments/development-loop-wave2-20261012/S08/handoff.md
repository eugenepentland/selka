# S08 canonical actual-loaded-code identity handoff

Base: c1857310e0bf623545380c8de24515f1b9970021. Owned source commits: b44a9241f210a3f33671d985eec9862cb1c28193 (canonical helper and tests), f2976df51180b1177558fffd30c89643a67cdc9f (pure source authentication and tests). Both normal commit hooks passed 88 Guardian tests; raw logs are retained here. No native build or full verification gate was run by S08.

The helper hashes the actual immutable module code object, with format version 1, explicit Python compatibility, all 18 semantically relevant code attributes including filenames and locations, tagged exact-type constants, float bits, nested code, sorted frozensets and slices. Unsupported values and resource bounds reject. The helper authenticates its own loaded closure. Source authentication compares bounded watched bytes compiled under the captured filename and optimization mode against the actual captured code; it does not replace loaded identity with current-source hashing.

Validation: helper-tests.log records 24 passing tests covering loader/reference/hashseed stability, semantic mutations, typed constants, stale pyc, source-after-import, detached helper code, unsupported constants and bounds. caller-auth-tests.log records 7 passing exact-patch regressions. The coordinator separately ported these into the actual production caller and reported all 7 passing; that integrated test result is coordinator evidence, not a claim that this private patch-text fixture tested its final tree.

startup_identity_probe.py copies the actual B0 Python scripts into private trees and executes real verify_cache.py --help and cache_session.py verify --help then stop. An observational trace records already-assigned identities; RuntimeGuard startup and request validation remain active. startup-identity.json shows before: verify_cache identity differs between one-shot and retained loading while five peer identities agree; after private canonical consumer migration: all six identities and the helper identity agree. Both routes exit 0. This reproduces a production startup identity discrepancy without native builds or receipt execution. It does not uniquely identify the reference contributors in the historical frozen run or qualify complete cache reuse, latency, RSS or p95 performance.

The coordinator owns uniform consumer imports, explicit helper format/hash binding, verification receipt version 2 and action domain v5, report schema version 1, fuzz action domain v2 and Juice measurement domain v2. Independent-seed-shards-v1 and seed derivation remain unchanged. RuntimeGuard authenticates the helper before its own canonical comparisons. Package-mode verification_process imports require the coordinator's relative-import fix.

caller_auth_function.py.txt is the exact bounded caller proposal integrated by the coordinator at verification prepare, fuzz common capture, Juice common capture and Juice comparison runtime capture. The helper is declared in each source closure. Matching immutable watched records supply exact SHA256 and size; missing/mismatched records reject. A fallback watch for the actual helper provider path stays in the request stack and snapshot validation list, including fake-root fixtures. Source bytes are read only between watch checks and compared against that record. Cached proof is keyed by code object identity (`is`) and watched content digest; it proves content equivalence only and cannot authorize dirty or closed snapshots. All existing request, lookup, admission, execution and publication guards remain required.

Open integrated qualification: the coordinator/S10 must complete final frozen-source suites and real forced/warm and one-shot/retained receipt coverage checks. No source API changes are pending from S08. Cross-worktree filename differences remain conservatively distinct by design.

Reproduction commands (after sourcing /home/epentland/.config/mylang/dev-env.sh, private TMPDIR):

    python3 scripts/verification_code_identity_test.py -v
    python3 experiments/development-loop-wave2-20261012/S08/caller_auth_regression.py
    python3 experiments/development-loop-wave2-20261012/S08/startup_identity_probe.py

All three commands exited 0. The startup probe modifies only its own temporary copies. No peer worktree or frozen source was edited.
