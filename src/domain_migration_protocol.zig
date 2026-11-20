//! Shared scalar-domain diagnostic protocol for checker and fix driver.
/// Stable removal diagnostic for scalar domains and their operation surface.
pub const removed_code = "E_DOMAIN_REMOVED";
/// An incomplete typed check defers destructive domain edits across all roots.
pub const deferred_message = "scalar domains and type-owned operations were removed; automatic migration is deferred until other diagnostics are repaired";
