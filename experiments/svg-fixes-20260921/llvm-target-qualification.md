# LLVM target-policy qualification

Run from the repository root after the pinned Zig toolchain is available:

```sh
MYLANG_ZIG=/absolute/path/to/zig \
  python3 experiments/svg-fixes-20260921/qualify_llvm_target.py
```

The script asks the selected Zig driver for its native and `-mcpu=baseline`
cc1 policies, translates a real QBE 112-byte copy through the production LLVM
adapter into LTO bitcode, links each policy into an executable, executes a byte
equality check, and retains LLVM IR plus disassembly beneath
`.tmp/svg-fixes-20260921/llvm-target-qualification/`. The JSON report records
the exact CPU/features, emitted attributes, bitcode magic, copy lowering, tool
version, and artifact hashes.

The retained 2026-09-21 run used Zig `0.17.0-dev.1683+5ceec001b`. Both
executables printed `ok`, and both intermediate objects began with raw LLVM
bitcode magic `42 43 c0 de`. The resolved native policy included `+avx,+avx2`
and lowered `copy112` to four YMM/XMM `vmovups` load/store pairs. The synthetic
portable baseline explicitly disabled AVX/AVX2 and lowered the same copy to
seven XMM `movups` load/store pairs. The retained IR contains the corresponding
`target-cpu` and full ordered `target-features` attributes in each case.
