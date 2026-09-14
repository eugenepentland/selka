//! Deterministic successful-evaluation receipt. No cache lookup or file writes.
/// Failures returned by render; callers must handle these boundary errors.
pub const RenderError = error{
    IncompleteProject,
    InvalidBudget,
    OutOfMemory,
};

const std = @import("std");
const project = @import("project.zig");
const receipt = @import("source_receipt.zig");
pub const Identity = receipt.Identity;
/// Instruction, frame, and live-byte limits a receipt records for its request.
pub const Budgets = struct { max_steps: u64 = 1_000_000, max_frames: u64 = 256, max_bytes: usize = 16 * 1024 * 1024 };
/// Allocate a deterministic evaluation receipt with source identities, limits, and the scalar result.
pub fn render(allocator: std.mem.Allocator, graph: *const project.Project, value: i64, options: Budgets, identity: Identity) RenderError![]u8 {
    return renderInner(allocator, graph, value, options, identity);
}
/// Allocate the evaluation request identity without executing the program.
pub fn renderRequest(allocator: std.mem.Allocator, graph: *const project.Project, options: Budgets, identity: Identity) RenderError![]u8 {
    return renderInner(allocator, graph, null, options, identity);
}
fn renderInner(allocator: std.mem.Allocator, graph: *const project.Project, value: ?i64, options: Budgets, identity: Identity) ![]u8 {
    if (!graph.progress.complete or graph.problem != null or graph.modules.items.len == 0) return error.IncompleteProject;
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
