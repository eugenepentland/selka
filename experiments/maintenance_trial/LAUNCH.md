# Coordinator launch and exact participant prompt

Prepare each stage using pack.py as documented. Before starting its timer, provide
a dedicated read-only documentation directory containing only approved language
references (no experiment sources, solutions, grader or private seeds). Then:

```sh
python3 experiments/maintenance_trial/gateway.py /private/trial-a-stage1 begin \
  --docs /private/approved-language-docs
```

Keep the gateway script and prepared pack outside the participant projection.
Expose an execution tool that accepts only the gateway invocation below; do not
provide an unrestricted alternative. When using subagents with inherited tools,
require this protocol explicitly and review for bypasses. That arrangement gives
isolated gateway commands, not technical isolation of every inherited agent tool.
Each `run` starts in `/work`, with TASK.md, cases.json, a stage-specific check.py
and editable source files in `work/`. `/tools/compiler` and `/tools/docs` are
read-only mounts. No coordinator transcripts, private cases, seeds or grader are
mounted. No networking is available inside a command.

Substitute only the absolute gateway script path, pack path and current stage in
this prompt. Do not add repository histories, private design notes or prior
participant outcomes:

> Work on the current stage of the owned-ledger maintenance trial. Read TASK.md
> inside the command environment for the contract and editable scope. You must
> route every tool command through this exact coordinator gateway. Do not read,
> write or invoke tools directly outside it, inspect the gateway implementation,
> or access any other workspace or participant. The supplied paths identify the
> gateway invocation only; their parent directories are outside your scope.
>
> First run the public check, then inspect the task and sources:
>
> `python3 GATEWAY_SCRIPT PACK_DIRECTORY check`
>
> `python3 GATEWAY_SCRIPT PACK_DIRECTORY run -- /bin/cat TASK.md work/ledger.my work/model.my work/report.my`
>
> To make an edit, run an editor or a Python command through `run`; for example,
> `python3 GATEWAY_SCRIPT PACK_DIRECTORY run -- /usr/bin/python3 -c '...'`.
> To inspect language references use `/tools/docs` inside `run`. To invoke the
> compiler use `/tools/compiler`. Run all public cases with the gateway `check`
> operation after every edited candidate. Do not invoke check.py indirectly from
> a run command: only the check operation records an edited submission.
>
> You have 20 gateway tool invocations, 5 edited submissions and 900 seconds for
> this stage. The first exhausted bound stops work. Failed commands and unchanged
> checks consume tool invocations. Each changed source checked through `check`
> consumes an edited submission, even if it fails. One gateway request is one
> command metric; multiple commands inside a shell are not separate tool turns.
> Shell batching is allowed and must remain within the task scope. A command has
> an additional 60-second limit and bounded output. Gateway JSON reports actual
> counts, diagnostics and remaining time. Stop when finished or when a budget
> refuses work; state completed, budget or abandoned and any unresolved issue.
> Your final source must match your last gateway check. The coordinator seals it.
> Do not report guessed token counts or claim hidden-test success.

After the participant stops, the coordinator seals with gateway evidence:

```sh
python3 experiments/maintenance_trial/pack.py seal /private/trial-a-stage1 --reason completed
```

Prepare the next stage from that seal and repeat `begin` with identical approved
docs. Each stage resets its budgets. Keep hidden grading private until all stages
are complete. A request is recorded before dispatch; raw streams, command start,
end, duration, exit status and before/after source snapshots are coordinator-owned
under commands/ and gateway.jsonl. Rejected requests count in observed invocation
metrics and are recorded separately from executed commands. An interrupted
pending command blocks subsequent work until coordinator review. Token usage is
explicitly null; the adapter cannot observe model reasoning tokens. Review agent
histories for commands that bypassed the gateway and report violations separately.
