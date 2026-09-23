# Language-level guest tests

These are the unit root's guest-program tests moved out of `src/root_test.zig`
and into `.my` files run by `mylang test`. A hand-migrated file is one area and
one native program, named after the Zig file it came from
(`python_collections_test.zig` becomes `python_collections.my`), so per-test
receipts and `--affected` stay per area. Files under `migrated/` are generated
area entries: `<area>.my` imports one `<area>_case_N.my` module per moved Zig
test, and each case module keeps its original guest program verbatim behind a
`public def program() -> int`. The case modules declare no tests, so the
directory runner does not run them as programs of their own; the area entry
imports them and holds the tests that assert `cN.program() == <expected>`. Both forms give every
test its own receipt, so an unrelated edit no longer rebuilds a whole Zig root,
and one program per area keeps the directory fan-out cheap.

Run the whole suite through the build:

```console
$ zig build test-lang
```

or directly, which is what `test-lang` runs:

```console
$ zig-out/bin/mylang test tests/lang --cache-dir .mylang-cache/lang-tests --gc-stress
```

The directory runner selects every program, fans the programs out across the
machine's cores, and reuses each successful test from its receipt, so an
unchanged rerun executes only the tests whose receipts the runner could not
adopt and costs a fraction of the first run:

```console
$ zig-out/bin/mylang test tests/lang --cache-dir /tmp/lang-cache --gc-stress
passed python_collections::test_inferred_literal_indexing_negative_indices_and_append
...
171 passed, 0 cached, 0 failed, 0 skipped across 30 programs
$ zig-out/bin/mylang test tests/lang/python_values.my --cache-dir /tmp/lang-cache --gc-stress
cached python_values::test_python_values_unicode_slicing_clamps_endpoints_and_returns_independent_text
...
0 passed, 7 cached, 0 failed, 0 skipped
```

A test whose receipt the runner cannot adopt (for example one that mutates a
record field) is re-executed and reported as `passed` instead of `cached`, so
the `passed`/`cached` split is the honest per-test signal.

`--gc-stress` is the run-wide form of the `--gc-stress` argument the Zig root's
`native_execute` tests pass to a guest: every collected test runs with the
runtime's stress collector. Without it the migrated tests would lose that
coverage, so the build step always passes it.

## The `migrated/` programs

A generated file in `migrated/` is a complete guest program from one Zig test,
followed by the test function that asserts its exit value. Keeping the program
verbatim means the migration cannot change what the test asserts, and one
program per test removes every top-level name collision between tests. The
hand-written area files are still the place to group several tests that share a
program; the generator only moves a Zig test whose whole body is a sequence of
value assertions so it cannot silently drop a generated or diagnostic case.

## Converting one Zig test

1. One `.my` file per Zig test file, starting with `module <file stem>`. It
   needs no `main`: the directory runner runs every file that declares a test
   and that no other program imports, and fails the run, naming the file, if a
   test-declaring file is loaded by no program.
2. One `public def test_<name>() -> bool` per Zig `test "..."`. The runner
   asserts `true`, so turn the Zig helper's expected value into a comparison
   inside the guest.
3. Copy any `// spec:` or `// spec-case:` tag above the Zig test to a `# spec:`
   or `# spec-case:` line directly above the `.my` test. Guardian reads both
   spellings, so coverage moves with the test.
4. A Zig test whose body only compiles or runs `native.run`/`runWithOptions`
   with one expected value is a value test and moves. A test that expects a
   compiler diagnostic (`expectError`, `expectMessage`, an `E_*` code), a
   runtime trap (`trapped()`, `result.trap.code`), a non-value assertion on
   `compilation.statistics`, or a provider/capability fixture stays in Zig.
5. Delete the Zig test in the same change that adds its `.my` twin. Two
   runners disagreeing is worse than one; the Zig test count must drop by
   exactly the number of tests moved.

Record every helper (`def`, `class`, `record`, `union`, `result`, `enum`) at the
top level of the `.my` file. Names are program-wide, so a helper that appears in
more than one Zig test needs a distinct name per test (for example
`Point` and `PointWriteback`).

## What stays in `src/root_test.zig`

The full rule, with the per-test backlog of Zig tests that still belong under `tests/lang`,
is `docs/tooling/test-layout.md`. In short:

Diagnostics, caches, projects and compiler internals; trap expectations until
`cases.json` can express one; effects and providers that need a sibling
manifest; and any test that asserts on `compilation.statistics`, reuse counts or
emitted-unit facts rather than a single guest value. The remaining Zig tests are
sharded as before.

## Migration decisions (2026-09-18)

Wave 1 moved 124 tests and stopped on the cold-cache measurement: the cold unit
root measured **319 s** after the move against the plan's 300–351 s baseline, so
removing value tests did not pay for itself on that axis. The per-edit inner
loop is a different axis, and `docs/tooling/test-layout.md` reopened a backlog
of the remaining Zig tests that qualify. A first audit pass moved 11 more whole
value tests (`python_syntax_test` 5, `compiler_test` 2, `const_lengths_test` 2,
`float_operations_test` 1, `unit_test` 1) to `tests/lang/backlog/`, one program
per moved test; the unit root is now 1102 tests. The page marks the 36 backlog
tests that the audit found assert on `status`, `stdout`, traps or checked
compiler records and therefore stay in Zig.

Trap tests stay in Zig. `mylang test` treats a trap as a failure and never
reuses a trap result, so `expect_trap` would exist for roughly 60 tests alone,
and sharding already hides their serial cost. Reopen only if a runner feature
earns its keep for other work; this is a decision, not a pending item. A whole
case that is one trap or one rejection can instead go to `tests/reject` and its
`zig build test-reject` runner; see `docs/tooling/test-layout.md`.

Effect and provider tests stay in Zig. A directory run rejects `--cases`, so
each entry would need a sibling manifest and its own build step, and the unit
root's remaining fixtures are Zig callbacks rather than data. Reopen if a
non-unit caller needs provider substitutions.

`tests/lang` cases that exercise `mutation` or `output` effects reuse their
receipts like every other passing test (`[NATIVE-TEST-2]`,
`[NATIVE-TEST-OUTPUT-1]`): a passing test's captured output is discarded, so
there is nothing a re-execution would show. Only a test with a genuinely
external effect (clock, entropy, environment, files, network) re-executes. The
migrated sources are warning-clean, so a warning never explains a missing
receipt.
