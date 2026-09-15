//! Conservative semantic dependencies: unchanged declarations, catalogs and module identities.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const identity = @import("identity.zig");
const lexer = @import("lexer.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const Hash = std.crypto.hash.sha2.Sha256;
/// Domain for checked ordinary-function dependency digests.
pub const functions_domain = "semantic-functions-v3";
/// Domain for the generic-specialization key primitive.
pub const specialization_domain = "semantic-specialization-v1";
/// Stable declaration identity plus the declaration's semantic interface digest.
/// The strings are owned by the allocator passed to `prepare`.
pub const DeclarationKey = struct { identity: []const u8, interface_sha256: ?[]const u8 };
/// Current function body spans, full declaration spans and dependency keys.
/// `contract_sha256` retains the build-contract dimension that participates in
/// `digest`; `catalog_digest` isolates the resolved type catalog.
pub const Prepared = struct {
    digest: [32]u8,
    bodies: []source.Span,
    declarations: []source.Span,
    keys: []const ?DeclarationKey,
    enabled: bool,
    contract_sha256: [32]u8,
    catalog_digest: [32]u8,
};
/// Compute body/declaration spans and the ordered declaration-interface gate.
/// `keys` is indexed by AST function and must be the same length as
/// `program.functions`; a length mismatch disables reuse rather than guessing.
/// `contract` is the Wave-3 contract fingerprint; the empty string is the
/// conservative default for callers that have not yet resolved a full contract.
pub fn prepare(
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    records: []const typed.Record,
    contract: []const u8,
    keys: []const ?DeclarationKey,
) error{ OutOfMemory, InternalError }!Prepared {
    const bodies = try allocator.alloc(source.Span, program.functions.len);
    errdefer allocator.free(bodies);
    const declarations = try allocator.alloc(source.Span, program.functions.len);
    errdefer allocator.free(declarations);
    const owned_keys = try allocator.alloc(?DeclarationKey, program.functions.len);
    for (owned_keys) |*slot| slot.* = null;
    errdefer freeKeys(allocator, owned_keys);

    var enabled = !@import("nominal_type_syntax.zig").present(program);
    if (enabled and try functionValues(allocator, src, program)) enabled = false;
    const keys_match = keys.len == program.functions.len;
    if (!keys_match) enabled = false;
    for (program.functions, bodies, declarations, 0..) |function, *body, *declaration, i| {
        body.* = program.statements.items[@backingInt(function.body)].span;
        declaration.* = .{ .start = declarationStart(function), .end = body.end };
        if (declaration.start > declaration.end or declaration.end > src.bytes.len) return error.InternalError;
        if (function.signature.type_parameters.len != 0 or function.policy.constant) enabled = false;
        if (!keys_match) continue;
        const supplied = keys[i] orelse {
            enabled = false;
            continue;
        };
        const copied_identity = try allocator.dupe(u8, supplied.identity);
        const copied_interface = if (supplied.interface_sha256) |interface| allocator.dupe(u8, interface) catch |err| {
            allocator.free(copied_identity);
            return err;
        } else null;
        owned_keys[i] = .{ .identity = copied_identity, .interface_sha256 = copied_interface };
        // A missing interface cannot conservatively distinguish header edits.
        if (copied_interface == null) enabled = false;
    }
    for (program.types.domains) |domain| if (domain.type_parameters.len != 0) {
        enabled = false;
    };

    var catalog_hash = Hash.init(.{});
    fingerprint(&catalog_hash, []const typed.Record, records);
    var catalog_digest: [32]u8 = undefined;
    catalog_hash.final(&catalog_digest);

    var contract_sha256: [32]u8 = undefined;
    Hash.hash(contract, &contract_sha256, .{});
    var hash = Hash.init(.{});
    hash.update(functions_domain);
    hash.update(&contract_sha256);
    // The digest is dependency-backed: ordered declaration identities/interfaces
    // plus the resolved type catalog. It adds the contract dimension to the
    // per-slot gate and never reintroduces bytes outside declarations.
    fingerprint(&hash, []const ?DeclarationKey, owned_keys);
    hash.update(&catalog_digest);
    return .{
        .digest = hash.finalResult(),
        .bodies = bodies,
        .declarations = declarations,
        .keys = owned_keys,
        .enabled = enabled,
        .contract_sha256 = contract_sha256,
        .catalog_digest = catalog_digest,
    };
}

fn freeKeys(allocator: std.mem.Allocator, keys: []?DeclarationKey) void {
    for (keys) |slot| if (slot) |owned| {
        allocator.free(owned.identity);
        if (owned.interface_sha256) |interface| allocator.free(interface);
    };
    allocator.free(keys);
}

/// The deterministic first byte of a declaration. `def` precedes the name, but
/// host/extern policy tokens may precede `def`; include them so their checked
/// metadata spans fall inside the declaration relocation segment.
fn declarationStart(function: ast.Function) usize {
    if (function.policy.host) |host| return @min(host.start, function.name.start);
    return function.name.start;
}

/// Normalize a declaration header (signature, defaults and effect bound) into
/// canonical NUL-separated token spellings and hash it. Bodies and comments are
/// excluded; the returned lowercase hex string is allocator-owned.
pub fn declarationInterfaceDigest(
    allocator: std.mem.Allocator,
    src: source.Source,
    syntax: ast.Program,
    function: ast.Function,
) error{ OutOfMemory, InternalError }!?[]const u8 {
    const body = syntax.statements.items[@backingInt(function.body)].span;
    var end = body.start;
    for (function.signature.parameters) |parameter| if (parameter.default_value) |value| {
        const default_span = syntax.nodes.items[@backingInt(value)].span;
        if (default_span.end > end) end = default_span.end;
    };
    const start = declarationStart(function);
    if (start > end or end > src.bytes.len or body.end > src.bytes.len) return null;
    const normalized = normalizeSpan(allocator, src, .{ .start = start, .end = end }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InternalError => return null,
    };
    defer allocator.free(normalized);
    const digest = identity.digestFields("mylang-declaration-header-v1", &.{normalized});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return allocator.dupe(u8, &hex) catch error.OutOfMemory;
}

// twin-drift-ok: the semantic cache cannot import incremental.zig (it pulls in
// project checking), so both modules intentionally share this lexRange token-join
// contract; the cache variant owns and frees its token slice.
/// Tokenize a source range and join token spellings with NUL separators. This
/// removes comments/formatting while preserving identifiers, literals and names.
fn normalizeSpan(allocator: std.mem.Allocator, src: source.Source, span: source.Span) error{ OutOfMemory, InternalError }![]const u8 {
    if (span.start > span.end or span.end > src.bytes.len) return error.InternalError;
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    const tokens = lexer.lexRange(allocator, src.bytes, span, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
    defer allocator.free(tokens);
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var first = true;
    for (tokens) |token| {
        if (token.tag == .eof) continue;
        if (!first) out.writer.writeAll("\x00") catch return error.OutOfMemory;
        first = false;
        if (token.span.start > token.span.end or token.span.end > src.bytes.len) return error.InternalError;
        out.writer.writeAll(src.bytes[token.span.start..token.span.end]) catch return error.OutOfMemory;
    }
    return out.toOwnedSlice() catch return error.OutOfMemory;
}

/// Canonical key for one generic specialization. This is a primitive for a future
/// reuse engine; `prepare` deliberately keeps generic templates and nominal
/// syntax on the fresh path, so this key is never used to claim current reuse.
/// It mixes every Wave-3 specialization dimension: template identity/fingerprint,
/// canonical concrete arguments (order-sensitive), observed provider/constraint
/// shape, target/runtime ABI and compiler identity.
pub fn specializationKey(
    allocator: std.mem.Allocator,
    template_identity: []const u8,
    arguments: []const []const u8,
    provider: []const u8,
    target_abi: []const u8,
    compiler_identity: []const u8,
) error{OutOfMemory}![]const u8 {
    var hash = Hash.init(.{});
    hash.update(specialization_domain);
    frame(&hash, template_identity);
    frame(&hash, provider);
    frame(&hash, target_abi);
    frame(&hash, compiler_identity);
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, arguments.len, .little);
    hash.update(&count);
    for (arguments) |argument| frame(&hash, argument);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)}) catch error.OutOfMemory;
}

/// Length-prefix a field so adjacent values cannot alias across boundaries.
fn frame(hash: *Hash, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

fn functionValues(allocator: std.mem.Allocator, src: source.Source, program: ast.Program) std.mem.Allocator.Error!bool {
    var names: std.StringHashMapUnmanaged(void) = .empty;
    defer names.deinit(allocator);
    for (program.functions) |function| {
        if (function.policy.owner == null) try names.put(allocator, src.text(function.name), {});
    }
    for (program.nodes.items) |node| if (node.data == .name) {
        const text = src.text(node.data.name);
        const start = if (std.mem.lastIndexOfAny(u8, text, ":.")) |at| at + 1 else 0;
        const bare = std.mem.trim(u8, text[start..], " \t\r\n");
        if (names.contains(bare)) return true;
    };
    return false;
}
fn fingerprint(hash: *Hash, comptime T: type, value: T) void {
    if (T == source.Span) return;
    switch (@typeInfo(T)) {
        .@"struct" => inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |name, Field| fingerprint(hash, Field, @field(value, name)),
        .@"union" => {
            fingerprint(hash, std.meta.Tag(T), std.meta.activeTag(value));
            inline for (@typeInfo(T).@"union".field_names, @typeInfo(T).@"union".field_types) |name, Field| {
                if (std.meta.activeTag(value) == @field(std.meta.Tag(T), name)) fingerprint(hash, Field, @field(value, name));
            }
        },
        .optional => |optional| {
            fingerprint(hash, bool, value != null);
            if (value) |present| fingerprint(hash, optional.child, present);
        },
        .pointer => |pointer| {
            if (pointer.size != .slice) @compileError("semantic dependencies require owned slices");
            fingerprint(hash, usize, value.len);
            if (pointer.child == u8) hash.update(value) else for (value) |item| fingerprint(hash, pointer.child, item);
        },
        .@"enum" => fingerprint(hash, @TypeOf(@backingInt(value)), @backingInt(value)),
        .int => hash.update(std.mem.asBytes(&value)),
        .bool => hash.update(&.{@intFromBool(value)}),
        .void => {},
        else => @compileError("semantic dependency requires explicit fingerprint: " ++ @typeName(T)),
    }
}
