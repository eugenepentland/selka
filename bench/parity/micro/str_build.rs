// str_build: append a short piece into a growable byte buffer 16,000,000 times.
//
// Port of str_build.zig (whose header comment still says 8,000,000; the loop
// bound is 16,000,000 in every language). `Vec<u8>::extend_from_slice` plays
// the part of `ArrayList(u8).appendSlice`; the sampling fold is identical.
// `length` is never negative, so `/` equals Zig's `@divFloor`.
use std::hint::black_box;

// Prints two space-separated values and a newline, like common.zig's `emit2`.
// Values are taken by value so no kernel local is ever borrowed (see emit1 in
// the other kernels and README.md).
#[inline(never)]
fn emit2(first: i64, second: i64) {
    println!("{} {}", first, second);
}

fn main() {
    let n: i64 = black_box(16000000);
    let piece: &[u8] = b"mylang!\n";
    let mut buffer: Vec<u8> = Vec::new();
    for _ in 0..n {
        buffer.extend_from_slice(piece);
    }
    let length = buffer.len() as i64;
    let samples = length / 1021;
    let mut total: i64 = 0;
    for j in 0..samples {
        total = (total + buffer[(j * 1021) as usize] as i64) % 1000003;
    }
    emit2(length, total);
}
