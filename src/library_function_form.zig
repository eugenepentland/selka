//! FR34: the standard-library function a method call on a value without methods meant.
//!
//! `clock.now()` was answered "write the function form `now(clock)`; no function `now` is declared or in the prelude, so declare
//! it first", which points at a function that does not exist: the function is `time.now(clock)`, after `import time`. When no
//! function of the name is in scope and exactly one standard module declares one whose first parameter takes the receiver's
//! type, the answer names it, its module and the import, and carries the rewrite and the import as one repair when both edits
//! are certain. The search is the one a name another module lacks already makes (`standard_library.exporting`), over the library's
//! own text, so it needs no module the program did not import.
//!
//! FR37: the same answer for a method written on a capability reached through a field (`ctx.clock.now()`), with the receiver's
//! own text, for the four capabilities that have no methods and a module's function in their place (`capabilityAnswer`).
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const import_fix = @import("import_fix.zig");
const source = @import("source.zig");
const standard_library = @import("standard_library.zig");

/// What a method call that names a library function is told: the function form with its module, and the repair.
pub const Advice = struct {
    /// The module's qualified function form, `time.now(clock)`.
    form: []const u8,
    /// The standard module, `time`.
    module: []const u8,
    /// Whether the file already imports the module, so only the rewrite is advice.
    imported: bool,
    /// The rewrite of the call with the import, when every edit is certain.
    fix: ?diagnostic.Fix,
};

/// What the checker answers for a method call on a value without methods: the message, and the repair when there is a certain one.
pub const Answer = struct {
    message: []const u8,
    fix: ?diagnostic.Fix = null,
};

/// The call being advised: where it is written and what it is.
pub const Call = struct {
    /// The method's name as written.
    name: source.Span,
    /// The function form without its module, `now(clock)`.
    form: []const u8,
    /// The whole call `clock.now()`, when the caller knows it; without it no repair is offered.
    span: ?source.Span,
};

/// The advice for `call` on a receiver whose type the library spells `receiver_type`, or null when no one standard module declares
/// a function of that name for it, or when the file imports the module under another name (its qualifier is then not the module's).
pub fn advise(allocator: std.mem.Allocator, src: source.Source, receiver_type: []const u8, call: Call) std.mem.Allocator.Error!?Advice {
    const module = standard_library.declaringFirstParameter(src.text(call.name), receiver_type) orelse return null;
    return adviseFrom(allocator, src, module, call);
}

/// `advise` for the function `module` declares, once the module is chosen.
fn adviseFrom(allocator: std.mem.Allocator, src: source.Source, module: []const u8, call: Call) std.mem.Allocator.Error!?Advice {
    if (try importedUnderAnotherName(allocator, src, module)) return null;
    const form = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ module, call.form });
    const imported = import_fix.moduleEdit(allocator, src, call.name, module) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InternalError => return .{ .form = form, .module = module, .imported = false, .fix = null },
    };
    return .{ .form = form, .module = module, .imported = imported == null, .fix = try repair(allocator, src, call, form, imported) };
}

/// The rewrite of the call as `form`, with `imported` (the `import` line, or null when the file has it), or null when the call's
/// text is not one the rewrite can replace as it stands: a comment or a line break inside it would be lost.
fn repair(allocator: std.mem.Allocator, src: source.Source, call: Call, form: []const u8, imported: ?diagnostic.Edit) std.mem.Allocator.Error!?diagnostic.Fix {
    const span = call.span orelse return null;
    const written = src.text(span);
    if (std.mem.indexOfAny(u8, written, "#\n") != null or !std.mem.endsWith(u8, written, ")")) return null;
    var fix: diagnostic.Fix = .{ .edit = .{ .span = span, .text = form } };
    if (imported) |edit| fix.more = try allocator.dupe(diagnostic.Edit, &.{edit});
    return fix;
}

/// The message tail that names the function: `write the function form `time.now(clock)`, from the standard module `time`` and, when
/// the file does not import it, `, and add `import time``.
pub fn clause(allocator: std.mem.Allocator, advice: Advice) std.mem.Allocator.Error![]const u8 {
    if (advice.imported) return std.fmt.allocPrint(allocator, "`{s}`, from the standard module `{s}`", .{ advice.form, advice.module });
    return std.fmt.allocPrint(allocator, "`{s}`, from the standard module `{s}`, and add `import {s}`", .{ advice.form, advice.module, advice.module });
}

/// Whether the file writes `import module as name`: the module's own qualifier is then not the one the file uses.
fn importedUnderAnotherName(allocator: std.mem.Allocator, src: source.Source, module: []const u8) std.mem.Allocator.Error!bool {
    const renamed = try std.fmt.allocPrint(allocator, "import {s} as ", .{module});
    defer allocator.free(renamed);
    return std.mem.indexOf(u8, src.bytes, renamed) != null;
}

/// How a capability that has no methods is read, for the message a method written on it gets (FR37): `Clock` is read with
/// `time.now(clock)`, so `ctx.clock.now()` and `ctx.clock.tick()` both say `time.now(ctx.clock)`.
pub const Reading = struct {
    /// The type as the library spells it and as a message names it: `Clock`.
    type_name: []const u8,
    /// What the message says to do: `read it with`.
    verb: []const u8,
    /// The standard module that has the function: `time`.
    module: []const u8,
    /// The function that reads the capability: `now`.
    function: []const u8,
    /// The capability's parameter in the function's own text: `clock`.
    parameter: []const u8,
    /// What follows the capability in the call, when the function takes more: `, request`.
    more: []const u8 = "",
};

/// The article before a type's name: `an` before a vowel.
fn article(name: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, "AEIOU", name[0]) != null) "an" else "a";
}

/// The sentence a capability without methods has always been refused with, from its reading: `a Clock has no methods; read it
/// with time.now(clock)`. It is the text that stays when the call's own text is not known or the module is imported under another name.
pub fn describe(comptime reading: Reading) []const u8 {
    return comptime article(reading.type_name) ++ " " ++ reading.type_name ++ " has no methods; " ++ reading.verb ++ " " ++
        reading.module ++ "." ++ reading.function ++ "(" ++ reading.parameter ++ reading.more ++ ")";
}

/// Whether `text` is a plain field path, names joined by dots (`ctx.clock`, `a.b.c`): nothing in it is a call, an index, a
/// bracket or a space, so replacing the call that has it as receiver replaces exactly what was written.
fn isFieldPath(text: []const u8) bool {
    var segments = std.mem.splitScalar(u8, text, '.');
    var count: usize = 0;
    while (segments.next()) |segment| : (count += 1) {
        if (segment.len == 0 or std.ascii.isDigit(segment[0])) return false;
        for (segment) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return count >= 2;
}

/// The answer for a method written on a capability without methods that is reached through an expression (`ctx.clock.now()`),
/// as the text that follows `unknown method for a Clock receiver; `, or null when the file imports the module under another
/// name (the text `describe` gives then stays). `receiver` is the receiver as written and `call` the whole call. When the method
/// named is the function the standard module declares for the type (`now`) and no function of the name is in scope (`own`), the
/// answer is that function with the receiver's own text, the import when the file lacks it, and, when the receiver is a plain
/// field path and the call has no comment or line break, the repair. Any other method is told how the capability is read.
pub fn capabilityAnswer(allocator: std.mem.Allocator, src: source.Source, reading: Reading, receiver: source.Span, call: Call, own: bool) std.mem.Allocator.Error!?Answer {
    const subject = try std.fmt.allocPrint(allocator, "{s} {s} has no methods", .{ article(reading.type_name), reading.type_name });
    const written: Call = if (isFieldPath(src.text(receiver))) call else .{ .name = call.name, .form = call.form, .span = null };
    const home = standard_library.declaringFirstParameterHome(src.text(call.name), reading.type_name, reading.module);
    if (!own) if (home) |module| if (try adviseFrom(allocator, src, module, written)) |advice| {
        const message = try std.fmt.allocPrint(allocator, "{s}; write the function form {s}", .{ subject, try clause(allocator, advice) });
        return .{ .message = message, .fix = advice.fix };
    };
    if (try importedUnderAnotherName(allocator, src, reading.module)) return null;
    const imported = if (import_fix.moduleEdit(allocator, src, call.name, reading.module)) |edit| edit == null else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InternalError => false,
    };
    const import_clause = if (imported) "" else try std.fmt.allocPrint(allocator, ", and add `import {s}`", .{reading.module});
    const message = try std.fmt.allocPrint(allocator, "{s}; {s} {s}.{s}({s}{s}){s}", .{
        subject, reading.verb, reading.module, reading.function, src.text(receiver), reading.more, import_clause,
    });
    return .{ .message = message };
}
