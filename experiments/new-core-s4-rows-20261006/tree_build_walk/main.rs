// Row `tree_build_walk` (S4 CONTRACT.md): a recursive enum with Box, built and dropped per batch.
// `Leaf` is a bare enum case (the niche in the Box makes `Tree` one pointer wide), so only an
// internal node allocates: one Box per Node, exactly like the Zig and Go ports.
use std::{env, process, time::Instant};

const MOD: i64 = 1_000_000_007;

struct Node {
    left: Tree,
    value: i64,
    right: Tree,
}

enum Tree {
    Leaf,
    Node(Box<Node>),
}

fn build(lo: i64, hi: i64, base: i64) -> Tree {
    if lo >= hi {
        return Tree::Leaf;
    }
    let mid = (lo + hi) / 2;
    Tree::Node(Box::new(Node {
        left: build(lo, mid, base),
        value: (base + 13 * mid) % 1009,
        right: build(mid + 1, hi, base),
    }))
}

fn walk(tree: &Tree, depth: i64) -> i64 {
    match tree {
        Tree::Leaf => 0,
        Tree::Node(node) => {
            (depth + 1) * node.value + walk(&node.left, depth + 1) + walk(&node.right, depth + 1)
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
