use crate::json::{bounded_array, bounded_integer, exact_object, Value};

pub fn run(request: &Value) -> Result<Value, ()> {
    exact_object(request, &["limit", "used", "requests"])?;
    let limit = bounded_integer(request.field("limit")?, 0, 1_000_000)?;
    let mut used = bounded_integer(request.field("used")?, 0, limit)?;
    let amounts = bounded_array(request.field("requests")?, 128)?
        .iter().map(|value| bounded_integer(value, 0, 1_000_000)).collect::<Result<Vec<_>, _>>()?;
    let mut accepted = Vec::with_capacity(amounts.len());
    for amount in amounts {
        let allow = used + amount < limit;
        accepted.push(Value::Bool(allow));
        if allow { used += amount; }
    }
    Ok(Value::Object(vec![
        ("accepted".into(), Value::Array(accepted)),
        ("used".into(), Value::Integer(used)),
        ("remaining".into(), Value::Integer(limit - used)),
    ]))
}
