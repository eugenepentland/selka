//! Frozen, standard-library-only JSON support for the Rust benchmark arm.
//! Object fields retain source order so duplicate names can be rejected.
#![allow(dead_code)] // The blank template intentionally exposes task-specific helpers.

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Integer(i64),
    Decimal(String),
    String(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

impl Value {
    pub fn object(&self) -> Result<&[(String, Value)], ()> {
        if let Self::Object(value) = self { Ok(value) } else { Err(()) }
    }

    pub fn array(&self) -> Result<&[Value], ()> {
        if let Self::Array(value) = self { Ok(value) } else { Err(()) }
    }

    pub fn string(&self) -> Result<&str, ()> {
        if let Self::String(value) = self { Ok(value) } else { Err(()) }
    }

    pub fn integer(&self) -> Result<i64, ()> {
        if let Self::Integer(value) = self { Ok(*value) } else { Err(()) }
    }

    pub fn field(&self, name: &str) -> Result<&Value, ()> {
        self.object()?.iter().find(|(key, _)| key == name).map(|(_, value)| value).ok_or(())
    }
}

pub fn exact_object<'a>(value: &'a Value, fields: &[&str]) -> Result<&'a [(String, Value)], ()> {
    let object = value.object()?;
    if object.len() != fields.len() || !fields.iter().all(|name| object.iter().any(|(key, _)| key == name)) {
        return Err(());
    }
    Ok(object)
}

pub fn bounded_integer(value: &Value, low: i64, high: i64) -> Result<i64, ()> {
    let value = value.integer()?;
    if (low..=high).contains(&value) { Ok(value) } else { Err(()) }
}

pub fn bounded_array(value: &Value, maximum: usize) -> Result<&[Value], ()> {
    let value = value.array()?;
    if value.len() <= maximum { Ok(value) } else { Err(()) }
}

pub fn identifier(value: &Value) -> Result<&str, ()> {
    let value = value.string()?;
    let bytes = value.as_bytes();
    if bytes.is_empty() || bytes.len() > 32 || !bytes[0].is_ascii_lowercase()
        || !bytes[1..].iter().all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || *byte == b'_' || *byte == b'-') {
        return Err(());
    }
    Ok(value)
}

pub fn parse(source: &str) -> Result<Value, ()> {
    let mut parser = Parser { bytes: source.as_bytes(), at: 0 };
    let value = parser.value(1)?;
    parser.whitespace();
    if parser.at == parser.bytes.len() { Ok(value) } else { Err(()) }
}

struct Parser<'a> { bytes: &'a [u8], at: usize }

impl Parser<'_> {
    fn whitespace(&mut self) {
        while self.at < self.bytes.len() && matches!(self.bytes[self.at], b' ' | b'\n' | b'\r' | b'\t') { self.at += 1; }
    }

    fn value(&mut self, depth: usize) -> Result<Value, ()> {
        self.whitespace();
        match self.bytes.get(self.at).copied() {
            Some(b'n') => { self.literal(b"null")?; Ok(Value::Null) }
            Some(b't') => { self.literal(b"true")?; Ok(Value::Bool(true)) }
            Some(b'f') => { self.literal(b"false")?; Ok(Value::Bool(false)) }
            Some(b'"') => Ok(Value::String(self.string()?)),
            Some(b'[') => self.array(depth),
            Some(b'{') => self.object(depth),
            Some(b'-' | b'0'..=b'9') => self.number(),
            _ => Err(()),
        }
    }

    fn literal(&mut self, expected: &[u8]) -> Result<(), ()> {
        if self.bytes.get(self.at..self.at + expected.len()) == Some(expected) {
            self.at += expected.len(); Ok(())
        } else { Err(()) }
    }

    fn array(&mut self, depth: usize) -> Result<Value, ()> {
        if depth > 32 { return Err(()); }
        self.at += 1;
        let mut values = Vec::new();
        self.whitespace();
        if self.bytes.get(self.at) == Some(&b']') { self.at += 1; return Ok(Value::Array(values)); }
        loop {
            values.push(self.value(depth + 1)?);
            self.whitespace();
            match self.bytes.get(self.at) {
                Some(b',') => self.at += 1,
                Some(b']') => { self.at += 1; return Ok(Value::Array(values)); }
                _ => return Err(()),
            }
        }
    }

    fn object(&mut self, depth: usize) -> Result<Value, ()> {
        if depth > 32 { return Err(()); }
        self.at += 1;
        let mut fields: Vec<(String, Value)> = Vec::new();
        self.whitespace();
        if self.bytes.get(self.at) == Some(&b'}') { self.at += 1; return Ok(Value::Object(fields)); }
        loop {
            self.whitespace();
            if self.bytes.get(self.at) != Some(&b'"') { return Err(()); }
            let key = self.string()?;
            if fields.iter().any(|(known, _)| known == &key) { return Err(()); }
            self.whitespace();
            if self.bytes.get(self.at) != Some(&b':') { return Err(()); }
            self.at += 1;
            let value = self.value(depth + 1)?;
            fields.push((key, value));
            self.whitespace();
            match self.bytes.get(self.at) {
                Some(b',') => self.at += 1,
                Some(b'}') => { self.at += 1; return Ok(Value::Object(fields)); }
                _ => return Err(()),
            }
        }
    }

    fn string(&mut self) -> Result<String, ()> {
        self.at += 1;
        let mut result = String::new();
        let mut plain = self.at;
        while self.at < self.bytes.len() {
            match self.bytes[self.at] {
                b'"' => {
                    result.push_str(std::str::from_utf8(&self.bytes[plain..self.at]).map_err(|_| ())?);
                    self.at += 1;
                    return Ok(result);
                }
                b'\\' => {
                    result.push_str(std::str::from_utf8(&self.bytes[plain..self.at]).map_err(|_| ())?);
                    self.at += 1;
                    let escaped = *self.bytes.get(self.at).ok_or(())?;
                    self.at += 1;
                    match escaped {
                        b'"' => result.push('"'), b'\\' => result.push('\\'), b'/' => result.push('/'),
                        b'b' => result.push('\u{0008}'), b'f' => result.push('\u{000c}'),
                        b'n' => result.push('\n'), b'r' => result.push('\r'), b't' => result.push('\t'),
                        b'u' => {
                            let first = self.hex4()?;
                            let scalar = if (0xd800..=0xdbff).contains(&first) {
                                if self.bytes.get(self.at..self.at + 2) != Some(b"\\u") { return Err(()); }
                                self.at += 2;
                                let second = self.hex4()?;
                                if !(0xdc00..=0xdfff).contains(&second) { return Err(()); }
                                0x10000 + ((first - 0xd800) << 10) + second - 0xdc00
                            } else {
                                if (0xdc00..=0xdfff).contains(&first) { return Err(()); }
                                first
                            };
                            result.push(char::from_u32(scalar).ok_or(())?);
                        }
                        _ => return Err(()),
                    }
                    plain = self.at;
                }
                0..=31 => return Err(()),
                _ => self.at += 1,
            }
        }
        Err(())
    }

    fn hex4(&mut self) -> Result<u32, ()> {
        let digits = self.bytes.get(self.at..self.at + 4).ok_or(())?;
        let mut value = 0;
        for digit in digits {
            value = value * 16 + match digit {
                b'0'..=b'9' => (digit - b'0') as u32,
                b'a'..=b'f' => (digit - b'a' + 10) as u32,
                b'A'..=b'F' => (digit - b'A' + 10) as u32,
                _ => return Err(()),
            };
        }
        self.at += 4;
        Ok(value)
    }

    fn number(&mut self) -> Result<Value, ()> {
        let start = self.at;
        if self.bytes.get(self.at) == Some(&b'-') { self.at += 1; }
        match self.bytes.get(self.at) {
            Some(b'0') => self.at += 1,
            Some(b'1'..=b'9') => { self.at += 1; while matches!(self.bytes.get(self.at), Some(b'0'..=b'9')) { self.at += 1; } }
            _ => return Err(()),
        }
        let mut decimal = false;
        if self.bytes.get(self.at) == Some(&b'.') {
            decimal = true; self.at += 1;
            let before = self.at;
            while matches!(self.bytes.get(self.at), Some(b'0'..=b'9')) { self.at += 1; }
            if before == self.at { return Err(()); }
        }
        if matches!(self.bytes.get(self.at), Some(b'e' | b'E')) {
            decimal = true; self.at += 1;
            if matches!(self.bytes.get(self.at), Some(b'+' | b'-')) { self.at += 1; }
            let before = self.at;
            while matches!(self.bytes.get(self.at), Some(b'0'..=b'9')) { self.at += 1; }
            if before == self.at { return Err(()); }
        }
        let token = std::str::from_utf8(&self.bytes[start..self.at]).map_err(|_| ())?;
        if decimal {
            let finite = token.parse::<f64>().map_err(|_| ())?;
            if !finite.is_finite() { return Err(()); }
            Ok(Value::Decimal(token.to_owned()))
        } else {
            Ok(Value::Integer(token.parse().map_err(|_| ())?))
        }
    }
}

pub fn encode(value: &Value) -> String {
    let mut output = String::new();
    write(value, &mut output);
    output
}

fn write(value: &Value, output: &mut String) {
    match value {
        Value::Null => output.push_str("null"),
        Value::Bool(value) => output.push_str(if *value { "true" } else { "false" }),
        Value::Integer(value) => output.push_str(&value.to_string()),
        Value::Decimal(value) => output.push_str(value),
        Value::String(value) => string(value, output),
        Value::Array(values) => {
            output.push('[');
            for (index, value) in values.iter().enumerate() { if index != 0 { output.push(','); } write(value, output); }
            output.push(']');
        }
        Value::Object(fields) => {
            output.push('{');
            for (index, (key, value)) in fields.iter().enumerate() {
                if index != 0 { output.push(','); }
                string(key, output); output.push(':'); write(value, output);
            }
            output.push('}');
        }
    }
}

fn string(value: &str, output: &mut String) {
    output.push('"');
    for character in value.chars() {
        match character {
            '"' => output.push_str("\\\""), '\\' => output.push_str("\\\\"),
            '\u{0008}' => output.push_str("\\b"), '\u{000c}' => output.push_str("\\f"),
            '\n' => output.push_str("\\n"), '\r' => output.push_str("\\r"), '\t' => output.push_str("\\t"),
            value if value < '\u{0020}' => output.push_str(&format!("\\u{:04x}", value as u32)),
            value => output.push(value),
        }
    }
    output.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_and_reject_duplicates() {
        let source = r#"{"a":[1,true,null,"x\u0000\ud83d\ude00"],"n":1.5e2}"#;
        assert_eq!(parse(&encode(&parse(source).unwrap())).unwrap(), parse(source).unwrap());
        assert!(parse(r#"{"a":1,"a":2}"#).is_err());
        assert!(parse("[1] trailing").is_err());
    }
}
