# Cascading-benefit experiment: does "solve it once" design pay off for agents?

Status: plan, 19 September 2026, built and run the same day under
[`experiments/cascade/`](../../experiments/cascade/README.md). The pack, the three frozen
arms, the runner, the gate and the scoring script all exist and are self-checked; 63
independent maintainer runs, 9 chained runs and 3 transfer probes have finished. The
result is in [cascade-experiment-results-2026-09-19](cascade-experiment-results-2026-09-19.md):
the decision rule below fails on its first two clauses, so the proposals' claim is not
supported by this pack and no language feature is built on it. §3.6's instruction for
that case — fix the metric or the prompt first — is what the results document proposes. The two
proposals this answers are the user's (an "elegance = benefits cascade, obligations do
not" essay and a shorter "reward the expected future diff" note); they are not in the
repository.

The agents in this experiment are DeepSeek agents run through the locally installed
DeepSeek Harness (`dsh`). Nothing in the design depends on that choice: any agent that
can be launched non-interactively on a directory and leaves a transcript with token
usage can play the designer or maintainer role. The harness-specific details are
confined to §3.3, §3.4 and §4.

## 1. What the proposals ask for, in mylang terms

Both proposals reduce to one claim and one instrument:

- **Claim.** A design that states each domain fact once, in a representation the rest of
  the program can rely on, makes later correct changes cheaper. Its opposite, an
  abstraction that merely moves complexity, makes them dearer.
- **Instrument.** Do not score elegance by reading code. Freeze competing designs, hand
  fresh maintainer agents the same hidden future changes, and measure what a verified
  change costs on each design, minus what the design cost up front.

The proposals also list language features that make facts cheap to preserve. Most of
them already exist here, so the experiment is not blocked on language work:

| Proposal wants | mylang today | Gap |
| --- | --- | --- |
| Nominal domain types with private construction (`Length`, `NetId`) | `domain X: u32` with `private def` and `wrap`/`unwrap` ([domains.md](../domains.md)) | scalars only |
| "Exactly one of these states" | `union` with exhaustive `match`, multi-field cases, recursive payloads | none |
| Opaque aggregates with a checked constructor (`ValidatedPolygon`, `NonEmpty[T]`) | a `record` is either `public` (anyone constructs it) or private (cannot appear in a public signature, [modules.md](../modules.md)) | **F1: no way to export a record's name and hide its constructor** |
| Small interfaces so one algorithm serves many types | structural contracts and named `constraint`s ([generics.md](../generics.md)) | none for the experiment |
| Contracts strong enough for local reasoning (effects, mutation visible at the boundary) | effect ceilings frozen as the interface contract; `mutates(...)`; `api-diff` classifies interface changes | none |
| Derivation from one definition (equality, printing) | structural `==` on records/unions/Option/Result landed 2026-09-18 | no derived `str`/hash; not needed here |

F1 is the one feature the proposals name that the language cannot express. The
experiment is designed so that a winning design either does not need it or shows
exactly where it was missed, which is the evidence a feature should be built from.

## 2. The subject: the sexpr port

`experiments/sexpr-port/` is the right bounded subsystem, for four reasons:

1. **It is verified independently.** 79 guest tests, 17 byte-identical goldens against
   the real Zig printer, and `reference_parse.py`, an independent Python reader. The
   proposals warn that agreement between consumers of shared code proves nothing; the
   reference parser is the independent oracle they ask for.
2. **It has a real history of future changes.** The Zig original under `../eda/src/sexpr`
   has 30 commits. The ones that are language changes rather than housekeeping, with the
   files they had to touch, are the change distribution the reward function needs:

   | EDA commit | Change | Files touched in sexpr | Lines |
   | --- | --- | --- | ---: |
   | `a332ed2b` | allow `,` in unquoted atoms | tokenizer | 34 |
   | `4a124f24` | SI unit-suffix literals (`220k`, `100nF`) | tokenizer, parser | 169 |
   | `21c79169` | parse errors with source spans | parser, tokenizer | 206 |
   | `65349595` | units that survive the literal (`100nF` prints as written) | ast, parser, printer, tokenizer | 119 |
   | `0420dc5d` | one paren scanner for two byte-splicing consumers | new `paren_span.zig` | 88 |

   The last two are textbook cascades of obligations: a fact ("a literal has a
   spelling", "where does this form end") had no single home, so every consumer changed.
3. **The port already contains facts stated more than once.** The SI and unit table is
   split across the tokenizer's letter predicates, the parser's `si_scale` and
   `parse_unit`, and the printer's `mm` rendering. Line and column bookkeeping exists
   twice (`tokenizer.advance` and `parser.span_at`) because `LexError` carries no column.
   `parse_unit` accepts two token conventions because the contract and the landed
   tokenizer disagree. These are exactly the seams a "representation" redesign would
   close, and they are there without anyone planting them.
4. **It has consumers.** `id_insert`, `sexp_form_bounds`, `docgen` and the exporters in
   the EDA repo are the router/DRC/editor of this domain: they react differently to the
   same parsed facts.

## 3. Design

### 3.1 Arms

Three frozen designs of the same reader, each passing the same gate (79 tests, 17
goldens, `compare.py --large`). The two redesigns are produced by designer agents of
the same model and configuration as the maintainers, so the arms differ only in the
design brief, not in who wrote them:

- **B, baseline.** The port as it is today.
- **P1, representation.** A designer agent is given the port and the proposal's coding
  policy verbatim: find a representation or invariant that makes several pieces of logic
  unnecessary; prefer sharing a domain rule over sharing incidental syntax; name which
  callers benefit, which assumptions become guaranteed, which responsibilities stay
  independent; check every claim against actual callers and tests. Likely outcomes, not
  prescribed: one unit/scale table read by tokenizer, parser and printer; `Span` minted
  only by the lexer and carried by `LexError`; tokens that carry decoded values and
  spellings so the parser never rescans text ("parse, don't validate").
- **P2, generalised.** A designer agent is told to make the reader maximally reusable:
  dialect parameters, pluggable number policies, a callback-driven printer. This is the
  control. If P2 scores as well as P1, the metric rewards abstraction per se and is wrong.

The designer sessions are run before the task pack exists in any location the designer
can read, and never see §3.2. Their cost (tokens, turns, wall time, diff size) is the
upfront term. A designer may delegate to subagents; the harness records delegation
depth in every session, and a delegated session's usage is summed into its parent's.

### 3.2 The held-out future-change pack

Seven tasks, each a directory with `request.md`, hidden guest tests and goldens, and a
`verify.json` in the format `scripts/verify.py` already runs. Hidden copies live under
`../mylang-eval/cascade/`, outside the repository, with a hash manifest checked in, the
same arrangement `docs/velocity-loop.md` uses for lane A. Each row names the proposal's
probe it implements and the real EDA change it is drawn from.

| Task | Change | Probes | Source |
| --- | --- | --- | --- |
| T1 | A lexical edge case every consumer shares: negative SI literals (`-4.7k`) and exponent floats (`1.5e3`) parse, print and round-trip | one fix, shared benefit | `a332ed2b` |
| T2 | New unit `in` (inches), normalised to mm, printed back | policy has a coherent home | `4a124f24` |
| T3 | A measure keeps its source spelling: `10mil` prints as `10mil` | representation extension | `65349595` |
| T4 | Printer only: short-list width 72 to 80 and a trailing newline | presentation stays independent (files touched outside the printer count against the design) | none, the proposal's control |
| T5 | New consumer `form_bounds(src, offset)`: byte range of the form at an offset, without a second scanner | "every node carries its span" cascades to a new reaction | `0420dc5d` |
| T6 | A KiCad dialect with no `;` comments, both dialects parsing in one program | legitimate divergence without flag proliferation | `paren_span.Comments` |
| T7 | `LexError` gains a column that agrees with the parser's | one source of truth for positions | `21c79169` |

T4 and T6 are the guards the proposals insist on: without them the pack would reward
indiscriminate unification.

### 3.3 Maintainer runs

- Fresh agent per run: `dsh --profile headless "<maintainer prompt>"`, launched with the
  working copy as its current directory. The headless profile answers one task, prints
  the final message and exits, which is the whole session. The model and reasoning
  effort come from `~/.dsh/settings.yaml` (today `deepseek-v4-flash`, effort `max`);
  the log records the model on every call, so a drift mid-experiment is detectable, and
  the values are copied into every run's record.
- Maintainers run without delegation: the maintainer prompt forbids spawning
  subagents, and a run whose session header or descendants show `delegationDepth`
  above 0 is discarded and rerun. Delegation is allowed for designers because their
  cost is a single upfront number; for maintainers it would blur what one change cost.
- Working copy contains only the arm's source, `docs/`, the installed compiler and the
  task's `request.md`. Never `src/`, `experiments/`, other arms, or other runs. The
  harness keys its session directory by the working copy's path, so each run gets a
  fresh directory and its log is found by that path alone.
- Three runs per arm per task, so 63 maintainer sessions. Independent runs first, from
  the frozen arm. Then one sequential chain per arm, T2 → T3 → T7, carrying each result
  forward, because the proposals are explicit that an abstraction may cost on the next
  change and pay on the six after it.
- Optional isolation: `experiments/maintenance_trial/gateway.py` already counts tool
  invocations, edited submissions and seconds under a budget and was exercised on
  2026-09-07 with two participants over three stages. Use it once the unisolated runs
  show the pack is sound.

### 3.4 What is measured per run

Correctness first, as a gate: hidden tests and goldens pass or the run scores nothing.
Then, reported separately, never as one composite until the noise floor is known.
Every signal comes from the session log the harness writes under
`~/.dsh/sessions/<working-copy slug>/session-*/session.v3.jsonl.zstd`, which
`scripts/audit_deepseek_tools.py` already decodes; the run record copies the fields it
needs so the experiment does not depend on the logs staying around.

| Signal | How |
| --- | --- |
| Tokens: input, output, reasoning, cache reads | summed over the log's per-call `usage` records (`inputTokens`, `outputTokens`, `reasoningTokens`, `cacheReadTokens`) |
| Turns, tool calls, repair rounds (check or test failures before first green) | tool-call and tool-result events in the log |
| Wall time and seconds waited on the compiler | event timestamps; the audit analyzer's interval accounting |
| Files and lines changed | diff against the frozen arm |
| Semantic decisions changed | `mylang api-diff` against the arm's interface file plus a `list-declarations` diff |
| Source read before the first edit | bytes returned by read commands, a direct measure of "cost of finding the information" |
| Coupling | T4: any file outside the printer touched; T6: count of new boolean parameters |

The proposal's objective is then computed per task:
`gain(P, τ) = cost(B, τ) − cost(P, τ)`, with tokens as the cost, and
`R(P) = Σ_τ gain(P, τ) − upfront(P)`. Cost is input plus output plus reasoning
tokens; cache reads are reported beside it, not added, because they measure the
harness's caching rather than the design.

### 3.5 Transfer probe (the second cascade)

After the maintainer runs, a cheap comprehension test: a fresh agent is given only the
arm's `ast.my` and its unit table, no parser or printer, and asked to predict the
rendering of ten inputs (`10mil`, `100nF`, a 73-column list). Score answers against the
goldens and record bytes read. This tests whether learning one contract makes the rest
of the program predictable, which the proposals separate from change cost.

### 3.6 Decision rule, fixed before any run

The approach is **justified** when all three hold:

1. P1 beats B on at least five of seven tasks by more than the run-to-run spread, and
   loses on none by more than the spread.
2. `R(P1) > 0` over the pack, so the designer's upfront cost is recovered within seven
   changes.
3. P2 does not satisfy rule 1. If it does, the pack rewards abstraction and must be
   revised before any conclusion is drawn.

If P1 wins, the record of where its designer and maintainers worked around the language
(a public record whose constructor should have been hidden, a table that had to be a
chain of `if`s because `match` has no literal patterns, a spelling that had to ride along
as `Option[str]`) is the feature backlog, with the run evidence attached. If P1 does not
win, no feature is built on the proposals' strength; the metric or the prompt is wrong
first.

## 4. What gets built, in order

All under `experiments/cascade/`; nothing under `src/` changes.

1. `pack/` with the seven tasks, hidden tests and goldens, `verify.json` each, and the
   hash manifest of the copies under `../mylang-eval/cascade/`. Written first, by a
   session that never produces a design.
2. `designs/B`, `designs/P1`, `designs/P2`, each a copy of the port with a `DESIGN.md`
   naming the facts it gives a single home, and `evidence/` with the gate results and the
   designer session's usage.
3. `run.py`: takes an arm, a task and a run count; builds the working copy in a fresh
   directory; launches the maintainer with the `dsh` template already listed under
   `solver.command_templates` in `velocity/goal.json`; verifies with
   `scripts/verify.py`; reads the session log for that directory; writes
   `runs/<arm>/<task>/<n>.json` with the verdict, the usage sums, the model and effort
   seen in the log, and the diff. The launcher is one function, so another agent CLI is
   a second template, not a rewrite.
4. `score.py`: the per-task table, spreads, `R(P)` per arm, the T4/T6 coupling columns
   and the transfer-probe scores. Charts are optional.

Budget: 2 designer sessions, 63 independent maintainer runs, 9 chained runs, 6 transfer
probes. At the 2026-09-07 calibration's pace (about 100 s per stage through the gateway)
the maintainer runs are hours with four in parallel, not days. Token cost is recorded,
not estimated, since no comparable run exists yet; the September 14 to 16 DeepSeek
sessions in `docs/audits/deepseek-tools-2026-09-16/` are the nearest reference for what
one agent-hour costs on this project.

## 5. Threats and how the design answers them

- **The designer games the pack.** The pack is written and hashed before the designer
  sessions exist, and lives outside the repository.
- **The tasks favour P1 because the author knew the likely redesign.** Five of seven
  tasks are drawn from the EDA history, not invented; T4 and T6 are written to punish
  unification.
- **Shared bugs across arms.** Verification is the independent reference parser and the
  Zig goldens, never agreement between arms.
- **Run-to-run variance swamps the effect.** Three runs per cell, spreads reported, and
  rule 1 requires the margin to exceed the spread.
- **The metric rewards the wrong thing.** P2 is the calibration control; a P2 win
  invalidates the pack rather than rewarding P2.
- **Token counts unavailable or wrong.** The harness log records usage per model
  call, and `run.py` fails a run rather than scoring it when the log for its directory
  is missing or has no usage records.
- **Model drift between arms.** The model and effort are read from every run's log, not
  assumed from settings; runs for one task are interleaved across arms, and a run whose
  model differs from the cohort's is discarded.
- **Hidden delegation.** A maintainer that spawned subagents would understate its own
  cost; the log's delegation depth catches it and the run is discarded.

## 6. What this feeds

If the result is positive, lane A of the velocity loop gains a sixth signal, the future-
change cost over a frozen design, and the coding policy in `velocity/LOOP-PROMPT.md`
gains the proposal's instruction to name the facts a change gives a single home. The
preference data the proposals describe (design X beat design Y because maintainers
finished later changes cheaper) is exactly `runs/` paired by task, so nothing extra is
needed to start collecting it.

Related: [real-project-readiness-2026-09-18](real-project-readiness-2026-09-18.md),
[velocity loop](../velocity-loop.md), `experiments/maintenance_trial/README.md`.
