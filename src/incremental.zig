//! Stable incremental identities and exported-interface fingerprints.
//!
//! Identities are derived from canonical module/declaration names and checked
//! interface data, never from source byte offsets. Body fingerprints are
//! content hashes of the declaration body, while the project interface
//! fingerprint is the checked `language-schema-v1` document.
const std = @import("std");
const ast = @import("ast.zig");
const interface = @import("interfaces.zig");
const project_compile = @import("project_compile.zig");
const schema_graph = @import("schema_graph.zig");
const source = @import("source.zig");

/// Identity allocation or schema derivation failed.
pub const Error = error{ OutOfMemory, SourceError, InternalError };
/// SHA-256 identity bytes.
pub const Hash = [32]u8;
/// One exported or private declaration identity and body fingerprint.
pub const Declaration = struct {
    name: []const u8,
    kind: []const u8,
    identity: []const u8,
    body_sha256: ?[]const u8 = null,
};
/// One module's stable identity and declaration table.
pub const Module = struct {
    name: []const u8,
    identity: []const u8,
    declarations: []const Declaration,
};
/// Debug manifest for incremental identities; all strings are allocator-owned.
pub const Report = struct {
    version: []const u8,
    project_interface_sha256: []const u8,
    modules: []const Module,
};

/// Derive a module identity from its canonical module name.
pub fn moduleIdentity(allocator: std.mem.Allocator, name: []const u8) Error![]const u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("mylang-module-v1\x00");
    hash.update(name);
    return hex(allocator, hash.finalResult());
}

/// Derive a declaration identity from module identity, kind, owner and local name.
pub fn declarationIdentity(allocator: std.mem.Allocator, module: []const u8, kind: []const u8, owner: ?[]const u8, name: []const u8) Error![]const u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("mylang-declaration-v1\x00");
    hash.update(module);
    hash.update("\x00");
    hash.update(kind);
    hash.update("\x00");
    if (owner) |value| hash.update(value);
    hash.update("\x00");
    hash.update(name);
    return hex(allocator, hash.finalResult());
}

/// Derive a body identity from its declaration identity and exact body bytes.
pub fn bodyIdentity(allocator: std.mem.Allocator, declaration: []const u8, bytes: []const u8) Error![]const u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("mylang-body-v1\x00");
    hash.update(declaration);
    hash.update("\x00");
    hash.update(bytes);
    return hex(allocator, hash.finalResult());
}

/// Derive a whole-project exported-interface fingerprint from the checked schema.
pub fn interfaceFingerprint(allocator: std.mem.Allocator, schema: []const u8) Error![]const u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("mylang-interface-v1\x00");
    hash.update(schema);
    return hex(allocator, hash.finalResult());
}

/// Release a report allocated by `describe` with the same allocator.
pub fn deinit(self: Report, allocator: std.mem.Allocator) void {
    for (self.modules) |module| {
        allocator.free(module.name);
        allocator.free(module.identity);
        for (module.declarations) |declaration| {
            allocator.free(declaration.name);
            allocator.free(declaration.identity);
            if (declaration.body_sha256) |hash| allocator.free(hash);
        }
        allocator.free(module.declarations);
    }
    allocator.free(self.modules);
    allocator.free(self.project_interface_sha256);
}

/// Build the stable-identity debug manifest for one checked project.
pub fn describe(allocator: std.mem.Allocator, compilation: *project_compile.Compilation) Error!Report {
    try compilation.check();
    const roots = compilation.exportRoots(allocator) catch |err| return classify(err);
    defer allocator.free(roots);
    const schema = schema_graph.render(allocator, compilation.index, compilation.program.?, roots) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.SourceError => return error.SourceError,
        else => return error.InternalError,
    };
    defer allocator.free(schema);
    const project_interface = try interfaceFingerprint(allocator, schema);
    const modules = try allocator.alloc(Module, compilation.index.units.len);
    for (compilation.index.units, 0..) |unit, module_index| {
        const name = try allocator.dupe(u8, compilation.index.project.modules.items[module_index].name);
        const identity = try moduleIdentity(allocator, name);
        var declarations: std.ArrayList(Declaration) = .empty;
        defer declarations.deinit(allocator);
        for (unit.symbols.items) |symbol| {
            const kind = @tagName(symbol.kind);
            const qualified = try allocator.dupe(u8, symbol.name);
            const decl_identity = try declarationIdentity(allocator, name, kind, symbol.owner, qualified);
            const body = declarationBody(unit.syntax, compilation.index.project.modules.items[module_index].src, symbol);
            const body_sha = if (body) |span| try bodyIdentity(allocator, decl_identity, span) else null;
            try declarations.append(allocator, .{ .name = qualified, .kind = kind, .identity = decl_identity, .body_sha256 = body_sha });
        }
        modules[module_index] = .{ .name = name, .identity = identity, .declarations = try declarations.toOwnedSlice(allocator) };
    }
    return .{ .version = "incremental-identities-v1", .project_interface_sha256 = project_interface, .modules = modules };
}

fn declarationBody(syntax: ast.Program, src: source.Source, symbol: interface.Symbol) ?[]const u8 {
    for (syntax.functions) |function| {
        if (function.name.start != symbol.span.start or function.name.end != symbol.span.end) continue;
        if (function.policy.host != null or function.policy.c_abi) return null;
        const span = syntax.statements.items[@backingInt(function.body)].span;
        if (span.end < span.start or span.end > src.bytes.len) return null;
        return src.bytes[span.start..span.end];
    }
    return null;
}

fn classify(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.SourceError => error.SourceError,
        else => error.InternalError,
    };
}

fn hex(allocator: std.mem.Allocator, digest: Hash) Error![]const u8 {
    return allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower)) catch error.OutOfMemory;
}
