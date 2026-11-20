// dict_count: HashMap read-modify-write over 1000 distinct short keys.
// The get/insert pair mirrors dict_count.zig's get + put and the selka
// `counts[key] = counts.get(key, 0) + 1` spelling: two hash lookups per step.
//
// `HashMap<&str, i64>` borrows the key strings from `keys`, as Zig's
// `StringHashMap(i64)` stores `[]const u8` slices it does not own. The hasher
// is std's default (SipHash-1-3, randomly keyed per process); Zig's
// StringHashMap uses Wyhash. The random key changes only iteration order,
// which this kernel never observes.
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
        let current = counts.get(key).copied().unwrap_or(0);
        counts.insert(key, current + 1);
    }
    let mut total: i64 = 0;
    for name in &keys {
        let count = counts.get(name.as_str()).copied().unwrap_or(0);
        total = (total + count * name.len() as i64) % 1000003;
    }
    emit1(total);
}
