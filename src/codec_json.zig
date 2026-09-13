//! Checked, bounded JSON operations that execute explicit domain codec contracts.
const project_compile = @import("project_compile.zig");
const function_key = "function";
/// Source, wire, and execution failures at a budgeted project call boundary.
pub const Error = json.ValueError || json.ParseError || project_compile.EmitError ||
    project_compile.PublicValueTypeError || project_compile.PublicFunctionError ||
    @import("schema.zig").RenderError || error{
    UnreleasedCodecFailure,
    InvalidCodecBudget,
    CodecMemoryLimit,
    UnsupportedInvocationVersion,
    InvocationSchemaMismatch,
    InvocationArguments,
};

const std = @import("std");
const typed = @import("typed.zig");
const json = @import("typed_json.zig");
const bc = @import("bytecode.zig");
const runtime = @import("codec_execution.zig");
/// Shared operation totals for guest steps, calls, traversed values, and peak live bytes.
pub const Statistics = struct { steps: u64 = 0, calls: usize = 0, values: usize = 0, peak_bytes: usize = 0 };
/// JSON and execution budgets shared across domain codecs and public function invocation.
pub const Options = struct {
    json: json.Limits = .{},
    max_steps: u64 = 1_000_000,
    max_frames: u64 = 256,
    max_calls: usize = 4096,
    max_work_values: usize = 131072,
    max_bytes: usize = 32 * 1024 * 1024,
    statistics: ?*Statistics = null,
};
/// Located conversion failure with optional owned domain rejection; release it before reuse.
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
    fn prepare(allocator: std.mem.Allocator, program: bc.Program, options: Options, failure: *Failure) !Operation {
        // Failure must be initialized and any previous owned rejection released.
        try failure.begin();
        if (options.statistics) |statistics| statistics.* = .{};
        try options.json.check();
        const empty_execution_budget = options.max_steps == 0 or options.max_frames == 0 or options.max_calls == 0;
        if (empty_execution_budget or options.max_work_values == 0 or options.max_bytes == 0) return error.InvalidCodecBudget;
        return .{
            .memory = .{ .parent = allocator, .limit = options.max_bytes },
            .execution = .{
                .backend = .{ .dispatch = @import("vm.zig").invoke, .program = program },
                .max_steps = options.max_steps,
                .max_frames = options.max_frames,
                .max_calls = options.max_calls,
                .arguments = .{
                    .max_values = options.json.max_values,
                    .max_depth = 128,
                },
                .failure = &failure.execution,
            },
            .traversal = .{ .limits = options.json },
            .work = .{ .limit = options.max_work_values },
            .statistics = options.statistics,
        };
    }
    fn report(self: *Operation) void {
        if (self.statistics) |statistics| statistics.* = .{ .steps = self.execution.used.steps, .calls = self.execution.used.calls, .values = self.work.values, .peak_bytes = self.memory.peak };
    }
    fn classify(self: *Operation, err: Error) Error {
        return if (err == error.OutOfMemory and self.memory.limit_failure) error.CodecMemoryLimit else err;
    }
};
/// Returned values/rejection payloads use allocator; release them there. Compiled
/// nominal identities and trap metadata still require the checked program alive.
pub fn decode(allocator: std.mem.Allocator, program: bc.Program, ty: typed.Type, bytes: []const u8, options: Options, failure: *Failure) Error!typed.Value {
    var operation = try Operation.prepare(allocator, program, options, failure);
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
/// Allocate typed JSON using declared domain encoders under shared execution and memory limits.
pub fn encode(allocator: std.mem.Allocator, program: bc.Program, ty: typed.Type, value: typed.Value, options: Options, failure: *Failure) Error![]u8 {
    var operation = try Operation.prepare(allocator, program, options, failure);
    operation.traversal.work = &operation.work;
    defer operation.report();
    return json.encodeWithCodecs(operation.memory.allocator(), &operation.execution, ty, value, &operation.traversal, &failure.location) catch |err| return operation.classify(err);
}
/// The frontend is checked/lowered before the runtime memory budget starts.
/// Both directions share execution, live-memory, and traversal budgets.
pub fn canonicalProject(allocator: std.mem.Allocator, compilation: *project_compile.Compilation, bytes: []const u8, options: Options, failure: *Failure) Error![]u8 {
    try failure.begin();
    if (options.statistics) |statistics| statistics.* = .{};
    try compilation.emit();
    var operation = try Operation.prepare(allocator, compilation.code.?, options, failure);
    operation.traversal.work = &operation.work;
    defer operation.report();
    return canonicalInner(&operation, compilation, bytes, failure) catch |err| return operation.classify(err);
}
fn canonicalInner(operation: *Operation, compilation: *project_compile.Compilation, bytes: []const u8, failure: *Failure) ![]u8 {
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

/// Schema-pinned public function request with named JSON argument values.
pub const Request = struct { version: []const u8, schema_sha256: []const u8, function: []const u8, arguments: std.json.Value };
/// Invoke a current exported interface only after checking its schema identity.
/// Arguments use named wire values; output is one ordinary typed-json-v1 envelope.
pub fn invokeProject(allocator: std.mem.Allocator, compilation: *project_compile.Compilation, bytes: []const u8, options: Options, failure: *Failure) Error![]u8 {
    try failure.begin();
    if (options.statistics) |statistics| statistics.* = .{};
    try compilation.emit();
    var operation = try Operation.prepare(allocator, compilation.code.?, options, failure);
    operation.traversal.work = &operation.work;
    defer operation.report();
    return invokeInner(&operation, compilation, bytes, failure) catch |err| return operation.classify(err);
}
fn invokeInner(operation: *Operation, compilation: *project_compile.Compilation, bytes: []const u8, failure: *Failure) ![]u8 {
    const allocator = operation.memory.allocator();
    try json.scanRequest(allocator, bytes, operation.traversal.limits);
    // parseFromSlice supplies complete input and uses its length as max_value_len.
    // These concrete documents contain no fixed-size arrays; generic parser-only
    // failures indicate an internal contract mismatch, not a caller input category.
    const parsed = std.json.parseFromSlice(Request, allocator, bytes, .{ .allocate = .alloc_always, .parse_numbers = false }) catch |err| switch (err) {
        error.BufferUnderrun, error.LengthMismatch, error.ValueTooLong, error.InvalidEnumTag => return error.InternalError,
        else => |parse_error| return parse_error,
    };
    defer parsed.deinit();
    const request = parsed.value;
    if (!std.mem.eql(u8, request.version, "typed-call-v1")) {
        failure.location.field("version");
        return error.UnsupportedInvocationVersion;
    }
    if (!try schemaMatches(allocator, compilation, request.schema_sha256)) {
        failure.location.field("schema_sha256");
        return error.InvocationSchemaMismatch;
    }
    const id = compilation.publicFunction(request.function) catch |err| {
        if (err != error.OutOfMemory) failure.location.field(function_key);
        return err;
    };
    const function = compilation.program.?.functions[@backingInt(id)];
    preflight(allocator, compilation.program.?.records, function) catch |err| {
        if (err != error.OutOfMemory) failure.location.field(function_key);
        return err;
    };
    if (request.arguments != .object or request.arguments.object.count() != function.signature.parameter_count) {
        failure.location.field("arguments");
        return error.InvocationArguments;
    }
    const parameters = function.scope.locals[0..function.signature.parameter_count];
    for (parameters) |parameter| if (!request.arguments.object.contains(parameter.name)) {
        failure.location.field("arguments");
        return error.InvocationArguments;
    };
    const arguments = try allocator.alloc(typed.Value, parameters.len);
    var initialized: usize = 0;
    defer {
        for (arguments[0..initialized]) |argument| argument.release(allocator);
        allocator.free(arguments);
    }
    for (parameters, arguments) |parameter, *argument| {
        argument.* = try json.decodeArgument(allocator, &operation.execution, .{ .ty = parameter.ty, .value = request.arguments.object.get(parameter.name).?, .name = parameter.name }, &operation.traversal, &failure.location);
        initialized += 1;
    }
    const value = operation.execution.invoke(allocator, id, arguments) catch |err| {
        if (err != error.OutOfMemory) failure.location.field(function_key);
        return err;
    };
    defer value.release(allocator);
    operation.traversal.values = 0;
    return json.encodeWithCodecs(allocator, &operation.execution, function.signature.return_type, value, &operation.traversal, &failure.location);
}
fn preflight(allocator: std.mem.Allocator, records: []const typed.Record, function: typed.Function) !void {
    if (function.policy.effects != 0) return error.InvocationEffects;
    try @import("data_type.zig").checkCodecs(allocator, records, function.signature.return_type);
    for (function.scope.locals[0..function.signature.parameter_count]) |parameter| {
        try @import("data_type.zig").checkCodecs(allocator, records, parameter.ty);
    }
}

fn schemaMatches(allocator: std.mem.Allocator, compilation: *project_compile.Compilation, expected: []const u8) !bool {
    const schema = try @import("schema.zig").render(allocator, compilation);
    defer allocator.free(schema);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(schema, &digest, .{});
    return std.mem.eql(u8, expected, &std.fmt.bytesToHex(digest, .lower));
}
