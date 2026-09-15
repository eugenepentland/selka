# Incremental compilation and testing: verified status

Verified 2026-09-15 against the current installed compiler, pinned for the
experiments. The checkout was `89198ff` with the named-constraint fixes and
concurrent incremental work uncommitted. Executable and compiler identities,
commands, source fixtures and results are in
[the evidence](incremental-status-2026-09-15-probes.json).

## Conclusion

The tested cache paths preserve correctness and selective test execution works.
Compilation reuse remains conservative, especially for programs using generics
and named constraints. This is useful incremental tooling, but it does not yet
meet a goal of recompiling only the affected generic implementation after edits.

## Observed behavior

| Experiment | Result |
| --- | --- |
| Cold two-module check | Two modules parsed |
| Unchanged one-shot check | Successful verdict reused |
| Helper body edit | Verdict invalidated; one parse reused and one refreshed |
| Invalid helper edit | Rejected; previous successful verdict not reused |
| Two deterministic tests, first run | Both executed and passed |
| Same tests, unchanged rerun | Both results reused |
| Change a helper used by one test | One test rerun, one result reused |
| Change an unused helper | Both test results reused |
| Force the test run | Both tests executed |
| Invalid source before a test rerun | Setup rejected instead of reporting cached success |
| Ordinary private-body edit within `check-session` | One body checked, four reused |
| Same edit in a program containing a named generic | Zero bodies reused; five ordinary bodies checked, generic checking remained fresh |
| Old compiler's cached success, then current compiler with the same cache | Current compiler missed the old verdict and correctly rejected the formerly accepted invalid program |

The targeted suites also passed: **26 invalidation tests and 43 native-test
tests**, including the clean-versus-warm equivalence matrix. The build-wired
Guardian gate passed all 88 checks.

## Remaining limits

1. **Body reuse across edits is in-process.** Ordinary one-shot checks persist
   syntax and successful whole-project verdicts, not checked function bodies.
   After an edit, they check bodies again. `check-session` retains an ordinary
   function-body cache across requests.
2. **Generics disable the existing body-cache path.**
   [semantic_key.prepare](../../src/semantic_key.zig#L18) disables that path when
   generic functions or other unsupported syntax are present. Specialization
   keys exist, but the specialization reuse engine is explicitly deferred.
3. **Test execution reuse does not skip project checking.** The test runner
   checks and lowers the project before consulting individual result receipts.
   A fake-only entry can exclude an unfinished production module; a selected
   test still requires its loaded project to be valid.
4. **The explanation's hits are not reliable execution counters.** An unchanged
   `check-project --explain-invalidation --report` reported six hits, including
   `check_body`, even though this one-shot path supplies no body cache and
   bypasses verdict replay to construct a fresh receipt. The report compares
   fingerprints. Its new `skipped` status correctly excludes lowering, emission
   and linking for a check-only command, but matching executed-stage fingerprints
   still do not establish that work was reused. Use actual syntax/verdict counts,
   session `functions` counters and test `passed`/`cached` results for that.

The earlier rebuild-cache warning was not reproduced in the cross-version
experiment. That is evidence for the tested compiler-identity transition, not
proof that every rebuild/install workflow refreshes the executable correctly.

For faster parallel agent work, the main remaining compiler optimization is
reuse of checked generic bodies and their specializations. Accurate stage
execution counters should accompany it so improvements can be measured.
