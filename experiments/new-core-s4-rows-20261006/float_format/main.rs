use std::time::Instant;

const MOD: i64 = 1_000_000_007;

/// Shortest round-trip decimal text of one value, folded byte by byte.
fn batch_result(size: i64, batch: i64, seed: i64) -> i64 {
    let mut part: i64 = 0;
    for j in 0..size {
        let k = (seed + batch + 13 * j) % 100_003;
        let x = k as f64 + 0.125 * (1 + j % 7) as f64;
        let text = x.to_string();
        let mut h: i64 = 0;
        for c in text.bytes() {
            h = (h * 131 + i64::from(c)) % MOD;
        }
        part = (part + h + text.len() as i64) % MOD;
    }
    part
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() != 4 || args[0] != "float_format" {
        std::process::exit(2);
    }
    let size = args[1].parse::<i64>().unwrap_or(0);
    let iterations = args[2].parse::<i64>().unwrap_or(0);
    let seed = args[3].parse::<i64>().unwrap_or(0);
    if size < 2 || iterations < 1 || !(1..=1_000_000).contains(&seed) {
        std::process::exit(2);
    }
    let start = Instant::now();
    let mut checksum: i64 = 0;
    for batch in 0..iterations {
        checksum = (checksum + batch_result(size, batch, seed)) % MOD;
    }
    let elapsed = start.elapsed().as_nanos();
    println!("{checksum} {elapsed}");
}
