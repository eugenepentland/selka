use std::collections::BTreeMap;
use crate::json::Value;

#[derive(Clone)]
#[allow(dead_code)] // Populated by the reservation feature during the timed task.
pub struct Reservation { pub item: String, pub quantity: i64 }

pub fn initial(stock: &[Value]) -> Result<BTreeMap<String, i64>, ()> {
    stock.iter().map(|item| Ok((item.field("id")?.string()?.to_owned(), item.field("quantity")?.integer()?))).collect()
}

pub fn apply(_available: &mut BTreeMap<String, i64>, _reservations: &mut BTreeMap<String, Reservation>, _operation: &Value) -> Result<&'static str, ()> {
    // Inventory loading/reporting exists; reservation transitions are the feature.
    Ok("unsupported-operation")
}
