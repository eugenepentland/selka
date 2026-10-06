//! Capability ABI and copied provider payload regression tests.
const std = @import("std");
const support = @import("test_support.zig");
const language = @import("mylang");
const build = @import("build.zig");
const print = @import("print.zig");
const ir = @import("ir.zig");
const options = @import("core_test_options");

const raw_environment =
    \\record Entry:
    \\    present: bool
    \\    bytes: [4]u8
    \\    length: u64
    \\
    \\result Lookup:
    \\    err: int,
    \\    ok: Entry
    \\
    \\def main(env: Environment) -> int:
    \\    match environment_get[Lookup](env, [75u8]):
    \\        case Lookup.ok(entry):
    \\            return int(entry.length)
    \\        case Lookup.err(code):
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
        \\extern def identity(host: Host, value: int) -> int effects(host)
        \\
        \\def main(host: Host) -> int:
        \\    return identity(host, 42)
    );
    const check = std.mem.indexOf(u8, text, "myl_core_host_check").?;
    const call = std.mem.indexOf(u8, text, "call i64 identity").?;
    try std.testing.expect(check < call);
}

// spec-case: NEW-CORE-S3-ABI-1
test "Core copied Host aggregate calls keep the runtime token out of value payloads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(),
        \\record Pair:
        \\    number: int
        \\    small: u8
        \\
        \\host def echo(host: Host, value: Pair) -> Pair effects(host)
        \\
        \\def main(host: Host) -> int:
        \\    return echo(host, Pair(number=42, small=7u8)).number
    );
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_host_invoke") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "box_make") != null);
}

fn trustedIrText(arena: std.mem.Allocator, source: []const u8) ![]u8 {
    var unit = try language.Compilation.initTrusted(arena, "cap_fixture.my", source);
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
        \\def main(net: Network) -> int:
        \\    _ = net.host("127.0.0.1:1234")
        \\    return 0
    );
    try std.testing.expect(std.mem.indexOf(u8, text, "fn myl_core_cap_host(capability, bytes)") != null);
    try std.testing.expectEqual(@as(usize, 14), std.mem.count(u8, text, "array_get"));
}

fn nestedScopeOrder(a: std.mem.Allocator) !void {
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a,
        \\def main(fs: Filesystem) -> int:
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
                if (std.mem.eql(u8, callee.name, "myl_core_file_access") and instruction.ty == .resource) try opened.append(a, ref);
                if (!std.mem.eql(u8, callee.name, "myl_core_file_scope_close")) continue;
                try std.testing.expectEqual(@as(usize, 0), returns);
                try std.testing.expectEqual(.runtime_c, callee.signature.linkage);
                try std.testing.expectEqual(.void, callee.signature.ret);
                const arguments = function.operands(instruction.data);
                try std.testing.expectEqual(@as(usize, 1), arguments.len);
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
    const source = try std.fmt.allocPrint(a, "{s}/c_grants.my", .{options.fixtures});
    const binary = try std.fs.path.join(a, &.{ root, "grants" });
    var environment = std.process.Environ.Map.init(a);
    try environment.put("MYLANG_OPTIONS", "--allow-env=IGNORED --allow-random=7");
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    try environment.put("KEEP", "visible");
    for ([_][]const []const u8{ &.{}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "build", source, "-o", binary, "--cache-dir", root });
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
