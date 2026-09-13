use std::collections::BTreeSet;
use crate::json::{bounded_array, bounded_integer, exact_object, identifier, Value};

pub fn validate(request: &Value) -> Result<(), ()> {
    exact_object(request, &["accounts", "batches"])?;
    let mut known = BTreeSet::new();
    for account in bounded_array(request.field("accounts")?, 32)? {
        exact_object(account, &["id", "balance"])?;
        let id = identifier(account.field("id")?)?;
        bounded_integer(account.field("balance")?, 0, 1_000_000)?;
        if !known.insert(id) { return Err(()); }
    }
    for batch in bounded_array(request.field("batches")?, 32)? {
        for transfer in bounded_array(batch, 32)? {
            exact_object(transfer, &["from", "to", "amount"])?;
            identifier(transfer.field("from")?)?;
            identifier(transfer.field("to")?)?;
            bounded_integer(transfer.field("amount")?, 0, 1_000_000)?;
        }
    }
    Ok(())
}
