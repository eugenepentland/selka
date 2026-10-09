//! Bounded copied-value Core trial batches. Completed records survive a later trap.
const std = @import("std");
const codec = @import("property_codec.zig");
const types = @import("property_types.zig");
const v = @import("property_value.zig");
const spawn = @import("process_spawn.zig");
const Value = std.json.Value;
/// Input, output and child-launch failures remain test failures.
pub const Error = codec.Error || error{ WriteFailed, ReadFailed };
/// A batch uses the same maximum input count as the old runner.
pub const batch_limit = 4096;
/// The old runner's default whole-batch wall-clock limit.
pub const Limits = struct { timeout_ms: u32 = 60000 };
/// Filesystem, arena and child-output allocation resources of one command, and the
/// environment its test processes get.
pub const Context = struct { arena: std.mem.Allocator, io: std.Io, backing: std.mem.Allocator, environment: spawn.Environment };
/// The structured trap fields that distinguish a test's precondition from a helper's.
pub const Trap = struct { code: []const u8 = "", message: []const u8 = "", frame: []const u8 = "" };
/// One completed trial and its captured output, actual value or structured trap.
pub const Outcome = struct { status: []const u8, actual: Value = .null, diagnostics: []const u8 = "", output: []const u8 = "", trace: []const u8 = "", trap: Trap = .{} };
/// One bounded batch request.
pub const BatchCall = struct { executor: *const Executor, function: Value, inputs: []const []const u64 };
/// A completed prefix and the reason its process stopped before any remaining inputs.
/// `timed_out` is the whole process's limit; `alarm` is a trial's own wall-clock limit,
/// which ends the process with `SIGALRM`.
pub const BatchOutcome = struct { outcomes: []const Outcome, complete: bool, ending: []const u8 = "", timed_out: bool = false, alarm: bool = false };
/// One trial of a request: the table row it calls, the test's signature for decoding
/// its answer, and its encoded inputs. A request may mix rows (NEW-CORE-TEST-BATCH-1).
pub const Trial = struct { row: usize, function: Value, words: []const u64 };
/// One selected test's executable and isolated working files.
pub const Executor = struct {
    context: Context,
    types: []const Value,
    executable: []const u8,
    table_index: usize,
    directory: []const u8,
    source_path: []const u8 = "",
    /// Encode only data parameters, in source declaration order.
    pub fn encode(self: *const Executor, function: Value, arguments: Value) Error![]const u64 {
        var encoder: codec.Codec = .{ .allocator = self.context.arena, .schema = try types.Schema.init(self.context.arena, self.types) };
        const parameters = v.array(v.get(function, "parameters"));
        var count: usize = 0;
        for (parameters) |parameter| if (!injected(v.text(v.get(parameter, "type")))) {
            count += 1;
        };
        if (arguments != .object or arguments.object.count() != count) return error.InvalidTestValue;
        for (parameters) |parameter| {
            const name = v.text(v.get(parameter, "type"));
            if (injected(name)) continue;
            const input = arguments.object.get(v.text(v.get(parameter, "name"))) orelse return error.InvalidTestValue;
            try encoder.encode(name, input);
        }
        return encoder.words.items;
    }
    fn batch(self: *const Executor, call: BatchCall, limits: Limits) Error!BatchOutcome {
        const items = try self.context.arena.alloc(Trial, call.inputs.len);
        for (items, call.inputs) |*item, words| item.* = .{ .row = self.table_index, .function = call.function, .words = words };
        return self.trials(items, limits);
    }
    /// Run `trials` in order in one process of the executable, each in its own forked
    /// trial; `limits` bounds the whole process. The answered prefix survives an early end.
    pub fn trials(self: *const Executor, requested: []const Trial, limits: Limits) Error!BatchOutcome {
        const c = self.context;
        const a = c.arena;
        var nonce: [16]u8 = undefined;
        std.Io.random(c.io, &nonce);
        const stem = try std.fmt.allocPrint(a, "{s}/{s}", .{ self.directory, std.fmt.bytesToHex(nonce, .lower) });
        const input = try std.fmt.allocPrint(a, "{s}.input", .{stem});
        const output = try std.fmt.allocPrint(a, "{s}.response", .{stem});
        var request: std.ArrayList(u8) = .empty;
        try appendWord(a, &request, requested.len);
        for (requested) |item| {
            try appendWord(a, &request, item.row);
            try appendWord(a, &request, item.words.len);
            for (item.words) |word| try appendWord(a, &request, word);
        }
        std.Io.Dir.cwd().writeFile(c.io, .{ .sub_path = input, .data = request.items }) catch return error.WriteFailed;
        const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(limits.timeout_ms), .clock = .awake } };
        const child = spawn.run(c.backing, c.io, .{ .argv = &.{ self.executable, input, output }, .environment = c.environment, .timeout = timeout }) catch |err| {
            return self.read(requested, output, .{ .ending = @errorName(err), .timed_out = err == error.Timeout });
        };
        defer c.backing.free(child.stdout);
        defer c.backing.free(child.stderr);
        const ending = switch (child.term) {
            .exited => |status| if (status == 0) "" else try std.fmt.allocPrint(a, "NativeTestProcessFailed: {any}\n{s}", .{ child.term, child.stderr }),
            .signal => try std.fmt.allocPrint(a, "NativeTestProcessFailed: {any}\n{s}", .{ child.term, child.stderr }),
            else => "abnormal termination",
        };
        const alarm = child.term == .signal and child.term.signal == .ALRM;
        var result = try self.read(requested, output, .{ .ending = ending, .alarm = alarm });
        if (std.mem.indexOf(u8, child.stderr, "myl-core leakcheck:") != null and requested.len != 0) {
            const count = @min(result.outcomes.len + 1, requested.len);
            const outcomes = try a.alloc(Outcome, count);
            @memcpy(outcomes[0..@min(count, result.outcomes.len)], result.outcomes[0..@min(count, result.outcomes.len)]);
            outcomes[count - 1] = .{ .status = "failure", .diagnostics = try a.dupe(u8, child.stderr) };
            result.outcomes = outcomes;
        }
        result.complete = result.outcomes.len == requested.len and ending.len == 0;
        return result;
    }
    const End = struct { ending: []const u8, timed_out: bool = false, alarm: bool = false };
    fn read(self: *const Executor, requested: []const Trial, output: []const u8, end: End) Error!BatchOutcome {
        const c = self.context;
        const bytes = std.Io.Dir.cwd().readFileAlloc(c.io, output, c.arena, .limited(64 << 20)) catch "";
        var reader: Reader = .{ .bytes = bytes };
        var outcomes: std.ArrayList(Outcome) = .empty;
        while (reader.cursor < bytes.len and outcomes.items.len < requested.len) {
            const function = requested[outcomes.items.len].function;
            const status = reader.word() catch break;
            const encoded = reader.chunk() catch break;
            const stdout = reader.chunk() catch break;
            const stderr = reader.chunk() catch break;
            const trace = reader.chunk() catch break;
            var outcome: Outcome = .{ .status = "value", .output = stdout, .trace = trace };
            if (status == 0) {
                if (encoded.len % 8 != 0) return error.InvalidTestValue;
                var decoder: codec.Codec = .{ .allocator = c.arena, .schema = try types.Schema.init(c.arena, self.types) };
                for (0..encoded.len / 8) |index| try decoder.words.append(c.arena, std.mem.readInt(u64, encoded[index * 8 ..][0..8], .little));
                outcome.actual = try decoder.decode(v.text(v.get(function, "result")));
                if (decoder.cursor != decoder.words.items.len) return error.InvalidTestValue;
            } else if (status == 1) {
                outcome = try trap(c.arena, stderr, stdout);
            } else {
                outcome.status = "failure";
                outcome.diagnostics = if (status == 4) stderr else try std.fmt.allocPrint(c.arena, "terminated by signal {d}", .{status & 0xffff});
            }
            if (self.source_path.len != 0) {
                const name = std.fs.path.basename(self.source_path);
                outcome.diagnostics = try std.mem.replaceOwned(u8, c.arena, outcome.diagnostics, self.source_path, name);
                outcome.trace = try std.mem.replaceOwned(u8, c.arena, outcome.trace, self.source_path, name);
            }
            try outcomes.append(c.arena, outcome);
        }
        return .{ .outcomes = outcomes.items, .complete = end.ending.len == 0, .ending = end.ending, .timed_out = end.timed_out, .alarm = end.alarm };
    }
};
/// Execute batches in source order; each request retains its own bounded process.
pub fn executeBatches(context: Context, calls: []const BatchCall, limits: Limits, width: usize) Error![]const BatchOutcome {
    _ = width;
    const results = try context.arena.alloc(BatchOutcome, calls.len);
    for (calls, results) |call, *result| result.* = try call.executor.batch(call, limits);
    return results;
}
fn appendWord(a: std.mem.Allocator, bytes: *std.ArrayList(u8), word: u64) Error!void {
    var encoded: [8]u8 = undefined;
    std.mem.writeInt(u64, &encoded, word, .little);
    try bytes.appendSlice(a, &encoded);
}
const Reader = struct {
    bytes: []const u8,
    cursor: usize = 0,
    fn word(self: *Reader) Error!u64 {
        if (self.bytes.len - self.cursor < 8) return error.InvalidTestValue;
        defer self.cursor += 8;
        return std.mem.readInt(u64, self.bytes[self.cursor..][0..8], .little);
    }
    fn chunk(self: *Reader) Error![]const u8 {
        const size = try self.word();
        if (size > self.bytes.len - self.cursor) return error.InvalidTestValue;
        defer self.cursor += @intCast(size);
        return self.bytes[self.cursor..][0..@intCast(size)];
    }
};
fn injected(name: []const u8) bool {
    for ([_][]const u8{ "stream_cap", "clock_cap", "random_cap", "filesystem_cap", "network_cap", "environment_cap" }) |known| if (std.mem.eql(u8, name, known)) return true;
    return false;
}
fn trap(a: std.mem.Allocator, stderr: []const u8, stdout: []const u8) Error!Outcome {
    const start = std.mem.indexOf(u8, stderr, "error[") orelse return .{ .status = "failure", .diagnostics = if (stderr.len == 0) "exited with status 1" else stderr, .output = stdout };
    const close = std.mem.indexOfScalarPos(u8, stderr, start, ']') orelse return error.InvalidTestValue;
    const head_end = std.mem.indexOfScalarPos(u8, stderr, close, '\n') orelse stderr.len;
    const code = stderr[start + "error[".len .. close];
    const failed = "native execution failed";
    const detail = if (std.mem.indexOf(u8, stderr[close..head_end], failed)) |offset| std.mem.trimStart(u8, stderr[close + offset + failed.len .. head_end], " ") else "";
    const contract = std.mem.eql(u8, code, "R_ASSERT") or std.mem.eql(u8, code, "R_REQUIRES") or std.mem.eql(u8, code, "R_ENSURES") or std.mem.eql(u8, code, "R_INVARIANT");
    const message = if (contract) try trapMessage(a, stderr, std.mem.trimStart(u8, detail, ": ")) else "";
    var frames = std.mem.splitScalar(u8, stderr[head_end..], '\n');
    var rendered: std.ArrayList(u8) = .empty;
    try rendered.print(a, "{s}{s}{s}\n", .{ code, if (contract and message.len != 0) ": " else if (!contract and detail.len != 0) " " else "", if (contract) message else detail });
    var frame: []const u8 = "";
    while (frames.next()) |line| {
        // The runtime lists at most sixteen frames and counts the rest (NEW-CORE-S5-TRACE-1).
        if (std.mem.startsWith(u8, line, "  ") and std.mem.endsWith(u8, line, " frames omitted")) try rendered.print(a, "{s}\n", .{line});
        if (!std.mem.startsWith(u8, line, "  in ")) continue;
        // The compiler's per-test wrapper is no frame of the program.
        if (std.mem.startsWith(u8, line["  in ".len..], "__test_")) continue;
        try rendered.print(a, "{s}\n", .{line});
        if (frame.len == 0) {
            const end = std.mem.indexOf(u8, line, " at ") orelse line.len;
            frame = line["  in ".len..end];
        }
    }
    // A budget's trap ends with the runtime's advice, as the old runner reported it.
    const head = stderr[close + 1 .. head_end];
    if (!contract and std.mem.indexOf(u8, head, failed) == null and std.mem.startsWith(u8, head, ": ")) try rendered.print(a, "\n{s}\n", .{head[2..]});
    return .{ .status = "trap", .diagnostics = rendered.items, .output = stdout, .trap = .{ .code = code, .message = message, .frame = frame } };
}

fn trapMessage(a: std.mem.Allocator, stderr: []const u8, fallback: []const u8) Error![]const u8 {
    const marker = "\x1eSELKA-TRAP ";
    const start = (std.mem.indexOf(u8, stderr, marker) orelse return fallback) + marker.len;
    const end = std.mem.indexOfScalarPos(u8, stderr, start, '\n') orelse stderr.len;
    const record = std.json.parseFromSliceLeaky(Value, a, stderr[start..end], .{}) catch return error.InvalidTestValue;
    return v.text(v.get(record, "operation"));
}

// spec-case: NEW-CORE-TEST-BATCH-1
test "trials reports an executable that cannot start as an ending with no answers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const context: Context = .{ .arena = a, .io = std.testing.io, .backing = std.testing.allocator, .environment = .{ .block = .empty } };
    const executor: Executor = .{ .context = context, .types = &.{}, .executable = try std.fs.path.join(a, &.{ root, "missing" }), .table_index = 0, .directory = root };
    const requested: []const Trial = &.{ .{ .row = 0, .function = .null, .words = &.{} }, .{ .row = 1, .function = .null, .words = &.{} } };
    const result = try executor.trials(requested, .{});
    try std.testing.expectEqual(@as(usize, 0), result.outcomes.len);
    try std.testing.expect(!result.complete);
    try std.testing.expect(!result.timed_out and !result.alarm);
    try std.testing.expect(result.ending.len != 0);
}

// spec-case: NEW-CORE-S3-RUNNER-1
test "trap preserves contract messages and old numeric detail while excluding compiler wrappers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const stderr = "x.selka:1:1: error[R_REQUIRES]: native execution failed: fallback\n" ++
        "  in x::test_a at x.selka:1:1\n  in __test_trial_0 at x.selka:1:1\n" ++
        "\x1eSELKA-TRAP {\"version\":1,\"operation\":\" leading: message\\nline \"}\n";
    const contract = try trap(a, stderr, "");
    try std.testing.expectEqualStrings(" leading: message\nline ", contract.trap.message);
    try std.testing.expectEqualStrings("x::test_a", contract.trap.frame);
    try std.testing.expectEqualStrings("R_REQUIRES:  leading: message\nline \n  in x::test_a at x.selka:1:1\n", contract.diagnostics);
    const numeric = try trap(a, "x.selka:1:1: error[R_DIVISION_BY_ZERO]: native execution failed (div: left 1, right 0)\n  in x::test_a at x.selka:1:1\n", "");
    try std.testing.expectEqualStrings("R_DIVISION_BY_ZERO (div: left 1, right 0)\n  in x::test_a at x.selka:1:1\n", numeric.diagnostics);
    try std.testing.expectError(error.InvalidTestValue, trapMessage(a, "\x1eSELKA-TRAP {\n", ""));
}

// spec: NEW-CORE-S5-TRACE-1
test "a budget trap keeps its omitted-frame count and ends with the runtime's advice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const stderr = "error[R_FRAME_LIMIT]: call-depth budget exhausted; raise it with --max-frames=N\n" ++
        "  in x::deep at x.selka:2:12\n  in x::deep at x.selka:2:12\n  1008 frames omitted\n" ++
        "\x1eSELKA-TRAP {\"version\":1,\"operation\":\"call-depth budget exhausted\"}\n";
    const budget = try trap(a, stderr, "");
    try std.testing.expectEqualStrings("R_FRAME_LIMIT", budget.trap.code);
    try std.testing.expectEqualStrings("x::deep", budget.trap.frame);
    try std.testing.expectEqualStrings("R_FRAME_LIMIT\n  in x::deep at x.selka:2:12\n  in x::deep at x.selka:2:12\n  1008 frames omitted\n\ncall-depth budget exhausted; raise it with --max-frames=N\n", budget.diagnostics);
    const wrapped = try trap(a, "error[R_STEP_LIMIT]: instruction budget exhausted\n  in x::test_a at x.selka:3:9\n  in __test_trial_0 at x.selka:1:1\n", "");
    try std.testing.expectEqualStrings("R_STEP_LIMIT\n  in x::test_a at x.selka:3:9\n\ninstruction budget exhausted\n", wrapped.diagnostics);
}
