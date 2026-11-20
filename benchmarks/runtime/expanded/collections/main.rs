// Normal standard collections and default allocator; snapshots deeply clone all inner vectors.
use std::{
    collections::{HashMap, HashSet},
    env,
    time::Instant,
};
const MOD: i64 = 1_000_000_007;
#[derive(Clone, Copy)]
enum Value {
    Int(i64),
    Bool(bool),
}
#[derive(Clone)]
struct Row {
    key: i64,
    ordinal: i64,
    value: i64,
}
const PROGRAM: &[(u8, usize)] = &[
    (0, 0),
    (4, 0),
    (2, 0),
    (4, 1),
    (3, 1),
    (1, 0),
    (8, 0),
    (10, 29),
    (3, 1),
    (2, 2),
    (7, 0),
    (2, 0),
    (9, 0),
    (10, 18),
    (3, 0),
    (12, 31),
    (4, 0),
    (11, 24),
    (3, 0),
    (3, 1),
    (5, 0),
    (2, 1000003),
    (7, 0),
    (4, 0),
    (3, 1),
    (2, 1),
    (5, 0),
    (4, 1),
    (11, 4),
    (3, 0),
    (14, 0),
    (2, 3),
    (6, 0),
    (2, 7),
    (5, 0),
    (2, 1000003),
    (7, 0),
    (13, 0),
];
fn integer(v: Value) -> i64 {
    match v {
        Value::Int(n) => n,
        _ => panic!("expected integer"),
    }
}
fn execute(program: &[(u8, usize)], size: usize, seed: i64) -> i64 {
    let mut stack: Vec<Value> = Vec::new();
    let mut returns: Vec<usize> = Vec::new();
    let mut vars = vec![0i64; 2];
    let mut pc = 0;
    loop {
        let (op, arg) = program[pc];
        pc += 1;
        match op {
            0 => stack.push(Value::Int(seed)),
            1 => stack.push(Value::Int(size as i64)),
            2 => stack.push(Value::Int(arg as i64)),
            3 => stack.push(Value::Int(vars[arg])),
            4 => vars[arg] = integer(stack.pop().unwrap()),
            5..=9 => {
                let b = integer(stack.pop().unwrap());
                let a = integer(stack.pop().unwrap());
                stack.push(match op {
                    5 => Value::Int(a + b),
                    6 => Value::Int(a * b),
                    7 => Value::Int(a % b),
                    8 => Value::Bool(a < b),
                    9 => Value::Bool(a == b),
                    _ => unreachable!(),
                });
            }
            10 => match stack.pop().unwrap() {
                Value::Bool(false) => pc = arg,
                Value::Bool(true) => {}
                _ => panic!("expected boolean"),
            },
            11 => pc = arg,
            12 => {
                returns.push(pc);
                pc = arg;
            }
            13 => pc = returns.pop().unwrap(),
            14 => return integer(stack.pop().unwrap()),
            _ => panic!("bad opcode"),
        }
    }
}
fn fold(xs: &[i64]) -> i64 {
    xs.iter().enumerate().map(|(i, v)| (i as i64 + 1) * v).sum()
}
fn main() {
    let args: Vec<String> = env::args().collect();
    assert_eq!(args.len(), 5);
    let kind = &args[1];
    let size: usize = args[2].parse().unwrap();
    let iterations: i64 = args[3].parse().unwrap();
    let seed: i64 = args[4].parse().unwrap();
    assert!(size >= 2 && iterations >= 1 && (1..=1_000_000).contains(&seed));
    let case_id = [
        "list_scan",
        "list_append",
        "list_filter",
        "dict_lookup",
        "dict_lookup_str",
        "dict_update",
        "dict_update_str",
        "set_dedup",
        "alloc_short",
        "alloc_retained",
        "mutate_nested",
        "sort_int",
        "sort_records",
        "lox_eval",
    ]
    .iter()
    .position(|name| *name == kind)
    .expect("unknown case");
    let values: Vec<i64> = (0..size).map(|j| (seed + j as i64 * 13) % 1009).collect();
    let keys: Vec<String> = (0..if kind.ends_with("_str") { size * 2 } else { 0 })
        .map(|j| j.to_string())
        .collect();
    let lookup: HashMap<i64, i64> = (0..if kind == "dict_lookup" { size } else { 0 })
        .map(|j| (j as i64, values[j]))
        .collect();
    let lookup_str: HashMap<String, i64> = (0..if kind == "dict_lookup_str" { size } else { 0 })
        .map(|j| (keys[j].clone(), values[j]))
        .collect();
    let mut nested: Vec<Vec<i64>> = (0..if kind == "mutate_nested" { size } else { 0 })
        .map(|j| (0..4).map(|k| (seed + j as i64 * 13 + k) % 1009).collect())
        .collect();
    let program = PROGRAM.to_vec();
    let mut checksum = 0;
    let start = Instant::now();
    for batch in 0..iterations {
        let part: i64 = match case_id {
            0 => values.iter().map(|v| (v + batch) % 1009).sum(),
            1 => {
                let mut xs = Vec::new();
                for j in 0..size {
                    xs.push((seed + batch + j as i64 * 13) % 1009);
                }
                fold(&xs)
            }
            2 => {
                let xs: Vec<i64> = (0..size)
                    .map(|j| (seed + batch + j as i64 * 13) % 1009)
                    .collect();
                let filtered: Vec<i64> = xs.iter().copied().filter(|v| v % 3 == 0).collect();
                fold(&filtered)
            }
            3 => {
                let mut sum = 0;
                for j in 0..size {
                    let k = (seed + j as i64 * 17 + batch) % (size as i64 * 2);
                    sum += lookup.get(&k).copied().unwrap_or(17);
                }
                sum
            }
            4 => {
                let mut sum = 0;
                for j in 0..size {
                    let k = ((seed + j as i64 * 17 + batch) % (size as i64 * 2)) as usize;
                    sum += lookup_str.get(&keys[k]).copied().unwrap_or(17);
                }
                sum
            }
            5 => {
                let mut map = HashMap::new();
                for j in 0..size {
                    map.insert(j as i64, values[j]);
                }
                for j in 0..size * 2 {
                    let k = (seed + j as i64 * 17 + batch) % (size as i64 * 2);
                    let old = map.get(&k).copied().unwrap_or(17);
                    map.insert(k, (old + j as i64 + batch + 1) % 1000003);
                }
                map.iter().map(|(k, v)| k + v).sum()
            }
            6 => {
                let mut map = HashMap::new();
                for j in 0..size {
                    map.insert(keys[j].clone(), values[j]);
                }
                for j in 0..size * 2 {
                    let k = ((seed + j as i64 * 17 + batch) % (size as i64 * 2)) as usize;
                    let old = map.get(&keys[k]).copied().unwrap_or(17);
                    map.insert(keys[k].clone(), (old + j as i64 + batch + 1) % 1000003);
                }
                let mut sum = 0;
                for (k, key) in keys.iter().enumerate() {
                    if let Some(v) = map.get(key) {
                        sum += k as i64 + v;
                    }
                }
                sum
            }
            7 => {
                let mut set = HashSet::new();
                for j in 0..size {
                    set.insert((seed + batch + j as i64 * 13) % (2.max(size / 4) as i64));
                }
                set.iter().sum()
            }
            8 => {
                let mut sum = 0;
                for j in 0..size {
                    let xs: Vec<i64> = (0..4).map(|k| seed + batch + j as i64 + k).collect();
                    sum += xs.iter().sum::<i64>();
                }
                sum
            }
            9 => {
                let mut lists = Vec::new();
                for j in 0..size {
                    lists.push(
                        (0..4)
                            .map(|k| seed + batch + j as i64 + k)
                            .collect::<Vec<i64>>(),
                    );
                }
                lists.iter().map(|xs| xs.iter().sum::<i64>()).sum()
            }
            10 => {
                let snapshot = nested.clone();
                let index = ((seed + batch * 17) % size as i64) as usize;
                nested[index][1] = (nested[index][1] + batch + 1) % 1000003;
                snapshot[index][1] + nested[index][1]
            }
            11 => {
                let mut xs: Vec<i64> = (0..size)
                    .map(|j| (seed + batch + j as i64 * 13) % 1009)
                    .collect();
                xs.sort();
                fold(&xs)
            }
            12 => {
                let mut rows: Vec<Row> = (0..size)
                    .map(|j| {
                        let value = (seed + batch + j as i64 * 13) % 1009;
                        Row {
                            key: value % 17,
                            ordinal: j as i64,
                            value,
                        }
                    })
                    .collect();
                rows.sort_by_key(|r| r.key);
                rows.iter()
                    .enumerate()
                    .map(|(i, r)| (i as i64 + 1) * (r.value * 17 + r.ordinal))
                    .sum()
            }
            13 => execute(&program, size, seed + batch),
            _ => panic!("unknown case"),
        };
        checksum = (checksum + part) % MOD;
    }
    let elapsed = start.elapsed().as_nanos();
    if kind == "mutate_nested" {
        for xs in nested {
            for v in xs {
                checksum = (checksum + v) % MOD;
            }
        }
    }
    println!("{} {}", checksum, elapsed);
}
