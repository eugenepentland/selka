//! Constant managed results have a distinct public proof and physical entry.
const std = @import("std");
const typed = @import("typed.zig");
const compiler = @import("compiler.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const calls = @import("rc_calls.zig");
const readonly = @import("rc_readonly_calls.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const source =
    \\record Span:
    \\    source: bytes
    \\    number: int
    \\def empty() -> Span:
    \\    return Span(b"", 0)
    \\def pick(items: list[Span], index: int) -> Span:
    \\    if index < 0:
    \\        return empty()
    \\    return items[index]
    \\def selected(items: list[Span]) -> int:
    \\    return pick(items, -1).number + pick(items, 0).number
    \\def main() -> int:
    \\    return selected([Span(b"a", 7)])
;
const Witness = struct { immortal: bool, borrowed: bool, raw: bool, digest: [32]u8 = @splat(0) };
fn witness(text: []const u8, name: []const u8) !Witness {
    var compilation = try compiler.Compilation.init(t.allocator, "immortal.my", text);
    defer compilation.deinit();
    try compilation.emit();
    const program = compilation.code.?;
    var layouts = try native.Catalog.initRecords(t.allocator, program.records);
    defer layouts.deinit();
    var catalog = try shapes.Catalog.init(t.allocator, &layouts);
    defer catalog.deinit();
    for (program.functions) |function| if (std.mem.eql(u8, function.name, name)) {
        const immortal = try calls.immortalIn(&catalog, program.functions, function, "rc-v3");
        const borrowed = try calls.borrowedIn(t.allocator, &catalog, program.functions, function, "rc-v3");
        var result: Witness = .{ .immortal = immortal != null, .borrowed = borrowed != null, .raw = false };
        const raw = if (immortal) |proof|
            try readonly.immortalEntry(&catalog, program.functions, function, "rc-v3", proof)
        else if (borrowed) |proof|
            try readonly.borrowedEntry(&catalog, program.functions, function, "rc-v3", proof)
        else
            try readonly.certify(&catalog, program.functions, function, "rc-v3");
        if (raw) |proof| {
            defer t.allocator.free(proof.calls);
            result.raw = true;
            result.digest = proof.identity;
        }
        return result;
    };
    return error.TestUnexpectedResult;
}

// spec: RC-IMMORTAL-ENTRY-1
test "RC immortal public authority composes with anchored borrowed entry" {
    const constant = try witness(source, "empty");
    const anchored = try witness(source, "pick");
    try t.expect(constant.immortal and constant.raw and !constant.borrowed);
    try t.expect(anchored.borrowed and anchored.raw and !anchored.immortal);
    try t.expect((try witness(source, "selected")).raw);
}

// spec-case: RC-IMMORTAL-ENTRY-1
test "RC immortal certificate refuses allocated constructors and binds literal bytes" {
    try t.expect(!(try witness("def empty() -> list[int]:\n    return []\ndef main() -> int:\n    return 0\n", "empty")).immortal);
    try t.expect(!(try witness("def empty() -> byte_buffer:\n    return byte_buffer([])\ndef main() -> int:\n    return 0\n", "empty")).immortal);
    try t.expect(!(try witness("def empty() -> str:\n    return \"x\"\ndef main() -> int:\n    return 0\n", "empty")).immortal);
    const before = try witness("def empty() -> bytes:\n    return b\"left\"\ndef main() -> int:\n    return 0\n", "empty");
    const after = try witness("def empty() -> bytes:\n    return b\"right\"\ndef main() -> int:\n    return 0\n", "empty");
    try t.expect(before.immortal and after.immortal);
    try t.expect(!std.mem.eql(u8, &before.digest, &after.digest));
}

const Manifest = struct { functions: []const struct { name: []const u8, symbol: []const u8, il: []const u8 } };
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "immortal.my", source);
    defer compilation.deinit();
    const encoded = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(encoded);
    return std.json.parseFromSlice(Manifest, t.allocator, encoded, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8, suffix: []const u8) ![]const u8 {
    for (manifest.functions) |function| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        const alternate = std.mem.endsWith(u8, function.symbol, "_rc_borrow") or std.mem.endsWith(u8, function.symbol, "_rc_immortal");
        if (suffix.len == 0 and !alternate) return function.il;
        if (suffix.len != 0 and std.mem.endsWith(u8, function.symbol, suffix)) return function.il;
    }
    return error.TestUnexpectedResult;
}

// spec-case: RC-IMMORTAL-ENTRY-1
test "RC immortal calls target separate raw unit while canonical stays owned" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const manifest = try emitted();
    defer manifest.deinit();
    const constant = try named(manifest.value, "empty", "_rc_immortal");
    const anchored = try named(manifest.value, "pick", "_rc_borrow");
    try t.expect(std.mem.indexOf(u8, constant, "# rc-frame") == null);
    try t.expect(std.mem.indexOf(u8, constant, "# myl-lit ") != null);
    try t.expect(std.mem.indexOf(u8, constant, "call $myl_qbe_fail_frame") != null);
    try t.expect(std.mem.indexOf(u8, anchored, "# rc-frame") == null);
    try t.expect(std.mem.indexOf(u8, anchored, "_rc_immortal(l %ctx") != null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "empty", ""), "# rc-frame") != null);
}

const Change = enum { none, shape, dependency, unavailable, traced };
fn changed(change: Change) !bool {
    const text = "def empty() -> bytes:\n    current = b\"ok\"\n    return current\ndef main() -> int:\n    return 0\n";
    var compilation = try compiler.Compilation.init(t.allocator, "immortal_change.my", text);
    defer compilation.deinit();
    try compilation.emit();
    const program = compilation.code.?;
    var layouts = try native.Catalog.initRecords(t.allocator, program.records);
    defer layouts.deinit();
    var catalog = try shapes.Catalog.init(t.allocator, &layouts);
    defer catalog.deinit();
    var function = program.functions[0];
    const original = try calls.immortalIn(&catalog, program.functions, function, "rc-v3");
    if (change == .none) return original != null;
    if (change == .shape or change == .dependency) {
        var supplied = original orelse return error.TestUnexpectedResult;
        if (change == .shape) supplied.shape_identity[0] ^= 1 else supplied.dependency_identity[0] ^= 1;
        const raw = try readonly.immortalEntry(&catalog, program.functions, function, "rc-v3", supplied);
        if (raw) |proof| t.allocator.free(proof.calls);
        return raw != null;
    }
    const code = try t.allocator.dupe(@import("bytecode.zig").Instruction, function.scope.instructions);
    defer t.allocator.free(code);
    function.scope.instructions = code;
    if (change == .unavailable) code[0].op = .{ .load_local = @fromBackingInt(0) } else code[0].op = .{ .call = function.id };
    return (try calls.immortalIn(&catalog, program.functions, function, "rc-v3")) != null;
}

// spec-case: RC-IMMORTAL-ENTRY-1
test "RC immortal entry refuses mismatched proof unavailable bits and calls" {
    try t.expect(try changed(.none));
    try t.expect(!try changed(.shape));
    try t.expect(!try changed(.dependency));
    try t.expect(!try changed(.unavailable));
    try t.expect(!try changed(.traced));
}

fn literalBound(count: usize) !bool {
    const literal = try t.allocator.alloc(u8, count);
    defer t.allocator.free(literal);
    @memset(literal, 'a');
    const text = try std.fmt.allocPrint(t.allocator, "def empty() -> bytes:\n    return b\"{s}\"\ndef main() -> int:\n    return 0\n", .{literal});
    defer t.allocator.free(text);
    return (try witness(text, "empty")).immortal;
}

// spec-case: RC-IMMORTAL-ENTRY-1
test "RC immortal exact literal authority stops at bounded instruction input" {
    try t.expect(try literalBound(126));
    try t.expect(!try literalBound(127));
}

fn targets(count: usize) !bool {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(t.allocator);
    try text.appendSlice(t.allocator, "record Item:\n    text: bytes\n    number: int\ndef selected(items: list[Item]) -> int:\n    total = 0\n");
    for (0..count) |i| try text.print(t.allocator, "    total += helper{d}({s}).number\n", .{ i, if (i % 2 == 0) "" else "items" });
    try text.appendSlice(t.allocator, "    return total\n");
    for (0..count) |i| {
        if (i % 2 == 0) try text.print(t.allocator, "def helper{d}() -> Item:\n    return Item(b\"x\", 1)\n", .{i}) else try text.print(t.allocator, "def helper{d}(items: list[Item]) -> Item:\n    return items[0]\n", .{i});
    }
    try text.appendSlice(t.allocator, "def main() -> int:\n    return 0\n");
    return (try witness(text.items, "selected")).raw;
}

// spec-case: RC-IMMORTAL-ENTRY-1
test "RC immortal and anchored routes share sixteen complete managed targets" {
    try t.expect(try targets(16));
    try t.expect(!try targets(17));
}

const RouteCatalog = struct {
    const Native = struct {
        /// Inject allocation failure in the exact native layout query.
        pub fn layout(_: *@This(), _: typed.Type) error{OutOfMemory}!native.Layout {
            return error.OutOfMemory;
        }
    };
    native: *Native,
    early: bool,
    /// Inject failure before or after managed-shape classification.
    pub fn get(self: *@This(), _: typed.Type) error{OutOfMemory}!struct { counted: bool, unique_drop: bool } {
        if (self.early) return error.OutOfMemory;
        return .{ .counted = true, .unique_drop = false };
    }
};
fn routeFailure(early: bool) !void {
    var compilation = try compiler.Compilation.init(t.allocator, "route_failure.my", "def empty() -> bytes:\n    return b\"a\"\ndef main() -> int:\n    return 0\n");
    defer compilation.deinit();
    try compilation.emit();
    const callee = compilation.code.?.functions[0];
    var layout: RouteCatalog.Native = .{};
    var catalog: RouteCatalog = .{ .native = &layout, .early = early };
    const routes = [_]readonly.Route{.{ .pc = 0, .target = callee.id, .certificate = .{ .immortal = .{ .shape_identity = @splat(0), .dependency_identity = @splat(0) } } }};
    const State = struct { readonly: bool, catalog: *RouteCatalog, plan: struct { readonly: ?readonly.Certificate } };
    const Cow = struct { rc: ?*State };
    const E = struct { cow: ?*Cow, pc: usize, states: []const ?[]const typed.Type };
    var state: State = .{ .readonly = true, .catalog = &catalog, .plan = .{ .readonly = .{ .identity = @splat(0), .calls = &routes } } };
    var cow: Cow = .{ .rc = &state };
    var emitter: E = .{ .cow = &cow, .pc = 0, .states = &.{&.{}} };
    _ = try @import("qbe_rc_readonly_calls.zig").route(E, &emitter, callee);
}

// spec-case: RC-IMMORTAL-ENTRY-1
test "RC immortal route preserves compiler allocation failure at both shape queries" {
    try t.expectError(error.OutOfMemory, routeFailure(true));
    try t.expectError(error.OutOfMemory, routeFailure(false));
}
