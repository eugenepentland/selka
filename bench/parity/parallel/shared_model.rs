// shared_model (PARALLEL.md, program 3): 4096 items, each reading 1000 entries of one shared list of 2^20 integers, plus its
// work chain. The list is built once and read by every thread; nothing is copied.
#[path = "common.rs"]
mod common;

use std::hint::black_box;
use std::io::{self, Write};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;

const MODULUS: i64 = 1000003;
const MODEL_SIZE: usize = 1048576;

// The shared work: t starts at seed mod 1000003, then rounds steps of t = (t * 31 + i) mod 1000003.
fn work(seed: i64, count: i64) -> i64 {
    let mut t = seed % MODULUS;
    let mut i = 0i64;
    while i < count {
        t = (t * 31 + i) % MODULUS;
        i += 1;
    }
    t
}

// The item's value: 1000 model entries summed mod 1000003, plus its work chain.
fn lookup(x: i64, model: &[i64], rounds: i64) -> i64 {
    let mut s = 0i64;
    for j in 0..1000i64 {
        s += model[((x * 7919 + j * 104729) % model.len() as i64) as usize];
    }
    s % MODULUS + work(x, rounds)
}

fn main() {
    let items = black_box(4096usize);
    let rounds = black_box(100000i64);
    let threads = common::thread_count();
    let model: Vec<i64> = (0..MODEL_SIZE).map(|k| (k as i64 * 2654435761 + 12345) % MODULUS).collect();
    let chunks = common::chunk_count(items, threads);
    let next = AtomicUsize::new(0);
    let total: i64 = thread::scope(|scope| {
        let workers: Vec<_> = (0..threads)
            .map(|_| {
                scope.spawn(|| {
                    let mut part = 0i64;
                    loop {
                        let index = next.fetch_add(1, Ordering::Relaxed);
                        if index >= chunks {
                            break;
                        }
                        let (start, count) = common::chunk_range(items, chunks, index);
                        for x in start..start + count {
                            part += lookup(x as i64, &model, rounds);
                        }
                    }
                    part
                })
            })
            .collect();
        workers.into_iter().map(|worker| worker.join().unwrap()).sum()
    });
    let stdout = io::stdout();
    let mut out = stdout.lock();
    writeln!(out, "shared_model {} {} checksum {}", items, rounds, total).unwrap();
}
