// mandelbrot: a 1600 x 1600 escape-time bitmap (50 iterations, limit 4.0),
// packed eight pixels per byte and folded into a checksum instead of being
// written out. See SUITE.md section 5.
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

fn mix(c: i64, v: i64) -> i64 {
    (c * 31 + v) % 1000000007
}

fn main() {
    let size: usize = black_box(1600);
    let iterations: i64 = 50;
    let limit = 4.0;
    let mut checksum: i64 = 0;
    for y in 0..size {
        let ci = 2.0 * y as f64 / size as f64 - 1.0;
        let mut byte: i64 = 0;
        let mut bits: i64 = 0;
        for x in 0..size {
            let cr = 2.0 * x as f64 / size as f64 - 1.5;
            let mut zr = 0.0;
            let mut zi = 0.0;
            let mut tr = 0.0;
            let mut ti = 0.0;
            let mut i = 0;
            while i < iterations && tr + ti <= limit {
                zi = 2.0 * zr * zi + ci;
                zr = tr - ti + cr;
                tr = zr * zr;
                ti = zi * zi;
                i = i + 1;
            }
            byte = byte * 2 + if tr + ti <= limit { 1 } else { 0 };
            bits = bits + 1;
            if bits == 8 {
                checksum = mix(checksum, byte);
                byte = 0;
                bits = 0;
            }
        }
        if bits > 0 {
            byte = byte << (8 - bits);
            checksum = mix(checksum, byte);
        }
    }
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "P4 {} {}", size, size).unwrap();
    writeln!(out, "{}", checksum).unwrap();
    out.flush().unwrap();
}
