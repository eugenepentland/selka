# Cold trap merging loses an inline caller

The new native regression builds the `looping` source in
`src/core/inline_origins_test.zig`, changing the initial list to `[1] * 1025`
so it stays on the heap. After release/verify passes, it replaces one cloned
ownership `is_unique` result by the ordinary IR boolean constant false. The
existing uniqueness-failure branch executes. This injects a failing compiler
premise without changing any IR operation meaning.

`program.ll` is the actual whole LLVM text captured before correcting cold
call merging. It contains the right `origin` scope with `inlinedAt main`, yet
the report names only `origin`. The compact DWARF/disassembly show LLVM merging
caller and callee traps with the same `0, 1` detail operands into one call:
the `origin` inline range ends before that call's PC. Runtime frame walking
therefore skips `main` as the presumed trapping frame.

The exact input compared with `notail` remains red. With `nomerge` on trapping
calls it reports both `origin` and `main at hand.my:1:288`. JSON captures command
arguments, runtime object digest and actual diagnostics. The input and corrected
input, compact program DWARF and main disassembly are retained. Native binaries
and complete runtime DWARF dumps remain untracked.

The production fix adds a call-site attribute to traps and assertion failures.
It changes no signature, record layout, instruction field or runtime behavior.
The focused regression verifies the caller as well as the exact callee.
