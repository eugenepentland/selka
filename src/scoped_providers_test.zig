//! Scope boundaries are checked before external effects; stores own cleanup order.
const std = @import("std");
const t = std.testing;
const scoped = @import("compiler.zig").scoped_providers;
const resources = @import("external_resources.zig");
// spec: SCOPED-PROVIDERS-1
test "scoped provider paths and acquisition permissions reject before effects" {
    for ([_][]const u8{ "r:../escape", "r:/absolute", "r:a/../b", "r:a//b", "r:./a", "r:a\\b", "r:a\x00b", "r:", "x:a" }) |request|
        try t.expectError(error.Denied, scoped.fileRequest(request, resources.all_permissions));
    try t.expectError(error.Denied, scoped.fileRequest("w:a", resources.permissionBit(.read)));
    try t.expectError(error.Denied, scoped.fileRequest("c:a", resources.permissionBit(.read)));
    try t.expectError(error.Denied, scoped.fileRequest("t:a", resources.permissionBit(.read)));
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
    var context: scoped.Context = .{ .allocator = t.allocator, .io = t.io, .directory = temporary.dir };
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
