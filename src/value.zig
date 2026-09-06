//! Public value API for the shared runtime ownership model.
const implementation = @import("runtime_values.zig");
pub const Type = implementation.Type;
pub const Value = implementation.Value;
pub const Aggregate = implementation.Aggregate;
pub const Resource = implementation.Resource;
pub const ExternalResource = implementation.ExternalResource;
pub const EnvironmentCapability = implementation.EnvironmentCapability;
pub const PoolSchema = implementation.PoolSchema;
