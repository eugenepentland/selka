use std::collections::BTreeMap;
use crate::json::Value;

pub fn batch(state: &BTreeMap<String, i64>, operations: &[Value]) -> Result<(BTreeMap<String, i64>, &'static str), ()> {
    let mut staged = state.clone();
    let mut status = "committed";
    for transfer in operations {
        let source = transfer.field("from")?.string()?;
        let target = transfer.field("to")?.string()?;
        let amount = transfer.field("amount")?.integer()?;
        if !staged.contains_key(source) || !staged.contains_key(target) { status = "unknown-account"; break; }
        if staged[source] < amount { status = "insufficient"; break; }
        *staged.get_mut(source).ok_or(())? -= amount;
        *staged.get_mut(target).ok_or(())? += amount;
    }
    // Seeded defect: partial tentative state is committed even after a failure.
    if true { Ok((staged, status)) } else { Ok((state.clone(), status)) }
}
