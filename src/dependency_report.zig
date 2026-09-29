//! Checked module/import inventory for verification tools; no VM execution required.
const std = @import("std");
const receipt = @import("source_receipt.zig");
const project_compile = @import("project_compile.zig");
const incremental = @import("incremental.zig");
/// Exact manifest bytes consumed during input generation, rather than a later disk read.
pub const Manifest = struct { module: []const u8, path: []const u8, sha256: []const u8 };
/// Required-policy content identity recorded beside the checked source graph.
pub const Policy = struct { config_sha256: []const u8, policy_sha256: ?[]const u8 = null };
/// Checking errors and receipt allocation failures remain distinct.
pub const RenderError = project_compile.CheckError || receipt.InputsError || incremental.Error;
/// Allocate lowercase SHA-256 for the supplied raw bytes.
pub fn hashBytes(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)});
}
/// Build the target/compiler contract a specialization key must distinguish.
fn contractFor(scratch: std.mem.Allocator, identity: receipt.Identity) std.mem.Allocator.Error!incremental.Contract {
    return .{
        .compiler_sha256 = try std.fmt.allocPrint(scratch, "{s}", .{std.fmt.bytesToHex(identity.compiler_sha256, .lower)}),
        .target_abi = try std.fmt.allocPrint(scratch, "{s}-{s}-{s}", .{ identity.architecture, identity.os, identity.abi }),
    };
}
/// Return an owned complete receipt only after checking all reachable modules.
pub fn render(allocator: std.mem.Allocator, compilation: *project_compile.Compilation, identity: receipt.Identity, manifests: []const Manifest, policy: ?Policy) RenderError![]u8 {
    try compilation.check();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const graph = compilation.index.project;
    const identities = try incremental.describe(scratch, compilation, try contractFor(scratch, identity));
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "project-dependencies-v1",
        .complete = true,
        .entry = graph.modules.items[0].name,
        .policy = policy,
        .implementation = try receipt.implementation(scratch, identity),
        .inputs = try receipt.inputs(scratch, graph),
        .embeds = try receipt.embeds(scratch, graph),
        .manifests = manifests,
        .incremental = identities,
    }, .{});
}
/// Return an owned best-effort receipt for a project whose checking failed. This
/// never runs or publishes a successful verdict; it exists so a rejected edit can
/// still be explained against the previous baseline.
pub fn renderPartial(allocator: std.mem.Allocator, compilation: *project_compile.Compilation, identity: receipt.Identity, manifests: []const Manifest, policy: ?Policy) RenderError![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const graph = compilation.index.project;
    const identities = try incremental.describePartial(scratch, compilation);
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "project-dependencies-v1",
        .complete = false,
        .entry = graph.modules.items[0].name,
        .policy = policy,
        .implementation = try receipt.implementation(scratch, identity),
        .inputs = try receipt.inputs(scratch, graph),
        .embeds = try receipt.embeds(scratch, graph),
        .manifests = manifests,
        .incremental = identities,
    }, .{});
}
