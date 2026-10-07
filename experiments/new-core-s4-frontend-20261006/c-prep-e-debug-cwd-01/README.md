# Actual S4-E Debug unit across private working directories

The immutable actual S4-E 5994 Debug `app.my` unit has LLVM SHA256
`1c40b584bc71793ebd6e8a1d597b03c65677dd33857bed2370293efed1363e48`
and `!DIFile(filename: "app.my", directory: "")`. Original E compiler SHA256
is `616ece995efec364e02fa592ecc883c0b10738a798b770571d72d8ceb6f89477`;
the copied original native recipe and its source receipt are recorded.

Both runs copied that exact LLVM into distinct private directories with the
same canonical input basename and `fresh.o` output basename. Each run used fresh
local and global Zig native caches. Every original semantic native flag stayed:
`cc -c -O0 -march=native -mllvm -x86-experimental-pref-innermost-loop-alignment=6
-Wno-override-module`. The actual compiler binary and both complete commands,
working directories, input/object sizes and hashes are in the JSON receipts.

Both compiles returned 0. Both complete 3,184-byte objects have SHA256
`d8dd5741be1e8c641748d89dec8810ff602a9203e1b8afeaf4006e4cfe7a0b37`.
The comparison used every object byte with no stripping or normalization.
Retained DWARF dumps identify `app.my` and omit `DW_AT_comp_dir`; a changed
private working directory did not enter this actual unit's debug bytes.

Canonical basenames are sufficient for this actual unit under its existing
flags. No stable debug-compilation-directory flag was needed or tested. This
does not replace future per-unit `--verify-cache` byte comparisons, nor establish
stability for native C/Zig source objects. Object files and cache trees remain in
the task-owned cache; their exact paths/hashes are retained here.

The admitted command acquired the shared CPU10 lock before its ordinary build
slot and ran away from CPU10, preventing overlap with timing. The initial
unadmitted waiter was canceled with an explicit ABORTED receipt and zero native
actions. No E source, protected baseline or production C implementation changed.
This is a correctness observation, not performance qualification.
