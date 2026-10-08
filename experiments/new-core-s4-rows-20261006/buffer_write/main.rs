use std::io::Write;
use std::time::Instant;

const MOD: i64 = 1_000_000_007;

/// Appends the decimal digits of SIZE values to a fresh byte buffer, then folds and drops it.
fn batch_result(size: i64, batch: i64, seed: i64) -> i64 {
    let mut buf: Vec<u8> = Vec::new();
    for j in 0..size {
        let v = (seed + batch + 13 * j) % 100_003;
        write!(buf, "{}", v).unwrap();
        buf.push(b',');
        if j % 16 == 15 {
            buf.push(b'\n');
        }
    }
    let mut h: i64 = 0;
    for &c in &buf {
        h = (h * 131 + i64::from(c)) % MOD;
    }
    (buf.len() as i64 + h) % MOD
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() != 4 || args[0] != "buffer_write" {
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
