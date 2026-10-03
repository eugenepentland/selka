//! Shared bounded source authority for native invariant dispatch copies.
const bytecode = @import("bytecode.zig");
/// No partial literal selection: larger dispatches retain their original loop.
pub const max_values = 16;
/// Fixed bounded condition storage; recognition allocates no scratch arrays.
pub const max_conditions = 64;
/// One pure scalar comparison feeding an original conditional jump.
pub const Condition = struct { pc: usize, value: i64, predicate: bytecode.Predicate, target: usize };
/// Every comparison of the chosen invariant local in the loop.
pub const Conditions = struct { items: [max_conditions]Condition = undefined, len: usize = 0 };
/// The complete set of equality literals admitted by one dispatch.
pub const Values = struct { items: [max_values]i64 = undefined, len: usize = 0 };
/// Bytecode authority for a single-entry loop and its immutable scalar local.
pub const Certificate = struct { head: usize, back: usize, slot: usize, conditions: Conditions, values: Values };
