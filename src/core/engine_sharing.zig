//! Where the compiler's engines find their shared tier (G4c): the compiler artifact store of the command.
//!
//! A command that went through `compiler_sharing.prepare` carries the store in its environment
//! (`SELKA_COMPILER_SHARED_CACHE`, set to the per-user default, or to "" when sharing is off), and `explicit` reads it. A command
//! that did not (the ordinary `selka check` opens its own artifact store by policy) resolves the same default with `byPolicy`.
//! Each engine opens its own handle on the store; opening one validates the namespace and costs a few small reads.
const std = @import("std");
const language = @import("selka");
const compiler_records = @import("engine/compiler_records.zig");

/// The store directory the environment names, or null when it names none or sharing is off (an empty value).
pub fn explicit(environment: *const std.process.Environ.Map) ?[]const u8 {
    return language.shared_artifact_store.selected(environment);
}

/// The store directory the environment names, else the per-user default while sharing is on by default (the rule of
/// `shared_artifact_store.openSelected`). A default path is allocated in `a`.
pub fn byPolicy(a: std.mem.Allocator, environment: *const std.process.Environ.Map) ?[]const u8 {
    const chosen = language.shared_cache_policy.resolve(a, environment, .compiler, null) catch return null;
    return (chosen orelse return null).path;
}

/// The engine tier of the compiler store at `directory`, or null when there is none or it cannot be opened: the engine then keeps its
/// records in the work directory alone, as before. An unusable store is not an error here: the command's own artifact store reports it.
pub fn open(gpa: std.mem.Allocator, io: std.Io, directory: ?[]const u8) ?compiler_records.Records {
    const given = directory orelse return null;
    return compiler_records.Records.open(gpa, io, given) catch null;
}
