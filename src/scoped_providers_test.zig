//! Scope boundaries are checked before external effects; stores own cleanup order.
const std = @import("std");
const t = std.testing;
const scoped = @import("compiler.zig").scoped_providers;
const resources = @import("external_resources.zig");
// spec: SCOPED-PROVIDERS-1
test "scoped provider paths and acquisition permissions reject before effects" {
    for ([_][]const u8{ "r:../escape", "r:/absolute", "r:a/../b", "r:a//b", "r:./a", "r:a\\b", "r:a\x00b", "r:", "z:a" }) |request|
        try t.expectError(error.Denied, scoped.fileRequest(request, resources.all_permissions));
    try t.expectError(error.Denied, scoped.fileRequest("w:a", resources.permissionBit(.read)));
    try t.expectError(error.Denied, scoped.fileRequest("c:a", resources.permissionBit(.read)));
    try t.expectError(error.Denied, scoped.fileRequest("t:a", resources.permissionBit(.read)));
    try t.expectError(error.Denied, scoped.fileRequest("k:a", resources.permissionBit(.read)));
    try t.expectError(error.Denied, scoped.fileRequest("x:a", resources.permissionBit(.read)));
    try t.expect(scoped.writingMode('k') and scoped.writingMode('x') and !scoped.writingMode('m'));
    try t.expectEqualStrings("nested/a", (try scoped.fileRequest("r:nested/a", resources.permissionBit(.read))).path);
    const allowed = [_]scoped.Endpoint{.{ .name = "127.0.0.1:9000", .address = try std.Io.net.IpAddress.parseLiteral("127.0.0.1:9000") }};
    _ = try scoped.endpoint(&allowed, "127.0.0.1:9000");
    try t.expectError(error.Denied, scoped.endpoint(&allowed, "127.0.0.1:9001"));
    try t.expectError(error.Denied, scoped.endpoint(&allowed, "localhost:9000"));
}
// spec: SCOPED-PROVIDERS-2
test "scoped filesystem handles partial IO cleanup exclusive creation and symlink denial" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var context: scoped.Context = .{ .allocator = t.allocator, .io = t.io, .roots = &.{.{ .dir = temporary.dir, .writable = true }} };
    defer context.deinit();
    var store = try resources.Store.init(t.allocator, .filesystem, context.filesystem(), 8);
    defer store.deinit();
    const authority = try store.grant();
    const readonly = try store.restrict(authority, resources.permissionBit(.read));
    try t.expectError(error.Denied, store.acquire(readonly, "c:data"));
    const created = try store.acquire(authority, "c:data");
    try t.expectEqual(@as(usize, 3), try store.write(created, "abc"));
    try store.complete(created);
    try t.expectError(error.Failed, store.acquire(authority, "c:data"));
    const file = try store.acquire(readonly, "r:data");
    var bytes: [2]u8 = undefined;
    const first = try store.read(file, &bytes);
    try t.expectEqual(@as(usize, 2), first.length);
    try t.expectEqualStrings("ab", &bytes);
    try t.expectError(error.Denied, store.write(file, "x"));
    try t.expectEqual(@as(usize, 1), (try store.read(file, &bytes)).length);
    try t.expect((try store.read(file, &bytes)).eof);
    try store.release(file);
    try temporary.dir.symLink(t.io, "data", "link", .{});
    try t.expectError(error.Denied, store.acquire(authority, "t:link"));
    const retained = try store.acquire(authority, "r:data");
    try t.expectEqual(@as(usize, 2), (try store.read(retained, &bytes)).length);
    try t.expectEqualStrings("ab", &bytes);
}
// spec: SCOPED-PROVIDERS-3
test "scoped TCP adapter connects only allowed endpoint and transfers bytes" {
    const address = try std.Io.net.IpAddress.parseLiteral("127.0.0.1:0");
    var server = try address.listen(t.io, .{});
    defer server.deinit(t.io);
    const name = try std.fmt.allocPrint(t.allocator, "{f}", .{server.socket.address});
    defer t.allocator.free(name);
    const endpoints = [_]scoped.Endpoint{.{ .name = name, .address = server.socket.address }};
    var context: scoped.Context = .{ .allocator = t.allocator, .io = t.io, .endpoints = &endpoints };
    defer context.deinit();
    var store = try resources.Store.init(t.allocator, .network, context.network(), 4);
    defer store.deinit();
    const authority = try store.grant();
    try t.expectError(error.Denied, store.acquire(authority, "127.0.0.1:1"));
    try t.expectEqual(@as(usize, 0), context.handles.items.len);
    const connection = try store.acquire(authority, name);
    const peer = try server.accept(t.io);
    defer peer.close(t.io);
    try t.expectEqual(@as(usize, 3), try store.write(connection, "abc"));
    var bytes: [3]u8 = undefined;
    var slices = [_][]u8{&bytes};
    try t.expectEqual(@as(usize, 3), try peer.read(t.io, &slices));
    try t.expectEqualStrings("abc", &bytes);
    var writer = peer.writer(t.io, &.{});
    try writer.interface.writeAll("ok");
    const got = try store.read(connection, &bytes);
    try t.expectEqual(@as(usize, 2), got.length);
    try t.expectEqualStrings("ok", bytes[0..got.length]);
    try store.complete(connection);
    try t.expectEqual(@as(usize, 0), store.statistics.live);
}
// spec: SCOPED-DIRECTORY-1
test "scoped metadata and listing snapshots preserve read authority and bounded publication" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data", .data = "abc" });
    try temporary.dir.createDir(t.io, "nested", .default_dir);
    try temporary.dir.symLink(t.io, "data", "link", .{});
    var context: scoped.Context = .{ .allocator = t.allocator, .io = t.io, .roots = &.{.{ .dir = temporary.dir, .writable = true }} };
    defer context.deinit();
    var store = try resources.Store.init(t.allocator, .filesystem, context.filesystem(), 8);
    defer store.deinit();
    const authority = try store.grant();
    const read_only = try store.restrict(authority, resources.permissionBit(.read));
    const write_only = try store.restrict(authority, resources.permissionBit(.write));
    try t.expectError(error.Denied, store.acquire(write_only, "m:data"));
    try t.expectError(error.Denied, store.acquire(write_only, "l:"));
    const metadata = try store.acquire(read_only, "m:data");
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data", .data = "changed after acquisition" });
    var bytes: [128]u8 = undefined;
    const first = try store.read(metadata, bytes[0..4]);
    try t.expectEqual(@as(usize, 4), first.length);
    try t.expect(!first.eof);
    _ = try store.read(metadata, bytes[4..10]);
    try t.expectEqualSlices(u8, &.{ 1, 1, 3, 0, 0, 0, 0, 0, 0, 0 }, bytes[0..10]);
    try t.expect(!(try store.read(metadata, bytes[0..0])).eof);
    try store.release(metadata);
    const list = try store.acquire(read_only, "l:");
    try temporary.dir.writeFile(t.io, .{ .sub_path = "later", .data = "new" });
    const got = try store.read(list, &bytes);
    try t.expect(got.eof);
    try t.expect(std.mem.indexOf(u8, bytes[0..got.length], "later") == null);
    try t.expectEqual(@as(u8, 1), bytes[0]);
    try t.expect(std.mem.indexOf(u8, bytes[0..got.length], "data") != null);
    try t.expect(std.mem.indexOf(u8, bytes[0..got.length], "nested") != null);
    try t.expect(std.mem.indexOf(u8, bytes[0..got.length], "link") != null);
    try t.expectError(error.Denied, store.write(list, "x"));
    try store.release(list);
    try t.expectError(error.Denied, store.acquire(authority, "l:link"));
    try t.expectError(error.Denied, store.acquire(authority, "m:../data"));
    context.snapshot_limits.entries = 1;
    try t.expectError(error.Denied, store.acquire(authority, "l:"));
    try t.expectEqual(@as(usize, 0), store.statistics.live);
}
// spec: SCOPED-DIRECTORY-2
test "scoped directory create allocation failures release unpublished snapshot bytes" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data", .data = "abc" });
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), snapshotFailure, .{temporary.dir});
}
fn snapshotFailure(allocator: std.mem.Allocator, directory: std.Io.Dir) !void {
    const snapshot = try @import("scoped_directory.zig").create(allocator, t.io, directory, "data", 'm', .{});
    defer snapshot.deinit();
    const listing = try @import("scoped_directory.zig").create(allocator, t.io, directory, "", 'l', .{});
    defer listing.deinit();
}
test "scoped directory snapshots retain the 64KiB transfer cap with larger configured snapshots" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    for (0..260) |index| {
        var name: [255]u8 = undefined;
        @memset(&name, 'x');
        _ = try std.fmt.bufPrint(name[250..], "{d:0>5}", .{index});
        try temporary.dir.writeFile(t.io, .{ .sub_path = &name, .data = "" });
    }
    var context: scoped.Context = .{ .allocator = t.allocator, .io = t.io, .roots = &.{.{ .dir = temporary.dir, .writable = true }}, .snapshot_limits = .{ .bytes = 80 * 1024, .entries = 260 } };
    defer context.deinit();
    var store = try resources.Store.init(t.allocator, .filesystem, context.filesystem(), 1);
    defer store.deinit();
    const list = try store.acquire(try store.grant(), "l:");
    const bytes = try t.allocator.alloc(u8, 80 * 1024);
    defer t.allocator.free(bytes);
    const first = try store.read(list, bytes);
    try t.expectEqual(@as(usize, 64 * 1024), first.length);
    try t.expect(!first.eof);
    const last = try store.read(list, bytes);
    try t.expectEqual(@as(usize, 260 * 258 + 1 - 64 * 1024), last.length);
    try t.expect(last.eof);
    try store.release(list);
}

// spec: CAPABILITY-4
test "multiple directory roots resolve in order and only writable roots accept changes" {
    var first = t.tmpDir(.{});
    defer first.cleanup();
    var second = t.tmpDir(.{});
    defer second.cleanup();
    try second.dir.writeFile(t.io, .{ .sub_path = "only-second", .data = "second" });
    var context: scoped.Context = .{ .allocator = t.allocator, .io = t.io, .roots = &.{
        .{ .dir = first.dir, .writable = false },
        .{ .dir = second.dir, .writable = true },
    } };
    defer context.deinit();
    var store = try resources.Store.init(t.allocator, .filesystem, context.filesystem(), 8);
    defer store.deinit();
    const authority = try store.grant();
    // The first root has no such file, so the search falls through to the second.
    const found = try store.acquire(authority, "r:only-second");
    var bytes: [6]u8 = undefined;
    try t.expectEqual(@as(usize, 6), (try store.read(found, &bytes)).length);
    try t.expectEqualStrings("second", &bytes);
    try store.complete(found);
    try t.expectError(error.Failed, store.acquire(authority, "r:absent"));
    // Creation skips the read-only root entirely and lands in the writable one.
    const created = try store.acquire(authority, "c:made");
    try store.complete(created);
    try t.expectError(error.FileNotFound, first.dir.access(t.io, "made", .{}));
    try second.dir.access(t.io, "made", .{});
    const directory = try store.acquire(authority, "k:folder");
    try store.complete(directory);
    try second.dir.access(t.io, "folder", .{});
    try t.expectError(error.Failed, store.acquire(authority, "k:folder"));
    const removed = try store.acquire(authority, "x:made");
    try store.complete(removed);
    try t.expectError(error.FileNotFound, second.dir.access(t.io, "made", .{}));
    const dropped = try store.acquire(authority, "x:folder");
    try store.complete(dropped);
    try t.expectError(error.Failed, store.acquire(authority, "x:folder"));
}

test "a context without any granted root reports the filesystem as unavailable" {
    var context: scoped.Context = .{ .allocator = t.allocator, .io = t.io };
    defer context.deinit();
    var store = try resources.Store.init(t.allocator, .filesystem, context.filesystem(), 8);
    defer store.deinit();
    try t.expectError(error.Unavailable, store.acquire(try store.grant(), "r:any"));
}

// spec-case: CAPABILITY-4
test "a direct root applies the whole path, allows traversal and keeps write authority" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "notes.txt", .data = "alpha\n" });
    try temporary.dir.createDir(t.io, "nested", .default_dir);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "nested/deep.txt", .data = "beta\n" });
    var context: scoped.Context = .{ .allocator = t.allocator, .io = t.io, .roots = &.{.{ .dir = temporary.dir, .writable = true, .direct = true }} };
    defer context.deinit();
    var store = try resources.Store.init(t.allocator, .filesystem, context.filesystem(), 8);
    defer store.deinit();
    const authority = try store.grant();
    // A scoped root would refuse `.` and `..`; a direct root resolves them, and a
    // read-only capability still refuses every writing mode.
    const readonly = try store.restrict(authority, resources.permissionBit(.read) | resources.permissionBit(.complete));
    for ([_]struct { request: []const u8, allowed: bool }{
        .{ .request = "r:./notes.txt", .allowed = true },
        .{ .request = "r:nested/../notes.txt", .allowed = true },
        .{ .request = "r:nested/deep.txt", .allowed = true },
        .{ .request = "c:made.txt", .allowed = false },
        .{ .request = "t:notes.txt", .allowed = false },
        .{ .request = "k:folder", .allowed = false },
        .{ .request = "x:notes.txt", .allowed = false },
        .{ .request = "a:notes.txt", .allowed = false },
    }) |case| {
        if (!case.allowed) {
            try t.expectError(error.Denied, store.acquire(readonly, case.request));
            continue;
        }
        const owner = try store.acquire(readonly, case.request);
        try store.complete(owner);
    }
    try t.expectError(error.Failed, store.acquire(authority, "r:absent.txt"));
    try t.expectError(error.Denied, store.acquire(authority, "q:notes.txt"));
    try t.expectError(error.FileNotFound, temporary.dir.access(t.io, "made.txt", .{}));
    const created = try store.acquire(authority, "c:made.txt");
    try store.complete(created);
    try temporary.dir.access(t.io, "made.txt", .{});
}

test "a scoped request rejects the paths a direct request accepts" {
    for ([_][]const u8{ "r:./a", "r:../a", "r:a/../b", "r:" }) |request| {
        try t.expectError(error.Denied, scoped.fileRequest(request, resources.all_permissions));
        // The same request decodes cleanly when only the mode is checked.
        _ = try scoped.openRequest(request, resources.all_permissions);
    }
    try t.expectError(error.Denied, scoped.openRequest("q:a", resources.all_permissions));
    try scoped.scopedSpec(.{ .mode = 'l', .path = "" });
    try t.expectError(error.Denied, scoped.scopedSpec(.{ .mode = 'r', .path = "" }));
}
