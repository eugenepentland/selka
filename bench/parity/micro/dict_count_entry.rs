// dict_count (idiomatic variant): one entry lookup instead of get + insert.
//
// Rust counterpart of dict_count_getorput.zig: `entry(key).or_insert(0)` is
// the single-lookup read-modify-write, like Zig's `getOrPut`. Everything else,
// including the default SipHash-1-3 hasher, is identical to dict_count.rs.
use std::collections::HashMap;
use std::hint::black_box;

// Prints one decimal value and a newline, like common.zig's `emit1`. The value
// is taken by value on purpose: `println!("{}", total)` inside `main` borrows
// `total`, and an address-taken accumulator can change the kernel loop's code
// (it keeps bytes_scan's loop scalar and branchy; see README.md).
#[inline(never)]
fn emit1(value: i64) {
    println!("{}", value);
}

fn main() {
    let mut keys: Vec<String> = Vec::new();
    for k in 0..1000_i64 {
        keys.push(format!("key{}", k));
    }
    let mut counts: HashMap<&str, i64> = HashMap::new();
    let n: i64 = black_box(2000000);
    for i in 0..n {
        let key: &str = &keys[((i * 7919) % 1000) as usize];
        *counts.entry(key).or_insert(0) += 1;
    }
    let mut total: i64 = 0;
    for name in &keys {
        let count = counts.get(name.as_str()).copied().unwrap_or(0);
        total = (total + count * name.len() as i64) % 1000003;
    }
    emit1(total);
}
