// text_ops: building, splitting, parsing and rewriting text with String,
// format!, split, parse, replace and matches (SUITE.md section 11).
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

fn main() {
    let lines = black_box(200_000usize);
    let text = (0..lines)
        .map(|i| format!("item{},{},{}", i, (i * 7919) % 100003, "x".repeat(i % 7)))
        .collect::<Vec<String>>()
        .join("\n");
    let mut total: i64 = 0;
    let mut widths: usize = 0;
    let mut sevens: usize = 0;
    for line in text.split('\n') {
        let fields: Vec<&str> = line.split(',').collect();
        total += fields[1].parse::<i64>().unwrap();
        widths += fields[2].len();
        if fields[0].ends_with('7') {
            sevens += 1;
        }
    }
    let rewritten = text.replace("item", "it");
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "{} {} {}", total, widths, sevens).unwrap();
    writeln!(out, "{} {} {}", text.len(), rewritten.len(), text.matches(",1").count()).unwrap();
}
