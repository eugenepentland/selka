# Capabilities and allocation contracts: how it works

Implementation detail moved out of `docs/effects.md`, under the same headings.

## Allocation contracts

A promise is judged on the body the build emits for the function, not on a
simplified copy of it. A function that something else calls runs over borrowed
views of its `str`, `bytes` and list parameters, so `text[i]`, a slice of a
parameter handed to another `@noalloc` function, and a loop over the bytes of a
`bytes` parameter keep the promise, while a call that has to copy the borrowed
text into an owned block (a runtime helper with no span form) breaks it. The
check lowers the function as such a callee and runs the same lowering passes and
ownership expansion a debug build runs; the optimizing passes of `--release` and
`--optimize-debug` only remove allocations from it, so debug and release builds
accept the same programs.

## Mutation contracts

Private helpers derive a return-origin bound from their bodies for ownership
optimization; it does not change the value rule seen by callers.

## Deterministic stand-ins

Real authority reaches a body through its parameters. A function without a
`Clock` input can build a simulated clock. Tests receive deterministic stand-ins
for supported capability parameters; a possible live `Host` input prevents
persistent test receipt reuse. A test with unresolved callback targets also
executes without persistent reuse.
