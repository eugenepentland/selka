// sort_builtin: two million xorshift values sorted in place by slice::sort
// (the standard stable sort); prints three order statistics and a checksum.
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

fn xorshift(mut x: u64) -> u64 {
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    x
}

fn mix(c: i64, v: i64) -> i64 {
    (c * 31 + v) % 1000000007
}

fn main() {
    let n = black_box(2_000_000usize);
    let mut state: u64 = 88172645463325252;
    let mut values: Vec<i64> = Vec::with_capacity(n);
    for _ in 0..n {
        state = xorshift(state);
        values.push((state >> 33) as i64);
    }
    values.sort();
    let c = values.iter().fold(0i64, |c, &v| mix(c, v));
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "{} {} {}", values[0], values[n / 2], values[n - 1]).unwrap();
    writeln!(out, "{}", c).unwrap();
}
