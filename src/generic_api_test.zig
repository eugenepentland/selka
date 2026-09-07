//! Checked public template schemas preserve symbolic contracts and private boundaries.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const File = @import("embedded_project.zig").File;
const library = "module lib; export Box; export Answer; export echo; " ++
    "struct Box<T:copy>{value:T} result Answer<T:copy>{ok:T,err:i64}" ++
    "fn echo<T:equality>(x:[2]T)->[2]T effects(){return x;}" ++
    "fn hidden<T:copy>(x:T)->T{return x;}";
const entry = "module main;import lib as api;export run;" ++
    "fn run(x:i64)->i64{return x;}fn main()->i64{return 0;}";
const Files = struct {
    library: []const u8 = library,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, &.{
            File{ .path = "main.my", .bytes = entry },
            File{ .path = "lib.my", .bytes = self.library },
        }, path, limit);
    }
};
fn inspect(allocator: std.mem.Allocator, library_source: []const u8) ![]u8 {
    var files: Files = .{ .library = library_source };
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    return language.schema_report.render(allocator, &compilation, .{
        .compiler_sha256 = @splat(42),
        .zig_version = "test",
        .architecture = "x86_64",
        .os = "linux",
        .abi = "gnu",
        .optimize = "Debug",
    });
}
fn scenario(allocator: std.mem.Allocator) !void {
    const bytes = try inspect(allocator, library);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const schema = parsed.value.object.get("schema").?.object;
    const templates = schema.get("generic_templates").?.array.items;
    try t.expectEqual(@as(usize, 3), templates.len);
    try t.expectEqualStrings("lib::Answer", templates[0].object.get("name").?.string);
    try t.expectEqualStrings("lib::Box", templates[1].object.get("name").?.string);
    const echo = templates[2].object;
    const contract = echo.get("contract").?.object;
    const signature = contract.get("signature").?.object;
    try t.expectEqualStrings("lib::echo", echo.get("name").?.string);
    try t.expect(!contract.get("callable").?.bool);
    try t.expect(contract.get("requires_explicit_instantiation").?.bool);
    try t.expectEqualStrings("[2]T", signature.get("result").?.string);
    try t.expectEqualStrings("equality", contract.get("type_parameters").?.array.items[0].object.get("requirements").?.array.items[0].string);
    try t.expectEqual(@as(usize, 0), signature.get("declared_effects").?.array.items.len);
    try t.expectEqualStrings("lib.my", echo.get("source").?.object.get("path").?.string);
    try t.expectEqual(@as(usize, 64), echo.get("source").?.object.get("sha256").?.string.len);
    try t.expectEqual(@as(usize, 0), schema.get("exports").?.array.items.len);
    const functions = schema.get("functions").?.array.items;
    try t.expectEqual(@as(usize, 1), functions.len);
    try t.expectEqualStrings("main::run", functions[0].object.get("name").?.string);
}
// spec: GENERIC-API-1
test "public generic schema separates checked templates from calls and releases allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "public generic identities survive whitespace while source receipts change" {
    const a = try inspect(t.allocator, library);
    defer t.allocator.free(a);
    const b = try inspect(t.allocator, "\n" ++ library);
    defer t.allocator.free(b);
    const first = try std.json.parseFromSlice(std.json.Value, t.allocator, a, .{});
    defer first.deinit();
    const second = try std.json.parseFromSlice(std.json.Value, t.allocator, b, .{});
    defer second.deinit();
    try t.expect(!std.mem.eql(u8, first.value.object.get("source_sha256").?.string, second.value.object.get("source_sha256").?.string));
    const left = first.value.object.get("schema").?.object.get("generic_templates").?.array.items;
    const right = second.value.object.get("schema").?.object.get("generic_templates").?.array.items;
    for (left, right) |before, after| {
        try t.expectEqualStrings(before.object.get("name").?.string, after.object.get("name").?.string);
        try t.expectEqual(before.object.get("source").?.object.get("line").?.integer + 1, after.object.get("source").?.object.get("line").?.integer);
    }
}
test "public generic schema refuses invalid uncalled bodies" {
    try t.expectError(error.SourceError, inspect(t.allocator, "module lib;export bad;fn bad<T:copy>(x:T)->bool{return x==x;}"));
}

test "public generic schemas retain structural field operation and codec constraints" {
    const bytes = try inspect(t.allocator, "module lib;export field;export action;export coded;" ++
        "fn field<T:copy+field(value:i64)>(x:T)->i64{return x.value;}" ++
        "fn action<T:copy+op(score(value:T)->i64 effects())>(x:T)->i64{return T.score(x);}" ++
        "fn coded<T:copy+codec>(x:T)->T{return x;}");
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    const templates = parsed.value.object.get("schema").?.object.get("generic_templates").?.array.items;
    const action = templates[0].object.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    const operation = action.get("operation_requirements").?.array.items[0].object;
    try t.expectEqualStrings("score", operation.get("name").?.string);
    try t.expectEqualStrings("i64", operation.get("result").?.string);
    try t.expectEqual(@as(usize, 0), operation.get("declared_effects").?.array.items.len);
    const coded = templates[1].object.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    try t.expectEqualStrings("codec", coded.get("requirements").?.array.items[1].string);
    const field = templates[2].object.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    try t.expectEqualStrings("value", field.get("field_requirements").?.array.items[0].object.get("name").?.string);
    try t.expectError(error.SourceError, inspect(t.allocator, "module lib;struct Secret{}export f;" ++
        "fn f<T:copy+field(value:Secret)>(x:T)->i64{return 0;}"));
}
