//! Checked, bounded JSON operations that execute explicit domain codec contracts.
const std = @import("std");
const typed = @import("typed.zig");
const json = @import("typed_json.zig");
const bc = @import("bytecode.zig");
const runtime = @import("codec_execution.zig");
pub const Statistics = struct { steps: u64 = 0, calls: usize = 0, values: usize = 0, peak_bytes: usize = 0 };
pub const Options = struct {
    json: json.Limits = .{},
    max_steps: u64 = 1_000_000,
    max_frames: u64 = 256,
    max_calls: usize = 4096,
    max_work_values: usize = 131072,
    max_bytes: usize = 32 * 1024 * 1024,
    statistics: ?*Statistics = null,
};
pub const Failure = struct {
    location: json.Location = .{},
    execution: runtime.Failure = .{},
    fn begin(self: *Failure) !void {
        if (self.execution.rejection != null) return error.UnreleasedCodecFailure;
        self.* = .{};
    }
    pub fn deinit(self: *Failure, allocator: std.mem.Allocator) void {
        self.execution.deinit(allocator);
        self.location = .{};
    }
};
const Operation = struct {
    memory: @import("codec_memory.zig").Memory,
    execution: runtime.Execution,
    traversal: json.Budget,
    work: json.WorkBudget,
    statistics: ?*Statistics,
    fn init(allocator: std.mem.Allocator, program: bc.Program, options: Options, failure: *Failure) !Operation {
        // Failure must be initialized and any previous owned rejection released.
        try failure.begin();
        if (options.statistics) |statistics| statistics.* = .{};
        try options.json.check();
        if (options.max_steps == 0 or options.max_frames == 0 or options.max_calls == 0 or options.max_work_values == 0 or options.max_bytes == 0) return error.InvalidCodecBudget;
        return .{
            .memory = .{ .parent = allocator, .limit = options.max_bytes },
            .execution = .{ .program = program, .max_steps = options.max_steps, .max_frames = options.max_frames, .max_calls = options.max_calls, .arguments = .{ .max_values = options.json.max_values, .max_depth = 128 }, .failure = &failure.execution },
            .traversal = .{ .limits = options.json },
            .work = .{ .limit = options.max_work_values },
            .statistics = options.statistics,
        };
    }
    fn report(self: *Operation) void {
        if (self.statistics) |statistics| statistics.* = .{ .steps = self.execution.steps, .calls = self.execution.calls, .values = self.work.values, .peak_bytes = self.memory.peak };
    }
    fn classify(self: *Operation, err: anyerror) anyerror {
        return if (err == error.OutOfMemory and self.memory.limit_failure) error.CodecMemoryLimit else err;
    }
};
/// Returned values/rejection payloads use allocator; release them there. Compiled
/// nominal identities and trap metadata still require the checked program alive.
pub fn decode(allocator: std.mem.Allocator, program: bc.Program, ty: typed.Type, bytes: []const u8, options: Options, failure: *Failure) !typed.Value {
    var operation = try Operation.init(allocator, program, options, failure);
    operation.traversal.work = &operation.work;
    defer operation.report();
    return decodeInner(&operation, ty, bytes, failure) catch |err| return operation.classify(err);
}
fn decodeInner(operation: *Operation, ty: typed.Type, bytes: []const u8, failure: *Failure) !typed.Value {
    const allocator = operation.memory.allocator();
    var document = try json.Document.parseWithLocation(allocator, bytes, operation.traversal.limits, &failure.location);
    defer document.deinit();
    return document.decodeWithCodecs(allocator, &operation.execution, ty, &operation.traversal, &failure.location);
}
pub fn encode(allocator: std.mem.Allocator, program: bc.Program, ty: typed.Type, value: typed.Value, options: Options, failure: *Failure) ![]u8 {
    var operation = try Operation.init(allocator, program, options, failure);
    operation.traversal.work = &operation.work;
    defer operation.report();
    return json.encodeWithCodecs(operation.memory.allocator(), &operation.execution, ty, value, &operation.traversal, &failure.location) catch |err| return operation.classify(err);
}
/// The frontend is checked/lowered before the runtime memory budget starts.
/// Both directions share execution, live-memory, and traversal budgets.
pub fn canonicalProject(allocator: std.mem.Allocator, compilation: *@import("project_compile.zig").Compilation, bytes: []const u8, options: Options, failure: *Failure) ![]u8 {
    try failure.begin();
    if (options.statistics) |statistics| statistics.* = .{};
    try compilation.emit();
    var operation = try Operation.init(allocator, compilation.code.?, options, failure);
    operation.traversal.work = &operation.work;
    defer operation.report();
    return canonicalInner(&operation, compilation, bytes, failure) catch |err| return operation.classify(err);
}
fn canonicalInner(operation: *Operation, compilation: *@import("project_compile.zig").Compilation, bytes: []const u8, failure: *Failure) ![]u8 {
    const allocator = operation.memory.allocator();
    var document = try json.Document.parseWithLocation(allocator, bytes, operation.traversal.limits, &failure.location);
    defer document.deinit();
    const ty = compilation.publicValueType(document.parsed.value.type) catch |err| {
        if (err != error.OutOfMemory) failure.location.field("type");
        return err;
    };
    const value = try document.decodeWithCodecs(allocator, &operation.execution, ty, &operation.traversal, &failure.location);
    defer value.release(allocator);
    operation.traversal.values = 0;
    return json.encodeWithCodecs(allocator, &operation.execution, ty, value, &operation.traversal, &failure.location);
}
