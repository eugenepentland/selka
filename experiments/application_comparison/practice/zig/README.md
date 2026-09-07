# Draft Zig preparation exercise

`starter/` is the participant project; `solution/` is coordinator-only. Both use
Zig 0.17.0-dev.1683+5ceec001b and standard-library I/O plus a local helper module.
Only the three specified expressions differ between their source files.

Run `python3 experiments/application_comparison/practice/zig/test_cli.py` from
the repository root to compile the solution, test exact stdin/stdout behavior,
and verify the starter's unresolved name and remaining two behavioral defects
using temporary copies. This test requires the installed toolchain at
`/home/epentland/.local/bin/zig`. It does not run Guardian or modify a baseline.
These construction checks are not comparative trials or a reviewed curriculum.
