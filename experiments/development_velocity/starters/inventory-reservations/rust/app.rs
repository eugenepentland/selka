#[path = "model.rs"] mod model;
#[path = "ledger.rs"] mod ledger;

use std::collections::BTreeMap;
use crate::json::Value;

pub fn run(request: &Value) -> Result<Value, ()> {
    model::validate(request)?;
    let mut available = ledger::initial(request.field("stock")?.array()?)?;
    let mut active: BTreeMap<String, ledger::Reservation> = BTreeMap::new();
    let results = request.field("operations")?.array()?.iter().map(|operation| {
        ledger::apply(&mut available, &mut active, operation).map(|status| Value::String(status.into()))
    }).collect::<Result<Vec<_>, _>>()?;
    let available = available.into_iter().map(|(id, quantity)| Value::Object(vec![
        ("id".into(), Value::String(id)), ("quantity".into(), Value::Integer(quantity))
    ])).collect();
    let active = active.into_keys().map(Value::String).collect();
    Ok(Value::Object(vec![("results".into(), Value::Array(results)),
        ("available".into(), Value::Array(available)), ("active".into(), Value::Array(active))]))
}
