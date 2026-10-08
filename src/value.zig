//! Public value API: compile-time scalar values and their type identities.
const implementation = @import("runtime_values.zig");
pub const Type = implementation.Type;
pub const Value = implementation.Value;
