//! Shared frontend export snapshot consumed by independent native backends.
const typed = @import("typed.zig");
/// Public declaration roots and exact language-schema-v1 bytes from one check.
pub const Interface = struct { roots: []const typed.FunctionId = &.{}, schema: ?[]const u8 = null };
