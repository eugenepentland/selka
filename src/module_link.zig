//! MODULE-COMPILE-3: merge the per-module units files a program's module
//! compiles wrote (`<module>.units.json`) into the one executable manifest the
//! build driver links, which is the manifest a whole-program emission writes.
const std = @import("std");
const native_descriptors = @import("native_descriptors.zig");
const native_render = @import("native_render.zig");
const owners = @import("rc_descriptors.zig");
const glue = @import("rc_glue.zig");
const Map = std.array_hash_map.String;

/// Why the modules' units do not make one program: two modules emitted one
/// symbol with different units (`Conflict`), or no module is the entry, or
/// the modules name different unit stores (`Incomplete`).
pub const Error = error{ OutOfMemory, Conflict, Incomplete };

/// The manifest member a unit's text-runtime need is merged from.
const text_format = "text_format";

/// One program manifest from the parsed units files of every module: each
/// unit once (a specialization two modules emitted must be the same unit),
/// the union of the modules' descriptor and renderer blocks rendered in symbol
/// order as a whole emission renders them, the union of their host bridges,
/// the entry module's entry, and the text runtime when any module needs it.
/// Everything is allocated with `allocator`, an arena.
pub fn merge(allocator: std.mem.Allocator, files: []const std.json.Value) Error![]const u8 {
    var state: Merge = .{ .allocator = allocator };
    for (files) |file| try state.add(file);
    return state.finish();
}

/// Everything one link accumulates from the modules' units files.
const Merge = struct {
    allocator: std.mem.Allocator,
    functions: Map(std.json.Value) = .empty,
    descriptors: Map([]const u8) = .empty,
    renderers: Map([]const u8) = .empty,
    host: Host = .{},
    shared: Shared = .{},
    entry: ?std.json.Value = null,
    store: ?[]const u8 = null,
    text: bool = false,

    fn add(self: *Merge, file: std.json.Value) Error!void {
        const manifest = field(file, "manifest");
        const store = string(field(manifest, "store"));
        if (self.store) |known| {
            if (!std.mem.eql(u8, known, store)) return error.Incomplete;
        } else self.store = store;
        for (array(field(manifest, "functions"))) |unit| {
            const entry = try self.functions.getOrPut(self.allocator, string(field(unit, "symbol")));
            if (!entry.found_existing) {
                entry.value_ptr.* = unit;
                continue;
            }
            for ([_][]const u8{ "il_digest", "meta_digest", "il", "il_facts", "locations", "messages", "inlines" }) |key| {
                if (!try equal(self.allocator, field(entry.value_ptr.*, key), field(unit, key))) return error.Conflict;
            }
        }
        try blocks(self.allocator, &self.descriptors, field(file, "descriptors"));
        try blocks(self.allocator, &self.renderers, field(file, "renderers"));
        try self.host.add(self.allocator, field(manifest, "host"));
        try self.shared.add(self.allocator, file, manifest);
        const needs_text = field(manifest, text_format);
        if (needs_text == .bool and needs_text.bool) self.text = true;
        if (string(field(manifest, "entry")).len != 0) self.entry = manifest;
    }

    fn finish(self: *Merge) Error![]const u8 {
        const entry = self.entry orelse return error.Incomplete;
        const a = self.allocator;
        const described = native_descriptors.render(a, try sortedBlocks(native_descriptors.Block, a, self.descriptors)) catch return error.OutOfMemory;
        const rendered = native_render.render(a, try sortedBlocks(native_render.Block, a, self.renderers)) catch return error.OutOfMemory;
        var functions = std.json.Array.init(a);
        try functions.appendSlice(self.functions.values());
        var object = try entry.object.clone(a);
        try object.put(a, "functions", .{ .array = functions });
        const owned = if (self.shared.owners.count() != 0) owners.render(a, try self.shared.ownerBlocks(a)) catch return error.OutOfMemory else "";
        const glued = if (self.shared.owners.count() != 0) glue.render(a, try sortedBlocks(glue.Block, a, self.shared.glue)) catch return error.OutOfMemory else "";
        try object.put(a, "runtime_data", .{ .string = try std.mem.concat(a, u8, &.{ described, rendered, owned, glued }) });
        try object.put(a, "embeds", try unionValue(a, self.shared.embeds));
        try object.put(a, "codecs", @import("module_codecs.zig").merge(a, self.shared.codecs.items) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.Conflict,
        });
        try object.put(a, "wire_types", try unionValue(a, self.shared.wire));
        try object.put(a, text_format, .{ .bool = self.text });
        try object.put(a, "host", try self.host.value(a));
        return std.json.Stringify.valueAlloc(a, std.json.Value{ .object = object }, .{}) catch return error.OutOfMemory;
    }
};

/// Runtime contracts and definition tables are link dependencies, never entry-local.
const Shared = struct {
    contract: ?[]const u8 = null,
    owners: Map(std.json.Value) = .empty,
    glue: Map([]const u8) = .empty,
    embeds: Map(std.json.Value) = .empty,
    codecs: std.ArrayList(std.json.Value) = .empty,
    wire: Map(std.json.Value) = .empty,

    fn add(self: *Shared, a: std.mem.Allocator, file: std.json.Value, manifest: std.json.Value) Error!void {
        const contract = string(field(manifest, "runtime_contract"));
        if (contract.len == 0) return error.Incomplete;
        if (self.contract) |known| {
            if (!std.mem.eql(u8, known, contract)) return error.Conflict;
        } else self.contract = contract;
        try unionRows(a, &self.owners, field(file, "owners"), "name");
        try blocks(a, &self.glue, field(file, "glue"));
        try unionRows(a, &self.embeds, field(manifest, "embeds"), "symbol");
        try self.codecs.append(a, field(manifest, "codecs"));
        try unionRows(a, &self.wire, field(manifest, "wire_types"), "name");
    }

    fn ownerBlocks(self: Shared, a: std.mem.Allocator) Error![]owners.Block {
        const rows = try sortedValues(a, self.owners);
        const out = try a.alloc(owners.Block, rows.len);
        for (rows, out) |row, *block| {
            const unique = field(row, "unique_body");
            if (unique != .bool) return error.Incomplete;
            const text = string(field(row, "text"));
            if (!owners.imageBlock(text)) return error.Incomplete;
            block.* = .{ .name = string(field(row, "name")), .text = text, .unique_body = unique.bool };
        }
        return out;
    }
};

fn unionRows(a: std.mem.Allocator, into: *Map(std.json.Value), list: std.json.Value, key: []const u8) Error!void {
    for (array(list)) |row| {
        const name = string(field(row, key));
        if (name.len == 0) return error.Incomplete;
        const entry = try into.getOrPut(a, name);
        if (entry.found_existing) {
            if (!try equal(a, entry.value_ptr.*, row)) return error.Conflict;
        } else entry.value_ptr.* = row;
    }
}

fn unionValue(a: std.mem.Allocator, rows: Map(std.json.Value)) Error!std.json.Value {
    if (rows.count() == 0) return .null;
    var out = std.json.Array.init(a);
    try out.appendSlice(try sortedValues(a, rows));
    return .{ .array = out };
}

fn equal(a: std.mem.Allocator, left: std.json.Value, right: std.json.Value) Error!bool {
    const x = std.json.Stringify.valueAlloc(a, left, .{}) catch return error.OutOfMemory;
    const y = std.json.Stringify.valueAlloc(a, right, .{}) catch return error.OutOfMemory;
    return std.mem.eql(u8, x, y);
}

/// The union of the modules' host bridge declarations and type rows, each
/// once, in name order.
const Host = struct {
    declarations: Map(std.json.Value) = .empty,
    types: Map(std.json.Value) = .empty,

    fn add(self: *Host, a: std.mem.Allocator, host: std.json.Value) Error!void {
        try unionRows(a, &self.declarations, field(host, "declarations"), "symbol");
        try unionRows(a, &self.types, field(host, "types"), "name");
    }

    fn value(self: *Host, a: std.mem.Allocator) Error!std.json.Value {
        var out: std.json.ObjectMap = .empty;
        var declarations = std.json.Array.init(a);
        var types = std.json.Array.init(a);
        if (self.declarations.count() != 0) {
            try declarations.appendSlice(try sortedValues(a, self.declarations));
            try types.appendSlice(try sortedValues(a, self.types));
        }
        try out.put(a, "types", .{ .array = types });
        try out.put(a, "declarations", .{ .array = declarations });
        return .{ .object = out };
    }
};

fn sortedValues(a: std.mem.Allocator, map: Map(std.json.Value)) Error![]std.json.Value {
    const keys = try a.dupe([]const u8, map.keys());
    std.mem.sort([]const u8, keys, {}, lessText);
    const out = try a.alloc(std.json.Value, keys.len);
    for (keys, out) |key, *slot| slot.* = map.get(key).?;
    return out;
}

/// Add each `{name, text}` block of `list`; one name must always carry one text.
fn blocks(a: std.mem.Allocator, into: *Map([]const u8), list: std.json.Value) Error!void {
    for (array(list)) |block| {
        const entry = try into.getOrPut(a, string(field(block, "name")));
        const body = string(field(block, "text"));
        if (entry.found_existing) {
            if (!std.mem.eql(u8, entry.value_ptr.*, body)) return error.Conflict;
        } else entry.value_ptr.* = body;
    }
}

/// The blocks of `map` as `Block`s, ordered by name.
fn sortedBlocks(comptime Block: type, a: std.mem.Allocator, map: Map([]const u8)) Error![]Block {
    const keys = try a.dupe([]const u8, map.keys());
    std.mem.sort([]const u8, keys, {}, lessText);
    const out = try a.alloc(Block, keys.len);
    for (keys, out) |key, *block| block.* = .{ .name = key, .text = map.get(key).? };
    return out;
}

fn field(value: std.json.Value, name: []const u8) std.json.Value {
    if (value != .object) return .null;
    return value.object.get(name) orelse .null;
}

fn array(value: std.json.Value) []const std.json.Value {
    return if (value == .array) value.array.items else &.{};
}

fn string(value: std.json.Value) []const u8 {
    return if (value == .string) value.string else "";
}

fn lessText(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
