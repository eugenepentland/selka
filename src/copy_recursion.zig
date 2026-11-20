//! `W_COPY_IN_RECURSION`: a `copy(...)` of a function's context passed into its own recursive call (O4).
//!
//! A recursive walk that builds its callee's context as `walk(Scope(block=copy(sb.block), parent=Some(copy(scope))))`
//! copies the caller's whole context at every level: the parent scope holds the parent block, so a tree of depth d is
//! copied d times over. A record built from borrows borrows (1A), and it may hold `Some(p)` of a read-only record
//! parameter (O4), so the same call written `walk(Scope(block=sb.block, parent=Some(scope)))` copies nothing.
//!
//! The pass reports a copy that is a field value of a record constructor (or the payload of `Some` in one) passed to a
//! direct recursive call, when the copied value is a parameter, a loop variable over a place of one, or a place of
//! either. Its fix deletes every copy of that constructor at once, and only in the exact shape the ownership checker
//! accepts as a borrowed record: the constructor is the argument of a read-only parameter, its record is plain, and every
//! managed field is a literal, `None`, a place of a read-only parameter or of a loop variable over one (a bare read only of
//! a record parameter or a loop variable, since a plain text, bytes or list parameter is a view), or `Some` of a read-only
//! record parameter, copied or not. Any other shape is reported with no fix.
//!
//! RB1 widened the shapes a borrowed record takes: a bare read-only dictionary, set, text, bytes or list parameter (the last
//! three as a frame block), and `Some(place)` of a place with an unboxed payload. The same constructor passed to any other
//! direct call, at a read-only parameter, is `W_NEEDLESS_COPY` with the same fix when its shape is certain, and nothing
//! otherwise: a non-recursive call copies once per call, so an uncertain shape is not worth a warning.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const origins = @import("origins.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");
const own_parameters = @import("own_parameters.zig");

/// The warning code `selka fix` applies where the fix is certain.
pub const code = "W_COPY_IN_RECURSION";

const depth_limit = 32;

/// Report the copies of their context that the checked functions pass into their own recursive calls.
pub fn warn(memory: std.mem.Allocator, program: typed.Program, src: source.Source, stubs: []const ?origins.Fact, sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    for (program.functions, 0..) |function, index| {
        if (function.policy.host != null or origins.standIn(stubs, index) != null) continue;
        if (!function.scope.body_complete or function.type_arguments.len != 0) continue;
        var pass: Pass = .{ .memory = memory, .program = program, .src = src, .function = function, .sink = sink };
        var body = try walk.Walker.init(memory, program, function.scope.body);
        defer body.deinit();
        while (try body.next()) |item| {
            const id = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            const node = program.nodes[@backingInt(id)];
            if (node.data != .call or @backingInt(node.data.call.function) >= program.functions.len) continue;
            const callee = program.functions[@backingInt(node.data.call.function)];
            pass.recursive = @backingInt(node.data.call.function) == index;
            if (!pass.recursive and (callee.policy.host != null or callee.policy.c_abi)) continue;
            for (node.data.call.arguments, 0..) |argument, position| try pass.argument(argument, callee, position);
        }
    }
}

const Pass = struct {
    memory: std.mem.Allocator,
    program: typed.Program,
    src: source.Source,
    function: typed.Function,
    sink: *diagnostic.Sink,
    /// The call being read calls this function (`W_COPY_IN_RECURSION`); else any other direct call (`W_NEEDLESS_COPY`, RB1).
    recursive: bool = true,

    /// One argument of a direct call: a record constructor whose fields copy places.
    fn argument(self: *Pass, id: typed.NodeId, callee: typed.Function, position: usize) std.mem.Allocator.Error!void {
        const node = self.program.nodes[@backingInt(id)];
        if (node.data != .record or node.own) return;
        var copies: std.ArrayList(typed.NodeId) = .empty;
        defer copies.deinit(self.memory);
        var certain = readOnlyParameterOf(callee, position) and self.plainRecord(node.ty);
        for (node.data.record) |field| {
            const value = self.program.nodes[@backingInt(field.value)];
            if (!own_parameters.managed(self.program.records, value.ty)) continue;
            if (copied(self.program, field.value)) |copy| {
                const place = self.operand(copy);
                if (self.root(place) == null) return;
                try copies.append(self.memory, copy);
                certain = certain and self.borrowable(place);
                continue;
            }
            if (self.someOf(field.value)) |payload| {
                const boxed = self.boxedSome(field.value);
                if (copied(self.program, payload)) |copy| {
                    const place = self.operand(copy);
                    if (self.root(place) == null) return;
                    try copies.append(self.memory, copy);
                    certain = certain and self.lendable(place, boxed);
                    continue;
                }
                certain = certain and self.lendable(.{ .node = payload }, boxed);
                continue;
            }
            certain = certain and (staticValue(self.program, field.value) or self.borrowable(.{ .node = field.value }));
        }
        if (copies.items.len == 0) return;
        if (!self.recursive) return self.needless(copies.items, certain);
        const first = self.program.nodes[@backingInt(copies.items[0])];
        const message = try std.fmt.allocPrint(self.memory, "`{s}` passes a copy of its own context into its recursive call, so every level copies the caller's; " ++
            "pass the places themselves: a record built from borrows borrows, and it may hold `Some(p)` of a read-only record parameter", .{self.function.name});
        const edits = try self.memory.alloc(diagnostic.Edit, copies.items.len);
        for (copies.items, edits) |copy, *edit| {
            const span = self.program.nodes[@backingInt(copy)].span;
            const receiver = receiverText(self.src, span) orelse {
                certain = false;
                break;
            };
            edit.* = .{ .span = span, .text = receiver };
        }
        if (certain) certain = !self.fixedAlready(edits);
        const item: diagnostic.Diagnostic = .{ .severity = .warning, .code = code, .span = first.span, .message = message };
        if (!certain) return self.sink.items.append(self.sink.allocator, item);
        try self.sink.appendFix(item, edits[0]);
        self.sink.items.items[self.sink.items.items.len - 1].provenance.fix.?.more = edits[1..];
    }

    /// `W_NEEDLESS_COPY` (RB1): the copies of one record constructor passed to a direct call, reported only with their fix,
    /// when the record then borrows; the fix deletes them together.
    fn needless(self: *Pass, copies: []const typed.NodeId, certain_shape: bool) std.mem.Allocator.Error!void {
        if (!certain_shape) return;
        const edits = try self.memory.alloc(diagnostic.Edit, copies.len);
        for (copies, edits) |copy, *edit| {
            const span = self.program.nodes[@backingInt(copy)].span;
            edit.* = .{ .span = span, .text = receiverText(self.src, span) orelse return };
        }
        if (self.fixedAlready(edits)) return;
        const message = "these copies are needless: a record whose fields all borrow places or read-only parameters is a borrowed value, so pass the places themselves";
        const item: diagnostic.Diagnostic = .{ .severity = .warning, .code = needless_code, .span = self.program.nodes[@backingInt(copies[0])].span, .message = message };
        try self.sink.appendFix(item, edits[0]);
        self.sink.items.items[self.sink.items.items.len - 1].provenance.fix.?.more = edits[1..];
    }

    /// The place a copy reads: the initializer of the temporary it copies, or the named local it copies.
    fn operand(self: *const Pass, copy: typed.NodeId) Place {
        const owner = @backingInt(self.program.nodes[@backingInt(copy)].data.buffer_operation.owner);
        if (owner < self.function.scope.locals.len and temporary(self.function.scope.locals[owner])) {
            if (self.sole(owner)) |initializer| return .{ .node = initializer };
        }
        return .{ .slot = owner };
    }

    /// Whether another warning already repairs one of these spans (a `W_NEEDLESS_COPY` of the same copy): two fixes of one
    /// copy would collide in `selka fix`.
    fn fixedAlready(self: *Pass, edits: []const diagnostic.Edit) bool {
        for (self.sink.items.items) |item| {
            const fix = item.provenance.fix orelse continue;
            for (0..fix.count()) |k| for (edits) |edit| {
                const other = fix.at(k).span;
                if (other.start < edit.span.end and edit.span.start < other.end) return true;
            };
        }
        return false;
    }

    fn readOnlySlot(self: *const Pass, slot: usize) bool {
        const own = slot < self.function.scope.own_parameters.len and self.function.scope.own_parameters[slot];
        return !own and !self.function.scope.locals[slot].mutable;
    }

    /// Whether the `Some` case of option constructor `id` boxes its payload (a recursive field).
    fn boxedSome(self: *const Pass, id: typed.NodeId) bool {
        const node = self.program.nodes[@backingInt(id)];
        const variants = self.program.records[node.ty.recordIndex()].shape.variants orelse return true;
        if (node.data.variant.tag >= variants.cases.len) return true;
        return variants.cases[node.data.variant.tag].boxed;
    }

    /// The payload of `Some(value)` of an option, or null.
    fn someOf(self: *const Pass, id: typed.NodeId) ?typed.NodeId {
        const node = self.program.nodes[@backingInt(id)];
        if (node.data != .variant or node.own) return null;
        if (!isOption(self.program, node.ty)) return null;
        return node.data.variant.value;
    }

    /// The parameter a place starts at, through its fields, elements and loop variables, or null when it starts anywhere
    /// else.
    fn root(self: *const Pass, place: Place) ?usize {
        var current = place;
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            const slot = switch (current) {
                .slot => |slot| slot,
                .node => |id| switch (self.program.nodes[@backingInt(id)].data) {
                    .field => |field| {
                        current = .{ .node = field.base };
                        continue;
                    },
                    .index => |index| {
                        current = .{ .node = index.base };
                        continue;
                    },
                    .block_value => |block| {
                        current = .{ .node = block.value };
                        continue;
                    },
                    .buffer_operation => |operation| if (operation.kind == .read) @backingInt(operation.owner) else return null,
                    .local => |local| @backingInt(local),
                    else => return null,
                },
            };
            if (slot >= self.function.scope.locals.len) return null;
            if (slot < self.function.signature.parameter_count) return slot;
            const local = self.function.scope.locals[slot];
            if (!temporary(local) and local.origin != .iteration) return null;
            current = .{ .node = self.sole(slot) orelse return null };
        }
        return null;
    }

    /// Whether a place may be read in place by a borrowed record: rooted at a read-only parameter, and a bare read only of a
    /// record parameter or a loop variable (a plain text, bytes or list parameter is a view a record cannot hold).
    fn borrowable(self: *const Pass, place: Place) bool {
        const start = self.root(place) orelse return false;
        if (!self.readOnlySlot(start)) return false;
        const slot = switch (place) {
            .slot => |slot| slot,
            .node => |id| blk: {
                const node = self.program.nodes[@backingInt(id)];
                if (node.own) return false;
                if (node.data != .local) return true;
                break :blk @backingInt(node.data.local);
            },
        };
        if (slot < self.function.signature.parameter_count) return self.parameterSource(slot);
        return self.function.scope.locals[slot].origin == .iteration;
    }

    /// Whether a read-only parameter, read bare, is a borrowed record source: a record, a dictionary or a set (the caller's
    /// storage), or a text, bytes or list (a frame block, RB1) that is not declared written or move-only.
    fn parameterSource(self: *const Pass, slot: usize) bool {
        const local = self.function.scope.locals[slot];
        if (self.plainRecord(local.ty)) return true;
        if (local.ownership.view or !local.ty.isAggregate() or local.ty.recordIndex() >= self.program.records.len) return false;
        if (std.mem.indexOfScalar(u16, self.function.signature.declared_mutates, @intCast(slot)) != null) return false;
        if (self.function.policy.c_abi) return false;
        const record = self.program.records[local.ty.recordIndex()];
        if (!record.isCollection() or record.collection.box) return false;
        return true;
    }

    /// Whether a place is what `Some(...)` of a borrowed record may hold: a bare read of a read-only record parameter, or
    /// (RB1) a projection of a place rooted at a read-only parameter, when the option's payload is not boxed.
    fn lendable(self: *const Pass, place: Place, boxed: bool) bool {
        const slot = switch (place) {
            .slot => |slot| slot,
            .node => |id| blk: {
                const node = self.program.nodes[@backingInt(id)];
                if (node.own) return false;
                if (node.data != .local) return !boxed and node.data != .record and node.data != .variant and self.borrowable(place);
                break :blk @backingInt(node.data.local);
            },
        };
        if (slot >= self.function.signature.parameter_count or !self.readOnlySlot(slot)) return false;
        return self.plainRecord(self.function.scope.locals[slot].ty);
    }

    /// The one initializer of a temporary or loop variable, or null.
    fn sole(self: *const Pass, slot: usize) ?typed.NodeId {
        return @import("needless_copy.zig").soleInitializer(self.memory, self.program, self.function, slot) catch null;
    }

    /// A plain record a borrowed record may be: no collection, managed or builtin form, no boxed field, not a tuple and
    /// not the payload of a fielded case.
    fn plainRecord(self: *const Pass, ty: typed.Type) bool {
        if (!ty.isAggregate() or ty.recordIndex() >= self.program.records.len) return false;
        const record = self.program.records[ty.recordIndex()];
        if (!record.isRecord() or record.isCollection()) return false;
        if (record.managed or record.collection.box) return false;
        if (record.shape.builtin != .none or record.contract.callback != null or record.shape.tuple) return false;
        for (record.fields) |field| if (field.boxed) return false;
        for (self.program.records) |other| if (other.shape.variants) |variants| for (variants.cases) |case| {
            const payload = case.payload orelse continue;
            if (case.fielded and payload.isAggregate() and payload.recordIndex() == ty.recordIndex()) return false;
        };
        return true;
    }
};

/// The code of the needless copies RB1 finds in a record passed to a non-recursive call (`needless_copy.code`).
const needless_code = @import("needless_copy.zig").code;

/// Whether parameter `position` of `callee` only reads its argument (not `own`, not `mut`).
fn readOnlyParameterOf(callee: typed.Function, position: usize) bool {
    if (position >= callee.signature.parameter_count) return false;
    const own = position < callee.scope.own_parameters.len and callee.scope.own_parameters[position];
    return !own and !callee.scope.locals[position].mutable;
}

fn temporary(local: typed.Local) bool {
    return local.usage.temporary or std.mem.startsWith(u8, local.name, "<");
}

/// Whether `id` is a source `copy(...)` of a managed value.
fn isCopy(program: typed.Program, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    if (node.view) return false;
    return switch (node.data) {
        .buffer_operation => |operation| operation.kind == .copy and operation.arguments.len == 0,
        else => false,
    };
}

/// A place a copy reads: an expression, or a named local the copy reads whole.
const Place = union(enum) { node: typed.NodeId, slot: usize };

/// The `copy(...)` a field value is, through the blocks that stage its operand, or null.
fn copied(program: typed.Program, id: typed.NodeId) ?typed.NodeId {
    var current = id;
    var depth: usize = 0;
    while (depth < depth_limit) : (depth += 1) {
        if (isCopy(program, current)) return current;
        switch (program.nodes[@backingInt(current)].data) {
            .block_value => |block| current = block.value,
            else => return null,
        }
    }
    return null;
}

fn isOption(program: typed.Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const name = program.records[ty.recordIndex()].name;
    return std.mem.startsWith(u8, name, "Option<") or std.mem.startsWith(u8, name, "std_result::Option<");
}

/// Whether a field value owns nothing a borrowed record could not hold beside its borrows: a text or bytes literal or `None`.
fn staticValue(program: typed.Program, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    return switch (node.data) {
        .array => |items| for (items) |item| {
            if (program.nodes[@backingInt(item)].data != .integer) break false;
        } else true,
        .variant => |variant| variant.value == null and isOption(program, node.ty),
        else => false,
    };
}

/// The operand text of `copy(operand)`, or null when the span does not spell exactly that.
fn receiverText(src: source.Source, span: source.Span) ?[]const u8 {
    const text = std.mem.trim(u8, src.text(span), " \t\r\n");
    if (!std.mem.startsWith(u8, text, "copy")) return null;
    var index: usize = 4;
    while (index < text.len and (text[index] == ' ' or text[index] == '\t')) index += 1;
    if (index >= text.len or text[index] != '(' or text[text.len - 1] != ')') return null;
    const receiver = std.mem.trim(u8, text[index + 1 .. text.len - 1], " \t\r\n");
    if (receiver.len == 0 or std.mem.indexOfScalar(u8, receiver, ',') != null) return null;
    return receiver;
}
