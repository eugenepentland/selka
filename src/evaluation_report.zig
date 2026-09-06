//! Deterministic successful-evaluation receipt. No cache lookup or file writes.
const std = @import("std");
const project = @import("project.zig");
const evaluation = @import("evaluation.zig");
const receipt = @import("source_receipt.zig");
pub const Identity = receipt.Identity;
pub fn render(allocator: std.mem.Allocator, graph: *const project.Project, value: i64, options: evaluation.Options, identity: Identity) ![]u8 {
    return renderInner(allocator, graph, value, options, identity);
}
pub fn renderRequest(allocator: std.mem.Allocator, graph: *const project.Project, options: evaluation.Options, identity: Identity) ![]u8 {
    return renderInner(allocator, graph, null, options, identity);
}
fn renderInner(allocator: std.mem.Allocator, graph: *const project.Project, value: ?i64, options: evaluation.Options, identity: Identity) ![]u8 {
    if (!graph.complete or graph.problem != null or graph.modules.items.len == 0) return error.IncompleteProject;
    if (options.max_steps == 0 or options.max_frames == 0 or options.max_bytes == 0) return error.InvalidBudget;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const request = .{
        .version = "eval-request-v1",
        .entry = graph.modules.items[0].name,
        .policy = "effect-free-parameter-free-v1",
        .implementation = try receipt.implementation(scratch, identity),
        .budgets = options,
        .sources = try receipt.inputs(scratch, graph),
    };
    // Hash compact JSON in declared field order, excluding the evaluated result.
    const request_digest = try receipt.digest(scratch, request);
    if (value == null) return std.json.Stringify.valueAlloc(allocator, .{
        .version = "eval-request-document-v1",
        .evaluation = "not-executed",
        .request_sha256 = request_digest,
        .request = request,
    }, .{});
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "eval-report-v1",
        .request_sha256 = request_digest,
        .request = request,
        .result = .{ .type = "i64", .decimal = try std.fmt.allocPrint(scratch, "{d}", .{value.?}) },
    }, .{});
}
