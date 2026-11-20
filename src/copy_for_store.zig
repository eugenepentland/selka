//! Which parameters a function copies into storage it keeps, where declaring the parameter `own` is the repair.
//!
//! A statement that stores `copy(p)` of a parameter `p` (a record field, a list or dictionary write, a
//! return) pays for a copy that an `own` parameter would not need. This file decides that one thing:
//! "this statement copies parameter `p` into storage". `selka lint`'s `L_COPY_FOR_STORE` reads it, and
//! the repair that edits the declaration reads the same answer, so the two cannot disagree.
//!
//! The copy is reported only where `own` can be written and changes something: a parameter that is
//! already `own`, one that is `mut` (a `mut` parameter writes the caller's value; `own` would be a
//! different promise), and one whose type holds no managed storage (`own` on it is `E_OWN_MARKER`).
//!
//! `W_COPY_FOR_STORE` (`warn`) is the same finding as a check warning with its repair, which `selka fix` applies: raised
//! by a project check only, for an ordinary function that is not generic, recursive or named as a value (nor `public`, unless the
//! project is no package: `Inputs.public_repaired`), a parameter with no default and no `from`, a copy the needless-copy pass
//! proves a move once the parameter is `own`, and callers that all pass there a new value or the bare name of an owned local or
//! `own` parameter the ownership check finds they no longer need (`callerMarks`, judged as the `W_COPY_MOVE` hints are). The edits: `own ` before the parameter,
//! `copy(p)` to `own p`, and `own ` before each such name, in whatever file its caller is (`withMarks`, added once the
//! callers are judged). Elsewhere lint's advice stays.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const needless_copy = @import("needless_copy.zig");
const origins = @import("origins.zig");
const own_parameters = @import("own_parameters.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");

/// The warning code of a parameter copied into storage, where declaring it `own` is the repair `selka fix` applies.
pub const code = "W_COPY_FOR_STORE";

/// What the warning pass reads of one checked program.
pub const Inputs = struct {
    program: typed.Program,
    src: source.Source,
    /// The functions a semantic summary stood in for: their warnings are replayed from the summary, not derived.
    stubs: []const ?origins.Fact,
    /// One flag per function, true for a `public` one: a caller outside the project may lend it a value.
    exported: []const bool,
    /// Whether the check is a project check (`selka check DIR`), whose program holds every caller there can be.
    project: bool,
    /// Whether a `public` function is repaired like a private one: the project sets no `interface_files` and its modules are not
    /// all inside one namespace, so no package root (`selka packages lock`) can hold them and every caller is in the check.
    public_repaired: bool = false,
};

/// Emit `W_COPY_FOR_STORE` with its repair for each parameter whose stored copy an `own` declaration would make a move. The
/// callers are judged afterwards, with the `W_COPY_MOVE` hints (`judged`): a caller that passes anything but a new value or
/// a markable name, or a caller the ownership check would refuse with the parameter `own`, leaves the warning out.
pub fn warn(memory: std.mem.Allocator, inputs: Inputs, sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    if (!inputs.project) return;
    for (inputs.program.functions, 0..) |function, index| {
        if (origins.standIn(inputs.stubs, index) != null or !ordinary(inputs, function, index)) continue;
        const copies = try storedCopies(memory, inputs.program, function);
        if (copies.len == 0) continue;
        if (try recursive(memory, inputs.program, function, index)) continue;
        for (copies, 0..) |copied, at| {
            const named_before = for (copies[0..at]) |earlier| {
                if (earlier.parameter == copied.parameter) break true;
            } else false;
            if (named_before or !plainDeclaration(inputs.src, function, copied.parameter)) continue;
            try warnParameter(memory, inputs, .{ .index = index, .parameter = copied.parameter, .copies = copies }, sink);
        }
    }
}

/// One parameter the pass judges: its function's position, its own position and the function's stored copies.
const Candidate = struct { index: usize, parameter: usize, copies: []const Copy };

/// Emit the warning of one parameter when the needless-copy pass proves a copy of it a move with the parameter `own` (the
/// last of `id=copy(id), title=copy(id)`, where lint names the first); the repair writes `own ` before the parameter and
/// every copy that pass proves. The warning points at the stored copy lint names.
fn warnParameter(memory: std.mem.Allocator, inputs: Inputs, candidate: Candidate, sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    const edits = try needless_copy.provedWithOwn(memory, inputs.program, inputs.src, candidate.index, candidate.parameter);
    if (edits.len == 0) return;
    const span = for (candidate.copies) |copied| {
        if (copied.parameter == candidate.parameter) break copied.span;
    } else return;
    const function = inputs.program.functions[candidate.index];
    const name = function.scope.locals[candidate.parameter].name;
    const at = function.scope.locals[candidate.parameter].declaration.start;
    const local = if (std.mem.lastIndexOf(u8, function.name, "::")) |colon| function.name[colon + 2 ..] else function.name;
    const signature = if (isPublic(inputs, candidate.index)) try std.fmt.allocPrint(memory, "; `{s}` is public, so its signature changes", .{local}) else "";
    const message = try std.fmt.allocPrint(memory, "`{s}` copies parameter `{s}` into storage it keeps, and no caller needs the value after the call: " ++
        "declare it `own {s}` and the function keeps that value rather than a copy{s}", .{ local, name, name, signature });
    try sink.items.append(sink.allocator, .{
        .code = code,
        .severity = .warning,
        .span = span,
        .message = message,
        .provenance = .{ .fix = .{ .edit = .{ .span = .{ .start = at, .end = at }, .text = "own " }, .more = edits } },
    });
}

/// The advice of a `W_COPY_FOR_STORE` warning as the caller judge reads a `W_COPY_MOVE` hint's (`needless_copy.Judged`): an
/// `own` parameter, named by the message (a stored copy's, or a list's whose elements a loop copies, `copy_loop_repair.zig`);
/// null for any other diagnostic.
pub fn judged(diagnostic_code: []const u8, message: []const u8) ?needless_copy.Judged {
    if (!std.mem.eql(u8, diagnostic_code, code)) return null;
    const opening = "copies parameter `";
    const element_opening = "copies each element of parameter `";
    const rest = if (std.mem.indexOf(u8, message, opening)) |at|
        message[at + opening.len ..]
    else if (std.mem.indexOf(u8, message, element_opening)) |at|
        message[at + element_opening.len ..]
    else
        return null;
    const end = std.mem.indexOfScalar(u8, rest, '`') orelse return null;
    return .{ .form = .argument, .parameter = rest[0..end] };
}

/// Whether the function at `index` is `public`: its signature is part of the module's interface.
pub fn isPublic(inputs: Inputs, index: usize) bool {
    return index < inputs.exported.len and inputs.exported[index];
}

/// Whether the function at `index` is one the warning may change: an ordinary declared function with a checked body, not
/// `public` (unless `Inputs.public_repaired`), generic, `main`, a test or a benchmark, a lambda, a callback, a host, foreign, builtin or conversion function.
pub fn ordinary(inputs: Inputs, function: typed.Function, index: usize) bool {
    if (!function.scope.body_complete or function.type_arguments.len != 0) return false;
    if (isPublic(inputs, index) and !inputs.public_repaired) return false;
    if (index == @backingInt(inputs.program.main)) return false;
    const policy = function.policy;
    if (policy.host != null or policy.c_abi) return false;
    if (policy.builtin or policy.conversion or policy.restricted) return false;
    const local = if (std.mem.lastIndexOf(u8, function.name, "::")) |colon| function.name[colon + 2 ..] else function.name;
    if (std.mem.eql(u8, local, "main") or std.mem.startsWith(u8, local, "test_") or std.mem.startsWith(u8, local, "bench_")) return false;
    if (std.mem.startsWith(u8, function.name, "lambda@") or std.mem.startsWith(u8, function.name, "@") or std.mem.startsWith(u8, function.name, "<")) return false;
    return true;
}

/// Whether parameter `parameter` is declared with no default value and no `from` clause names it. The checked program
/// keeps the `from` clause (`return_origin`) and the parameter's name span; the default is read from the source text after
/// the name, up to the `,` or `)` that ends the parameter, so nothing of the merged syntax is read (`lazy_readers.zig`).
pub fn plainDeclaration(src: source.Source, function: typed.Function, parameter: usize) bool {
    const local = function.scope.locals[parameter];
    if (local.origin != .parameter or !std.mem.eql(u8, src.text(local.declaration), local.name)) return false;
    var depth: usize = 0;
    for (src.bytes[local.declaration.end..]) |byte| switch (byte) {
        '(', '[', '{' => depth += 1,
        ')', ']', '}' => {
            if (depth == 0) break;
            depth -= 1;
        },
        ',' => if (depth == 0) break,
        '=' => if (depth == 0) return false,
        else => {},
    };
    return switch (function.signature.return_origin) {
        .fresh => true,
        .params => |positions| std.mem.indexOfScalar(u16, positions, @intCast(parameter)) == null,
        .unknown => false,
    };
}

/// What one body does with a function: nothing, calls it with a new value or a markable name at the judged parameter each
/// time, or withholds the repair (a call that passes anything else there, or the function named as a value).
const Use = enum { none, calls, withholds };

/// Whether the function at `index` calls itself or names itself as a value: its own calls would need the parameter too.
pub fn recursive(memory: std.mem.Allocator, program: typed.Program, function: typed.Function, index: usize) std.mem.Allocator.Error!bool {
    const found = try use(memory, program, function, index, null, null);
    return found != .none;
}

/// How `caller`'s body uses `callee`: each call's argument at `position` must be a new value (`fresh`) or, when `marks` is
/// given, the bare name of an owned local or an `own` parameter (`named`), whose start is appended to `marks`; with no
/// position, any call or value use withholds.
fn use(memory: std.mem.Allocator, program: typed.Program, caller: typed.Function, callee: usize, position: ?usize, marks: ?*std.ArrayList(u32)) std.mem.Allocator.Error!Use {
    if (!caller.scope.body_complete) return .none;
    var found: Use = .none;
    var body = try walk.Walker.init(memory, program, caller.scope.body);
    defer body.deinit();
    while (try body.next()) |item| {
        const id = switch (item) {
            .expression => |value| value,
            .statement => continue,
        };
        switch (program.nodes[@backingInt(id)].data) {
            .function_value => |named| if (@backingInt(named) == callee) return .withholds,
            .call => |call| if (@backingInt(call.function) == callee) {
                const at = position orelse return .withholds;
                if (at >= call.arguments.len) return .withholds;
                const argument: Argument = .{ .memory = memory, .program = program, .caller = caller };
                if (!try argument.accepted(call.arguments[at], marks)) return .withholds;
                found = .calls;
            },
            else => {},
        }
    }
    return found;
}

/// The places in `caller` where the repair of parameter `position` of the function at `callee` writes `own `: the start of
/// each argument there that is the bare name of an owned local or an `own` parameter (the ownership check judges whether it
/// is the name's last use). Null when the caller withholds the repair: a call passes something else there (a place, a loop
/// element, a pattern binding, a plain parameter of the caller), or it names the function as a value.
pub fn callerMarks(memory: std.mem.Allocator, program: typed.Program, caller: typed.Function, callee: usize, position: usize) std.mem.Allocator.Error!?[]const u32 {
    var marks: std.ArrayList(u32) = .empty;
    const found = try use(memory, program, caller, callee, position, &marks);
    if (found == .withholds) return null;
    return marks.items;
}

/// Whether the callers in a program whose every body was checked accept the repair of parameter `position` of the function
/// at `callee`, and where it writes `own ` in them (`callerMarks`, sorted); null when it is withheld: nothing calls it, a
/// call passes something else there, or a node names it as a value. A check whose bodies a summary stood in for asks each
/// caller separately (`callerMarks`) and its stood-in callers' stored answers.
pub fn callersAccept(memory: std.mem.Allocator, program: typed.Program, callee: usize, position: usize) std.mem.Allocator.Error!?[]const u32 {
    const accepted = try acceptedByCallers(memory, program, &.{.{ .callee = callee, .position = position }});
    return accepted[0];
}

/// One repair the callers judge: the function's position and the parameter's.
pub const Target = struct { callee: usize, position: usize };

/// `callersAccept` for several targets in one walk of the program: one answer per target, in order.
pub fn acceptedByCallers(memory: std.mem.Allocator, program: typed.Program, targets: []const Target) std.mem.Allocator.Error![]const ?[]const u32 {
    const called = try memory.alloc(bool, targets.len);
    @memset(called, false);
    const withheld = try memory.alloc(bool, targets.len);
    @memset(withheld, false);
    const marks = try memory.alloc(std.ArrayList(u32), targets.len);
    @memset(marks, .empty);
    var of_callee: std.AutoHashMapUnmanaged(usize, std.ArrayList(usize)) = .empty;
    for (targets, 0..) |target, index| {
        const entry = try of_callee.getOrPut(memory, target.callee);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.append(memory, index);
    }
    for (program.nodes) |node| switch (node.data) {
        .function_value => |named| if (of_callee.get(@backingInt(named))) |list| for (list.items) |index| {
            withheld[index] = true;
        },
        else => {},
    };
    for (program.functions, 0..) |caller, caller_index| {
        if (!caller.scope.body_complete) continue;
        var body = try walk.Walker.init(memory, program, caller.scope.body);
        defer body.deinit();
        while (try body.next()) |item| {
            const id = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            const call = switch (program.nodes[@backingInt(id)].data) {
                .call => |value| value,
                else => continue,
            };
            const list = of_callee.get(@backingInt(call.function)) orelse continue;
            if (caller_index == @backingInt(call.function)) continue;
            for (list.items) |index| {
                const at = targets[index].position;
                const argument: Argument = .{ .memory = memory, .program = program, .caller = caller };
                if (at >= call.arguments.len or !try argument.accepted(call.arguments[at], &marks[index])) withheld[index] = true;
                called[index] = true;
            }
        }
    }
    const accepted = try memory.alloc(?[]const u32, targets.len);
    for (accepted, called, withheld, marks) |*slot, any, refused, *list| slot.* = if (any and !refused) try sortedMarks(memory, list.items) else null;
    return accepted;
}

/// `marks` in ascending order with each place once (the instances of a generic caller share a call's place).
pub fn sortedMarks(memory: std.mem.Allocator, marks: []const u32) std.mem.Allocator.Error![]const u32 {
    const sorted = try memory.dupe(u32, marks);
    std.mem.sort(u32, sorted, {}, std.sort.asc(u32));
    var kept: usize = 0;
    for (sorted) |mark| {
        if (kept > 0 and sorted[kept - 1] == mark) continue;
        sorted[kept] = mark;
        kept += 1;
    }
    return sorted[0..kept];
}

/// The repair `fix` with `own ` written at each of `marks` (the callers' arguments, `callerMarks`), after its own edits.
pub fn withMarks(memory: std.mem.Allocator, fix: diagnostic.Fix, marks: []const u32) std.mem.Allocator.Error!diagnostic.Fix {
    const places = try sortedMarks(memory, marks);
    if (places.len == 0) return fix;
    const more = try memory.alloc(diagnostic.Edit, fix.more.len + places.len);
    @memcpy(more[0..fix.more.len], fix.more);
    for (more[fix.more.len..], places) |*edit, at| edit.* = .{ .span = .{ .start = at, .end = at }, .text = "own " };
    return .{ .edit = fix.edit, .more = more };
}

/// The caller whose argument `fresh` judges, and the program it is in.
const Argument = struct {
    memory: std.mem.Allocator,
    program: typed.Program,
    caller: typed.Function,

    /// Whether one argument is one the repair accepts: a new value (`fresh`), or with `marks` given the bare name of an owned
    /// local or an `own` parameter (`named`), whose start is appended to `marks` for the `own ` the repair writes there.
    fn accepted(self: Argument, id: typed.NodeId, marks: ?*std.ArrayList(u32)) std.mem.Allocator.Error!bool {
        if (try self.fresh(id, 0)) return true;
        const list = marks orelse return false;
        const start = try self.named(id, 0) orelse return false;
        try list.append(self.memory, start);
        return true;
    }

    /// The start of an argument that is the bare name of a local the caller owns: a declared local (not a loop element, a
    /// pattern binding or a view) or an `own` parameter, written as its name with no marker, also through the temporary
    /// the lowering stages it in. Null for anything else; a plain parameter of the caller is the caller's borrow.
    fn named(self: Argument, id: typed.NodeId, depth: usize) std.mem.Allocator.Error!?u32 {
        if (depth > 8) return null;
        const node = self.program.nodes[@backingInt(id)];
        if (node.own) return null;
        const slot = switch (node.data) {
            .local => |value| @as(usize, @backingInt(value)),
            else => return null,
        };
        const locals = self.caller.scope.locals;
        if (slot >= locals.len) return null;
        const local = locals[slot];
        const parameter = slot < self.caller.signature.parameter_count;
        if (!local.written()) {
            if (parameter) return null;
            const value = try needless_copy.soleInitializer(self.memory, self.program, self.caller, slot) orelse return null;
            return self.named(value, depth + 1);
        }
        if (local.ownership.view or node.span.end - node.span.start != local.name.len) return null;
        if (parameter) {
            const own = slot < self.caller.scope.own_parameters.len and self.caller.scope.own_parameters[slot];
            return if (own) @intCast(node.span.start) else null;
        }
        return if (local.origin == .local) @intCast(node.span.start) else null;
    }

    /// Whether one argument is a new value the callee may keep: a literal (a list literal too), an f-string, a call's
    /// result, a constructor, a concatenation or a `copy(...)`, through the temporary the lowering stages it in (a block
    /// around it, or a compiler temporary that one store initializes, as the arguments of a call that holds other calls
    /// are). A name the program wrote, a field, an element, or a value marked `own` is not.
    fn fresh(self: Argument, id: typed.NodeId, depth: usize) std.mem.Allocator.Error!bool {
        if (depth > 8) return false;
        const program = self.program;
        const node = program.nodes[@backingInt(id)];
        if (node.own) return false;
        return switch (node.data) {
            .array, .format, .record, .variant, .call => true,
            .binary => |binary| binary.op == .add,
            .buffer_operation => |operation| operation.kind == .copy and operation.arguments.len == 0,
            .cast, .wrap => |inner| self.fresh(inner, depth + 1),
            .local => |slot| staged: {
                const at = @backingInt(slot);
                if (at < self.caller.signature.parameter_count or at >= self.caller.scope.locals.len) break :staged false;
                if (self.caller.scope.locals[at].written()) break :staged false;
                const value = try needless_copy.soleInitializer(self.memory, program, self.caller, at) orelse break :staged false;
                break :staged try self.fresh(value, depth + 1);
            },
            .block_value => |block| staged: {
                const statements = switch (program.statements[@backingInt(block.body)].data) {
                    .block => |items| items,
                    else => break :staged false,
                };
                if (statements.len == 0 or node.view) break :staged false;
                const store = switch (program.statements[@backingInt(statements[0])].data) {
                    .initialize => |value| value,
                    else => break :staged false,
                };
                const slot = switch (program.nodes[@backingInt(block.value)].data) {
                    .local => |value| value,
                    else => break :staged false,
                };
                if (@backingInt(slot) != @backingInt(store.slot)) break :staged false;
                // A list literal: a new buffer the statements after it fill.
                if (program.nodes[@backingInt(store.value)].data == .acquire_buffer) break :staged true;
                break :staged statements.len == 1 and try self.fresh(store.value, depth + 1);
            },
            else => false,
        };
    }
};

/// One parameter a function copies into storage, and the `copy(...)` that does it.
pub const Copy = struct {
    /// Position of the parameter, which is also its local slot in `function.scope.locals`.
    parameter: usize,
    /// The span of the `copy(...)` expression.
    span: source.Span,
};

/// Whether a function body that copies parameter `parameter` into storage should be told to declare it `own`:
/// the parameter is plain (neither `mut` nor `own`), and its type holds managed storage (the judgement the
/// `own` marker check makes, `own_parameters.managed`).
pub fn ownable(program: typed.Program, function: typed.Function, parameter: usize) bool {
    if (parameter >= function.signature.parameter_count or parameter >= function.scope.locals.len) return false;
    if (parameter < function.scope.own_parameters.len and function.scope.own_parameters[parameter]) return false;
    if (std.mem.indexOfScalar(u16, function.signature.mutates, @intCast(parameter)) != null) return false;
    return own_parameters.managed(program.records, function.scope.locals[parameter].ty);
}

/// What one function's scan reads and appends to, so each step takes the one value.
const Scan = struct {
    memory: std.mem.Allocator,
    program: typed.Program,
    function: typed.Function,
    /// What every local of the function was initialized with, to follow a staged copy back to its parameter.
    initializers: std.AutoHashMapUnmanaged(u32, typed.NodeId) = .empty,
    found: std.ArrayList(Copy) = .empty,
};

/// Every parameter of `function` that a statement of its body copies into storage and that `ownable` accepts,
/// in statement order; a statement names a parameter once, at the copy's own place. The slice is owned by
/// `memory`, which should be an arena.
pub fn storedCopies(memory: std.mem.Allocator, program: typed.Program, function: typed.Function) std.mem.Allocator.Error![]const Copy {
    // A copy of a record or another non-collection aggregate stages the value in
    // fresh locals first, so remember what every local was initialized with and
    // follow the chain to the parameter.
    var scan: Scan = .{ .memory = memory, .program = program, .function = function };
    defer scan.initializers.deinit(memory);
    var first = try walk.Walker.init(memory, program, function.scope.body);
    defer first.deinit();
    while (try first.next()) |item| {
        const id = switch (item) {
            .statement => |value| value,
            else => continue,
        };
        const store = switch (program.statements[@backingInt(id)].data) {
            .initialize => |value| value,
            else => continue,
        };
        try scan.initializers.put(memory, @intCast(@backingInt(store.slot)), store.value);
    }
    var second = try walk.Walker.init(memory, program, function.scope.body);
    defer second.deinit();
    while (try second.next()) |item| {
        const id = switch (item) {
            .statement => |value| value,
            else => continue,
        };
        try collectStatement(&scan, id);
    }
    return scan.found.toOwnedSlice(memory);
}

/// Collect the copies one statement stores: an element write, a record field, or a list write.
fn collectStatement(scan: *Scan, id: typed.StatementId) std.mem.Allocator.Error!void {
    switch (scan.program.statements[@backingInt(id)].data) {
        .assign => |store| try collectStored(scan, store.value),
        .initialize => |store| try collectStored(scan, store.value),
        .discard => |value| try collectStored(scan, value),
        .ret => |value| try collectStored(scan, value),
        else => {},
    }
}

/// Judge one stored expression: a record's field or a writing collection
/// operation. A plain local initialized with a copy already answered for
/// itself, so only a store into another value counts here. Every parameter the
/// statement copies is named once, at the copy's own place.
fn collectStored(scan: *Scan, value: typed.NodeId) std.mem.Allocator.Error!void {
    const first = scan.found.items.len;
    switch (scan.program.nodes[@backingInt(unwrapped(scan.program, value))].data) {
        .record => |fields| for (fields) |field| try collectCopied(scan, field.value, first),
        .update => |update| for (update.fields) |field| try collectCopied(scan, field.value, first),
        .buffer_operation => |operation| {
            if (operation.kind != .append and operation.kind != .insert and operation.kind != .write) return;
            for (operation.arguments) |argument| try collectCopied(scan, argument, first);
        },
        else => {},
    }
}

/// Collect one stored value that is a copy of a parameter the statement (whose copies start at `first`) has not named yet.
fn collectCopied(scan: *Scan, value: typed.NodeId, first: usize) std.mem.Allocator.Error!void {
    const copied = copiedParameter(scan, value, 0) orelse return;
    if (!ownable(scan.program, scan.function, copied.parameter)) return;
    for (scan.found.items[first..]) |seen| if (seen.parameter == copied.parameter) return;
    try scan.found.append(scan.memory, copied);
}

/// Whether one stored node is `copy(parameter)`, following the staging locals a
/// copy of a record or an aggregate creates to the parameter it came from. The
/// chain must contain the copy: a plain parameter read (a dictionary key, an
/// index) is not a copy and never counts.
fn copiedParameter(scan: *const Scan, id: typed.NodeId, depth: usize) ?Copy {
    if (depth > 6) return null;
    const node = scan.program.nodes[@backingInt(unwrapped(scan.program, id))];
    return switch (node.data) {
        .buffer_operation => |operation| copy: {
            if (operation.kind != .copy or operation.arguments.len != 0) break :copy null;
            const parameter = localParameter(scan, operation.owner, depth + 1) orelse break :copy null;
            break :copy .{ .parameter = parameter, .span = node.span };
        },
        // A local that was initialized from the copy made for the store.
        .local => |slot| local: {
            const init = scan.initializers.get(@intCast(@backingInt(slot))) orelse break :local null;
            break :local copiedParameter(scan, init, depth + 1);
        },
        else => null,
    };
}

/// Resolve one copy owner local to the parameter it copies.
fn localParameter(scan: *const Scan, slot: typed.LocalId, depth: usize) ?usize {
    if (@backingInt(slot) < scan.function.signature.parameter_count) return @backingInt(slot);
    if (depth > 6) return null;
    const init = scan.initializers.get(@intCast(@backingInt(slot))) orelse return null;
    const node = scan.program.nodes[@backingInt(unwrapped(scan.program, init))];
    return switch (node.data) {
        .local => |inner| localParameter(scan, inner, depth + 1),
        .buffer_operation => |operation| if (operation.kind == .copy and operation.arguments.len == 0)
            localParameter(scan, operation.owner, depth + 1)
        else
            null,
        else => null,
    };
}

/// Follow the block a staged value wraps, to the value the statement stores.
fn unwrapped(program: typed.Program, id: typed.NodeId) typed.NodeId {
    var current = id;
    while (true) {
        const node = program.nodes[@backingInt(current)];
        current = switch (node.data) {
            .block_value => |block| block.value,
            else => return current,
        };
    }
}
