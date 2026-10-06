//! Bounded copied-value Core trial batches. Completed records survive a later trap.
const std = @import("std");
const codec = @import("property_codec.zig");
const types = @import("property_types.zig");
const v = @import("property_value.zig");
const Value = std.json.Value;
/// Input, output and child-launch failures remain test failures.
pub const Error = codec.Error || error{ WriteFailed, ReadFailed };
/// A batch uses the same maximum input count as the old runner.
pub const batch_limit = 4096;
/// The old runner's default whole-batch wall-clock limit.
pub const Limits = struct { timeout_ms: u32 = 60000 };
/// Filesystem, arena and child-output allocation resources of one command.
pub const Context = struct { arena: std.mem.Allocator, io: std.Io, backing: std.mem.Allocator };
/// The structured trap fields that distinguish a test's precondition from a helper's.
pub const Trap = struct { code: []const u8 = "", message: []const u8 = "", frame: []const u8 = "" };
/// One completed trial and its captured output, actual value or structured trap.
pub const Outcome = struct { status: []const u8, actual: Value = .null, diagnostics: []const u8 = "", output: []const u8 = "", trace: []const u8 = "", trap: Trap = .{} };
/// One bounded batch request.
pub const BatchCall = struct { executor: *const Executor, function: Value, inputs: []const []const u64 };
/// A completed prefix and the reason its process stopped before any remaining inputs.
pub const BatchOutcome = struct { outcomes: []const Outcome, complete: bool, ending: []const u8 = "", timed_out: bool = false };
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
        for (v.array(v.get(function, "parameters"))) |parameter| {
            const name = v.text(v.get(parameter, "type"));
            if (injected(name)) continue;
            try encoder.encode(name, v.get(arguments, v.text(v.get(parameter, "name"))));
        }
        return encoder.words.items;
    }
    fn batch(self: *const Executor, call: BatchCall, limits: Limits) Error!BatchOutcome {
        const c = self.context;
        const a = c.arena;
        var nonce: [16]u8 = undefined;
        std.Io.random(c.io, &nonce);
        const stem = try std.fmt.allocPrint(a, "{s}/{s}", .{ self.directory, std.fmt.bytesToHex(nonce, .lower) });
        const input = try std.fmt.allocPrint(a, "{s}.input", .{stem});
        const output = try std.fmt.allocPrint(a, "{s}.response", .{stem});
        var request: std.ArrayList(u8) = .empty;
        try appendWord(a, &request, call.inputs.len);
        for (call.inputs) |words| {
            try appendWord(a, &request, words.len);
            for (words) |word| try appendWord(a, &request, word);
        }
        std.Io.Dir.cwd().writeFile(c.io, .{ .sub_path = input, .data = request.items }) catch return error.WriteFailed;
        const index = try std.fmt.allocPrint(a, "{d}", .{self.table_index});
        const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(limits.timeout_ms), .clock = .awake } };
        const child = std.process.run(c.backing, c.io, .{ .argv = &.{ self.executable, index, input, output }, .timeout = timeout }) catch |err| {
            return self.read(call.function, output, .{ .ending = @errorName(err), .timed_out = err == error.Timeout });
        };
        defer c.backing.free(child.stdout);
        defer c.backing.free(child.stderr);
        const ending = switch (child.term) {
            .exited => |status| if (status == 0) "" else try std.fmt.allocPrint(a, "NativeTestProcessFailed: {any}\n{s}", .{ child.term, child.stderr }),
            .signal => try std.fmt.allocPrint(a, "NativeTestProcessFailed: {any}\n{s}", .{ child.term, child.stderr }),
            else => "abnormal termination",
        };
        var result = try self.read(call.function, output, .{ .ending = ending });
        if (std.mem.indexOf(u8, child.stderr, "myl-core leakcheck:") != null and call.inputs.len != 0) {
            const count = @min(result.outcomes.len + 1, call.inputs.len);
            const outcomes = try a.alloc(Outcome, count);
            @memcpy(outcomes[0..@min(count, result.outcomes.len)], result.outcomes[0..@min(count, result.outcomes.len)]);
            outcomes[count - 1] = .{ .status = "failure", .diagnostics = try a.dupe(u8, child.stderr) };
            result.outcomes = outcomes;
        }
        result.complete = result.outcomes.len == call.inputs.len and ending.len == 0;
        return result;
    }
    const End = struct { ending: []const u8, timed_out: bool = false };
    fn read(self: *const Executor, function: Value, output: []const u8, end: End) Error!BatchOutcome {
        const c = self.context;
        const bytes = std.Io.Dir.cwd().readFileAlloc(c.io, output, c.arena, .limited(64 << 20)) catch "";
        var reader: Reader = .{ .bytes = bytes };
        var outcomes: std.ArrayList(Outcome) = .empty;
        while (reader.cursor < bytes.len) {
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
        return .{ .outcomes = outcomes.items, .complete = end.ending.len == 0, .ending = end.ending, .timed_out = end.timed_out };
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
    while (frames.next()) |line| if (std.mem.startsWith(u8, line, "  in ")) {
        if (std.mem.startsWith(u8, line["  in ".len..], "__test_")) continue;
        try rendered.print(a, "{s}\n", .{line});
        if (frame.len == 0) {
            const end = std.mem.indexOf(u8, line, " at ") orelse line.len;
            frame = line["  in ".len..end];
        }
    };
    return .{ .status = "trap", .diagnostics = rendered.items, .output = stdout, .trap = .{ .code = code, .message = message, .frame = frame } };
}

fn trapMessage(a: std.mem.Allocator, stderr: []const u8, fallback: []const u8) Error![]const u8 {
    const marker = "\x1eMYLANG-TRAP ";
    const start = (std.mem.indexOf(u8, stderr, marker) orelse return fallback) + marker.len;
    const end = std.mem.indexOfScalarPos(u8, stderr, start, '\n') orelse stderr.len;
    const record = std.json.parseFromSliceLeaky(Value, a, stderr[start..end], .{}) catch return error.InvalidTestValue;
    return v.text(v.get(record, "operation"));
}

// spec-case: NEW-CORE-S3-RUNNER-1
test "trap preserves contract messages and old numeric detail while excluding compiler wrappers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const stderr = "x.my:1:1: error[R_REQUIRES]: native execution failed: fallback\n" ++
        "  in x::test_a at x.my:1:1\n  in __test_trial_0 at x.my:1:1\n" ++
        "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\" leading: message\\nline \"}\n";
    const contract = try trap(a, stderr, "");
    try std.testing.expectEqualStrings(" leading: message\nline ", contract.trap.message);
    try std.testing.expectEqualStrings("x::test_a", contract.trap.frame);
    try std.testing.expectEqualStrings("R_REQUIRES:  leading: message\nline \n  in x::test_a at x.my:1:1\n", contract.diagnostics);
    const numeric = try trap(a, "x.my:1:1: error[R_DIVISION_BY_ZERO]: native execution failed (div: left 1, right 0)\n  in x::test_a at x.my:1:1\n", "");
    try std.testing.expectEqualStrings("R_DIVISION_BY_ZERO (div: left 1, right 0)\n  in x::test_a at x.my:1:1\n", numeric.diagnostics);
    try std.testing.expectError(error.InvalidTestValue, trapMessage(a, "\x1eMYLANG-TRAP {\n", ""));
}
