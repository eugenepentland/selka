use std::collections::BTreeSet;
use crate::json::{bounded_array, bounded_integer, exact_object, identifier, Value};

pub fn validate(request: &Value) -> Result<(), ()> {
    exact_object(request, &["stock", "operations"])?;
    let mut known = BTreeSet::new();
    for item in bounded_array(request.field("stock")?, 32)? {
        exact_object(item, &["id", "quantity"])?;
        let id = identifier(item.field("id")?)?;
        bounded_integer(item.field("quantity")?, 0, 1_000_000)?;
        if !known.insert(id) { return Err(()); }
    }
    for operation in bounded_array(request.field("operations")?, 128)? {
        let op = operation.field("op")?.string()?;
        match op {
            "reserve" => {
                exact_object(operation, &["op", "token", "id", "quantity"])?;
                identifier(operation.field("id")?)?;
                bounded_integer(operation.field("quantity")?, 1, 1_000_000)?;
            }
            "release" => { exact_object(operation, &["op", "token"])?; }
            _ => return Err(()),
        }
        identifier(operation.field("token")?)?;
    }
    Ok(())
}
