//! Scalar helper composition binds proof and caller-cache identities together.
const std = @import("std");
const compiler = @import("compiler.zig");
const bytecode = @import("bytecode.zig");
const filename = "readonly_calls.my";
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const calls = @import("rc_readonly_calls.zig");
const cache = @import("qbe_rc_cache.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Witness = struct { admitted: bool, key: [32]u8 };
const prefix =
    \\record Item:
    \\    text: bytes
    \\    number: int
;
const suffix =
    \\def selected(items: list[Item]) -> int:
    \\    total = 0
    \\    i = 0
    \\    while i < len(items):
    \\        item = items[i]
    \\        total += middle(items, i) + item.number
    \\        i += 1
    \\    return total
    \\def middle(items: list[Item], i: int) -> int:
    \\    return leaf(items, i)
    \\def main() -> int:
    \\    return selected([Item(b"a", 3), Item(b"b", 7)])
;

fn witness(allocator: std.mem.Allocator, leaf: []const u8) !Witness {
    const source = try std.mem.concat(allocator, u8, &.{ prefix, "\n", leaf, "\n", suffix });
    defer allocator.free(source);
    return witnessSource(allocator, source);
}

fn witnessSource(allocator: std.mem.Allocator, source: []const u8) !Witness {
    var compilation = try compiler.Compilation.init(allocator, filename, source);
    defer compilation.deinit();
    try compilation.emit();
    const program = compilation.code.?;
    var layouts = try native.Catalog.initRecords(allocator, program.records);
    defer layouts.deinit();
    var catalog = try shapes.Catalog.init(allocator, &layouts);
    defer catalog.deinit();
    for (program.functions, 0..) |function, index| if (std.mem.eql(u8, function.name, "selected")) {
        return .{
            .admitted = (try calls.identity(&catalog, program.functions, function, "rc-v3")) != null,
            .key = try cache.key(allocator, program, &layouts, index, @splat(1)),
        };
    };
    return error.TestUnexpectedResult;
}

fn dependencySource(allocator: std.mem.Allocator, count: usize, chain: bool) ![]const u8 {
    var source: std.ArrayList(u8) = .empty;
    errdefer source.deinit(allocator);
    try source.appendSlice(allocator, prefix);
    try source.appendSlice(allocator, "\ndef selected(items: list[Item]) -> int:\n    total = 0\n");
    for (0..if (chain) 1 else count) |index| {
        const line = try std.fmt.allocPrint(allocator, "    total += helper{d}(items, 0)\n", .{index});
        defer allocator.free(line);
        try source.appendSlice(allocator, line);
    }
    try source.appendSlice(allocator, "    return total\n");
    for (0..count) |index| {
        const header = try std.fmt.allocPrint(allocator, "def helper{d}(items: list[Item], i: int) -> int:\n", .{index});
        defer allocator.free(header);
        try source.appendSlice(allocator, header);
        const result = if (chain and index + 1 < count)
            try std.fmt.allocPrint(allocator, "    return helper{d}(items, i)\n", .{index + 1})
        else
            try allocator.dupe(u8, "    return items[i].number\n");
        defer allocator.free(result);
        try source.appendSlice(allocator, result);
    }
    try source.appendSlice(allocator, "def main() -> int:\n    return selected([Item(b\"a\", 3)])\n");
    return source.toOwnedSlice(allocator);
}

fn dependencyWitness(count: usize, chain: bool) !Witness {
    const source = try dependencySource(t.allocator, count, chain);
    defer t.allocator.free(source);
    return witnessSource(t.allocator, source);
}

const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
fn emitted() !std.json.Parsed(Manifest) {
    const source = try dependencySource(t.allocator, 2, true);
    defer t.allocator.free(source);
    var compilation = try compiler.Compilation.init(t.allocator, filename, source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
fn rawReader(il: []const u8) bool {
    return std.mem.indexOf(u8, il, "call $myl_qbe_rc_frame_enter") == null and
        std.mem.indexOf(u8, il, "call $myl_rc_native_loan") == null and
        std.mem.indexOf(u8, il, "call $myl_rc_native_retain") == null and
        std.mem.indexOf(u8, il, "call $myl_qbe_fail_frame") != null;
}

// spec: RC-READONLY-CALLS-1
test "RC readonly calls compose scalar helpers and hash transitive body changes" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const before = try witness(t.allocator,
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return items[i].number
    );
    const after = try witness(t.allocator,
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return items[i].number + 1
    );
    try t.expect(before.admitted);
    try t.expect(after.admitted);
    try t.expect(!std.mem.eql(u8, &before.key, &after.key));
}

// spec-case: RC-READONLY-CALLS-1
test "RC readonly calls refuse transitive allocation and admit certified managed helpers" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const allocated = try witness(t.allocator,
        \\def leaf(items: list[Item], i: int) -> int:
        \\    other = [items[i].number]
        \\    return len(other)
    );
    const managed = try witness(t.allocator,
        \\def returned(items: list[Item], i: int) -> Item:
        \\    return items[i]
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return returned(items, i).number
    );
    try t.expect(!allocated.admitted);
    try t.expect(managed.admitted);
}

// spec-case: RC-READONLY-CALLS-1
test "RC readonly proof keys preserve GC identities" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.gc);
    const result = try witness(t.allocator,
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return items[i].number
    );
    const expected: [32]u8 = @splat(1);
    try t.expectEqual(expected, result.key);
}

// spec-case: RC-READONLY-CALLS-1
test "RC readonly calls refuse mutual recursion" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const result = try witness(t.allocator,
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return middle(items, i)
    );
    try t.expect(!result.admitted);
}

// spec-case: RC-READONLY-CALLS-1
test "RC readonly calls refuse exhausted dependency depth and completion storage" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try t.expect((try dependencyWitness(15, true)).admitted);
    try t.expect(!(try dependencyWitness(16, true)).admitted);
    try t.expect((try dependencyWitness(15, false)).admitted);
    try t.expect(!(try dependencyWitness(16, false)).admitted);
}

// spec-case: RC-READONLY-CALLS-1
test "RC readonly calls emit raw caller and transitive helpers with checked bounds" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(rawReader(try named(manifest.value, "selected")));
    try t.expect(rawReader(try named(manifest.value, "helper0")));
    try t.expect(rawReader(try named(manifest.value, "helper1")));
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "helper1"), "call $myl_qbe_fail_normalized_index_bounds") != null);
}

fn managedEmission() !std.json.Parsed(Manifest) {
    const source = prefix ++
        \\
        \\def pick(items: list[Item], index: int) -> Item:
        \\    return items[index]
        \\def selected(items: list[Item]) -> int:
        \\    first = pick(items, 0)
        \\    second = pick(items, 1)
        \\    return first.number + second.number
        \\def main() -> int:
        \\    return selected([Item(b"a", 3), Item(b"b", 7)])
    ;
    var compilation = try compiler.Compilation.init(t.allocator, "managed_readonly.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

// spec: RC-READONLY-MANAGED-CALLS-1
test "RC readonly managed calls select public alternates without ownership journals" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var output = try managedEmission();
    defer output.deinit();
    const selected = try named(output.value, "selected");
    try t.expect(rawReader(selected));
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, selected, "_rc_borrow(l %ctx"));
    // The canonical managed helper remains independently owned.
    try t.expect(std.mem.indexOf(u8, try named(output.value, "pick"), "call $myl_qbe_rc_frame_enter") != null);
}

// spec-case: RC-READONLY-MANAGED-CALLS-1
test "RC readonly managed calls invalidate unchanged callers when public certificates disappear" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const before = try witness(t.allocator,
        \\def returned(items: list[Item], i: int) -> Item:
        \\    return items[i]
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return returned(items, i).number
    );
    const after = try witness(t.allocator,
        \\def returned(items: list[Item], i: int) -> Item:
        \\    if i < 0:
        \\        return Item(b"x", 11)
        \\    other = [items[i]]
        \\    return other[0]
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return returned(items, i).number
    );
    try t.expect(before.admitted);
    try t.expect(!after.admitted);
    try t.expect(!std.mem.eql(u8, &before.key, &after.key));
}

fn managedDependencies(count: usize) !Witness {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(t.allocator);
    try source.appendSlice(t.allocator, prefix ++ "\ndef selected(items: list[Item]) -> int:\n    return left(items) + right(items)\n");
    for ([_][]const u8{ "left", "right" }, 0..) |name, side| {
        try source.print(t.allocator, "def {s}(items: list[Item]) -> int:\n    total = 0\n", .{name});
        for (0..count) |i| if (i % 2 == side) {
            try source.print(t.allocator, "    total += pick{d}(items).number\n", .{i});
        };
        try source.appendSlice(t.allocator, "    return total\n");
    }
    for (0..count) |i| try source.print(t.allocator, "def pick{d}(items: list[Item]) -> Item:\n    return items[0]\n", .{i});
    try source.appendSlice(t.allocator, "def main() -> int:\n    return selected([Item(b\"a\", 3)])\n");
    return witnessSource(t.allocator, source.items);
}

// spec-case: RC-READONLY-MANAGED-CALLS-1
test "RC readonly managed queries share one root bound across plain descendants" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try t.expect((try managedDependencies(16)).admitted);
    try t.expect(!(try managedDependencies(17)).admitted);
}

const RouteChange = enum { none, missing, target, shape };
fn routed(change: RouteChange) !?@import("rc_model.zig").BorrowCertificate {
    const source = prefix ++
        \\
        \\def pick(items: list[Item]) -> Item:
        \\    return items[0]
        \\def main() -> int:
        \\    return pick([Item(b"a", 3)]).number
    ;
    var compilation = try compiler.Compilation.init(t.allocator, "route.my", source);
    defer compilation.deinit();
    try compilation.emit();
    const program = compilation.code.?;
    const callee = program.functions[0];
    var layouts = try native.Catalog.initRecords(t.allocator, program.records);
    defer layouts.deinit();
    var catalog = try shapes.Catalog.init(t.allocator, &layouts);
    defer catalog.deinit();
    const certificate = (try @import("rc_calls.zig").borrowedIn(t.allocator, &catalog, program.functions, callee, "rc-v3")) orelse return error.TestUnexpectedResult;
    var route = [_]calls.Route{.{ .pc = 0, .target = callee.id, .certificate = certificate }};
    switch (change) {
        .target => route[0].target = @fromBackingInt(999),
        .shape => route[0].certificate.shape_identity[0] ^= 1,
        else => {},
    }
    const State = struct { readonly: bool, catalog: *shapes.Catalog, plan: struct { readonly: ?calls.Certificate } };
    const Cow = struct { rc: ?*State };
    const E = struct { cow: ?*Cow, pc: usize, states: []const ?[]const @import("typed.zig").Type };
    var state: State = .{ .readonly = true, .catalog = &catalog, .plan = .{ .readonly = .{ .identity = @splat(0), .calls = if (change == .missing) &.{} else &route } } };
    var cow: Cow = .{ .rc = &state };
    var emitter: E = .{ .cow = &cow, .pc = 0, .states = &.{&.{callee.scope.locals[0].ty}} };
    return @import("qbe_rc_readonly_calls.zig").route(E, &emitter, callee);
}

// spec-case: RC-READONLY-MANAGED-CALLS-1
test "RC readonly managed routes never fall back on missing target or layout proof" {
    try t.expect((try routed(.none)) != null);
    try t.expectError(error.InternalError, routed(.missing));
    try t.expectError(error.InternalError, routed(.target));
    try t.expectError(error.InternalError, routed(.shape));
}

fn sourceEmission(source: []const u8) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, filename, source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

// spec-case: RC-READONLY-MANAGED-CALLS-1
test "RC readonly composition keeps pure conditional collection captures raw" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const source =
        \\def selected(first: list[int], second: list[int], choice: bool) -> int:
        \\    return len(first if choice else second)
        \\def main() -> int:
        \\    return selected([1], [2, 3], True)
    ;
    try t.expect((try witnessSource(t.allocator, source)).admitted);
    var output = try sourceEmission(source);
    defer output.deinit();
    try t.expect(rawReader(try named(output.value, "selected")));
}

fn conservativeCapture() !bool {
    const source =
        \\def leaf(first: list[int], second: list[int], choice: bool) -> int:
        \\    return len(first if choice else second)
        \\def selected(first: list[int], second: list[int], choice: bool) -> int:
        \\    return leaf(first, second, choice)
        \\def main() -> int:
        \\    return selected([1], [2, 3], True)
    ;
    var compilation = try compiler.Compilation.init(t.allocator, "capture.my", source);
    defer compilation.deinit();
    try compilation.emit();
    var program = compilation.code.?;
    const functions = try t.allocator.dupe(bytecode.Function, program.functions);
    defer t.allocator.free(functions);
    program.functions = functions;
    // Keep the conditional value on the operand stack instead of materializing
    // its two arms through a local. This is valid pure bytecode; the general
    // ownership planner conservatively loses its exact root at the join.
    const old = functions[0].scope.instructions;
    var code = [_]bytecode.Instruction{ old[0], old[1], old[2], old[4], old[5], old[8], old[9], old[10], old[11] };
    code[1].op = .{ .jump_if_false = 4 };
    code[3].op = .{ .jump = 5 };
    functions[0].scope.instructions = &code;
    try bytecode.validate(t.allocator, program);
    var layouts = try native.Catalog.initRecords(t.allocator, program.records);
    defer layouts.deinit();
    var catalog = try shapes.Catalog.init(t.allocator, &layouts);
    defer catalog.deinit();
    var budget: @import("rc_readonly_plan.zig").Budget = .{};
    const grammar = try @import("rc_readonly_body.zig").certify(&catalog, functions[0]);
    const physical = try @import("rc_readonly_plan.zig").certify(&catalog, functions, functions[0], &budget);
    const leaf = try calls.identity(&catalog, functions, functions[0], "rc-v3");
    const root = try calls.identity(&catalog, functions, functions[1], "rc-v3");
    return grammar and !physical and leaf == null and root == null;
}

// spec-case: RC-READONLY-MANAGED-CALLS-1
test "RC readonly conservative capture refusal propagates through plain callers" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try t.expect(try conservativeCapture());
}

// spec-case: RC-READONLY-MANAGED-CALLS-1
test "RC readonly byte indexing admits immutable octets and refuses mutable buffers" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const source =
        \\def octets(values: list[bytes], index: int) -> bytes:
        \\    return values[index]
        \\def selected(values: list[bytes], index: int) -> int:
        \\    saved = octets(values, 0)
        \\    return int(saved[index])
        \\def main() -> int:
        \\    return selected([b"abc"], -1)
    ;
    try t.expect((try witnessSource(t.allocator, source)).admitted);
    var output = try sourceEmission(source);
    defer output.deinit();
    const il = try named(output.value, "selected");
    try t.expect(rawReader(il));
    try t.expect(std.mem.indexOf(u8, il, "_rc_borrow(l %ctx") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_fail_index_bounds") != null);
    try t.expect(!(try witnessSource(t.allocator,
        \\def selected(value: byte_buffer, index: int) -> int:
        \\    return int(value[index])
        \\def main() -> int:
        \\    return 0
    )).admitted);
    try t.expect(!(try witnessSource(t.allocator,
        \\def selected(value: str, index: int) -> int:
        \\    return len(value[index])
        \\def main() -> int:
        \\    return 0
    )).admitted);
    try t.expect(!(try witnessSource(t.allocator,
        \\def selected(value: dict[int, int], index: int) -> int:
        \\    return value[index]
        \\def main() -> int:
        \\    return 0
    )).admitted);
}

// spec-case: RC-READONLY-MANAGED-CALLS-1
test "RC readonly plain descendants select their own managed alternate routes" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var output = try sourceEmission(prefix ++
        \\
        \\def pick(items: list[Item], index: int) -> Item:
        \\    return items[index]
        \\def middle(items: list[Item]) -> int:
        \\    saved = pick(items, 0)
        \\    current = pick(items, 1)
        \\    return saved.number + current.number
        \\def selected(items: list[Item]) -> int:
        \\    return middle(items) + 1
        \\def main() -> int:
        \\    return selected([Item(b"a", 3), Item(b"b", 7)])
    );
    defer output.deinit();
    try t.expect(rawReader(try named(output.value, "selected")));
    const middle = try named(output.value, "middle");
    try t.expect(rawReader(middle));
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, middle, "_rc_borrow(l %ctx"));
}

// spec-case: RC-READONLY-MANAGED-CALLS-1
test "RC readonly large helper results materialize saved bits before repeated calls" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var output = try sourceEmission(
        \\record Big:
        \\    text: bytes
        \\    padding: [600]int
        \\    number: int
        \\def pick(items: list[Big], index: int) -> Big:
        \\    return items[index]
        \\def selected(items: list[Big]) -> int:
        \\    saved = pick(items, 0)
        \\    total = 0
        \\    i = 0
        \\    while i < 2:
        \\        current = pick(items, i)
        \\        total += saved.number + current.number + int(saved.text[0])
        \\        i += 1
        \\    return total
        \\def main() -> int:
        \\    return 0
    );
    defer output.deinit();
    const selected = try named(output.value, "selected");
    try t.expect(rawReader(selected));
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, selected, "_rc_borrow(l %ctx, l %aux"));
    try t.expect(std.mem.count(u8, selected, ", 4816\n") >= 2);
}
