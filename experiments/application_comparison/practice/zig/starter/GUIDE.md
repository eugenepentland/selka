# Zig preparation guide

Use the supplied Zig 0.17.0-dev toolchain. From this directory, compile with
`zig build-exe main.zig -femit-bin=/tmp/practice-zig` and run
`printf m | /tmp/practice-zig`. In an isolated participant session the tool may
be installed as `/tools/zig/zig`; use that path in place of `zig`.
The isolated command runner gives each command a fresh `/tmp`. Compile and run
within the same shell command, for example:
`/tools/zig/zig build-exe main.zig -femit-bin=/tmp/practice-zig && printf m | /tmp/practice-zig`.

Repair the unresolved-name diagnostic first: Zig checks this reachable branch
at compilation, even when another input would be used. Read the diagnostic's
file and line, and look for the existing named constant in that module.

`@import("helper.zig")` imports a local module; `pub fn` exports a function.
Calls use the imported module name followed by the function name. Integer
arguments and results here are explicitly typed `i64`.

`error{InvalidDigit}!i64` is an error union: parsing either returns an integer or
an error. `catch` explicitly chooses the value to return on failure. Follow the
exercise contract when choosing that fallback. `try` propagates operational I/O
errors from `main`. Slices represent the exact input bytes; do not trim input.

Check all three command branches against the provided public cases. This
starter has exactly three deliberate defects. Compilation alone does not prove
that the behavior matches those cases. Application dependencies are limited to
the Zig standard library and the local helper module.
