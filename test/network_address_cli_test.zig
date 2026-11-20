//! FR5a (F-4): the `network` operations that take an address at run time (`connect_to`, `listen_at`,
//! `open_poller_at`, `dial_to`) are checked against the launch's grants exactly as `net.host("IP:PORT")` is:
//! `--allow-endpoint` for connecting, `--allow-listen` for listening, verbatim, and every address without
//! `--restrict`. A Network narrowed with `net.host` refuses any address but its own. The guest reads its operations
//! and addresses from its arguments, so one program shows each launch, and prints one line of codes per operation.
const std = @import("std");
const testing = std.testing;
const net = std.Io.net;

/// The guest: `op address` pairs from the arguments. `narrowed` connects through `net.host` of the port the test
/// put in the source (`{d}`), so it reaches only that address.
const guest =
    \\import network
    \\
    \\
    \\func try_poller(net: Network, address: str, out: Stream):
    \\    match network.open_poller_at(net, address):
    \\        case ok(made):
    \\            mut live = own made
    \\            mut outcome = network.new_outcome()
    \\            live = network.port(own live, network.LISTENER, mut outcome)
    \\            print(out, "poller", address, 0, outcome.value > 0)
    \\            _ = own live
    \\        case err(code):
    \\            print(out, "poller", address, code)
    \\
    \\
    \\func try_dial(net: Network, local: str, target: str, out: Stream):
    \\    match network.open_poller_at(net, local):
    \\        case ok(made):
    \\            mut live = own made
    \\            mut outcome = network.new_outcome()
    \\            network.dial_to(mut live, net, target, mut outcome)
    \\            print(out, "dial", target, outcome.code, outcome.value)
    \\            _ = own live
    \\        case err(code):
    \\            print(out, "dial", target, "no poller", code)
    \\
    \\
    \\func try_listen(net: Network, address: str, out: Stream):
    \\    match network.listen_at(net, address):
    \\        case ok(made):
    \\            _ = own made
    \\            print(out, "listen", address, 0)
    \\        case err(code):
    \\            print(out, "listen", address, code)
    \\
    \\
    \\func try_connect(net: Network, address: str, out: Stream):
    \\    match network.connect_to(net, address):
    \\        case ok(made):
    \\            _ = network.close(own made)
    \\            print(out, "connect", address, 0)
    \\        case err(code):
    \\            print(out, "connect", address, code)
    \\
    \\
    \\func main(args: str[], net: Network, out: Stream) -> int:
    \\    mut at = 0
    \\    while at + 1 < len(args):
    \\        const op = args[at]
    \\        const address = args[at + 1]
    \\        match op:
    \\            case "poller":
    \\                try_poller(net, address, out)
    \\            case "listen":
    \\                try_listen(net, address, out)
    \\            case "connect":
    \\                try_connect(net, address, out)
    \\            case "dial":
    \\                try_dial(net, "127.0.0.1:0", address, out)
    \\            case "narrowed":
    \\                with net.host("127.0.0.1:{d}") as scoped:
    \\                    try_connect(scoped, address, out)
    \\            case _:
    \\                print(out, "unknown", op)
    \\        at += 2
    \\    return 0
    \\
;

/// A port nothing listens on once this returns.
fn freePort() !u16 {
    const address: net.IpAddress = .{ .ip4 = .loopback(0) };
    var holder = try address.listen(testing.io, .{});
    defer holder.deinit(testing.io);
    return holder.socket.address.getPort();
}

/// Build the guest into `dir` as `addresses`, with `narrowed` pinned to port `pinned`.
fn buildGuest(dir: std.Io.Dir, arena: std.mem.Allocator, pinned: u16) !void {
    try dir.writeFile(testing.io, .{ .sub_path = "addresses.selka", .data = try std.fmt.allocPrint(arena, guest, .{pinned}) });
    const paths = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), arena);
    var environment = try paths.privateEnvironment(arena);
    const built = try std.process.run(arena, testing.io, .{
        .argv = &.{ compiler, "build", "addresses.selka", "-o", "addresses", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path },
        .cwd = .{ .dir = dir },
        .environ_map = &environment,
    });
    try testing.expectEqualStrings("", built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
}

/// Run the built guest with `options` in `SELKA_OPTIONS` and `args` as its arguments; return its standard output.
fn runGuest(dir: std.Io.Dir, arena: std.mem.Allocator, options: []const u8, args: []const []const u8) ![]const u8 {
    const paths = @import("test_paths");
    var environment = try paths.privateEnvironment(arena);
    try environment.put("SELKA_OPTIONS", options);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, "./addresses");
    try argv.appendSlice(arena, args);
    const ran = try std.process.run(arena, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = dir }, .environ_map = &environment });
    try testing.expectEqualStrings("", ran.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
    return ran.stdout;
}

/// `127.0.0.1:PORT`.
fn at(arena: std.mem.Allocator, port: u16) ![]const u8 {
    return std.fmt.allocPrint(arena, "127.0.0.1:{d}", .{port});
}

// FR5a: granted, not granted and the wrong kind of grant, for each operation. Codes: 0 done, 1 no grant of that kind
// at all ("no network authority is available"), 2 outside the granted endpoints, 3 granted but nothing answers there.
// A dial answers in its outcome: code 0 with the new id, or `OUTCOME_DENIED` (7) with the Network's code as the value.
test "an address given at run time is granted by --allow-listen and --allow-endpoint exactly as a net.host literal" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const granted = try at(arena, try freePort());
    const other = try at(arena, try freePort());
    try buildGuest(temporary.dir, arena, 1);
    // Listening and connecting both granted for `granted`, and the kernel's choice of port for the dial's poller.
    const both = try std.fmt.allocPrint(arena, "--restrict --allow-listen={s} --allow-listen=127.0.0.1:0 --allow-endpoint={s}", .{ granted, granted });
    const ran = try runGuest(temporary.dir, arena, both, &.{ "poller", granted, "poller", other, "listen", granted, "listen", other, "connect", granted, "connect", other, "dial", other });
    try testing.expectEqualStrings(try std.fmt.allocPrint(arena,
        \\poller {s} 0 True
        \\poller {s} 2
        \\listen {s} 0
        \\listen {s} 2
        \\connect {s} 3
        \\connect {s} 2
        \\dial {s} 7 2
        \\
    , .{ granted, other, granted, other, granted, other, other }), ran);
    // A listen grant does not let the program connect, and a connect grant does not let it listen.
    const listen_only = try runGuest(temporary.dir, arena, try std.fmt.allocPrint(arena, "--restrict --allow-listen={s}", .{granted}), &.{ "poller", granted, "connect", granted });
    try testing.expectEqualStrings(try std.fmt.allocPrint(arena, "poller {s} 0 True\nconnect {s} 1\n", .{ granted, granted }), listen_only);
    const connect_only = try runGuest(temporary.dir, arena, try std.fmt.allocPrint(arena, "--restrict --allow-endpoint={s}", .{granted}), &.{ "poller", granted, "listen", granted, "connect", granted });
    try testing.expectEqualStrings(try std.fmt.allocPrint(arena, "poller {s} 1\nlisten {s} 1\nconnect {s} 3\n", .{ granted, granted, granted }), connect_only);
}

// FR5a: `IP:0` is granted only by `--allow-listen=IP:0` and only to a poller, which reports the port the kernel chose;
// a blocking listener cannot report it and a connect to port 0 reaches nothing, so both are refused.
test "a run-time IP:0 listens through a poller under --allow-listen=IP:0 and nowhere else" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const fixed = try at(arena, try freePort());
    try buildGuest(temporary.dir, arena, 1);
    const zero = "127.0.0.1:0";
    const granted = try runGuest(temporary.dir, arena, "--restrict --allow-listen=127.0.0.1:0", &.{ "poller", zero, "listen", zero, "poller", fixed });
    try testing.expectEqualStrings(try std.fmt.allocPrint(arena, "poller {s} 0 True\nlisten {s} 2\npoller {s} 2\n", .{ zero, zero, fixed }), granted);
    const everything = try runGuest(temporary.dir, arena, "", &.{ "poller", zero, "listen", zero, "connect", zero });
    try testing.expectEqualStrings(try std.fmt.allocPrint(arena, "poller {s} 0 True\nlisten {s} 2\nconnect {s} 3\n", .{ zero, zero, zero }), everything);
}

// FR5a: without `--restrict` every address is granted, so a malformed one fails as an endpoint nobody answers on (3):
// the grammar is the one `--allow-endpoint` and `net.host` share, with nothing after the port.
test "without --restrict a run-time address reaches anything well formed and nothing malformed" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const closed = try at(arena, try freePort());
    try buildGuest(temporary.dir, arena, 1);
    const ran = try runGuest(temporary.dir, arena, "", &.{ "poller", "127.0.0.1:0", "connect", closed, "connect", "localhost:80", "connect", "127.0.0.1:80 ", "connect", " 127.0.0.1:80", "connect", "127.0.0.1:+80", "connect", "[::1]:80", "connect", "127.0.0.1:65536" });
    try testing.expectEqualStrings(try std.fmt.allocPrint(arena,
        \\poller 127.0.0.1:0 0 True
        \\connect {s} 3
        \\connect localhost:80 3
        \\connect 127.0.0.1:80  3
        \\connect  127.0.0.1:80 3
        \\connect 127.0.0.1:+80 3
        \\connect [::1]:80 3
        \\connect 127.0.0.1:65536 3
        \\
    , .{closed}), ran);
}

// FR5a: a Network narrowed with `net.host` stays narrow. An address other than the narrowing's is refused with 2, even
// when the launch grants every address, where before the narrowing's address was used in its place; the narrowing's own
// address is reached.
test "connect_to through a net.host narrowing reaches only the narrowing's address" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const address: net.IpAddress = .{ .ip4 = .loopback(0) };
    var listener = try address.listen(testing.io, .{});
    defer listener.deinit(testing.io);
    const port = listener.socket.address.getPort();
    const pinned = try at(arena, port);
    const elsewhere = try at(arena, try freePort());
    try buildGuest(temporary.dir, arena, port);
    const ran = try runGuest(temporary.dir, arena, "", &.{ "narrowed", pinned, "narrowed", elsewhere, "connect", elsewhere });
    try testing.expectEqualStrings(try std.fmt.allocPrint(arena, "connect {s} 0\nconnect {s} 2\nconnect {s} 3\n", .{ pinned, elsewhere, elsewhere }), ran);
}
