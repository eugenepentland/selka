# Incremental self-hosting, stage 1: the lexer and parser (plan, 2026-10-19)

Status: accepted, 19 October 2026. The user decided U1 to U8 the same day
(§11). Codex implements it, starting after the project ladder closes (§12 is
the launch instruction). Written against `main` at `c62ea5671e`. Nothing in
this plan is implemented. It narrows and amends the
[progressive self-hosting plan of 12 October](selfhost-progressive-parity-plan-2026-10-12.md)
(never adopted) to a first stage that agents can carry to deletion, and it
records what the 12 October plan did not know: the compiler already has a
byte-exact syntax contract, and the project ladder has since changed the memory
model, the gate and the agent workflow.

Scheduling, 22 October 2026: the EDA port roadmap (`eda-port-roadmap-2026-10-22.md`
§4.I) makes this plan stream H. It starts after the port's G2 stage freezes the
language, and its stages are H1 (this plan) to H5. The gates and rules here are
unchanged. Who implements (U5) is revisited at H1's start.

## 1. Summary

Move the lexer and parser into one Selka component. The component reads source
bytes and returns exactly the bytes the Zig front end already writes to its
syntax cache (`StoredSyntax`, §3.2), plus the parser's diagnostics. The host
accepts that payload through the path that already serves disk-cache hits, so
nothing downstream changes. The live Zig parser is the oracle, byte for byte,
over a corpus of about 1,000 files. Once the Selka parser matches everywhere,
passes the performance and qualification gates, and has run as the default with
the Zig parser shadowing it for 14 days without a mismatch, `src/lexer.zig` and
`src/parser.zig` are deleted.

Four phases: prerequisites (four parallel lanes), the Selka lexer and parser
(two lanes), integration with shadow and flip (one lane), deletion (one lane).
Every ported section must run close to the Zig code it replaces on the same
work. When it does not, the fix goes into the language: the compiler, the runtime
or the standard library, not a workaround in the ported code (S11, the user's
rule of 19 October). A standing performance lane does that work beside each
stage. The October pilot parser ran 6× to 20× slower than the Zig parser, so
stage 1 begins with a measured spike whose findings are that lane's first items
(§5, P1). Later stages (declarations, bodies, lowering) are outlined in §7 and get their
own plans from what this stage measures.

**What this does and does not buy.** Self-hosting is for dogfooding the
language at its hardest scale and for moving compiler work into Selka. It does
not shorten the gate: any compiler change, in whatever language, still reruns
everything that runs the compiler, and the corpus is the same size. The edit
loop for a syntax change should end roughly even with today's (§2). The
compiler-edit gate is the subject of the test-core speed lane, which runs
before this plan.

## 2. What a syntax change costs, by phase

| Phase | Where a syntax change is made | Edit to rebuilt compiler | Gate |
| --- | --- | --- | --- |
| Today | `src/lexer.zig`, `src/parser.zig`, `src/ast.zig` | `zig build`, 2 to 7 s ([audit](development-loop-audit-2026-10-12.md) §2) | everything that runs the compiler reruns |
| P1 and P2, shadow mode | both parsers, in one commit (S8) | `zig build` plus a component rebuild | the same, plus one shadow parse of the corpus |
| After deletion (P3) | `selfhost/frontend/*.my`; `ast.zig` only when the tree's shape changes | a component rebuild, at most the same-day `zig build` time (G3) | the same set reruns, now keyed on the component identity (S9) |

The double-work window, P1 to P3, is the cost. The September port stalled on it:
it tracked a frozen oracle while the language moved, so every change was made
twice for months ([pause record](selfhost-pause-and-salvage-2026-09-17.md)).
This plan bounds the window by shadowing against the live parser, landing both
sides in one commit, and deleting the Zig side on a fixed rule.

## 3. Where we start

### 3.1 The Zig code this stage replaces

| Item | Size |
| --- | --- |
| `src/lexer.zig`, `src/parser.zig`, `src/ast.zig` | 669, 2,879 and 462 lines |
| Distinct diagnostic codes raised by the lexer and parser | 40 |
| Lexer, parser and syntax test files | 1,969 lines |
| Lexer call sites outside tests | 13 in 9 files (`compiler`, `interfaces`, `main`, `embed`, `project`, `module_names`, `navigation_partial`, two migration modules) |
| Parser users outside tests | `compiler`, `declarations`, `interfaces`, `main` |
| Token consumers beyond the parser | the formatter (`formatter.zig` reads tokens), `mylang dump-tokens`, the declaration listing |

`ast.zig` stays after deletion: it is the type the payload decodes into.

### 3.2 The contract that already exists

`Compilation.parseCached` (`src/compiler.zig`) consults the front-end cache
before lexing. On a miss it lexes, parses, and calls
`frontend_cache.rememberSyntax`, which writes a `StoredSyntax` value: the
program's `types`, `nodes`, `statements`, `functions`, `lambdas`, `attributes`
and `docstrings` tables. `decodeSyntax` reads it back on a hit. The encoding is
`src/persist_codec.zig`: little-endian integers at their declared width, a byte
per `bool`, an enum as its tag integer, an optional as a presence byte and the
value, a slice as a `u64` length and its items, a struct as its fields in
order, a union as its tag and payload. The AST is flat tables addressed by
index, and names are spans into the source bytes, not strings.

Three things follow:

- A Selka program can produce that payload with a byte buffer. No new syntax
  schema is needed (decision U2).
- Every stage downstream of parsing already consumes decoded payloads on every
  warm build, so a component's output enters through a tested path.
- Unchanged files never reach the component on later builds: their syntax is a
  cache hit. The component sees only the files that changed.

The lexer has its own oracle too: `mylang dump-tokens FILE` prints
`tokens-v1` JSON with each token's kind, byte span, line and column.

### 3.3 Self-hosting machinery on main

- Two Selka components run in production: `test-index` (for `tests-for`,
  `context` and lint notes) and `cache-plan` (test-cache closures). They are
  built by `selka-components` with a seed compiler pinned in
  `selfhost/component-seed.json` (commit `2ed71384d7`, 17 October, checked
  ownership), and run as separate processes over
  [component-protocol-v1](../tooling/component-protocol.md).
- The admitted source profile, `component-v1` ([bootstrap profiles](../bootstrap-v1.md)),
  is narrow: it is why earlier pilots spelled token kinds as strings.
- The process boundary is the only one. Selka cannot be linked into the Zig
  binary (no exported functions, no buffer arguments; `extern func` is
  scalar-only), and the standard library has no way to read standard input, so
  a resident worker on pipes is not yet possible.
- Stale: `selfhost/README.md` still describes the QBE back end, and
  `selfhost/stage0-pin.json` names a QBE-era seed.

### 3.4 The unmerged bootstrap branch

`codex/selka-bootstrap-20261011` (`dff9304b9c`, 325 commits not in main) holds
seven components. The two this stage could salvage are `lexer_pilot` and
`parser_pilot`. A read-only survey on 19 October found:

| Question | `lexer_pilot` | `parser_pilot` |
| --- | --- | --- |
| Size (source, tests) | 1,101 and 162 lines | 5,850 and 1,058 lines (`full_parser.my` 1,980) |
| Representation | `Token(kind: str, start, end)`, kinds as Zig tag-name strings, keywords by an `if word == b"…"` chain | one untyped `Value{kind, integer, data, children, names}` pool mirroring `ast.Program`, field names as strings |
| Wire | 12 bytes a token | tokens in as tag strings; the tree out as a value graph (`SLKAST01`) |
| Parity reached | 79 fixtures, 1,714 tokens | 378 of 379 modules (`tests/lang`, `tests/value_semantics`, `src/stdlib`, 116 fixtures) |
| Syntax since its base | | misses `accept_resource[T]`, `@noalloc`, `const x: T` without `=`, the removed effect clauses (`effect_bound` in 15 places) and the single-clause `gather` |
| On today's compiler | blocked by `E_SINGLE_OWNER_LOOP` | of 46 modules, 41 `E_SINGLE_OWNER_BORROW`, 2 `MOVED`, 1 `OVERLAP`; `mylang fix` inserts 132 `.copy()` calls and leaves 10 clean, 11 sites unrepairable |
| Measured cost | 3.3× to 7.7× the Zig lexer | 6× to 20× the Zig parser; 440 KB of dense source took 1,057 ms against 75 ms, with a 29.3 MB reply of 900,093 values |

The profile explains most of it: no enums, no dictionaries, string kinds, a
generic value pool and a seed build at -O0, plus about 8 ms of launch and
authentication per exchange. The audits never separated serialization from
parsing. One blocker is structural: 18 parser modules pass two fields of one
state record as `mut` at once (`sequence(mut p.pool, p.catalog, …)`), which
checked ownership rejects as `E_SINGLE_OWNER_OVERLAP` (the field-borrow
friction of FR-107 and FR-350 in the selka-projects ledger).

What is worth taking: the keyword and operator tables, the 79 lexer and 116
parser fixtures, the shadow corpus lists, and the qualification inventories (49
`expectError` checks and 24 malformed exchanges). The code itself is not (U6).

The `body_check` component (33k lines) is not a salvage source for later
stages either. It is built around the Zig checker's internal tables and the
syntax that main has since removed (effects, comprehensions, scalar domains,
reference counting). Only its fixtures and diagnostic inventory are worth
mining.

### 3.5 The corpus

| Source | Files | Lines |
| --- | ---: | ---: |
| `tests/` (of which `tests/lang` 356 files, 29.5k lines) | 496 | 35.7k |
| `test/core` | 190 | 12.6k |
| `selka-projects` (outside the tree; optional input) | 228 | 23.8k |
| `src/stdlib` | 36 | 5.7k |
| EDA application sources (`experiments/velocity-evidence/v1/application-sources`) | 47 | 5.7k |
| `selfhost/` | 48 | 3.1k |
| `bench/`, `benchmarks/` | 49 | 2.8k |
| `examples/` | 93 | 2.0k |

About 960 files and 68k lines in the tree, and about 1,190 files and 91k lines
with selka-projects. Every lexer and parser diagnostic fixture in the Zig tests joins
it as the negative corpus. The generated 191k-line and 510k-line projects of the
[packed stage cache experiment](../../experiments/packed-raw-20261010/README.md)
are the throughput inputs.

## 4. Decisions in this plan

- **S1. The stage-1 contract is `StoredSyntax` plus diagnostics.** The
  component returns the payload bytes and the diagnostics the Zig lexer and
  parser would have raised (code, span, message, notes, fix edits, order). A
  generated layout description of `StoredSyntax` (`mylang dump-syntax
  --layout`) and a test that fails when `ast.zig` changes it without updating
  the description make every tree-shape change visible to the Selka side.
- **S2. The live Zig parser is the oracle, byte for byte.** No frozen oracle.
  The parity harness compares payload bytes and diagnostics for every corpus
  file and names the first differing field path on a mismatch.
- **S3. Compiler code in Selka is written over `bytes` with integer spans.**
  Flat tables of scalar records, enums for kinds, no stored slices and no text
  copy per token. This matches the Zig design, and it makes the stage neutral to
  wave 3 (`str` as bytes, slices as views): the component neither waits for
  wave 3 nor needs migrating by it beyond what `mylang fix` does.
- **S4. One resident worker per compiler process.** Framed requests over
  standard input and output, all of an invocation's cache misses in one
  request, the executable authenticated once, a deadline per request, kill and
  reap on timeout or host exit, a `quit` message. This is H2 of the 12 October
  plan restricted to one stage. The worker reads requests from standard input
  (U3, decided; spelling in §5, lane B) and writes replies with `Stream.write`,
  which already flushes on every call.
- **S5. Component output enters through the syntax cache.** On a miss the host
  calls the worker instead of the Zig lexer and parser and stores the result as
  it stores its own.
- **S6. Two build policies.** For development, the current compiler builds the
  component in debug, one unit per module, through the shared unit store, and
  `MYLANG_COMPONENT_DIR` selects the development install. For the gate and
  production, the qualified seed builds it with `--release` and the
  reproducibility rebuild.
- **S7. Re-seeding is a script.** Tag the commit, build the seed, record its
  receipt, build every component with both the old and the new seed, require
  identical corpus outputs, then switch `component-seed.json`. It runs at every
  flip and whenever the component needs a newer language feature. A re-seed is
  the "release" of [D7](../adr/D7-feature-delay.md): compiler code may use a
  feature once the seed implements it.
- **S8. A syntax change during shadow lands in both parsers in one commit.**
  The shadow step in the gate goes red otherwise. Shadow ends on a fixed rule:
  14 days as the default with zero mismatches, then deletion.
- **S9. The component's identity is an input of every cached step that parses.**
  After deletion the Zig test binaries no longer change with the parser, so
  without this a parser edit would reuse stale verdicts.
- **S10. Progress is computed.** `selfhost/ownership.json` lists each stage's
  Zig and Selka sources, its mode variable, default, flip and deletion dates and
  gate state, and a unit test checks it against the code's defaults. The
  12 October dashboard is deferred.
- **S11. Each ported section stays close to Zig parity, and a gap is fixed in
  the language** (the user's decision, 19 October). The measurement is
  identical in-memory work with process launch excluded: the Selka section built
  `--release` against the Zig code it replaces built ReleaseFast. It runs over
  the corpus and the 191k-line and 510k-line projects, in an exclusive timing
  window, with the two arms interleaved. The target is at most 1.10× the Zig
  median and p95 on every row.
  - A row over the target opens a `perf` item in the ledger (lane S).
  - Its fix lands in the compiler, runtime or standard library, by the
    macro-then-micro rule of the 12 October plan (§7.1, its H7):
    1. Attribute the cost in the section.
    2. Reduce it to a micro benchmark with a Zig twin in `bench/parity`, whose
       ratio matches the attributed share.
    3. Fix it, then show that the section's row moved.
  - A workaround in the component's source is allowed only with a `# FR-NNN:`
    marker and only until the language fix lands. It never closes the item.
  - A fix that needs a shape, ownership-rule or capability change goes to the
    user.
  - Every fix also passes the existing parity and runtime suites, so a gain in
    the compiler's own code is never paid for by user programs.
- **S12. The parity row outlives the Zig code.** At deletion, the Zig twin and
  a frozen copy of its inputs move to `bench/selfhost/`, outside the compiler.
  The section's ratio stays measurable after the Zig code is gone, and later
  language changes cannot silently regress it.

## 5. Phases and lanes

Each lane runs in its own worktree and branch, lands through
`scripts/patch_gate.py --parallel` on its branch, and reaches `main` only by a
coordinator merge after a green complete verification. Never pushed.

### P0. Prerequisites (parallel, about a week)

| Lane | Deliverable | Acceptance | Files |
| --- | --- | --- | --- |
| **A. Oracle and corpus** | `mylang dump-syntax FILE [--layout]`, a developer command printing the `StoredSyntax` payload and the diagnostics in one framed form; `selfhost/corpus.json` (globs, the optional selka-projects root, the negative fixtures); `selfhost/tests/syntax_parity.py`, which runs any candidate parser over the corpus against `dump-syntax`; the parity bench of S11: a Zig twin driver in `bench/selfhost/` that links the lexer, parser and payload encoder and times them over files held in memory, the matching Selka harness that times the component's batch entry with `Clock`, and one runner for both in a timing window | Zig against itself: zero mismatches over the corpus; editing an `ast.zig` field turns the layout test red; a deliberately corrupted payload names the field path; the twin reproduces `dump-syntax` bytes and a Zig-against-Zig run reads 1.00× within its interval | `src/main.zig`, a new `src/syntax_dump.zig`, `selfhost/tests/`, `bench/selfhost/` |
| **B. Standard input and the worker** | standard input for Selka programs (spelling below); the framed protocol (component-protocol envelope, new magic); the host side in `component_launch.zig`; a Selka echo worker | crash, timeout, oversize frame, malformed frame, early exit and identity change each fail closed (G5); no hung test process | `src/core/runtime/`, `src/stdlib/`, `src/component_*.zig` |
| **C. Seed and development builds** | the re-seed script and procedure (S7; language wave 2's batch 2s writes the script under the amendment of 20 October, and this lane adopts it); a `frontend-v1` source profile admitting enums, unions, dictionaries, generics, `fails`/`try` and byte buffers; `zig build components-dev` (S6) | two-seed equivalence on the existing components; edit to ready component measured | `selfhost/*.zig`, `selfhost/tools/`, `docs/bootstrap-v1.md` |
| **D. Inventory and housekeeping** | `selfhost/ownership.json` and its test; rewritten `selfhost/README.md`; the old stage-0 pin marked historical | the inventory test fails on a default that disagrees with the code | `selfhost/` docs, one test |
| **P. Performance parity (standing)** | the `perf` items of S11, fixed in the compiler, runtime or standard library, each with its micro benchmark, Zig twin, threshold and provenance note in `bench/parity` | each item's section row moves by the share its micro attributed; parity and runtime suites within their thresholds | `src/core/`, `src/core/runtime/`, `src/stdlib/`, `bench/parity/` |

**Standard input (lane B; spelling accepted 19 October).**
The entry point declares a parameter of type `Input` (written `stdin: Input` in
the guides; the type selects the stream, so the name is free). Like the output
streams it is granted unconditionally, and `--restrict` cannot remove it. Every
read blocks, and a read error traps `R_INPUT`, the way a failed write traps
`R_OUTPUT`.

| Method | Returns |
| --- | --- |
| `stdin.read(max: int) -> bytes` | up to `max` bytes, `b""` at the end of input |
| `stdin.read_exact(n: int) -> bytes?` | exactly `n` bytes, or `None` when input ends first (a truncated frame) |
| `stdin.read_line() -> bytes?` | through the next `\n`, or the final unterminated line, or `None` at the end |
| `stdin.read_into(mut buffer: byte_buffer, max: int) -> int` | appends up to `max` bytes to the buffer without an intermediate copy; the count, 0 at the end |

`input_from(data: bytes) -> Input` gives guest tests an in-memory input.
Standard output already pipes: `out.write(data)` writes raw bytes and flushes.
A Selka program can then sit in a shell pipeline, and the component worker is
one such program.

Lane P starts when the P1 checkpoint produces its first items. It stays open
through every later stage, and it is the only lane that changes the compiler
for performance. Its compiler work is ordinary compiler work and lands through
the same gates.

### P1. The Selka lexer and parser (after A and C, one to two weeks)

| Lane | Deliverable | Acceptance |
| --- | --- | --- |
| **E. Lexer** | `selfhost/frontend/lexer.my` and its tests | tokens equal to `dump-tokens` for every corpus file; lexer diagnostics equal over the negative corpus |
| **F. Parser and encoder** | `selfhost/frontend/parser.my`, `syntax_encode.my`, a batch entry that parses a list of files, and Selka tests | payload bytes equal to `dump-syntax` for every corpus file; diagnostics equal over the negative corpus; throughput recorded (G2) |

**Throughput checkpoint, before either lane writes the full grammar.** The
pilot's 6× to 20× is the plan's largest risk. E and F first build a spike: the
lexer and the expression and statement core of the parser, with the encoder,
built `--release`, run over the 191k-line project's files against the Zig
lexer and parser on the same files, in a timing window, with the time split
into lexing, parsing, encoding and process cost. Every row over S11's 1.10×
becomes a `perf` item for lane P, which fixes it in the language while E and F
write the rest of the grammar. The lanes stop only when a cause needs a shape,
ownership-rule or capability change. Those, and the spike's numbers, go to the
user.

E and F can overlap once the token kinds are fixed: F starts on the Zig token
stream (decoded from `dump-tokens`) and switches to E's lexer when E matches.

### P2. Integration, shadow and flip (after B and F, about a week)

| Lane | Deliverable | Acceptance |
| --- | --- | --- |
| **G. Integration** | `MYLANG_PARSER_MODE=reference|shadow|component` in `parseCached` and in every consumer of §3.1, including the formatter's tokens; the worker batching all misses of an invocation; shadow on in `zig build test`; S9 keys | G1 to G5 (§6) green; the flip commit changes the default and records the date in the inventory |

### P3. Deletion (14 days after the flip, zero mismatches)

| Lane | Deliverable | Acceptance |
| --- | --- | --- |
| **H. Deletion** | `src/lexer.zig` and `src/parser.zig` removed; their tests moved to Selka tests or corpus fixtures; consumers on the component | lines removed, `zig build` time and gate time before and after, recorded; neither worse |

## 6. Gates for stage 1

| Gate | Condition |
| --- | --- |
| G1 parity | zero mismatches over the corpus: payload bytes and diagnostics |
| G2 performance | (a) section parity, S11: the component's in-memory lex, parse and encode at most 1.10× the Zig twin's median and p95 on every row; (b) end to end: cold `mylang check` of the 191k-line project and its helper-edit loop each at most 1.05× the Zig parser's; both in an exclusive timing window; worker start cost reported |
| G3 edit loop | a one-line `parser.my` edit to a ready development component takes at most a one-line `parser.zig` edit to a rebuilt compiler, measured the same day |
| G4 incremental | syntax-cache hit counts identical in both modes on the 40-edit cohort; test receipts unaffected |
| G5 qualification | the worker's failure inventory of lane B passes in component mode |

## 7. After stage 1 (outline)

| Stage | Boundary | Notes |
| --- | --- | --- |
| 2. Declarations and type interface | declaration and signature tables | the next most self-contained piece; 2.1k- and 1.3k-line pilots on the bootstrap branch |
| 3. Bodies, generics, effects, origins, contracts, incremental retention | the typed program | the long pole: about 25k lines of Zig; the 33k-line `body_check` component is reference material |
| 4. Lowering to Core IR | the `ir_snapshot` wire form, checked by canonical digests and `verify_ir` | after this the Zig front end is gone (H1 of the 12 October plan) |
| 5. Back end | Core IR in, Core IR or LLVM text out | last, or never; performance-critical |

Each gets its own plan, written from stage 1's measurements of throughput,
worker cost and diagnostics parity, and each inherits S11 and S12: its section
has a Zig twin and a 1.10× row, and its gaps go to lane P as language fixes. Back-end tests that build from source text
couple the back end's gate to the front end. Converting them to Core IR inputs
decouples the two in either language. It is worth doing before stage 3.

## 8. Agents and workflow

- Codex implements the plan (U5) under the operating rules and the launch
  instruction of §12. Lanes run in their own worktrees, landing in two tiers,
  through build slots, with no pushes and no broad process kills.
- Friction from writing compiler code in Selka goes to the selka-projects ledger
  as its own lane (`ledger/S.md`, `FR-500` to `FR-599`), with `# FR-NNN:`
  markers on workarounds, so stage 1 doubles as the ladder's largest project.
- File ownership follows §5's lane table; lanes B and G both touch
  `component_launch.zig` and run in that order.

## 9. Risks

- **Tree-shape churn.** Any `ast.zig` change during P1 to P3 changes the
  payload. S1's layout test makes it visible at once; S8 makes the author fix
  both sides.
- **Diagnostics parity is the long tail.** Byte-equal trees come early;
  message text, notes, fix edits and ordering for 40 codes take the time.
- **Throughput is the largest risk.** The October pilot ran 6× to 20× the Zig
  parser, mostly from its profile (string kinds, an untyped value pool, -O0
  seed builds) and per-exchange launch cost. The causes were never separated.
  This plan's design removes the profile limits and the value graph, and the
  syntax cache keeps unchanged files from reaching the component. No
  well-designed Selka parser has been timed yet. S11 turns each gap into a
  language fix, so the risk moves to lane P's throughput: the stage's flip
  waits on G2(a). Some causes may need decisions the user owns (§11).
- **Field borrows.** A parser's natural state is one record of several tables.
  Checked ownership rejects passing two of its fields as `mut` in one call
  (FR-107, FR-350). Until the user decides those shape items, the code passes
  the whole state as one `mut` parameter, and each workaround carries a
  `# FR-NNN:` marker.
- **Worker lifetime.** A resident process adds hang and leak modes. G5 and
  kill-and-reap are mandatory. Test binaries start one worker per process, not
  one per test.
- **Trusted sources.** Embedded standard modules are parsed with
  `trusted_intrinsics`. The worker must carry that flag, and parity must cover
  `src/stdlib`.
- **Seed builds take time.** A re-seed builds a ReleaseFast compiler (minutes).
  S7 keeps it out of the edit loop.

## 10. Calendar (estimate)

P0 about a week of lane time with four lanes in parallel; P1 one to two weeks;
P2 about a week; then 14 days of default-on shadow before P3. Without
performance work, about four to six weeks to delete the Zig lexer and parser.
Lane P's work is the unknown: the October pilot's gap suggests several language
fixes before G2(a) holds, each sized by its micro benchmark. The gates decide,
not the calendar.

## 11. Decisions (all taken 19 October)

1. **U1.** The plan is adopted. Its architecture is the 12 October plan's H1,
   H3, H4 and H5, with H2 restricted to one stage (S4). H6 to H8 are deferred,
   except the inventory (S10).
2. **U2.** The stage-1 contract is the existing `StoredSyntax` payload.
3. **U3.** Selka gets standard input, so programs can pipe stdin to stdout.
   The spelling is in §5, lane B.
4. **U4.** The shadow rules hold: both parsers change in one commit while
   shadowed, and the Zig parser is deleted after 14 days without a mismatch.
5. **U5.** Codex implements the plan.
6. **U6.** The lexer and parser are written fresh to S3's design. Only the
   pilots' tables, fixtures, corpus lists and qualification inventories are
   taken.
7. **U7.** Work starts after the project ladder closes.
8. **U8.** Each ported section is kept within 1.10× of the Zig code it
   replaces by fixing the language (S11, S12, lane P).

## 12. Operating rules and launch instruction for Codex

The default is **decide, log, continue**. Write every decision to
`experiments/selfhost-stage1-20261019/DECISIONS.md`: the question, the options,
the evidence, the choice, and whether it can be reversed. Commit at every step,
with a progress section in `experiments/selfhost-stage1-20261019/status.md`, so
the run can be inspected without interrupting it. Investigate and fix a gate
failure within the run, for up to about 6 to 8 h. Early measurements, the P1
spike included, are checkpoints; only the final ones bind.

**Hard stops.** Stop and ask only for:

1. A shape, ownership-rule or capability change, or anything that reverses or
   pre-empts a decided item (the 13 October decisions, waves 2 and 3). The
   `Input` capability exactly as §5 specifies it is approved; any other change
   to it is a stop.
2. Relaxing a gate on `main`, G1 to G5, or S11's 1.10×, or retiring or moving a
   verification group. Measuring one better is allowed.
3. A broken premise. For example, the Zig parser's payload is not
   deterministic, or `StoredSyntax` cannot carry something the parser must
   return.
4. A failure that cannot be fixed within the bound.
5. Anything outside this plan's branches: pushes, `origin`, `claude/*` and
   `projects/*` branches, Claude worktrees, another active lane's tree. The one
   exception is the selka-projects repository, where this plan may write
   `ledger/S.md` and its index rows.
6. Resources: free space on `/` under 25 GB, or the machine swapping.

**Branches and authority.**

- Integration happens on `selfhost/stage1`, in the worktree
  `~/ai/canopy/mylang-selfhost`, branched from `main`. Each lane gets its own
  branch (`selfhost/a-oracle`, `selfhost/b-input`, …) in its own worktree,
  which it claims with `git worktree lock --reason`.
- Fast-forwarding `main` to a `selfhost/stage1` tip is authorized when that tip
  has passed `python3 scripts/verify_cache.py --zig "$ZIG" --profile complete`
  and `main` has not moved since the batch's base. Do it only in the primary
  checkout, with `git -C ~/ai/canopy/mylang merge --ff-only selfhost/stage1`,
  after `git -C ~/ai/canopy/mylang status --porcelain` prints nothing. If `main`
  has moved, merge it into `selfhost/stage1`, verify again, then fast-forward.
- The flip of P2 is authorized when G1 to G5 hold. Record the measurements in
  `DECISIONS.md` and the date in `selfhost/ownership.json`.
- The 14-day shadow outlasts the run. Prepare P3's deletion on
  `selfhost/stage1-delete` and leave it unmerged. A short follow-up run lands
  it once the inventory shows 14 days with zero mismatches.
- Lane P changes the compiler for performance. Each of its fixes passes the
  parity and runtime suites as well as the gates, and a fix that changes what
  a program means is hard stop 1.
- **Wave 3 goes first** (the user's decision, 19 October;
  `docs/audits/language-wave3-plan-2026-10-19.md`).
  - Lanes A, C and D may run at the same time as wave 3.
  - Lane B (standard input) starts after wave 3's W1 and W3 have landed on `main`.
  - P1 and lane P start after wave 3's stage B has landed, because lane P and
    wave 3's W4 change the same Core files.
  - Check `main`'s log and `experiments/language-wave3-20261019/status.md`.
  - Do not edit the files wave 3 owns while it runs, and merge `main` as its
    batches land.

**Machine rules from `CLAUDE.md`.**

- Every compiler tree runs `source ~/.config/mylang/dev-env.sh` first.
- Builds and focused tests go through `scripts/build-slot.sh build …`, and
  timing runs through `scripts/build-slot.sh timing …`.
- `scripts/verify_cache.py` owns its own admission. At most four agents build
  the compiler at once.
- Caches, `TMPDIR` and install prefixes go under `~/.cache/`, never `/tmp`.
- Every behavioural change under `src/` ships with a test change in the same
  diff (Guardian's `change-classification`). `SPEC.md` is frozen and needs no
  new bullets.
- Keep committed evidence under 10 MB. Large logs stay in `~/.cache`.
- Never kill a process this run did not start, and never use broad `pkill`
  patterns.

**Finish** with `experiments/selfhost-stage1-20261019/REPORT.md`. It covers:

- G1 to G5 with their measurements;
- every S11 row before and after;
- each lane P item with its micro benchmark;
- the friction filed in `ledger/S.md`;
- lines added in Selka and to be deleted in Zig;
- the deletion branch's state;
- a first sketch of stage 2's boundary and its parity rows.

```text
You are implementing docs/audits/selfhost-plan-2026-10-19.md on main in
~/ai/canopy/mylang: stage 1 of incremental self-hosting (the lexer and parser).
Read the plan fully, then CLAUDE.md, then the 12 October plan it amends. Decide,
log in experiments/selfhost-stage1-20261019/DECISIONS.md, and continue; stop
only for the hard stops in section 12. Create the worktree
~/ai/canopy/mylang-selfhost on branch selfhost/stage1 from main. Wave 3
(docs/audits/language-wave3-plan-2026-10-19.md) goes first: run P0's lanes A, C
and D now; start lane B only after wave 3's W1 and W3 are on main; start P1 and
lane P only after wave 3's stage B is on main (check main's log and
experiments/language-wave3-20261019/status.md). Start P1 with the throughput
spike, and open lane P from its first row over 1.10x. Write the lexer and
parser fresh; take only tables, fixtures, corpus lists and qualification
inventories from codex/selka-bootstrap-20261011, and read it with git show,
never by checking it out over another tree. File friction from writing compiler
code in Selka to ~/ai/canopy/selka-projects/ledger/S.md (FR-500 to FR-599).
Never push. Fast-forward main only from the primary checkout after a green
complete verification, as section 12 says. Flip the default when G1 to G5 hold,
and prepare the deletion on selfhost/stage1-delete without merging it. Commit at
every step with a progress section in status.md. Finish with REPORT.md.
```
