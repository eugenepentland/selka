// knucleotide: every k-letter substring of a generated DNA sequence counted in a
// HashMap<&[u8], u32> keyed by slices of one byte sequence, default hasher
// (SUITE.md section 6).
use std::collections::HashMap;
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

fn generate(length: usize) -> Vec<u8> {
    let bases = b"ACGT";
    let mut seq = Vec::with_capacity(length);
    let mut seed: i64 = 42;
    for _ in 0..length {
        seed = (seed * 3877 + 29573) % 139968;
        seq.push(bases[(seed * 4 / 139968) as usize]);
    }
    seq
}

fn frequencies(seq: &[u8], k: usize) -> HashMap<&[u8], u32> {
    let mut counts = HashMap::new();
    for i in 0..seq.len() - k + 1 {
        *counts.entry(&seq[i..i + k]).or_insert(0) += 1;
    }
    counts
}

fn main() {
    let seq = generate(black_box(1_000_000));
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    for k in [1, 2] {
        let counts = frequencies(&seq, k);
        let mut entries: Vec<(&[u8], u32)> = counts.into_iter().collect();
        entries.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
        for (key, count) in entries {
            writeln!(out, "{} {}", std::str::from_utf8(key).unwrap(), count).unwrap();
        }
    }
    for key in ["GGT", "GGTA", "GGTATT", "GGTATTTTAATT", "GGTATTTTAATTTATAGT"] {
        let counts = frequencies(&seq, key.len());
        let count = counts.get(key.as_bytes()).copied().unwrap_or(0);
        writeln!(out, "{}\t{}", count, key).unwrap();
    }
}
