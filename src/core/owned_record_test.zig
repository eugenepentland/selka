//! Whole fielded patterns consume fresh payload records without partial-move state.
const std = @import("std");
const language = @import("mylang");
const contract = @import("single_owner.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

fn checked(a: std.mem.Allocator, source: []const u8) !language.typed.Program {
    var unit = try language.Compilation.init(a, "zero-rc.my", source);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |diagnostic| report("{s} at {d}: {s}\n", .{ diagnostic.code, diagnostic.span.start, diagnostic.message });
        return err;
    };
    return unit.program.?;
}

fn refuses(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.checkMode(arena.allocator(), try checked(arena.allocator(), source), &failure, true));
    try std.testing.expectEqualStrings(code, failure.code);
}

fn executes(parent: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a, source);
    var failure: contract.Failure = .{};
    contract.checkMode(a, program, &failure, true) catch |err| {
        report("zero-RC source: {s} at {d}\n", .{ failure.message, failure.span.start });
        return err;
    };
    const main_fn = program.functions[@backingInt(program.main)];
    const parameter_names = try a.alloc([]const u8, main_fn.signature.parameter_count);
    const capabilities = try a.alloc(u8, parameter_names.len);
    for (parameter_names, capabilities, main_fn.scope.locals[0..parameter_names.len]) |*name, *cap, local| {
        name.* = local.name;
        cap.* = local.ty.capabilityIndex() orelse 255;
    }
    inline for (.{ false, true }) |optimized| {
        var refusal: build.Refusal = .{};
        var module = build.buildExecutable(a, .{ .program = program, .single_owner = true, .zero_rc = true }, &refusal) catch |err| {
            report("zero-RC builder: {s}\n", .{refusal.reason});
            return err;
        };
        const result = if (optimized) try passes.run(a, &module, .verify) else try passes.debug(a, &module);
        contract.verifyLowered(&module, &failure) catch |err| {
            report("zero-RC lowering: {s} at {d}\n{s}\n", .{ failure.message, failure.span.start, try @import("print.zig").module(a, &module) });
            return err;
        };
        const run = support.runOwned(a, &module, .{ .own = false, .release = optimized, .verify = optimized, .analysis = support.analysis(&result), .main = .{ .parameters = parameter_names, .capabilities = capabilities } }) catch |err| {
            report("zero-RC execution (optimized={}):\n{s}\n", .{ optimized, try @import("print.zig").module(a, &module) });
            return err;
        };
        if (run.status != 0) report("zero-RC run:\n{s}{s}\n", .{ run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings(expected, run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(zero.emittedClean(run.llvm));
    }
}

// spec: NEW-CORE-ZERO-RC-RECORD-UNPACK-1
test "zero RC record unpack moves fields and drops ignored and unused owners" {
    try executes(std.testing.allocator,
        \\enum Bundle:
        \\    parts(left: str[], right: str[], ignored: str[], unused: str[])
        \\record Pair:
        \\    left: str[]
        \\    right: str[]
        \\func make(n: int) -> Bundle:
        \\    return Bundle.parts(left=["left-" + str(n)], right=["right-" + str(n)], ignored=["drop-" + str(n)], unused=["unused-" + str(n)])
        \\func split(n: int) -> Pair:
        \\    match make(n):
        \\        case Bundle.parts(left=a, right=b, ignored=_, unused=unused):
        \\            return Pair(left=a, right=b)
        \\func discard(n: int):
        \\    match make(n):
        \\        case Bundle.parts(left=_, right=_, ignored=_, unused=_):
        \\            pass
        \\func main(out: Stream) -> int:
        \\    for n in range(4):
        \\        const pair = split(n)
        \\        discard(n)
        \\        out.print(pair.left[0], pair.right[0])
        \\    return 0
    , "left-0 right-0\nleft-1 right-1\nleft-2 right-2\nleft-3 right-3\n");
}

// spec-case: NEW-CORE-ZERO-RC-RECORD-UNPACK-1
test "zero RC record unpack preserves wide and recursive boxed fields" {
    try executes(std.testing.allocator,
        \\enum Tree:
        \\    leaf(a: str, b: str, c: str, d: str, e: str, f: str)
        \\    node(child: Tree, discarded: Tree)
        \\func leaf(n: int) -> Tree:
        \\    return Tree.leaf(a="a" + str(n), b="b" + str(n), c="c" + str(n), d="d" + str(n), e="e" + str(n), f="f" + str(n))
        \\func make(n: int) -> Tree:
        \\    return Tree.node(child=leaf(n), discarded=leaf(n + 1))
        \\func detach(n: int) -> Tree:
        \\    match make(n):
        \\        case Tree.node(child=child, discarded=_):
        \\            const replacement = make(99)
        \\            _ = replacement
        \\            return child
        \\        case Tree.leaf(a=a, b=b, c=c, d=d, e=e, f=f):
        \\            return Tree.leaf(a=a, b=b, c=c, d=d, e=e, f=f)
        \\func first(n: int) -> str:
        \\    match detach(n):
        \\        case Tree.leaf(a=a, b=_, c=_, d=_, e=_, f=_):
        \\            return a
        \\        case Tree.node(child=_, discarded=_):
        \\            return "unexpected"
        \\func main(out: Stream) -> int:
        \\    out.print(first(7), first(8))
        \\    return 0
    , "a7 a8\n");
}

// spec-case: NEW-CORE-ZERO-RC-RECORD-UNPACK-1
test "zero RC record unpack cleans fields through propagation and loop exits" {
    try executes(std.testing.allocator,
        \\enum Job:
        \\    ready(result: Result[str, str], ignored: str[])
        \\func prepare(fail: bool) -> Job:
        \\    if fail:
        \\        return Job.ready(result=Err("failure-" + str(1)), ignored=["unused-" + str(1)])
        \\    return Job.ready(result=Ok("done-" + str(2)), ignored=["unused-" + str(2)])
        \\func run(fail: bool) -> Result[str, str]:
        \\    match prepare(fail):
        \\        case Job.ready(result=value, ignored=_):
        \\            const text = try value
        \\            return Ok(text)
        \\enum Pair:
        \\    parts(first: str[], second: str[])
        \\func select() -> str[]:
        \\    mut result: str[] = []
        \\    for n in range(3):
        \\        match Pair.parts(first=["first-" + str(n)], second=["second-" + str(n)]):
        \\            case Pair.parts(first=first, second=_):
        \\                if n == 0:
        \\                    continue
        \\                result = first
        \\                break
        \\    return result
        \\func main(out: Stream) -> int:
        \\    for n in range(2):
        \\        match run(n == 0):
        \\            case Ok(text):
        \\                out.print(text)
        \\            case Err(message):
        \\                out.print(message)
        \\    out.print(select()[0])
        \\    return 0
    , "failure-1\ndone-2\nfirst-1\n");
}

// spec-case: NEW-CORE-ZERO-RC-RECORD-UNPACK-1
test "zero RC record unpack rejects duplicate moves and borrowed field escapes" {
    const cases = [_]struct { source: []const u8, code: []const u8 }{
        .{ .source =
        \\enum Pair:
        \\    parts(left: str[], right: str[])
        \\func main() -> int:
        \\    match Pair.parts(left=["a"], right=["b"]):
        \\        case Pair.parts(left=left, right=_):
        \\            const saved = left
        \\            return len(saved) + len(left)
        , .code = "E_SINGLE_OWNER_MOVED" },
        .{ .source =
        \\enum Pair:
        \\    parts(left: str[], right: str[])
        \\func escape(pair: Pair) -> str[]:
        \\    match pair:
        \\        case Pair.parts(left=left, right=_):
        \\            return left
        \\func main() -> int:
        \\    return len(escape(Pair.parts(left=["a"], right=["b"])))
        , .code = "E_SINGLE_OWNER_OVERLAP" },
        .{ .source =
        \\enum Tree:
        \\    leaf(value: str)
        \\    node(child: Tree)
        \\func escape() -> str:
        \\    match Tree.node(child=Tree.leaf(value="nested")):
        \\        case Tree.node(child=Tree.leaf(value=value)):
        \\            return value
        \\        case Tree.node(child=Tree.node(child=_)):
        \\            return "node"
        \\        case Tree.leaf(value=_):
        \\            return "leaf"
        \\func main() -> int:
        \\    return len(escape())
        , .code = "E_SINGLE_OWNER_OVERLAP" },
        .{ .source =
        \\record Pair:
        \\    left: str[]
        \\    right: str[]
        \\func main() -> int:
        \\    const pair = Pair(left=["a"], right=["b"])
        \\    const stolen = pair.left
        \\    return len(stolen)
        , .code = "E_SINGLE_OWNER_BORROW" },
    };
    for (cases) |case| try refuses(std.testing.allocator, case.source, case.code);
}

// spec-case: NEW-CORE-ZERO-RC-RECORD-UNPACK-1
test "zero RC record unpack box transfer rejects wrong types and the RC ABI" {
    const ir = @import("ir.zig");
    const verify = @import("verify_ir.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .zero_rc = true, .single_owner = true };
    const box = try module.intern(a, .{ .box = .str });
    var h = try support.Hand.init(a, &module, "take", .{ .params = &.{box}, .ret = .str, .owned = 1 });
    const taken = try h.emit(.{ .op = .box_take, .ty = .str, .a = try h.param(0) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = taken });
    _ = try h.finish();
    var failure: verify.Failure = .{};
    try verify.verifyModule(a, &module, &failure);
    module.zero_rc = false;
    try std.testing.expectError(error.InvalidIr, verify.verifyModule(a, &module, &failure));
    module.zero_rc = true;
    module.functions.items[0].insts.items[taken.index()].ty = box;
    try std.testing.expectError(error.InvalidIr, verify.verifyModule(a, &module, &failure));
}
