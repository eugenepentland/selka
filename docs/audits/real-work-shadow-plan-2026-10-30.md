# Real work as the engine's shadow traffic (plan, 2026-10-30)

Status: accepted, 30 October 2026: the user took U1 to U4 at their defaults (§6) and asked to start. Written against main
deb15f427.

## 1. Why

The incremental engine's first consumer, the `mylang test` receipts, runs in shadow on main since deb15f427: for every
test the old receipts and the engine both decide, the old decision is acted on, and every disagreement is logged to
`~/.cache/mylang/engine-shadow/shadow.jsonl`. The active campaign (C2b1, C2b2) makes deliberate edits to every kind of
file and decides the switch (C2c1). Deleting the old receipt code (C2c3) waits for real use as well, because real work
makes edit patterns nobody scripts.

This plan makes that real use useful work. Writing Selka code test-first is the traffic the shadow most needs: every
red-then-green step is a verdict change, which is where an engine reuse would be a soundness failure, and every fix the
work finds in the compiler is a compiler edit followed by the suites. Three tracks, each split into steps of at most six
hours, each worth doing on its own:

- **S, self-hosting stage 1, started:** the first pieces of the accepted plan (`selfhost-plan-2026-10-19.md`), the
  oracle and corpus, standard input, and a Selka lexer spike measured against the Zig lexer.
- **L, standard library:** the open `stdlib` items of the friction ledger (`selka-projects/LEDGER.md`) and what the
  Selka tools of track T need.
- **T, tools in Selka:** the first developer tools moved from Python to Selka, run beside the Python originals until
  their outputs agree (step 4 of the engine plan, the outer layer).

## 2. Track S: self-hosting stage 1, the first pieces

The stage-1 plan moves the lexer and parser into Selka, with the live Zig parser as a byte-exact oracle over about
1,000 files. It was scheduled after the EDA port's G2 freeze (stream H); the port is paused, so this starts its
prerequisites and the lexer now (decision U1). Its rules hold unchanged: the Zig front end stays the reference, a gap
the port finds is fixed in the language (S11), and nothing is deleted in this plan.

| Step | Work | Est. | Who |
| --- | --- | --- | --- |
| S1a | `mylang dump-syntax FILE [--layout]`: the `StoredSyntax` payload and the parser's diagnostics in one framed form (stage-1 lane A); a test that an `ast.zig` field edit turns the layout test red | 4–6 h | lane |
| S1b | `selfhost/corpus.json` (the repository's `.my` files, the selka-projects root when present, the negative fixtures) and `selfhost/tests/syntax_parity.py`, which runs a candidate over the corpus against `dump-syntax`/`dump-tokens`; Zig against itself shows zero mismatches | 3–5 h | lane |
| S2a | Standard input: the `Input` entry parameter, `read`, `read_exact`, `read_line`, `read_into`, `input_from(bytes)` for tests, `R_INPUT` (spelling accepted on 19 October, stage-1 lane B), with `tests/lang` tests and docs | 4–6 h | lane |
| S2b | The framed component protocol over standard input and output, the host side in `component_launch.zig`, and a Selka echo worker; crash, timeout, oversize, malformed frame and early exit each fail closed | 5–6 h | lane |
| S3a | Selka lexer spike, part 1: `selfhost/frontend/lexer.my` for indentation, names, keywords and punctuation, tested against `dump-tokens` | 5–6 h | lane |
| S3b | Part 2: numbers, text and byte literals, comments, and the lexer's diagnostics over the negative fixtures | 5–6 h | lane |
| S3c | The lexer over the whole corpus (zero token mismatches) and its throughput against the Zig lexer on the same files, split by phase; every row over 1.10× becomes a `perf` item for the language | 3–5 h | lane |

The spike is an ordinary Selka program with Selka tests. Making it a component the compiler calls needs stage-1 lane C
(the `frontend-v1` source profile and the re-seed), which is not in this plan.

## 3. Track L: standard library

| Step | Work | Est. | Source |
| --- | --- | --- | --- |
| L1 | `args`: a command-line parser for Selka tools (flags, options with values, positionals, `--help` text, errors as values) | 3–5 h | track T needs it |
| L2 | `time` calendar conversion: civil date and time from Unix nanoseconds and back, RFC 3339 and HTTP date formatting and parsing | 4–6 h | FR-215 (an HTTP `Date` header is 30 lines of arithmetic) |
| L3 | An in-memory `Connection` for guest tests of socket code, following the existing capability stand-in pattern | 4–6 h | FR-221 (socket code has no guest tests) |
| L4 | `http.Error` kinds, so 413 and 431 are told from 400 by value, not text | 2–4 h | FR-211 |
| L5 | `gzip` and `deflate` decoding, enough to read the edit-check maps (`coverage-*.json.gz`) from a Selka tool; checked against `std.compress.flate` on the real maps | 5–6 h | track T, later tools |

Each module lands with `tests/lang` tests, a documentation section with a runnable example and a `features.json` entry.
Its speed is recorded but not held to the 1.10× rule while only debug builds matter (the user's ruling of 30 October on
the codec).

## 4. Track T: tools in Selka

| Step | Work | Est. |
| --- | --- | --- |
| T1 | `tools/selka/shadow_summary.my`, the port of `scripts/engine_shadow_summary.py` (171 lines): the same report over the campaign's logs, byte for byte; the coordinator uses it for the shadow review | 3–5 h |
| T2 | `tools/selka/gate_summary.my`, the port of `scripts/gate_summary.py` (292 lines), checked against `scripts/gate_summary_test.py`'s fixtures and the gate logs in the evidence archive | 4–6 h |
| T3 | A driver test that runs each Selka tool and its Python original on the same inputs and fails on any difference, so the two cannot drift until the Python one is retired | 2–3 h |

The engine plan's rule that outer-layer tools are built by the pinned stage-0 compiler cannot hold yet: the pin
(`selfhost/stage0-pin.json`, commit ef9281e36) predates the language these tools need. Until a new pin, they are built by
main's compiler and are not part of the gate (decision U2).

## 5. How the work feeds the shadow

- **Environment:** every lane's shells set `MYLANG_ENGINE_SHADOW_LOG=@user` and `MYLANG_ENGINE_VERIFY=16`; the gate and
  the edit check already do.
- **Test-first:** the lanes write the test before the code, so a red-to-green change is recorded for most steps.
- **Count, not days:** the soak that unblocks C2c3 is counted, not timed (decision U3). It needs at least 300 unforced
  `mylang test` runs from this plan's lanes, at least 50 of them after a verdict-changing edit, and at least 20 after a
  compiler edit. It also needs zero engine reuses of a changed verdict (`verdict_differs`), every soundness line
  explained, and the efficiency lines counted.
- **Checkpoints:** the coordinator reads the log after every two landed steps, with T1's tool once it exists.

## 6. Lanes, order and decisions

Two lanes beside the two already running (C on the campaign, B on F3), so at most four build-heavy agents share the
machine:

- **Lane E (new, Sonnet):** track S, in the order S1a, S1b, S3a, S3b, S3c, S2a, S2b. The lexer comes before standard
  input because it is pure Selka with the most tests.
- **Lane D (Sonnet, idle since F1/F4):** L1, T1, T3, then L2, L4, T2, L3, L5.

The coordinator reviews, gates and lands each step on main as before, and updates the roadmap chart: a new stage, "Real
work in Selka", one row per step.

Decisions for the user:

- **U1.** Start self-hosting stage 1's first pieces now, ahead of the EDA port's G2 freeze. *Default: yes.*
- **U2.** The Selka tools are built by main's compiler and stay out of the gate until a new stage-0 pin. *Default: yes.*
- **U3.** C2c3 waits for the counted soak of §5 instead of two calendar days. *Default: yes.*
- **U4.** The picks of tracks L and T. *Default: as listed; any FR from the ledger can replace one.*

## 7. Size

- **Track S:** 29–40 h.
- **Track L:** 18–27 h.
- **Track T:** 9–14 h.

The two lanes run in parallel, so about four to five days of elapsed time.
