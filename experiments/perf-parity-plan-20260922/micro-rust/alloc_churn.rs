// alloc_churn: build, fold and drop a 16-element list once per batch.
//
// The matched Rust arm of this kernel: alloc_churn.zig's loop, with the
// allocation Rust's standard library actually offers. Each batch starts a fresh
// empty `Vec`, grows it by `push` (capacity 4 -> 8 -> 16: one malloc and two
// reallocs; Zig's ArrayList grows 9 -> 23) and frees it when it leaves scope.
// Stable Rust std has no arena allocator, so this runs on the global allocator
// (glibc malloc) and is the memory-strategy match for alloc_churn_gpa.zig
// (smp_allocator alloc + free per batch), not for the arena-reset `zig-fast`
// arm. alloc_churn_reuse.rs is the retained-capacity counterpart of that arena.
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
    for batch in 0..n {
        let mut values: Vec<i64> = Vec::new();
        for j in 0..16_i64 {
            values.push(batch + j);
        }
        for &v in &values {
            total = (total + v) % 1000003;
        }
    }
    emit1(total);
}
