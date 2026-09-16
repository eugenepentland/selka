//! Declared contract manifests for selected-provider validation.
//!
//! `mylang list-interfaces --contracts` publishes the exported declarations of a
//! project after signature/visibility checking and before body checking. This
//! module maps provider file paths to module names, extracts the selected test
//! signatures for discovery, and compares a replacement's declared contracts
//! against every public contract it replaces. Exact identity covers names,
//! defaults, types, nominal identities, generic requirements and data shapes;
//! effects, mutation footprints and return origins use the frozen directional
//! subset relation, so a narrower implementation is accepted but a stronger one
//! is not.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
/// Malformed manifests (never produced by this compiler), missing modules and
/// stronger-or-different replacements are all explicit provider failures.
pub const Error = error{ InvalidContracts, IncompatibleProvider, OutOfMemory };
/// The canonical declaration-type descriptor wire version accepted by this validator.
pub const version = "interface-contracts-v2";
const effects_marker = "effects=";
const mutates_marker = ";mutates=";
const origin_marker = ";origin=";
const modules_key = "modules";
const declarations_key = "declarations";
const name_key = "name";
const kind_key = "kind";
const manifest_function_kind = "function";
const signature_key = "signature";
const generics_key = "generics";
const permissions_key = "permissions";
const shape_key = "shape";
const functions_key = "functions";
const version_key = "version";

/// Map each `providers` key (a relative `.my` path) to its dotted module name.
/// Entries are ordered by provider path so a JSON map's key insertion order can
/// never change the selected contract-module sequence or its identity.
pub fn moduleNames(allocator: std.mem.Allocator, providers: std.json.Value) Error![][]const u8 {
    if (providers != .object or providers.object.count() == 0) return error.InvalidContracts;
    const PathPair = struct { path: []const u8, name: []const u8 };
    const pairs = try allocator.alloc(PathPair, providers.object.count());
    defer allocator.free(pairs);
    var entries = providers.object.iterator();
    var index: usize = 0;
    while (entries.next()) |entry| : (index += 1) {
        if (entry.value_ptr.* != .string) {
            for (pairs[0..index]) |pair| allocator.free(pair.name);
            return error.InvalidContracts;
        }
        pairs[index] = .{ .path = entry.key_ptr.*, .name = try moduleNameFromPath(allocator, entry.key_ptr.*) };
    }
    std.mem.sort(PathPair, pairs, {}, struct {
        fn lessThan(_: void, a: PathPair, b: PathPair) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);
    const names = try allocator.alloc([]const u8, pairs.len);
    for (pairs, names) |pair, *name| name.* = pair.name;
    return names;
}

/// `production.my` -> `production`; `a/b.my` -> `a.b`.
pub fn moduleNameFromPath(allocator: std.mem.Allocator, path: []const u8) Error![]const u8 {
    if (!std.mem.endsWith(u8, path, ".my") or path.len == 3) return error.InvalidContracts;
    const stem = path[0 .. path.len - 3];
    const name = try allocator.dupe(u8, stem);
    for (name) |*byte| if (byte.* == '/') {
        byte.* = '.';
    };
    return name;
}

/// One provider replacement entry for canonical identity ordering.
const ProviderPair = struct { path: []const u8, source: []const u8 };

fn providerLessThan(_: void, a: ProviderPair, b: ProviderPair) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

/// A stable identity for the replacement sources named by one case's providers.
/// Entries are sorted by path and length-prefixed, so JSON key insertion order
/// cannot produce a distinct graph identity for the same replacement set.
pub fn providerIdentity(allocator: std.mem.Allocator, providers: std.json.Value) Error![]const u8 {
    if (providers != .object) return error.InvalidContracts;
    const pairs = allocator.alloc(ProviderPair, providers.object.count()) catch return error.OutOfMemory;
    defer allocator.free(pairs);
    var iterator = providers.object.iterator();
    var index: usize = 0;
    while (iterator.next()) |entry| : (index += 1) {
        const source = switch (entry.value_ptr.*) {
            .string => |source_text| source_text,
            else => return error.InvalidContracts,
        };
        pairs[index] = .{ .path = entry.key_ptr.*, .source = source };
    }
    std.mem.sort(ProviderPair, pairs, {}, providerLessThan);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    for (pairs) |pair| {
        var header: [16]u8 = undefined;
        try out.appendSlice(allocator, std.fmt.bufPrint(&header, "{x}\x00", .{pair.path.len}) catch return error.OutOfMemory);
        try out.appendSlice(allocator, pair.path);
        try out.appendSlice(allocator, std.fmt.bufPrint(&header, "{x}\x00", .{pair.source.len}) catch return error.OutOfMemory);
        try out.appendSlice(allocator, pair.source);
        try out.append(allocator, '\n');
    }
    return fs.hash(allocator, out.items) catch error.OutOfMemory;
}

/// A stable identity for the production declarations a case replaces. Every
/// exact and permission field participates, so an interface edit invalidates the
/// receipt even when replacement bytes are unchanged.
pub fn contractIdentity(allocator: std.mem.Allocator, contracts: std.json.Value, modules: []const []const u8) Error![]const u8 {
    try checkVersion(contracts);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, version);
    for (modules) |module_name| {
        const module = findModule(contracts, module_name) orelse return error.InvalidContracts;
        try appendValue(&out, allocator, module);
    }
    return fs.hash(allocator, out.items) catch error.OutOfMemory;
}

fn appendValue(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: std.json.Value) Error!void {
    const encoded = std.json.Stringify.valueAlloc(allocator, value, .{}) catch return error.OutOfMemory;
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
    try out.appendSlice(allocator, "\n");
}

/// Build the test-discovery schema from declared exported functions. The shape
/// matches the checked schema keys discovery and receipt hashing already read;
/// `parameters` carries the canonical declared signature string so a declared
/// signature change invalidates a receipt even before any body is checked.
pub fn testSchema(allocator: std.mem.Allocator, contracts: std.json.Value) Error!std.json.Value {
    try checkVersion(contracts);
    var functions = std.json.Array.init(allocator);
    for (array(field(contracts, modules_key))) |module| {
        const module_name = text(field(module, name_key));
        for (array(field(module, declarations_key))) |declaration| {
            if (!std.mem.eql(u8, text(field(declaration, kind_key)), "function")) continue;
            var map: std.json.ObjectMap = .empty;
            try map.put(allocator, name_key, .{ .string = try std.fmt.allocPrint(allocator, "{s}::{s}", .{ module_name, text(field(declaration, name_key)) }) });
            try map.put(allocator, "result", .{ .string = resultOf(text(field(declaration, signature_key))) });
            try map.put(allocator, "parameters", .{ .string = text(field(declaration, signature_key)) });
            try map.put(allocator, "return_reference", .{ .string = "unknown" });
            try functions.append(.{ .object = map });
        }
    }
    var root: std.json.ObjectMap = .empty;
    try root.put(allocator, functions_key, .{ .array = functions });
    return .{ .object = root };
}

/// Recover the declared result spelling from a canonical `def(...)->T` string by
/// first matching the outermost arrow, so nested callback signatures cannot
/// confuse discovery's boolean-result test.
fn resultOf(signature: []const u8) []const u8 {
    var depth: usize = 0;
    var index: usize = 0;
    while (index + 2 < signature.len) : (index += 1) {
        switch (signature[index]) {
            '(' => depth += 1,
            ')' => {
                if (depth > 0) depth -= 1;
                if (depth == 0 and signature[index + 1] == '-' and signature[index + 2] == '>') {
                    var rest = signature[index + 3 ..];
                    if (std.mem.lastIndexOf(u8, rest, " effects(")) |at| rest = rest[0..at];
                    return rest;
                }
            },
            else => {},
        }
    }
    return "";
}

/// Validate each replaced module's full exported declaration set. Every
/// production declaration must reappear with the same exact identity; its
/// declared permissions may only narrow.
pub fn validate(allocator: std.mem.Allocator, production: std.json.Value, replacement: std.json.Value, modules: []const []const u8) Error!void {
    try checkVersion(production);
    try checkVersion(replacement);
    _ = allocator;
    for (modules) |module_name| {
        const before_module = findModule(production, module_name) orelse return error.InvalidContracts;
        const after_module = findModule(replacement, module_name) orelse return error.IncompatibleProvider;
        for (array(field(before_module, declarations_key))) |before| {
            const name = text(field(before, name_key));
            const kind = text(field(before, kind_key));
            const after = findDeclaration(after_module, name) orelse return error.IncompatibleProvider;
            if (!std.mem.eql(u8, kind, text(field(after, kind_key)))) return error.IncompatibleProvider;
            if (!std.mem.eql(u8, text(field(before, generics_key)), text(field(after, generics_key)))) return error.IncompatibleProvider;
            if (std.mem.eql(u8, kind, manifest_function_kind)) {
                if (!std.mem.eql(u8, text(field(before, signature_key)), text(field(after, signature_key)))) return error.IncompatibleProvider;
                try permissionsCompatible(text(field(after, permissions_key)), text(field(before, permissions_key)));
            } else if (!std.mem.eql(u8, text(field(before, shape_key)), text(field(after, shape_key)))) {
                return error.IncompatibleProvider;
            }
        }
    }
}

/// `impl` may use a subset of `destination`'s effects and mutation footprint and
/// a no-broader return origin. Anything stronger rejects.
pub fn permissionsCompatible(impl: []const u8, destination: []const u8) Error!void {
    const impl_effects = segment(impl, effects_marker, mutates_marker) orelse return error.InvalidContracts;
    const dest_effects = segment(destination, effects_marker, mutates_marker) orelse return error.InvalidContracts;
    var effects = std.mem.tokenizeScalar(u8, impl_effects, ',');
    while (effects.next()) |effect| if (!containsToken(dest_effects, effect)) return error.IncompatibleProvider;

    const impl_mutates = segment(impl, mutates_marker, origin_marker) orelse return error.InvalidContracts;
    const dest_mutates = segment(destination, mutates_marker, origin_marker) orelse return error.InvalidContracts;
    var mutates = std.mem.tokenizeScalar(u8, impl_mutates, ',');
    while (mutates.next()) |position| if (!containsToken(dest_mutates, position)) return error.IncompatibleProvider;

    const impl_origin = segment(impl, origin_marker, null) orelse return error.InvalidContracts;
    const dest_origin = segment(destination, origin_marker, null) orelse return error.InvalidContracts;
    if (!originTextSubset(impl_origin, dest_origin)) return error.IncompatibleProvider;
}

fn segment(haystack: []const u8, start_marker: []const u8, end_marker: ?[]const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, haystack, start_marker) orelse return null;
    const rest = haystack[start + start_marker.len ..];
    const end = if (end_marker) |marker| std.mem.indexOf(u8, rest, marker) orelse return null else rest.len;
    return rest[0..end];
}

fn containsToken(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    var tokens = std.mem.tokenizeScalar(u8, haystack, ',');
    while (tokens.next()) |token| if (std.mem.eql(u8, token, needle)) return true;
    return false;
}

/// `fresh` is narrower than `params` which is narrower than `unknown`; two
/// `params` bounds compare by position set.
fn originTextSubset(impl: []const u8, destination: []const u8) bool {
    const impl_rank = originRank(impl) orelse return false;
    const dest_rank = originRank(destination) orelse return false;
    if (impl_rank > dest_rank) return false;
    // `unknown` is the widest published bound; a fresh/params implementation fits.
    if (dest_rank == 2) return true;
    if (impl_rank != 1) return true;
    const impl_positions = if (std.mem.startsWith(u8, impl, "params:")) impl["params:".len..] else impl;
    const dest_positions = if (std.mem.startsWith(u8, destination, "params:")) destination["params:".len..] else destination;
    var positions = std.mem.tokenizeScalar(u8, impl_positions, ',');
    while (positions.next()) |position| if (!containsToken(dest_positions, position)) return false;
    return true;
}

fn originRank(tag: []const u8) ?u8 {
    if (std.mem.startsWith(u8, tag, "fresh")) return 0;
    if (std.mem.startsWith(u8, tag, "params")) return 1;
    if (std.mem.startsWith(u8, tag, "unknown")) return 2;
    return null;
}

fn checkVersion(contracts: std.json.Value) Error!void {
    if (!std.mem.eql(u8, text(field(contracts, version_key)), version)) return error.InvalidContracts;
}

fn findModule(contracts: std.json.Value, name: []const u8) ?std.json.Value {
    for (array(field(contracts, modules_key))) |module| {
        if (std.mem.eql(u8, text(field(module, name_key)), name)) return module;
    }
    return null;
}

fn findDeclaration(module: std.json.Value, name: []const u8) ?std.json.Value {
    for (array(field(module, declarations_key))) |declaration| {
        if (std.mem.eql(u8, text(field(declaration, name_key)), name)) return declaration;
    }
    return null;
}

fn field(value: std.json.Value, name: []const u8) std.json.Value {
    if (value != .object) return .null;
    return value.object.get(name) orelse .null;
}

fn array(value: std.json.Value) []std.json.Value {
    if (value != .array) return &.{};
    return value.array.items;
}

fn text(value: std.json.Value) []const u8 {
    return if (value == .string) value.string else "";
}

// spec-case: NATIVE-TEST-3
test "provider module paths map to dotted module names and reject malformed keys" {
    const a = std.testing.allocator;
    const mapped = try moduleNameFromPath(a, "a/b.my");
    defer a.free(mapped);
    try std.testing.expectEqualStrings("a.b", mapped);
    const top = try moduleNameFromPath(a, "production.my");
    defer a.free(top);
    try std.testing.expectEqualStrings("production", top);
    try std.testing.expectError(error.InvalidContracts, moduleNameFromPath(a, "production.txt"));
    try std.testing.expectError(error.InvalidContracts, moduleNameFromPath(a, ".my"));
    try std.testing.expectError(error.InvalidContracts, moduleNames(a, .null));
    const empty = try std.json.parseFromSlice(std.json.Value, a, "{}", .{});
    defer empty.deinit();
    try std.testing.expectError(error.InvalidContracts, moduleNames(a, empty.value));
}

// spec-case: NATIVE-TEST-3
test "declared permission substitution is directional and malformed manifests reject" {
    try permissionsCompatible("effects=;mutates=;origin=fresh", "effects=output;mutates=;origin=unknown");
    try permissionsCompatible("effects=mutation;mutates=0;origin=params:0", "effects=mutation,output;mutates=0,1;origin=unknown");
    try permissionsCompatible("effects=;mutates=;origin=params:0", "effects=;mutates=;origin=params:0,1");
    try std.testing.expectError(error.IncompatibleProvider, permissionsCompatible("effects=output;mutates=;origin=unknown", "effects=;mutates=;origin=unknown"));
    try std.testing.expectError(error.IncompatibleProvider, permissionsCompatible("effects=;mutates=1;origin=unknown", "effects=;mutates=0;origin=unknown"));
    try std.testing.expectError(error.IncompatibleProvider, permissionsCompatible("effects=;mutates=;origin=unknown", "effects=;mutates=;origin=fresh"));
    try std.testing.expectError(error.IncompatibleProvider, permissionsCompatible("effects=;mutates=;origin=params:1", "effects=;mutates=;origin=params:0"));
    try std.testing.expectError(error.InvalidContracts, permissionsCompatible("bogus", "effects=;mutates=;origin=unknown"));
}

const contract_fixture =
    \\{"version":"interface-contracts-v2","modules":[{"name":"production","declarations":[
    \\{"name":"helper","kind":"function","signature":"def(x:i64)->i64","generics":"","permissions":"effects=;mutates=;origin=unknown","shape":""},
    \\{"name":"D","kind":"domain","generics":"","permissions":"","shape":"backing:i64"}]}]}
;
const contract_narrower =
    \\{"version":"interface-contracts-v2","modules":[{"name":"production","declarations":[
    \\{"name":"helper","kind":"function","signature":"def(x:i64)->i64","generics":"","permissions":"effects=;mutates=;origin=fresh","shape":""},
    \\{"name":"D","kind":"domain","generics":"","permissions":"","shape":"backing:i64"}]}]}
;
const contract_wider =
    \\{"version":"interface-contracts-v2","modules":[{"name":"production","declarations":[
    \\{"name":"helper","kind":"function","signature":"def(x:i64)->i64","generics":"","permissions":"effects=output;mutates=;origin=unknown","shape":""},
    \\{"name":"D","kind":"domain","generics":"","permissions":"","shape":"backing:i64"}]}]}
;
const contract_changed_signature =
    \\{"version":"interface-contracts-v2","modules":[{"name":"production","declarations":[
    \\{"name":"helper","kind":"function","signature":"def(x:bool)->i64","generics":"","permissions":"effects=;mutates=;origin=unknown","shape":""},
    \\{"name":"D","kind":"domain","generics":"","permissions":"","shape":"backing:i64"}]}]}
;
const contract_changed_shape =
    \\{"version":"interface-contracts-v2","modules":[{"name":"production","declarations":[
    \\{"name":"helper","kind":"function","signature":"def(x:i64)->i64","generics":"","permissions":"effects=;mutates=;origin=unknown","shape":""},
    \\{"name":"D","kind":"domain","generics":"","permissions":"","shape":"backing:bool"}]}]}
;
const contract_missing =
    \\{"version":"interface-contracts-v2","modules":[{"name":"production","declarations":[
    \\{"name":"D","kind":"domain","generics":"","permissions":"","shape":"backing:i64"}]}]}
;

fn parsedContract(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
}

// spec-case: NATIVE-TEST-3
test "a replacement must supply every public contract with an identical identity" {
    const a = std.testing.allocator;
    const production = try parsedContract(a, contract_fixture);
    defer production.deinit();
    const modules = [_][]const u8{"production"};

    const identical = try parsedContract(a, contract_fixture);
    defer identical.deinit();
    try validate(a, production.value, identical.value, &modules);
    const identical_identity = try contractIdentity(a, identical.value, &modules);
    defer a.free(identical_identity);
    const identity = try contractIdentity(a, production.value, &modules);
    defer a.free(identity);
    try std.testing.expectEqualStrings(identity, identical_identity);

    const narrower = try parsedContract(a, contract_narrower);
    defer narrower.deinit();
    try validate(a, production.value, narrower.value, &modules);

    const wider = try parsedContract(a, contract_wider);
    defer wider.deinit();
    try std.testing.expectError(error.IncompatibleProvider, validate(a, production.value, wider.value, &modules));

    const signature = try parsedContract(a, contract_changed_signature);
    defer signature.deinit();
    try std.testing.expectError(error.IncompatibleProvider, validate(a, production.value, signature.value, &modules));
    const changed_identity = try contractIdentity(a, signature.value, &modules);
    defer a.free(changed_identity);
    try std.testing.expect(!std.mem.eql(u8, identity, changed_identity));

    const shape = try parsedContract(a, contract_changed_shape);
    defer shape.deinit();
    try std.testing.expectError(error.IncompatibleProvider, validate(a, production.value, shape.value, &modules));

    const missing = try parsedContract(a, contract_missing);
    defer missing.deinit();
    try std.testing.expectError(error.IncompatibleProvider, validate(a, production.value, missing.value, &modules));
    try std.testing.expectError(error.InvalidContracts, validate(a, production.value, missing.value, &.{"absent"}));
}

// spec-case: NATIVE-TEST-3
test "declared test discovery schema and provider identities are stable" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const production = try parsedContract(a, contract_fixture);
    defer production.deinit();
    const schema = try testSchema(scratch, production.value);
    const functions = array(field(schema, functions_key));
    try std.testing.expectEqual(@as(usize, 1), functions.len);
    try std.testing.expectEqualStrings("production::helper", text(field(functions[0], name_key)));
    try std.testing.expectEqualStrings("i64", text(field(functions[0], "result")));

    const bool_fixture = try parsedContract(a,
        \\{"version":"interface-contracts-v2","modules":[{"name":"main","declarations":[
        \\{"name":"test_ok","kind":"function","signature":"def()->bool","generics":"","permissions":"effects=;mutates=;origin=unknown","shape":""}]}]}
    );
    defer bool_fixture.deinit();
    const bool_schema = try testSchema(scratch, bool_fixture.value);
    try std.testing.expectEqualStrings("bool", text(field(array(field(bool_schema, functions_key))[0], "result")));

    const first = try std.json.parseFromSlice(std.json.Value, a, "{\"production.my\":\"module production\"}", .{});
    defer first.deinit();
    const second = try std.json.parseFromSlice(std.json.Value, a, "{\"production.my\":\"module production\\n// changed\"}", .{});
    defer second.deinit();
    const names = try moduleNames(a, first.value);
    defer {
        for (names) |name| a.free(name);
        a.free(names);
    }
    try std.testing.expectEqualStrings("production", names[0]);
    const first_identity = try providerIdentity(a, first.value);
    defer a.free(first_identity);
    const second_identity = try providerIdentity(a, second.value);
    defer a.free(second_identity);
    try std.testing.expect(!std.mem.eql(u8, first_identity, second_identity));

    const ordered = try std.json.parseFromSlice(std.json.Value, a, "{\"a.my\":\"module a\",\"b.my\":\"module b\"}", .{});
    defer ordered.deinit();
    const reversed = try std.json.parseFromSlice(std.json.Value, a, "{\"b.my\":\"module b\",\"a.my\":\"module a\"}", .{});
    defer reversed.deinit();
    const ordered_identity = try providerIdentity(a, ordered.value);
    defer a.free(ordered_identity);
    const reversed_identity = try providerIdentity(a, reversed.value);
    defer a.free(reversed_identity);
    try std.testing.expectEqualStrings(ordered_identity, reversed_identity);
}
