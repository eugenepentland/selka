# DeepSeek tool-cycle audit: mylang

Update: the managed-job preset and cycle guidance were applied after this audit. See [the deployment and validation record](preset-update.md) for activation and rollback. The measurements below describe the pre-update sessions.

The highest-value change is to give the active coding preset managed background commands with completion notifications, then use narrower verification during development. Ordinary tool dispatch is already relatively fast. The current persistent-shell preset encourages manual background jobs and sleep-based polling, and kills foreground commands at five minutes.

This audit inspected local session logs, the installed harness, the custom `minimal-delegation` preset, and the harness checkout. It added a reusable Python analyzer; it did not change running agents, presets, compiler behavior, or verification policy.

## Measured scope

The snapshot covers September 14–16, 2026, ending at 15:53:29 UTC on September 16: 92 sessions associated with `/home/epentland/ai/canopy/mylang`, including 18 root sessions, 72 children and two grandchildren. The analyzer counted 15,754 completed calls and skipped 1,293 inherited calls before `session/end-seed`. There were five unfinished calls, no unmatched results, and no JSON/decompression errors. Active logs continue to grow, so rerunning produces different totals.

To honor the request to ignore main-agent waits for subagents, the headline excludes **all** shell calls containing `sleep` in root sessions and in sessions with children, plus agent-status/wait tools and human-input tools. That conservative exclusion removes 20.47 call-hours, including some root-agent build polling. It is deliberately broader than confirmed subagent waiting. Remaining worker sleeps can still contain coordination; individual calls can be excluded with `--exclude-call SESSION:SEQ` after inspection.

| Included work | Calls | Observed call-hours |
|---|---:|---:|
| Worker shell sleeps/polls | 341 | 8.02 |
| Zig tests without a filter | 485 | 4.26 |
| Zig builds with a filter | 1,065 | 2.52 |
| Other Zig build commands | 490 | 1.49 |
| Scripts, compiler invocations, mixed commands | 2,576 | 3.23 |
| Reads/searches and mixed commands | 6,979 | 1.43 |
| Recursive grep | 1,411 | 0.45 |
| Job collection | 10 | 0.16 |
| Other tools and shell commands | 1,957 | 0.15 |

Included tool blocking totals **21.71 agent-hours**, after removing overlapping calls within each agent. The elapsed union across agents is **13.13 hours**, and the measured pre-tool/model phase totals **18.08 agent-hours**. These are different accounting views, not an additive project timeline. Pre-tool/model time includes request assembly, provider delay, retries and generation.

Only **615 calls lasting at least 30 seconds account for 83.8% of included tool time**. Conversely, 12,937 calls under one second account for just 31.8 minutes. Even eliminating every one of those short calls' execution times could recover at most that measured 31.8 minutes; avoiding unnecessary calls might also avoid model round trips, which this ceiling does not measure.

The complete measurements, source-file hashes, session coordinates, exclusions and caveats are in [metrics.json](metrics.json) and [measured-summary.md](measured-summary.md). Categories use command-text patterns, so mixed shell commands are not precise process profiles. No model reasoning, user-message bodies, API keys, or full tool outputs are copied into these artifacts.

## 1. Give long commands a managed job lifecycle

The active custom preset at `/home/epentland/.dsh/.agent-presets/minimal-delegation/agent.cordis.yml` mounts `dsh-tool-bash-persistent`. Its tool schema accepts only `command`, and both its terminal and persistent-shell settings specify `timeoutMs: 300000`. It also mounts `tool-jobs`, but that does not turn `command &` into a registered job. The persistent tool does not register shell processes with the job service.

The sampled logs show 14,092 included bash calls, a 131 ms median, and only six explicit managed background starts across the selected history. Only 895 bash calls advertised `run_in_background` at all. Most sessions therefore cannot follow the usual advice to set `run_in_background: true`; that argument is absent from their tool schema.

There are **23 persistent-shell timeouts after excluding coordinator sleeps**, consuming **116.2 agent-minutes**. Fourteen are in Zig build/test categories, two are worker sleep/poll calls, and seven are other commands. Their results have `isError: false` despite the timeout text. The installed implementation resets the shell after a timeout; its message does not establish that an OOM occurred. The 116.2 minutes are time spent in failed/unfinished attempts, not proof that all that time can be recovered.

Evidence examples:

| Session | Call seq | Observation |
|---|---:|---|
| `43a19335-e962-4423-9ab0-6255c6e2f95f` | 60280 | Full `test-units` redirected to a log; timeout/reset after 303.234 s |
| `e079b3b1-aa2a-449f-ac0d-dcfad985db7a` | 56235 | Full `test-units --summary all`; timeout/reset after 303.234 s |
| `70e7a805-5890-43f4-b2f8-aafb0889ac10` | 73752 | `sleep 300` before reading a completion file; timeout/reset after 303.177 s |
| `6d12c9ef-1282-4ab7-91ad-ef0970ad49f5` | 57449 | A managed bash job collected with a blocking wait; 390.130 s |

Recommended implementation: create a separately selectable development preset that exposes the ordinary `dsh-tool-bash` with its shell/job dependencies and `tool-jobs` completion delivery. Replace the persistent `bash` registration in that preset rather than registering two tools named `bash`. Its commands must supply `workdir` and their required environment because ordinary bash calls run in fresh shells. Preserve the deployment's existing permission and sandbox policy.

Launch long builds/tests with `run_in_background: true`, return a job id promptly, and let completion notifications bring the result to the agent. The installed `tool-jobs` already has completion injection and idle-agent wakeup code. Use `job_output` to collect a result when needed; calling it immediately with a long blocking wait still blocks the agent, as the 390-second example demonstrates. If dependent work is all that remains, waiting is appropriate and should end on process completion.

If persistent shell state is required, the alternative is a harness change: yield a command handle after a short foreground budget, continue the process under owned cancellation, and surface its completion through jobs. This requires lifecycle tests and is more work than composing the existing managed shell.

Raising the five-minute timeout alone would prevent some resets but would not reduce blocking. Reducing the existing 25 ms polling interval is a much smaller opportunity than changing how long commands are scheduled.

## 2. Replace worker sleep polling with completion events

The 341 included worker calls containing `sleep` consume 8.02 agent-hours; median call duration is 60.075 s and p95 is 240.084 s. Typical commands sleep and then read a build log or check a PID. Some also launch work, so the entire duration is not necessarily sleep.

This is the largest measured opportunity to free an agent to do independent work. It is **not eight hours of proven wasted elapsed time**: the background command may need most of that time, and the logs do not consistently record its actual completion timestamp. A useful outcome metric is the delay from process completion to the agent consuming the result, alongside completed development tasks per hour.

Do not replace minute-long sleeps with a stream of frequent model-driven polls. That trades blocking for extra model requests and context. Use one background launch, automatic completion, and one collection. Keep subagent waits separate from command waits in future telemetry.

## 3. Reduce the amount of verification per edit

Zig build/test-containing calls account for 8.27 included agent-hours. Of those, unfiltered tests account for 4.26 hours and 12 timeout attempts. The log contains repeated full `test-units` invocations and broad `zig build test` commands during ongoing development. Repeated command text alone does not establish that the work was unnecessary; source content may have changed.

Correction from the subsequent dependency audit: `zig build test-units -Dtest-filter=...` and `zig build test-cli -Dtest-filter=...` narrow test selection, but their `bounded()` helper also depends on the full install step. That step pulls in installed executables, runtime preparation and Guardian. The nearby comment and `CLAUDE.md` describe a narrower graph than the code actually builds; the initial audit incorrectly repeated that description. See [the follow-up findings](remaining-bottlenecks.md) for the exact dependency path and log evidence.

During an edit cycle, choose the relevant root and test filter, then broaden after the focused behavior passes. Run the required full gate on the final integrated source state. Preserve failures and required acceptance checks; this recommendation does not remove Guardian or relax completion criteria. Avoid rebuilding all installed artifacts when a focused test binary is sufficient, and run `zig build` when an installed compiler is needed after a source change.

For several agents, use a host-wide budget for heavyweight verification rather than allowing every worktree to run a full build with its own independent fan-out. Existing `max_rss` declarations coordinate steps inside a Zig build; they do not prove a global limit across all concurrently launched builds. The logs do not contain enough CPU/RSS measurements to quantify contention or select a safe global worker count.

Preserve caches across ordinary edit cycles. Use deliberately isolated caches for cold-cache experiments only. Cache deletion and replacement of `ZIG_GLOBAL_CACHE_DIR` appear in the logs, but no cache-hit telemetry supports a numerical savings claim.

## 4. Scope searches to source and documentation

Two avoidable examples are recursive grep over the repository or Guardian cache data:

| Session | Call seq | Observed duration |
|---|---:|---:|
| `session-fdec2a6c-51ab-4edd-bcee-0060ffdefb61` | 12128 | 303.562 s, timeout/reset |
| `a6f793cc-adbd-4f8d-b16d-ef2e0ddca673` | 3021 | 303.353 s, timeout/reset |

Their outputs include large Guardian finding records before clipping. Use `rg` with explicit paths such as `src`, `docs`, `SPEC.md`, and `CLAUDE.md`. Prefer `rg -l` when only filenames are needed and `rg --files` for discovery. Request a small relevant file slice next. Avoid scanning `.guardian/cache`, worktrees, generated evidence, and compiler caches unless they are the actual subject of the question.

Three comparable scoped queries on the current checkout took **5–12 ms** locally; their argv, repeated timings, byte counts and exit codes are retained in [search-benchmark.json](search-benchmark.json). These measurements have different search scope and machine state from the old log calls, so they are evidence that a cheap path exists, not a controlled speedup ratio. The broadest scoped query still returned 184 KB; file-only results or a narrower pattern would further reduce model context.

## 5. Preserve useful failure and timing information

The installed harness reports version `0.1.2-rc.1`; the local checkout reports `0.1.5-rc.1` at commit `2377c272a8`. Editing the checkout alone would not change the installed harness. The installed persistent-shell implementation at `~/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-tool-bash-persistent/lib/index.js` has the timeout/reset path at lines 281–290 and the command-only schema at lines 328–336. The checkout has newer explicit status markers, but retains the fundamental timeout/reset behavior. An upgrade needs validation against the custom preset; it is not established as a complete fix by this audit.

Capture process exit status independently of output trimming. Commands such as `zig build test-units | tail` can return the status of `tail`; use a managed process result, or `set -o pipefail`/`${PIPESTATUS[0]}` when a pipeline is needed. The logs contain both masked and explicitly preserved pipeline patterns. A successful tool transport result is not proof that tests passed.

For future telemetry, record command queued/start/end timestamps, exit reason, job id, result-delivery timestamp, and when the agent consumes completion. Record test target/filter, source identity, cache mode, and peak RSS where available. That separates actual build work, queue contention, timeout recovery and delayed result collection. Avoid capturing credentials or full process environments.

The custom preset has a complete fixed persona and suppresses additional runtime context. Therefore any new operating guidance must reach the actual preset prompt or explicit task input; merely adding generic host prompt guidance may not affect these sessions. Preserve the correct persona configuration field for the installed version.

## Suggested order and success criteria

1. Trial a development preset with managed background commands and completion notices. Verify foreground output, background survival, completion delivery, cancellation, working-directory/environment behavior and unchanged permission policy before adopting it broadly.
2. Add concise cycle guidance to that preset: focused tests while editing, full final acceptance, scoped `rg`, bounded output, no shell sleeps to monitor jobs, and independent work while a job runs.
3. Measure a comparable development window with this analyzer. Target zero persistent-shell build timeouts and zero worker sleep-poll loops. Track completion-to-consumption latency and task throughput before claiming a time saving.
4. Then profile the remaining slow test/compile targets and global resource contention. Batch independent reads to reduce unnecessary model round trips, while preserving execution order for dependent or mutating work.

## Run the analyzer

From the repository root:

```sh
python3 scripts/audit_deepseek_tools.py \
  --project /home/epentland/ai/canopy/mylang \
  --json-output /tmp/deepseek-tools.json \
  --markdown-output /tmp/deepseek-tools.md
```

The default log root is `~/.dsh/sessions`. `--logs PATH` can select a copied log collection or a single project's session directory. Exact session-header cwd matches and their recorded descendants are included. The analyzer supports the event structure observed in these version-0 logs; it does not claim validation of every released session format.

Command text is omitted by default. `--include-command-text` adds original shell commands to selected JSON evidence rows and should be used only with a private output path. `--exclude-call SESSION:SEQ` can be repeated for additional verified coordination waits. Reports do not execute any command found in a log, use an API, or change source logs.

Each file is copied to a fixed-size temporary snapshot and hashed before streaming JSONL decoding. Concatenated Zstandard frames are supported through the `zstd` executable; plain `session.jsonl` requires only Python's standard library. Incomplete frames/JSON and unpaired calls are reported. Duplicate session ids are rejected to avoid counting multiple stored generations as independent sessions.

Validation: 13 focused Python tests passed, covering concurrent interval accounting, session-local call ids, inherited history, coordinator exclusions, explicit overrides, privacy, schema differences, truncated JSON, and concatenated/truncated Zstandard frames. An independent pass verified all 92 saved source hashes and reproduced the completed, inherited and unfinished call counts; [validation.json](validation.json) records those checks. The analyzer also completed against the real logs. Three bounded source-search benchmarks ran. No build or Guardian gate was exercised, so no Guardian feedback entry was required.

```sh
python3 -m unittest discover -s tests -p 'test_deepseek_tool_audit.py' -v
```
