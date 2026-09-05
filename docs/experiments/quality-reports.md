# T: resolved reference and complexity reports

Status: `report-quality` implemented, version `quality-v1`. The command checks one
source compilation, analyzes its typed bodies, and prints advisory facts. It does
not lower or execute guest code. Source errors still reject analysis; metric
thresholds do not change validity or the successful command's exit status.

```sh
zig build run -- report-quality examples/duplicates.my
zig build run -- report-quality examples/duplicates.my --max-nesting=2 --max-function-lines=60
```

## Resolved references

Each function lists outgoing call sites by resolved declaration ID, rendered with
callee name and source location. Incoming counts count syntactic call sites from
all checked functions, including unreachable callers. Recursion and mutually
recursive components work without treating identifier spelling as a reference.
Comments and unrelated binding names do not add call edges.

Reachability starts at `main` and follows every checked call edge, including calls
inside constant-false branches and short-circuit operands. A function is visited
once; cycles terminate and long call chains do not use host recursion. This is a
conservative static graph, not evidence that a function ran, that a test asserted
anything, or that runtime inputs exercised a path. Runtime coverage and assertion
outcomes are explicitly reported as unmeasured.

Unreachable private functions receive a private-reachability review note. Other
unreachable functions receive a note requiring consideration of external entry
policy before removal. No dead-code deletion or unused-public error follows from
this report. Current programs have one main entry; future module/export entry roots
must extend this model rather than treating public entry points as dead code.

Bindings are reported separately by their declaration locations with the semantic
checker's static read/write counters. These include checker accounting for source
operations and are not dynamic event counts. This first report covers function
calls and local bindings, not a complete index of type/field/schema references or
cross-compilation imports. Those features must extend it as modules/schemas arrive.

## Metrics and review thresholds

| Metric | Definition | Default review threshold |
| --- | --- | --- |
| nodes | Visited checked expressions/statements, including root block | Count only |
| function-lines | Physical lines from function-name declaration through closing body brace, inclusive | 80 |
| longest-line-bytes | Longest complete physical line intersecting that range, excluding newline/CR | 100 |
| parameters | Declared parameter count, including capability/reference parameters | 6 |
| control-nesting | Maximum nested if/while/match statement depth; ordinary blocks/borrows add no level | 4 |
| decision-points | One per if, while, short-circuit logical operator, and try; max(arms-1,0) per match | 10 |

Decision points are a defined structural counter, not a claim of exact cyclomatic
complexity or runtime path count. Implicit arithmetic/bounds traps and provider
failures do not add decisions. Else-if is represented by nested if statements;
function calls do not import callee complexity. Comments/blank lines affect physical
line metrics, and several functions on one physical line share its full byte length.
Byte length is not Unicode display width. Binding declarations can share a spelling
in separate scopes without sharing a declaration location.

CLI options are `--max-function-lines=N`, `--max-line-bytes=N`, `--max-parameters=N`,
`--max-nesting=N`, and `--max-decisions=N`. Each is report-only and accepted once;
zero disables that metric's signal while preserving the measured fact. A positive
threshold signals only when exceeded, not when equal. Embedders use the equivalent
`quality.Options` fields. Invalid/negative/overflowing options are usage errors.

Threshold messages ask for review of cohesion before splitting. A large exhaustive
table or coherent function may be appropriate. The tool makes no extraction plan,
module-boundary recommendation, correctness claim, or pass/fail quality verdict.

## Acceptance evidence

`src/quality_test.zig` verifies resolved incoming sites, unreachable callers,
constant-false paths, cycles, private/public distinction, branch/loop/logical/match/
try counters, nesting, physical lines, deterministic reports, configurable/disabled
signals, and every allocation failure through analysis and rendering. A 2,001-function
call chain is analyzed iteratively without lowering or execution. Line lengths are
precomputed once per physical source line.

Actual CLI tests verify advisory exit status even with exceeded thresholds, source
error rejection, call names, unmeasured-coverage wording, and invalid/duplicate/wrong-
command options. Running the existing duplicate corpus reports one loop decision
per sum helper and all three calls reachable from main. That agrees with inspection
and does not establish execution coverage or general metric usefulness.

[Canonical formatting](formatter.md) is now implemented; the project-verification
driver remains pending. Future modules and schemas
must extend reference coverage and entry-root policy. Production review outcomes
remain necessary before treating these thresholds as evidence of useful policy.
