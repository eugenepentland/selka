//! `W_COPY_RETURNED`: the `W_COPY_MOVE` hint "every return of `f` copies a place of `p`" as a repair `selka fix` applies,
//! where the rewrite is certain.
//!
//! The repair writes ` from p` after the function's result type and turns each returned `copy(PLACE)` into `PLACE`; the
//! callers are not edited. It is raised beside the hint (same span), by a project check only (entry `selka_check_all`, whose
//! program holds every caller there can be), for an ordinary function (`copy_for_store.ordinary`: generic, `main`, a test, a
//! lambda or a callback apart, and a `public` one unless `Inputs.public_repaired`: the project is no package, COPY-FROM-PUBLIC)
//! that is not named as a value and does not call itself. A `public` function's message ends "; `f` is public, so its signature
//! changes".
//! The hint itself names only what the function alone allows (`from_advice.zig`, which `warnReturnsFrom` asks): a
//! parameter that lends the result (a plain text parameter lends no record, `E_BORROW_SOURCE`; a `mut` one cannot lend the
//! success of a function that fails with a managed error, `E_CORE_UNSUPPORTED`), and other returns that are constants (a
//! new value beside a borrowed return is `E_BORROW_MIXED`).
//!
//! The callers are judged afterwards with the hints (`src/main.zig` cold, `sema_summaries` cached), more strictly: a caller
//! the ownership check refuses with the result `from p` for any reason, its own undeclared borrowed return included,
//! withholds the warning, and the hint stays. Where the warning stays, the hint beside it is left out (`dropHintsBeside`).
const std = @import("std");
const copy_for_store = @import("copy_for_store.zig");
const diagnostic = @import("diagnostic.zig");
const needless_copy = @import("needless_copy.zig");
const origins = @import("origins.zig");
const return_borrow = @import("return_borrow.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");

/// The warning code of a function whose every return copies a place of one parameter, where declaring the result `from` it
/// is the repair `selka fix` applies.
pub const code = "W_COPY_RETURNED";

/// The opening the hint and the warning share before the parameter's name.
const place_opening = "copies a place of `";

/// Emit `W_COPY_RETURNED` with its repair beside each `W_COPY_MOVE` "every return" hint already in `sink` whose rewrite the
/// function alone makes certain. Its callers are judged afterwards (`judged`).
pub fn warn(memory: std.mem.Allocator, inputs: copy_for_store.Inputs, sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    if (!inputs.project) return;
    const count = sink.items.items.len;
    for (0..count) |at| {
        const item = sink.items.items[at];
        const advice = needless_copy.judgedByCallers(item.code, item.message) orelse continue;
        if (advice.form != .result) continue;
        const index = functionAt(inputs.program, item.span) orelse continue;
        if (origins.standIn(inputs.stubs, index) != null) continue;
        const function = inputs.program.functions[index];
        if (!copy_for_store.ordinary(inputs, function, index)) continue;
        const parameter = parameterNamed(function, advice.parameter) orelse continue;
        if (try namedOrRecursive(memory, inputs.program, index)) continue;
        const fix = try repair(memory, inputs, function, parameter) orelse continue;
        const local = if (std.mem.lastIndexOf(u8, function.name, "::")) |colon| function.name[colon + 2 ..] else function.name;
        const name = function.scope.locals[parameter].name;
        const signature = if (copy_for_store.isPublic(inputs, index)) try std.fmt.allocPrint(memory, "; `{s}` is public, so its signature changes", .{local}) else "";
        const message = try std.fmt.allocPrint(memory, "every return of `{s}` copies a place of `{s}`, and no caller keeps the result: " ++
            "declare it `from {s}` and return the places themselves{s}", .{ local, name, name, signature });
        try sink.items.append(sink.allocator, .{
            .code = code,
            .severity = .warning,
            .span = item.span,
            .message = message,
            .provenance = .{ .fix = fix },
        });
    }
}

/// The advice of a `W_COPY_RETURNED` warning as the caller judge reads a `W_COPY_MOVE` hint's: a result `from` the parameter
/// the message names; null for any other diagnostic.
pub fn judged(diagnostic_code: []const u8, message: []const u8) ?needless_copy.Judged {
    if (!std.mem.eql(u8, diagnostic_code, code)) return null;
    const at = std.mem.indexOf(u8, message, place_opening) orelse return null;
    const rest = message[at + place_opening.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '`') orelse return null;
    return .{ .form = .result, .parameter = rest[0..end] };
}

/// Leave out each `W_COPY_MOVE` hint at the span of a `W_COPY_RETURNED` warning that stayed: the warning is the same advice
/// with its repair. Run after the callers have judged both.
pub fn dropHintsBeside(items: *std.ArrayList(diagnostic.Diagnostic)) void {
    var any = false;
    for (items.items) |item| {
        if (std.mem.eql(u8, item.code, code)) any = true;
    }
    if (!any) return;
    var index: usize = 0;
    while (index < items.items.len) {
        const item = items.items[index];
        const hint = needless_copy.judgedByCallers(item.code, item.message);
        const beside = hint != null and hint.?.form == .result and for (items.items) |other| {
            if (std.mem.eql(u8, other.code, code) and other.span.start == item.span.start and other.span.end == item.span.end) break true;
        } else false;
        if (beside) {
            _ = items.orderedRemove(index);
            continue;
        }
        index += 1;
    }
}

/// The function a diagnostic at `span` is in: the one declared last before it (functions do not nest), not generic.
pub fn functionAt(program: typed.Program, span: source.Span) ?usize {
    var nearest: ?usize = null;
    for (program.functions, 0..) |function, index| {
        if (function.type_arguments.len != 0 or function.declaration.start > span.start) continue;
        if (nearest) |best| if (program.functions[best].declaration.start >= function.declaration.start) continue;
        nearest = index;
    }
    return nearest;
}

/// The position of the parameter of `function` called `name`.
pub fn parameterNamed(function: typed.Function, name: []const u8) ?usize {
    const count = @min(function.signature.parameter_count, function.scope.locals.len);
    for (function.scope.locals[0..count], 0..) |local, slot| {
        if (std.mem.eql(u8, local.name, name)) return slot;
    }
    return null;
}

/// Whether the function at `index` is named as a value anywhere in the program (a function with a `from` result cannot be
/// one), or its own body calls it.
fn namedOrRecursive(memory: std.mem.Allocator, program: typed.Program, index: usize) std.mem.Allocator.Error!bool {
    for (program.nodes) |node| switch (node.data) {
        .function_value => |named| if (@backingInt(named) == index) return true,
        else => {},
    };
    var body = try walk.Walker.init(memory, program, program.functions[index].scope.body);
    defer body.deinit();
    while (try body.next()) |item| {
        const id = switch (item) {
            .expression => |value| value,
            .statement => continue,
        };
        switch (program.nodes[@backingInt(id)].data) {
            .call => |call| if (@backingInt(call.function) == index) return true,
            else => {},
        }
    }
    return false;
}

/// Whether `caller`'s body names the function at `callee` as a value, which a function with a `from` result cannot be
/// (`E_VIEW_FUNCTION_VALUE`): the cached judge asks it of a caller that also calls the function, as the cold one finds every
/// such use in the program.
pub fn namesAsValue(memory: std.mem.Allocator, program: typed.Program, caller: typed.Function, callee: usize) std.mem.Allocator.Error!bool {
    if (!caller.scope.body_complete) return false;
    var body = try walk.Walker.init(memory, program, caller.scope.body);
    defer body.deinit();
    while (try body.next()) |item| {
        const id = switch (item) {
            .expression => |value| value,
            .statement => continue,
        };
        switch (program.nodes[@backingInt(id)].data) {
            .function_value => |named| if (@backingInt(named) == callee) return true,
            else => {},
        }
    }
    return false;
}

/// The repair: ` from PARAMETER` after the result type, and each returned `copy(PLACE)` written `PLACE`. Null when the
/// signature or a copy is not spelled the way the edit expects.
fn repair(memory: std.mem.Allocator, inputs: copy_for_store.Inputs, function: typed.Function, parameter: usize) std.mem.Allocator.Error!?diagnostic.Fix {
    const program = inputs.program;
    const src = inputs.src;
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    var body = try walk.Walker.init(memory, program, function.scope.body);
    defer body.deinit();
    while (try body.next()) |item| {
        const statement = switch (item) {
            .statement => |value| value,
            .expression => continue,
        };
        const value = switch (program.statements[@backingInt(statement)].data) {
            .ret => |returned| returned,
            else => continue,
        };
        if (!try returnedCopies(memory, program, src, value, &edits)) return null;
    }
    if (edits.items.len == 0) return null;
    const at = resultEnd(src, function.declaration) orelse return null;
    const clause = try std.fmt.allocPrint(memory, " from {s}", .{function.scope.locals[parameter].name});
    return .{ .edit = .{ .span = .{ .start = at, .end = at }, .text = clause }, .more = try edits.toOwnedSlice(memory) };
}

/// Append the edit of each `copy(PLACE)` one returned value holds, as the hint reads it: the value itself, or the payload of
/// an option's `Some` or a result's success. False when a copy is not spelled `copy(...)`.
fn returnedCopies(memory: std.mem.Allocator, program: typed.Program, src: source.Source, id: typed.NodeId, edits: *std.ArrayList(diagnostic.Edit)) std.mem.Allocator.Error!bool {
    var current = id;
    for (0..32) |_| {
        const value = needless_copy.inherited(program, current);
        const node = program.nodes[@backingInt(value)];
        if (needless_copy.isCopy(program, value)) {
            const text = src.text(node.span);
            const open = "copy(";
            if (!std.mem.startsWith(u8, text, open) or !std.mem.endsWith(u8, text, ")")) return false;
            const inner = std.mem.trim(u8, text[open.len .. text.len - 1], " \t");
            if (inner.len == 0 or std.mem.indexOfAny(u8, inner, "\r\n") != null) return false;
            try edits.append(memory, .{ .span = node.span, .text = try memory.dupe(u8, inner) });
            return true;
        }
        const variant = switch (node.data) {
            .variant => |found| found,
            else => return true,
        };
        const step = return_borrow.step(program.records, node.ty) orelse return true;
        if (variant.tag != step.tag) return true;
        current = variant.value orelse return true;
    }
    return false;
}

/// The offset just after the result type of the function whose name is `name`: past the parameter list, `->` and the type,
/// before a `fails` clause or the `:` that ends the header. Null for a header the scan does not read (no result type, a
/// `from` or `where` clause, a function type as the result).
fn resultEnd(src: source.Source, name: source.Span) ?u32 {
    const bytes = src.bytes;
    var at: usize = name.end;
    // Type parameters, then the parameter list.
    var depth: usize = 0;
    var opened = false;
    while (at < bytes.len) : (at += 1) {
        switch (bytes[at]) {
            '(', '[', '{' => {
                if (bytes[at] == '(') opened = true;
                depth += 1;
            },
            ')', ']', '}' => {
                if (depth == 0) return null;
                depth -= 1;
                if (depth == 0 and bytes[at] == ')' and opened) break;
            },
            ':' => if (depth == 0) return null,
            else => {},
        }
    }
    if (at >= bytes.len) return null;
    at += 1;
    while (at < bytes.len and (bytes[at] == ' ' or bytes[at] == '\t')) at += 1;
    if (!std.mem.startsWith(u8, bytes[at..], "->")) return null;
    at += 2;
    const start = at;
    depth = 0;
    var end: ?usize = null;
    while (at < bytes.len) : (at += 1) {
        const byte = bytes[at];
        switch (byte) {
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => {
                if (depth == 0) return null;
                depth -= 1;
            },
            '\n', '#' => if (depth == 0) return null,
            ':' => if (depth == 0) {
                end = at;
                break;
            },
            else => if (depth == 0 and (at == start or !word(bytes[at - 1]))) if (keyword(bytes[at..])) |found| {
                if (!std.mem.eql(u8, found, "fails")) return null;
                end = at;
                break;
            },
        }
    }
    const stop = end orelse return null;
    const spelled = std.mem.trimEnd(u8, bytes[start..stop], " \t");
    if (std.mem.trim(u8, spelled, " \t").len == 0 or std.mem.indexOf(u8, spelled, "->") != null) return null;
    return @intCast(start + spelled.len);
}

/// The clause keyword `text` starts with, as a whole word, or null.
fn keyword(text: []const u8) ?[]const u8 {
    for ([_][]const u8{ "fails", "from", "where" }) |found| {
        if (std.mem.startsWith(u8, text, found) and (text.len == found.len or !word(text[found.len]))) return found;
    }
    return null;
}

/// Whether `byte` can be part of a name.
fn word(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}
