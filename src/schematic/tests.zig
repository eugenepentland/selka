//! Trusted byte-I/O boundary tests; the independent Python suite validates complete schematics.
const std = @import("std");
const t = std.testing;
const language = @import("mylang");
const bridge = @import("host.zig");
const application = @import("app.zig");
const declarations =
    \\module io;export length;export byte;export put;export issue;
    \\host fn length(file:i64)->i64 effects(host);
    \\host fn byte(file:i64,position:i64)->u8 effects(host);
    \\host fn put(value:u8)->i64 effects(host);
    \\host fn issue(code:i64,file:i64,position:i64)->i64 effects(host);
;
const main_source =
    \\module main;import io;
    \\fn main()->i64{let n=io::length(0);discard io::put(65u8);while n==2{discard io::put(66u8);}return n;}
;
fn provider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    const bytes = if (std.mem.eql(u8, path, "io.my")) declarations else if (std.mem.eql(u8, path, "main.my")) main_source else return error.NotFound;
    if (bytes.len > limit) return error.TooLarge;
    return allocator.dupe(u8, bytes);
}
fn callbackScenario(allocator: std.mem.Allocator, code: language.bytecode.Program) !void {
    var context: bridge.Context = .{ .allocator = allocator, .documents = &.{"\xc2\xb5"} };
    defer context.deinit();
    var registry = try language.vm_host.Registry.init(allocator, code);
    defer registry.deinit();
    try context.install(&registry);
    const session = try registry.begin(allocator, code, .{});
    defer session.close() catch |err| std.debug.panic("host session cleanup failed: {s}", .{@errorName(err)});
    const length = try registry.registry.resolve("io::length");
    const byte = try registry.registry.resolve("io::byte");
    const put = try registry.registry.resolve("io::put");
    const issue = try registry.registry.resolve("io::issue");
    try t.expectEqual(@as(i64, 2), (try session.call(length, &.{.{ .i64 = 0 }})).i64);
    try t.expectEqual(@as(i128, 181), (try session.call(byte, &.{ .{ .i64 = 0 }, .{ .i64 = 1 } })).integer.value);
    try hostFailure(error.HostFailure, session.call(byte, &.{ .{ .i64 = 0 }, .{ .i64 = -1 } }));
    try hostFailure(error.HostFailure, session.call(byte, &.{ .{ .i64 = 0 }, .{ .i64 = 2 } }));
    try hostFailure(error.HostFailure, session.call(length, &.{.{ .i64 = 1 }}));
    _ = try session.call(put, &.{language.vm.Value.number(.u8, 65)});
    try t.expectEqualStrings("A", context.output.items);
    _ = try session.call(issue, &.{ .{ .i64 = 15 }, .{ .i64 = 0 }, .{ .i64 = 9 } });
    _ = try session.call(issue, &.{ .{ .i64 = 20 }, .{ .i64 = 0 }, .{ .i64 = 10 } });
    try t.expectEqualDeep(bridge.Issue{ .code = 15, .file = 0, .position = 9 }, context.issue.?);
    try context.output.resize(allocator, 4 * 1024 * 1024);
    try hostFailure(error.HostWorkLimit, session.call(put, &.{language.vm.Value.number(.u8, 66)}));
}
fn hostFailure(expected: anyerror, result: language.host_functions.Error!language.vm.Value) !void {
    const value = result catch |err| {
        if (err == error.OutOfMemory) return err;
        try t.expectEqual(expected, err);
        return;
    };
    value.release(t.allocator);
    try t.expect(false);
}
// spec: SCHEMATIC-1
test "schematic byte callbacks and hostFailure preserve bounds output ownership and first issue under allocation failure" {
    var app: application.App = undefined;
    try app.init(t.allocator, .{ .context = null, .read = provider });
    defer app.deinit();
    try callbackScenario(t.allocator, app.program.compilation.code.?);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), callbackScenario, .{app.program.compilation.code.?});
}
test "schematic documents reject malformed UTF8 and XML controls with exact byte positions" {
    try t.expect(bridge.validateDocuments(&.{"ok \xc2\xb5\n\t\r"}) == null);
    for ([_][]const u8{ "\xff", "\xc0\x80", "\xed\xa0\x80", "\x00", "\xef\xbf\xbe", "\xf4\x90\x80\x80" }) |invalid| {
        const issue = bridge.validateDocuments(&.{ "valid", invalid }).?;
        try t.expectEqualDeep(bridge.Issue{ .code = 8, .file = 1, .position = 0 }, issue);
    }
    const big = try t.allocator.alloc(u8, 1024 * 1024 + 1);
    defer t.allocator.free(big);
    try t.expectEqual(@as(i64, 7), bridge.validateDocuments(&.{big}).?.code);
}
test "schematic application clears output and trap state between bounded runs" {
    var app: application.App = undefined;
    try app.init(t.allocator, .{ .context = null, .read = provider });
    defer app.deinit();
    const invalid: [3][]const u8 = .{ "\xff", "", "" };
    try t.expectError(error.InvalidSchematic, app.run(t.allocator, &invalid, .{}));
    try t.expectEqual(@as(i64, 8), app.issue.?.code);
    const nonzero: [3][]const u8 = .{ "one", "", "" };
    try t.expectError(error.InvalidSchematic, app.run(t.allocator, &nonzero, .{}));
    const docs: [3][]const u8 = .{ "", "", "" };
    const partial: [3][]const u8 = .{ "xx", "", "" };
    try t.expectError(error.GuestTrap, app.run(t.allocator, &partial, .{ .max_steps = 100 }));
    try t.expectEqualStrings("R_STEP_LIMIT", app.trap.?.code);
    const result = try app.run(t.allocator, &docs, .{});
    defer t.allocator.free(result);
    try t.expect(app.trap == null and app.issue == null);
    try t.expectEqualStrings("A", result);
    try t.expectError(error.TooLarge, provider(null, t.allocator, "main.my", 0));
    try t.expectError(error.NotFound, provider(null, t.allocator, "unknown.my", 1024));
}

// spec: DISK-PROJECT-1
test "disk initSource and initDisk release failed compilations and reload bounded sources" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var disk: language.project_files.Files = .{ .io = t.io, .root = root };
    try t.expectError(error.NotFound, language.project_files.Files.read(&disk, t.allocator, "main.my", 100));
    try temp.dir.writeFile(t.io, .{ .sub_path = "main.my", .data = main_source });
    try t.expectError(error.TooLarge, language.project_files.Files.read(&disk, t.allocator, "main.my", main_source.len - 1));
    const exact = try language.project_files.Files.read(&disk, t.allocator, "main.my", main_source.len);
    defer t.allocator.free(exact);
    try t.expectEqualStrings(main_source, exact);
    var app: application.App = undefined;
    try t.expectError(error.SourceError, app.initDisk(t.allocator, t.io, root));
    try temp.dir.writeFile(t.io, .{ .sub_path = "io.my", .data = "module io; broken" });
    try t.expectError(error.SourceError, app.initDisk(t.allocator, t.io, root));
    try temp.dir.writeFile(t.io, .{ .sub_path = "io.my", .data = declarations });
    try temp.dir.writeFile(t.io, .{ .sub_path = "main.my", .data = "module main; fn main()->i64 { return true; }" });
    try t.expectError(error.SourceError, app.initDisk(t.allocator, t.io, root));
    try temp.dir.writeFile(t.io, .{ .sub_path = "main.my", .data = main_source });
    try app.initDisk(t.allocator, t.io, root);
    defer app.deinit();
    const output = try app.run(t.allocator, &.{ "", "", "" }, .{});
    defer t.allocator.free(output);
    try t.expectEqualStrings("A", output);
}

// The independent Python oracle checks this same fixture's electrical geometry.
// This test additionally forces GC at allocation boundaries during real parsing,
// graph construction, shared row mutation and rendering, using a leak-checking allocator.
// spec: SCHEMATIC-MODEL-1
test "schematic managed fixture keeps identical SVG under collection stress and reclaims temporary graphs" {
    var files = std.heap.ArenaAllocator.init(t.allocator);
    defer files.deinit();
    const input_allocator = files.allocator();
    const names = [_][]const u8{ "straps-synth-lmx2595.sexp", "lmx2595rhar.sexp", "spi.sexp" };
    var documents: [3][]const u8 = undefined;
    for (names, &documents) |name, *document| {
        const path = try std.fmt.allocPrint(input_allocator, "experiments/schematic/fixtures/{s}", .{name});
        document.* = try std.Io.Dir.cwd().readFileAlloc(t.io, path, input_allocator, .limited(1024 * 1024));
    }
    var app: application.App = undefined;
    try app.initDisk(t.allocator, t.io, "src/schematic/guest");
    defer app.deinit();
    const normal = try app.run(t.allocator, &documents, .{ .max_steps = 100_000_000 });
    defer t.allocator.free(normal);
    const expected = try std.Io.Dir.cwd().readFileAlloc(t.io, "experiments/schematic/straps-synth-lmx2595.svg", input_allocator, .limited(1024 * 1024));
    try t.expectEqualStrings(expected, normal);
    var statistics: language.vm.GcStatistics = .{};
    const stressed = try app.run(t.allocator, &documents, .{
        .max_steps = 100_000_000,
        .memory = .{ .gc = .{ .stress = true, .statistics = &statistics } },
    });
    defer t.allocator.free(stressed);
    try t.expectEqualStrings(normal, stressed);
    try t.expect(statistics.created >= 9);
    try t.expect(statistics.collections > statistics.created);
    try t.expect(statistics.reclaimed > 0);
    try t.expectEqual(@as(usize, 0), statistics.live_objects);
}

test {
    _ = @import("dev_session.zig");
}

const named_main =
    \\module main;import io;
    \\fn main()->i64{
    \\let inputs=io::inputs();
    \\discard io::put(io::byte(io::Document.id(inputs.circuit),0));
    \\discard io::put(io::byte(io::Document.id(inputs.pinout),0));
    \\discard io::put(io::byte(io::Document.id(inputs.interface),0));
    \\return 0;
    \\}
;
fn namedProvider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    const bytes = if (std.mem.eql(u8, path, "io.my")) @embedFile("guest/io.my") else if (std.mem.eql(u8, path, "main.my")) named_main else return error.NotFound;
    if (bytes.len > limit) return error.TooLarge;
    return allocator.dupe(u8, bytes);
}
fn namedScenario(allocator: std.mem.Allocator, code: language.bytecode.Program) !void {
    var context: bridge.Context = .{ .allocator = allocator, .documents = &.{ "Circuit", "Pinout", "Interface" } };
    defer context.deinit();
    var registry = try language.vm_host.Registry.init(allocator, code);
    defer registry.deinit();
    try context.install(&registry);
    const result = try language.vm.runWithHost(allocator, code, .{}, &registry, .{});
    try t.expectEqual(@as(i64, 0), result.value);
    try t.expectEqualStrings("CPI", context.output.items);
}

// spec: SCHEMATIC-INPUTS-1
test "named schematic input handles select their host documents and retain scalar byte ABI under allocation failure" {
    var app: application.App = undefined;
    try app.init(t.allocator, .{ .context = null, .read = namedProvider });
    defer app.deinit();
    try namedScenario(t.allocator, app.program.compilation.code.?);
    try t.checkAllAllocationFailures(t.allocator, namedScenario, .{app.program.compilation.code.?});
}

// spec: SCHEMATIC-INPUTS-2
test "named schematic input providers reject missing documents" {
    var app: application.App = undefined;
    try app.init(t.allocator, .{ .context = null, .read = namedProvider });
    defer app.deinit();
    const code = app.program.compilation.code.?;
    var context: bridge.Context = .{ .allocator = t.allocator, .documents = &.{ "Circuit", "Pinout" } };
    defer context.deinit();
    var registry = try language.vm_host.Registry.init(t.allocator, code);
    defer registry.deinit();
    try context.install(&registry);
    const session = try registry.begin(t.allocator, code, .{});
    defer session.close() catch unreachable;
    const interface_input = try registry.registry.resolve("io::interface_input");
    try hostFailure(error.HostFailure, session.call(interface_input, &.{}));
}

const decimal_main =
    \\module main
    \\import io
    \\import text
    \\def main() -> int:
    \\    text.decimal(-12)
    \\    _ = io.put(44u8)
    \\    text.decimal(-9223372036854775808)
    \\    _ = io.put(44u8)
    \\    text.decimal(0)
    \\    return 0
;
fn decimalProvider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    const bytes = if (std.mem.eql(u8, path, "main.my")) decimal_main else if (std.mem.eql(u8, path, "text.my")) @embedFile("guest/text.my") else if (std.mem.eql(u8, path, "io.my")) @embedFile("guest/io.my") else return error.NotFound;
    if (bytes.len > limit) return error.TooLarge;
    return allocator.dupe(u8, bytes);
}
// spec: SCHEMATIC-PYTHON-1
test "Python schematic decimal output preserves negative numbers and minimum integer" {
    var app: application.App = undefined;
    try app.init(t.allocator, .{ .context = null, .read = decimalProvider });
    defer app.deinit();
    const output = try app.run(t.allocator, &.{ "", "", "" }, .{ .memory = .{ .gc = .{ .stress = true } } });
    defer t.allocator.free(output);
    try t.expectEqualStrings("-12,-9223372036854775808,0", output);
}
