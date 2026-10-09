# D6: Freeze the compiler/runtime boundary

Status: accepted.

## Rule

The self-hosted compiler owns lexing, parsing, resolution, type checking, typed
IR, lowering, and QBE text generation. `runtime-abi-v1` owns managed allocation,
traps, capability plumbing, process startup, and platform operations. QBE owns
machine-code generation. A thin Zig stage-0 launcher may locate resources and
invoke the compiler.

## Rejected alternative

Reject porting the C runtime, QBE, and platform startup merely to claim that all
code is self-hosted. Also reject allowing `.selka` compiler code to call arbitrary
Zig internals.

## Compatibility consequence

The ABI and resource manifest are versioned inputs to every bootstrap stage.
Boundary changes require an explicit ABI revision and parity work; frontend
changes within the boundary need no Zig rewrite.
