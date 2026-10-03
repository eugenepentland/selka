# Checked positive list indexes

The native emitter recognizes the exact checked negative-index normalizer followed by a plain list read. A single unsigned comparison between the original index and the current receiver length permits a positive read to skip the normalizer; a failed comparison enters the complete original code. The read still uses its original result protocol and source position. Negative indexes, checked cast/add failures, normalized bounds traps and counted execution retain the original lowering.

The certificate refuses byte and zero-sized element lists, managed elements, mutable/indexed receiver places, reference locals, hidden ownership/COW work, extra branch entries, and versioned or counted execution. A checked list capacity times element stride of at least two fits native size_t, so a valid list length is below 2^63 and the unsigned guard also proves that the signed index is nonnegative. Guest index expressions and receiver snapshot capture have already run.

This is a compiler candidate; central Lox instruction and wall-time receipts determine whether it improves the joined evaluator. It does not expose unchecked indexing or alter the VM bytecode.

## Validation and reproducibility

All commands ran in `codex-lox-parity-lowering-20261003`, based on `fd86729e`, with private `TMPDIR=$PWD/.tmp-lox-lowering/tmp` and `ZIG_GLOBAL_CACHE_DIR=$PWD/.tmp-lox-lowering/zig-global`. Commands below also used `scripts/build-slot.sh` for admission.

* `scripts/build-slot.sh build zig build test-units -Dtest-filter='positive index' --cache-dir .tmp-lox-lowering/zig-cache -p .tmp-lox-lowering/compiler -j2`: 16/16 passed, including four named tests and twelve mandatory test blocks. Native unaccounted execution covers zero, negative, minimum/maximum integer and empty-list traps with exact detail/stderr comparison against counted execution; COW snapshots and index callbacks replacing the receiver run under RC and stressed tracing GC. IL assertions cover managed-element and mutable indexed-receiver refusals.
* `scripts/build-slot.sh build .tmp-lox-lowering/compiler/focus/mylang test tests/lang/positive_list_index.my --release --rc-runtime --cache-dir .tmp-lox-lowering/positive-lang-llvm --json`: 3/3 passed.
* `scripts/build-slot.sh build .tmp-lox-lowering/compiler/focus/mylang test tests/lang/positive_list_index.my --mode ReleaseFast --gc-runtime --gc-stress --cache-dir .tmp-lox-lowering/positive-lang-qbe-gc --json`: 3/3 passed. These language test modes count steps; the native unaccounted tests above exercise the actual shortcut.
* `scripts/build-slot.sh build zig build -Doptimize=ReleaseFast -Dcompiler-only --cache-dir .tmp-lox-lowering/zig-cache-release -p .tmp-lox-lowering/compiler-release -j2`: passed, including the automatic Guardian gate. The compiler and adjacent QBE were copied into the immutable private `positive-release/bin` directory for central guest compilation.
* `scripts/build-slot.sh gate /home/epentland/ai/canopy/guardian-zig/zig-out/bin/guardian-check all . --gate`: 88 checks passed before final test additions; the commit hook reruns the gate on the completed source and notes.

The frozen ReleaseFast compiler SHA256 is `da94c579e03ffaab2e9d43a6d9119b529bbb01dab5085e7a3986a6ecd98912c6`, and its adjacent QBE SHA256 is `99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63`. The frozen compiler is `.tmp-lox-lowering/positive-release/bin/mylang`. The baseline compiler SHA256 is `45d05b554849bf3c12553549d9138556ba0204f9d59ba3aaa2ecb2327eb39ac4`.

The frozen compiler emitted 36 guarded sites across 26 functions of the joined Lox evaluator, including `vm::run`, frame byte/short readers, numeric/add helpers, scalar heap readers and table probes. `.tmp-lox-lowering/positive-joined-emitted.json` preserves that IL. Test/build/gate receipts remain under the private scratch directory; no performance workloads ran on the centrally reserved CPUs.

Guardian initially rejected an import cycle, a complex proof function and long boolean conditions. Shared certificate data and smaller proof predicates resolved all three findings. The parent task records this feedback in the required consolidated Guardian log.
