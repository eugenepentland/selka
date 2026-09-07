# Explicit integer operations

All operations take two operands of the same builtin integer type (or a generic `integer` type) and return that type. Arguments evaluate once, left to right. They also work in scalar module constants.

`bit_and(a,b)`, `bit_or(a,b)` and `bit_xor(a,b)` operate on the declared-width two’s-complement representation.

`shift_left(a,count)` discards high bits. `shift_right(a,count)` uses arithmetic sign extension for signed integers and zero extension for unsigned integers. Counts must be nonnegative and strictly smaller than the operand width; otherwise execution traps with `R_INVALID_SHIFT`. Constant evaluation reports a located `E_CONSTANT_ARITHMETIC` error.

`wrapping_add`, `wrapping_sub` and `wrapping_mul` reduce mathematical results modulo 2 raised to the declared width. `saturating_add`, `saturating_sub` and `saturating_mul` clamp to the declared type’s bounds. Existing arithmetic operators retain checked-overflow behavior.

The VM and native C backend use widened intermediates and explicit unsigned bit manipulation. Behavior does not depend on host overflow settings. Floating-point types are a separate stage.

Validation: `zig test src/integer_operations_test.zig` runs width-boundary, constant/generic, allocation-failure and located trap checks in Debug and ReleaseFast. `python3 tests/native_integer_operations.py --compiler zig-out/bin/mylang` executes all eight width boundaries and invalid counts in the VM and native C at `-O0` and `-O2`, with undefined-behavior sanitization enabled.
