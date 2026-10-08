// Row `record_pass` (S4 CONTRACT.md): a twelve-field record passed and returned by value.
use std::{env, process, time::Instant};

const MOD: i64 = 1_000_000_007;

struct State {
    f0: i64,
    f1: i64,
    f2: i64,
    f3: i64,
    f4: i64,
    f5: i64,
    f6: i64,
    f7: i64,
    f8: i64,
    f9: i64,
    f10: i64,
    f11: i64,
}

fn mix(a: i64, b: i64) -> i64 {
    (a * 31 + b) % 1009
}

fn advance(s: State, x: i64) -> State {
    let t = mix(s.f0 + s.f5, x);
    let f3 = if x % 3 == 0 { mix(s.f4, x) } else { s.f4 };
    State {
        f0: s.f1,
        f1: s.f2,
        f2: s.f3,
        f3,
        f4: s.f5,
        f5: s.f6,
        f6: s.f7,
        f7: s.f8,
        f8: s.f9,
        f9: s.f10,
        f10: s.f11,
        f11: t,
    }
}

fn batch_result(size: i64, batch: i64, seed: i64) -> i64 {
    let base = seed + batch;
    let mut s = State {
        f0: base % 1009,
        f1: (base + 7) % 1009,
        f2: (base + 14) % 1009,
        f3: (base + 21) % 1009,
        f4: (base + 28) % 1009,
        f5: (base + 35) % 1009,
        f6: (base + 42) % 1009,
        f7: (base + 49) % 1009,
        f8: (base + 56) % 1009,
        f9: (base + 63) % 1009,
        f10: (base + 70) % 1009,
        f11: (base + 77) % 1009,
    };
    for j in 0..size {
        s = advance(s, (base + 13 * j) % 1009);
    }
    s.f0 + 2 * s.f1
        + 3 * s.f2
        + 4 * s.f3
        + 5 * s.f4
        + 6 * s.f5
        + 7 * s.f6
        + 8 * s.f7
        + 9 * s.f8
        + 10 * s.f9
        + 11 * s.f10
        + 12 * s.f11
}

fn number(text: &str) -> Option<i64> {
    text.parse().ok()
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 5 || args[1] != "record_pass" {
        process::exit(2);
    }
    let (Some(size), Some(iterations), Some(seed)) =
        (number(&args[2]), number(&args[3]), number(&args[4]))
    else {
        process::exit(2);
    };
    if size < 2 || iterations < 1 || !(1..=1_000_000).contains(&seed) {
        process::exit(2);
    }
    let mut checksum = 0i64;
    let start = Instant::now();
    for batch in 0..iterations {
        checksum = (checksum + batch_result(size, batch, seed)) % MOD;
    }
    let elapsed = start.elapsed().as_nanos();
    println!("{} {}", checksum, elapsed);
}
