// bytes_scan: index an 8 MiB byte slice and count one octet value, sixteen times.
//
// Port of bytes_scan.zig: build the buffer with `extend_from_slice`, borrow it
// as `&[u8]` (Zig's `buffer.items`, no copy), then an index loop over it. The
// loop is deliberately `data[k]` rather than `for &b in data`, because the
// kernel measures indexing; `k < data.len()` lets LLVM drop the bounds check.
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
    let piece: &[u8] = b"mylang micro benchmark kernel payload 0123456789 abcdefghijklmno";
    let chunks: i64 = black_box(131072);
    let mut buffer: Vec<u8> = Vec::new();
    for _ in 0..chunks {
        buffer.extend_from_slice(piece);
    }
    let data: &[u8] = &buffer;
    let mut count: i64 = 0;
    for pass_index in 0..16_i64 {
        count += pass_index;
        for k in 0..data.len() {
            if data[k] == 109 {
                count += 1;
            }
        }
    }
    emit1(count);
}
