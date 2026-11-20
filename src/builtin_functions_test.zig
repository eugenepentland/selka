//! The standard library's `builtin func` declarations against the compiler's own tables (W10).
//!
//! A supplied function's body is gone from the page, and the body was the one place the declaration and the compiler's
//! lowering were written down together. These tests hold the two together instead: every declaration has a supplier,
//! every supplier has a declaration, and each declaration's parameters, their markers, its result and `fails` are the
//! ones the supplier's table names. A home's declared result is also checked against what the operation answers at
//! every resolved call (`sema_supplied.requireDeclaredResult`; `tests/lang/builtin_functions.selka` makes those calls).
const std = @import("std");
const product = @import("product.zig");
const t = std.testing;
const ast = @import("ast.zig");
const fixture = @import("stdlib_fixture.zig");
const transition = @import("ownership_transition_test_support.zig");
const source = @import("source.zig");
const language = @import("compiler.zig");
const standard_library = @import("standard_library.zig");
const retired_methods = @import("retired_methods.zig");
const scalar_text_helpers = @import("scalar_text_helpers.zig");
const builtin_functions = @import("builtin_functions.zig");

/// One `builtin func` as its module declares it.
const Declared = struct { module: []const u8, function: ast.Function, src: source.Source };

/// Every `builtin func` of the embedded standard library, read from a project that imports every module.
fn declarations(arena: std.mem.Allocator) ![]const Declared {
    var text: std.ArrayList(u8) = .empty;
    for (standard_library.paths) |file| try text.print(arena, "import {s}\n", .{product.chopSource(file)});
    try text.appendSlice(arena, "\nfunc main() -> int:\n    return 0\n");
    var entry: fixture.Entry = .{ .text = text.items };
    var project = language.project.Project.init(arena);
    try project.load(.{ .context = &entry, .read = fixture.Entry.read }, "main", .{});
    const index = try language.interfaces.build(&project);
    var out: std.ArrayList(Declared) = .empty;
    for (project.modules.items, 0..) |module, id| {
        if (!std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        for (index.units[id].syntax.functions) |function| {
            if (!function.policy.builtin) continue;
            try out.append(arena, .{ .module = module.name, .function = function, .src = module.src });
        }
    }
    return out.items;
}

fn find(all: []const Declared, module: []const u8, name: []const u8) ?Declared {
    for (all) |entry| if (std.mem.eql(u8, entry.module, module) and std.mem.eql(u8, entry.src.text(entry.function.name), name)) return entry;
    return null;
}

/// The parameters a scalar text helper takes, as its checker counts them (`scalar_text_helpers.zig`).
fn helperParameters(candidate: scalar_text_helpers.ScalarHelper) usize {
    return switch (candidate) {
        .char_count, .chars, .bytes => 1,
        .char_at => 2,
        .char_slice => 3,
        .char_stride, .list_stride => 4,
        .char_find, .char_rfind, .char_index, .char_rindex, .char_count_of, .char_startswith, .char_endswith => 4,
    };
}

/// The parameters a lane operation takes, as `sema_simd.zig` checks them.
fn laneParameters(operation: builtin_functions.LaneOperation) usize {
    return switch (operation) {
        .splat, .sum, .min, .max, .sqrt => 1,
        .load => 2,
        .store, .select, .fma => 3,
    };
}

fn mutCount(function: ast.Function) usize {
    var count: usize = 0;
    for (function.signature.parameters) |parameter| count += @intFromBool(parameter.mut);
    return count;
}

fn declaresResult(function: ast.Function) bool {
    return function.signature.return_type.end > function.signature.return_type.start;
}

/// How many `builtin func` declarations have no supplier.
fn unsupplied(all: []const Declared) usize {
    var count: usize = 0;
    for (all) |entry| {
        const name = entry.src.text(entry.function.name);
        count += @intFromBool(builtin_functions.supplier(entry.module, name, entry.function.signature.parameters.len) == null);
    }
    return count;
}

/// The supplied homes of the retired-method table and how many of them no declaration names.
const HomeCount = struct { homes: usize, missing: usize };
fn undeclaredHomes(all: []const Declared) HomeCount {
    var out: HomeCount = .{ .homes = 0, .missing = 0 };
    inline for (.{ &retired_methods.retirements, &retired_methods.method_homes, &retired_methods.library_homes }) |table| for (table) |row| {
        const module = row.home.module orelse continue;
        if (builtin_functions.home(module, row.home.function, row.arguments + 1) == null) continue;
        out.homes += 1;
        out.missing += @intFromBool(find(all, module, row.home.function) == null);
    };
    return out;
}

/// How many lane operations, scalar helpers, parallel maps and testing counters no declaration names.
fn undeclaredOthers(all: []const Declared) usize {
    var missing: usize = 0;
    for (std.enums.values(builtin_functions.LaneOperation)) |operation| missing += @intFromBool(find(all, "simd", @tagName(operation)) == null);
    for (std.enums.values(scalar_text_helpers.ScalarHelper)) |candidate| {
        const name = if (candidate == .list_stride) "stride" else @tagName(candidate);
        missing += @intFromBool(find(all, scalar_text_helpers.moduleOf(candidate), name) == null);
    }
    for (builtin_functions.parallel_functions) |name| missing += @intFromBool(find(all, "parallel", name) == null);
    for (builtin_functions.testing_functions) |name| missing += @intFromBool(find(all, "testing", name) == null);
    return missing;
}

test "W10 every builtin declaration has a supplier and every supplier has its declaration" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const all = try declarations(arena.allocator());
    // 62 retired-method homes (the strip family's three since W13-S3, `buffers.clear` since BYTEWIN), 31 homes of live
    // methods (W13: 54 rows, a search's bounds a row per count, `lists.exchange` since W13-S3), the library's two private homes
    // (`strings.find_offset`, `rfind_offset`, W13-S3), 9 lane operations, 14 scalar helpers, 7 parallel maps, the
    // two runtime reads `parallel.threads` and `parallel.cpus`, 2 testing counters, and the 2 derived JSON
    // codecs `json.encode` and `json.decode` (CODEC-S1). The 31st live-method home is `bytes.find_any`'s `end` (R3-FINDEND).
    // The 145th is `registers.start_core1` (MCU-CORE1), beside the other `registers` operations; the 12 `cpu` operations
    // (MCU-NOC1) follow, seven of them private (the PRIMASK pair and the event log's raw readers).
    try t.expectEqual(@as(usize, 157), all.len);
    try t.expectEqual(@as(usize, 0), unsupplied(all));
    const homes = undeclaredHomes(all);
    try t.expectEqual(@as(usize, 119), homes.homes);
    try t.expectEqual(@as(usize, 0), homes.missing);
    try t.expectEqual(@as(usize, 0), undeclaredOthers(all));
}

/// Hold one declaration's parameters, markers, result and `fails` to its supplier's table.
fn expectMatchesSupplier(entry: Declared) !void {
    const function = entry.function;
    const parameters = function.signature.parameters;
    const supplier = builtin_functions.supplier(entry.module, entry.src.text(function.name), parameters.len).?;
    // Only a scalar helper and a home's search bounds have defaults; a home's call that leaves trailing bounds to
    // their defaults is the row of the count it wrote (W13-Q3), so every such count has its row.
    for (parameters, 0..) |parameter, index| {
        if (parameter.default_value == null or supplier == .scalar) continue;
        try t.expect(supplier == .home);
        try t.expect(builtin_functions.home(entry.module, entry.src.text(function.name), index) != null);
    }
    switch (supplier) {
        .home => |row| {
            // The receiver and the method's operands; a writer takes its receiver `mut` and only it.
            try t.expectEqual(row.arguments + 1, parameters.len);
            const receiver = if (row.home.arguments_first) parameters.len - 1 else 0;
            try t.expectEqual(row.home.writer, parameters[receiver].mut);
            try t.expectEqual(@as(usize, @intFromBool(row.home.writer)), mutCount(function));
            // A method that always answered `true` has a home that answers nothing. What every other home answers
            // is checked against its operation at each resolved call (`tests/lang/builtin_functions.selka`).
            if (row.answer == .nothing) try t.expect(!declaresResult(function));
        },
        .lane => |operation| {
            try t.expectEqual(laneParameters(operation), parameters.len);
            try t.expectEqual(@as(usize, @intFromBool(operation == .store)), mutCount(function));
            try t.expectEqual(operation != .store, declaresResult(function));
            try t.expect(function.signature.failure_type == null);
        },
        .scalar => |candidate| {
            try t.expectEqual(helperParameters(candidate), parameters.len);
            try t.expectEqual(@as(usize, 0), mutCount(function));
            try t.expect(declaresResult(function) and function.signature.failure_type == null);
        },
        .parallel => {
            try t.expectEqual(@as(usize, 0), mutCount(function));
            try t.expect(declaresResult(function));
        },
        .testing => {
            try t.expectEqual(@as(usize, 0), mutCount(function));
            try t.expect(declaresResult(function) and function.signature.failure_type == null);
        },
        .json => {
            try t.expectEqual(@as(usize, 1), parameters.len);
            try t.expectEqual(@as(usize, 0), mutCount(function));
            try t.expect(declaresResult(function) and function.signature.failure_type != null);
        },
        .registers => {
            // Every operation but `simulated` takes the bank first; none marks `mut` or fails. `pin32` takes four.
            try t.expect(parameters.len <= 4);
            try t.expectEqual(@as(usize, 0), mutCount(function));
            try t.expect(function.signature.failure_type == null);
        },
    }
}

test "W10 each builtin declaration's parameters, markers, result and fails match its supplier's table" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const all = try declarations(arena.allocator());
    try t.expectEqual(@as(usize, 157), all.len);
    for (all) |entry| try expectMatchesSupplier(entry);
}

test "W10 the supplier table answers each kind by its own names" {
    try t.expect(builtin_functions.supplier("strings", "upper", 1).? == .home);
    try t.expect(builtin_functions.supplier("simd", "sum", 1).? == .lane);
    try t.expect(builtin_functions.supplier("json", "decode", 1).? == .json);
    try t.expect(builtin_functions.supplier("json", "loads", 1) == null);
    try t.expect(builtin_functions.supplier("strings", "char_count", 1).? == .scalar);
    try t.expect(builtin_functions.supplier("parallel", "map_with3", 5).? == .parallel);
    try t.expect(builtin_functions.supplier("testing", "__test_blocks", 0).? == .testing);
    try t.expect(builtin_functions.supplier("registers", "write32", 3).? == .registers);
    try t.expect(builtin_functions.supplier("registers", "pin32", 4).? == .registers);
    try t.expect(builtin_functions.supplier("registers", "writes", 1) == null);
    try t.expect(builtin_functions.supplier("cpu", "send_event", 1).? == .registers);
    try t.expect(builtin_functions.supplier("cpu", "__interrupts_disable", 1).? == .registers);
    try t.expect(builtin_functions.supplier("cpu", "interrupts_off", 1) == null);
    // The strip family is the native trim, which lends a view of its text (W13-S3); `find` answers an option, a real
    // function with a body; `lists.exchange` is the list's own exchange (W13-S3).
    try t.expect(builtin_functions.supplier("strings", "strip", 1).? == .home);
    try t.expect(builtin_functions.supplier("lists", "exchange", 3).? == .home);
    try t.expectEqual(@as(?builtin_functions.Supplier, null), builtin_functions.supplier("strings", "find", 2));
    try t.expect(builtin_functions.supplier("strings", "find_offset", 4).? == .home);
    // A library-only home is no home a program's call is recognized as.
    try t.expectEqual(@as(?retired_methods.Retirement, null), retired_methods.home("strings", "find_offset", 4));
    try t.expectEqualStrings("strings", builtin_functions.embeddedModule("@stdlib/strings.selka").?);
    try t.expectEqual(@as(?[]const u8, null), builtin_functions.embeddedModule("app/strings.selka"));
    // Only the views and the loop sources answer something their declaration cannot name.
    try t.expect(builtin_functions.unsignedResult("dicts", "keys"));
    try t.expect(builtin_functions.unsignedResult("strings", "chars"));
    try t.expect(!builtin_functions.unsignedResult("dicts", "get"));
}

/// Check `text` as a project's entry module and answer its first error's code, or "" when it checks.
fn expectCode(text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), text);
    const found = if (report.passed) "" else (report.firstError() orelse return error.TestUnexpectedResult).code;
    try t.expectEqualStrings(code, found);
}

test "W10 a builtin func outside the standard library is refused and says why" {
    try expectCode("builtin func shout(text: str) -> str\n\nfunc main() -> int:\n    return 0\n", "E_BUILTIN_DECLARATION");
    try expectCode("public builtin func shout(text: str) -> str\n\nfunc main() -> int:\n    return 0\n", "E_BUILTIN_DECLARATION");
    var c = try language.Compilation.init(t.allocator, "main.selka", "builtin func shout(text: str) -> str\n\nfunc main() -> int:\n    return 0\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_BUILTIN_DECLARATION", c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "only the standard library declares a `builtin func`") != null);
}

test "W10 a builtin func no operation supplies is refused in a trusted source" {
    var c = try language.Compilation.initTrusted(t.allocator, "strings.selka", "public builtin func shout(text: str) -> str\n\nfunc main() -> int:\n    return 0\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_BUILTIN_SUPPLIER", c.diagnostics.items[0].code);
}

test "W10 a simd operation or a scalar helper is not a function value; a text home is" {
    try expectCode(
        \\import simd
        \\
        \\func apply(f: func(Simd[float, 4]) -> float, v: Simd[float, 4]) -> float:
        \\    return f(v)
        \\
        \\func main() -> int:
        \\    const v = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
        \\    return int(apply(simd.sum, v))
        \\
    , "E_BUILTIN_FUNCTION_VALUE");
    try expectCode(
        \\import strings
        \\
        \\func apply(f: func(str) -> int, text: str) -> int:
        \\    return f(text)
        \\
        \\func main() -> int:
        \\    return apply(strings.char_count, "abc")
        \\
    , "E_BUILTIN_FUNCTION_VALUE");
    try expectCode(
        \\import strings
        \\
        \\func apply(f: func(str) -> str, text: str) -> str:
        \\    return f(text)
        \\
        \\func main() -> int:
        \\    return len(apply(strings.upper, "abc"))
        \\
    , "");
}

test "W10 an aliased call is the operation, with the operation's own refusals" {
    // A dictionary's keys through an alias are the live view, so writing the dictionary in the loop is refused, as
    // it is for `dicts.keys(m)`; before W10 the alias ran the body, a copied list, and the loop was accepted.
    try transition.refuses(t.allocator,
        \\import dicts as d
        \\
        \\func main() -> int:
        \\    mut m = {"a": 1, "b": 2}
        \\    for k in d.keys(m):
        \\        m[k] = 0
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    // A constant negative index is refused at check, as the direct spelling refuses it.
    try expectCode(
        \\import lists as l
        \\
        \\func main() -> int:
        \\    mut xs = [1, 2, 3]
        \\    return l.pop_at(mut xs, -1)
        \\
    , "E_NEGATIVE_INDEX_REMOVED");
    try expectCode(
        \\import lists as l
        \\
        \\func main() -> int:
        \\    mut xs = [1, 2, 3]
        \\    return l.pop_at(mut xs, 1)
        \\
    , "");
}
