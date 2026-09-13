//! Frozen process transport; application behavior lives in app.rs.
mod app;
mod json;

use std::io::{self, Read};
use json::Value;

fn invalid_envelope() -> Value {
    Value::Object(vec![("error".into(), Value::String("invalid-envelope".into()))])
}

fn execute() -> Value {
    let mut bytes = Vec::new();
    if io::stdin().take(1_048_577).read_to_end(&mut bytes).is_err() || bytes.len() > 1_048_576 {
        return invalid_envelope();
    }
    let source = match std::str::from_utf8(&bytes) { Ok(value) => value, Err(_) => return invalid_envelope() };
    let envelope = match json::parse(source) { Ok(value) => value, Err(_) => return invalid_envelope() };
    let fields = match envelope.object() { Ok(value) if value.len() == 1 && value[0].0 == "requests" => value, _ => return invalid_envelope() };
    let requests = match fields[0].1.array() { Ok(value) if value.len() <= 64 => value, _ => return invalid_envelope() };
    let results = requests.iter().map(|request| app::run(request).unwrap_or_else(|_| {
        Value::Object(vec![("error".into(), Value::String("invalid-request".into()))])
    })).collect();
    Value::Object(vec![("results".into(), Value::Array(results))])
}

fn main() {
    println!("{}", json::encode(&execute()));
}
