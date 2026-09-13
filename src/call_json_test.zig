const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const codec = language.codec_json;
const source = "module data;export D;export R;export Output;export combine;export fail;export " ++
    "constant;export view;export cap;export clock;export Time;export loop;result R{ok:D," ++
    "err:i64}domain D:i64{codec i64{decode:dec,encode:enc}private fn raw(x:i64)->D{return " ++
    "wrap<D>(x);}fn dec(x:i64)->R{if x<=0{return new R.err(-1);}return new R.ok(D.raw(x));" ++
    "}fn enc(x:D)->i64{return unwrap(x);}}struct Output{value:D,total:i64}fn " ++
    "combine(left:D,right:i64)->Output{return new Output{value:left," ++
    "total:D.enc(left)+right};}fn fail(x:i64)->R{return new R.err(x);}fn " ++
    "constant()->u64{return 18446744073709551615u64;}fn view(x:&i64)->i64{return " ++
    "read_ref(x);}fn cap(x:allocator)->i64{return 0;}result Time{ok:i64,err:i64}fn " ++
    "clock(c:clock_cap)->Time{return clock_now<Time>(c);}fn hidden()->i64{return 1;}fn " ++
    "loop(x:i64)->i64{return loop(x);}";
const Provider = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "module main;import data;fn main()->i64{return 0;}");
        if (std.mem.eql(u8, path, "data.my")) return allocator.dupe(u8, source);
        return error.NotFound;
    }
};
fn request(allocator: std.mem.Allocator, c: *language.project_compile.Compilation, name: []const u8, arguments: []const u8) ![]u8 {
    const schema = try language.schema.render(allocator, c);
    defer allocator.free(schema);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(schema, &digest, .{});
    return std.fmt.allocPrint(allocator, "{{\"version\":\"typed-call-v1\",\"schema_sha256\":\"{s}\",\"function\":\"{s}\",\"arguments\":{s}}}", .{ std.fmt.bytesToHex(digest, .lower), name, arguments });
}
fn scenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Provider.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    var failure: codec.Failure = .{};
    defer failure.deinit(allocator);
    const bytes = try request(allocator, &c, "data::combine", "{\"right\":\"5\",\"left\":\"7\"}");
    defer allocator.free(bytes);
    var stats: codec.Statistics = .{};
    const output = try codec.invokeProject(allocator, &c, bytes, .{ .statistics = &stats }, &failure);
    defer allocator.free(output);
    try t.expectEqualStrings("{\"version\":\"typed-json-v1\",\"type\":\"data::Output\",\"value\":{\"value\":\"7\",\"total\":\"12\"}}", output);
    // Error results returned by the target remain data, not invocation failures.
    const fail_request = try request(allocator, &c, "data::fail", "{\"x\":\"-3\"}");
    defer allocator.free(fail_request);
    const fail_output = try codec.invokeProject(allocator, &c, fail_request, .{}, &failure);
    defer allocator.free(fail_output);
    try t.expectEqualStrings("{\"version\":\"typed-json-v1\",\"type\":\"data::R\",\"value\":{\"case\":\"err\",\"value\":\"-3\"}}", fail_output);
}
test "JSON function calls execute named domain arguments and typed results under every allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
// spec: WIRE-6
test "JSON function calls reject stale schemas visibility effects references and malformed arguments before execution" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Provider.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    var failure: codec.Failure = .{};
    defer failure.deinit(t.allocator);
    var stats: codec.Statistics = .{};
    const cases = .{
        .{ "data::hidden", "{}", error.UnknownPublicFunction },
        .{ "data::D.raw", "{\"x\":\"1\"}", error.UnknownPublicFunction },
        .{ "data::clock", "{\"c\":false}", error.InvocationEffects },
        .{ "data::view", "{\"x\":\"1\"}", error.InvocationReference },
        .{ "data::cap", "{\"x\":false}", error.NotDataType },
        .{ "data::combine", "{}", error.InvocationArguments },
        .{ "data::combine", "{\"left\":\"0\",\"wrong\":\"5\"}", error.InvocationArguments },
        .{ "data::combine", "[]", error.InvocationArguments },
    };
    inline for (cases) |case| {
        const bytes = try request(t.allocator, &c, case[0], case[1]);
        defer t.allocator.free(bytes);
        try t.expectError(case[2], codec.invokeProject(t.allocator, &c, bytes, .{ .statistics = &stats }, &failure));
    }
    const stale = try request(t.allocator, &c, "data::combine", "{\"left\":\"0\",\"right\":\"5\"}");
    defer t.allocator.free(stale);
    const hash_start = std.mem.indexOf(u8, stale, "schema_sha256\":\"").? + "schema_sha256\":\"".len;
    stale[hash_start] = '0' + @as(u8, @intFromBool(stale[hash_start] == '0'));
    try t.expectError(error.InvocationSchemaMismatch, codec.invokeProject(t.allocator, &c, stale, .{ .statistics = &stats }, &failure));
    try t.expectEqualStrings("/schema_sha256", failure.location.text());
}
test "JSON function call budgets span decoding execution and encoding with located failures" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Provider.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    var failure: codec.Failure = .{};
    defer failure.deinit(t.allocator);
    const bytes = try request(t.allocator, &c, "data::combine", "{\"left\":\"7\",\"right\":\"5\"}");
    defer t.allocator.free(bytes);
    var stats: codec.Statistics = .{};
    const output = try codec.invokeProject(t.allocator, &c, bytes, .{ .statistics = &stats }, &failure);
    t.allocator.free(output);
    const exact = stats;
    const limited = try codec.invokeProject(t.allocator, &c, bytes, .{ .max_steps = exact.steps, .max_calls = exact.calls, .max_work_values = exact.values }, &failure);
    t.allocator.free(limited);
    try t.expectError(error.CodecCallLimit, codec.invokeProject(t.allocator, &c, bytes, .{ .max_calls = 1 }, &failure));
    try t.expectEqualStrings("/function", failure.location.text());
    try t.expectError(error.CodecCallLimit, codec.invokeProject(t.allocator, &c, bytes, .{ .max_calls = 2 }, &failure));
    try t.expectEqualStrings("/value/value", failure.location.text());
    try t.expectError(error.DomainCodecTrap, codec.invokeProject(t.allocator, &c, bytes, .{ .max_steps = exact.steps - 1 }, &failure));
    try t.expectEqualStrings("/value/value", failure.location.text());
    try t.expectError(error.CodecMemoryLimit, codec.invokeProject(t.allocator, &c, bytes, .{ .max_bytes = 1 }, &failure));
    const bad = try request(t.allocator, &c, "data::combine", "{\"left\":\"0\",\"right\":\"5\"}");
    defer t.allocator.free(bad);
    try t.expectError(error.DomainCodecRejected, codec.invokeProject(t.allocator, &c, bad, .{}, &failure));
    try t.expectEqualStrings("/arguments/left", failure.location.text());
    try t.expectEqual(@as(i64, -1), failure.execution.rejection.?.i64);
    failure.deinit(t.allocator);
    const loop = try request(t.allocator, &c, "data::loop", "{\"x\":\"1\"}");
    defer t.allocator.free(loop);
    try t.expectError(error.InvocationTrap, codec.invokeProject(t.allocator, &c, loop, .{ .max_frames = 2 }, &failure));
    try t.expectEqualStrings("/function", failure.location.text());
    try t.expectEqualStrings("R_FRAME_LIMIT", failure.execution.trap.?.code);
    try t.expectEqualStrings("data::loop", failure.execution.trap.?.stack.frames[0].function);
    const constant = try request(t.allocator, &c, "data::constant", "{}");
    defer t.allocator.free(constant);
    const number = try codec.invokeProject(t.allocator, &c, constant, .{ .max_calls = 1 }, &failure);
    defer t.allocator.free(number);
    try t.expectEqualStrings("{\"version\":\"typed-json-v1\",\"type\":\"u64\",\"value\":\"18446744073709551615\"}", number);
}
const Dynamic = struct {
    bytes: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Dynamic = @ptrCast(@alignCast(context.?));
        return allocator.dupe(u8, self.bytes);
    }
};
test "JSON function call argument envelope depth preserves the 128 level value boundary" {
    for ([_]usize{ 127, 128 }) |levels| {
        var text = std.Io.Writer.Allocating.init(t.allocator);
        defer text.deinit();
        try text.writer.writeAll("module data;export consume;");
        for (0..levels) |index| try text.writer.print("export R{d};", .{index});
        for (0..levels) |index| {
            try text.writer.print("struct R{d}{{next:", .{index});
            if (index + 1 == levels) try text.writer.writeAll("bool}") else try text.writer.print("R{d}}}", .{index + 1});
        }
        try text.writer.writeAll("fn consume(x:R0)->bool{return true;}fn main()->i64{return 0;}");
        var dynamic: Dynamic = .{ .bytes = text.written() };
        var project = language.project.Project.init(t.allocator);
        defer project.deinit();
        try project.load(.{ .context = &dynamic, .read = Dynamic.read }, "data", .{});
        var index = try language.interfaces.build(&project);
        var c = try language.project_compile.Compilation.init(&index);
        var arguments = std.Io.Writer.Allocating.init(t.allocator);
        defer arguments.deinit();
        try arguments.writer.writeAll("{\"x\":");
        for (0..levels) |_| try arguments.writer.writeAll("{\"next\":");
        try arguments.writer.writeAll("true");
        for (0..levels + 1) |_| try arguments.writer.writeByte('}');
        const bytes = try request(t.allocator, &c, "data::consume", arguments.written());
        defer t.allocator.free(bytes);
        var failure: codec.Failure = .{};
        defer failure.deinit(t.allocator);
        const options: codec.Options = .{ .json = .{ .max_depth = 128 } };
        if (levels == 127) {
            const output = try codec.invokeProject(t.allocator, &c, bytes, options, &failure);
            defer t.allocator.free(output);
            try t.expectEqualStrings("{\"version\":\"typed-json-v1\",\"type\":\"bool\",\"value\":true}", output);
        } else {
            try t.expectError(error.CodecDepthLimit, codec.invokeProject(t.allocator, &c, bytes, options, &failure));
            try t.expect(std.mem.startsWith(u8, failure.location.text(), "/arguments/x/next/"));
        }
    }
}

test "JSON calls reject UnsupportedInvocationVersion before codecs execute" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Provider.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    var failure: codec.Failure = .{};
    defer failure.deinit(t.allocator);
    var stats: codec.Statistics = .{};
    const input = "{\"version\":\"typed-call-v2\",\"schema_sha256\":\"\",\"function\":\"data::combine\",\"arguments\":{}}";
    try t.expectError(error.UnsupportedInvocationVersion, codec.invokeProject(t.allocator, &c, input, .{ .statistics = &stats }, &failure));
    try t.expectEqualStrings("/version", failure.location.text());
}
