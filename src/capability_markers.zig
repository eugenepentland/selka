//! `W_CAPABILITY_OWN`: an `own` marker that capability handles (5C) made redundant.
//!
//! Before 5C a `Filesystem`, `Clock`, `Entropy`, `Environment`, `Network` or `Process` owned its provider state, so
//! passing one on, or a record that held one, needed `own`: `make(own fs)`, `Ctx(fs=own fs)`, `func make(own fs:
//! Filesystem)`. A capability is a scalar handle now, copied like an integer, and those markers transfer nothing. They
//! still check, so no accepted program is refused; this pass reports each one as a warning whose certain fix deletes
//! the marker, and `selka fix` cleans a project in one run.
//!
//! The pass reports two shapes:
//! - an `own` expression whose value is a capability, or a value that owns nothing now and held a capability (Core's
//!   ownership check accepts the marker for exactly these values, `provider_types.holdsFormerLeaf`);
//! - an `own` parameter declaration whose type is such a value.
//!
//! A marker in a generic instance (its type depends on a type parameter) is left alone: the template is shared, and
//! `own` may transfer another instance's value.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const origins = @import("origins.zig");
const own_parameters = @import("own_parameters.zig");
const provider_types = @import("provider_types.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");

/// The warning code `selka fix` applies.
pub const code = "W_CAPABILITY_OWN";

const expression_message = "a capability is a shareable handle now, so `own` transfers nothing here; remove it";
const parameter_message = "a capability is a shareable handle now, so an `own` parameter takes nothing; remove `own`";

/// Report every redundant capability `own` marker of the checked functions whose bodies this check holds.
pub fn warn(memory: std.mem.Allocator, program: typed.Program, src: source.Source, stubs: []const ?origins.Fact, sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
    defer seen.deinit(memory);
    for (program.functions, 0..) |function, index| {
        if (function.policy.host != null) continue;
        if (origins.standIn(stubs, index) != null) continue;
        if (!function.scope.body_complete) continue;
        if (function.type_arguments.len == 0) try parameters(memory, program, src, function, &seen, sink);
        var body = try walk.Walker.init(memory, program, function.scope.body);
        defer body.deinit();
        while (try body.next()) |item| {
            const id = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            const node = program.nodes[@backingInt(id)];
            if (!node.own or node.type_dependent) continue;
            if (!redundant(program.records, node.ty)) continue;
            const edit = remove(src, node.span) orelse continue;
            try report(memory, &seen, sink, node.span, edit, expression_message);
        }
    }
}

/// Whether `own` on a value of `ty` is redundant since 5C: the value owns nothing now and held a capability.
pub fn redundant(records: []const typed.Record, ty: typed.Type) bool {
    return !own_parameters.managed(records, ty) and provider_types.holdsFormerLeaf(records, ty);
}

fn parameters(memory: std.mem.Allocator, program: typed.Program, src: source.Source, function: typed.Function, seen: *std.AutoHashMapUnmanaged(usize, void), sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    const flags = function.scope.own_parameters;
    const count = @min(flags.len, function.signature.parameter_count, function.scope.locals.len);
    for (function.scope.locals[0..count], flags[0..count]) |local, own| {
        if (!own or !redundant(program.records, local.ty)) continue;
        const edit = parameterMarker(src, local.declaration) orelse continue;
        try report(memory, seen, sink, edit.span, edit, parameter_message);
    }
}

fn report(memory: std.mem.Allocator, seen: *std.AutoHashMapUnmanaged(usize, void), sink: *diagnostic.Sink, span: source.Span, edit: diagnostic.Edit, message: []const u8) std.mem.Allocator.Error!void {
    const entry = try seen.getOrPut(memory, edit.span.start);
    if (entry.found_existing) return;
    try sink.appendFix(.{ .severity = .warning, .code = code, .span = span, .message = message }, edit);
}

/// The edit deleting the `own` that a marked expression's span starts with, and the blanks after it.
pub fn remove(src: source.Source, span: source.Span) ?diagnostic.Edit {
    if (span.end > src.bytes.len or span.start >= span.end) return null;
    const text = src.text(span);
    var start: usize = 0;
    while (start < text.len and (text[start] == '(' or std.ascii.isWhitespace(text[start]))) start += 1;
    if (!std.mem.startsWith(u8, text[start..], "own")) return null;
    var end = start + 3;
    if (end == text.len or identifierByte(text[end])) return null;
    while (end < text.len and (text[end] == ' ' or text[end] == '\t')) end += 1;
    return .{ .span = .{ .start = span.start + start, .end = span.start + end }, .text = "" };
}

/// The edit deleting the `own ` written before a parameter's name, or null when the source does not spell it there.
pub fn parameterMarker(src: source.Source, name: source.Span) ?diagnostic.Edit {
    if (name.start > src.bytes.len or name.start < 4) return null;
    var cursor = name.start;
    while (cursor > 0 and (src.bytes[cursor - 1] == ' ' or src.bytes[cursor - 1] == '\t')) cursor -= 1;
    if (cursor == name.start or cursor < 3) return null;
    if (!std.mem.eql(u8, src.bytes[cursor - 3 .. cursor], "own")) return null;
    if (cursor > 3 and identifierByte(src.bytes[cursor - 4])) return null;
    return .{ .span = .{ .start = cursor - 3, .end = name.start }, .text = "" };
}

fn identifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

test "the marker edits delete own and its blanks, and nothing that only ends in own" {
    const text = "f(own fs, own  ctx)\nfunc g(own fs: Filesystem, known: int)";
    const src: source.Source = .{ .path = "t.selka", .bytes = text, .line_starts = &.{0} };
    const first = remove(src, .{ .start = 2, .end = 8 }).?;
    try std.testing.expectEqual(@as(usize, 2), first.span.start);
    try std.testing.expectEqual(@as(usize, 6), first.span.end);
    const second = remove(src, .{ .start = 10, .end = 18 }).?;
    try std.testing.expectEqual(@as(usize, 15), second.span.end);
    const name_at = std.mem.indexOf(u8, text, "fs:").?;
    const parameter = parameterMarker(src, .{ .start = name_at, .end = name_at + 2 }).?;
    try std.testing.expectEqualStrings("own ", text[parameter.span.start..parameter.span.end]);
    const known_at = std.mem.indexOf(u8, text, "known").?;
    try std.testing.expect(parameterMarker(src, .{ .start = known_at, .end = known_at + 5 }) == null);
}
