// Normal Vec allocations use Rust's default system allocator; shared batches
// clone the entire Vec and drop the snapshot inside the measured kernel.
use std::{env, time::Instant};
const MOD: i64 = 1_000_000_007;
struct Record {
    code: i64,
    bias: i64,
    payload: Vec<i64>,
}
fn read_record(r: &Record) -> i64 {
    r.code + r.bias + r.payload[0]
}
#[derive(Clone, Copy)]
enum Value {
    Int(i64),
    Bool(bool),
}
fn main() {
    let args: Vec<String> = env::args().collect();
    assert_eq!(args.len(), 5);
    let case = args[1].as_str();
    let size: usize = args[2].parse().unwrap();
    let iterations: i64 = args[3].parse().unwrap();
    let seed: i64 = args[4].parse().unwrap();
    assert!(size >= 2 && iterations >= 1 && (1..=1_000_000).contains(&seed));
    let (checksum, elapsed) = match case {
        "record_reads" => {
            let records: Vec<Record> = (0..size)
                .map(|j| {
                    let j = j as i64;
                    Record {
                        code: (seed + j * 17) % 1009,
                        bias: (seed * 3 + j * 7) % 257,
                        payload: (0..4).map(|k| j + seed + k).collect(),
                    }
                })
                .collect();
            let mut index = seed as usize % size;
            let mut checksum = 0;
            let start = Instant::now();
            for _ in 0..iterations {
                let v = read_record(&records[index]);
                checksum = (checksum + v) % MOD;
                index = (index + 2 * seed as usize + 1) % size;
            }
            (checksum, start.elapsed().as_nanos())
        }
        "tagged_stack" => {
            let opcodes: Vec<i64> = (0..size).map(|j| (j as i64 + seed) % 4).collect();
            let mut stack = vec![Value::Int(seed), Value::Bool(false)];
            let mut cursor = 0;
            let start = Instant::now();
            for _ in 0..iterations {
                let popped = stack.pop().unwrap();
                let base = match stack[0] {
                    Value::Int(v) => v,
                    _ => panic!("invalid base"),
                };
                let op = opcodes[cursor];
                let delta = match (op, popped) {
                    (0, Value::Bool(b)) => {
                        if b {
                            3
                        } else {
                            1
                        }
                    }
                    (1, Value::Bool(_)) => 7,
                    (2, Value::Bool(_)) => 11,
                    (3, Value::Bool(_)) => 13,
                    (0, Value::Int(v)) => v % 5,
                    (1, Value::Int(v)) => v % 7,
                    (2, Value::Int(v)) => v % 11,
                    (3, Value::Int(v)) => v % 13,
                    _ => unreachable!(),
                };
                let next = (base + delta + op + 1) % 1_000_003;
                stack[0] = Value::Int(next);
                stack.push(if op == 0 || op == 2 {
                    Value::Bool(next % 2 == 0)
                } else {
                    Value::Int(next % 97)
                });
                cursor = (cursor + 1) % size;
            }
            let elapsed = start.elapsed().as_nanos();
            let base = match stack[0] {
                Value::Int(v) => v,
                _ => unreachable!(),
            };
            let top = match stack[1] {
                Value::Int(v) => v,
                Value::Bool(b) => i64::from(b),
            };
            (base * 101 + top, elapsed)
        }
        "mutate_unique" | "mutate_shared" => {
            let mut values: Vec<i64> = (0..size).map(|j| (seed + j as i64 * 13) % 1009).collect();
            let mut checksum = 0;
            let start = Instant::now();
            for batch in 0..iterations {
                let index = ((seed + batch * 17) % size as i64) as usize;
                if case == "mutate_shared" {
                    let snapshot = values.clone();
                    values[index] = (values[index] + batch + 1) % 1_000_003;
                    checksum = (checksum + snapshot[index] + values[index]) % MOD;
                    drop(snapshot);
                } else {
                    values[index] = (values[index] + batch + 1) % 1_000_003;
                    checksum = (checksum + values[index]) % MOD;
                }
            }
            let elapsed = start.elapsed().as_nanos();
            for v in values {
                checksum = (checksum + v) % MOD;
            }
            (checksum, elapsed)
        }
        _ => panic!("unknown case"),
    };
    println!("{} {}", checksum, elapsed);
}
