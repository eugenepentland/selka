// binary_trees: perfect binary trees of `Option<Box<Node>>` children on the
// global allocator; each tree is dropped normally after its check.
// See SUITE.md section 1.
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

struct Node {
    left: Option<Box<Node>>,
    right: Option<Box<Node>>,
}

fn make(depth: i64) -> Box<Node> {
    if depth == 0 {
        Box::new(Node {
            left: None,
            right: None,
        })
    } else {
        Box::new(Node {
            left: Some(make(depth - 1)),
            right: Some(make(depth - 1)),
        })
    }
}

fn check(node: &Node) -> i64 {
    match (&node.left, &node.right) {
        (Some(left), Some(right)) => 1 + check(left) + check(right),
        _ => 1,
    }
}

fn main() {
    let max_depth: i64 = black_box(16);
    let min_depth: i64 = 4;
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());

    let stretch = max_depth + 1;
    writeln!(
        out,
        "stretch tree of depth {}\t check: {}",
        stretch,
        check(&make(stretch))
    )
    .unwrap();

    let long_lived = make(max_depth);

    let mut depth = min_depth;
    while depth <= max_depth {
        let iterations: i64 = 1 << (max_depth - depth + min_depth);
        let mut total: i64 = 0;
        for _ in 0..iterations {
            total += check(&make(depth));
        }
        writeln!(
            out,
            "{}\t trees of depth {}\t check: {}",
            iterations, depth, total
        )
        .unwrap();
        depth += 2;
    }

    writeln!(
        out,
        "long lived tree of depth {}\t check: {}",
        max_depth,
        check(&long_lived)
    )
    .unwrap();
    out.flush().unwrap();
}
