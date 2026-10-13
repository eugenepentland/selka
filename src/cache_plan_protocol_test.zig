//! Qualification of the complete Core planner contract and bounded reply decoder.
const std = @import("std");
const wire = @import("cache_plan_protocol.zig");
const contract = @import("cache_plan_contract.zig");
const adapter = @import("cache_plan_adapter.zig");
const component_name = "cache-plan";
comptime {
    _ = @import("cache_plan_protocol_v2_test.zig");
}
// spec: SELFHOST-CACHE-PLAN-1
test "planner reach preserves equal digests, duplicate roots, cycles and batch isolation" {
    const a = std.testing.allocator;
    const graph: wire.Graph = .{ .digests = &.{ @splat(9), @splat(3), @splat(3), @splat(1) }, .callees = &.{ &.{ 1, 2 }, &.{0}, &.{3}, &.{} } };
    var result = try wire.reference(a, graph, &.{ &.{ 0, 0 }, &.{ 0, 2 }, &.{} });
    defer result.deinit();
    try std.testing.expectEqualSlices(u32, &.{ 3, 1, 2 }, result.batches[0]);
    try std.testing.expectEqualSlices(u32, &.{ 3, 1 }, result.batches[1]);
    try std.testing.expectEqual(@as(usize, 0), result.batches[2].len);
    const request = try wire.request(a, graph, &.{&.{ 0, 0 }}, 42);
    defer a.free(request.bytes);
    try std.testing.expectEqualSlices(u8, "SLKCP001", request.bytes[0..8]);
    var bytes: [84]u8 = @splat(0);
    wire.header(&bytes, 1, request.identity);
    std.mem.writeInt(u32, bytes[64..68], 1, .little);
    std.mem.writeInt(u32, bytes[68..72], 3, .little);
    std.mem.writeInt(u32, bytes[72..76], 3, .little);
    std.mem.writeInt(u32, bytes[76..80], 1, .little);
    std.mem.writeInt(u32, bytes[80..84], 2, .little);
    var decoded = try wire.reply(a, &bytes, request.identity, graph, &.{&.{ 0, 0 }});
    defer decoded.deinit();
    try std.testing.expectEqualSlices(u32, result.batches[0], decoded.batches[0]);
    try rejectTruncations(a, &bytes, request.identity, graph);
    try rejectHeaders(a, &bytes, request.identity, graph);
    try rejectIds(a, &bytes, request.identity, graph);
    std.mem.writeInt(u32, bytes[80..84], 2, .little);
    std.mem.writeInt(u32, bytes[76..80], 2, .little);
    std.mem.writeInt(u32, bytes[80..84], 1, .little);
    try std.testing.expectError(error.ComponentProtocol, wire.reply(a, &bytes, request.identity, graph, &.{&.{0}}));
}
// spec-case: SELFHOST-CACHE-PLAN-1
test "planner refuses malformed graphs and oversized declared output before allocation" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.ComponentProtocol, wire.reference(a, .{ .digests = &.{@splat(0)}, .callees = &.{} }, &.{}));
    try std.testing.expectError(error.ComponentProtocol, wire.reference(a, .{ .digests = &.{@splat(0)}, .callees = &.{&.{1}} }, &.{&.{0}}));
    try std.testing.expectError(error.ComponentProtocol, wire.reference(a, .{ .digests = &.{@splat(0)}, .callees = &.{&.{}} }, &.{&.{1}}));
    const identity: wire.Identity = .{ .request_id = 0, .snapshot = @splat(0) };
    var bytes: [72]u8 = @splat(0);
    wire.header(&bytes, 1, identity);
    std.mem.writeInt(u32, bytes[64..68], 1, .little);
    std.mem.writeInt(u32, bytes[68..72], std.math.maxInt(u32), .little);
    try std.testing.expectError(error.ComponentProtocol, wire.reply(a, &bytes, identity, .{ .digests = &.{@splat(0)}, .callees = &.{&.{}} }, &.{&.{0}}));
}
// spec: SELFHOST-CACHE-CONTRACT-1
test "disposable pure successes are supported and durable or effect policies explicitly refuse" {
    try (contract.Policy{}).validate();
    const unsupported = [_]contract.Policy{
        .{ .retention = .durable },
        .{ .commit = .durable_checkpoint },
        .{ .retry = .idempotent_effect },
        .{ .execution = .{ .run = "run", .step = "step" } },
        .{ .computation = .recorded_effect },
        .{ .computation = .measurement },
        .{ .success_only = false },
    };
    for (unsupported) |policy| try std.testing.expectError(error.UnsupportedCacheContract, policy.validate());
}
// spec-case: SELFHOST-CACHE-PLAN-1
test "planner eagerly binds explicit reference and fails closed for unavailable component or invalid mode" {
    const a = std.testing.allocator;
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("MYLANG_COMPONENT_DIR", "/no-such-cache-plan-component");
    try std.testing.expectError(error.ComponentMissing, adapter.bind(a, std.testing.io, &environ));
    try environ.put("MYLANG_CACHE_PLAN_MODE", "invalid");
    try std.testing.expectError(error.ComponentMode, adapter.bind(a, std.testing.io, &environ));
    try environ.put("MYLANG_CACHE_PLAN_MODE", "reference");
    var bound = try adapter.bind(a, std.testing.io, &environ);
    defer bound.deinit(a);
    try bound.validate(a);
    var result = try bound.batch(a, .{ .digests = &.{}, .callees = &.{} }, &.{});
    defer result.deinit();
}

// spec-case: SELFHOST-CACHE-PLAN-2
test "incremental component transport binds correlated v2 replies and rejects failed execution" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var buffer: [4096]u8 = undefined;
    const directory = buffer[0..try temporary.dir.realPath(io, &buffer)];
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("TMPDIR", directory);
    try environ.put("MYLANG_COMPONENT_DIR", directory);
    const script =
        \\#!/usr/bin/python3
        \\import sys,struct
        \\b=open(sys.argv[2],'rb').read()
        \\sys.stdout.buffer.write(b[:16]+struct.pack('<II',1,64)+b[24:64]+b'\0'*64)
        \\
    ;
    try fixture(a, temporary.dir, script);
    try environ.put("MYLANG_CACHE_PLAN_MODE", "shadow");
    var bound = try adapter.bind(a, io, &environ);
    defer bound.deinit(a);
    const input: adapter.incremental_protocol.Incremental = .{ .graph = .{ .digests = &.{}, .callees = &.{} }, .roots = &.{}, .topology = @splat(1), .changed = &.{}, .candidates = &.{} };
    var result = try bound.incremental(a, input);
    defer result.deinit();
    try std.testing.expectEqual(@as(u64, 1), result.transport.startups);
    try std.testing.expectEqual(@as(u64, 124), result.transport.request_bytes);
    try std.testing.expectEqual(@as(u64, 128), result.transport.reply_bytes);
    try fixture(a, temporary.dir, "#!/bin/sh\nexit 7\n");
    var failing = try adapter.bind(a, io, &environ);
    defer failing.deinit(a);
    try std.testing.expectError(error.ComponentFailed, failing.incremental(a, input));
}
fn fixture(a: std.mem.Allocator, dir: std.Io.Dir, script: []const u8) !void {
    const io = std.testing.io;
    try dir.writeFile(io, .{ .sub_path = component_name, .data = script });
    const file = try dir.openFile(io, component_name, .{});
    defer file.close(io);
    try file.setPermissions(io, .fromMode(0o700));
    var digest: wire.Digest = undefined;
    std.crypto.hash.sha2.Sha256.hash(script, &digest, .{});
    const manifest = try std.fmt.allocPrint(a, "{{\"format\":1,\"component\":\"cache-plan\",\"protocol\":2,\"schema\":2,\"artifact\":\"cache-plan\",\"sha256\":\"{s}\"}}", .{std.fmt.bytesToHex(digest, .lower)});
    defer a.free(manifest);
    try dir.writeFile(io, .{ .sub_path = "cache-plan.json", .data = manifest });
}
// spec-case: SELFHOST-CACHE-PLAN-2
test "planner retained snapshot supports borrowed bindings and rejects same-length replacement" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(io, ".", a);
    defer a.free(directory);
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("TMPDIR", directory);
    try environ.put("MYLANG_COMPONENT_DIR", directory);
    const script =
        \\#!/usr/bin/python3
        \\import sys,struct
        \\b=open(sys.argv[2],'rb').read()
        \\n=64 if b[:8]==b'SLKCP002' else 4
        \\sys.stdout.buffer.write(b[:16]+struct.pack('<II',1,n)+b[24:64]+b'\0'*n)
        \\# original
        \\
    ;
    try fixture(a, temporary.dir, script);
    var bound = try adapter.bind(a, io, &environ);
    defer bound.deinit(a);
    try std.testing.expectEqualStrings(script, bound.snapshot.?);
    const borrowed = bound;
    for (0..2) |_| {
        var legacy = try borrowed.batch(a, .{ .digests = &.{}, .callees = &.{} }, &.{});
        defer legacy.deinit();
        const input: adapter.incremental_protocol.Incremental = .{ .graph = .{ .digests = &.{}, .callees = &.{} }, .roots = &.{}, .topology = @splat(1), .changed = &.{}, .candidates = &.{} };
        var incremental = try borrowed.incremental(a, input);
        defer incremental.deinit();
    }
    const replacement = try a.dupe(u8, script);
    defer a.free(replacement);
    replacement[replacement.len - 2] = 'X';
    try temporary.dir.writeFile(io, .{ .sub_path = component_name, .data = replacement });
    try std.testing.expectEqualStrings(script, bound.snapshot.?);
    try std.testing.expectError(error.ComponentDigest, borrowed.batch(a, .{ .digests = &.{}, .callees = &.{} }, &.{}));
}

// spec-case: SELFHOST-CACHE-PLAN-2
test "planner retained snapshot post-validation detects same-size mutation with restored timestamps" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(io, ".", a);
    defer a.free(directory);
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("TMPDIR", directory);
    try environ.put("MYLANG_COMPONENT_DIR", directory);
    const deployment = try std.fs.path.join(a, &.{ directory, component_name });
    defer a.free(deployment);
    try environ.put("PLANNER_TEST_DEPLOYMENT", deployment);
    const script =
        \\#!/usr/bin/python3
        \\import os,sys,struct
        \\p=os.environ['PLANNER_TEST_DEPLOYMENT'];s=os.stat(p)
        \\c=bytearray(open(p,'rb').read());c[-2]=ord('X')
        \\open(p,'wb').write(c);os.utime(p,ns=(s.st_atime_ns,s.st_mtime_ns))
        \\b=open(sys.argv[2],'rb').read()
        \\sys.stdout.buffer.write(b[:16]+struct.pack('<II',1,4)+b[24:64]+b'\0'*4)
        \\# original
        \\
    ;
    try fixture(a, temporary.dir, script);
    var bound = try adapter.bind(a, io, &environ);
    defer bound.deinit(a);
    try std.testing.expectError(error.ComponentDigest, bound.batch(a, .{ .digests = &.{}, .callees = &.{} }, &.{}));
    try std.testing.expectEqualStrings(script, bound.snapshot.?);
}

// spec-case: SELFHOST-CACHE-PLAN-2
test "planner artifactSnapshot and bind release owned bytes on every allocation failure" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(io, ".", a);
    defer a.free(directory);
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("TMPDIR", directory);
    try environ.put("MYLANG_COMPONENT_DIR", directory);
    try fixture(a, temporary.dir, "#!/bin/sh\nexit 0\n");
    try std.testing.checkAllAllocationFailures(a, snapshotAllocations, .{ directory, &environ });
}

fn snapshotAllocations(a: std.mem.Allocator, directory: []const u8, environ: *const std.process.Environ.Map) !void {
    const launch = @import("component_launch.zig");
    const snapshot = try launch.artifactSnapshot(a, std.testing.io, directory, component_name);
    defer snapshot.deinit(a);
    const verified = try launch.artifact(a, std.testing.io, directory, component_name);
    defer a.free(verified.path);
    var bound = try adapter.bind(a, std.testing.io, environ);
    defer bound.deinit(a);
    try std.testing.expectEqualSlices(u8, snapshot.contents, bound.snapshot.?);
    try std.testing.expectEqualSlices(u8, &snapshot.verified.digest, &bound.artifact.?.digest);
}
// spec-case: SELFHOST-CACHE-PLAN-1
test "verified planner binds mode and implementation; corrupt or changed deployment fails closed" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var buffer: [4096]u8 = undefined;
    const directory = buffer[0..try temporary.dir.realPath(io, &buffer)];
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("TMPDIR", directory);
    try environ.put("MYLANG_COMPONENT_DIR", directory);
    const script =
        \\#!/usr/bin/python3
        \\import sys,struct
        \\b=open(sys.argv[2],'rb').read()
        \\sys.stdout.buffer.write(b[:16]+struct.pack('<II',1,4)+b[24:64]+b'\0'*4)
        \\
    ;
    try fixture(a, temporary.dir, script);
    var bound = try adapter.bind(a, io, &environ);
    defer bound.deinit(a);
    var answer = try bound.batch(a, .{ .digests = &.{}, .callees = &.{} }, &.{});
    defer answer.deinit();
    try environ.put("MYLANG_CACHE_PLAN_MODE", "shadow");
    var shadow = try adapter.bind(a, io, &environ);
    defer shadow.deinit(a);
    try std.testing.expect(!std.mem.eql(u8, &bound.identity, &shadow.identity));
    var parity = try shadow.batch(a, .{ .digests = &.{}, .callees = &.{} }, &.{});
    defer parity.deinit();
    try fixture(a, temporary.dir, "#!/bin/sh\nexit 7\n");
    try std.testing.expectError(error.ComponentChanged, bound.validate(a));
    var failing = try adapter.bind(a, io, &environ);
    defer failing.deinit(a);
    try std.testing.expectError(error.ComponentFailed, failing.batch(a, .{ .digests = &.{}, .callees = &.{} }, &.{}));
    try fixture(a, temporary.dir, "#!/bin/sh\nprintf malformed\n");
    var malformed = try adapter.bind(a, io, &environ);
    defer malformed.deinit(a);
    try std.testing.expectError(error.ComponentProtocol, malformed.batch(a, .{ .digests = &.{}, .callees = &.{} }, &.{}));
    try temporary.dir.writeFile(io, .{ .sub_path = component_name, .data = "corrupt" });
    try std.testing.expectError(error.ComponentDigest, adapter.bind(a, io, &environ));
}

fn rejectTruncations(a: std.mem.Allocator, bytes: *[84]u8, identity: wire.Identity, graph: wire.Graph) !void {
    for (0..bytes.len) |length| try std.testing.expectError(error.ComponentProtocol, wire.reply(a, bytes[0..length], identity, graph, &.{&.{0}}));
}

fn rejectHeaders(a: std.mem.Allocator, bytes: *[84]u8, identity: wire.Identity, graph: wire.Graph) !void {
    for ([_]usize{ 0, 8, 12, 16, 20, 24, 32, 63 }) |offset| {
        bytes[offset] ^= 1;
        try std.testing.expectError(error.ComponentProtocol, wire.reply(a, bytes, identity, graph, &.{&.{0}}));
        bytes[offset] ^= 1;
    }
}

fn rejectIds(a: std.mem.Allocator, bytes: *[84]u8, identity: wire.Identity, graph: wire.Graph) !void {
    for ([_]u32{ 0, 1, 4 }) |bad| {
        std.mem.writeInt(u32, bytes[80..84], bad, .little);
        try std.testing.expectError(error.ComponentProtocol, wire.reply(a, bytes, identity, graph, &.{&.{0}}));
    }
}
// spec-case: SELFHOST-CACHE-PLAN-1
test "planner shared launch rejects output beyond the configured capture budget" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const io = std.testing.io;
    const timeout: std.Io.Timeout = .{ .duration = .{ .clock = .awake, .raw = .fromMilliseconds(1000) } };
    try std.testing.expectError(error.StreamTooLong, @import("component_launch.zig").runBounded(arena.allocator(), io, .{
        .argv = &.{ "/usr/bin/python3", "-c", "import sys;sys.stdout.buffer.write(b'x'*256)" },
        .timeout = timeout.toDeadline(io),
        .stdout_limit = .limited(64),
        .stderr_limit = .limited(64),
    }));
}

// spec-case: SELFHOST-CACHE-PLAN-1
test "planner temporary directory failures remain ComponentIo" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(io, ".", a);
    defer a.free(directory);
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("MYLANG_COMPONENT_DIR", directory);
    try fixture(a, temporary.dir, "#!/bin/sh\nexit 0\n");
    var bound = try adapter.bind(a, io, &environ);
    defer bound.deinit(a);
    const missing = try std.fs.path.join(a, &.{ directory, "missing" });
    defer a.free(missing);
    try environ.put("TMPDIR", missing);
    try std.testing.expectError(error.ComponentIo, bound.batch(a, .{ .digests = &.{}, .callees = &.{} }, &.{}));
}

// spec-case: SELFHOST-CACHE-PLAN-1
test "planner sealed snapshot rejects mutations and executes with inherited writable descriptor" {
    const io = std.testing.io;
    const linux = std.os.linux;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const launch = @import("component_launch.zig");
    for (0..8) |_| {
        const file = try launch.sealedExecutable(io, "#!/bin/sh\nprintf sealed\n");
        defer file.close(io);
        const duplicate = linux.fcntl(file.handle, linux.F.DUPFD, 0);
        try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(duplicate));
        const inherited: std.Io.File = .{ .handle = @intCast(duplicate), .flags = .{ .nonblocking = false } };
        defer inherited.close(io);
        try std.testing.expectEqual(linux.E.PERM, linux.errno(linux.write(inherited.handle, "x", 1)));
        try std.testing.expectEqual(linux.E.PERM, linux.errno(linux.ftruncate(inherited.handle, 0)));
        try std.testing.expectEqual(linux.E.PERM, linux.errno(linux.ftruncate(inherited.handle, 4096)));
        try std.testing.expectEqual(linux.E.PERM, linux.errno(linux.fcntl(inherited.handle, linux.F.ADD_SEALS, linux.F.SEAL_FUTURE_WRITE)));
        const seals = linux.F.SEAL_WRITE | linux.F.SEAL_GROW | linux.F.SEAL_SHRINK | linux.F.SEAL_SEAL;
        try std.testing.expectEqual(@as(usize, seals), linux.fcntl(file.handle, linux.F.GET_SEALS, 0));
        const executable = try std.fmt.allocPrint(a, "/proc/{d}/fd/{d}", .{ linux.getpid(), file.handle });
        const timeout: std.Io.Timeout = .{ .duration = .{ .clock = .awake, .raw = .fromMilliseconds(1000) } };
        const result = try launch.runBounded(a, io, .{
            .argv = &.{executable},
            .timeout = timeout.toDeadline(io),
            .stdout_limit = .limited(64),
            .stderr_limit = .limited(64),
        });
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        try std.testing.expectEqualStrings("sealed", result.stdout);
    }
}
