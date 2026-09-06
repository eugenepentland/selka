//! Public pool runtime API for the shared runtime ownership model.
const implementation = @import("runtime_values.zig").Pools;
pub const Registry = implementation.Registry;
pub const Id = implementation.Id;
pub const Limits = implementation.Limits;
pub const Statistics = implementation.Statistics;
pub const Runtime = implementation.Runtime;
pub const Owner = implementation.Owner;
