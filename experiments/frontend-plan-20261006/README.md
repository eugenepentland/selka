# Evidence for `docs/audits/frontend-plan-after-new-core-2026-10-06.md`

These scripts were run from a session scratch directory. `SCRATCH` in the sources marks
that directory; set it to any working directory before rerunning.

- `classify_src.py` splits `src/` of a branch (`B` at the top) into front end, new core,
  old back end, tooling, tests and apps by `@import` closure from `sema.zig`,
  `parser.zig`, `lexer.zig` and `typed.zig`. It also groups the front end by role. Run it
  from the repository root.
- `count_spellings.py SCRATCH` counts lines matching each spelling's regex. It reads
  three corpora under `SCRATCH/corpus/`:
  - `eda/`: `git -C eda-bench archive codex/s4-eda-stage1 mylang`;
  - `lox/`: `git archive f44302d87 benchmarks/lox/ports/mylang`;
  - `stdlib/`: `git archive 2e4f0f512 src/stdlib`.

  The output is `spellings.txt`. These are regex counts, so they are approximate.
- `gen_program.py N OUT.my` writes the synthetic N-function program behind the
  compile-time numbers (50/200/800 functions = 757/3,007/12,007 lines).
- `ownership_rows.txt` and `ownership_tests_lang.txt` are the `mylang-core build --release
  --stats` ownership lines. They come from a ReleaseFast `mylang-core` built from
  `2e4f0f51`, run over 33 benchmark rows and over the 100 `tests/lang` programs with a
  `main` that build under the new core.
