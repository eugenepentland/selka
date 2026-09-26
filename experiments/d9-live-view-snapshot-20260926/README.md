# Live-view mapping snapshot investigation

`divergence.my` is the unchanged minimal reproducer from the RC constructor
publication audit. `histories.my` prints all three values for snapshot-first,
owner-first, and sharing consumed before view creation, in that order.

The Python drivers preserve exact build commands, compiler/source SHA256,
stdout, stderr and counted RC traffic. Run them from the compiler worktree;
they name the frozen local compiler and scratch directory from the original
experiment. Adjust those paths when reproducing elsewhere. LLVM uses the real
LLVM backend with `--llvm-opt 3 --lto`, without a later `--qbe` override.

The compiler snapshot correction does not resolve the separately recorded
GC/RC sharing-history difference. See the linked audit and compressed raw
records; no expected output was inferred from a Boolean assertion.
