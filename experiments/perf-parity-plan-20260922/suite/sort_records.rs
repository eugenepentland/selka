// sort_records: one million {key, id} records stable-sorted by key through
// slice::sort_by_key; prints the first and last key and a checksum over the
// ids in sorted order. Fields are i64 to match mylang's int.
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

#[derive(Clone, Copy)]
struct Rec {
    key: i64,
    id: i64,
}

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
    let n = black_box(1_000_000usize);
    let mut state: u64 = 88172645463325252;
    let mut records: Vec<Rec> = Vec::with_capacity(n);
    for i in 0..n {
        state = xorshift(state);
        records.push(Rec {
            key: ((state >> 33) % 100000) as i64,
            id: i as i64,
        });
    }
    records.sort_by_key(|r| r.key);
    let c = records.iter().fold(0i64, |c, r| mix(c, r.id));
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "{} {}", records[0].key, records[n - 1].key).unwrap();
    writeln!(out, "{}", c).unwrap();
}
