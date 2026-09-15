//! Conservative semantic dependencies: unchanged declarations, catalogs and module identities.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const Hash = std.crypto.hash.sha2.Sha256;
/// Domain for checked ordinary-function dependency digests.
pub const functions_domain = "semantic-functions-v3";
/// Domain for the generic-specialization key primitive.
pub const specialization_domain = "semantic-specialization-v1";
/// Current function body spans and a dependency key; unsupported query surfaces stay fresh.
/// `contract_sha256` retains the build-contract dimension that participated in `digest`.
pub const Prepared = struct { digest: [32]u8, bodies: []source.Span, enabled: bool, contract_sha256: [32]u8 };
/// Ignore body contents while preserving source outside bodies and resolved type identities.
/// `contract` is the Wave-3 contract fingerprint; the empty string is the conservative
/// default for callers that have not yet resolved a full contract.
pub fn prepare(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, records: []const typed.Record, contract: []const u8) error{ OutOfMemory, InternalError }!Prepared {
    const bodies = try allocator.alloc(source.Span, program.functions.len);
    var enabled = !@import("nominal_type_syntax.zig").present(program);
    if (enabled and try functionValues(allocator, src, program)) enabled = false;
    for (program.functions, bodies) |function, *body| {
        body.* = program.statements.items[@backingInt(function.body)].span;
        if (function.signature.type_parameters.len != 0 or function.policy.constant) enabled = false;
    }
    for (program.types.domains) |domain| if (domain.type_parameters.len != 0) {
        enabled = false;
    };
    var contract_sha256: [32]u8 = undefined;
    Hash.hash(contract, &contract_sha256, .{});
    var hash = Hash.init(.{});
    hash.update(functions_domain);
    hash.update(&contract_sha256);
    fingerprint(&hash, []const u8, src.path);
    for (src.origins) |origin| fingerprint(&hash, []const u8, origin.original.path);
    const ordered = try allocator.dupe(source.Span, bodies);
    defer allocator.free(ordered);
    std.mem.sort(source.Span, ordered, {}, less);
    var cursor: usize = 0;
    for (ordered) |body| {
        if (body.start < cursor or body.end < body.start or body.end > src.bytes.len) return error.InternalError;
        fingerprint(&hash, []const u8, src.bytes[cursor..body.start]);
        cursor = body.end;
    }
    fingerprint(&hash, []const u8, src.bytes[cursor..]);
    // Catalog order matters: checked bodies retain nominal type identities.
    fingerprint(&hash, []const typed.Record, records);
    return .{ .digest = hash.finalResult(), .bodies = bodies, .enabled = enabled, .contract_sha256 = contract_sha256 };
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
fn less(_: void, a: source.Span, b: source.Span) bool {
    return a.start < b.start;
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
