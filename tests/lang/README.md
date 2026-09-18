# Language-level guest tests

These are the unit root's guest-program tests moved out of `src/root_test.zig`
and into `.my` files run by `mylang test`. A hand-migrated file is one area and
one native program, named after the Zig file it came from
(`python_collections_test.zig` becomes `python_collections.my`), so per-test
receipts and `--affected` stay per area. Files under `migrated/` are generated
area entries: `<area>.my` imports one `<area>_case_N.my` module per moved Zig
test, and each case module keeps its original guest program verbatim behind a
`public def program() -> int`. The case modules declare no `main`, so the
directory runner does not run them as programs of their own; the area entry
holds the tests that assert `cN.program() == <expected>`. Both forms give every
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

1. One `.my` file per Zig test file. Start it with `module <file stem>` and end
   it with `def main() -> int: return 0`; the directory runner treats a file
   with a top-level `main` as one program.
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

Diagnostics, caches, projects and compiler internals; trap expectations until
`cases.json` can express one; effects and providers that need a sibling
manifest; and any test that asserts on `compilation.statistics`, reuse counts or
emitted-unit facts rather than a single guest value. The remaining Zig tests are
sharded as before.
