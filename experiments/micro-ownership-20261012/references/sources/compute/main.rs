use std::{env, time::Instant};
const MOD: i64 = 1_000_000_007;
#[derive(Clone, Copy)]
struct Triple {
    a: i64,
    b: i64,
    c: i64,
}
struct Packet {
    identifier: i64,
    payload_sum: i64,
    length: i64,
}
fn affine_a(x: i64) -> i64 {
    x * 3 + 7
}
fn affine_b(x: i64) -> i64 {
    x * 5 + 11
}
fn score(r: Triple) -> i64 {
    r.a + r.b * 3 + r.c * 5
}
fn optional(x: i64, p: i64) -> Option<i64> {
    if x % 4 == 0 {
        None
    } else {
        Some(x + p)
    }
}
fn checked(x: i64, p: i64) -> Result<i64, i64> {
    if x % 5 == 0 {
        Err(1)
    } else {
        Ok(x + p)
    }
}
fn forwarded(x: i64, p: i64) -> Result<i64, i64> {
    let v = checked(x, p)?;
    Ok(v * 3 + 1)
}
fn search(xs: &[i64], key: i64) -> i64 {
    let (mut lo, mut hi) = (0, xs.len());
    while lo < hi {
        let mid = (lo + hi) / 2;
        if xs[mid] < key {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if lo < xs.len() && xs[lo] == key {
        lo as i64 + 1
    } else {
        0
    }
}
fn frame(j: i64, seed: i64) -> Vec<u8> {
    let id = (seed + j * 17) % 65536;
    let mut raw = vec![165, 1, (id / 256) as u8, (id % 256) as u8, 4];
    for k in 0..4 {
        raw.push(((seed + j * 13 + k * 7) % 256) as u8);
    }
    let check = raw.iter().map(|&b| b as i64).sum::<i64>() % 256;
    raw.push(check as u8);
    match j % 4 {
        1 => raw[0] = 164,
        2 => raw[9] = raw[9].wrapping_add(1),
        3 => raw[4] = 5,
        _ => (),
    };
    raw
}
fn decode(raw: &[u8]) -> Result<Packet, i64> {
    if raw.len() < 6 {
        return Err(3);
    }
    if raw[0] != 165 {
        return Err(1);
    }
    if raw[1] != 1 {
        return Err(2);
    }
    let length = raw[4] as usize;
    if raw.len() != length + 6 {
        return Err(3);
    }
    let check: i64 = raw[..raw.len() - 1].iter().map(|&b| b as i64).sum();
    if check % 256 != raw[raw.len() - 1] as i64 {
        return Err(4);
    }
    let total = raw[5..raw.len() - 1].iter().map(|&b| b as i64).sum();
    Ok(Packet {
        identifier: raw[2] as i64 * 256 + raw[3] as i64,
        payload_sum: total,
        length: length as i64,
    })
}
fn main() {
    let args: Vec<String> = env::args().collect();
    assert_eq!(args.len(), 5);
    let names = [
        "integer_math",
        "float_math",
        "branch_predictable",
        "branch_mixed",
        "record_construct",
        "record_update",
        "call_direct",
        "call_indirect",
        "option_handle",
        "result_propagate",
        "binary_search",
        "packet_decode",
    ];
    let kind = names
        .iter()
        .position(|s| *s == args[1])
        .expect("unknown case");
    let size: usize = args[2].parse().unwrap();
    let iterations: i64 = args[3].parse().unwrap();
    let seed: i64 = args[4].parse().unwrap();
    assert!(size >= 2 && iterations >= 1 && (1..=1000000).contains(&seed));
    let values: Vec<i64> = (0..size).map(|j| (seed + j as i64 * 37) % 1009).collect();
    let ordered: Vec<i64> = (0..size).map(|j| j as i64 * 3 + seed % 11).collect();
    let flags: Vec<bool> = (0..size)
        .map(|j| {
            if kind == 2 {
                j % 16 != 0
            } else {
                (values[j] * 73 + j as i64 * 19 + seed) % 101 < 50
            }
        })
        .collect();
    let records: Vec<Triple> = values
        .iter()
        .map(|&x| Triple {
            a: x,
            b: x % 17,
            c: x * 3 % 101,
        })
        .collect();
    let frames: Vec<Vec<u8>> = (0..size).map(|j| frame(j as i64, seed)).collect();
    let function: fn(i64) -> i64 = if seed % 2 == 0 { affine_a } else { affine_b };
    let mut checksum = 0;
    let start = Instant::now();
    for batch in 0..iterations {
        let phase = batch % 17;
        let mut pass_total = 0;
        for j in 0..size {
            let x = values[j];
            let value = match kind {
                0 => ((x + phase) * 17 + 23) / 7 % 1009,
                1 => {
                    (((x as f64 / 8.0 + phase as f64 / 4.0) * (x as f64 / 16.0 + 1.0) + 0.5)
                        * 128.0) as i64
                }
                2 | 3 => {
                    if flags[j] {
                        (x + phase) * 3 + 1
                    } else {
                        (x + phase) * 5 + 7
                    }
                }
                4 => score(Triple {
                    a: x + phase,
                    b: x % 17,
                    c: (x * 3 + phase) % 101,
                }),
                5 => {
                    let mut r = records[j];
                    r.a = x + phase;
                    r.b = x % 17;
                    r.c = (x * 3 + phase) % 101;
                    score(r)
                }
                6 => affine_a(x + phase),
                7 => function(x + phase),
                8 => match optional(x, phase) {
                    Some(v) => v * 3 + 1,
                    None => 19,
                },
                9 => match forwarded(x, phase) {
                    Ok(v) => v,
                    Err(e) => e * 7,
                },
                10 => search(&ordered, (x + phase) % (size as i64 * 3 + 3) + seed % 11),
                11 => match decode(&frames[j]) {
                    Ok(p) => p.identifier + p.payload_sum * 3 + p.length,
                    Err(e) => e * 101,
                },
                _ => unreachable!(),
            };
            pass_total += value;
        }
        checksum = (checksum + pass_total) % MOD;
    }
    let elapsed = start.elapsed().as_nanos();
    println!("{} {}", checksum, elapsed);
}
