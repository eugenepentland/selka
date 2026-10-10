//! Native coordinator boundary regression tests; no Python runtime required.
const std = @import("std");
const files = @import("component_files.zig");
const archive = @import("component_archive.zig");
const t = std.testing;

// digest takes no allocator: even a large executable cannot enter an arena.
test "streaming checksum hashes eight MiB with fixed storage" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(t.io, "large", .{});
    const block: [65536]u8 = @splat('A');
    for (0..128) |_| try file.writeStreamingAll(t.io, &block);
    file.close(t.io);
    const path = try temporary.dir.realPathFileAlloc(t.io, "large", t.allocator);
    defer t.allocator.free(path);
    const hash = try files.digest(t.io, path);
    try t.expectEqualStrings("b16bd32b101132fd0102461bc75ea65442c37293ac881ae953486c8ac26a7388", &hash);
}

test "canonical JSON matches sorted Python ensure_ascii Unicode golden" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var items: std.array_list.Managed(std.json.Value) = .init(a);
    try items.appendSlice(&.{ .{ .bool = true }, .null, .{ .integer = 42 } });
    const nested = try files.object(a, &.{.{ .name = "é", .value = files.string("雪\x00😀") }});
    const value = try files.object(a, &.{ .{ .name = "中", .value = nested }, .{ .name = "a", .value = .{ .array = items } } });
    const result = try files.canonical(a, value);
    try t.expectEqualStrings("{\"a\":[true,null,42],\"\\u4e2d\":{\"\\u00e9\":\"\\u96ea\\u0000\\ud83d\\ude00\"}}", result);
}

fn octal(bytes: []u8, value: usize) void {
    @memset(bytes, '0');
    bytes[bytes.len - 1] = 0;
    var rest = value;
    var at = bytes.len - 1;
    while (rest != 0) {
        at -= 1;
        bytes[at] = @intCast('0' + rest % 8);
        rest /= 8;
    }
}

fn entry(file: std.Io.File, name: []const u8, kind: u8, target: []const u8, content: []const u8, mode: usize) !void {
    var header: [512]u8 = @splat(0);
    @memcpy(header[0..name.len], name);
    octal(header[100..108], mode);
    octal(header[124..136], content.len);
    @memset(header[148..156], ' ');
    header[156] = kind;
    @memcpy(header[157..][0..target.len], target);
    @memcpy(header[257..263], "ustar\x00");
    @memcpy(header[263..265], "00");
    var sum: usize = 0;
    for (header) |byte| sum += byte;
    octal(header[148..156], sum);
    try file.writeStreamingAll(t.io, &header);
    try file.writeStreamingAll(t.io, content);
    const padding: [512]u8 = @splat(0);
    if (content.len % 512 != 0) try file.writeStreamingAll(t.io, padding[0 .. 512 - content.len % 512]);
}

fn paths(temporary: std.Io.Dir, a: std.mem.Allocator) !struct { source: [:0]const u8, destination: [:0]const u8 } {
    try temporary.createDir(t.io, "out", .default_dir);
    const source = try temporary.realPathFileAlloc(t.io, "seed.tar", a);
    const destination = try temporary.realPathFileAlloc(t.io, "out", a);
    return .{ .source = source, .destination = destination };
}

test "native tar preserves executable files and safe leading parent symlinks" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(t.io, "seed.tar", .{});
    try entry(file, "donor/tool", '0', "", "hello", 0o755);
    try entry(file, "nested/tool", '2', "../donor/tool", "", 0o777);
    const end: [1024]u8 = @splat(0);
    try file.writeStreamingAll(t.io, &end);
    file.close(t.io);
    const p = try paths(temporary.dir, t.allocator);
    defer t.allocator.free(p.source);
    defer t.allocator.free(p.destination);
    try archive.extract(t.io, p.source, p.destination);
    const content = try temporary.dir.readFileAlloc(t.io, "out/nested/tool", t.allocator, .limited(16));
    defer t.allocator.free(content);
    try t.expectEqualStrings("hello", content);
    const stat = try temporary.dir.statFile(t.io, "out/donor/tool", .{});
    try t.expect((stat.permissions.toMode() & 0o111) == 0o111);
}

test "native tar rejects escaping and symlink-dependent parent targets" {
    for ([_][]const u8{ "../../outside", "/outside", "d/../outside" }) |target| {
        var temporary = t.tmpDir(.{});
        defer temporary.cleanup();
        const file = try temporary.dir.createFile(t.io, "seed.tar", .{});
        try entry(file, "nested/link", '2', target, "", 0o777);
        const end: [1024]u8 = @splat(0);
        try file.writeStreamingAll(t.io, &end);
        file.close(t.io);
        const p = try paths(temporary.dir, t.allocator);
        defer t.allocator.free(p.source);
        defer t.allocator.free(p.destination);
        try t.expectError(error.UnsafeSeedArchive, archive.extract(t.io, p.source, p.destination));
    }
}

test "native tar rejects traversal names and symlink parents" {
    for ([_][]const u8{ "../outside", "/outside", "alias/../outside", "alias//outside", "./alias/child" }) |name| {
        var temporary = t.tmpDir(.{});
        defer temporary.cleanup();
        const file = try temporary.dir.createFile(t.io, "seed.tar", .{});
        try entry(file, name, '0', "", "bad", 0o644);
        const end: [1024]u8 = @splat(0);
        try file.writeStreamingAll(t.io, &end);
        file.close(t.io);
        const p = try paths(temporary.dir, t.allocator);
        defer t.allocator.free(p.source);
        defer t.allocator.free(p.destination);
        try t.expectError(error.UnsafeSeedArchive, archive.extract(t.io, p.source, p.destination));
    }
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(t.io, "seed.tar", .{});
    try entry(file, "donor/file", '0', "", "ok", 0o644);
    try entry(file, "alias", '2', "donor", "", 0o777);
    try entry(file, "alias/child", '2', "../donor/file", "", 0o777);
    const end: [1024]u8 = @splat(0);
    try file.writeStreamingAll(t.io, &end);
    file.close(t.io);
    const p = try paths(temporary.dir, t.allocator);
    defer t.allocator.free(p.source);
    defer t.allocator.free(p.destination);
    try t.expectError(error.UnsafeSeedArchive, archive.extract(t.io, p.source, p.destination));
}

test "tree identity excludes cache components and preserves ordinary and linked files" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(t.io, "source/__pycache__");
    try temporary.dir.writeFile(t.io, .{ .sub_path = "source/__pycache__/ignored", .data = "excluded" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "source/ignored.pyc", .data = "excluded" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "source/contains__pycache__text.my", .data = "kept" });
    try temporary.dir.symLink(t.io, "contains__pycache__text.my", "source/linked.my", .{});
    try temporary.dir.symLink(t.io, "__pycache__", "source/linked-directory", .{ .is_directory = true });
    const path = try temporary.dir.realPathFileAlloc(t.io, "source", t.allocator);
    defer t.allocator.free(path);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const identity = try files.tree(arena.allocator(), t.io, path);
    try t.expectEqual(@as(usize, 2), identity.object.count());
    try t.expectEqualStrings(&files.textDigest("kept"), identity.object.get("contains__pycache__text.my").?.string);
    try t.expectEqualStrings(identity.object.get("contains__pycache__text.my").?.string, identity.object.get("linked.my").?.string);
}

test "CPU metadata streams procfs despite its zero stat size" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const stat = try std.Io.Dir.cwd().statFile(t.io, "/proc/cpuinfo", .{});
    try t.expectEqual(@as(u64, 0), stat.size);
    const record = try files.firstBlock(t.allocator, t.io, "/proc/cpuinfo");
    defer t.allocator.free(record);
    try t.expect(record.len > 0);
    try t.expect(std.mem.indexOfScalar(u8, record, ':') != null);
    try t.expect(std.mem.indexOf(u8, record, "\n\n") == null);
}

test "CPU metadata first block ends at separator and rejects its byte ceiling" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "cpu", .data = "model: first\nflags: a b\n\nmodel: second\n" });
    const path = try temporary.dir.realPathFileAlloc(t.io, "cpu", t.allocator);
    defer t.allocator.free(path);
    const record = try files.firstBlock(t.allocator, t.io, path);
    defer t.allocator.free(record);
    try t.expectEqualStrings("model: first\nflags: a b", record);
    const ceiling: [65536]u8 = @splat('x');
    try temporary.dir.writeFile(t.io, .{ .sub_path = "cpu", .data = &ceiling });
    try t.expectError(error.CpuMetadataTooLarge, files.firstBlock(t.allocator, t.io, path));
    try temporary.dir.writeFile(t.io, .{ .sub_path = "cpu", .data = ceiling[0..65535] });
    const boundary = try files.firstBlock(t.allocator, t.io, path);
    defer t.allocator.free(boundary);
    try t.expectEqual(@as(usize, 65535), boundary.len);
}
