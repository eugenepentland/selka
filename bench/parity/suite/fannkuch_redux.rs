// fannkuch_redux: the benchmarks-game C algorithm over three small Vecs.
// Flips prefixes of every permutation of 0..n-1 in the incremental order the C
// program generates; prints the alternating flip checksum and the maximum.
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

fn fannkuch(n: usize) -> (i64, i64) {
    let mut perm = vec![0usize; n];
    let mut perm1: Vec<usize> = (0..n).collect();
    let mut count = vec![0usize; n];
    let mut max_flips: i64 = 0;
    let mut checksum: i64 = 0;
    let mut perm_count: u64 = 0;
    let mut r = n;
    loop {
        while r != 1 {
            count[r - 1] = r;
            r -= 1;
        }
        perm.copy_from_slice(&perm1);
        let mut flips: i64 = 0;
        let mut k = perm[0];
        while k != 0 {
            let k2 = (k + 1) >> 1;
            for i in 0..k2 {
                perm.swap(i, k - i);
            }
            flips += 1;
            k = perm[0];
        }
        max_flips = max_flips.max(flips);
        checksum += if perm_count % 2 == 0 { flips } else { -flips };
        loop {
            if r == n {
                return (checksum, max_flips);
            }
            let perm0 = perm1[0];
            for i in 0..r {
                perm1[i] = perm1[i + 1];
            }
            perm1[r] = perm0;
            count[r] -= 1;
            if count[r] > 0 {
                break;
            }
            r += 1;
        }
        perm_count += 1;
    }
}

fn main() {
    let n = black_box(10usize);
    let (checksum, max_flips) = fannkuch(n);
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "{}", checksum).unwrap();
    writeln!(out, "Pfannkuchen({}) = {}", n, max_flips).unwrap();
}
