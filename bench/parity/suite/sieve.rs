// sieve: Eratosthenes over a Vec<bool> of n + 1 flags; prints the prime count.
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

fn main() {
    let n = black_box(20_000_000usize);
    let mut flags = vec![true; n + 1];
    flags[0] = false;
    flags[1] = false;
    let mut i = 2;
    while i * i <= n {
        if flags[i] {
            let mut j = i * i;
            while j <= n {
                flags[j] = false;
                j += i;
            }
        }
        i += 1;
    }
    let count = flags.iter().filter(|&&flag| flag).count();
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "{}", count).unwrap();
}
