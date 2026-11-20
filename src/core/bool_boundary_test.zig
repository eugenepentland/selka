//! FX4: a `bool` that crosses from emitted code into the C runtime. The test runner's trial hands a `bool` test's result
//! to `myl_core_test_write_bool(bool)`, a runtime helper (`runtime_c`), and the emitter gave a runtime helper's `bool`
//! and narrow integer parameters no `zeroext`/`signext`. Clang compiles the helper to read the whole 32-bit register
//! its caller widened, so when LLVM did not optimise the caller (`selka test`'s default `--debug-o0` build and
//! `--unoptimized`) the upper bits of a value computed by `not` and `and` reached the result word and the runner read
//! a False result as a pass. These tests run `selka test` on tests whose every value is False and require each to
//! fail, in the default build, `--unoptimized` and `--optimize-debug`; and check that a runtime helper's `bool`
//! parameter carries its extension on the declaration and on the call.
const std = @import("std");
const support = @import("test_support.zig");
const ir = @import("ir.zig");
const emit_llvm = @import("emit_llvm.zig");
const test_builder = @import("test_builder.zig");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");

/// Tests whose value is False, each through a different shape: the three of F-23 first, then a parameter, the runtime's
/// text of a `bool`, a template, a list element, a record field, a `parallel` task's result, a dictionary value, a
/// fallible test's `Ok(False)`, a property over a generated `bool`, and a record key the runtime compares.
const false_shapes =
    \\import parallel
    \\
    \\func yes() -> bool:
    \\    return True
    \\
    \\func no() -> bool:
    \\    return False
    \\
    \\func f() -> bool:
    \\    return not yes() and yes()
    \\
    \\func positive(n: int) -> bool:
    \\    return not (n <= 0) and n > 0
    \\
    \\public func test_returns_not_a_and_b() -> bool:
    \\    return not yes() and yes()
    \\
    \\public func test_returns_f() -> bool:
    \\    return f()
    \\
    \\public func test_branches_on_f() -> bool:
    \\    if f():
    \\        return True
    \\    return False
    \\
    \\public func test_not_of_an_or() -> bool:
    \\    return not (no() or yes())
    \\
    \\public func test_a_parameter_shape() -> bool:
    \\    return positive(0)
    \\
    \\public func test_str_of_false_is_true() -> bool:
    \\    return str(f()) == "True"
    \\
    \\public func test_template_of_false_is_true() -> bool:
    \\    return f"{f()}" == "True"
    \\
    \\public func test_a_list_element() -> bool:
    \\    const xs = [f(), positive(-1)]
    \\    return xs[0]
    \\
    \\record Flagged:
    \\    flag: bool
    \\    id: int
    \\
    \\public func test_a_record_field() -> bool:
    \\    const a = Flagged(flag=f(), id=1)
    \\    return a.flag
    \\
    \\public func test_a_parallel_result() -> bool:
    \\    const flags = parallel.map([-2, 0], positive)
    \\    return flags[0] or flags[1]
    \\
    \\public func test_a_dictionary_value() -> bool:
    \\    mut d: dict[int, bool] = {}
    \\    d[1] = f()
    \\    return d[1]
    \\
    \\func checked(n: int) -> bool fails str:
    \\    if n < 0:
    \\        fail "negative"
    \\    return not (n == 0) and n > 0
    \\
    \\public func test_a_fallible_false() -> bool fails str:
    \\    return try checked(0)
    \\
    \\public func test_a_property_that_is_always_false(b: bool) -> bool:
    \\    return not b and b
    \\
    \\public func test_a_record_key_the_runtime_compares() -> bool:
    \\    mut d: dict[Flagged, int] = {}
    \\    d[Flagged(flag=f(), id=1)] = 1
    \\    return Flagged(flag=True, id=1) in d
    \\
;
const false_count = 14;

/// Tests whose value is False through an `extern func`'s `bool` argument or result, and a capability's `bool` result.
const extern_shapes =
    \\extern func fx4_not(host: Host, b: bool) -> bool
    \\extern func fx4_echo(host: Host, b: bool) -> bool
    \\extern func fx4_as_int(host: Host, b: bool) -> int
    \\
    \\func yes() -> bool:
    \\    return True
    \\
    \\func f() -> bool:
    \\    return not yes() and yes()
    \\
    \\public func test_extern_not_of_true(host: Host) -> bool:
    \\    return fx4_not(host, yes())
    \\
    \\public func test_extern_echo_of_false(host: Host) -> bool:
    \\    return fx4_echo(host, f())
    \\
    \\public func test_extern_widens_false_to_zero(host: Host) -> bool:
    \\    return fx4_as_int(host, f()) != 0
    \\
    \\public func test_a_missing_file_exists(fs: Filesystem) -> bool:
    \\    return fs.exists("fx4-no-such-file.txt")
    \\
;
const extern_count = 4;

const extern_c =
    \\#include <stdbool.h>
    \\#include <stdint.h>
    \\bool fx4_not(bool b) { return !b; }
    \\bool fx4_echo(bool b) { return b; }
    \\int64_t fx4_as_int(bool b) { return (int64_t)b; }
    \\
;

/// The modes the runner must agree in: the default (`--debug-o0`), no Core passes, and LLVM at `-O2`.
const modes = [_][]const u8{ "--debug-o0", "--unoptimized", "--optimize-debug" };

/// "every test failed" when `selka test` in each mode reports `expected` tests, every one failed with the value
/// False, else what it reported.
fn everyTestFails(a: std.mem.Allocator, dir: anytype, source: []const u8, expected: usize, link: ?[]const u8) ![]const u8 {
    const io = std.testing.io;
    try dir.dir.writeFile(io, .{ .sub_path = "shapes.selka", .data = source });
    if (link) |c| try dir.dir.writeFile(io, .{ .sub_path = "shapes.c", .data = c });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const file = try std.fs.path.join(a, &.{ root, "shapes.selka" });
    const c_file = try std.fs.path.join(a, &.{ root, "shapes.c" });
    var environment = try options.privateEnvironment(a);
    for (modes) |mode| {
        const cache = try std.fs.path.join(a, &.{ root, mode[2..] });
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "test", file, mode, "--json", "--cache-dir", cache });
        if (link != null) try argv.appendSlice(a, &.{ "--link", c_file, "--allow-host" });
        const result = try std.process.run(a, io, .{ .argv = argv.items, .environ_map = &environment });
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{}) catch
            return std.fmt.allocPrint(a, "{s}: no report\n{s}{s}", .{ mode, result.stdout, result.stderr });
        const tests = parsed.object.get("tests").?.array.items;
        var false_failures: usize = 0;
        for (tests) |item| {
            const failed = std.mem.eql(u8, item.object.get("status").?.string, "failed");
            const reason = item.object.get("reason").?.string;
            const false_value = std.mem.indexOf(u8, reason, "false") != null or std.mem.indexOf(u8, reason, "False") != null;
            if (failed and false_value) false_failures += 1 else return std.fmt.allocPrint(a, "{s}: {s} {s}: {s}", .{
                mode, item.object.get("name").?.string, item.object.get("status").?.string, reason,
            });
        }
        if (tests.len != expected or false_failures != expected) return std.fmt.allocPrint(a, "{s}: {d} tests, {d} failed on False", .{ mode, tests.len, false_failures });
    }
    return "every test failed";
}

test "FX4: selka test fails every test whose value is False, in the default build, --unoptimized and --optimize-debug" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    try std.testing.expectEqualStrings("every test failed", try everyTestFails(arena.allocator(), dir, false_shapes, false_count, null));
}

test "FX4: an extern func's and a capability's False reaches the test runner as False in every mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    try std.testing.expectEqualStrings("every test failed", try everyTestFails(arena.allocator(), dir, extern_shapes, extern_count, extern_c));
}

fn fixedLocation(_: *const anyopaque, _: u32) emit_llvm.Location {
    return .{ .path = "bool_boundary.selka", .line = 1, .column = 1 };
}

test "FX4: a runtime helper's bool and u8 arguments are declared and passed with zeroext" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    // The trial's result writer and a byte push, as the test builder declares them (`runtime_c`).
    const write_bool = try test_builder.helper(a, &module, "myl_core_test_write_bool", &.{.bool}, .void);
    const push = try test_builder.helper(a, &module, "myl_core_buffer_push", &.{ .byte_buffer, .u8 }, .byte_buffer);
    var hand = try support.Hand.init(a, &module, "probe", .{ .params = &.{ .bool, .byte_buffer, .u8 }, .ret = .i64 });
    const flag = try hand.emit(.{ .op = .not, .ty = .bool, .a = try hand.param(0) });
    _ = try hand.emit(.{ .op = .call, .ty = .void, .a = @fromBackingInt(write_bool), .data = try hand.extra(&.{flag}) });
    const pushed = try hand.emit(.{ .op = .call, .ty = .byte_buffer, .a = @fromBackingInt(push), .data = try hand.extra(&.{ try hand.param(1), try hand.param(2) }) });
    _ = try hand.emit(.{ .op = .drop, .ty = .void, .a = pushed });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = try hand.int(.i64, 0) });
    _ = try hand.finish();
    var entry = try support.Hand.init(a, &module, "main", .{ .params = &.{}, .ret = .i64 });
    _ = try entry.emit(.{ .op = .ret, .ty = .void, .a = try entry.int(.i64, 0) });
    module.entry = try entry.finish();
    const context: u8 = 0;
    const text = try emit_llvm.emitModule(a, &module, .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "bool_boundary.selka", .main = .{} });
    try std.testing.expect(std.mem.indexOf(u8, text, "declare void @myl_core_test_write_bool(i1 zeroext)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call void @myl_core_test_write_bool(i1 zeroext %") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "declare ptr @myl_core_buffer_push(ptr, i8 zeroext)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@myl_core_test_write_bool(i1)") == null);
}
