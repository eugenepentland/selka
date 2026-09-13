#[path = "model.rs"] mod model;
#[path = "ledger.rs"] mod ledger;

use std::collections::BTreeMap;
use crate::json::Value;

pub fn run(request: &Value) -> Result<Value, ()> {
    model::validate(request)?;
    let mut state: BTreeMap<String, i64> = request.field("accounts")?.array()?.iter().map(|account| Ok((
        account.field("id")?.string()?.to_owned(), account.field("balance")?.integer()?
    ))).collect::<Result<_, ()>>()?;
    let mut results = Vec::new();
    for operations in request.field("batches")?.array()? {
        let (next, status) = ledger::batch(&state, operations.array()?)?;
        state = next;
        results.push(Value::String(status.into()));
    }
    let balances = state.into_iter().map(|(id, balance)| Value::Object(vec![
        ("id".into(), Value::String(id)), ("balance".into(), Value::Integer(balance))
    ])).collect();
    Ok(Value::Object(vec![("results".into(), Value::Array(results)), ("balances".into(), Value::Array(balances))]))
}
