// ALTERNATIVE, NOT A ROW ARM: the literal `Node(Box<Tree>, i64, Box<Tree>)` enum, which boxes even each Leaf
// (2N+1 allocations per tree). See NOTES.md. Build: rustc -O --edition 2021 alt_box_per_leaf.rs
use std::{env, process, time::Instant};

const MOD: i64 = 1_000_000_007;

enum Tree {
    Leaf,
    Node(Box<Tree>, i64, Box<Tree>),
}

fn build(lo: i64, hi: i64, base: i64) -> Tree {
    if lo >= hi {
        return Tree::Leaf;
    }
    let mid = (lo + hi) / 2;
    Tree::Node(
        Box::new(build(lo, mid, base)),
        (base + 13 * mid) % 1009,
        Box::new(build(mid + 1, hi, base)),
    )
}

fn walk(tree: &Tree, depth: i64) -> i64 {
    match tree {
        Tree::Leaf => 0,
        Tree::Node(left, value, right) => {
            (depth + 1) * value + walk(left, depth + 1) + walk(right, depth + 1)
        }
    }
}

fn number(text: &str) -> Option<i64> {
    text.parse().ok()
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 5 || args[1] != "tree_build_walk" {
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
        let tree = build(0, size, seed + batch);
        let part = walk(&tree, 0) % MOD;
        checksum = (checksum + part) % MOD;
    }
    let elapsed = start.elapsed().as_nanos();
    println!("{} {}", checksum, elapsed);
}
