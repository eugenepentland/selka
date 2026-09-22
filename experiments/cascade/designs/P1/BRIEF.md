# Designer brief — representation (arm P1)

You are designing a small S-expression reader written in mylang. `project/` holds
the current implementation, its guest tests and its `CONTRACT.md`; `bin/mylang`
is the installed compiler; `docs/` is the language documentation.

Your job is a **redesign of the representation**, not a feature and not a
cleanup. Work by this policy:

- Find a representation or an invariant that makes several pieces of logic
  unnecessary. Prefer sharing a domain rule over sharing incidental syntax.
- Name, in writing, which callers benefit from each choice, which assumptions
  become guaranteed rather than checked, and which responsibilities stay
  independent.
- Check every claim against the actual callers and the tests. A claim that a
  table is now the single source of truth is only true if the other copies are
  gone.

Likely outcomes — these are directions, not a prescription, and a different
design that satisfies the policy is welcome:

- one unit/scale table read by the tokenizer, the parser and the printer, instead
  of byte predicates in one place, multipliers in another and a literal `"mm"` in
  a third;
- a span minted once by the lexer and carried everywhere a position is needed,
  instead of a second walk over the source to recover a column;
- tokens that carry decoded values and spellings, so the parser never rescans
  text to decide what a token is or how it was written.

## Invariants

- The public surface stays: `main.my`, the modules `sexpr.ast`, `sexpr.tokenizer`,
  `sexpr.parser`, `sexpr.printer`, and the public names they export today. Other
  code — and the tests you were given — import those names.
- The reader's observable behaviour stays: the same tokens, the same AST values,
  the same canonical renderings, the same diagnostics.
- `project/tests` — all 79 tests — must pass unchanged. If a test would have to
  change, the behaviour changed and the design is wrong.

## Deliverables

1. The redesigned `project/` in place: it must pass

   ```sh
   ../bin/mylang test project/tests
   ../bin/mylang run project/main.my -- <file.sexp> --render
   ```

2. `DESIGN.md` at the top of this working copy: the facts the design gives a
   single home, the callers that benefit, what is now guaranteed, and what you
   deliberately left independent. Keep it to a page; say what is true of the code
   as it now stands, not what you intended.
3. A short final message: what you changed, and the exact commands you ran with
   their results.

Work only inside this working copy: do not read or write anything outside it —
nothing else is needed and nothing else is part of the task. Do not spawn
subagents.
