// spectral_norm: ten power-iteration rounds on the infinite matrix
// A(i, j) = 1 / ((i + j)(i + j + 1)/2 + i + 1), n = 2000. `a` stays a separate
// function. See SUITE.md section 3.
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

fn a(i: usize, j: usize) -> f64 {
    1.0 / ((i + j) * (i + j + 1) / 2 + i + 1) as f64
}

fn mul_av(v: &[f64], out: &mut [f64]) {
    let n = v.len();
    for i in 0..n {
        let mut s = 0.0;
        for j in 0..n {
            s = s + a(i, j) * v[j];
        }
        out[i] = s;
    }
}

fn mul_atv(v: &[f64], out: &mut [f64]) {
    let n = v.len();
    for i in 0..n {
        let mut s = 0.0;
        for j in 0..n {
            s = s + a(j, i) * v[j];
        }
        out[i] = s;
    }
}

fn mul_atav(v: &[f64], out: &mut [f64], tmp: &mut [f64]) {
    mul_av(v, tmp);
    mul_atv(tmp, out);
}

fn main() {
    let n: usize = black_box(2000);
    let mut u = vec![1.0; n];
    let mut v = vec![0.0; n];
    let mut tmp = vec![0.0; n];
    for _ in 0..10 {
        mul_atav(&u, &mut v, &mut tmp);
        mul_atav(&v, &mut u, &mut tmp);
    }
    let mut vbv = 0.0;
    let mut vv = 0.0;
    for i in 0..n {
        vbv = vbv + u[i] * v[i];
        vv = vv + v[i] * v[i];
    }
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "{}", ((vbv / vv).sqrt() * 1e9) as i64).unwrap();
    out.flush().unwrap();
}
