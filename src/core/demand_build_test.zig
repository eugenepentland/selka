//! Demand body omission must preserve the full builder's IR, LLVM and warnings.
const std = @import("std");
const stage_loss = @import("stage_loss_test_support.zig");
const frontend = @import("frontend.zig");
const build = @import("build.zig");
const lowering = @import("lowering_cache.zig");
const demand = @import("lowering_demand.zig");
const stage = @import("stage_store.zig");
const ir = @import("ir.zig");
const emit = @import("emit_llvm.zig");
const support = @import("test_support.zig");
const report = std.debug.print;

const Work = struct { omitted: usize, checked: usize, reused: usize, lowered: usize, warnings: usize, retried: bool, attempt: build.CachedError!void };

fn firstLine(_: *const anyopaque, span: u32) emit.Location {
    return .{ .line = 1, .column = span + 1 };
}

fn sameModule(a: std.mem.Allocator, actual: *const ir.Module, expected: *const ir.Module) !void {
    try support.verified(a, actual, &.{});
    try std.testing.expectEqual(expected.entry, actual.entry);
    try std.testing.expectEqualDeep(expected.compounds.items, actual.compounds.items);
    try std.testing.expectEqualDeep(expected.strings.items, actual.strings.items);
    try std.testing.expectEqual(expected.functions.items.len, actual.functions.items.len);
    for (expected.functions.items, actual.functions.items) |left, right| {
        try std.testing.expectEqualStrings(left.name, right.name);
        try std.testing.expectEqualDeep(left.signature, right.signature);
        try std.testing.expectEqual(left.span, right.span);
        try std.testing.expectEqualDeep(left.insts.items, right.insts.items);
        try std.testing.expectEqualDeep(left.extra.items, right.extra.items);
        try std.testing.expectEqualDeep(left.loops.items, right.loops.items);
        try std.testing.expectEqual(left.blocks.items.len, right.blocks.items.len);
        for (left.blocks.items, right.blocks.items) |l, r| {
            try std.testing.expectEqualDeep(l.insts.items, r.insts.items);
            try std.testing.expectEqualDeep(l.preds.items, r.preds.items);
        }
    }
    const context: u8 = 0;
    const options: emit.Options = .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = "main.my", .main = .{ .parameters = &.{"out"} } };
    try std.testing.expectEqualStrings(try emit.emitModule(a, expected, options), try emit.emitModule(a, actual, options));
}

fn check(session: *frontend.Session, a: std.mem.Allocator) !frontend.Checked {
    var diagnostics: std.ArrayList(u8) = .empty;
    return session.check(a, "main", &diagnostics) catch |err| {
        report("demand fixture: {s}\n", .{diagnostics.items});
        return err;
    };
}

fn compare(backing: std.mem.Allocator, directory: *std.testing.TmpDir, corrupt_after_check: bool) !Work {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const cache_root = try std.fs.path.join(a, &.{ root, "cache" });
    var store = try stage.Store.init(backing, std.testing.io, cache_root);
    defer store.deinit();
    var proof = try demand.Context.init(a, &store, try std.fs.path.join(a, &.{ root, "main.my" }), false);
    var session = frontend.Session.init(backing, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(backing, cache_root);
    session.configureDemand(proof.callback());
    const checked = try check(&session, a);
    const state = session.demandState().?;
    proof.attach(state.prepared, state.omitted);
    var omitted: usize = 0;
    for (state.omitted) |value| omitted += @intFromBool(value);
    const warnings = try session.warnings(a);
    // Admission has already happened, so this exercises an omitted artifact
    // failing during replay, rather than merely a missing receipt at admission.
    if (corrupt_after_check) try std.testing.expect(try stage_loss.damage(&store) > 0);
    var lower = lowering.Cache.init(&store);
    lower.demand = &proof;
    var refusal: build.Refusal = .{};
    var retried = false;
    var retry_session = frontend.Session.init(backing, std.testing.io, root);
    defer retry_session.deinit();
    const attempted = build.buildExecutableCached(a, .{ .program = checked.program, .source = checked.src }, &refusal, &lower);
    const attempt: build.CachedError!void = if (attempted) |_| {} else |err| err;
    const actual = attempted catch |err| switch (err) {
        error.CacheMiss => blk: {
            retried = true;
            try retry_session.enableCache(backing, cache_root);
            const full = try check(&retry_session, a);
            var retry_proof = try demand.Context.init(a, &store, try std.fs.path.join(a, &.{ root, "main.my" }), false);
            const full_state = retry_session.demandState().?;
            retry_proof.attach(full_state.prepared, &.{});
            lower.demand = &retry_proof;
            const complete = try build.buildExecutableCached(a, .{ .program = full.program, .source = full.src }, &refusal, &lower);
            try retry_proof.finish();
            lower.demand = null;
            break :blk complete;
        },
        else => return err,
    };
    if (!retried) try proof.finish();
    var fresh_session = frontend.Session.init(backing, std.testing.io, root);
    defer fresh_session.deinit();
    const fresh = try check(&fresh_session, a);
    const expected = try build.buildExecutable(a, .{ .program = fresh.program, .source = fresh.src }, &refusal);
    try sameModule(a, &actual, &expected);
    try std.testing.expectEqualStrings(try fresh_session.warnings(a), warnings);
    if (retried) try std.testing.expectEqualStrings(warnings, try retry_session.warnings(a));
    return .{ .omitted = omitted, .checked = session.statistics().checked, .reused = lower.reused, .lowered = lower.lowered, .warnings = warnings.len, .retried = retried, .attempt = attempt };
}

const main_source = "import lib\n\nfunc main(out: Stream) -> int:\n    out.print(lib.change(4), lib.keep(5))\n    return 0\n";
const library = "public func change(x: int) -> int:\n    return x + 1\n\npublic func keep(x: int) -> int:\n    return x * 2\n";

fn fixture(directory: *std.testing.TmpDir, lib: []const u8) !void {
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = main_source });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data = lib });
}

// spec: NEW-CORE-DEMAND-1
test "demand lowering omits unchanged bodies and only lowers the edited function" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try fixture(&directory, library);
    const cold = try compare(std.testing.allocator, &directory, false);
    try std.testing.expectEqual(@as(usize, 0), cold.omitted);
    const warm = try compare(std.testing.allocator, &directory, false);
    try std.testing.expectEqual(@as(usize, 2), warm.omitted);
    try std.testing.expect(warm.checked <= 1);
    try std.testing.expectEqual(@as(usize, 3), warm.reused);
    try std.testing.expectEqual(@as(usize, 0), warm.lowered);
    try fixture(&directory, "public func change(x: int) -> int:\n    return x + 9\n\npublic func keep(x: int) -> int:\n    return x * 2\n");
    const edited = try compare(std.testing.allocator, &directory, false);
    try std.testing.expectEqual(@as(usize, 1), edited.omitted);
    try std.testing.expectEqual(@as(usize, 1), edited.checked);
    try std.testing.expectEqual(@as(usize, 1), edited.lowered);
    try std.testing.expect(!edited.retried);
    const stable = try compare(std.testing.allocator, &directory, false);
    try std.testing.expectEqual(@as(usize, 2), stable.omitted);
}

// spec-case: NEW-CORE-DEMAND-1
test "demand replay relocates shifted bodies and fails safe after catalog changes" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try fixture(&directory, library);
    _ = try compare(std.testing.allocator, &directory, false);
    try fixture(&directory, "\n\npublic func change(x: int) -> int:\n    return x + 10000\n\npublic func keep(x: int) -> int:\n    return x * 2\n");
    const shifted = try compare(std.testing.allocator, &directory, false);
    try std.testing.expectEqual(@as(usize, 1), shifted.omitted);
    try std.testing.expect(shifted.lowered <= 2);
    try fixture(&directory, "record Earlier:\n    value: int\nfunc unused() -> int:\n    return 9\n\n" ++ library);
    _ = try compare(std.testing.allocator, &directory, false);
    _ = try compare(std.testing.allocator, &directory, false);
    try fixture(&directory, "public func change(x: int) -> int:\n    return added(x)\n\nfunc added(x: int) -> int:\n    return x + 3\n\npublic func keep(x: int) -> int:\n    return x * 2\n");
    _ = try compare(std.testing.allocator, &directory, false);
    try fixture(&directory, library);
    _ = try compare(std.testing.allocator, &directory, false);
}

// spec-case: NEW-CORE-DEMAND-1
test "demand artifact loss after admission retries complete checking" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try fixture(&directory, library);
    _ = try compare(std.testing.allocator, &directory, false);
    const lost = try compare(std.testing.allocator, &directory, true);
    try std.testing.expectError(error.CacheMiss, lost.attempt);
    try std.testing.expectEqual(@as(usize, 2), lost.omitted);
    try std.testing.expect(lost.retried);
    _ = try compare(std.testing.allocator, &directory, false);
}

// spec-case: NEW-CORE-DEMAND-1
test "demand omission preserves moved warnings and changed effect facts" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const warning_library = "public func change(x: int) -> int:\n    return x + 1\n\npublic func keep(x: int) -> int:\n    mut unused = 41\n    return x * 2\n";
    try fixture(&directory, warning_library);
    try std.testing.expect((try compare(std.testing.allocator, &directory, false)).warnings > 0);
    try fixture(&directory, "\n\n" ++ warning_library);
    try std.testing.expect((try compare(std.testing.allocator, &directory, false)).omitted > 0);
    try fixture(&directory, library);
    _ = try compare(std.testing.allocator, &directory, false);
    try fixture(&directory, "public func change(x: int) -> int:\n    mut xs: int[] = [x]\n    return xs[0] + 1\n\npublic func keep(x: int) -> int:\n    return x * 2\n");
    _ = try compare(std.testing.allocator, &directory, false);
}

// spec-case: NEW-CORE-DEMAND-1
test "demand receipts reuse unchanged external default origins and reject edited sources" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const defaults = "public record Item:\n    value: int = 42\n";
    const source = "import defaults\n\npublic func change(x: int) -> int:\n    return defaults.Item().value + x\n\npublic func keep(x: int) -> int:\n    return x * 2\n";
    try fixture(&directory, source);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "defaults.my", .data = defaults });
    _ = try compare(std.testing.allocator, &directory, false);
    const warm = try compare(std.testing.allocator, &directory, false);
    try std.testing.expectEqual(@as(usize, 2), warm.omitted);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "defaults.my", .data = "\n\n" ++ defaults });
    try std.testing.expectEqual(@as(usize, 1), (try compare(std.testing.allocator, &directory, false)).omitted);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "defaults.my", .data = "\n\npublic record Item:\n    value: int = 43\n" });
    try std.testing.expectEqual(@as(usize, 1), (try compare(std.testing.allocator, &directory, false)).omitted);
}

// spec-case: NEW-CORE-DEMAND-1
// spec-case: NEW-CORE-STAGE-CACHE-3
test "demand literal growth before a lambda preserves independent raw bodies without fallback" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const with_lambda =
        \\public func change(x: int) -> int:
        \\    return x + 1
        \\
        \\func apply(f: func(int) -> int, x: int) -> int:
        \\    return f(x)
        \\
        \\public func keep(x: int) -> int:
        \\    return apply(lambda n: n * 2, x)
        \\
    ;
    try fixture(&directory, with_lambda);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = "import lib\nimport idle\n\nfunc main(out: Stream) -> int:\n    out.print(lib.change(4), lib.keep(5), idle.stable(9))\n    return 0\n" });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "idle.my", .data = "public func stable(x: int) -> int:\n    return x * 3\n" });
    _ = try compare(std.testing.allocator, &directory, false);
    const grown_library = try std.mem.replaceOwned(u8, std.testing.allocator, with_lambda, "x + 1", "x + 10000");
    defer std.testing.allocator.free(grown_library);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data = grown_library });
    const grown = try compare(std.testing.allocator, &directory, false);
    try std.testing.expect(!grown.retried);
    try std.testing.expect(grown.omitted >= 1);
    try std.testing.expect(grown.reused >= 2);
    const second_library = try std.mem.replaceOwned(u8, std.testing.allocator, with_lambda, "x + 1", "x + 100000000");
    defer std.testing.allocator.free(second_library);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data = second_library });
    const grown_again = try compare(std.testing.allocator, &directory, false);
    try std.testing.expect(!grown_again.retried);
    try std.testing.expect(grown_again.omitted >= 1);
    try std.testing.expect(grown_again.reused >= 2);
    const repeated = try compare(std.testing.allocator, &directory, false);
    try std.testing.expect(!repeated.retried);
}

// spec: FRONTEND-UNREACHABLE-1
// spec-case: NEW-CORE-DEMAND-1
test "demand omits proven unreachable functions and retries when an omitted body becomes reachable" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const extra = library ++ "\npublic func dormant(x: int) -> int:\n    return x + 3\n";
    try fixture(&directory, extra);
    _ = try compare(std.testing.allocator, &directory, false);
    const warm = try compare(std.testing.allocator, &directory, false);
    try std.testing.expectEqual(@as(usize, 3), warm.omitted);
    try std.testing.expectEqual(@as(usize, 0), warm.lowered);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = "import lib\n\nfunc main(out: Stream) -> int:\n    out.print(lib.change(4), lib.keep(5), lib.dormant(6))\n    return 0\n" });
    const reachable = try compare(std.testing.allocator, &directory, false);
    try std.testing.expectError(error.CacheMiss, reachable.attempt);
    try std.testing.expect(reachable.retried);
    const restored = try compare(std.testing.allocator, &directory, false);
    try std.testing.expect(!restored.retried);
    try std.testing.expect(restored.reused >= 3);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data = library ++ "\npublic func dormant(x: int) -> int:\n    return x + 30000\n" });
    const edited = try compare(std.testing.allocator, &directory, false);
    try std.testing.expect(!edited.retried);
    try std.testing.expect(edited.omitted >= 2);
    try std.testing.expect(edited.reused >= 2);
}

// spec-case: NEW-CORE-DEMAND-1
test "demand managed byte constant length changes preserve other modules without fallback" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const bytes_library =
        \\const usage: bytes = b"usage"
        \\
        \\public func change(x: int) -> int:
        \\    return x + len(usage)
        \\
        \\public func keep(x: int) -> int:
        \\    return x * 2
        \\
    ;
    try fixture(&directory, bytes_library);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = "import lib\nimport idle\n\nfunc main(out: Stream) -> int:\n    out.print(lib.change(4), lib.keep(5), idle.stable(9))\n    return 0\n" });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "idle.my", .data = "public func stable(x: int) -> int:\n    return x * 3\n" });
    _ = try compare(std.testing.allocator, &directory, false);
    const first = try std.mem.replaceOwned(u8, std.testing.allocator, bytes_library, "b\"usage\"", "b\"longer usage text\"");
    defer std.testing.allocator.free(first);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data = first });
    const grown = try compare(std.testing.allocator, &directory, false);
    try std.testing.expect(!grown.retried);
    try std.testing.expect(grown.omitted >= 2);
    try std.testing.expect(grown.reused >= 2);
    const second = try std.mem.replaceOwned(u8, std.testing.allocator, bytes_library, "b\"usage\"", "b\"an even longer usage message\"");
    defer std.testing.allocator.free(second);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data = second });
    const grown_again = try compare(std.testing.allocator, &directory, false);
    try std.testing.expect(!grown_again.retried);
    try std.testing.expect(grown_again.omitted >= 2);
    try std.testing.expect(grown_again.reused >= 2);
}

// spec-case: NEW-CORE-DEMAND-1
test "demand replay preserves nested generic type suffixes after a body shifts" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const nested_library =
        \\public func change(x: int) -> int:
        \\    return x + 1
        \\
        \\func count[T](items: T[]?) -> int:
        \\    match items:
        \\        case Some(values):
        \\            return len(values)
        \\        case None:
        \\            return 0
        \\
        \\public func keep(x: int) -> int:
        \\    mut items: int[]? = Some([x, x + 2])
        \\    return count(items)
        \\
    ;
    try fixture(&directory, nested_library);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = "import lib\nimport idle\n\nfunc main(out: Stream) -> int:\n    out.print(lib.change(4), lib.keep(5), idle.stable(9))\n    return 0\n" });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "idle.my", .data = "public func stable(x: int) -> int:\n    return x * 3\n" });
    _ = try compare(std.testing.allocator, &directory, false);
    const warm = try compare(std.testing.allocator, &directory, false);
    try std.testing.expect(!warm.retried);
    try std.testing.expect(warm.omitted >= 1);
    const shifted_library = try std.mem.replaceOwned(u8, std.testing.allocator, nested_library, "x + 1", "x + 10000");
    defer std.testing.allocator.free(shifted_library);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data = shifted_library });
    const shifted = try compare(std.testing.allocator, &directory, false);
    try std.testing.expect(!shifted.retried);
    try std.testing.expect(shifted.omitted >= 1);
    try std.testing.expect(shifted.reused >= 1);
}
