// Row `union_find` (CONTRACT.md): union by linking roots, path halving that mutates `parent`.
// One `Vec<usize>` per batch, `find` takes `&mut [usize]`; std only.
use std::{env, process, time::Instant};

const MOD: i64 = 1_000_000_007;

fn find(parent: &mut [usize], mut x: usize) -> usize {
    while parent[x] != x {
        parent[x] = parent[parent[x]];
        x = parent[x];
    }
    x
}

fn batch_result(size: usize, batch: i64, seed: i64) -> i64 {
    let n = size as i64;
    let mut parent: Vec<usize> = (0..size).collect();
    for j in 0..n {
        let a = ((seed + batch + 13 * j) % n) as usize;
        let b = ((seed + 7 * batch + 17 * j + 1) % n) as usize;
        let ra = find(&mut parent, a);
        let rb = find(&mut parent, b);
        if ra != rb {
            parent[ra] = rb;
        }
    }
    let mut components = 0;
    for j in 0..size {
        if find(&mut parent, j) == j {
            components += 1;
        }
    }
    let mut rootsum = 0;
    for j in 0..size {
        rootsum += find(&mut parent, j) as i64;
    }
    (components * 1000003 + rootsum) % MOD
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 5 || args[1] != "union_find" {
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
    let mut checksum = 0;
    let start = Instant::now();
    for batch in 0..iterations {
        checksum = (checksum + batch_result(size, batch, seed)) % MOD;
    }
    let elapsed = start.elapsed().as_nanos();
    println!("{} {}", checksum, elapsed);
}
