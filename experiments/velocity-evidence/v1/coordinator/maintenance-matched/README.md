# Velocity maintenance with explicit coordinator handoff

Protocol: velocity-maintenance-handoff-v2. Two fresh participants A/B each complete three sequential stages; the same participant context resumes for stages 2/3. Each stage's coordinator begin precedes dispatch/followup, matching historical handoff timing. This is a new cohort; autonomous-first-check maintenance observations are preserved as supplemental evidence. No old clocks are corrected or replaced.

Prepare once before clocks:

```
python3 -B coordinator.py freeze
python3 -B coordinator.py prepare --compiler /home/epentland/ai/canopy/application-trials/velocity-v1/toolchain/bin/mylang --model 'Same inherited root configuration for A/B; exact serving model ID unavailable'
```

Stage dispatch (coordinator only):

```
/usr/bin/python3 -B /home/epentland/ai/canopy/application-trials/velocity-v1/maintenance-matched/coordinator.py begin --participant A
```

Then immediately dispatch participant-prompt.txt, replacing PARTICIPANT with A. Repeat for B. After a participant seals a stage and returns a final response, the coordinator explicitly begins that participant's next stage and resumes the SAME agent with the same one-stage prompt. Never begin before intending to dispatch. Duplicate begin fails; no restarts or clock corrections. The bridge never starts clocks, requires an existing begin and unchanged public check first, and returns await-coordinator on transitions.

Freeze retains the same documentation allowlist, private per-stage seeds shared by A/B, adapter code/doc hashes and existing maintenance harness receipt. Prepare pins the same frozen compiler and prepares only stage 1 for each participant. No original helper or repository harness changes. Instructions and namespace boundaries remain separate: inherited tools are constrained by participant instructions and require transcript review.

Timing is last executed command result.time minus gateway.started_unix, including coordinator handoff and subsequent reasoning/waits. Begin-to-first-command gap is first executed request.time minus gateway.started_unix, reported separately without subtraction. Sealing delay remains separately observable. A stage without executed commands has a null first-command gap. Initial unchanged checks are retained separately from edited failures. No command counts are called model turns.

After all six stages seal, use coordinator.py grade (or grade --resume) and summary. Retain failed/time-limited stages; never delete incomplete execution records for silent reruns. Independent structure/protocol review and historical-seed replay are separate follow-up work. Private seeds/results and coordinator directories must never be mounted to participants.

Prelaunch validation uses mocked gateways only; no clocks, compilation or participant execution. Freeze and prepare do not begin clocks.
