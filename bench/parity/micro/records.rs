// records: construct a 3-field value struct per iteration and pass it by value.
//
// Port of records.zig. The struct is called `Vec` in the Zig and mylang
// kernels; it is `Vec3` here only so it does not shadow the prelude's `Vec`.
// As in Zig, `norm1` is an ordinary function the optimizer may inline.
// `%` equals Zig's `@mod` here because every dividend is non-negative; Zig's
// build keeps `@mod`'s sign fix-up in this loop and Rust's `%` does not
// (`rem_euclid` is the op-for-op floor mod; see README.md).
use std::hint::black_box;

#[derive(Clone, Copy)]
struct Vec3 {
    x: i64,
    y: i64,
    z: i64,
}

fn norm1(v: Vec3) -> i64 {
    v.x + v.y + v.z
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
    let n: i64 = black_box(20000000);
    let mut total: i64 = 0;
    for i in 0..n {
        let v = Vec3 { x: i, y: i + 1, z: i + 2 };
        total = (total + norm1(v)) % 1000003;
    }
    emit1(total);
}
