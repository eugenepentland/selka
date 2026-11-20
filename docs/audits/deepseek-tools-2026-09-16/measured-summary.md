# DeepSeek tool latency audit

Project: `/home/epentland/ai/canopy/mylang`

Observed 92 sessions and 15,754 completed calls, 2026-09-14T02:44:50.757000+00:00 to 2026-09-16T15:53:29.452000+00:00.

Included tool time: **21.71 agent-hours** (overlaps removed within each agent). Excluded coordination/human waits: **20.47 call-hours**.

Elapsed union with at least one included tool outstanding: 13.13 hours. Pre-tool/model phase: 18.08 agent-hours.

Categories are command-text hints. Durations are observed blocking, not promised savings.

| Category | Calls | Call-hours | Median ms | p95 ms |
|---|---:|---:|---:|---:|
| coordinator_sleep (excluded) | 385 | 20.398 | 240061.0 | 290121.0 |
| worker_sleep_or_poll | 341 | 8.022 | 60075.0 | 240084.0 |
| zig_test_unfiltered | 485 | 4.255 | 1561.0 | 240349.0 |
| scripts_compiler_or_mixed | 2,576 | 3.225 | 143.0 | 15430.0 |
| zig_build_filtered | 1,065 | 2.523 | 3363.0 | 38105.0 |
| zig_build_other | 490 | 1.490 | 1065.0 | 93602.0 |
| read_search_or_mixed | 6,979 | 1.432 | 118.0 | 494.0 |
| recursive_grep | 1,411 | 0.447 | 125.0 | 340.0 |
| job_collection | 10 | 0.158 | 7.5 | 390130.0 |
| other_shell | 208 | 0.080 | 124.0 | 9641.0 |
| agent_wait (excluded) | 55 | 0.070 | 68.0 | 652.0 |
| git_or_mixed | 396 | 0.032 | 144.0 | 644.0 |
| other_tools | 1,212 | 0.024 | 14.0 | 263.0 |
| guardian_command | 141 | 0.016 | 413.0 | 807.0 |

## Signals

- Included persistent-shell timeouts: 23; 116.2 minutes spent in those calls.
- Calls under one second: 12,937; 31.8 total minutes.
- Calls at least 30 seconds: 615; 18.19 call-hours.
- Explicit managed background starts: 6; bash calls with background support advertised: 895.
- Bash calls supplying timeout/background/workdir arguments absent from their command-only schema: 0.
- Unfinished calls: 5; unmatched results: 0; sessions with parse/decode issues: 0.

## Slowest included calls

| Seconds | Category | Session | Call seq |
|---:|---|---|---:|
| 390.130 | job_collection | `6d12c9ef-1282-4ab7-91ad-ef0970ad49f5` | 57449 |
| 303.562 | recursive_grep | `session-fdec2a6c-51ab-4edd-bcee-0060ffdefb61` | 12128 |
| 303.493 | zig_test_unfiltered | `9db72cf9-a4c6-49a2-acab-cae075eefc36` | 109500 |
| 303.353 | recursive_grep | `a6f793cc-adbd-4f8d-b16d-ef2e0ddca673` | 3021 |
| 303.234 | zig_test_unfiltered | `43a19335-e962-4423-9ab0-6255c6e2f95f` | 60280 |
| 303.234 | zig_test_unfiltered | `e079b3b1-aa2a-449f-ac0d-dcfad985db7a` | 56235 |
| 303.220 | zig_test_unfiltered | `462b5d4e-5a6a-45a6-8051-10c9d94492f4` | 111231 |
| 303.216 | zig_test_unfiltered | `0ad17631-be4e-4fac-9fff-a846c15d3389` | 65993 |
| 303.185 | scripts_compiler_or_mixed | `93c0328f-07e8-4f27-844e-f12960ec0f25` | 15836 |
| 303.177 | worker_sleep_or_poll | `70e7a805-5890-43f4-b2f8-aafb0889ac10` | 73752 |
| 303.176 | zig_test_unfiltered | `9e53632a-1e8d-4552-b28d-90f8d942d736` | 75966 |
| 303.171 | read_search_or_mixed | `e7f7cd63-e75c-4185-806b-6d2e65fc62a5` | 81365 |
| 303.165 | zig_test_unfiltered | `be4048b7-4f11-4068-90b6-b968d885bee5` | 176264 |
| 303.162 | zig_test_unfiltered | `session-043a9a11-7757-44fe-86cb-ad5f8bb15ffd` | 57886 |
| 303.159 | zig_test_unfiltered | `session-f0dc790a-c137-467c-8054-7bc0d5a6a5fc` | 259495 |

## Interpretation limits

- Call/result wall time includes queueing, policy, process work and persistence; CPU time is unavailable.
- Summed call seconds are agent-time, not project elapsed time or guaranteed savings. Per-agent and global interval unions are separate.
- All root/parent-agent shell calls containing sleep are conservatively excluded, including some build polls. Agent control waits and human input are also excluded.
- Worker sleep/poll time overlaps real background work; completion timestamps are needed to measure avoidable detection delay.
- Command categories are regex hints over whole commands and may include quoted code or mixed actions. Repeated commands do not establish redundant work.
- Pre-tool phase is step/start to assistant/message, including request assembly, provider delay, retries and generation; it is not pure inference time.
- Only completed calls are timed. Live tails, unfinished calls, unmatched results and decode issues are reported per session.
- Logs are per-file snapshots, not one atomic snapshot across sessions. Source hashes identify the bytes read; no log content is modified.
- Failure/truncation markers are textual signals; shell pipelines may mask exit codes and old logs often omit explicit status.
