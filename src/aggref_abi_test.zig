//! One QBE-AGGREF-1 crossing decision for the QBE emitter and the generated
//! copied-value adapter: the manifest records it, the generated C consumes it
//! without re-deriving it, and both are checked against the emitted QBE callee
//! signature for the same program.
const std = @import("std");
const language = @import("compiler.zig");
const v = @import("qbe_build_value.zig");
const embed = @import("qbe_build_embed.zig");
const shape = @import("qbe_build_shapes.zig");
const Value = std.json.Value;

/// A guest program whose exported functions cover every argument shape the
/// copied boundary carries: a scalar word, a plain record, a fixed array, a
/// nested record, and an aggregate far past the 4096-byte by-value budget.
const guest =
    \\module main
    \\
    \\
    \\public record Inner:
    \\    a: i64
    \\    b: i64
    \\
    \\
    \\public record Outer:
    \\    inner: Inner
    \\    values: [4]i64
    \\
    \\
    \\public def take_scalar(x: i64) -> i64:
    \\    return x
    \\
    \\
    \\public def take_record(p: Inner) -> i64:
    \\    return p.a + p.b
    \\
    \\
    \\public def take_array(values: [4]i64) -> i64:
    \\    return values[0]
    \\
    \\
    \\public def take_nested(o: Outer) -> i64:
    \\    return o.inner.a + o.values[0]
    \\
    \\
    \\public def take_big(values: [600]i64) -> i64:
    \\    return values[0]
    \\
    \\
    \\def main() -> int:
    \\    return 0
;

/// Serve the one guest module every agreement check compiles.
fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, guest);
    return error.NotFound;
}

/// Emit the `qbe-units-v1` manifest through the real project path, so the
/// exported signatures and their roots are the ones a native build sees.
fn emitted(allocator: std.mem.Allocator) ![]u8 {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    return compilation.emitQbe(allocator);
}

/// The parameter spellings of one `export function` in one emitted unit, the
/// leading context word first.
fn calleeParameters(allocator: std.mem.Allocator, il: []const u8, symbol: []const u8) ![]const []const u8 {
    const marker = try std.fmt.allocPrint(allocator, "${s}(", .{symbol});
    const at = std.mem.indexOf(u8, il, marker) orelse return error.MissingSignature;
    const open = at + marker.len - 1;
    const close = std.mem.indexOfScalarPos(u8, il, open, ')') orelse return error.MissingSignature;
    var parameters: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, il[open + 1 .. close], ',');
    while (it.next()) |parameter| {
        const spelling = std.mem.trim(u8, parameter, " ");
        const space = std.mem.indexOfScalar(u8, spelling, ' ') orelse return error.MissingSignature;
        try parameters.append(allocator, spelling[0..space]);
    }
    return parameters.items;
}

/// Every C parameter list the generated adapter spells for one symbol, each
/// list keeping its leading context pointer.
fn declarations(allocator: std.mem.Allocator, source: []const u8, symbol: []const u8) ![]const []const []const u8 {
    const marker = try std.fmt.allocPrint(allocator, " {s}(void *", .{symbol});
    var lists: std.ArrayList([]const []const u8) = .empty;
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, marker)) |at| {
        cursor = at + marker.len;
        const open = at + (std.mem.indexOfScalar(u8, marker, '(') orelse return error.MissingSignature);
        const close = std.mem.indexOfScalarPos(u8, source, open, ')') orelse return error.MissingSignature;
        var list: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, source[open + 1 .. close], ',');
        while (it.next()) |parameter| try list.append(allocator, std.mem.trim(u8, parameter, " "));
        try lists.append(allocator, list.items);
    }
    return lists.items;
}

/// Require the manifest's recorded crossing, the emitted QBE callee signature
/// and every generated C declaration to agree parameter by parameter.
fn agree(allocator: std.mem.Allocator, manifest: Value) !void {
    const types = v.array(v.get(manifest, "wire_types"));
    const adapter: shape.Shapes = .{ .types = types };
    const source = try embed.libraryWrapper(allocator, manifest);
    var exported: usize = 0;
    for (v.array(v.get(manifest, "functions"))) |function| {
        const item = v.get(function, "export");
        if (item == .null) continue;
        exported += 1;
        const symbol = v.text(v.get(function, "symbol"));
        const parameters = v.array(v.get(item, "parameters"));
        const callee = try calleeParameters(allocator, v.text(v.get(function, "il")), symbol);
        const lists = try declarations(allocator, source, symbol);
        try std.testing.expectEqual(parameters.len + 1, callee.len);
        try std.testing.expect(lists.len != 0);
        for (parameters, 0..) |parameter, i| {
            const name = v.text(parameter);
            const pointer = try adapter.byAddress(name);
            const word = try adapter.scalar(name);
            // The emitter and the manifest cannot disagree: a recorded crossing
            // is the emitted `l` address, a scalar word is the emitted `l` too,
            // and neither is ever a by-value aggregate.
            if (pointer or word) try std.testing.expectEqualStrings("l", callee[i + 1]);
            if (pointer) try std.testing.expect(!word);
            if (!pointer and !word) try std.testing.expect(!std.mem.eql(u8, "l", callee[i + 1]));
            for (lists) |list| {
                try std.testing.expectEqual(parameters.len + 1, list.len);
                if (pointer) try std.testing.expectEqualStrings("const void *", list[i + 1]);
                if (word) try std.testing.expectEqualStrings("uint64_t", list[i + 1]);
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 5), exported);
}

// spec: QBE-AGGREF-3
test "every exported aggregate argument is recorded as a crossing and emitted as an address" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const manifest = try emitted(arena.allocator());
    const parsed = try std.json.parseFromSlice(Value, arena.allocator(), manifest, .{ .allocate = .alloc_always });
    const types = v.array(v.get(parsed.value, "wire_types"));
    const adapter: shape.Shapes = .{ .types = types };
    try std.testing.expect(try adapter.byAddress("main::Inner"));
    try std.testing.expect(try adapter.byAddress("[4]i64"));
    try std.testing.expect(try adapter.byAddress("main::Outer"));
    try std.testing.expect(try adapter.byAddress("[600]i64"));
    try std.testing.expect(!try adapter.byAddress("i64"));
    try agree(arena.allocator(), parsed.value);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"by_address\":true") != null);
}

/// A hand-written manifest whose recorded crossing deliberately contradicts the
/// type's own shape, so only an adapter that reads the field can match it.
const contradictory =
    \\{"entry":"","entry_parameters":[],"schema":null,"codecs":null,
    \\"wire_types":[
    \\{"name":"i64","kind":"scalar","size":8,"alignment":8,"count":0,"stride":0,"fields":[],"by_address":false},
    \\{"name":"Box","kind":"record","size":8,"alignment":8,"count":1,"stride":0,"fields":[{"type":"i64","offset":0}],"by_address":false},
    \\{"name":"Ptr","kind":"record","size":8,"alignment":8,"count":1,"stride":0,"fields":[{"type":"i64","offset":0}],"by_address":true}],
    \\"functions":[{"symbol":"takes","export":{"name":"m::takes","parameters":["Box","Ptr","i64"],"parameter_names":["b","p","x"],"result":"i64","scalar":false,"references":false}}]}
;

// spec: QBE-AGGREF-4
test "the generated adapter spells and passes an argument from the recorded crossing alone" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const parsed = try std.json.parseFromSlice(Value, arena.allocator(), contradictory, .{ .allocate = .alloc_always });
    const source = try embed.libraryWrapper(arena.allocator(), parsed.value);
    // `Box` is a record and `Ptr` is the same record, so only the recorded
    // field separates the by-value C parameter from the address parameter.
    try std.testing.expect(std.mem.indexOf(u8, source, "extern uint64_t takes(void *, WireValue1, const void *, uint64_t);") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "takes(ctx,*(WireValue1 *)wire_arguments[0],wire_arguments[1],wire_word(wire_arguments[2],&wire_types[0]))") != null);
}

// spec-case: QBE-AGGREF-4
test "a malformed adapter or unit is rejected rather than agreed with" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    try std.testing.expectError(error.MissingSignature, calleeParameters(arena.allocator(), "export function l $other(l %ctx) {", "takes"));
    try std.testing.expectError(error.MissingSignature, declarations(arena.allocator(), "extern uint64_t takes(void *", "takes"));
    try std.testing.expectEqual(@as(usize, 0), (try declarations(arena.allocator(), "", "takes")).len);
}

// spec-case: QBE-AGGREF-6
test "one ABI identity has one definition on each side of the module boundary" {
    // The compiler owns the manifest tag as `native_test_dependencies.abi` and
    // the native build driver owns the same tag as `qbe_build.native_abi`. A
    // single file cannot hold it for both: Zig lets a file belong to only one
    // module, and the driver is compiled both inside the compiler executable
    // (root module) and as its own `qbe_build` module. This test is the join —
    // it sees both modules at once, so a bump on either side alone fails here
    // instead of letting the driver accept a manifest the emitter never writes.
    const compiler_abi = @import("native_test_dependencies.zig").abi;
    const driver = @import("qbe_build.zig");
    try std.testing.expectEqualStrings(compiler_abi, driver.native_abi);
    try std.testing.expect(std.mem.indexOf(u8, driver.generation_identity, compiler_abi) != null);
}
