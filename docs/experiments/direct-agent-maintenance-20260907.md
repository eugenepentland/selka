# Repeated owner/generic maintenance — 2026-09-07

Two fresh agents each completed the same three-stage application sequence. Every
first edited submission passed its public checks and later private grading.
Independent source review also passed. This is an unscored same-language
calibration, not evidence of an advantage over another language or tool setup.

| Participant | Stage | Gateway commands | Edited submissions | Failed edited submissions | Start to final command | Gateway command time | Private observations |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A | Missing-item repair | 4 | 1 | 0 | 49.8 s | 0.79 s | 144/144 |
| A | Capped-value feature | 4 | 1 | 0 | 39.7 s | 0.73 s | 144/144 |
| A | Cross-module summary migration | 4 | 1 | 0 | 43.8 s | 0.86 s | 192/192 |
| B | Missing-item repair | 4 | 1 | 0 | 51.0 s | 0.82 s | 144/144 |
| B | Capped-value feature | 4 | 1 | 0 | 49.6 s | 0.76 s | 144/144 |
| B | Cross-module summary migration | 4 | 1 | 0 | 50.5 s | 0.87 s | 192/192 |

Each stage began with an unchanged public check that failed as expected, followed
by source inspection, one edit command and a passing edited check. Thus there
were 12 public checks, including six initial failures, but zero failed **edited**
submissions. All 24 requests were recorded and within the frozen per-stage limits
of 20 commands, five edited checks and 900 seconds. There were no abandoned,
budget-exhausted or excluded participant stages.

The application stores four integers in a generic owned buffer, fills it through
a generic mutable borrow helper, and returns a checked result across three
modules. Participants retained their own sealed changes between stages. The
migration changed the exported record to exactly `net:i64`, `accepted:u64`, and
`rejected:u64`, removed old fields, and updated its consumers. Review verified
ownership, allocator/result propagation, the generic helper, module boundaries,
exact field types and absence of input-specific shortcuts. No compiler, VM,
standard library, host or gate changes were needed by participants.

Private grading used 48 cases per stage with a common fresh private seed for both
participants. Report results and individual summary fields were independently
checked, for 960 observations overall. Independent review before launch caught
and fixed a grader whose encoded fields could compensate for one another, public
tools exposing future contracts, and sealing rules that lost unchecked budget or
abandoned submissions. Adversarial and unfinished-outcome fixtures verified those
repairs before the authoring snapshot was frozen. These coordinator repairs are
not participant application defects or Guardian findings.

Timing from stage start to the last command includes reasoning and tool waits,
but excludes final-response time and subsequent sealing. Start-to-seal times
(79.3–106.1 seconds) additionally include coordinator delay; both are retained in
the observations. Command time includes isolation, source capture, Python driver,
compilation and VM execution. Isolated compiler timing is unavailable. Background
acceptance work may have affected timing; no contention correction is claimed.

Both agents inherited the same root configuration with fresh initial contexts;
the exact serving model ID, token counts and cost telemetry were unavailable.
Their final sources were byte-identical at every stage. These are tiny, strongly
specified tasks, and there are only two fresh participants. The experiment did
not isolate typed holes, traces, host replay, laws or diagnostic recovery as a
productivity treatment. Larger repeated maintenance and matched treatments remain
necessary before claiming fewer turns or superior reliability.

Gateway commands ran in isolated environments with only current-stage public
files and read-only compiler/documentation mounts. Every recorded command chain
passes protocol review. Inherited agent tools were restricted by instruction;
gateway evidence cannot prove that no unlogged host-tool invocation occurred.
The command records are therefore observed requests, not independently verified
whole-model tool or token telemetry. Source review complements these bounded
behavioral cases; it is not runtime allocator-failure injection for this app.

The [observations](../../experiments/maintenance-evidence/20260907/observations.json),
[independent review](../../experiments/maintenance-evidence/20260907/source-review.json),
[prelaunch review](../../experiments/maintenance-evidence/20260907/review.json),
and [raw evidence](../../experiments/maintenance-evidence/20260907/) retain every
setup, sealed source, command/stream, before/after snapshot, private outcome and
source/compiler identity. The compiler is pinned by SHA-256; the frozen authoring
revision is `d21e291`. Original coordinator files remain under
`/home/epentland/ai/canopy/application-trials/maintenance-20260907`.
