//! Public memory API for the shared runtime ownership model.
const implementation = @import("runtime_values.zig").Memory;
pub const Error = implementation.Error;
pub const Limits = implementation.Limits;
pub const Statistics = implementation.Statistics;
pub const BufferInfo = implementation.BufferInfo;
pub const Growth = implementation.Growth;
pub const Kind = implementation.Kind;
pub const Token = implementation.Token;
pub const AllocatorCapability = implementation.AllocatorCapability;
pub const BackingLease = implementation.BackingLease;
pub const Allocation = implementation.Allocation;
pub const Borrow = implementation.Borrow;
pub const View = implementation.View;
pub const Extent = implementation.Extent;
pub const Split = implementation.Split;
pub const Store = implementation.Store;
