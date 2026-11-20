# SIMD: how it works

Implementation detail moved out of `docs/simd.md`. The guide keeps the user-visible rule.

## Lowering

A `Simd[T, N]` is an LLVM `<N x T>` in SSA. Elementwise arithmetic is one `fadd`,
`fsub`, `fmul`, `fdiv` or `fneg` on the vector, and a comparison is one `fcmp` that
answers `<N x i1>`. A lane read is one `extractelement`, after the same bounds check
an array index runs. Passing a vector to a function or returning one does not
spill it: the vector crosses the call in its registers. In memory a float vector is
its lanes in order, and a mask is spilled lane by lane, because LLVM packs an
`i1` vector into bits.
