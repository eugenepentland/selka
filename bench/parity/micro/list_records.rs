// list_records: a Vec of 32-byte structs, then ten field-summing passes.
//
// Port of list_records.zig: 2,000,000 four-field rows pushed onto a `Vec<Row>`
// that starts empty, then ten passes that add the pass index and every row's
// `c`. Fields a, b and d are written and never read, exactly as in Zig/mylang.
use std::hint::black_box;

#[derive(Clone, Copy)]
#[allow(dead_code)]
struct Row {
    a: i64,
    b: i64,
    c: i64,
    d: i64,
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
    let n: i64 = black_box(2000000);
    let mut rows: Vec<Row> = Vec::new();
    for i in 0..n {
        rows.push(Row { a: i, b: i + 1, c: i + 2, d: i + 3 });
    }
    let mut total: i64 = 0;
    for pass_index in 0..10_i64 {
        total += pass_index;
        for row in &rows {
            total += row.c;
        }
    }
    emit1(total);
}
