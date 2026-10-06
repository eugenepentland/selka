// Row `grid_dp` (CONTRACT.md): a minimum-cost path DP over two nested dynamic grids.
// `Vec<Vec<i64>>` for both grids, built row by row and dropped inside every batch; std only.
use std::{env, process, time::Instant};

const MOD: i64 = 1_000_000_007;

/// Largest `w` with `w * w <= n`, the same integer loop in every language.
fn isqrt(n: usize) -> usize {
    let mut w = 0;
    while (w + 1) * (w + 1) <= n {
        w += 1;
    }
    w
}

fn batch_result(w: usize, h: usize, batch: i64, seed: i64) -> i64 {
    let cost: Vec<Vec<i64>> = (0..h)
        .map(|i| {
            (0..w)
                .map(|j| (seed + batch + 13 * (i * w + j) as i64) % 1009)
                .collect()
        })
        .collect();
    let mut dp: Vec<Vec<i64>> = (0..h).map(|_| vec![0; w]).collect();
    dp[0][0] = cost[0][0];
    for j in 1..w {
        dp[0][j] = dp[0][j - 1] + cost[0][j];
    }
    for i in 1..h {
        dp[i][0] = dp[i - 1][0] + cost[i][0];
        for j in 1..w {
            dp[i][j] = cost[i][j] + dp[i - 1][j].min(dp[i][j - 1]);
        }
    }
    dp[h - 1][w - 1] + dp[h - 1].iter().sum::<i64>()
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 5 || args[1] != "grid_dp" {
        process::exit(2);
    }
    let (Ok(size), Ok(iterations), Ok(seed)) = (
        args[2].parse::<usize>(),
        args[3].parse::<i64>(),
        args[4].parse::<i64>(),
    ) else {
        process::exit(2);
    };
    if size < 2 || iterations < 1 || !(1..=1_000_000).contains(&seed) {
        process::exit(2);
    }
    let w = isqrt(size);
    let h = size / w;
    let mut checksum = 0;
    let start = Instant::now();
    for batch in 0..iterations {
        checksum = (checksum + batch_result(w, h, batch, seed)) % MOD;
    }
    let elapsed = start.elapsed().as_nanos();
    println!("{} {}", checksum, elapsed);
}
