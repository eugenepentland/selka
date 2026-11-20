// float_loop: a binary64 multiply-add-sqrt dependency chain.
//
// Port of float_loop.zig. rustc never contracts `x * 0.999 + s` into an FMA
// (only `f64::mul_add` does), so the IEEE order matches Zig's strict float mode.
// `as i64` saturates where Zig's `@intFromFloat` would be illegal; the value
// here is about 4.47e9, well inside i64, so both print the same integer.
use std::hint::black_box;

// Prints one decimal value and a newline, like common.zig's `emit1`. The value
// is taken by value on purpose: `println!("{}", total)` inside `main` borrows
// `total`, and an address-taken accumulator can change the kernel loop's code
// (it keeps bytes_scan's loop scalar and branchy; see README.md).
#[inline(never)]
fn emit1(value: i64) {
    println!("{}", value);
}

fn main() {
    let n: i64 = black_box(20000000);
    let mut x: f64 = 0.0;
    for i in 0..n {
        x = x * 0.999 + (i as f64).sqrt();
    }
    emit1((x * 1000.0) as i64);
}
