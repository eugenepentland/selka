//! Source-level standard paths and state-preserving buffered filesystem helpers.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const Fixture = struct {
    text: []const u8,
    fn load(raw: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Fixture = @ptrCast(@alignCast(raw.?));
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        if (self.text.len > limit) return error.TooLarge;
        return allocator.dupe(u8, self.text);
    }
};
fn run(text: []const u8, expected: i64) !void {
    var fixture: Fixture = .{ .text = text };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &fixture, .read = Fixture.load });
    defer program.deinit();
    const outcome = try language.vm.run(t.allocator, program.compilation.code.?);
    try t.expectEqual(expected, outcome.value);
}
// spec: STANDARD-IO-5
test "acquisitionBytes rejects nonbyte values before reading provider memory" {
    try t.expectError(error.InternalError, @import("byte_values.zig").acquisitionBytes(t.allocator, .{ .i64 = 7 }, .i64, &.{}));
}
const io_fixture = @import("standard_io_fixture.zig");
fn ioScenario(text: []const u8, provider: *io_fixture.Provider, expected: i64) !void {
    var source_fixture: io_fixture.Source = .{ .text = text };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &source_fixture, .read = io_fixture.Source.load });
    defer program.deinit();
    const outcome = try language.vm.runWithOptions(t.allocator, program.compilation.code.?, .{ .resources = .{ .filesystem = provider.provider() } });
    try t.expectEqual(expected, outcome.value);
    try t.expect(!provider.live);
    try t.expectEqual(provider.calls.acquire, provider.calls.release);
}
// spec: STANDARD-IO-2
// spec: STANDARD-IO-3
test "standard IO retains partial reads EOF buffered limit byte and failed write progress" {
    var read_provider: io_fixture.Provider = .{};
    try ioScenario(@embedFile("stdlib/fixtures/io/read.my"), &read_provider, 3);
    try t.expectEqual(@as(usize, 2), read_provider.calls.read);
    var limit_provider: io_fixture.Provider = .{};
    try ioScenario(@embedFile("stdlib/fixtures/io/collect.my"), &limit_provider, 99);
    var writer: io_fixture.Provider = .{ .failure = .{ .write = 1 } };
    try ioScenario(@embedFile("stdlib/fixtures/io/write.my"), &writer, 5);
    try t.expectEqualStrings("hello", writer.progress.output[0..writer.progress.length]);
    var stalled: io_fixture.Provider = .{ .failure = .{ .read = 0, .stalled = true } };
    try ioScenario(@embedFile("stdlib/fixtures/io/read.my"), &stalled, 10);
    try t.expectEqual(@as(usize, 1), stalled.calls.read);
    var failed: io_fixture.Provider = .{ .failure = .{ .read = 1 } };
    try ioScenario(@embedFile("stdlib/fixtures/io/read.my"), &failed, 22);
}
fn injectedIo(allocator: std.mem.Allocator, code: language.bytecode.Program) !void {
    var provider: io_fixture.Provider = .{};
    defer {
        std.debug.assert(!provider.live);
        std.debug.assert(provider.calls.acquire == provider.calls.release);
    }
    const result = try language.vm.runWithOptions(allocator, code, .{ .resources = .{ .filesystem = provider.provider() } });
    try t.expectEqual(@as(i64, 3), result.value);
}
// spec: STANDARD-IO-4
test "standard IO dynamic requests and opened files unwind on every OutOfMemory position" {
    var fixture: io_fixture.Source = .{ .text = @embedFile("stdlib/fixtures/io/read.my") };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &fixture, .read = io_fixture.Source.load });
    defer program.deinit();
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), injectedIo, .{program.compilation.code.?});
}
test "standard IO line reading accepts delimiter at bound and retains next line data" {
    var provider: io_fixture.Provider = .{ .input = "a\nb" };
    try ioScenario(@embedFile("stdlib/fixtures/io/line.my"), &provider, 98);
    try t.expectEqual(@as(usize, 2), provider.calls.read);
}
test "standard IO typed paths reject before acquiring provider authority" {
    const source = try std.mem.replaceOwned(u8, t.allocator, @embedFile("stdlib/fixtures/io/read.my"), "\"data\"", "\"../data\"");
    defer t.allocator.free(source);
    var provider: io_fixture.Provider = .{};
    try ioScenario(source, &provider, -11);
    try t.expectEqual(@as(usize, 0), provider.calls.acquire);
}
// spec: STANDARD-DIRECTORY-1
test "standard IO metadata and directory entries preserve kinds size and opaque nonopenable names" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data", .data = "abc" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "odd\\name", .data = "x" });
    try temporary.dir.createDir(t.io, "nested", .default_dir);
    try temporary.dir.symLink(t.io, "data", "link", .{});
    var source_fixture: io_fixture.Source = .{ .text = @embedFile("stdlib/fixtures/io/metadata.my") };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &source_fixture, .read = io_fixture.Source.load });
    defer program.deinit();
    var context: language.scoped_providers.Context = .{ .allocator = t.allocator, .io = t.io, .directory = temporary.dir };
    defer context.deinit();
    const result = try language.vm.runWithOptions(t.allocator, program.compilation.code.?, .{ .resources = .{ .filesystem = context.filesystem() } });
    try t.expectEqual(@as(i64, 15), result.value);
    for (context.handles.items) |handle| try t.expect(handle == null);
}
test "standard IO independent prebuffer retry EOF edges and completion failure regressions" {
    var prebuffer: io_fixture.Provider = .{ .failure = .{ .write = 1 } };
    try ioScenario(@embedFile("stdlib/fixtures/io/prebuffer.my"), &prebuffer, 42);
    try t.expectEqualStrings("012345678901234567890123456789012345678901234567890123456789ABCDEFGH", prebuffer.progress.output[0..prebuffer.progress.length]);
    var finish: io_fixture.Provider = .{ .failure = .{ .complete = 0 } };
    try ioScenario(@embedFile("stdlib/fixtures/io/finish_retry.my"), &finish, 42);
    try t.expectEqual(@as(usize, 2), finish.calls.complete);
    try t.expectEqualStrings("hi", finish.progress.output[0..finish.progress.length]);
    var edges: io_fixture.Provider = .{};
    try ioScenario(@embedFile("stdlib/fixtures/io/read_edges.my"), &edges, 42);
    try t.expectEqual(@as(usize, 2), edges.calls.read);
}
