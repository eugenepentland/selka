//! Checked domain conversion contracts for the copied native codec-call ABI.
const std = @import("std");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const bytecode = @import("bytecode_model.zig");
/// Checked decode/encode methods and their declared rejection representation.
pub const Codec = struct { domain: []const u8, wire: []const u8, decode: usize, encode: usize, result: []const u8, ok: usize, err: usize, error_type: []const u8 };
/// One compiled codec method the native runtime calls by its exported symbol.
pub const Callback = struct { index: usize, symbol: []const u8, input: []const u8, output: []const u8 };
/// Domain conversion shapes, the native descriptor symbol of each manifest
/// entry, and the compiled methods that implement them. `descriptors` is
/// positionally parallel to `types`: the generated adapter hands the runtime the
/// exact `myl_native_type` the program already publishes for that type, rather
/// than synthesizing a second descriptor that could drift from the collector's.
pub const Metadata = struct {
    types: []const @import("qbe_wire.zig").Type,
    descriptors: []const []const u8,
    codecs: []const Codec,
    callbacks: []const Callback,
    /// Per-type invariant functions invoked only at copied-value boundaries.
    validations: []const Callback = &.{},
};

/// Derive metadata for every declared domain codec in the program.
/// MODULE-TEST-2: canonical, so a merge of each module's metadata is the
/// whole program's: types by name (descriptors alongside), codecs by domain,
/// callbacks by symbol, and each method numbered by its callback's position.
pub fn describe(allocator: std.mem.Allocator, program: bytecode.Program, catalog: *native.Catalog) native.Error!Metadata {
    var codecs: std.ArrayList(Codec) = .empty;
    var callbacks: std.ArrayList(Callback) = .empty;
    for (program.records) |record| if (record.contract.codec) |codec| {
        const result = program.functions[@backingInt(codec.decode)].signature.return_type;
        const shape = typed.resultShape(result, program.records) orelse return error.InvalidType;
        try codecs.append(allocator, .{
            .domain = record.name,
            .wire = typed.typeName(codec.wire, program.records),
            .decode = @backingInt(codec.decode),
            .encode = @backingInt(codec.encode),
            .result = typed.typeName(result, program.records),
            .ok = shape.ok_tag,
            .err = shape.error_tag,
            .error_type = typed.typeName(shape.error_type, program.records),
        });
        for ([_]typed.FunctionId{ codec.decode, codec.encode }) |id| {
            try callbacks.append(allocator, try describeCallback(allocator, program, program.functions[@backingInt(id)]));
        }
    };
    var validations: std.ArrayList(Callback) = .empty;
    for (program.functions) |function| if (@import("invariant_callbacks.zig").isName(function.name)) {
        try validations.append(allocator, try describeCallback(allocator, program, function));
    };
    const table = try @import("qbe_wire.zig").describeWithDomains(allocator, catalog, true);
    const descriptors = try allocator.alloc([]const u8, table.types.len);
    for (table.ids, descriptors) |id, *slot| slot.* = try @import("native_descriptors.zig").symbol(allocator, catalog, id);
    return canonical(allocator, .{
        .types = table.types,
        .descriptors = descriptors,
        .codecs = try codecs.toOwnedSlice(allocator),
        .callbacks = try callbacks.toOwnedSlice(allocator),
        .validations = try validations.toOwnedSlice(allocator),
    });
}

fn describeCallback(allocator: std.mem.Allocator, program: bytecode.Program, function: bytecode.Function) native.Error!Callback {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(function.name, &digest, .{});
    return .{
        .index = @backingInt(function.id),
        .symbol = try std.fmt.allocPrint(allocator, "myl_f_{s}", .{std.fmt.bytesToHex(digest, .lower)}),
        .input = typed.typeName(function.scope.locals[0].ty, program.records),
        .output = typed.typeName(function.signature.return_type, program.records),
    };
}

/// `metadata` with its codecs sorted by domain and its callbacks by symbol,
/// one callback per symbol, and every method index renumbered to its
/// callback's position.
pub fn canonical(allocator: std.mem.Allocator, metadata: Metadata) error{OutOfMemory}!Metadata {
    const callbacks = try allocator.dupe(Callback, metadata.callbacks);
    std.mem.sort(Callback, callbacks, {}, callbackBefore);
    var unique: usize = 0;
    for (callbacks) |callback| {
        if (unique != 0 and std.mem.eql(u8, callbacks[unique - 1].symbol, callback.symbol)) continue;
        callbacks[unique] = callback;
        unique += 1;
    }
    const codecs = try allocator.dupe(Codec, metadata.codecs);
    for (codecs) |*codec| {
        codec.decode = position(metadata.callbacks, callbacks[0..unique], codec.decode);
        codec.encode = position(metadata.callbacks, callbacks[0..unique], codec.encode);
    }
    std.mem.sort(Codec, codecs, {}, codecBefore);
    for (callbacks[0..unique], 0..) |*callback, index| callback.index = index;
    const validations = try allocator.dupe(Callback, metadata.validations);
    std.mem.sort(Callback, validations, {}, callbackBefore);
    for (validations, 0..) |*validation, index| validation.index = index;
    return .{ .types = metadata.types, .descriptors = metadata.descriptors, .codecs = codecs, .callbacks = callbacks[0..unique], .validations = validations };
}

/// The position in `sorted` of the callback `original` numbered `index`.
fn position(original: []const Callback, sorted: []const Callback, index: usize) usize {
    const symbol = for (original) |callback| {
        if (callback.index == index) break callback.symbol;
    } else return index;
    for (sorted, 0..) |callback, at| if (std.mem.eql(u8, callback.symbol, symbol)) return at;
    return index;
}

// spec: MODULE-TEST-2
test "canonical codec metadata sorts codecs and callbacks and renumbers every method" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const metadata = try canonical(arena.allocator(), .{
        .types = &.{},
        .descriptors = &.{},
        .codecs = &.{
            .{ .domain = "m::Zone", .wire = "str", .decode = 7, .encode = 3, .result = "r", .ok = 0, .err = 1, .error_type = "str" },
            .{ .domain = "m::Area", .wire = "str", .decode = 3, .encode = 7, .result = "r", .ok = 0, .err = 1, .error_type = "str" },
        },
        .callbacks = &.{
            .{ .index = 7, .symbol = "myl_f_b", .input = "str", .output = "r" },
            .{ .index = 3, .symbol = "myl_f_a", .input = "str", .output = "r" },
            .{ .index = 7, .symbol = "myl_f_b", .input = "str", .output = "r" },
        },
    });
    try std.testing.expectEqual(@as(usize, 2), metadata.callbacks.len);
    try std.testing.expectEqualStrings("myl_f_a", metadata.callbacks[0].symbol);
    try std.testing.expectEqual(@as(usize, 1), metadata.callbacks[1].index);
    try std.testing.expectEqualStrings("m::Area", metadata.codecs[0].domain);
    try std.testing.expectEqual(@as(usize, 0), metadata.codecs[0].decode);
    try std.testing.expectEqual(@as(usize, 1), metadata.codecs[1].decode);
    try std.testing.expectEqual(@as(usize, 0), metadata.codecs[1].encode);
}

fn callbackBefore(_: void, left: Callback, right: Callback) bool {
    return std.mem.lessThan(u8, left.symbol, right.symbol);
}

fn codecBefore(_: void, left: Codec, right: Codec) bool {
    return std.mem.lessThan(u8, left.domain, right.domain);
}
