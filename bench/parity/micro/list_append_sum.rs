// list_append_sum: grow a Vec<i64> by push, then fold it.
//
// Port of list_append_sum.zig: `Vec::new()` + `push` for
// `ArrayList(i64) = .empty` + `append`, then a `for` over the elements.
// The growth policy differs by library: Vec doubles, Zig's ArrayList grows by
// about 1.5x; both sit on an mremap-capable allocator (glibc malloc here,
// smp_allocator in Zig).
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
    let n: i64 = black_box(16000000);
    let mut values: Vec<i64> = Vec::new();
    for i in 0..n {
        values.push(i);
    }
    let mut total: i64 = 0;
    for &v in &values {
        total += v;
    }
    emit1(total);
}
