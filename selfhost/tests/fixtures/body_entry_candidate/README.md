# B7 capability/resource candidate corpus

This separate proposal contains 24 cases: 14 successful closed-surface controls,
8 exact source diagnostics and 2 native-valid profile candidates (file.write and
text readline). It does not change the B6 manifest or claim schema7 support.
`proposal.json` pins source hashes, diagnostics including ordered notes/repair
bytes, and exact runtime output. `helper.my` is the imported capability donor.

All 24 native project checks match their expected status. All 16 native-valid
cases compile with `--release --verify-facts` and run with
`MYL_CORE_LEAKCHECK=1`, returning7 with exact captured outputs and no leak report.
Native host SHA and control counts are in the proposal. Thirty-two standalone
native typed/IR views are nonempty and successful; these are inspection artifacts,
not full wire-batch comparison or selected-body qualification.

The six repeated-scope programs apply RLIMIT_NOFILE32 only to their generated
binaries, preserving any stricter inherited limit. Each executes128 opens/exits:
normal scope exit with a bytes snapshot, helper early return, caught checked
failure, break, continue and nested return. Successful subsequent opens prove no
descriptor accumulation on those routes. Empty pre-global-cleanup runtime handle
leak reports independently prove no tracked handles at exit. Neither observation
establishes runtime reverse close ordering. Native Core IR retains explicit
file-scope close calls; runtime traps intentionally omit leak checks and are not
counted as affirmative cleanup evidence.

Private raw command/host/source receipts are retained in
`.tmp/b7-entry-proposal/native/{checks,runtime,typed-ir}.json`, with per-case typed
and IR text alongside. Admissions1849/1852/1855/1856 cover checks, generated
controls and corrected views. Two failed exploratory command recipes are retained
separately: unsupported build-project (no guest executed), and dump-typed extra
arguments interpreted as a function filter (empty output rejected). Final native
controls use build --project and plain dump-typed/dump-ir.

`entry_inventory.json` identifies all seven real entrypoints and their complete
import closures by source hash. Actual entry admission is still pending: require
all transitive imports, full reference/component/shadow typed/catalog equality,
then generated normal and release/facts/leaks exchange checks for valid requests,
malformed requests, usage and missing files. Nine selected helper libraries or
six test roots are a separate prerequisite, not entrypoint/bootstrap proof.
Native catalog, entry adaptation, effects/origins/warnings and backend remain
retained seams. These fixtures make no full-language or performance claim.
