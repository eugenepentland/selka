// calls: N ordinary calls to a two-argument leaf function that must not inline.
//
// Port of calls.zig: `#[inline(never)]` plays the part of Zig's `noinline`.
// Both operands of `%` are never negative, so Rust's `%` equals `@mod` in
// value. It is cheaper, though: the out-of-line `step` cannot prove `a + b`
// non-negative, so Zig's `@mod` keeps a sign fix-up that `%` never needs.
// `(a + b).rem_euclid(1000003)` is the op-for-op floor mod (see README.md).
use std::hint::black_box;

#[inline(never)]
fn step(a: i64, b: i64) -> i64 {
    (a + b) % 1000003
}

// Prints one decimal value and a newline, like common.zig's `emit1`. The value
// is taken by value on purpose: `println!("{}", total)` inside `main` borrows
// `total`, and an address-taken accumulator can change the kernel loop's code
// (it keeps bytes_scan's loop scalar and branchy; see README.md).
#[inline(never)]
fn emit1(value: i64) {
    println!("{}", value);
}

fn main() {
    let n: i64 = black_box(30000000);
    let mut total: i64 = 0;
    for i in 0..n {
        total = step(total, i);
    }
    emit1(total);
}
