//! `W_CAPABILITY_MUT`: a `mut` capability parameter that nothing writes (5C).
//!
//! A capability is a shareable handle now, a scalar like an integer. `mut` on a scalar parameter means "a rebinding of
//! the parameter reaches the caller", and a capability parameter that the body never assigns and never passes on as a
//! `mut` argument has nothing to hand back, so the marker only makes every caller write `mut fs`. Agents write it out of
//! habit (`func read(mut fs: Filesystem)`). This pass reports each such declaration as a warning whose certain fix
//! deletes the `mut`.
//!
//! The fix edits the declaration only. The call sites then carry the existing `E_MUTATION_MARKER` refusal ("does not
//! write `fs`; remove `mut`"), whose own fix deletes the argument's marker, and `selka fix` runs rounds until the
//! project settles: a function that passed its parameter on as `mut` to a callee that just lost its own `mut` warns in
//! the next round.
//!
//! A function used as a value (stored in a record, passed as a callback) is left alone: its function type spells the
//! `mut` too, and the two must agree, so deleting the declaration's marker would be a type error.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const origins = @import("origins.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");

/// The warning code `selka fix` applies.
pub const code = "W_CAPABILITY_MUT";

const message = "a capability is a shareable handle now, so `mut` on this parameter only makes every caller write `mut`: " ++
    "the body never assigns it or passes it on as `mut`; remove `mut` here (`selka fix` removes it at the call sites too)";

/// Report every `mut` capability parameter that its function's body never writes, for the checked functions whose bodies
/// this check holds.
pub fn warn(memory: std.mem.Allocator, program: typed.Program, src: source.Source, stubs: []const ?origins.Fact, sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    var as_value: ?[]bool = null;
    defer if (as_value) |flags| memory.free(flags);
    for (program.functions, 0..) |function, index| {
        if (function.signature.mutates.len == 0) continue;
        if (function.policy.host != null or function.policy.c_abi) continue;
        if (origins.standIn(stubs, index) != null) continue;
        if (!function.scope.body_complete or function.type_arguments.len != 0) continue;
        const count = @min(function.signature.parameter_count, function.scope.locals.len);
        for (function.signature.mutates) |position| {
            if (position >= count) continue;
            const local = function.scope.locals[position];
            if (!unwritten(function, position, local)) continue;
            const edit = parameterMarker(src, local.declaration) orelse continue;
            // The function's uses are found once, and only when a parameter qualifies.
            if (as_value == null) as_value = try functionValues(memory, program);
            if (as_value.?[index]) break;
            try sink.appendFix(.{ .severity = .warning, .code = code, .span = edit.span, .message = message }, edit);
        }
    }
}

/// Whether parameter `position`, a declared `mut` capability, is never written: not assigned, and not passed on as `mut`.
fn unwritten(function: typed.Function, position: u16, local: typed.Local) bool {
    if (local.ty.capabilityIndex() == null or local.ty == .host_cap) return false;
    if (local.usage.writes != 0) return false;
    const owned = function.scope.own_parameters;
    return position >= owned.len or !owned[position];
}

/// One flag per function: true where the function is named as a value somewhere in the checked bodies.
fn functionValues(memory: std.mem.Allocator, program: typed.Program) std.mem.Allocator.Error![]bool {
    const flags = try memory.alloc(bool, program.functions.len);
    @memset(flags, false);
    for (program.nodes) |node| switch (node.data) {
        .function_value => |id| if (@backingInt(id) < flags.len) {
            flags[@backingInt(id)] = true;
        },
        else => {},
    };
    return flags;
}

/// The edit deleting the `mut ` written before a parameter's name, or null when the source does not spell it there.
pub fn parameterMarker(src: source.Source, name: source.Span) ?diagnostic.Edit {
    if (name.start > src.bytes.len or name.start < 4) return null;
    var cursor = name.start;
    while (cursor > 0 and (src.bytes[cursor - 1] == ' ' or src.bytes[cursor - 1] == '\t')) cursor -= 1;
    if (cursor == name.start or cursor < 3) return null;
    if (!std.mem.eql(u8, src.bytes[cursor - 3 .. cursor], "mut")) return null;
    if (cursor > 3 and identifierByte(src.bytes[cursor - 4])) return null;
    return .{ .span = .{ .start = cursor - 3, .end = name.start }, .text = "" };
}

fn identifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

test "the parameter edit deletes mut and its blanks, and nothing that only ends in mut" {
    const text = "func f(mut fs: Filesystem, summut x: int)";
    const src: source.Source = .{ .path = "t.selka", .bytes = text, .line_starts = &.{0} };
    const at = std.mem.indexOf(u8, text, "fs:").?;
    const edit = parameterMarker(src, .{ .start = at, .end = at + 2 }).?;
    try std.testing.expectEqualStrings("mut ", text[edit.span.start..edit.span.end]);
    const other = std.mem.indexOf(u8, text, "x:").?;
    try std.testing.expect(parameterMarker(src, .{ .start = other, .end = other + 1 }) == null);
}
