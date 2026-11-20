# Binary64 floating point: how it works

Implementation detail and measurements moved out of `docs/floating-point.md`. The guide keeps the user-visible rule.

## Zig-exact log10, exp, atan2 and pow_float

Each is the algorithm Zig runs, operation for operation (musl's `log10`, `exp` and `log` as Zig's `compiler_rt` carries them, `atan` and `atan2`, and Go's `pow`), written in Selka with no reordering and no fused multiply-add; none calls the C library, whose results differ from Zig's in the last bit for some arguments.

`tests/lang/math_zig_exact.selka` checks 1,674 of the 256,712 results the reference capture holds, and
`experiments/g3-pre-s1-fixes-20261105/math/` has the generator, the Zig program that captures the results and the
Selka program that compares every one of them.

## Zig-exact ln, atan, acos, asin, tan, expm1, sinh, cosh, tanh, cbrt, sin and cos

As with the four above, each is the algorithm Zig runs, operation for operation (the table-driven `log` of `compiler_rt`, musl's `atan`, `acos`, `asin`, `expm1`, `sinh`, `cosh` and `tanh`, FreeBSD's `cbrt`, and `compiler_rt`'s `sin`, `cos` and `tan` with their `__sin`, `__cos` and `__tan` kernels), written in Selka with no reordering and no fused multiply-add; none calls the C library, which differs from Zig in the last bit for 3% to 55% of the arguments depending on the function.

The argument reduction is Zig's `rem_pio2`, the Payne-Hanek reduction included (`rem_pio2_large`, from the 690-word table of 2/pi), so every finite argument up to the largest `float` is reduced without a trap: `math.sin(1.0e300)` and `math.cos(1.7976931348623157e308)` answer Zig's bits.

`tests/lang/math_zig_exact.selka` checks 2,969 of the 1,201,814 results the reference capture holds, and
`experiments/math-exact-20261106/` has the Zig program that captures the results (`capture.zig`), the Selka program that
compares every one of them (`verify_math.selka`) and the script that runs both (`run.sh`).

## Intrinsics and the execution environment

Validation: focused Zig tests cover ties, subnormals, infinities, canonical NaNs,
signed zeros, checked conversions, constants and library allocation failures.
These tests establish behavior on the tested host, not certification of every
native target.

## NaN payloads

Canonicalizing at these points instead of after every operation keeps float loops free of a compare, branch and call per operation, and results stay identical across machines, because a NaN is canonical before anything could see that two processors produced different payloads.
