# Modules: how it works

Implementation detail moved out of `docs/modules.md`. The guide keeps the user-visible rule.

## Headerless scripts

Generated `.api` metadata retains its module identity header.

The generated entry stops after the first failed grant instead of reporting every missing capability.

## Re-exports

The facade adds only a public name. A reference through it resolves to the
declaring module's identity, so the declaration keeps one implementation, one
contract and one schema entry, and the project fingerprint reports the facade
name.

## Checking every module of a project

whatever it is called (`selka check build` checks the modules of a folder called `build`, named `build.NAME`). A file whose name is not a module name (`bad-name.selka`) is skipped and named on standard error. The check loads all the modules through
one generated entry, `selka_check_all`, which exists only in memory (a project that has a module of that name is
refused with exit status 2), so the work is shared across the project and a second run is served from the caches as a
second `check ENTRY` is. A test file keeps its access to the private declarations of the module it tests, and the
generated entry reports no warnings. The count in the last line is the number of project modules loaded.

## The project root and `selka.json`

A hidden-folder entry is named `__hidden_tmp.scratch` inside the compiler, and a test report shows it as `.tmp.scratch_test::test_x`.
