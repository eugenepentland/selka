//! NATIVE-TEST-5: a test provider replaces a module only when it keeps every
//! declaration that module exports, compared at the declaration level before any
//! body is checked: names, defaults, canonical types and nominal identities, data
//! shapes and generic requirements exactly, and declared effects, mutation footprints
//! and return-origin bounds by the directional subset relation, so a narrower
//! implementation is accepted and a stronger one is not.
const std = @import("std");
const language = @import("mylang");
const frontend = @import("frontend.zig");

/// Why a provider is refused: it changes a declaration it replaces
/// (`IncompatibleProvider`), or a permission string is not the compiler's.
pub const Error = error{ OutOfMemory, IncompatibleProvider, InvalidContracts };

/// One module's exported declarations, as `mylang list-interfaces --contracts` renders them.
pub const Module = language.interfaces.ContractModule;

const effects_field = "effects=";
const mutates_field = ";mutates=";
const origin_field = ";origin=";
const callable_kind = "function";

/// The exported declarations of module `name` in the graph `session` declared, or
/// null when the graph has no such module.
pub fn declarations(session: *frontend.Session, name: []const u8) Error!?Module {
    for (session.project.modules.items, 0..) |module, index| {
        if (!std.mem.eql(u8, module.name, name)) continue;
        return session.interfaceIndex().contractModule(index) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.InvalidContracts;
        };
    }
    return null;
}

/// Require `replacement` to keep every declaration `production` exports.
pub fn validate(production: Module, replacement: Module) Error!void {
    for (production.declarations) |before| {
        const after = find(replacement, before.name) orelse return error.IncompatibleProvider;
        if (!std.mem.eql(u8, before.kind, after.kind)) return error.IncompatibleProvider;
        if (!std.mem.eql(u8, before.generics, after.generics)) return error.IncompatibleProvider;
        if (std.mem.eql(u8, before.kind, callable_kind)) {
            if (!std.mem.eql(u8, before.signature, after.signature)) return error.IncompatibleProvider;
            try permissionsCompatible(after.permissions, before.permissions);
        } else if (!std.mem.eql(u8, before.shape, after.shape)) return error.IncompatibleProvider;
    }
}

fn find(module: Module, name: []const u8) ?language.interfaces.ContractDeclaration {
    for (module.declarations) |declaration| if (std.mem.eql(u8, declaration.name, name)) return declaration;
    return null;
}

// twin-drift-ok: the new runner's port of native_test_contracts.permissionsCompatible, which S5-D deletes with the old runner.
/// `implementation` may use a subset of `destination`'s effects and mutation
/// footprint and a no-broader return origin; anything stronger is incompatible.
pub fn permissionsCompatible(implementation: []const u8, destination: []const u8) Error!void {
    const impl_effects = segment(implementation, effects_field, mutates_field) orelse return error.InvalidContracts;
    const dest_effects = segment(destination, effects_field, mutates_field) orelse return error.InvalidContracts;
    var effects = std.mem.tokenizeScalar(u8, impl_effects, ',');
    while (effects.next()) |effect| if (!containsToken(dest_effects, effect)) return error.IncompatibleProvider;
    const impl_mutates = segment(implementation, mutates_field, origin_field) orelse return error.InvalidContracts;
    const dest_mutates = segment(destination, mutates_field, origin_field) orelse return error.InvalidContracts;
    var mutates = std.mem.tokenizeScalar(u8, impl_mutates, ',');
    while (mutates.next()) |position| if (!containsToken(dest_mutates, position)) return error.IncompatibleProvider;
    const impl_origin = segment(implementation, origin_field, null) orelse return error.InvalidContracts;
    const dest_origin = segment(destination, origin_field, null) orelse return error.InvalidContracts;
    if (!originSubset(impl_origin, dest_origin)) return error.IncompatibleProvider;
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

/// `fresh` is narrower than `params`, which is narrower than `unknown`; two `params`
/// bounds compare by position set.
fn originSubset(implementation: []const u8, destination: []const u8) bool {
    const impl_rank = originRank(implementation) orelse return false;
    const dest_rank = originRank(destination) orelse return false;
    if (impl_rank > dest_rank) return false;
    if (dest_rank == 2 or impl_rank != 1) return true;
    const params = "params:";
    const impl_positions = if (std.mem.startsWith(u8, implementation, params)) implementation[params.len..] else implementation;
    const dest_positions = if (std.mem.startsWith(u8, destination, params)) destination[params.len..] else destination;
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

/// The hex identity of the production declarations a provider set replaces: an
/// interface edit changes it even when the replacement's bytes do not.
pub fn identity(a: std.mem.Allocator, modules: []const Module) std.mem.Allocator.Error![]const u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (modules) |module| {
        const encoded = std.json.Stringify.valueAlloc(a, module, .{ .emit_null_optional_fields = false }) catch return error.OutOfMemory;
        hasher.update(encoded);
        hasher.update("\n");
    }
    const digest = hasher.finalResult();
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}

/// The hex identity of a provider set's replacement sources, each path and text
/// length-prefixed, in path order.
pub fn providerIdentity(a: std.mem.Allocator, providers: []const frontend.Provider) std.mem.Allocator.Error![]const u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (providers) |provider| for ([_][]const u8{ provider.path, provider.text }) |part| {
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, part.len, .little);
        hasher.update(&length);
        hasher.update(part);
    };
    const digest = hasher.finalResult();
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}

const fixture_main = "import reading\n\npublic func test_reading() -> bool effects():\n    return reading.sample() == 42\n\nfunc main() -> int:\n    return 0\n";

fn declared(a: std.mem.Allocator, providers: []const frontend.Provider, session: *frontend.Session) !Module {
    var report: std.ArrayList(u8) = .empty;
    session.setProviders(providers);
    try session.declare(a, "main", &report);
    return (try declarations(session, "reading")).?;
}

// spec-case: NATIVE-TEST-5
test "a provider keeps a declaration's identity and may only narrow its permissions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = fixture_main });
    // An unfinished body is never checked: the declarations alone are compared.
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "reading.my", .data = "\npublic func sample() -> int effects():\n    return todo[int]()\n" });
    var production_session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer production_session.deinit();
    const production = try declared(a, &.{}, &production_session);
    const narrower = "\npublic func sample() -> i64 effects():\n    return 42\n";
    const wider = "\npublic func sample() -> int effects(managed_allocation):\n    return 42\n";
    const retyped = "\npublic func sample() -> u8 effects():\n    return 42\n";
    var narrow_session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer narrow_session.deinit();
    var wide_session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer wide_session.deinit();
    var retyped_session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer retyped_session.deinit();
    try validate(production, try declared(a, &.{.{ .path = "reading.my", .text = narrower }}, &narrow_session));
    try std.testing.expectError(error.IncompatibleProvider, validate(production, try declared(a, &.{.{ .path = "reading.my", .text = wider }}, &wide_session)));
    try std.testing.expectError(error.IncompatibleProvider, validate(production, try declared(a, &.{.{ .path = "reading.my", .text = retyped }}, &retyped_session)));
    try std.testing.expectError(error.InvalidContracts, permissionsCompatible("bogus", "effects=;mutates=;origin=unknown"));
    try std.testing.expectError(error.IncompatibleProvider, permissionsCompatible("effects=;mutates=;origin=params:1", "effects=;mutates=;origin=params:0"));
    try permissionsCompatible("effects=;mutates=;origin=params:0", "effects=;mutates=;origin=params:0,1");
    try std.testing.expect(!std.mem.eql(u8, try providerIdentity(a, &.{.{ .path = "a.my", .text = "bc" }}), try providerIdentity(a, &.{.{ .path = "ab.my", .text = "c" }})));
    try std.testing.expectEqual(@as(usize, 64), (try identity(a, &.{production})).len);
}
