// group_tasks (PARALLEL.md, program 2): eight independent tasks, each summing the work of 512 items.
#[path = "common.rs"]
mod common;

use std::hint::black_box;
use std::io::{self, Write};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;

const MODULUS: i64 = 1000003;
const TASKS: usize = 8;
const PER_TASK: usize = 512;

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

// The work of items first .. first + count - 1, summed.
fn span(first: usize, count: usize, rounds: i64) -> i64 {
    (first..first + count).map(|x| work(x as i64, rounds)).sum()
}

fn main() {
    let rounds = black_box(100000i64);
    let threads = common::thread_count();
    let next = AtomicUsize::new(0);
    let results: Vec<(usize, i64)> = thread::scope(|scope| {
        let workers: Vec<_> = (0..threads)
            .map(|_| {
                scope.spawn(|| {
                    let mut done = Vec::new();
                    loop {
                        let index = next.fetch_add(1, Ordering::Relaxed);
                        if index >= TASKS {
                            break;
                        }
                        done.push((index, span(index * PER_TASK, PER_TASK, rounds)));
                    }
                    done
                })
            })
            .collect();
        workers.into_iter().flat_map(|worker| worker.join().unwrap()).collect()
    });
    let checksum: i64 = results.iter().map(|(_, value)| value).sum();
    let stdout = io::stdout();
    let mut out = stdout.lock();
    writeln!(out, "group_tasks {} {} {} checksum {}", TASKS, PER_TASK, rounds, checksum).unwrap();
}
