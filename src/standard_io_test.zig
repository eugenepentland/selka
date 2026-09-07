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
// spec: STANDARD-IO-1
test "standard IO imports expose strict paths and bounded joining" {
    try run("module main;import std_path;import std_bytes;import std_result;import std_fs;import std_io;" ++
        "fn main(heap:allocator)->i64{" ++
        "if std_path::valid(\"../a\") || std_path::valid(\"a//b\") || std_path::valid(\"/x\"){return -1;}" ++
        "match std_path::extension(\"a/name.txt\"){std_result::Option<std_path::Span>.none=>{return -2;}," ++
        "std_result::Option<std_path::Span>.some(span)=>{if span.start!=7u64 || span.end!=10u64{return -3;}}}" ++
        "match std_path::join(heap,\"a\",\"b\",3u64){std_bytes::Built.err(discard)=>{return -4;},std_bytes::Built.ok(bytes)=>{" ++
        "borrow bytes[0..len_buffer(bytes)] as view{return std_bytes::compare(view,\"a/b\");}}}}", 0);
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
test "standard IO convenient file writes report actual provider progress and complete cleanup" {
    const text = "module main;import std_fs;fn main(heap:allocator,fs:filesystem_cap)->i64{" ++
        "match std_fs::write_file(heap,fs,\"data\",new std_fs::Mode.write_existing,\"hello\"){" ++
        "std_fs::WriteFile.ok(n)=>{return cast<i64>(n);},std_fs::WriteFile.err(e)=>{return cast<i64>(e.progress);}}}";
    var normal: io_fixture.Provider = .{};
    try ioScenario(text, &normal, 5);
    try t.expectEqualStrings("hello", normal.progress.output[0..normal.progress.length]);
    var failed: io_fixture.Provider = .{ .failure = .{ .write = 1 } };
    try ioScenario(text, &failed, 2);
    try t.expectEqualStrings("he", failed.progress.output[0..failed.progress.length]);
}
test "standard IO convenient file reads accept exact bounds and retain partial failure data" {
    const prefix = "module main;import std_fs;import std_bytes;fn main(heap:allocator,fs:filesystem_cap)->i64{" ++
        "match std_bytes::create(heap,3){std_bytes::Built.err(discard)=>{return -1;},std_bytes::Built.ok(bytes)=>{" ++
        "match std_fs::read_file(heap,fs,\"data\",bytes,";
    const suffix = "){std_fs::ReadFile.ok(result)=>{return cast<i64>(len_buffer(result));}," ++
        "std_fs::ReadFile.err(failure)=>{let n=read_field(failure,progress);let partial=take_field(failure,bytes);" ++
        "if len_buffer(partial)!=n{return -2;}return cast<i64>(n);}}}}}";
    var exact: io_fixture.Provider = .{};
    try ioScenario(prefix ++ "3u64" ++ suffix, &exact, 3);
    var partial: io_fixture.Provider = .{};
    try ioScenario(prefix ++ "2u64" ++ suffix, &partial, 2);
    var empty: io_fixture.Provider = .{ .input = "" };
    try ioScenario(prefix ++ "0u64" ++ suffix, &empty, 0);
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
test "standard IO directory decoders reject invalid framing traversal and zero bytes" {
    try run("module main;import std_fs;import std_result;fn main()->i64{" ++
        "let invalid=new [7]u8[1u8,1u8,3u8,0u8,46u8,46u8,47u8];" ++
        "borrow invalid[0..7] as view{match std_fs::directory_count(view){std_result::Option<u64>.some(discard)=>{return -1;},std_result::Option<u64>.none=>{}}}" ++
        "let truncated=new [4]u8[1u8,1u8,3u8,0u8];" ++
        "borrow truncated[0..4] as view{match std_fs::directory_entry(view,0u64){std_result::Option<std_fs::DirectoryEntry>.some(discard)=>{return -2;},std_result::Option<std_fs::DirectoryEntry>.none=>{}}}return 0;}", 0);
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
test "standard IO metadata rejects malformed wire and preserves full u64 size" {
    const text = "module main;import std_fs;import std_io;fn main(heap:allocator,fs:filesystem_cap)->i64{" ++
        "match std_fs::metadata(heap,fs,\"data\"){std_fs::MetadataResult.ok(value)=>{" ++
        "if value.size!=18446744073709551615u64{return -1;}return 42;},std_fs::MetadataResult.err(cause)=>{" ++
        "if cause.kind==new std_io::Kind.malformed{return 1;}if cause.kind==new std_io::Kind.unexpected_eof{return 2;}return -2;}}}";
    var maximum: io_fixture.Provider = .{ .input = &.{ 1, 1, 255, 255, 255, 255, 255, 255, 255, 255 } };
    try ioScenario(text, &maximum, 42);
    var malformed: io_fixture.Provider = .{ .input = &.{ 2, 1, 255, 255, 255, 255, 255, 255, 255, 255 } };
    try ioScenario(text, &malformed, 1);
    var truncated: io_fixture.Provider = .{ .input = &.{ 1, 1, 255 } };
    try ioScenario(text, &truncated, 2);
}
