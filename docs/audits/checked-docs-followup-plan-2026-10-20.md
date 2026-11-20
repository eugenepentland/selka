# Checked docs follow-up: a summary you can read, a fast gate, the pilots' friction (plan, 2026-10-20)

Status: written on 20 October 2026 at the user's request, after a review of the
[checked project docs](checked-project-docs-plan-2026-10-19.md) pilots (lane D5,
`experiments/checked-docs-20261019/REPORT.md`). The decisions in §6 are the review's
recommendations, taken as accepted when the user launches the run. Codex implements
it, **after language wave 2 has landed** (§5): both change the compiler.

## 1. Summary

The pilots proved the mechanism. Three projects went through releases 0.1 and 0.2,
every `release check` is green, and the agent-written decisions carry real reasons
and rejected alternatives. Three things keep the result from doing its job, which is
letting a person read the document instead of the code:

1. **The overview is a reference manual, not a summary.**
   - kicad-convert's is 1,302 lines and markdown's is 5,066, about 40% of each
     project's source.
   - 10–12% of the lines are facts saying "none" (`Contracts: none.`,
     `Tested directly by: none.`, `Status: implemented.`).
   - About a third of the lines are blank.
   - The module map repeats modules as "see above".
   - Some examples dump long escaped byte strings.
2. **The full gate is slow on a large project** (FR-423). `release check` runs one
   compiler per test case and reuses no receipts, so markdown's warm run takes 345 s.
   Plain `mylang test` over the same project takes about 40 s.
3. **Eleven friction items are open** (FR-412 to FR-420, and FR-423 above). FR-421
   and FR-422 were fixed on 20 October (`277f093fce`).

After this run, `OVERVIEW.md` is a short summary that you read top to bottom, with a
generated per-module reference beside it for looking things up. `release check`
costs what `mylang test` costs, and the friction items are closed.

## 2. Design

### 2.1 The overview: a summary to read, a reference to look up

1. **Two outputs, one generator.** `mylang overview PROJECT --write` writes:
   - `OVERVIEW.md`, the summary;
   - `reference/<module>.md`, one file per module, the detail.

   `--check` checks both, and `release check`'s overview step covers both. One file
   per module keeps parallel lanes out of each other's files.
2. **The summary holds:**
   - the project summary;
   - the contents;
   - the at-a-glance table;
   - a **flat module table**: module, purpose (its docstring's first sentence),
     imports, public declarations, private functions. This replaces the repeated
     tree;
   - the authority table;
   - the changes since the last release, with each pending decision's title and
     `Why:` paragraph;
   - per module, its docstring and a **table of its public declarations**:
     - the linked name;
     - the first sentence of its docstring;
     - compact markers: `mut` for parameters it writes, the capabilities it holds, and
       `fails E`;
   - the releases, with each decision's title and first sentence.

   Signatures, full docstrings, examples, field tables, tests and per-declaration
   decisions move to the reference.
3. **No empty facts anywhere.** A fact is shown only when it has content. "Status:
   implemented" disappears; a hole shows as `hole`. "Writes: nothing. Authority:
   none." disappears. A test asserts that no generated line is only a "none" fact.
4. **Size targets**, measured on the pilots and reported, not gated: the summary is
   at most about 10% of the project's source lines. That is about 330 lines for
   kicad-convert and 1,200 for markdown, which has 140 public declarations. Codex logs
   the measured sizes and any layout decision.
5. **Determinism and staleness** keep the original plan's G1 and G2 for both outputs.

### 2.2 Examples that read

1. **Rule `long-example`** (`L_LONG_EXAMPLE`). An example whose expected output runs
   past 120 characters, or whose `>>>` block runs past 6 lines, reports in a plain
   `mylang lint` and as a warning in `release check`. It never blocks. The guide gets
   a short "show the call, not a dump" section: pick a small input, show `Ok(…)` or
   `Err(…)` directly rather than unwrapping it with a `match`, and assert a property
   (`len(...)`, a prefix) instead of printing a large value.
2. **FR-418: one display rule.** A `str` prints with the same quoting whether it is
   bare or nested in `Ok`, `Err`, a record or a list. Today the two differ. Regenerate
   the affected expected outputs.
3. **FR-412.** A docstring example that is a single index or field assignment
   (`>>> xs[0] = 1`, `>>> p.x = 2`) is a statement, not an expression wrapped for
   display.

### 2.3 The gate costs what `mylang test` costs (FR-423)

`release check`'s tests step runs the project's test roots and examples through the
same path as one `mylang test` invocation over those roots: one build per root,
forked trials, and receipts reused. A warm, unchanged run then reuses every receipt.
- **Target:** markdown's warm `release check` within 1.2× of `mylang test` over the
  same roots, and at most 10 s if the receipts allow (the original G6).
- Measure cold and warm on all three pilots through `scripts/build-slot.sh timing`.

### 2.4 The friction items

| Item | Fix |
| --- | --- |
| FR-413 | `release init`/`release check` name the file and position of a source error instead of `declaration loading failed: SourceError` |
| FR-414 | The guide documents `release.exclude` for intentional fixtures and repro sources, and the format step's failure names that option |
| FR-415 | A docstring example counts as a use for `L_DEAD_PRIVATE` and as a test for `L_UNTESTED_EXPORT` |
| FR-416 | `--adopt-comments` adopts only a block directly adjacent to the declaration (no blank line), never a banner or section divider, and prints every adoption it makes. `--dry-run` lists them without writing |
| FR-417 | A file-level waiver (`# lint: allow-file RULE reason="…"`) replaces markdown's 42 identical lines and kicad-convert's and http-server's 12–16. The guide explains how a project's lint configuration applies inside `release check` |
| FR-419 | The test filesystem's root is `.`, so `listdir(".")` lists it instead of being denied with a grant message |
| FR-420 | A function passed as a value counts as a use for `L_DEAD_PRIVATE` |

Each item becomes a named test, and FR-412, FR-415, FR-419 and FR-420 get their
ledger repros as fixtures.

### 2.5 The pilots, again

In `~/ai/canopy/selka-projects`, on a branch `docs-followup` cut from its `main`:
1. Regenerate the overviews and references with the final compiler.
2. Replace the waivers that FR-415, FR-417 and FR-420 made unnecessary.
3. Shorten any example `long-example` flags.
4. Re-run `tools/check-all.sh` and `release check` everywhere.
5. Re-measure G6.
6. Bump `COMPILER` to a ReleaseFast install of the final `main`, fast-forward `main`,
   and leave the checkout on `main`.
7. Mark FR-412 to FR-420 and FR-423 fixed in `LEDGER.md`, with the commit.

No interface change is involved, so no release is cut.

## 3. Batches

| Batch | Contents | Lands when |
| --- | --- | --- |
| F1 | §2.3 (the fast gate) and FR-412, FR-413, FR-415, FR-418, FR-419, FR-420 | every item is a named test; complete verification passes |
| F2 | §2.1 (summary and reference), §2.2's lint and guide section, FR-414, FR-416, FR-417 | the original G1/G2 hold for both outputs; complete verification passes |
| F3 | §2.5 (the pilots) | all three projects green on the new pin |

## 4. Gates

| # | Criterion |
| --- | --- |
| K1 | No generated overview or reference line is only a "none" fact. The summaries' sizes are reported against §2.1's targets |
| K2 | The original plan's G1 (determinism) and G2 (staleness walk) pass for `OVERVIEW.md` and every `reference/*.md` |
| K3 | Every item of §2.2 and §2.4 is a named test, and the ledger repros pass |
| K4 | markdown's warm `release check` is within 1.2× of `mylang test` over the same roots; cold and warm times for all three pilots are reported |
| K5 | The pilots are green on the new pin. The waivers this plan made unnecessary are gone, and the LEDGER items are marked fixed |
| K6 | Complete verification, formatting, `doctest .` and `doc-coverage .` pass for each batch, and `docs/tooling/release-docs.md` describes the two outputs, the new lint and the file-level waiver |

## 5. How it fits

- **Language wave 2 runs first.** This run starts after wave 2's REPORT records its
  last batch, because both edit `src/`: lint, the test runner and docstring
  examples.
- Wave 2's batch P migrates the pilots' docstring examples to the new spellings.
  This run's F3 starts from that `main`.
- If the same Codex session runs both, it finishes wave 2 completely, landing P,
  before starting F1.
- **Amendment, 20 October (evening): F1 and F2 run now, beside wave 2.** Wave 2
  still has a long queue (§4a of its plan), so waiting for it would idle this run for
  days.
  - F1 and F2 change tooling: `release check`, the test runner path, doctest, the
    overview generator and one lint rule. Wave 2's remaining work changes method
    refusals, patterns and `own`. They share only small sorted tables, such as
    lint registration and `diagnostic_codes.zig` rows, plus guide sections.
  - Run F1 and F2 in `~/ai/canopy/mylang-docs-followup`. Merge `main` before every
    landing and resolve those tables by keeping both sides' rows in order.
  - Write new examples and tests in the spellings `main` has at the time. Wave 2's
    generated migrations rewrite them after it merges.
  - **F3 still waits** for wave 2's batch P, because both rewrite the pilots.

## 6. Decisions (recommended, accepted at launch)

1. **Q1.** A summary `OVERVIEW.md` plus generated `reference/<module>.md` files.
2. **Q2.** Empty facts are never printed.
3. **Q3.** `long-example` is report-only, with a guide section.
4. **Q4.** An example counts as a use and as a test.
5. **Q5.** File-level lint waivers, with a reason.
6. **Q6.** `release check` runs tests through the `mylang test` path, with receipts.

## 7. Operating rules

The language wave 2 plan's §10 applies unchanged, with
`experiments/checked-docs-followup-20261020/` for `DECISIONS.md`, `status.md` and
`REPORT.md`, the integration branch `docs-followup/integration` in
`~/ai/canopy/mylang-docs-followup`, and these hard stops added:
- a change to the language itself;
- an edit to `selfhost/`.

In selka-projects, work only on `docs-followup`, then fast-forward `main` and bump
`COMPILER` as §2.5 says. Never push.
