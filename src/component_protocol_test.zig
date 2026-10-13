//! Native component boundary qualification: malformed frames and artifact failures.
//! Exercises bounded launches, cleanup, shadow parity, and host-only name mapping.
const std = @import("std");
const wire = @import("component_protocol.zig");
const adapter = @import("component_adapter.zig");
const typed = @import("typed.zig");
const id: typed.FunctionId = @fromBackingInt(@intCast(0));
// spec-case: SELFHOST-COMPONENT-1
test "component frames reject truncation, stale identity, trailing bytes and foreign test IDs" {
    const a = std.testing.allocator;
    const request = try wire.request(a, &.{&.{}}, &.{id}, 42);
    defer a.free(request.bytes);
    var bytes: [80]u8 = @splat(0);
    std.mem.writeInt(u32, bytes[64..68], 1, .little);
    std.mem.writeInt(u32, bytes[68..72], 1, .little);
    std.mem.writeInt(u32, bytes[72..76], 0, .little);
    std.mem.writeInt(u32, bytes[76..80], 0, .little);
    wire.header(&bytes, 1, request.identity);
    var answer = try wire.reply(a, &bytes, request.identity, &.{"test"}, &.{id});
    defer answer.deinit();
    try std.testing.expectEqual(@as(usize, 1), answer.direct[0].len);
    try std.testing.expectError(error.ComponentProtocol, wire.reply(a, bytes[0..79], request.identity, &.{"test"}, &.{id}));
    bytes[24] ^= 1;
    try std.testing.expectError(error.ComponentProtocol, wire.reply(a, &bytes, request.identity, &.{"test"}, &.{id}));
    bytes[24] ^= 1;
    try std.testing.expectError(error.ComponentProtocol, wire.reply(a, &bytes, request.identity, &.{"test"}, &.{}));
    std.mem.writeInt(u32, bytes[72..76], 1, .little);
    try std.testing.expectError(error.ComponentProtocol, wire.reply(a, &bytes, request.identity, &.{"test"}, &.{id}));
}
// spec-case: SELFHOST-COMPONENT-1
test "component launch boundary is explicit and reports missing manifests" {
    const a = std.testing.allocator;
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    const selected = adapter.configured(std.testing.io, &environ);
    try std.testing.expect(selected == .component);
    try environ.put("MYLANG_TEST_INDEX_MODE", "invalid");
    try std.testing.expect(adapter.configured(std.testing.io, &environ) == .invalid);
    try std.testing.expectError(error.ComponentMissing, adapter.artifact(a, std.testing.io, "/no-such-component-directory"));
    const runtime: adapter.Runtime = .{ .io = std.testing.io, .environ = &environ, .component_dir = "/no-such-component-directory" };
    try std.testing.expectError(error.ComponentMissing, (adapter.Adapter{ .component = runtime }).buildNamed(a, &.{"test"}, &.{&.{}}, &.{id}));
}

fn fixture(a: std.mem.Allocator, dir: std.Io.Dir, script: []const u8) !void {
    const io = std.testing.io;
    try dir.writeFile(io, .{ .sub_path = "test-index", .data = script });
    const file = try dir.openFile(io, "test-index", .{});
    defer file.close(io);
    try file.setPermissions(io, .fromMode(0o700));
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(script, &digest, .{});
    const manifest = try std.fmt.allocPrint(a, "{{\"format\":1,\"component\":\"test-index\",\"protocol\":1,\"schema\":1,\"artifact\":\"test-index\",\"sha256\":\"{s}\"}}", .{std.fmt.bytesToHex(digest, .lower)});
    defer a.free(manifest);
    try dir.writeFile(io, .{ .sub_path = "test-index.json", .data = manifest });
}
// spec-case: SELFHOST-COMPONENT-1
test "component verifies artifact and bounds child failures and deadlines" {
    const a = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [4096]u8 = undefined;
    const directory = path_buffer[0..try temporary.dir.realPath(std.testing.io, &path_buffer)];
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("TMPDIR", directory);
    var runtime: adapter.Runtime = .{ .io = std.testing.io, .environ = &environ, .component_dir = directory, .timeout_ms = 10 };
    try fixture(a, temporary.dir, "#!/bin/sh\nexit 7\n");
    try std.testing.expectError(error.ComponentFailed, (adapter.Adapter{ .component = runtime }).buildNamed(a, &.{"test"}, &.{&.{}}, &.{id}));
    try fixture(a, temporary.dir, "#!/bin/sh\n/bin/sleep 1\n");
    try std.testing.expectError(error.ComponentTimeout, (adapter.Adapter{ .component = runtime }).buildNamed(a, &.{"test"}, &.{&.{}}, &.{id}));
    runtime.timeout_ms = 1000;
    try fixture(a, temporary.dir, "#!/bin/sh\nprintf invalid\n");
    try std.testing.expectError(error.ComponentProtocol, (adapter.Adapter{ .component = runtime }).buildNamed(a, &.{"test"}, &.{&.{}}, &.{id}));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "test-index", .data = "changed" });
    try std.testing.expectError(error.ComponentDigest, adapter.artifact(a, std.testing.io, directory));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "test-index.json", .data = "{\"format\":2}" });
    try std.testing.expectError(error.ComponentManifest, adapter.artifact(a, std.testing.io, directory));
}

// spec-case: SELFHOST-COMPONENT-1
test "component rejects every malformed header field and oversized list count" {
    const a = std.testing.allocator;
    const request = try wire.request(a, &.{&.{}}, &.{id}, 42);
    defer a.free(request.bytes);
    var bytes: [80]u8 = @splat(0);
    std.mem.writeInt(u32, bytes[64..68], 1, .little);
    std.mem.writeInt(u32, bytes[68..72], 1, .little);
    wire.header(&bytes, 1, request.identity);
    for ([_]usize{ 0, 8, 12, 16, 20, 24, 32, 63 }) |offset| {
        bytes[offset] ^= 1;
        try std.testing.expectError(error.ComponentProtocol, wire.reply(a, &bytes, request.identity, &.{"test"}, &.{id}));
        bytes[offset] ^= 1;
    }

    std.mem.writeInt(u32, bytes[68..72], std.math.maxInt(u32), .little);
    try std.testing.expectError(error.ComponentProtocol, wire.reply(a, &bytes, request.identity, &.{"test"}, &.{id}));
    std.mem.writeInt(u32, bytes[68..72], 1, .little);
    var trailing: [84]u8 = @splat(0);
    @memcpy(trailing[0..80], &bytes);
    wire.header(&trailing, 1, request.identity);
    try std.testing.expectError(error.ComponentProtocol, wire.reply(a, &trailing, request.identity, &.{"test"}, &.{id}));
}

fn concurrentCall(a: std.mem.Allocator, runtime: adapter.Runtime, failure: *?adapter.Error) void {
    var answer = (adapter.Adapter{ .component = runtime }).buildNamed(a, &.{}, &.{}, &.{}) catch |err| {
        failure.* = err;
        return;
    };
    answer.deinit();
}
// spec-case: SELFHOST-COMPONENT-1
test "component private request directories are concurrent and cleaned; shadow compares exact answers" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [4096]u8 = undefined;
    const directory = path_buffer[0..try temporary.dir.realPath(io, &path_buffer)];
    const log = try std.fs.path.join(a, &.{ directory, "requests.log" });
    defer a.free(log);
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("TMPDIR", directory);
    try environ.put("COMPONENT_TEST_LOG", log);
    const script =
        \\#!/usr/bin/python3
        \\import os,sys,struct
        \\p=sys.argv[2]
        \\b=open(p,'rb').read()
        \\with open(os.environ['COMPONENT_TEST_LOG'],'a') as f:f.write(p+'\n')
        \\n=struct.unpack_from('<I',b,64)[0]
        \\payload=struct.pack('<I',n)+b'\0'*(n*8)
        \\sys.stdout.buffer.write(b[:16]+struct.pack('<II',1,len(payload))+b[24:64]+payload)
        \\
    ;
    try fixture(a, temporary.dir, script);
    const runtime: adapter.Runtime = .{ .io = io, .environ = &environ, .component_dir = directory };
    var failures: [2]?adapter.Error = .{ null, null };
    const one = try std.Thread.spawn(.{}, concurrentCall, .{ std.heap.page_allocator, runtime, &failures[0] });
    const two = try std.Thread.spawn(.{}, concurrentCall, .{ std.heap.page_allocator, runtime, &failures[1] });
    one.join();
    two.join();
    try std.testing.expect(failures[0] == null and failures[1] == null);
    const paths = try temporary.dir.readFileAlloc(io, "requests.log", a, .limited(8192));
    defer a.free(paths);
    var lines = std.mem.tokenizeScalar(u8, paths, '\n');
    const first = lines.next().?;
    const second = lines.next().?;
    try std.testing.expect(!std.mem.eql(u8, first, second));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, std.fs.path.dirname(first).?, .{}));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, std.fs.path.dirname(second).?, .{}));
    var empty = try (adapter.Adapter{ .shadow = runtime }).buildNamed(a, &.{}, &.{}, &.{});
    empty.deinit();
    try std.testing.expectError(error.ComponentShadowMismatch, (adapter.Adapter{ .shadow = runtime }).buildNamed(a, &.{"test"}, &.{&.{}}, &.{id}));
}

// spec-case: SELFHOST-COMPONENT-1
test "component shared empty golden frame preserves high identity bytes" {
    const a = std.testing.allocator;
    const identity: wire.Identity = .{ .request_id = std.math.maxInt(u64), .snapshot = @splat(255) };
    const request = try wire.request(a, &.{}, &.{}, identity.request_id);
    defer a.free(request.bytes);
    wire.header(request.bytes, 0, identity);
    const golden_request = "SLKIDX01\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x08\x00\x00\x00" ++ @as([40]u8, @splat(255)) ++ @as([8]u8, @splat(0));
    try std.testing.expectEqualSlices(u8, golden_request, request.bytes);
    const golden_reply = "SLKIDX01\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x04\x00\x00\x00" ++ @as([40]u8, @splat(255)) ++ @as([4]u8, @splat(0));
    var reply_bytes: [68]u8 = @splat(0);
    wire.header(&reply_bytes, 1, identity);
    try std.testing.expectEqualSlices(u8, golden_reply, &reply_bytes);
    var answer = try wire.reply(a, golden_reply, identity, &.{}, &.{});
    defer answer.deinit();
    try std.testing.expectEqual(@as(usize, 0), answer.direct.len);
}

// spec-case: SELFHOST-COMPONENT-1
test "component names remain host-only Unicode and embedded NUL byte slices" {
    const a = std.testing.allocator;
    const request = try wire.request(a, &.{&.{}}, &.{id}, 7);
    defer a.free(request.bytes);
    const name = "模块::test_é\x00尾";
    try std.testing.expect(std.mem.indexOf(u8, request.bytes, name) == null);
    var bytes: [84]u8 = @splat(0);
    wire.header(&bytes, 1, request.identity);
    std.mem.writeInt(u32, bytes[64..68], 1, .little);
    std.mem.writeInt(u32, bytes[68..72], 1, .little);
    std.mem.writeInt(u32, bytes[76..80], 1, .little);
    var answer = try wire.reply(a, &bytes, request.identity, &.{name}, &.{id});
    defer answer.deinit();
    try std.testing.expectEqualStrings(name, answer.direct[0][0]);
    try std.testing.expectEqualStrings(name, answer.reached[0][0]);
    try std.testing.expect(answer.direct[0][0].ptr == name.ptr);
}

// spec-case: SELFHOST-COMPONENT-1
test "component rejects every reply truncation" {
    const a = std.testing.allocator;
    const identity: wire.Identity = .{ .request_id = 1, .snapshot = @splat(0) };
    var bytes: [80]u8 = @splat(0);
    wire.header(&bytes, 1, identity);
    std.mem.writeInt(u32, bytes[64..68], 1, .little);
    std.mem.writeInt(u32, bytes[68..72], 1, .little);
    for (0..bytes.len) |length| {
        try std.testing.expectError(error.ComponentProtocol, wire.reply(a, bytes[0..length], identity, &.{"test"}, &.{id}));
    }
}

// spec-case: SELFHOST-COMPONENT-1
test "component invalid mode and unusable temporary root report explicit errors" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var buffer: [4096]u8 = undefined;
    const directory = buffer[0..try temporary.dir.realPath(io, &buffer)];
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("MYLANG_TEST_INDEX_MODE", "invalid");
    try std.testing.expectError(error.ComponentMode, adapter.configured(io, &environ).buildNamed(a, &.{}, &.{}, &.{}));
    try fixture(a, temporary.dir, "#!/bin/sh\nexit 0\n");
    const missing = try std.fs.path.join(a, &.{ directory, "missing" });
    defer a.free(missing);
    try environ.put("TMPDIR", missing);
    const runtime: adapter.Runtime = .{ .io = io, .environ = &environ, .component_dir = directory };
    try std.testing.expectError(error.ComponentIo, (adapter.Adapter{ .component = runtime }).buildNamed(a, &.{}, &.{}, &.{}));
}

// spec-case: SELFHOST-COMPONENT-1
test "component runChild deadline includes wait after both output streams close" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var buffer: [4096]u8 = undefined;
    const directory = buffer[0..try temporary.dir.realPath(io, &buffer)];
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("TMPDIR", directory);
    const pid_path = try std.fs.path.join(a, &.{ directory, "child.pid" });
    defer a.free(pid_path);
    try environ.put("COMPONENT_PID_PATH", pid_path);
    try fixture(a, temporary.dir, "#!/bin/sh\ntrap '' TERM\nprintf '%s' $$ > \"$COMPONENT_PID_PATH\"\nexec 1>&- 2>&-\nexec /bin/sleep 2\n");
    const runtime: adapter.Runtime = .{ .io = io, .environ = &environ, .component_dir = directory, .timeout_ms = 100 };
    const start = std.Io.Clock.awake.now(io);
    try std.testing.expectError(error.ComponentTimeout, (adapter.Adapter{ .component = runtime }).buildNamed(a, &.{}, &.{}, &.{}));
    try std.testing.expect(start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds < std.time.ns_per_s);
    const pid_bytes = try temporary.dir.readFileAlloc(io, "child.pid", a, .limited(128));
    defer a.free(pid_bytes);
    const pid = try std.fmt.parseInt(std.os.linux.pid_t, pid_bytes, 10);
    try std.testing.expectEqual(std.os.linux.E.SRCH, std.os.linux.errno(std.os.linux.kill(pid, @fromBackingInt(0))));
}
