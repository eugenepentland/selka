# Scored participant runtime boundary

Status: implementation design, not evidence of a launched isolated agent.

The installed `codex exec --help` exposes read-only/workspace-write shell sandboxes,
JSON events, ephemeral sessions, user-config/rule suppression and model selection.
Those options alone do not prove that every enabled tool is restricted to the
participant mount. Do not label ordinary coordinator subagents as isolated scored
sessions. Current independent baseline builders are unscored construction work.

For the initial scored runtime, implement an explicit model tool loop whose only
application-side dispatch targets are the coordinator's participant gateway.
OpenAI function calling returns proposed calls to application code, which executes
them and supplies results; the caller supplies tool definitions. Preserve reasoning
items together with outputs in subsequent model requests as documented in the
[official function-calling guide](https://developers.openai.com/api/docs/guides/function-calling).
This supplies a practical way to restrict the dispatch surface; it does not by
itself provide OS isolation. The namespace runner remains the enforcement layer.

Gateway requirements:

- Only named participant operations: run command, public check, phase completion.
  No arbitrary coordinator file paths, tool mounts, adapters, expected answers,
  grader files, private session configuration, or arbitrary Python dispatch.
- The gateway chooses practice/work mounts from trusted session phase. Model
  arguments cannot choose a cwd outside that mount or expose the other phase.
  All shell/file/editor/search operations execute inside the existing namespace
  runner with reviewed tools mounted read-only.
- Enforce the remaining phase deadline before each request/tool invocation and
  bound child execution by it. Preserve command output/timing and failed attempts.
  Never treat a late response or a check finishing after budget as on-time success.
- Public checks use coordinator-owned adapters/cases and captured source identities;
  hidden grading remains unavailable until all three sessions are sealed.
- Fresh model context for each participant; retain that participant's practice
  history into its scored task. Freeze prompt, model/settings, docs, tool inventory,
  and context policy across a matched cohort. No reuse of another attempt's history.
- Persist every model request/response, tool call/result and reported usage outside
  participant mounts. Unknown usage/cost is missing evidence, not zero.
- Use only declared custom function tools. Reject unknown tools/call schemas and
  duplicate call IDs; do not enable hosted shell, connectors, web search or a
  second path to filesystem access. Keep API credentials solely with coordinator.
- A fake model transcript may test routing, deadlines and escape attempts but must
  stay a fixture. A live model smoke test is separately labeled unscored calibration.

`participant_gateway.py` now implements the command dispatch foundation, including
trusted phase mounts, deadline checks, immutable tool checks and private records.
Its fixture tests execute real isolated commands in both phases. Public-check and
completion dispatch are now implemented: check adapters/cases stay coordinator-owned,
submissions are immutable, each check phase is bounded by remaining task time, and
late completion seals as budget exhaustion. Main Zig public-check adapters require
a Guardian phase; actual policy/binary enforcement still needs cohort review.
Gateway configuration is pinned across restarts.

`model_loop.py` now runs an explicit function-tool loop against that gateway. It
retains practice history supplied by the coordinator, reasoning items (requesting
encrypted reasoning content for stateless continuation), requests/responses, tool
outputs, model configuration and reported usage. Unknown usage stays marked
incomplete. Late responses cannot dispatch tools; duplicate calls, parallel calls,
unknown tools and changed model identity reject. Unfinished model runs cannot be
silently overwritten. Non-tool final replies do not count as completed patches.

`responses_transport.py` and its fixed HTTP worker implement bounded Responses API
transport without an SDK dependency. The worker receives credentials only from the
coordinator, uses HTTPS to the official API endpoint, rejects redirects, bounds
request/response bytes, and is killed on deadline or coordinator death. A fixture
credential may access a loopback HTTP server for tests; real credentials cannot.
Fixture model responses have driven actual isolated checks/completion, and a local
HTTP server has exercised transport success, malformed replies, redirects and
request timeouts. This is not proof of live API compatibility or model access.

`preparation_gateway.py` now verifies practice against a separately pinned adapter
and public case. Checks snapshot only `practice/`, enforce its remaining deadline,
and retain results outside participant mounts. Completion requires the latest
passing source snapshot; unchecked edits reject. Abandonment or timeout records
failed/budget practice and still transitions to the task. Practice code is not
copied into the task baseline.

`model_loop.run_preparation` uses the same explicit function-tool transport as the
task phase, with separate requests, transcripts and usage records. Fixture tests
run practice and task checks in real isolation, preserve practice history when
starting the task loop, and verify that task source appears only after preparation
ends. Model/tool exceptions retain unfinished records for explicit recovery.
This is simulated-model acceptance, not live calibration.

`session_driver.run_fixture` now captures a supplied curriculum and runs preparation
and task model loops in sequence, carrying the practice transcript forward and
retaining per-phase/combined usage. Interrupted phases preserve their records and
cannot be silently restarted. It accepts only fresh fixture sessions. A full
simulated session and preparation-transport interruption pass isolated tests.

Persistent phase cache policy, reviewed frozen practice curricula, cohort-to-driver binding, live access
preflight, cohort launch receipts, token-budget policy and analysis still need
work. `OPENAI_API_KEY` is not configured in the inspected environment and no live
model call has been made. The user has been asked to configure credentials locally
and identify the model/project; do not paste credentials into trial records. The
exact model and common budgets remain unset in `study-plan.json`; do not launch
scored sessions yet.

Public verification now accepts complete named packs in both phases. All cases
run against one captured source with the shared remaining phase deadline; later
cases are explicitly marked unrun/failing after expiration. Individual execution
records stay private, with bounded diagnostics and per-case outcomes exposed by
the gateway. Single-case callers remain supported. Simulated full-session tests
exercise two-case preparation and task packs.
