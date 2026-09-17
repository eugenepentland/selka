# Applied minimal-delegation update

Applied on September 16, 2026 at 16:07:59 UTC to the locally installed DeepSeek Harness `0.1.2-rc.1`.

The active files are [agent.cordis.yml](/home/epentland/.dsh/.agent-presets/minimal-delegation/agent.cordis.yml) and [preset.yml](/home/epentland/.dsh/.agent-presets/minimal-delegation/preset.yml). The preset id and display name remain `minimal-delegation` / `Minimal + subagents`.

## Behavior

- The persistent-shell stack is replaced by the installed managed `bash`/`pwsh` tools, using the host's existing shell, sandbox, approval and job services.
- Long commands can return a job id immediately with `run_in_background: true`. Job completion injects a notice into a busy agent or wakes an idle one within the existing wake budget. `job_output`, `job_list` and `job_kill` manage those processes.
- The fixed persona now teaches the model to background commands expected to take more than roughly ten seconds, work independently while they run, collect required results, and use completion-aware waits when dependent work remains. It discourages shell sleep polling.
- Guidance covers focused mylang tests during edits, required full acceptance and Guardian checks at completion, cache reuse, scoped `rg`, bounded output and preserving pipeline exit status.
- The editor, continuable subagent tools and model-selection support are retained. Global permission settings, model routes, compiler code and verification policy were not changed.

**Shell state no longer persists between calls.** The prompt and tool schema tell the model to supply `workdir` and required environment variables for each call. This matters especially when working in several worktrees.

## Activation

Start a **new session using minimal-delegation**. The installed preset loader detects changes when creating the next composition generation. Existing agents keep their already-mounted generation, and their children inherit that same generation. A new child of an old session therefore does not pick up the change by itself. No server restart is required for new sessions.

## Verification

The exact candidate was loaded through a separate `dsh --profile preset-smoke` process using the installed packages, an isolated DSH home, the real shell/job implementations and a local synthetic model adapter. No external model calls or compiler/Guardian gates were run.

Nine checks passed:

1. The actual preset mounts with exactly one managed bash tool and the existing editor/delegation tools.
2. Its assembled prompt includes background execution, focused verification and the session workspace.
3. Relative workdirs, managed session environment, fresh-shell behavior and nonzero pipeline status work.
4. The host's workspace-write sandbox policy is retained in the isolated test.
5. A two-second job returns promptly, survives a 100 ms foreground timeout argument, allows independent work, wakes its idle owner and retains output.
6. Another agent cannot collect the owned job.
7. Job cancellation stops the process.
8. Foreground timeout reporting works and a subsequent command can run.
9. A child composition inherits and can execute the managed shell.

The background launch returned in **6 ms** and the process completed after **2,008 ms**. This verifies asynchronous behavior; it is not a measured speedup for real development tasks.

The live files were checked against the tested candidate after atomic file replacement. Their hashes and the test result are in [deployment.json](/home/epentland/.dsh/preset-backups/minimal-delegation/20260916T160243Z/deployment.json). The retained [smoke driver](/home/epentland/.dsh/preset-backups/minimal-delegation/20260916T160243Z/smoke/driver.mjs) and [result](/home/epentland/.dsh/preset-backups/minimal-delegation/20260916T160243Z/smoke/result.json) permit inspection.

## Rollback

The original files are in [the timestamped backup](/home/epentland/.dsh/preset-backups/minimal-delegation/20260916T160243Z/original). Restore its `agent.cordis.yml` and `preset.yml` to the active preset directory, then start a new session. Existing sessions continue with their current generation until they are closed.
