//! Capability ABI and copied provider payload regression tests.
const std = @import("std");
const support = @import("test_support.zig");
const language = @import("selka");
const build = @import("build.zig");
const print = @import("print.zig");
const ir = @import("ir.zig");
const options = @import("core_test_options");

const raw_environment =
    \\record Entry:
    \\    present: bool
    \\    bytes: FixedArray[u8, 4]
    \\    length: u64
    \\
    \\result Lookup:
    \\    err: int,
    \\    ok: Entry
    \\
    \\func main(env: Environment) -> int:
    \\    match environment_get[Lookup](env, FixedArray[u8, 1]([75u8])):
    \\        case ok(entry):
    \\            return int(entry.length)
    \\        case err(code):
    \\            return -code
;

// spec-case: NEW-CORE-S3-ABI-1
test "Core raw environment payload follows named field order and copies fixed octets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try trustedIrText(arena.allocator(), raw_environment);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_environment_raw") != null);
    try std.testing.expect(std.mem.count(u8, text, "list_get") == 4);
}

// spec-case: NEW-CORE-S3-ABI-1
test "Core Host extern authority is checked before its scalar erasing call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(),
        \\extern func identity(host: Host, value: int) -> int
        \\
        \\func main(host: Host) -> int:
        \\    return identity(host, 42)
    );
    const check = std.mem.indexOf(u8, text, "myl_core_host_check").?;
    const call = std.mem.indexOf(u8, text, "call i64 identity").?;
    try std.testing.expect(check < call);
}

// A plain `bytes` parameter given to a resource write: the connection's request is built from the view, so the
// octets are written in place. Without the view form the request was refused ("resource request type").
const resource_write =
    \\import network
    \\
    \\func send(mut connection: network.Connection, data: bytes) -> int:
    \\    match write_resource[network.Written](connection, data):
    \\        case ok(count):
    \\            return int(count)
    \\        case err(code):
    \\            return -code
    \\
    \\func main(net: Network, out: Stream) -> int:
    \\    with net.host("127.0.0.1:1") as scoped:
    \\        match network.connect(scoped):
    \\            case ok(connection):
    \\                mut live = own connection
    \\                return send(mut live, b"ab")
    \\            case err(code):
    \\                print(out, code)
    \\    return 0
;

// spec-case: NEW-CORE-C9-BYTES-2
test "a resource write of a plain bytes parameter is a span write: the request builds and no copy of the octets is made" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(arena.allocator(), resource_write, &refusal);
    const text = try print.module(arena.allocator(), &module);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_span_resource_write") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_view_copy_bytes") == null);
}

fn trustedIrText(arena: std.mem.Allocator, source: []const u8) ![]u8 {
    var unit = try language.Compilation.initTrusted(arena, "cap_fixture.selka", source);
    try unit.check();
    var refusal: build.Refusal = .{};
    const module = try build.buildModule(arena, unit.program.?, &refusal);
    try support.verified(arena, &module, &.{});
    return print.module(arena, &module);
}

// spec-case: NEW-CORE-S3-ABI-1
test "Core literal network narrowing copies fixed octets into a verified pointer call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(),
        \\func main(net: Network) -> int:
        \\    with net.host("127.0.0.1:1234") as scoped_endpoint:
        \\        _ = scoped_endpoint
        \\        return 0
    );
    try std.testing.expect(std.mem.indexOf(u8, text, "fn myl_core_cap_host(cap, bytes) -> cap") != null);
    try std.testing.expectEqual(@as(usize, 14), std.mem.count(u8, text, "array_get"));
}

fn nestedScopeOrder(a: std.mem.Allocator) !void {
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a,
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("first", "r") as first:
        \\        with fs.open("second", "r") as second:
        \\            return 0
    , &refusal);
    var opened: std.ArrayList(ir.Ref) = .empty;
    var closed: std.ArrayList(ir.Ref) = .empty;
    var returns: usize = 0;
    for (module.functions.items) |function| {
        if (function.signature.linkage != .internal) continue;
        for (function.blocks.items) |block| {
            for (block.insts.items) |ref| {
                const instruction = function.inst(ref);
                if (instruction.op == .ret) {
                    try std.testing.expectEqual(@as(usize, 2), closed.items.len);
                    returns += 1;
                }
                if (instruction.op != .call) continue;
                const callee = module.functions.items[instruction.a.index()];
                // The path is a span form when it is text (`build.span_redirects`): both names open a file.
                const file_access = std.mem.eql(u8, callee.name, "myl_core_file_access") or std.mem.eql(u8, callee.name, "myl_core_span_file_access");
                if (file_access and instruction.ty == .resource) try opened.append(a, ref);
                if (!std.mem.eql(u8, callee.name, "myl_core_owned_file_scope_end")) continue;
                try std.testing.expectEqual(@as(usize, 0), returns);
                try std.testing.expectEqual(.runtime_c, callee.signature.linkage);
                try std.testing.expectEqual(.void, callee.signature.ret);
                const arguments = function.operands(instruction.data);
                try std.testing.expectEqual(@as(usize, 2), arguments.len);
                const provider = function.inst(function.resolve(arguments[1]));
                try std.testing.expectEqual(ir.Op.param, provider.op);
                try std.testing.expectEqual(@as(u64, 0), provider.data);
                try closed.append(a, function.resolve(arguments[0]));
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 2), opened.items.len);
    try std.testing.expectEqual(@as(usize, 2), closed.items.len);
    try std.testing.expectEqual(@as(usize, 1), returns);
    try std.testing.expectEqual(opened.items[1], closed.items[0]);
    try std.testing.expectEqual(opened.items[0], closed.items[1]);
}

// spec-case: NEW-CORE-S3-ABI-1
test "Core nested file scopes close in reverse order before return" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nestedScopeOrder(arena.allocator());
}

fn builtinEnvironmentDenial(a: std.mem.Allocator) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "input.txt", .data = "inside" });
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try std.fmt.allocPrint(a, "{s}/c_grants.selka", .{options.fixtures});
    const binary = try std.fs.path.join(a, &.{ root, "grants" });
    var environment = std.process.Environ.Map.init(a);
    try environment.put("SELKA_OPTIONS", "--allow-env=IGNORED --allow-random=7");
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    try environment.put("KEEP", "visible");
    for ([_][]const []const u8{ &.{}, &.{ "--release", "--verify-facts" } }) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "-o", binary, "--cache-dir", try options.suiteCache(a, @src()) });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const result = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .cwd = .{ .path = root }, .environ_map = &environment });
        try std.testing.expect(result.term == .exited and result.term.exited == 1);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "inside\n") != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "visible") == null);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "error[R_CAPABILITY]") != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leakcheck:") == null);
    }
}

// spec-case: NEW-CORE-S3-ABI-1
test "Core built-in Environment reads preserve explicit allowlists without restrict" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try builtinEnvironmentDenial(arena.allocator());
}

const lent_entry =
    \\func main(args: str[], fs: Filesystem, out: Stream) -> int:
    \\    match fs.read_file("input.txt"):
    \\        case Ok(data):
    \\            print(out, f"{len(data)} {len(args)}")
    \\        case Err(_):
    \\            pass
    \\    return 0
    \\
;

/// The C entry `selka build --emit-llvm` writes for `source`: from `define i32 @main(`
/// to the end of the module.
fn entryLlvm(a: std.mem.Allocator, root: []const u8, source: []const u8) ![]const u8 {
    const llvm = try std.fs.path.join(a, &.{ root, "entry.ll" });
    const binary = try std.fs.path.join(a, &.{ root, "entry" });
    const argv = [_][]const u8{ options.corePath(), "build", source, "-o", binary, "--emit-llvm", llvm, "--cache-dir", try options.suiteCache(a, @src()) };
    const built = try std.process.run(a, std.testing.io, .{ .argv = &argv });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, llvm, a, .limited(64 << 20));
    return text[std.mem.indexOf(u8, text, "define i32 @main(").?..];
}

fn entryReleases(a: std.mem.Allocator) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lent.selka", .data = lent_entry });
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const taken = try entryLlvm(a, root, try std.fmt.allocPrint(a, "{s}/c_entry_own.selka", .{options.fixtures}));
    // A capability is a scalar handle (5C): the entry grants it and destroys nothing after `main`, whether `main` takes it
    // or borrows it; the runtime's table holds its provider until the process ends.
    try std.testing.expect(std.mem.indexOf(u8, taken, "%cap1 = call i64 @myl_core_cap_grant(") != null);
    try std.testing.expect(std.mem.indexOf(u8, taken, "%cap2 = call i64 @myl_core_cap_grant(") != null);
    try std.testing.expect(std.mem.indexOf(u8, taken, "@myl_core_drop_owned(ptr %cap") == null);
    try std.testing.expect(std.mem.indexOf(u8, taken, "@myl_core_drop_owned(ptr %args)") == null);
    const lent = try entryLlvm(a, root, try std.fs.path.join(a, &.{ root, "lent.selka" }));
    try std.testing.expect(std.mem.indexOf(u8, lent, "%cap1 = call i64 @myl_core_cap_grant(") != null);
    try std.testing.expect(std.mem.indexOf(u8, lent, "@myl_core_drop_owned(ptr %cap") == null);
    try std.testing.expect(std.mem.indexOf(u8, lent, "@myl_core_drop_owned(ptr %args)") != null);
}

test "the C entry grants capability handles and destroys none after main, taken or borrowed (F-G2b-34, 5C)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try entryReleases(arena.allocator());
}

/// A `main` that declares a `Stop` beside a Stream, and the same `main` without it.
const stop_entry =
    \\import process
    \\
    \\func main(out: Stream, stop: Stop) -> int:
    \\    print(out, process.stop_requested(stop))
    \\    return 0
    \\
;
const no_stop_entry =
    \\func main(out: Stream) -> int:
    \\    print(out, False)
    \\    return 0
    \\
;

fn stopEntry(a: std.mem.Allocator) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "stop.selka", .data = stop_entry });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "plain.selka", .data = no_stop_entry });
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const heard = try entryLlvm(a, root, try std.fs.path.join(a, &.{ root, "stop.selka" }));
    try std.testing.expect(std.mem.indexOf(u8, heard, "%stop1 = call i64 @myl_core_stop_listen()") != null);
    try std.testing.expect(std.mem.indexOf(u8, heard, "i64 1, i64 %stop1)") != null);
    const plain = try entryLlvm(a, root, try std.fs.path.join(a, &.{ root, "plain.selka" }));
    try std.testing.expect(std.mem.indexOf(u8, plain, "myl_core_stop_") == null);
}

test "the C entry installs the stop handler only for a main that declares a Stop, and hands main handle 0's call (FR5b)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try stopEntry(arena.allocator());
}

fn ownedEntryRuns(a: std.mem.Allocator) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "input.txt", .data = "inside" });
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try std.fmt.allocPrint(a, "{s}/c_entry_own.selka", .{options.fixtures});
    const binary = try std.fs.path.join(a, &.{ root, "entry_own" });
    var environment = std.process.Environ.Map.init(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    for ([_][]const []const u8{ &.{}, &.{ "--release", "--verify-facts" } }) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "-o", binary, "--cache-dir", try options.suiteCache(a, @src()) });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        // Before the fix the entry freed the grants a second time and 20 of 20 runs of
        // this program aborted; one clean run is not enough evidence, so run it twenty times.
        for (0..20) |_| {
            const result = try std.process.run(a, std.testing.io, .{ .argv = &.{ binary, "first", "second" }, .cwd = .{ .path = root }, .environ_map = &environment });
            try std.testing.expect(result.term == .exited and result.term.exited == 0);
            try std.testing.expectEqualStrings("read 6 bytes in 1 call with 2 arguments\n", result.stdout);
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leakcheck:") == null);
        }
    }
}

test "a main that takes its capabilities and arguments with own runs and exits cleanly every time (F-G2b-34)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try ownedEntryRuns(arena.allocator());
}
