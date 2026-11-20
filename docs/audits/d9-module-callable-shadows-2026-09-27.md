# Declared builtin callable names in modules

The combined RC gate at `685e2631` dropped `rc_plain_replacements.my` before
running its assertions. Its declared `replace` function parsed successfully,
but module name resolution rejected the keyword token and returned
`InternalError`. The accepted GC compiler reproduces the same failure, and
`module_names.zig` is identical between `main` and that integration checkpoint.

Reference normalization now accepts `len` and `replace` as the final callable
name, matching the parser's existing declaration rules. Qualifier segments,
visibility checks and other keyword restrictions retain their existing rules.
The common ordinary-name fast path is unchanged. Module tests cover local
shadows, imported shadows and an unrelated module's builtin `len`.

Validation on the Debug compiler with SHA-256
`e6200732a5a4fccb315abc3e06091d0c2c909f60d2a3e31df76bf15247eb2c2f`:

- Debug build: 12/12 steps; dotted-module tests: 20/20; existing declaration
  shadow tests: 12/12.
- The originally dropped guest file passes all three assertions under GC stress
  and counted RC, on QBE and LLVM O3/full LTO: 12 executed assertions, no cached
  results, failures or skips.
- Formatting: 2/2 steps. Whole-tree Guardian: 88 checks.

The [receipts](../../experiments/d9-module-callable-shadows-20260927/README.md)
preserve the old compiler failure, final runs and two corrected harness mistakes:
an unsupported colon-qualified fixture and a single-file JSON reader that
initially required an optional directory-only field. A zero-match spec-tag test
filter also failed correctly before the actual test-name filter was used.

The fresh combined full gate remains required. These focused results do not
change the failed verdict of the original `685e2631` gate or accept WP-4.
