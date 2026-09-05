//! Deterministic successful-evaluation receipt. No cache lookup or file writes.
const std = @import("std");
const project = @import("project.zig");
const evaluation = @import("evaluation.zig");
pub const Identity = struct { compiler_sha256: [32]u8, zig_version: []const u8, architecture: []const u8, os: []const u8, abi: []const u8, optimize: []const u8 };
const Import = struct { module: []const u8, alias: []const u8 };
const Input = struct { module: []const u8, path: []const u8, sha256: []const u8, bytes: usize, imports: []const Import };
pub fn render(allocator: std.mem.Allocator, graph: *const project.Project, value: i64, options: evaluation.Options, identity: Identity) ![]u8 {
    if (!graph.complete or graph.problem != null or graph.modules.items.len == 0) return error.IncompleteProject;
    if (options.max_steps == 0 or options.max_frames == 0 or options.max_bytes == 0) return error.InvalidBudget;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const inputs = try scratch.alloc(Input, graph.order.items.len);
    for (inputs, graph.order.items) |*input, id| {
        const module = graph.modules.items[id];
        const imports = try scratch.alloc(Import, module.imports.len);
        for (imports, module.imports) |*item, imported| item.* = .{ .module = graph.modules.items[imported.target].name, .alias = imported.alias };
        input.* = .{ .module = module.name, .path = module.src.path, .sha256 = try std.fmt.allocPrint(scratch, "{s}", .{std.fmt.bytesToHex(module.digest, .lower)}), .bytes = module.src.bytes.len, .imports = imports };
    }
    const request = .{
        .version = "eval-request-v1",
        .entry = graph.modules.items[0].name,
        .policy = "effect-free-parameter-free-v1",
        .implementation = .{
            .compiler_sha256 = try std.fmt.allocPrint(scratch, "{s}", .{std.fmt.bytesToHex(identity.compiler_sha256, .lower)}),
            .zig_version = identity.zig_version,
            .architecture = identity.architecture,
            .os = identity.os,
            .abi = identity.abi,
            .optimize = identity.optimize,
        },
        .budgets = options,
        .sources = inputs,
    };
    // Hash compact JSON in declared field order, excluding the evaluated result.
    const canonical = try std.json.Stringify.valueAlloc(scratch, request, .{});
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical, &digest, .{});
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "eval-report-v1",
        .request_sha256 = try std.fmt.allocPrint(scratch, "{s}", .{std.fmt.bytesToHex(digest, .lower)}),
        .request = request,
        .result = .{ .type = "i64", .decimal = try std.fmt.allocPrint(scratch, "{d}", .{value}) },
    }, .{});
}
