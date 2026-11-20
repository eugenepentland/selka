//! The `W_COPY_MOVE` loop hint ("`x` is copied out of each element of `xs`") as repairs `selka fix` applies, where the
//! rewrite is certain (COPY-A2c).
//!
//! Inside one function (`needless_copy.zig`, `loopRepair`): the loop over a list a call returns, or over an owned list, whose
//! copy case (ix) left (a field of the element, `copy(x.f)`, or a copy an `own` argument takes) is a `W_NEEDLESS_COPY` repair:
//! `for x in own xs:` and `own x.f`. `copy_loop_edits.zig` writes its edits and message.
//!
//! A plain list parameter (`warn`): the hint "(each of its callers then gives its list with `own`)" is a `W_COPY_FOR_STORE`
//! warning beside it, the `own`-parameter repair for a list. Its edits are `own ` before the parameter and every repair the
//! needless-copy pass proves only once the parameter is `own` (`needless_copy.warnOne`, the function as declared and with the
//! parameter `own`): `for x in own xs:` and `own x` or `own x.f` for each loop, and `own p` for a stored `copy(p)`
//! (`needless_copy.provedWithOwn`). It is the same finding as a stored copy's, so it takes that code: the callers are judged
//! as that warning's are, and the `own ` before each caller's last use of a name is written the same way
//! (`copy_for_store.callerMarks`). The same withholding applies: a project check only; an ordinary function
//! (`copy_for_store.ordinary`: a `public` one only in a project that is no package) that does not call or name itself; a parameter with no default and no `from`; a caller that
//! passes a place, a loop element, a plain parameter or a name it reads again. Where the warning stays, the hint beside it is
//! left out (`dropHintsBeside`).
const std = @import("std");
const copy_for_store = @import("copy_for_store.zig");
const copy_from_repair = @import("copy_from_repair.zig");
const diagnostic = @import("diagnostic.zig");
const needless_copy = @import("needless_copy.zig");
const origins = @import("origins.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");

/// What a hint about a plain list parameter adds to the advice: the callers give their lists up.
const callers_note = "(each of its callers then gives its list with `own`)";

/// Emit `W_COPY_FOR_STORE` beside each `W_COPY_MOVE` hint already in `sink` that asks a plain list parameter's callers to give
/// their lists with `own`, where the needless-copy pass proves the hinted copy a move once the parameter is `own`. A parameter
/// another warning of that code already names gains the loop's edits there. Its callers are judged afterwards, as that code's.
pub fn warn(memory: std.mem.Allocator, inputs: copy_for_store.Inputs, sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    if (!inputs.project) return;
    var done: std.AutoHashMapUnmanaged([2]usize, void) = .empty;
    const count = sink.items.items.len;
    for (0..count) |at| {
        const item = sink.items.items[at];
        const advice = needless_copy.judgedByCallers(item.code, item.message) orelse continue;
        if (advice.form != .argument or std.mem.indexOf(u8, item.message, callers_note) == null) continue;
        const index = copy_from_repair.functionAt(inputs.program, item.span) orelse continue;
        if (origins.standIn(inputs.stubs, index) != null) continue;
        const function = inputs.program.functions[index];
        if (!copy_for_store.ordinary(inputs, function, index)) continue;
        const parameter = copy_from_repair.parameterNamed(function, advice.parameter) orelse continue;
        if (!copy_for_store.ownable(inputs.program, function, parameter)) continue;
        if (!copy_for_store.plainDeclaration(inputs.src, function, parameter)) continue;
        if ((try done.getOrPut(memory, .{ index, parameter })).found_existing) continue;
        if (try copy_for_store.recursive(memory, inputs.program, function, index)) continue;
        const loops = try loopEditsWithOwn(memory, inputs, index, parameter);
        const covered = for (loops) |edit| {
            if (edit.span.start == item.span.start and edit.span.end == item.span.end) break true;
        } else false;
        if (!covered) continue;
        if (storeWarning(sink.items.items[0..count], inputs.program, index, advice.parameter)) |slot| {
            const fix = sink.items.items[slot].provenance.fix orelse continue;
            sink.items.items[slot].provenance.fix = .{ .edit = fix.edit, .more = try std.mem.concat(memory, diagnostic.Edit, &.{ fix.more, loops }) };
            continue;
        }
        const stored = try needless_copy.provedWithOwn(memory, inputs.program, inputs.src, index, parameter);
        const local = if (std.mem.lastIndexOf(u8, function.name, "::")) |colon| function.name[colon + 2 ..] else function.name;
        const name = function.scope.locals[parameter].name;
        const signature = if (copy_for_store.isPublic(inputs, index)) try std.fmt.allocPrint(memory, "; `{s}` is public, so its signature changes", .{local}) else "";
        const message = try std.fmt.allocPrint(memory, "`{s}` copies each element of parameter `{s}` into storage it keeps, and no caller needs " ++
            "the list after the call: declare it `own {s}` and loop over `own {s}`, and the function keeps the elements rather than copies{s}", .{ local, name, name, name, signature });
        const declared = function.scope.locals[parameter].declaration.start;
        try sink.items.append(sink.allocator, .{
            .code = copy_for_store.code,
            .severity = .warning,
            .span = item.span,
            .message = message,
            .provenance = .{ .fix = .{
                .edit = .{ .span = .{ .start = declared, .end = declared }, .text = "own " },
                .more = try std.mem.concat(memory, diagnostic.Edit, &.{ stored, loops }),
            } },
        });
    }
}

/// The position in `items` of a `W_COPY_FOR_STORE` warning of parameter `name` in the function at `index`, or null.
fn storeWarning(items: []const diagnostic.Diagnostic, program: typed.Program, index: usize, name: []const u8) ?usize {
    for (items, 0..) |item, at| {
        const advice = copy_for_store.judged(item.code, item.message) orelse continue;
        if (!std.mem.eql(u8, advice.parameter, name)) continue;
        if (copy_from_repair.functionAt(program, item.span) == index) return at;
    }
    return null;
}

/// The edits of the loop repairs (`W_NEEDLESS_COPY` with a header edit and a copy edit) the needless-copy pass makes in the
/// function at `index` only once parameter `parameter` is `own`, in order: the header's `own `, then the copy's.
pub fn loopEditsWithOwn(memory: std.mem.Allocator, inputs: copy_for_store.Inputs, index: usize, parameter: usize) std.mem.Allocator.Error![]const diagnostic.Edit {
    const declared = inputs.program.functions[index];
    const own = try memory.alloc(bool, @max(declared.signature.parameter_count, declared.scope.own_parameters.len));
    @memset(own, false);
    @memcpy(own[0..declared.scope.own_parameters.len], declared.scope.own_parameters);
    own[parameter] = true;
    var with_own = declared;
    with_own.scope.own_parameters = own;
    var before: std.AutoHashMapUnmanaged(source.Span, void) = .empty;
    for (try needless_copy.warnOne(memory, inputs.program, inputs.src, declared)) |item| {
        const fix = loopRepairOf(item) orelse continue;
        try before.put(memory, fix.more[0].span, {});
    }
    var found: std.ArrayList(diagnostic.Edit) = .empty;
    for (try needless_copy.warnOne(memory, inputs.program, inputs.src, with_own)) |item| {
        const fix = loopRepairOf(item) orelse continue;
        if (before.contains(fix.more[0].span)) continue;
        try found.appendSlice(memory, &.{ fix.edit, fix.more[0] });
    }
    return found.toOwnedSlice(memory);
}

/// The fix of a loop repair: a `W_NEEDLESS_COPY` whose first edit inserts `own ` and whose one other edit replaces the copy.
fn loopRepairOf(item: diagnostic.Diagnostic) ?diagnostic.Fix {
    if (!std.mem.eql(u8, item.code, needless_copy.code)) return null;
    const fix = item.provenance.fix orelse return null;
    if (fix.more.len != 1 or fix.edit.span.start != fix.edit.span.end or !std.mem.eql(u8, fix.edit.text, "own ")) return null;
    return fix;
}

// twin-drift-ok: `copy_from_repair.dropHintsBeside` leaves out the `from` hint at the span of its own warning; this one the
// loop hint at the span of a copy another code's repair replaces, read from that repair's edits.
/// Leave out each `W_COPY_MOVE` loop hint whose copy a `W_COPY_FOR_STORE` warning that stayed repairs: the warning is the same
/// advice with its repair. Run after the callers have judged both.
pub fn dropHintsBeside(items: *std.ArrayList(diagnostic.Diagnostic)) void {
    const any = for (items.items) |item| {
        if (std.mem.eql(u8, item.code, copy_for_store.code)) break true;
    } else false;
    if (!any) return;
    var index: usize = 0;
    while (index < items.items.len) {
        const item = items.items[index];
        const hint = needless_copy.judgedByCallers(item.code, item.message);
        if (hint != null and hint.?.form == .argument and repaired(items.items, item.span)) {
            _ = items.orderedRemove(index);
            continue;
        }
        index += 1;
    }
}

/// Whether a `W_COPY_FOR_STORE` warning in `items` replaces the copy at `span`.
fn repaired(items: []const diagnostic.Diagnostic, span: source.Span) bool {
    for (items) |item| {
        if (!std.mem.eql(u8, item.code, copy_for_store.code)) continue;
        const fix = item.provenance.fix orelse continue;
        for (fix.more) |edit| if (edit.span.start == span.start and edit.span.end == span.end) return true;
    }
    return false;
}
