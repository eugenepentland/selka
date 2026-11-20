//! The event loop end to end: a Selka server on one thread serves real loopback clients through one
//! `Poller` (NETWORK-POLL-1 to NETWORK-POLL-5). The server is `fixtures/event_loop_server.selka`; it
//! listens on port 0, announces the port the kernel chose on stderr, and every test drives it with
//! plain sockets from this process. `fixtures/event_loop_probe.selka` plays both ends in one process.
const std = @import("std");
const testing = std.testing;
const net = std.Io.net;
const posix = std.posix;

const server_source = @embedFile("fixtures/event_loop_server.selka");
/// The fixture's idle timeout, which the tests wait out (milliseconds).
const idle_ms: i64 = 2000;

/// One client connection that closes at most once, so a test may close it early and still defer the close.
const Peer = struct {
    stream: net.Stream,
    open: bool = true,

    fn close(self: *Peer) void {
        if (self.open) self.stream.close(testing.io);
        self.open = false;
    }
};

/// A running fixture server: its process, and the port it announced.
const Server = struct {
    child: std.process.Child,
    port: u16,

    fn deinit(self: *Server) void {
        self.child.kill(testing.io);
    }

    fn connect(self: Server) !Peer {
        const address: net.IpAddress = .{ .ip4 = .loopback(self.port) };
        return .{ .stream = try address.connect(testing.io, .{ .mode = .stream }) };
    }

    /// Wait for the server to exit on its own, as it does once a client asked it to stop.
    fn expectCleanExit(self: *Server) !void {
        const term = try self.child.wait(testing.io);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, term);
    }

    /// Ask the server to stop and wait for it, after every other client has gone.
    fn stop(self: *Server) !void {
        var last = try self.connect();
        defer last.close();
        var farewell: [3]u8 = undefined;
        try sendAll(last.stream, "q");
        try readFull(last.stream, &farewell);
        try testing.expectEqualStrings("bye", &farewell);
        try self.expectCleanExit();
    }
};

/// Many client connections to one server, closed together.
fn Crowd(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        streams: [capacity]net.Stream = undefined,
        count: usize = 0,

        /// Open `wanted` connections before any is served.
        fn open(self: *Self, server: Server, wanted: usize) !void {
            while (self.count < wanted) : (self.count += 1) self.streams[self.count] = (try server.connect()).stream;
        }

        /// Send clients `from` to `to` their own tag and index as a request, and check the same bytes come back.
        fn echoRound(self: *Self, tag: u8, from: usize, to: usize) !void {
            for (self.streams[from..to], from..) |stream, index| {
                var request: [8]u8 = undefined;
                try echo(stream, try std.fmt.bufPrint(&request, "{c}{d:0>3}\n", .{ tag, index }));
            }
        }

        /// Close clients `from` to `to` and forget them, so `closeAll` does not close them again.
        fn closeRange(self: *Self, from: usize, to: usize) void {
            for (self.streams[from..to]) |stream| stream.close(testing.io);
            std.mem.copyForwards(net.Stream, self.streams[from..], self.streams[to..self.count]);
            self.count -= to - from;
        }

        fn closeAll(self: *Self) void {
            self.closeRange(0, self.count);
        }
    };
}

/// Build `source` into `dir` and start it under `shell` (a `sh -c` prefix such as a `ulimit`),
/// returning once it has announced its port on the first stderr line.
fn startProgram(dir: std.Io.Dir, arena: std.mem.Allocator, source: []const u8, shell: []const u8) !Server {
    try dir.writeFile(testing.io, .{ .sub_path = "server.selka", .data = source });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), arena);
    var environment = try paths.privateEnvironment(arena);
    const built = try std.process.run(arena, testing.io, .{
        .argv = &.{ compiler, "build", "server.selka", "-o", "server", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path },
        .cwd = .{ .dir = dir },
        .environ_map = &environment,
    });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    try environment.put("SELKA_OPTIONS", "--restrict --allow-listen=127.0.0.1:0");
    const command = try std.fmt.allocPrint(arena, "{s}exec ./server", .{shell});
    var child = try std.process.spawn(testing.io, .{
        .argv = &.{ "/bin/sh", "-c", command },
        .cwd = .{ .dir = dir },
        .environ_map = &environment,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .pipe,
    });
    errdefer child.kill(testing.io);
    var line: [96]u8 = undefined;
    const announced = try readLine(&child, &line);
    return .{ .child = child, .port = try lastNumber(announced) };
}

/// Start the test fixture server, which announces `port N`.
fn start(dir: std.Io.Dir, arena: std.mem.Allocator, shell: []const u8) !Server {
    return startProgram(dir, arena, server_source, shell);
}

/// Read one line of the child's stderr, without its newline.
fn readLine(child: *std.process.Child, line: []u8) ![]const u8 {
    var length: usize = 0;
    while (length < line.len) {
        const width = try child.stderr.?.readStreaming(testing.io, &.{line[length .. length + 1]});
        if (width == 0 or line[length] == '\n') break;
        length += width;
    }
    return line[0..length];
}

/// The decimal number that ends `text` (`port 8080`, `listening on 127.0.0.1:8080`).
fn lastNumber(text: []const u8) !u16 {
    var start_of_digits = text.len;
    while (start_of_digits > 0 and std.ascii.isDigit(text[start_of_digits - 1])) start_of_digits -= 1;
    return std.fmt.parseInt(u16, text[start_of_digits..], 10);
}

fn readable(stream: net.Stream, timeout_ms: i32) !bool {
    var fds = [_]posix.pollfd{.{ .fd = stream.socket.handle, .events = posix.POLL.IN, .revents = 0 }};
    return (try posix.poll(&fds, timeout_ms)) > 0;
}

fn sendAll(stream: net.Stream, bytes: []const u8) !void {
    var writer = stream.writer(testing.io, &.{});
    try writer.interface.writeAll(bytes);
}

/// Read until `buffer` is full, failing if the server stays silent for ten seconds or closes early.
fn readFull(stream: net.Stream, buffer: []u8) !void {
    var total: usize = 0;
    while (total < buffer.len) {
        if (!try readable(stream, 10_000)) return error.TestUnexpectedResult;
        var slices = [_][]u8{buffer[total..]};
        const width = try stream.read(testing.io, &slices);
        if (width == 0) return error.TestUnexpectedResult;
        total += width;
    }
}

/// Send `request` and read the same number of bytes back, which must equal `request`.
fn echo(stream: net.Stream, request: []const u8) !void {
    try expectReply(stream, request, request);
}

/// Send `request` on `stream` and read back exactly `prefix.len` bytes; they must be `prefix`.
fn expectReply(stream: net.Stream, request: []const u8, prefix: []const u8) !void {
    var reply: [64]u8 = undefined;
    try sendAll(stream, request);
    try readFull(stream, reply[0..prefix.len]);
    try testing.expectEqualStrings(prefix, reply[0..prefix.len]);
}

/// Whether the server has closed `stream`: a read that returns zero bytes.
fn closedWithin(stream: net.Stream, timeout_ms: i32) !bool {
    if (!try readable(stream, timeout_ms)) return false;
    var scratch: [16]u8 = undefined;
    var slices = [_][]u8{&scratch};
    return (try stream.read(testing.io, &slices)) == 0;
}

fn milliseconds() i64 {
    return @intCast(@divTrunc(std.Io.Clock.awake.now(testing.io).nanoseconds, std.time.ns_per_ms));
}

fn localPort(stream: net.Stream) !u16 {
    var address: std.os.linux.sockaddr.in = undefined;
    var length: std.os.linux.socklen_t = @sizeOf(std.os.linux.sockaddr.in);
    try testing.expectEqual(@as(usize, 0), std.os.linux.getsockname(stream.socket.handle, @ptrCast(&address), &length));
    return std.mem.bigToNative(u16, address.port);
}

/// Read `total` bytes of the pattern 0, 1, ... 255 repeated, as the `b<N>` request produces.
fn expectPattern(stream: net.Stream, total: usize) !void {
    var buffer: [65536]u8 = undefined;
    var done: usize = 0;
    while (done < total) {
        if (!try readable(stream, 10_000)) return error.TestUnexpectedResult;
        var slices = [_][]u8{&buffer};
        const width = try stream.read(testing.io, &slices);
        if (width == 0) return error.TestUnexpectedResult;
        for (buffer[0..width], done..) |octet, index| try testing.expectEqual(@as(u8, @truncate(index)), octet);
        done += width;
    }
    try testing.expectEqual(total, done);
}

/// Send each stream a request and check that none is answered within a short wait.
fn waitUnanswered(streams: []const net.Stream) !void {
    for (streams) |stream| try sendAll(stream, "wait\n");
    for (streams) |stream| try testing.expect(!try readable(stream, 300));
}

/// Each stream's pending request is now answered with its own bytes.
fn expectAnswered(streams: []const net.Stream) !void {
    for (streams) |stream| {
        var reply: [5]u8 = undefined;
        try readFull(stream, &reply);
        try testing.expectEqualStrings("wait\n", &reply);
    }
}

/// The fixture server with an idle timeout of `milliseconds` (it is a constant of the fixture's source).
fn serverWithIdle(arena: std.mem.Allocator, milliseconds_: i64) ![]const u8 {
    const patched = try std.mem.replaceOwned(u8, arena, server_source, "const IDLE_MS: int = 2000", try std.fmt.allocPrint(arena, "const IDLE_MS: int = {d}", .{milliseconds_}));
    // A fixture that changed its constant would silently run with the old timeout and make this test about nothing.
    try testing.expect(!std.mem.eql(u8, patched, server_source) or milliseconds_ == idle_ms);
    return patched;
}

// spec: NETWORK-POLL-2
test "a poller serves sixty concurrent clients on one thread while an idle client waits" {
    // F29: this used to compare the time sixty clients took with the idle timeout, so a loaded machine failed it. The property is
    // that the idle client does not starve the others (FR-214), which is an ordering: every request is answered while the idle
    // client is still connected. The server's idle timeout is made long enough that no load can end it first.
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var server = try startProgram(temporary.dir, arena_state.allocator(), try serverWithIdle(arena_state.allocator(), 600_000), "");
    defer server.deinit();
    // FR-214: this client connects and says nothing, which starved a blocking server.
    var idle = try server.connect();
    defer idle.close();
    var crowd: Crowd(60) = .{};
    defer crowd.closeAll();
    // Every client has a connection before any is served, then each is answered twice.
    try crowd.open(server, 60);
    try crowd.echoRound('e', 0, 60);
    try crowd.echoRound('f', 0, 60);
    // Sixty clients were answered, twice each, and the idle one is still there, silent and not closed by the server.
    try testing.expect(!try closedWithin(idle.stream, 0));
    // The server still answers a new client while the idle one waits.
    var late = try server.connect();
    defer late.close();
    try echo(late.stream, "echo\n");
    try testing.expect(!try closedWithin(idle.stream, 0));
    crowd.closeAll();
    late.close();
    idle.close();
    try server.stop();
}

// spec-case: NETWORK-POLL-2
test "a poller closes an idle client after the timeout it asked for, and sixty idle clients with it, and still answers a new one" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var server = try start(temporary.dir, arena_state.allocator(), "");
    defer server.deinit();
    var idle = try server.connect();
    defer idle.close();
    const idle_since = milliseconds();
    var crowd: Crowd(60) = .{};
    defer crowd.closeAll();
    try crowd.open(server, 60);
    try crowd.echoRound('e', 0, 60);
    // The idle client is closed by the server, no sooner than the timeout it asked for. Only the lower bound is a claim: a loaded
    // machine can delay the close, never bring it forward, and the wait is bounded by the poll below.
    try testing.expect(try closedWithin(idle.stream, 60_000));
    try testing.expect(milliseconds() - idle_since >= idle_ms - 100);
    // The server still answers a new client, and leaves its loop when one asks it to.
    var late = try server.connect();
    defer late.close();
    try echo(late.stream, "echo\n");
    var farewell: [3]u8 = undefined;
    try sendAll(late.stream, "q");
    try readFull(late.stream, &farewell);
    try testing.expectEqualStrings("bye", &farewell);
    // It stops once every client is gone: the sixty went idle too and were closed.
    try server.expectCleanExit();
}

// spec-case: NETWORK-POLL-3
test "a poller sends a response larger than the socket buffers over several wake-ups to a slow reader" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var server = try start(temporary.dir, arena_state.allocator(), "");
    defer server.deinit();
    // 16,384 blocks of 256 bytes: 4 MiB, far more than the kernel will take at once.
    var slow = try server.connect();
    defer slow.close();
    try sendAll(slow.stream, "b16384");
    std.Io.sleep(testing.io, std.Io.Duration.fromMilliseconds(400), .awake) catch {};
    // The server's send is blocked on a full socket, and it still serves another client.
    var other = try server.connect();
    defer other.close();
    try echo(other.stream, "hi\n");
    // The slow client now reads everything, and every byte is where it belongs.
    try expectPattern(slow.stream, 16384 * 256);
    try testing.expect(!try closedWithin(other.stream, 0));
    slow.close();
    other.close();
    try server.stop();
}

// spec: NETWORK-POLL-4
test "the poller reports the bound port, each client's address and its connection limit" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var server = try start(temporary.dir, arena_state.allocator(), "");
    defer server.deinit();
    // FR-204: the server listened on port 0 and the kernel chose the port it announced.
    try testing.expect(server.port >= 1024);
    var expected: [32]u8 = undefined;
    // FR-216: the peer the server names is this client's own address.
    var first = try server.connect();
    defer first.close();
    try expectReply(first.stream, "p", try std.fmt.bufPrint(&expected, "peer 127.0.0.1:{d}", .{try localPort(first.stream)}));
    // A second client has a different address.
    var second = try server.connect();
    defer second.close();
    try testing.expect(try localPort(second.stream) != try localPort(first.stream));
    try expectReply(second.stream, "p", try std.fmt.bufPrint(&expected, "peer 127.0.0.1:{d}", .{try localPort(second.stream)}));
    // The limit is at least the descriptor-limited minimum, and two connections are open.
    var limits: [64]u8 = undefined;
    try sendAll(first.stream, "l");
    try testing.expect(try readable(first.stream, 10_000));
    var slices = [_][]u8{&limits};
    const length = try first.stream.read(testing.io, &slices);
    try testing.expect(std.mem.startsWith(u8, limits[0..length], "limit "));
    try testing.expect(std.mem.endsWith(u8, limits[0..length], " open 2"));
    first.close();
    second.close();
    try server.stop();
}

// spec-case: NETWORK-POLL-1
test "a poller's connection limit is the descriptor limit less 64 even above 1,024" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    // A descriptor limit of 2000 leaves 1936 slots: the table grows past its first 1,024.
    var server = try start(temporary.dir, arena_state.allocator(), "ulimit -n 2000 && ");
    defer server.deinit();
    var client = try server.connect();
    defer client.close();
    try expectReply(client.stream, "l", "limit 1936 open 1");
    client.close();
    try server.stop();
}

// spec-case: NETWORK-POLL-1
test "a program started after a poller opened gets the soft descriptor limit this program started with" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "child_limit.selka", .data = @embedFile("fixtures/poller_child_limit.selka") });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), arena);
    var environment = try paths.privateEnvironment(arena);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    // Soft 2000, hard 4000: the poller raises its own soft limit to 4000 (a limit of 3,936 connections), and `sh -c 'ulimit -n'`
    // still reports 2000, as it does when no poller has opened.
    const result = try std.process.run(arena, testing.io, .{
        .argv = &.{
            "/bin/sh",                                    "-c",                "ulimit -Sn 2000 && ulimit -Hn 4000 && exec \"$0\" \"$@\"",
            compiler,                                     "run",               "child_limit.selka",
            "--zig=" ++ @import("test_options").zig_path, "--cache-dir=cache", "--restrict",
            "--allow-listen=127.0.0.1:0",                 "--allow-process",
        },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    try testing.expectEqualStrings("child before 2000\npoller limit 3936\nchild with a poller 2000\n", result.stdout);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

// spec-case: NETWORK-POLL-1
test "a poller with a full connection table leaves clients in the backlog until a slot frees" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    // A descriptor limit of 100 leaves 36 slots after the 64 the runtime keeps back.
    var server = try start(temporary.dir, arena_state.allocator(), "ulimit -n 100 && ");
    defer server.deinit();
    var crowd: Crowd(40) = .{};
    defer crowd.closeAll();
    try crowd.open(server, 40);
    // The first 36 are served; the other four wait in the kernel's backlog and are not answered.
    try crowd.echoRound('e', 0, 36);
    try waitUnanswered(crowd.streams[36..40]);
    // Closing four served clients frees four slots, and the waiting clients are accepted and answered.
    crowd.closeRange(0, 4);
    try expectAnswered(crowd.streams[32..36]);
    try testing.expectEqual(@as(usize, 36), crowd.count);
    crowd.closeAll();
    try server.stop();
}

/// What `fixtures/event_loop_probe.selka` prints, with the port it binds in the first line.
const probe_transcript =
    \\port {d}
    \\limit ok True open 0
    \\empty wait 0
    \\accept before connect code 1 value 0
    \\listener wait 1 0 1
    \\accept code 0 value 1024
    \\recv before data code 1 value 0
    \\peer 127.0.0.1:0 True
    \\open 1
    \\data wait 1 True 1
    \\recv code 0 value 5
    \\received hello
    \\send code 0 value 6
    \\send from offset 3 code 0 value 3
    \\send nothing code 0 value 0
    \\client read world!def
    \\send to wrong id code 4 value 0
    \\recv from slot id code 4 value 0
    \\quiet wait 0
    \\writable wait 1 2
    \\muted wait 0
    \\unmuted wait 1 1
    \\recv x code 0 value 1
    \\bad interest code 6 value 0
    \\idle wait 1 True 16
    \\idle again at once 0
    \\shutdown code 0 value 0
    \\client eof 1
    \\hangup wait 1 True 5
    \\recv after hangup code 2 value 0
    \\close code 0 value 0
    \\recv after close code 4 value 0
    \\close again code 4 value 0
    \\open at end 0
    \\
;

// spec: NETWORK-POLL-3
test "a poller and a client in one process: the poller reports every step" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // The probe dials its own endpoint by literal, so it needs a port chosen before it starts.
    const address: net.IpAddress = .{ .ip4 = .loopback(0) };
    var holder = try address.listen(testing.io, .{});
    const port = holder.socket.address.getPort();
    holder.deinit(testing.io);
    const source = try std.mem.replaceOwned(u8, arena, @embedFile("fixtures/event_loop_probe.selka"), "18090", try std.fmt.allocPrint(arena, "{d}", .{port}));
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "probe.selka", .data = source });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), arena);
    var environment = try paths.privateEnvironment(arena);
    const endpoint = try std.fmt.allocPrint(arena, "127.0.0.1:{d}", .{port});
    const result = try std.process.run(arena, testing.io, .{
        .argv = &.{
            compiler,
            "run",
            "probe.selka",
            "--zig=" ++ @import("test_options").zig_path,
            "--cache-dir=cache",
            "--restrict",
            try std.fmt.allocPrint(arena, "--allow-listen={s}", .{endpoint}),
            try std.fmt.allocPrint(arena, "--allow-endpoint={s}", .{endpoint}),
        },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    var expected: std.ArrayList(u8) = .empty;
    try expected.print(arena, probe_transcript, .{port});
    try testing.expectEqualStrings(expected.items, result.stdout);
}

/// What `fixtures/event_loop_sizes_probe.selka` prints: every size arrives whole and in order both ways, and nothing is
/// left over; a blocking client's read finds zeros after the bytes it got; a peer that closes midway ends the stream
/// after the bytes it sent.
const sizes_transcript =
    \\connected True True
    \\size 0 sent 0 received 0 same True True back 0 same True True then nothing 0 1
    \\size 1 sent 1 received 1 same True True back 1 same True True then nothing 0 1
    \\size 243 sent 243 received 243 same True True back 243 same True True then nothing 0 1
    \\size 244 sent 244 received 244 same True True back 244 same True True then nothing 0 1
    \\size 245 sent 245 received 245 same True True back 245 same True True then nothing 0 1
    \\size 2292 sent 2292 received 2292 same True True back 2292 same True True then nothing 0 1
    \\size 2293 sent 2293 received 2293 same True True back 2293 same True True then nothing 0 1
    \\size 16383 sent 16383 received 16383 same True True back 16383 same True True then nothing 0 1
    \\size 16384 sent 16384 received 16384 same True True back 16384 same True True then nothing 0 1
    \\size 16385 sent 16385 received 16385 same True True back 16385 same True True then nothing 0 1
    \\client read 5 bytes, nonzero after them 0
    \\peer closed after 20000 received 20000 same True True
    \\after the peer closed: appended and code 0 2
    \\send to a closed peer fails True
    \\one read of a message of 40000 took True True True
    \\send after the reader closed True
    \\open at end 0
    \\
;

// spec: NETWORK-POLL-3
test "recv and send move messages of 0 to 16,385 bytes whole in both directions, under the leak check" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const address: net.IpAddress = .{ .ip4 = .loopback(0) };
    var holder = try address.listen(testing.io, .{});
    const port = holder.socket.address.getPort();
    holder.deinit(testing.io);
    const source = try std.mem.replaceOwned(u8, arena, @embedFile("fixtures/event_loop_sizes_probe.selka"), "18091", try std.fmt.allocPrint(arena, "{d}", .{port}));
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "probe.selka", .data = source });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), arena);
    var environment = try paths.privateEnvironment(arena);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const endpoint = try std.fmt.allocPrint(arena, "127.0.0.1:{d}", .{port});
    const result = try std.process.run(arena, testing.io, .{
        .argv = &.{
            compiler,
            "run",
            "probe.selka",
            "--zig=" ++ @import("test_options").zig_path,
            "--cache-dir=cache",
            "--restrict",
            try std.fmt.allocPrint(arena, "--allow-listen={s}", .{endpoint}),
            try std.fmt.allocPrint(arena, "--allow-endpoint={s}", .{endpoint}),
        },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    try testing.expectEqualStrings(sizes_transcript, result.stdout);
}

/// What `fixtures/network_limits_probe.selka` prints: every limit ran out where it should and nowhere else.
const limits_transcript =
    \\read timed out True True
    \\read after the timeout 2 False
    \\write timed out True True timed out: the endpoint did not answer within the time limit
    \\closed peer 0 True
    \\no limits 5
    \\listener True
    \\unknown id True
    \\own timeout True
    \\idle 1 True 16
    \\the longer one stays 0
    \\back to the poller's 1 True 16
    \\own with none on the poller 1 True 16
    \\never 0
    \\connect timed out True True timed out: the endpoint did not answer within the time limit
    \\connect refused 3 False
    \\
;

/// A loopback port no socket holds when this returns.
fn freePort() !u16 {
    const address: net.IpAddress = .{ .ip4 = .loopback(0) };
    var holder = try address.listen(testing.io, .{});
    defer holder.deinit(testing.io);
    return holder.socket.address.getPort();
}

// FR1 (F-5, F-13): a read, a write and a connect given time limits by `network.connect_within` fail with
// `network.timed_out()` near the limit and leave a refused connect and a closed peer as they were; a connection's own
// idle timeout replaces the poller's for it alone.
test "connect_within bounds a connect, a read and a write, and a connection's idle timeout is its own" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const polled = try freePort();
    const refused = try freePort();
    // A listener with a backlog of none and one connection already queued drops every further SYN, so a connect to it
    // is never answered (Linux; the kernel retries the SYN for about two minutes).
    const silent_address: net.IpAddress = .{ .ip4 = .loopback(0) };
    var silent = try silent_address.listen(testing.io, .{ .kernel_backlog = 0 });
    defer silent.deinit(testing.io);
    const silent_port = silent.socket.address.getPort();
    const queued_address: net.IpAddress = .{ .ip4 = .loopback(silent_port) };
    var queued = try queued_address.connect(testing.io, .{ .mode = .stream });
    defer queued.close(testing.io);
    var source: []const u8 = @embedFile("fixtures/network_limits_probe.selka");
    source = try std.mem.replaceOwned(u8, arena, source, "18101", try std.fmt.allocPrint(arena, "{d}", .{polled}));
    source = try std.mem.replaceOwned(u8, arena, source, "18102", try std.fmt.allocPrint(arena, "{d}", .{silent_port}));
    source = try std.mem.replaceOwned(u8, arena, source, "18103", try std.fmt.allocPrint(arena, "{d}", .{refused}));
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "probe.selka", .data = source });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), arena);
    var environment = try paths.privateEnvironment(arena);
    const result = try std.process.run(arena, testing.io, .{
        .argv = &.{
            compiler,
            "run",
            "probe.selka",
            "--zig=" ++ @import("test_options").zig_path,
            "--cache-dir=cache",
            "--restrict",
            "--allow-clock",
            try std.fmt.allocPrint(arena, "--allow-listen=127.0.0.1:{d}", .{polled}),
            try std.fmt.allocPrint(arena, "--allow-endpoint=127.0.0.1:{d}", .{polled}),
            try std.fmt.allocPrint(arena, "--allow-endpoint=127.0.0.1:{d}", .{silent_port}),
            try std.fmt.allocPrint(arena, "--allow-endpoint=127.0.0.1:{d}", .{refused}),
        },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    try testing.expectEqualStrings(limits_transcript, result.stdout);
    try testing.expectEqualStrings("", result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

/// What `fixtures/network_dial_probe.selka` prints: one loop serves and calls, and each dial ends the way it should.
const dial_transcript =
    \\dial True True
    \\connected True accepted 1
    \\served and called ping pong
    \\nine 9 connected 9 open 18
    \\refused 111
    \\dial within True True
    \\timed out True True 110 True
    \\idle 1 True 16
    \\small buffer True
    \\small buffer of connect_within True
    \\denied True True
    \\memory True 2
    \\open at end 0
    \\
;

// FR7 (F-29, F-30, F-34): a Poller dials its own listener, holds nine dialled connections by id, sees a refused port and
// a connect past its limit as errors without blocking the loop, times a dialled connection out as idle, and a receive
// buffer of 4 KiB lowers what a writer's kernel takes for a reader that never reads.
test "a poller dials, serves the connections it dialled, and reports a refused or unanswered dial" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const polled = try freePort();
    const refused = try freePort();
    // A backlog of none with one connection queued drops every further SYN (Linux), so a dial to it is never answered.
    const silent_address: net.IpAddress = .{ .ip4 = .loopback(0) };
    var silent = try silent_address.listen(testing.io, .{ .kernel_backlog = 0 });
    defer silent.deinit(testing.io);
    const silent_port = silent.socket.address.getPort();
    const queued_address: net.IpAddress = .{ .ip4 = .loopback(silent_port) };
    var queued = try queued_address.connect(testing.io, .{ .mode = .stream });
    defer queued.close(testing.io);
    var source: []const u8 = @embedFile("fixtures/network_dial_probe.selka");
    source = try std.mem.replaceOwned(u8, arena, source, "18201", try std.fmt.allocPrint(arena, "{d}", .{polled}));
    source = try std.mem.replaceOwned(u8, arena, source, "18202", try std.fmt.allocPrint(arena, "{d}", .{silent_port}));
    source = try std.mem.replaceOwned(u8, arena, source, "18203", try std.fmt.allocPrint(arena, "{d}", .{refused}));
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "probe.selka", .data = source });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), arena);
    var environment = try paths.privateEnvironment(arena);
    const result = try std.process.run(arena, testing.io, .{
        .argv = &.{
            compiler,
            "run",
            "probe.selka",
            "--zig=" ++ @import("test_options").zig_path,
            "--cache-dir=cache",
            "--restrict",
            "--allow-clock",
            try std.fmt.allocPrint(arena, "--allow-listen=127.0.0.1:{d}", .{polled}),
            try std.fmt.allocPrint(arena, "--allow-endpoint=127.0.0.1:{d}", .{polled}),
            try std.fmt.allocPrint(arena, "--allow-endpoint=127.0.0.1:{d}", .{silent_port}),
            try std.fmt.allocPrint(arena, "--allow-endpoint=127.0.0.1:{d}", .{refused}),
        },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    try testing.expectEqualStrings(dial_transcript, result.stdout);
    try testing.expectEqualStrings("", result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

// W28 (F-29): a fake service and its client in two tasks of one group checked and then never finished, because one task's
// blocking read held the other task's calls to the shared Network. A task cannot take the Network now, so `check` refuses
// the program and names the event loop; the same program as one loop that accepts and dials answers and finishes.
test "F-29's service and client in two tasks are refused, and one loop that accepts and dials finishes" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const port = try freePort();
    const endpoint = try std.fmt.allocPrint(arena, "127.0.0.1:{d}", .{port});
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tasks.selka", .data = @embedFile("fixtures/f29_task_service_and_client.selka") });
    const loop = try std.mem.replaceOwned(u8, arena, @embedFile("fixtures/f29_one_loop.selka"), "127.0.0.1:18211", endpoint);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "loop.selka", .data = loop });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), arena);
    var environment = try paths.privateEnvironment(arena);
    const refused = try std.process.run(arena, testing.io, .{
        .argv = &.{ compiler, "check", "tasks.selka" },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, refused.stderr, "error[E_TASK_CAPABILITY]: `net` is a `Network`"));
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "one event loop that accepts and dials (`network.dial`") != null);
    const ran = try std.process.run(arena, testing.io, .{
        .argv = &.{
            compiler,
            "run",
            "loop.selka",
            "--zig=" ++ @import("test_options").zig_path,
            "--cache-dir=cache",
            "--restrict",
            try std.fmt.allocPrint(arena, "--allow-listen={s}", .{endpoint}),
            try std.fmt.allocPrint(arena, "--allow-endpoint={s}", .{endpoint}),
        },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    try testing.expectEqualStrings("client read 62\n", ran.stdout);
    try testing.expectEqualStrings("", ran.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
}

// FR7: a dial needs the grant a blocking connect needs. Without `--allow-endpoint` for the address, the Network refuses
// it before any socket is made, and the poller's table is unchanged.
test "a poller's dial to an endpoint the command line did not grant is denied" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const polled = try freePort();
    const source = try std.fmt.allocPrint(arena,
        \\import network
        \\
        \\func main(net: Network, out: Stream) -> int:
        \\    with net.host("127.0.0.1:{d}") as scoped:
        \\        with net.host("127.0.0.1:9") as elsewhere:
        \\            match network.open_poller(scoped):
        \\                case ok(poller):
        \\                    mut live = own poller
        \\                    mut outcome = network.new_outcome()
        \\                    network.dial(mut live, elsewhere, mut outcome)
        \\                    print(out, outcome.code == network.OUTCOME_DENIED, outcome.value)
        \\                    live = network.connection_limit(own live, mut outcome)
        \\                    print(out, "open", outcome.extra)
        \\                    return 0
        \\                case err(code):
        \\                    return code
        \\
    , .{polled});
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "denied.selka", .data = source });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), arena);
    var environment = try paths.privateEnvironment(arena);
    const result = try std.process.run(arena, testing.io, .{
        .argv = &.{
            compiler,
            "run",
            "denied.selka",
            "--zig=" ++ @import("test_options").zig_path,
            "--cache-dir=cache",
            "--restrict",
            try std.fmt.allocPrint(arena, "--allow-listen=127.0.0.1:{d}", .{polled}),
            try std.fmt.allocPrint(arena, "--allow-endpoint=127.0.0.1:{d}", .{polled}),
        },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    try testing.expectEqualStrings("True 2\nopen 0\n", result.stdout);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

/// The number of descriptors process `pid` holds open.
fn descriptors(arena: std.mem.Allocator, pid: std.process.Child.Id) !usize {
    const command = try std.fmt.allocPrint(arena, "ls /proc/{d}/fd | wc -l", .{pid});
    const result = try std.process.run(arena, testing.io, .{ .argv = &.{ "/bin/sh", "-c", command } });
    return std.fmt.parseInt(usize, std.mem.trim(u8, result.stdout, " \n"), 10);
}

/// Connect, echo one line and close, `cycles` times in a row.
fn churn(server: Server, cycles: usize) !void {
    var request: [16]u8 = undefined;
    for (0..cycles) |cycle| {
        var peer = try server.connect();
        defer peer.close();
        try echo(peer.stream, try std.fmt.bufPrint(&request, "c{d:0>5}\n", .{cycle}));
    }
}

/// Wait up to five seconds for the server to hold exactly `wanted` descriptors.
fn expectDescriptors(arena: std.mem.Allocator, pid: std.process.Child.Id, wanted: usize) !void {
    var attempts: usize = 0;
    while (attempts < 100 and try descriptors(arena, pid) != wanted) : (attempts += 1) {
        std.Io.sleep(testing.io, std.Io.Duration.fromMilliseconds(50), .awake) catch {};
    }
    try testing.expectEqual(wanted, try descriptors(arena, pid));
}

// spec-case: NETWORK-POLL-3
test "a poller holds no descriptor after fifteen hundred connect, echo and close cycles" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var server = try start(temporary.dir, arena, "");
    defer server.deinit();
    const pid = server.child.id.?;
    const before = try descriptors(arena, pid);
    // 1,500 connections pass through a table of 1,024 slots, so every slot is reused and no id repeats.
    try churn(server, 1500);
    try expectDescriptors(arena, pid, before);
    var peer = try server.connect();
    defer peer.close();
    try expectReply(peer.stream, "l", "limit ");
    peer.close();
    try server.stop();
}

// spec-case: NETWORK-POLL-4
test "the shipped event-loop echo example echoes concurrent clients and logs each peer" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(testing.io, "examples/event-loop-echo/main.selka", arena, .limited(1 << 20));
    var server = try startProgram(temporary.dir, arena, source, "");
    defer server.deinit();
    var first = try server.connect();
    defer first.close();
    var second = try server.connect();
    defer second.close();
    // The example logs `accepted ADDRESS:PORT` for each client, naming the client's own port.
    var line: [96]u8 = undefined;
    const logged = try readLine(&server.child, &line);
    try testing.expectEqual(try localPort(first.stream), try lastNumber(logged));
    try testing.expect(std.mem.startsWith(u8, logged, "accepted 127.0.0.1:"));
    try echo(first.stream, "one\n");
    try echo(second.stream, "two\n");
    // A message longer than one receive chunk comes back whole and in order.
    var message: [20_000]u8 = undefined;
    for (&message, 0..) |*octet, index| octet.* = @truncate(index *% 7 +% 3);
    try sendAll(first.stream, &message);
    var echoed: [20_000]u8 = undefined;
    try readFull(first.stream, &echoed);
    try testing.expectEqualSlices(u8, &message, &echoed);
}

/// What `fixtures/client_poller_probe.selka` prints against the echo server: nothing to accept, no port for the listener,
/// every connection open, and each connection's message echoed.
const client_transcript =
    \\accept True
    \\listener True
    \\dialled 1500 connected 1500 failed 0
    \\limit True open 1500
    \\sent 1500 echoed 1500
    \\
;

/// The same program under a connect grant for an endpoint it does not dial: every dial is denied and the poller holds nothing.
const client_denied_transcript =
    \\accept True
    \\listener True
    \\dialled 0 connected 0 failed 1500
    \\limit True open 0
    \\sent 0 echoed 0
    \\
;

/// Run `fixtures/client_poller_probe.selka`, which dials the echo server on `port`, under `--restrict` and `grants`, with the
/// leak check on.
fn runClientProbe(dir: std.Io.Dir, arena: std.mem.Allocator, port: u16, grants: []const []const u8) !std.process.RunResult {
    const source = try std.mem.replaceOwned(u8, arena, @embedFile("fixtures/client_poller_probe.selka"), "127.0.0.1:18301", try std.fmt.allocPrint(arena, "127.0.0.1:{d}", .{port}));
    try dir.writeFile(testing.io, .{ .sub_path = "client.selka", .data = source });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), arena);
    var environment = try paths.privateEnvironment(arena);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ compiler, "run", "client.selka", "--zig=" ++ @import("test_options").zig_path, "--cache-dir=cache", "--restrict" });
    try argv.appendSlice(arena, grants);
    return std.process.run(arena, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = dir }, .environ_map = &environment });
}

// spec: NETWORK-POLL-6
test "a client poller holds fifteen hundred outgoing connections with a message each way, under only a connect grant" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // The server holds the other 1,500 ends, and does not time them out while the client dials the rest.
    var server = try startProgram(temporary.dir, arena, try serverWithIdle(arena, 120_000), "ulimit -n 4096 && ");
    defer server.deinit();
    const endpoint = try std.fmt.allocPrint(arena, "--allow-endpoint=127.0.0.1:{d}", .{server.port});
    // Only a connect grant: no `--allow-listen` is given, and the client needs none.
    const result = try runClientProbe(temporary.dir, arena, server.port, &.{endpoint});
    try testing.expectEqualStrings(client_transcript, result.stdout);
    try testing.expectEqualStrings("", result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try server.stop();
}

// spec: NETWORK-POLL-6
test "a client poller whose launch grants no endpoint is refused, and one whose grant names another endpoint holds nothing" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const port = try freePort();
    // No grant at all: the launch refuses the program before it runs, in the words it uses for a connect.
    const bare = try runClientProbe(temporary.dir, arena, port, &.{});
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, bare.term);
    try testing.expect(std.mem.indexOf(u8, bare.stderr, "this command line did not grant a capability the entry point requests; pass --allow-endpoint=IP:PORT or --allow-listen=IP:PORT, or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`net: Network?`)") != null);
    // A listen grant alone is no connect grant: the open fails with 1, "no network authority is available".
    const listening = try runClientProbe(temporary.dir, arena, port, &.{"--allow-listen=127.0.0.1:0"});
    try testing.expectEqualStrings("open failed 1 no network authority is available\n", listening.stdout);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, listening.term);
    // A grant for another endpoint opens the poller and denies each dial (2) without a socket being made.
    const elsewhere = try runClientProbe(temporary.dir, arena, port, &.{"--allow-endpoint=127.0.0.1:9"});
    try testing.expectEqualStrings(client_denied_transcript, elsewhere.stdout);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, elsewhere.term);
}

/// The resident set of process `pid` in KiB, as the kernel reports it in `/proc/PID/status` (a file that has no size, so it is read
/// as a stream: one read returns the whole of it).
fn residentKb(arena: std.mem.Allocator, pid: posix.pid_t) !u64 {
    const path = try std.fmt.allocPrint(arena, "/proc/{d}/status", .{pid});
    var file = try std.Io.Dir.cwd().openFile(testing.io, path, .{});
    defer file.close(testing.io);
    var buffer: [8192]u8 = undefined;
    const width = try file.readStreaming(testing.io, &.{&buffer});
    const text = buffer[0..width];
    const at = std.mem.indexOf(u8, text, "VmRSS:") orelse return error.TestUnexpectedResult;
    var fields = std.mem.tokenizeAny(u8, text[at + "VmRSS:".len ..], " \t\n");
    return std.fmt.parseInt(u64, fields.next() orelse return error.TestUnexpectedResult, 10);
}

/// Run `event_loop_trim_server.selka` with its two constants replaced, under the leak check, and wait until the resident set of the
/// server, which has stored and deleted 12 MB of values, is under 9 MB (the process itself starts at about 3 MB; without a trim it
/// stays above 14 MB for ever). Then a client ends its wait and the server must exit cleanly, the leak check silent.
fn expectMemoryReturned(wait_ms: []const u8, rounds: []const u8) !void {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const base = @embedFile("fixtures/event_loop_trim_server.selka");
    const timed = try std.mem.replaceOwned(u8, arena, base, "const WAIT_MS: int = 20000", try std.fmt.allocPrint(arena, "const WAIT_MS: int = {s}", .{wait_ms}));
    const source = try std.mem.replaceOwned(u8, arena, timed, "const ROUNDS: int = 1", try std.fmt.allocPrint(arena, "const ROUNDS: int = {s}", .{rounds}));
    // A fixture that changed a constant would silently run with the old one and make this test about nothing.
    try testing.expect(!std.mem.eql(u8, source, base) or (std.mem.eql(u8, wait_ms, "20000") and std.mem.eql(u8, rounds, "1")));
    var server = try startProgram(temporary.dir, arena, source, "export SELKA_CORE_LEAKCHECK=1; ");
    defer server.deinit();
    var line: [32]u8 = undefined;
    try testing.expectEqualStrings("emptied 0", try readLine(&server.child, &line));
    const pid = server.child.id.?;
    // The wait is long and the trim comes before it blocks, or the loop is idle for a second: either way well within 30 seconds.
    const deadline = milliseconds() + 30_000;
    var resident = try residentKb(arena, pid);
    while (resident >= 9_000 and milliseconds() < deadline) {
        std.Io.sleep(testing.io, std.Io.Duration.fromMilliseconds(50), .awake) catch {};
        resident = try residentKb(arena, pid);
    }
    try testing.expect(resident < 9_000);
    var late = try server.connect();
    defer late.close();
    // What is left of stderr when the server ends is empty: a leak report would be there.
    var rest: [256]u8 = undefined;
    var length: usize = 0;
    while (length < rest.len) {
        length += server.child.stderr.?.readStreaming(testing.io, &.{rest[length..]}) catch |failure| switch (failure) {
            error.EndOfStream => break,
            else => return failure,
        };
    }
    try testing.expectEqualStrings("", rest[0..length]);
    try server.expectCleanExit();
}

// spec-case: RUNTIME-HEAP-RETURN-1
test "a server that deleted 12 MB of values holds a few MB once its poller waits for a long time" {
    try expectMemoryReturned("20000", "1");
}

// spec-case: RUNTIME-HEAP-RETURN-1
test "a server that deleted 12 MB of values holds a few MB after its short waits found nothing for a second" {
    try expectMemoryReturned("100", "200");
}
