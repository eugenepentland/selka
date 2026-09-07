//! Conservative semantic dependencies: unchanged declarations, catalogs and module identities.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const Hash = std.crypto.hash.sha2.Sha256;
/// Current function body spans and a dependency key; unsupported query surfaces stay fresh.
pub const Prepared = struct { digest: [32]u8, bodies: []source.Span, enabled: bool };
/// Ignore body contents while preserving source outside bodies and resolved type identities.
pub fn prepare(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, records: []const typed.Record) error{ OutOfMemory, InternalError }!Prepared {
    const bodies = try allocator.alloc(source.Span, program.functions.len);
    var enabled = !@import("nominal_type_syntax.zig").present(program);
    for (program.functions, bodies) |function, *body| {
        body.* = program.statements.items[@backingInt(function.body)].span;
        if (function.signature.type_parameters.len != 0 or function.policy.constant) enabled = false;
    }
    for (program.types.domains) |domain| if (domain.type_parameters.len != 0) {
        enabled = false;
    };
    var hash = Hash.init(.{});
    hash.update("semantic-functions-v1");
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
    return .{ .digest = hash.finalResult(), .bodies = bodies, .enabled = enabled };
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
