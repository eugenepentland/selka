# DL-7: a map of the compiler source (13 November 2026)

Stage 7 of `docs/audits/compiler-dev-loop-plan-3-2026-11-12.md`, by lane DL-7 (Sonnet 5.5). **What landed:**
`docs/tooling/compiler-map.md` (258 lines, none over 120 characters): 18 pipeline stages with the function to open
first, five recipes (a library function in three shapes, a diagnostic, a statement form, a Core instruction, a flag),
where each area's tests are with the fastest command, and what is dead or frozen.

**How each recipe was derived and tested.** Three commits of 2 October to 13 November give a recipe's files (what they
share; the rest is marked optional). A fourth commit, not used for it, is compared: `dl7_recipe_check.py` reads the
recipes off the page and counts the files that commit touched which no step names. File lists and output:
`~/ai/canopy/mylang-evidence-archive/experiments/dev-loop-audit-20261112/DL7/` (`recipe-commits.txt`,
`recipe-check.txt`).

| Recipe | Derived from | Fourth commit | Missed |
| --- | --- | --- | ---: |
| a1 library function, Selka body | 4e926b92d6 82627b6d91 3452b23a04 | fdd6136fc1, 17e4ec6e84 | 0, 0 |
| a2 host call (`Filesystem`, `Process`) | e6948446a4 7c188f6360 0cb4221085 | 2577b7a6e2 | 2 |
| a3 C runtime helper | cec29ffe8d 6f8a115bd9 ab3d10b31f | f352b45e1b | 0 |
| b diagnostic | 6e5416a64b fff7b16347 734515c3ea | ca53389210, 928405632e | 0, 3 |
| c statement form | 31aa2ca803 5b1d599886 2c887cfc3b | abaa01adf9 | 0 (4 without optional steps) |
| d Core instruction | 83a34d66ad 5c139d5a61 fee0a76968 | 7c43adc2c9 | 9 (1 after recipes a and b) |
| e command-line flag | 84579310f4 c5e21468b5 c3fb63b072 | a302d1a7d2, 363a243f4b | 3, 0 |

The misses are each commit's own subject: a2 `docs/tooling/runtime-budgets.md` and `core_test.c`; b a parser rule
(`frontend_patterns.zig`, `ast.zig`, a test); d eight files of the simd library function that recipe (a) names, and
`interfaces.zig` (a new generic type); e the three files the flag controls. First pass, before I read the misses: a2 6,
a3 6, b 8 on `ca53389210`, c 3, d 14, e 3 and 2. I added what every such change needed (full runtime paths, the caller
builders, the Core test home, the expression checker, the `check` flag's files) and nothing for one commit's subject.
Recipe (d) is the nearest to the Stop: 25 paths, about 14 unconditional, 11 for a new typed node. Not a Stop.

**Findings that shaped the map.** (1) Six files name all 108 `Op` variants: `ir`, `verify_ir`, `ownership_ops`,
`emit_llvm` and two Lean files; two of the four Core op commits also added a typed node, and seven files name all 54
nodes. (2) No commit since W10 added a `builtin func`: that line of (a) is from W10's diff, untried on a fourth commit.
(3) The six weeks added no statement tag except in the 9 October syntax rewrite, so (c) adds the files that name every
tag (`ast`, `parser`, `generic_bodies`, `local_qualifiers`, `quality`, `sema_statements`) to what the commits did.
(4) Gates found: `doc-coverage` (every stdlib export named and exemplified), `reference_test` (a printed code has a
sorted row), `syntax_dump_test` (`syntax_layout.txt`), `lazy_readers_test`, `STDLIB-COUNT-1`. No test reads a row of
`docs/tooling/fix.md` or of the Core op table in `docs/design/ownership-certificates.md`.

**The test.** `tests/compiler_map.py` runs inside the existing gate action `goals_register` (`goals_register.py --map`,
passed in `build.zig`), which already reads documentation and checks the paths it names, so no new action. Over the
page's backquoted spans outside fences: a path must exist (`<name>` and `*` need a match); `` `path: name` `` must name
a function the file declares (`fn`, `func`, `def`, a C definition, a Lean theorem; comments left out); a command that
names a path is checked; at most 300 lines of 120 characters; every named file is an input of the action
(`build_test_inputs.zig` gained `src/**/*.c`, `src/**/*.my`, the manifest, the layout, the fix corpus, `test/core/`).
The real page: 281 paths, 58 functions. `tests/compiler_map_test.py` (16 tests, run in `verification_cache`) shows that
a renamed file and a renamed function each give `docs/tooling/compiler-map.md:LINE: ...`; `goals_register_test.py` +2.

**Open.** The edit check selects `test-goals` for the page and the driver only, so a rename is learned at the gate;
`selfhost/README.md` still describes the retired QBE back end.
