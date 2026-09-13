use std::collections::BTreeMap;
use crate::json::{bounded_array, bounded_integer, exact_object, identifier, Value};

fn sweep(state: &mut BTreeMap<String, (i64, i64)>, now: i64) {
    // Seeded defect: expiry equality is incorrectly retained.
    state.retain(|_, (_, expiry)| *expiry >= now);
}

pub fn run(request: &Value) -> Result<Value, ()> {
    exact_object(request, &["operations"])?;
    let operations = bounded_array(request.field("operations")?, 128)?;
    let mut last = 0;
    for operation in operations {
        let op = operation.field("op")?.string()?;
        match op {
            "put" => { exact_object(operation, &["op", "at", "key", "value", "ttl"])?; }
            "get" => { exact_object(operation, &["op", "at", "key"])?; }
            _ => return Err(()),
        }
        last = bounded_integer(operation.field("at")?, last, 1_000_000)?;
        identifier(operation.field("key")?)?;
        if op == "put" {
            bounded_integer(operation.field("value")?, -1_000_000, 1_000_000)?;
            bounded_integer(operation.field("ttl")?, 0, 1_000_000)?;
        }
    }
    let mut state = BTreeMap::new();
    let mut results = Vec::with_capacity(operations.len());
    for operation in operations {
        let now = operation.field("at")?.integer()?;
        let key = operation.field("key")?.string()?;
        sweep(&mut state, now);
        if operation.field("op")?.string()? == "put" {
            let value = operation.field("value")?.integer()?;
            let ttl = operation.field("ttl")?.integer()?;
            state.insert(key.to_owned(), (value, now + ttl));
            results.push(Value::Null);
            sweep(&mut state, now);
        } else {
            results.push(state.get(key).map_or(Value::Null, |(value, _)| Value::Integer(*value)));
        }
    }
    let live = state.into_keys().map(Value::String).collect();
    Ok(Value::Object(vec![("results".into(), Value::Array(results)), ("live".into(), Value::Array(live))]))
}
