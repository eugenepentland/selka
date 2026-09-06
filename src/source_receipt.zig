//! Shared source/implementation identities from an already loaded project snapshot.
/// Failures returned by inputs; callers must handle these boundary errors.
pub const InputsError = error{
    IncompleteProject,
    OutOfMemory,
};

const std = @import("std");
const project = @import("project.zig");
/// Compiler digest and toolchain/target fields that distinguish receipt implementations.
pub const Identity = struct { compiler_sha256: [32]u8, zig_version: []const u8, architecture: []const u8, os: []const u8, abi: []const u8, optimize: []const u8 };
/// JSON-ready implementation identity whose strings use the receipt allocator.
pub const Implementation = struct { compiler_sha256: []const u8, zig_version: []const u8, architecture: []const u8, os: []const u8, abi: []const u8, optimize: []const u8 };
/// Dependency module name and the alias used by the importing module.
pub const Import = struct { module: []const u8, alias: []const u8 };
/// Source identity, digest, byte count, and direct imports recorded in a receipt.
pub const Input = struct { module: []const u8, path: []const u8, sha256: []const u8, bytes: usize, imports: []const Import };
/// Returned arrays/strings belong to the supplied request arena; names/path views
/// also borrow the project. Neither may be released while serializing the receipt.
pub fn inputs(arena: std.mem.Allocator, graph: *const project.Project) InputsError![]const Input {
    if (!graph.progress.complete or graph.problem != null or graph.modules.items.len == 0) return error.IncompleteProject;
    const output = try arena.alloc(Input, graph.order.items.len);
    for (output, graph.order.items) |*input, id| {
        const module = graph.modules.items[id];
        const imports = try arena.alloc(Import, module.imports.len);
        for (imports, module.imports) |*item, imported| item.* = .{ .module = graph.modules.items[imported.target].name, .alias = imported.alias };
        input.* = .{ .module = module.name, .path = module.src.path, .sha256 = try std.fmt.allocPrint(arena, "{s}", .{std.fmt.bytesToHex(module.digest, .lower)}), .bytes = module.src.bytes.len, .imports = imports };
    }
    return output;
}
/// Allocate the digest representation and retain the supplied toolchain identity fields.
pub fn implementation(arena: std.mem.Allocator, identity: Identity) std.mem.Allocator.Error!Implementation {
    return .{
        .compiler_sha256 = try std.fmt.allocPrint(arena, "{s}", .{std.fmt.bytesToHex(identity.compiler_sha256, .lower)}),
        .zig_version = identity.zig_version,
        .architecture = identity.architecture,
        .os = identity.os,
        .abi = identity.abi,
        .optimize = identity.optimize,
    };
}
/// Serialize a receipt component and allocate its lowercase SHA-256 digest.
pub fn digest(arena: std.mem.Allocator, value: anytype) ![]const u8 {
    const canonical = try std.json.Stringify.valueAlloc(arena, value, .{});
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical, &hash, .{});
    return std.fmt.allocPrint(arena, "{s}", .{std.fmt.bytesToHex(hash, .lower)});
}
