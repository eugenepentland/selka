// intloop: integer arithmetic over a loop-carried dependency.
// total = (total + i * 7) % 1000003 for i in 0..N
//
// Port of intloop.zig. `total` and `i` are never negative, so Rust's truncating
// `%` gives the same value as Zig's `@mod` and selka's floor `%`.
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
    let n: i64 = black_box(30000000);
    let mut total: i64 = 0;
    for i in 0..n {
        total = (total + i * 7) % 1000003;
    }
    emit1(total);
}
