// matmul: n x n f64 matrices in flat row-major Vecs, indexed i * n + j,
// C = A * B by the i-k-j loop; prints the trace and the sum of C, each scaled
// by 1000.
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

struct Lcg {
    seed: i64,
}

impl Lcg {
    fn next(&mut self) -> f64 {
        self.seed = (self.seed * 3877 + 29573) % 139968;
        self.seed as f64 / 139968.0
    }
}

fn main() {
    let n = black_box(500usize);
    let mut rng = Lcg { seed: 42 };
    let a: Vec<f64> = (0..n * n).map(|_| rng.next()).collect();
    let b: Vec<f64> = (0..n * n).map(|_| rng.next()).collect();
    let mut c = vec![0.0f64; n * n];
    for i in 0..n {
        for k in 0..n {
            let aik = a[i * n + k];
            for j in 0..n {
                c[i * n + j] = c[i * n + j] + aik * b[k * n + j];
            }
        }
    }
    let mut trace = 0.0f64;
    for i in 0..n {
        trace = trace + c[i * n + i];
    }
    let mut total = 0.0f64;
    for i in 0..n {
        for j in 0..n {
            total = total + c[i * n + j];
        }
    }
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "{}", (trace * 1000.0) as i64).unwrap();
    writeln!(out, "{}", (total * 1000.0) as i64).unwrap();
}
