// alloc_churn (retained-capacity variant): one Vec cleared at every batch.
//
// The std-only counterpart of alloc_churn.zig's
// `arena_state.reset(.retain_capacity)`: storage is obtained during the first
// batch and kept, so later batches make no allocator call at all. It no longer
// drops a list per batch, which is what alloc_churn.rs measures.
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
    let n: i64 = black_box(1000000);
    let mut total: i64 = 0;
    let mut values: Vec<i64> = Vec::new();
    for batch in 0..n {
        values.clear();
        for j in 0..16_i64 {
            values.push(batch + j);
        }
        for &v in &values {
            total = (total + v) % 1000003;
        }
    }
    emit1(total);
}
