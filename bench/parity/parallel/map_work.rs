// map_work (PARALLEL.md, program 1): 4096 items, each a chain of 100000 modular steps, split into chunks as parallel.map does.
#[path = "common.rs"]
mod common;

use std::hint::black_box;
use std::io::{self, Write};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;

const MODULUS: i64 = 1000003;

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

fn main() {
    let items = black_box(4096usize);
    let rounds = black_box(100000i64);
    let threads = common::thread_count();
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
                            part += work(x as i64, rounds);
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
    writeln!(out, "map_work {} {} checksum {}", items, rounds, total).unwrap();
}
