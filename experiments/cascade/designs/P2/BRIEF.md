# Designer brief — generalised reuse (arm P2, the control)

You are designing a small S-expression reader written in mylang. `project/` holds
the current implementation, its guest tests and its `CONTRACT.md`; `bin/mylang`
is the installed compiler; `docs/` is the language documentation.

Your job is to make the reader **maximally reusable**: turn the assumptions it
happens to bake in into parameters, hooks and policies, so that the same code can
serve readers and printers that differ from this one in as many ways as possible.

Directions to work in — take them as far as the code allows:

- dialect parameters, so a caller can select comment syntax, atom characters and
  number conventions rather than editing the lexer;
- pluggable number policies, so the scale table, the unit table and the
  normalisation rule are supplied rather than compiled in;
- a callback-driven printer, so a caller can choose the layout policy, the
  indentation, the number formatting and the line-ending behaviour;
- whatever else generalisation suggests: configuration for the depth cap, for
  the string escape rule, for the token set.

Breadth is the point of this arm. Where a default keeps the current behaviour,
supply the current behaviour as the default.

## Invariants

- The public surface stays: `main.my`, the modules `sexpr.ast`, `sexpr.tokenizer`,
  `sexpr.parser`, `sexpr.printer`, and the public names they export today. Other
  code — and the tests you were given — import those names.
- The reader's observable behaviour stays: the same tokens, the same AST values,
  the same canonical renderings, the same diagnostics, with the defaults in
  place.
- `project/tests` — all 79 tests — must pass unchanged. If a test would have to
  change, the default behaviour changed and the design is wrong.

## Deliverables

1. The generalised `project/` in place: it must pass

   ```sh
   ../bin/mylang test project/tests
   ../bin/mylang run project/main.my -- <file.sexp> --render
   ```

2. `DESIGN.md` at the top of this working copy: the extension points the design
   adds, what a caller can now vary without touching the reader, and what each
   new parameter defaults to. Keep it to a page; say what is true of the code as
   it now stands, not what you intended.
3. A short final message: what you changed, and the exact commands you ran with
   their results.

Work only inside this working copy: do not read or write anything outside it —
nothing else is needed and nothing else is part of the task. Do not spawn
subagents.
