use serde_json::{json, Value};
use std::collections::HashMap;
use std::time::Instant;
const MOD: i64 = 1_000_000_007;
#[derive(Default)]
struct Inputs {
    raw: Vec<u8>,
    texts: Vec<String>,
    other: Vec<String>,
    numbers: Vec<i64>,
    fragments: Vec<String>,
}
fn score(text: &str) -> i64 {
    text.len() as i64 + text.bytes().map(i64::from).sum::<i64>()
}
fn name(j: usize) -> String {
    format!(
        "{}{}",
        if j % 2 == 0 {
            "café,\"item\""
        } else {
            "naïve,item"
        },
        j
    )
}
fn inputs(case: &str, size: usize, seed: i64) -> Inputs {
    let mut d = Inputs::default();
    match case {
        "bytes_scan" => {
            d.raw = (0..size)
                .map(|j| ((seed + j as i64 * 37) % 256) as u8)
                .collect()
        }
        "string_equal" => {
            d.texts = vec![
                "a".repeat(size),
                "é".repeat(size),
                "a".repeat(size),
                format!("café{seed}"),
            ];
            d.other = vec![
                "a".repeat(size),
                "é".repeat(size - 1) + "ê",
                "b".to_owned() + &"a".repeat(size - 1),
                format!("café{seed}"),
            ];
        }
        "string_search" => {
            d.texts = vec![format!("{};café;needle;{seed}", "a".repeat(size))];
            d.other = ["a", "needle", "absentΩ", "é"]
                .iter()
                .map(|s| s.to_string())
                .collect();
        }
        "string_split" | "string_join" => {
            let options = ["", "alpha", "café", "x", "naïve"];
            d.fragments = (0..size)
                .map(|j| options[(seed as usize + j) % 5].to_string())
                .collect();
            d.texts = vec![d.fragments.join("|"), d.fragments.join("::")];
        }
        "int_parse" => {
            d.texts = (0..size)
                .map(|j| {
                    let n = (seed + j as i64 * 137) % 1_000_003;
                    match j % 6 {
                        0 => n.to_string(),
                        1 => format!("-{n}"),
                        2 => format!("00{n}"),
                        3 => format!("{n}x"),
                        4 => "oops".to_owned(),
                        _ => String::new(),
                    }
                })
                .collect();
        }
        "int_format" => {
            d.numbers = (0..size)
                .map(|j| {
                    let n = (seed + j as i64 * 137) % 1_000_003;
                    if j % 3 == 0 {
                        -n
                    } else {
                        n
                    }
                })
                .collect()
        }
        "word_count" => {
            let vocabulary = [
                "red", "blue", "café", "red", "green", "blue", "naïve", "red",
            ];
            let separators = [" ", "\t", "\n", "  "];
            let text = (0..size)
                .map(|j| {
                    format!(
                        "{}{}",
                        vocabulary[(seed as usize + j) % 8],
                        separators[j % 4]
                    )
                })
                .collect::<String>();
            d.texts = vec![text.clone() + "red", text + "blue"];
        }
        "csv_aggregate" => {
            let regions = ["east", "west", "north"];
            let text = (0..size)
                .map(|j| {
                    let amount = if j % 11 == 0 {
                        "oops".to_owned()
                    } else {
                        ((seed + j as i64 * 19) % 100_003).to_string()
                    };
                    format!(
                        "{},\"{}\",{},{},{}\n",
                        seed + j as i64,
                        name(j).replace('"', "\"\""),
                        regions[(seed as usize + j) % 3],
                        amount,
                        if (seed as usize + j) % 3 != 0 {
                            "1"
                        } else {
                            "0"
                        }
                    )
                })
                .collect();
            d.texts = vec![text];
        }
        "json_transform" => {
            let rows:Vec<Value>=(0..size).map(|j|json!({"id":seed+j as i64,"name":name(j),"amount":(seed+j as i64*19)%100_003,"active":(seed as usize+j)%3!=0})).collect();
            d.texts = vec![serde_json::to_string(&rows).unwrap()];
        }
        _ => panic!("unknown case"),
    }
    d
}
// Same documented CSV subset as the other ports; UTF-8 scalars preserve names.
fn csv_rows(text: &str) -> Vec<Vec<String>> {
    let mut rows = Vec::new();
    let mut fields = Vec::new();
    let mut field = String::new();
    let mut quoted = false;
    let mut chars = text.chars().peekable();
    while let Some(ch) = chars.next() {
        if quoted {
            if ch == '"' {
                if chars.peek() == Some(&'"') {
                    field.push('"');
                    chars.next();
                } else {
                    quoted = false;
                }
            } else {
                field.push(ch);
            }
        } else {
            match ch {
                '"' => quoted = true,
                ',' => fields.push(std::mem::take(&mut field)),
                '\n' => {
                    fields.push(std::mem::take(&mut field));
                    rows.push(std::mem::take(&mut fields));
                }
                _ => field.push(ch),
            }
        }
    }
    assert!(!quoted && field.is_empty() && fields.is_empty());
    rows
}
fn word_job(text: &str) -> i64 {
    let mut counts: HashMap<&str, i64> = HashMap::new();
    for word in text.split_ascii_whitespace() {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
        .into_iter()
        .map(|(word, n)| score(word) * n * n)
        .sum()
}
fn csv_job(text: &str) -> i64 {
    let mut groups: HashMap<String, i64> = [
        ("east".to_owned(), 0),
        ("west".to_owned(), 0),
        ("north".to_owned(), 0),
    ]
    .into_iter()
    .collect();
    let (mut accepted, mut rejected, mut names) = (0, 0, 0);
    for row in csv_rows(text) {
        match row[3].parse::<i64>() {
            Ok(amount) => {
                if row[4] == "1" {
                    *groups.get_mut(&row[2]).unwrap() += amount;
                    accepted += 1;
                    names += score(&row[1]);
                }
            }
            Err(_) => rejected += 1,
        }
    }
    groups["east"]
        + groups["west"] * 2
        + groups["north"] * 3
        + accepted * 17
        + rejected * 101
        + names
}
fn json_job(text: &str, bump: i64) -> i64 {
    let rows: Vec<Value> = serde_json::from_str(text).unwrap();
    let output: Vec<Value> = rows
        .into_iter()
        .filter(|r| r["active"].as_bool().unwrap())
        .map(|r| json!({"id":r["id"],"name":r["name"],"amount":r["amount"].as_i64().unwrap()+bump}))
        .collect();
    score(&serde_json::to_string(&output).unwrap())
}

fn bytes_job(raw: &[u8], mask: u8) -> i64 {
    raw.iter().map(|value| i64::from(*value ^ mask)).sum()
}
fn search_job(text: &str, needle: &str) -> i64 {
    text.find(needle)
        .map(|pos| text[..pos].chars().count() as i64 + 1)
        .unwrap_or(0)
}
fn split_job(text: &str, separator: &str) -> i64 {
    let parts: Vec<&str> = text.split(separator).collect();
    parts.len() as i64 * 7 + parts.into_iter().map(score).sum::<i64>()
}
fn kernel(kind: &str, d: &Inputs, iterations: usize, seed: usize) -> i64 {
    let mut checksum: i64 = 0;
    match kind {
        "bytes_scan" => {
            for step in 0..iterations {
                let cursor = seed + step;
                let value = bytes_job(&d.raw, (cursor % 256) as u8);
                checksum = (checksum + value).rem_euclid(MOD);
            }
        }
        "string_equal" => {
            for step in 0..iterations {
                let cursor = seed + step;
                let value = i64::from(d.texts[cursor % 4] == d.other[cursor % 4]);
                checksum = (checksum + value).rem_euclid(MOD);
            }
        }
        "string_search" => {
            for step in 0..iterations {
                let cursor = seed + step;
                let value = search_job(&d.texts[0], &d.other[cursor % 4]);
                checksum = (checksum + value).rem_euclid(MOD);
            }
        }
        "string_split" => {
            for step in 0..iterations {
                let cursor = seed + step;
                let value = split_job(
                    &d.texts[cursor % 2],
                    if cursor % 2 == 0 { "|" } else { "::" },
                );
                checksum = (checksum + value).rem_euclid(MOD);
            }
        }
        "string_join" => {
            for step in 0..iterations {
                let cursor = seed + step;
                let value = score(&d.fragments.join(if cursor % 2 == 0 { "|" } else { "::" }));
                checksum = (checksum + value).rem_euclid(MOD);
            }
        }
        "int_parse" => {
            for step in 0..iterations {
                let cursor = seed + step;
                let value = d.texts[cursor % d.texts.len()].parse::<i64>().unwrap_or(97);
                checksum = (checksum + value).rem_euclid(MOD);
            }
        }
        "int_format" => {
            for step in 0..iterations {
                let cursor = seed + step;
                let value = score(&d.numbers[cursor % d.numbers.len()].to_string());
                checksum = (checksum + value).rem_euclid(MOD);
            }
        }
        "word_count" => {
            for step in 0..iterations {
                let cursor = seed + step;
                let value = word_job(&d.texts[cursor % 2]);
                checksum = (checksum + value).rem_euclid(MOD);
            }
        }
        "csv_aggregate" => {
            for _ in 0..iterations {
                let value = csv_job(&d.texts[0]);
                checksum = (checksum + value).rem_euclid(MOD);
            }
        }
        "json_transform" => {
            for step in 0..iterations {
                let cursor = seed + step;
                let value = json_job(&d.texts[0], (cursor % 17) as i64);
                checksum = (checksum + value).rem_euclid(MOD);
            }
        }
        _ => unreachable!(),
    }
    checksum
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() != 4 {
        std::process::exit(2);
    }
    let cases = [
        "bytes_scan",
        "string_equal",
        "string_search",
        "string_split",
        "string_join",
        "int_parse",
        "int_format",
        "word_count",
        "csv_aggregate",
        "json_transform",
    ];
    if !cases.contains(&args[0].as_str()) {
        std::process::exit(2);
    }
    let size = args[1].parse::<usize>().unwrap_or(0);
    let iterations = args[2].parse::<usize>().unwrap_or(0);
    let seed = args[3].parse::<i64>().unwrap_or(0);
    if size < 2 || iterations < 1 || !(1..=1_000_000).contains(&seed) {
        std::process::exit(2);
    }
    let data = inputs(&args[0], size, seed);
    let start = Instant::now();
    let checksum = kernel(&args[0], &data, iterations, seed as usize);
    let elapsed = start.elapsed().as_nanos();
    println!("{checksum} {elapsed}");
}
