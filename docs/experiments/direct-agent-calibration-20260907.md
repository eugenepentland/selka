# Direct agent calibration — 2026-09-07

Three fresh coding subagents independently added optional job priorities to the
workflow planner, using `.my`, Python, and Zig. No API key or external model API
call was used. All three sealed submissions passed the seven common private test
groups: 138 planner manifests and four malformed-input requests. This is one
unscored exploratory block, not the 36-session pilot or evidence of a language win.

| Participant | Preparation | Feature task | Public submissions | Private result |
|---|---:|---:|---:|---|
| Python | 24.7 s | 95.7 s | 1 | 7/7 groups passed |
| `.my` | 26.3 s | 133.4 s | 1 | 7/7 groups passed |
| Zig + Guardian | 305.9 s | 249.0 s | 3 | 7/7 groups passed |

Times are observed monotonic wall time, including tool waits within each phase.
All participants passed the common 21-case practice exercise. Preparation and
feature budgets were 20 and 30 minutes respectively, with no language discount.
Zig practice included **260.0 seconds of cold compilation across 21 builds**.
Public-check latencies totaled approximately 0.22 s for Python, 0.37 s for `.my`,
and 40.0 s for Zig. These timings describe this harness/workflow, not pure coding
speed, model thinking time, or a normal warm-cache development loop. Hidden
grading occurred after sealing and is excluded from participant times.

## What happened

Python added a validated optional dataclass field and priority/ID heap keys.
`.my` added signed priority parsing and an ID-indexed priority buffer, consulting
it only during ready-job selection. Zig added validated job priority and selection
logic, then extracted `parseJob` after Guardian reported cognitive complexity
27 against a limit of 25. Existing dependency readiness, layers, timings and error
ordering were preserved in the passing private cases.

Python and `.my` passed their first public submission. Zig's first submission
failed Guardian complexity and two line-length findings; its second failed one
remaining 241-character test line against a 240-character limit. Its third passed
all 88 Guardian checks, 18 Debug tests, ReleaseSafe compilation and public cases.
No Guardian policy edits, freezes, or accepted debt were introduced. Ten advisory
line-length findings remained. Gate findings here demonstrated maintainability
review and formatting friction, **not detected application correctness bugs**.

A separate agent reviewed all three sealed changes against public requirements,
without hidden cases. It found no concrete correctness or stdlib-only violations.
It considered `parseJob` a coherent improvement, but saw no readability benefit
from splitting a JSON fixture inside a field name. It suggested stronger literal
expected timing/join cases for `.my` and dependency-permutation tests for Zig;
these are coverage improvements, not demonstrated defects. The `.my` test host
path also became specific to the trial sandbox. Sealed sources were not repaired
after this review or private grading.

The `.my` agent used an installed compiler check successfully; recorded direct
navigation-client usage was zero. This run therefore does not demonstrate a
navigation advantage or diagnostic repair benefit. Application logic remained
in each target language with stdlib-only dependencies. Python scripts in the
`.my` tree served as external test drivers, not application business logic.
No language/compiler source edits or Zig host rebuilds were needed.

## Limits and next actions

- One small feature, one participant per language, draft task packs, and no
  language-focused control: no statistical ranking or large-codebase claim.
- Exact model ID, tokens and model costs were unavailable; none are estimated.
- Agents received fresh contexts and instructions to use only their own gateway.
  Gateway commands used namespace isolation, but the whole coding-agent runtime
  retained host tools. This is not enforced whole-agent confinement. Participants
  also shared host resources. Source edits and commands were recorded by gateway.
- Generic prompt wording caused initial main-document reads at the wrong paths.
  Future prompts should name `.trial-public/CONTRACT.md` and `GUIDE.md` explicitly.
- Reuse a verified build for one immutable source/toolchain/configuration across
  a case suite. Keep per-case process isolation and separate cold-build reporting;
  do not reuse a pass when source, policy, tools or relevant inputs change. The
  current repeat-cold-build policy particularly inflates Zig onboarding cost.
- Keep generated `__pycache__` files out of future source captures, without
  modifying these sealed snapshots. Preserve Guardian ROI from temporary gate
  directories; current snapshot ROI records came from baseline construction and
  were left unclassified.
- Next, repeat matched tasks across repair and shared-contract/feature families.
  Expand to medium/large maintenance only after those results justify the cost.

The evidence supports feasibility: agents completed the same feature in all
three languages, and `.my` needed no compiler change. It does not yet establish
faster development, fewer defects, or lower maintenance cost for `.my`.

## Evidence

[Machine-readable summary](../../experiments/application_comparison/evidence/direct-agent-calibration-20260907.json)
contains timings, source hashes, public retries, tool metrics and deviations.
Complete source snapshots, public logs, private grading, configuration receipts,
patches, bridge/setup scripts and review notes remain at
`/home/epentland/ai/canopy/application-trials/direct-20260907`.
Tool/environment receipts verified before and after private grading. Guardian
feedback was committed separately as `3b046b1` in guardian-zig; its commit hook
also passed with zero blocking findings. Scored pilot session count remains zero.
