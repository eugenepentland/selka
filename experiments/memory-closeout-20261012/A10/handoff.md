# A10 command-support handoff (later milestones pending)

Base C0: fbfcaa7a923186a8e773c3760f81c10aa345a432.
Worker branch: codex/memory-closeout-20261012-A10.
Proposed command-support commit: this changeset; packaging/default/retirement remain separate.

Owns the assigned core CLI/test runner files, ownership docs, src/main.zig by
coordinator reservation, and these A10 fixtures/reports. Pipeline.zig reserved
for a later default stage but no default change has been applied.

Implemented guest-test selection through parser, directory children, eager source
validation, every reachable-root/key/cached/shadow lowering, and three receipt
domains. Three registered focused tests pass (3/3). A08 reviewed the deferred
canonical-fact path: full source validation remains eager, facts bind raw source
and both ownership bits, execution lowers independently. Keeping deferred fact
reuse does not skip source ownership checking.

Implemented opt-in ownership checking through the full frontend check parser,
including library sources, diagnostic/report options, disabling ordinary green
source-receipt replay and summary-only body omission. Developer --typed/--stats
still routes to the dedicated profiling check implementation.

Evidence:

- inventory.md: current source command and packaging matrix.
- C0-components.json: both installed component source entries refuse C0 zeroRC
  at with-try file acquisition; A07 owns checker fix and A08 module migrations.
- C0-package-symbols.json: both frozen installed components contain retain/release
  and sharing symbols; they are active RC-installed artifacts, not historical seeds.
- command_matrix.py and fixtures/: five guest modes, property copies, cached and
  child directory execution, Result entries, run-project and move/library refusals.
- admission_survey.py: preserves original identities across all 356 current .my
  files in tests/lang and tests/value_semantics; a private mirror adds the guest
  runner's inert main to 201 library entries for the C0-style check parser.
- migration.md: accurate opt-in migration notes; no default/retirement claim.

Commands run:

- pinned Zig build affected-compiler via common admission: pass before and after
  test mode plumbing; outputs zig-out/focus/mylang with libexec siblings.
- pinned Zig build test-core with filters 'zero RC guest test', 'zero RC test
  receipts', 'zero RC directory children': exit 0, Guardian test PASS 3/3.
- C0 check of both component main files through common admission: source refusal
  status 1 for both; exact output and C0 compiler hash recorded.
- Initial matrix/survey launch used wrong zig-out/bin path; did not execute guests,
  corrected to zig-out/focus and requeued. No passing claim from that harness error.

Shared requests: coordinator authored NEW-CORE-ZERO-RC-TEST-1 in SPEC.md here;
include with command-support commit. Final root verification and integrated
A07 helper/checker fixes remain coordinator-owned. No Guardian FEEDBACK write.

Milestone 2 default promotion and milestone 3 legacy retirement are intentionally
unapplied until coordinator qualification approval. Package recipe needs a
separately keyed qualified zeroRC final component build without changing immutable
seed history or creating a host/component bootstrap dependency cycle.

Command support qualification (worker candidate, C0 plus this command changeset):

- `test-support-matrix-qualified.json`: all 23 command rows pass, including
  the five guest modes, shadow/reference keys, warm receipt reuse (3/3 cached),
  library diagnostics, invalid moves after ordinary RC receipts, and both
  in-process and spawned-child directory execution. Compiler SHA256:
  `d0766f6dad145b76c1bec5cb700ee2d29da6937dbd66f84010ab3d774056539e`.
- Earlier matrix reports retain harness mistakes explicitly: an empty leakcheck
  variable still requests instrumentation; cache tests require the string `0`.
  Old generated directory fixtures used a retired module header. Both harness
  errors were corrected; no production cache/directory change was needed.
- `guest-admission.json`: all 356 current guest files are retained; 179 admit,
  177 refuse. Source admission only, not guest execution. Sorted refused lists
  and `guest-migration-ledger.json` identify 123 explicit-copy local migrations,
  19 evaluation-order reviews, 33 production/lifetime reviews and 2 explicit
  boundaries. Classification records the first refusal; subsequent defects can
  still surface. Parent assigned migrations to their source owners.
- Required full integration verification remains the coordinator's gate. These
  focused passes are command-stage evidence, not milestone 1 qualification.

Support commit: `8d4a9845f`, required Guardian 88/88 passed. Post-refactor
repeat focused tests pass 3/3; all 23 command rows pass in
`test-support-matrix-refactor.json`, compiler SHA256
`8a4f53e6202bd25c44f0b7a65851b281188a6921630b5862ec6aaa6725e798f9`.
`test-support-assertion-audit.json` additionally checks exact test counts, no
unsupported tests, exact move diagnostics and run output against that raw report.

Separately prepared the optional independent owned-component compiler route,
including immutable-pin validation, mode-bound cache identity, explicit guest
selection and native qualification-driver forwarding. See
`packaging-preparation.md`/`.json`. Fake-tool orchestration tests pass 21/21.
No production new manifest exists and root builds still select the historical
route, so this is packaging preparation, not installed RC retirement.

Doctest/session followup: `check-session` accepts the ownership flags and keeps
eager checks on repeated, cleared and failed requests. `doctest` accepts zero-RC
and passes it into each check/run invocation. `followup-matrix.json` records all
six rows passing: module/project checks, positive and negative five-request
sessions, and repeated doctest runs with positive execution, library checking and
expected move refusal. Focused `zero RC doctest` unit selection passed 8/8
(one named regression and seven existing unnamed import blocks). The original
focus installation was preserved for A04; this candidate uses a private prefix.
