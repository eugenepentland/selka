// sort_quick: two million xorshift values sorted in place by the SUITE.md
// recursive Hoare quicksort (recurse on the smaller side, loop on the larger);
// prints three order statistics and a checksum. Bounds are signed because
// `j` can step to lo - 1.
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

fn quicksort(xs: &mut [i64], mut lo: isize, mut hi: isize) {
    while lo < hi {
        let pivot = xs[(lo + (hi - lo) / 2) as usize];
        let mut i = lo;
        let mut j = hi;
        while i <= j {
            while xs[i as usize] < pivot {
                i += 1;
            }
            while xs[j as usize] > pivot {
                j -= 1;
            }
            if i <= j {
                xs.swap(i as usize, j as usize);
                i += 1;
                j -= 1;
            }
        }
        if j - lo < hi - i {
            quicksort(xs, lo, j);
            lo = i;
        } else {
            quicksort(xs, i, hi);
            hi = j;
        }
    }
}

fn main() {
    let n = black_box(2_000_000usize);
    let mut state: u64 = 88172645463325252;
    let mut values: Vec<i64> = Vec::with_capacity(n);
    for _ in 0..n {
        state = xorshift(state);
        values.push((state >> 33) as i64);
    }
    quicksort(&mut values, 0, n as isize - 1);
    let c = values.iter().fold(0i64, |c, &v| mix(c, v));
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "{} {} {}", values[0], values[n / 2], values[n - 1]).unwrap();
    writeln!(out, "{}", c).unwrap();
}
