//! Scalar fusion proves complete use coverage and preserves checked text behavior.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const fusion = @import("fuse_text_scalar.zig");
const options = @import("core_test_options");
const report = std.debug.print;

const selected =
    \\func scan(text: str) -> str:
    \\    mut out = ""
    \\    for ch in strings.chars(text):
    \\        if ch == "é" or "\0" == ch:
    \\            out += ch
    \\        elif ch != "🙂":
    \\            out += ch
    \\    return out
    \\func main() -> int:
    \\    return strings.char_count(scan("aé\0🙂"))
;

fn count(module: *const ir.Module, op: ir.Op) usize {
    var found: usize = 0;
    for (module.functions.items) |f| for (f.insts.items) |inst| {
        if (inst.op == op) found += 1;
    };
    return found;
}

fn checkedReads(module: *const ir.Module) !void {
    for (module.functions.items) |f| for (f.insts.items) |inst| {
        if (inst.op == .str_code) try std.testing.expect(inst.check == .exact and inst.span != 0);
    };
}

// spec-case: NEW-CORE-STR-1
test "scalar fusion shares one checked decode across literal comparisons and branch appends" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(arena.allocator(), selected, &refusal);
    try std.testing.expectEqual(@as(usize, 0), count(&module, .str_char));
    try std.testing.expectEqual(@as(usize, 1), count(&module, .str_code));
    try std.testing.expectEqual(@as(usize, 2), count(&module, .str_append_char));
    try checkedReads(&module);
}

fn handCase(a: std.mem.Allocator, bytes: []const u8, linkage: ir.Linkage) !u32 {
    var module: ir.Module = .{};
    try module.strings.append(a, bytes);
    try module.functions.append(a, .{ .name = @import("flags.zig").str_eq_symbol, .signature = .{ .params = &.{ .str, .str }, .ret = .bool, .linkage = linkage } });
    var hand = try support.Hand.init(a, &module, "main", .{ .params = &.{.str}, .ret = .i64 });
    const receiver = try hand.param(0);
    const offset = try hand.int(.u64, 0);
    const character = try hand.emit(.{ .op = .str_char, .ty = .str, .a = receiver, .b = offset, .check = .exact, .span = 9 });
    const copy = try hand.emit(.{ .op = .copy, .ty = .str, .a = character });
    const literal = try hand.loose(.{ .op = .str_const, .ty = .str });
    _ = try hand.emit(.{ .op = .call, .ty = .bool, .a = @fromBackingInt(@as(u32, 0)), .data = try hand.extra(&.{ copy, literal }) });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = try hand.int(.i64, 0) });
    const changed = try fusion.run(a, &module, &hand.function);
    try std.testing.expectEqual(if (changed == 1) ir.Type.u32 else ir.Type.str, hand.function.inst(copy).ty);
    _ = try hand.finish();
    try support.verified(a, &module, &.{});
    return changed;
}

// spec-case: NEW-CORE-STR-1
test "scalar fusion decodes valid literals but preserves extern authority and malformed or wider literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Case = struct { bytes: []const u8, expected: u32 };
    for ([_]Case{
        .{ .bytes = "x", .expected = 1 },                .{ .bytes = "\x00", .expected = 1 },
        .{ .bytes = "é", .expected = 1 },
        .{ .bytes = "🙂", .expected = 1 },
        .{ .bytes = "\xf4\x8f\xbf\xbf", .expected = 1 }, .{ .bytes = "", .expected = 0 },
        .{ .bytes = "ab", .expected = 0 },
        .{ .bytes = "éx", .expected = 0 },
        .{ .bytes = "\xc0\x80", .expected = 0 },         .{ .bytes = "\xed\xa0\x80", .expected = 0 },
        .{ .bytes = "\xf4\x90\x80\x80", .expected = 0 }, .{ .bytes = "\xf0", .expected = 0 },
    }) |case| {
        try std.testing.expectEqual(case.expected, try handCase(a, case.bytes, .runtime_c));
        try std.testing.expectEqual(@as(u32, 0), try handCase(a, case.bytes, .extern_c));
    }
}

// migrate-embedded: skip original optimizer materialization witnesses; modern bodies are derived below
const fallback = [_][]const u8{
    "    return ch\n",
    "    const values = [ch]\n    return copy(values[0])\n",
    "    return identity(ch)\n",
    "    const selected = if strings.char_count(text) > 1 then ch else \"!\"\n    return selected\n",
    "    text += ch\n    return text\n",
    "    return if ch == \"éx\" then \"yes\" else \"no\"\n",
};

// spec-case: NEW-CORE-TEXT-BYTES-1
test "scalar fusion retains escaping consumers and decodes independently owned self appends" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (fallback) |body| {
        const prefix = "func identity(text: str) -> str:\n    return text\nfunc scan(source: str) -> str:\n    mut text = source\n    const ch = strings.char_at(text, 0)\n";
        const suffix = "func main() -> int:\n    return strings.char_count(scan(\"éx\"))\n";
        // Keep the original optimizer-negative guest bytes as removal witnesses.
        if (std.mem.indexOf(u8, body, " then ") != null) {
            const original = try std.mem.concat(a, u8, &.{ prefix, body, suffix });
            var retired = try @import("selka").Compilation.init(a, "original-fusion.selka", original);
            defer retired.deinit();
            try std.testing.expectError(error.SourceError, retired.check());
            try std.testing.expectEqualStrings("E_CONDITIONAL_EXPRESSION_REMOVED", retired.diagnostics.items[0].code);
        }
        const selected_before = "    const selected = if strings.char_count(text) > 1 then ch else \"!\"\n    return selected\n";
        const selected_after = "    mut selected: str\n    if strings.char_count(text) > 1:\n        selected = ch\n    else:\n        selected = \"!\"\n    return selected\n";
        const assigned = try std.mem.replaceOwned(u8, a, body, selected_before, selected_after);
        const modern = try std.mem.replaceOwned(u8, a, assigned, "    return if ch == \"éx\" then \"yes\" else \"no\"\n", "    if ch == \"éx\":\n        return \"yes\"\n    else:\n        return \"no\"\n");
        const owned_prefix = "func identity(text: str) -> str:\n    return copy(text)\nfunc scan(source: str) -> str:\n    mut text = copy(source)\n    const ch = strings.char_at(text, 0)\n";
        const source = try std.mem.concat(a, u8, &.{ owned_prefix, modern, suffix });
        var refusal: @import("build.zig").Refusal = .{};
        const module = try support.buildSource(a, source, &refusal);
        const independent_append = std.mem.eql(u8, body, "    text += ch\n    return text\n");
        try std.testing.expectEqual(@as(usize, if (independent_append) 0 else 1), count(&module, .str_char));
        try std.testing.expectEqual(@as(usize, if (independent_append) 1 else 0), count(&module, .str_code));
        try std.testing.expectEqual(@as(usize, if (independent_append) 1 else 0), count(&module, .str_append_char));
        try support.verified(a, &module, &.{});
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "scalar fusion self append preserves the borrowed source through ownership and donation" {
    const passes = @import("passes.zig");
    for ([_]passes.Mode{ .off, .trusted, .verify }) |mode| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var refusal: @import("build.zig").Refusal = .{};
        var module = try support.buildSource(a,
            \\func scan(source: str) -> str:
            \\    mut text = copy(source)
            \\    const ch = strings.char_at(text, 0)
            \\    text += ch
            \\    return text
            \\func main(out: Stream) -> int:
            \\    const source = "é" + str(1)
            \\    const result = scan(source)
            \\    print(out, source, result)
            \\    return 0
        , &refusal);
        const result = try support.runPasses(a, &module, mode);
        const ran = try support.runOwned(a, &module, .{ .own = false, .release = mode != .off, .verify = mode == .verify, .analysis = support.analysis(&result) });
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings("é1 é1é\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
}

fn fixture(a: std.mem.Allocator) !void {
    const original_path = try std.fmt.allocPrint(a, "{s}/t_scalar_fusion.selka", .{options.fixtures});
    const original = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, original_path, a, .limited(1 << 20));
    // This formerly valid negative access names the middle of the three-scalar input.
    // Deliberate negative bounds failures elsewhere in the fixture stay unchanged.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, original, ", -2)"));
    const runtime_source = try std.mem.replaceOwned(u8, a, original, ", -2)", ", 1)");
    var directory = stable_dir.tmpDir(a, @src());
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "t_scalar_fusion.selka", .data = runtime_source });
    const source = try directory.dir.realPathFileAlloc(std.testing.io, "t_scalar_fusion.selka", a);
    var environment = try options.privateEnvironment(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "test", "--force", source, "--json", "--cache-dir", try options.suiteCache(a, @src()) });
        try argv.appendSlice(a, mode);
        const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (result.term != .exited or result.term.exited != 1) report("scalar fixture: {s}{s}\n", .{ result.stdout, result.stderr });
        try std.testing.expect(result.term == .exited and result.term.exited == 1);
        try std.testing.expectEqualStrings("", result.stderr);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, result.stdout, .{});
        try std.testing.expectEqual(@as(i64, 8), parsed.value.object.get("passed").?.integer);
        try std.testing.expectEqual(@as(i64, 9), parsed.value.object.get("failed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("unsupported").?.integer);
        for (parsed.value.object.get("tests").?.array.items) |test_case| {
            const name = test_case.object.get("name").?.string;
            const reason = test_case.object.get("reason").?.string;
            if (std.mem.indexOf(u8, name, "large_negative") != null) try std.testing.expect(std.mem.startsWith(u8, reason, "R_TEXT_BOUNDS (index -9223372036854775807, length 2)"));
            if (std.mem.indexOf(u8, name, "large_positive") != null) try std.testing.expect(std.mem.startsWith(u8, reason, "R_TEXT_BOUNDS (index 9223372036854775807, length 2)"));
            if (std.mem.indexOf(u8, name, "minimum_signed") != null) try std.testing.expect(std.mem.startsWith(u8, reason, "R_TEXT_BOUNDS (index -9223372036854775808, length 2)"));
            if (std.mem.indexOf(u8, name, "nonplace_unicode") != null) try std.testing.expect(std.mem.startsWith(u8, reason, "R_TEXT_BOUNDS (index 99, length 2)"));
            if (std.mem.indexOf(u8, name, "large_negative") != null or
                std.mem.indexOf(u8, name, "minimum_signed") != null)
                try std.testing.expect(std.mem.indexOf(u8, reason, "negative indexes are not allowed") != null);
            try std.testing.expect(std.mem.indexOf(u8, reason, "NativeTestProcessFailed") == null);
        }
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "scalar fusion native modes preserve Unicode bounds aliases escaping uses and exact failures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try fixture(arena.allocator());
}

const scalar_invalid = "error[E_CORE_UNSUPPORTED]: S2 IR operation -1 is not implemented\n";
const ScalarCase = struct { bytes: []const u8, offsets: []const u64, op: ?ir.Op = null, stdout: []const u8 = "", status: u8 = 1, stderr: []const u8 = scalar_invalid };

fn scalarHand(a: std.mem.Allocator, case: ScalarCase) !ir.Module {
    var module: ir.Module = .{};
    try module.strings.append(a, case.bytes);
    var h = try support.Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const text = try h.loose(.{ .op = .str_const, .ty = .str });
    for (case.offsets) |offset| {
        const at = try h.int(.u64, @bitCast(offset));
        for ([_]ir.Op{ .str_width, .str_code }) |op| {
            if (case.op != null and case.op.? != op) continue;
            const value = try h.emit(.{ .op = op, .ty = if (op == .str_width) .u64 else .u32, .a = text, .b = at });
            try h.printValues(try h.param(0), &.{value});
        }
    }
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return module;
}

fn scalarCases(allocator: std.mem.Allocator, cases: []const ScalarCase) !void {
    var state = std.heap.ArenaAllocator.init(allocator);
    defer state.deinit();
    const a = state.allocator();
    for ([_]support.RunOptions{ .{}, .{ .release = true }, .{ .release = true, .verify = true } }) |mode| {
        for (cases) |case| {
            var module = try scalarHand(a, case);
            const result = try support.runOwned(a, &module, mode);
            try std.testing.expectEqual(case.status, result.status);
            try std.testing.expectEqualStrings(case.stdout, result.stdout);
            try std.testing.expectEqualStrings(case.stderr, result.stderr);
        }
    }
}

fn invalidOffsets(allocator: std.mem.Allocator, op: ir.Op) !void {
    const text = "L\x00é€🙂";
    try scalarCases(allocator, &.{
        .{ .bytes = "", .offsets = &.{0}, .op = op },
        .{ .bytes = text, .offsets = &.{text.len}, .op = op },
        .{ .bytes = text, .offsets = &.{std.math.maxInt(u64)}, .op = op },
    });
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "scalar fusion emitter preserves ASCII NUL and all Unicode widths in every native mode" {
    try scalarCases(std.testing.allocator, &.{.{ .bytes = "L\x00é€🙂", .offsets = &.{ 0, 1, 2, 4, 7 }, .stdout = "1\n76\n1\n0\n2\n233\n3\n8364\n4\n128578\n", .status = 0, .stderr = "" }});
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "scalar fusion emitter guards empty end and extreme manual width offsets in every native mode" {
    try invalidOffsets(std.testing.allocator, .str_width);
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "scalar fusion emitter guards empty end and extreme manual code offsets in every native mode" {
    try invalidOffsets(std.testing.allocator, .str_code);
}
