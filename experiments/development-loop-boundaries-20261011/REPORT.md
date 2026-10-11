# Development-loop boundaries and advisory budgets qualification

Qualified source: `66043848d2aa279956df09d441a41324d8f1d1af`, including main
`9225adeb06cca3ab19a0f4437ec2065fbea34e2e`. Pinned Zig:
`0.17.0-dev.1683+5ceec001b`. Three Sol 6.1 agents implemented and reviewed the
independent tooling boundary, local action contracts, and advisory calibration.

## Changes

- The pure native tooling root contains 27 named tests plus its import-root test.
  Its 11-file source closure and independent binary avoid compiler/component
  artifacts. Unfiltered unit targets and the complete gate retain coverage;
  focused tooling filters reject a no-match result. The source parity and edit
  matrix are recorded in `docs/audits/selka-dl3-pure-native-evidence-2026-10-11.json`.
- Inventory v2 identifies every registered member with a unique summary label.
  Receipt keys bind each group's membership and recipes independently of global
  inventory growth. A reviewed configuration fingerprint permits projection of
  declarative input lists; changed executable build wiring or unfamiliar list
  syntax restores broad invalidation. Whole-gate discovery and coverage remain
  mandatory. See `docs/audits/selka-dl3-group-contracts-2026-10-11.md`.
- Reports capture named member timings, compatible action identities, and
  bounded advisory calibration. Failed, unstable, reused, ambiguous or incomplete
  observations cannot supply fresh samples. Calibration cannot change gate
  verdicts or authorize receipts. No hard action deadlines were introduced.

The configuration qualification still matched
`7cefed8043b05279aa8960b33ea742e728f91dfc294d08c6e48d7b4a0a8fd6fc`
after the final integration fixes.

## Complete verification and unchanged requests

`qualify_session.py` submitted one first request and four unchanged requests to
one retained session, followed by a clean stop. All five passed with stable
inputs. The complete inventory contains 45 groups and accounts for all 94
required members, with no unknown members. The first request passed **134/134
steps and 2,860 Zig tests**; the reported 25,311 skips are shard exclusions.
The complete verification includes `test` and `fmt-check`. Guardian passed all
88 checks. Each unchanged request passed 44/44 steps.

| Request | Groups reused / selected | Files hashed | Directories enumerated | Gate held | Request elapsed |
| --- | ---: | ---: | ---: | ---: | ---: |
| First (`cold`) | 0 / 45 | 28,801 | 2,283 | 621.478s | 633.517s |
| `warm` | 34 / 11 | 0 | 0 | 36.664s | 42.963s |
| `warm-2` | 34 / 11 | 0 | 0 | 31.649s | 35.601s |
| `warm-3` | 34 / 11 | 0 | 0 | 27.789s | 31.685s |
| `warm-4` | 34 / 11 | 0 | 0 | 30.990s | 34.488s |

The first request starts a fresh session with no reusable action receipts for
these inputs. Prepared binaries, Zig caches and native artifact caches were
retained, so it is not a cold compiler build. None of these five requests needed
a build admission. Each gate queue wait was below 0.5 seconds. Every unchanged
request reused the tooling-unit result and six retained input snapshots, and
made 175,677 metadata observations. It hashed zero bytes. The 11 fresh groups
still perform their required discovery, Guardian, language and other checks.

These are operational shared-server observations. They establish eliminated
snapshot work and qualified reuse, without establishing an isolated speedup,
p95 target, aggregate CPU use or aggregate memory use.

## Calibration

The saved CLI calibration accepted 176 distinct compatible member observations:
21 members have five samples and receive `report_only_candidate` suggestions;
71 have one sample and remain `insufficient_samples`; two remain `unknown`.
All five reports have the same budget context. The unknown members are the
identity-qualification and Zig-format members, for which no eligible timed
execution was captured.

The 37 recorded rejections cover five complete stdout captures without a Zig
summary and 32 unmapped, ambiguous or reused observations. Summary-bearing stderr
captures were complete, untruncated and not malformed. No missing time was
invented. Recommendations use the observed median and 1.5 times the observed
maximum for review; every recommended hard deadline remains null. Five samples
provide no percentile or confidence claim. Nested step durations can overlap and
cannot establish a complete action duration by addition.

`budget-calibration.json`, the five `verification-*.json` files, the inventory,
raw session log, and `qualification-summary.json` contain the machine-readable
evidence. `session-summary.json` records protocol success and snapshot work.

## Earlier attempts and remaining limits

The first attempt found two omissions introduced with main's `parallel` module:
its standard-library documentation section and its embedded reference inventory
entry. Commits `1c23870e3` and `66043848d` fix those omissions. The existing coverage,
reference and executable documentation checks pass in the qualified run.

The next attempt passed every test and formatting step, but final input stability
failed. The coordinator returned 75 and retained no new receipts. Its exact
historical cause was not captured; matching final bytes alone cannot disprove a
transient watched event. Both attempts are preserved under `attempts/` and are
excluded from calibration. A separate read-only observer recorded no relevant
input events throughout the successful retry and unchanged requests. Its source
and log are included as diagnostic evidence; the coordinator's own stability
checks remained authoritative throughout.

Compiler/Core edits can now preserve the pure tooling result. Compiler/native
roots and artifact producers still have broad dependencies; lifetime or runtime
changes may still invalidate substantial work. A tooling-test edit can also
invalidate the broad native unit fixture recipe. Further dependency separation,
producer identities, calibrated enforcement, and DL4–DL8 remain outstanding.
The five-second edit-loop and self-hosted compiler performance targets have not
been qualified by this pass.
