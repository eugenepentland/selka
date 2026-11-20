// json_roundtrip: generate a compact JSON text of nested records, parse it into a
// recursive enum, walk the tree into a checksum, and serialize it back (SUITE.md
// section 12). Decimals are parsed with str::parse::<f64> and printed from their
// scaled integers. Std only.
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

const ALPHA: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const LOWER: &[u8] = b"abcdefghijklmnopqrstuvwxyz";

/// The shared checksum step: `(c * 31 + v) mod 1000000007`, for non-negative `v`.
fn mix(c: u64, v: u64) -> u64 {
    (c * 31 + v) % 1_000_000_007
}

#[derive(Clone, Copy)]
struct Decimal {
    scaled: i64,
    value: f64,
}

enum Value {
    Null,
    Boolean(bool),
    Integer(i64),
    Decimal(Decimal),
    Text(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

struct Gen {
    x: u64,
}

impl Gen {
    fn full(&mut self) -> u64 {
        let mut x = self.x;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.x = x;
        x
    }

    fn draw(&mut self) -> u64 {
        self.full() >> 33
    }

    fn pick(&mut self, n: u64) -> u64 {
        self.draw() % n
    }
}

/// Writes one signed decimal with exactly three fractional digits; no sign for zero.
fn gen_decimal(gen: &mut Gen, text: &mut Vec<u8>) {
    let mag = gen.pick(2_000_000);
    let sign = gen.pick(2);
    if sign == 1 && mag > 0 {
        text.push(b'-');
    }
    text.extend_from_slice(format!("{}.{:03}", mag / 1000, mag % 1000).as_bytes());
}

/// Writes one record at nesting depth `depth`, as SUITE.md section 12 describes.
fn gen_record(gen: &mut Gen, text: &mut Vec<u8>, depth: u32) {
    text.extend_from_slice(format!("{{\"id\":{}", gen.draw()).as_bytes());
    let length = 4 + gen.pick(12);
    text.extend_from_slice(b",\"name\":\"");
    for _ in 0..length {
        let r = gen.pick(16);
        if r == 0 {
            text.extend_from_slice(b"\\\"");
        } else if r == 1 {
            text.extend_from_slice(b"\\\\");
        } else if r == 2 {
            text.extend_from_slice(b"\\n");
        } else {
            text.push(ALPHA[gen.pick(62) as usize]);
        }
    }
    text.push(b'"');
    text.extend_from_slice(b",\"pos\":[");
    gen_decimal(gen, text);
    text.push(b',');
    gen_decimal(gen, text);
    text.extend_from_slice(b"],\"tags\":[");
    let tags = gen.pick(5);
    for t in 0..tags {
        if t > 0 {
            text.push(b',');
        }
        let letters = 1 + gen.pick(4);
        text.push(b'"');
        for _ in 0..letters {
            text.push(LOWER[gen.pick(26) as usize]);
        }
        text.push(b'"');
    }
    text.extend_from_slice(b"],\"child\":");
    if depth < 3 && gen.pick(3) != 0 {
        gen_record(gen, text, depth + 1);
    } else {
        text.extend_from_slice(b"null");
    }
    text.push(b'}');
}

/// A recursive-descent parser over the generated text.
struct Parser<'a> {
    text: &'a [u8],
    pos: usize,
}

impl Parser<'_> {
    fn parse_value(&mut self) -> Value {
        match self.text[self.pos] {
            b'n' => {
                self.pos += 4;
                Value::Null
            }
            b't' => {
                self.pos += 4;
                Value::Boolean(true)
            }
            b'f' => {
                self.pos += 5;
                Value::Boolean(false)
            }
            b'"' => Value::Text(self.parse_string()),
            b'[' => self.parse_array(),
            b'{' => self.parse_object(),
            _ => self.parse_number(),
        }
    }

    fn parse_string(&mut self) -> String {
        self.pos += 1;
        let mut out: Vec<u8> = Vec::new();
        while self.text[self.pos] != b'"' {
            if self.text[self.pos] == b'\\' {
                self.pos += 1;
                out.push(match self.text[self.pos] {
                    b'n' => b'\n',
                    b'"' => b'"',
                    b'\\' => b'\\',
                    _ => panic!("unsupported escape"),
                });
            } else {
                out.push(self.text[self.pos]);
            }
            self.pos += 1;
        }
        self.pos += 1;
        String::from_utf8(out).unwrap()
    }

    fn parse_number(&mut self) -> Value {
        let start = self.pos;
        let mut has_dot = false;
        while self.pos < self.text.len() {
            let c = self.text[self.pos];
            if c == b'.' {
                has_dot = true;
            } else if c != b'-' && !c.is_ascii_digit() {
                break;
            }
            self.pos += 1;
        }
        let token = std::str::from_utf8(&self.text[start..self.pos]).unwrap();
        if !has_dot {
            return Value::Integer(token.parse::<i64>().unwrap());
        }
        let value: f64 = token.parse().unwrap();
        let negative = token.starts_with('-');
        let digits = if negative { &token[1..] } else { token };
        let dot = digits.find('.').unwrap();
        let whole: i64 = digits[..dot].parse().unwrap();
        let frac: i64 = digits[dot + 1..dot + 4].parse().unwrap();
        let magnitude = whole * 1000 + frac;
        Value::Decimal(Decimal { scaled: if negative { -magnitude } else { magnitude }, value })
    }

    fn parse_array(&mut self) -> Value {
        self.pos += 1;
        let mut items = Vec::new();
        if self.text[self.pos] == b']' {
            self.pos += 1;
            return Value::Array(items);
        }
        loop {
            items.push(self.parse_value());
            let sep = self.text[self.pos];
            self.pos += 1;
            if sep != b',' {
                break;
            }
        }
        Value::Array(items)
    }

    fn parse_object(&mut self) -> Value {
        self.pos += 1;
        let mut members = Vec::new();
        if self.text[self.pos] == b'}' {
            self.pos += 1;
            return Value::Object(members);
        }
        loop {
            let key = self.parse_string();
            self.pos += 1;
            let value = self.parse_value();
            members.push((key, value));
            let sep = self.text[self.pos];
            self.pos += 1;
            if sep != b',' {
                break;
            }
        }
        Value::Object(members)
    }
}

/// Folds one value into the walk checksum, in document order.
fn walk(value: &Value, c: &mut u64) {
    match value {
        Value::Null => *c = mix(*c, 1),
        Value::Boolean(b) => *c = mix(*c, if *b { 3 } else { 2 }),
        Value::Integer(n) => {
            *c = mix(*c, 4);
            *c = mix(*c, n.unsigned_abs());
        }
        Value::Decimal(d) => {
            *c = mix(*c, 5);
            let scaled = (d.value * 1e9) as i64;
            *c = mix(*c, scaled.unsigned_abs());
        }
        Value::Text(s) => {
            *c = mix(*c, 6);
            *c = mix(*c, s.len() as u64);
        }
        Value::Array(items) => {
            *c = mix(*c, 7);
            *c = mix(*c, items.len() as u64);
            for item in items {
                walk(item, c);
            }
        }
        Value::Object(members) => {
            *c = mix(*c, 8);
            *c = mix(*c, members.len() as u64);
            for (key, member) in members {
                *c = mix(*c, key.len() as u64);
                walk(member, c);
            }
        }
    }
}

/// Appends the compact JSON form of `value` to `out`.
fn serialize(value: &Value, out: &mut Vec<u8>) {
    match value {
        Value::Null => out.extend_from_slice(b"null"),
        Value::Boolean(b) => out.extend_from_slice(if *b { b"true" } else { b"false" }),
        Value::Integer(n) => out.extend_from_slice(n.to_string().as_bytes()),
        Value::Decimal(d) => {
            let magnitude = d.scaled.unsigned_abs();
            if d.scaled < 0 {
                out.push(b'-');
            }
            out.extend_from_slice(format!("{}.{:03}", magnitude / 1000, magnitude % 1000).as_bytes());
        }
        Value::Text(s) => {
            out.push(b'"');
            for &byte in s.as_bytes() {
                match byte {
                    b'"' => out.extend_from_slice(b"\\\""),
                    b'\\' => out.extend_from_slice(b"\\\\"),
                    b'\n' => out.extend_from_slice(b"\\n"),
                    _ => out.push(byte),
                }
            }
            out.push(b'"');
        }
        Value::Array(items) => {
            out.push(b'[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                serialize(item, out);
            }
            out.push(b']');
        }
        Value::Object(members) => {
            out.push(b'{');
            for (i, (key, member)) in members.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                out.extend_from_slice(format!("\"{}\":", key).as_bytes());
                serialize(member, out);
            }
            out.push(b'}');
        }
    }
}

fn main() -> io::Result<()> {
    let records = black_box(120_000usize);
    let mut gen = Gen { x: 88172645463325252 };
    let mut text: Vec<u8> = vec![b'['];
    for r in 0..records {
        if r > 0 {
            text.push(b',');
        }
        gen_record(&mut gen, &mut text, 0);
    }
    text.push(b']');

    let mut parser = Parser { text: &text, pos: 0 };
    let root = parser.parse_value();

    let mut walk_sum: u64 = 0;
    walk(&root, &mut walk_sum);
    let mut serialized: Vec<u8> = Vec::with_capacity(text.len());
    serialize(&root, &mut serialized);
    let mut serialized_mix: u64 = 0;
    for &byte in &serialized {
        serialized_mix = mix(serialized_mix, byte as u64);
    }

    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "records {} text {} walk {}", records, text.len(), walk_sum)?;
    writeln!(out, "serialized {} mix {}", serialized.len(), serialized_mix)?;
    if serialized == text {
        writeln!(out, "roundtrip ok")?;
    } else {
        writeln!(out, "roundtrip mismatch")?;
    }
    out.flush()
}
