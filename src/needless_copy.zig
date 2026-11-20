//! `W_NEEDLESS_COPY`: a `.copy()` whose copy-free form provably checks.
//!
//! P1 makes a certain finding a checker warning with its `fix`, and `selka fix`
//! applies that fix. This pass finds the copies that carry no value, in two
//! exact shapes:
//!
//! - case (i): the copy is an argument to a read-only parameter, an f-string
//!   hole or a printed value, so the callee only reads it and the copy-free form
//!   passes the borrow;
//! - case (ii): the copied value is an owned local and the copy is its last use,
//!   so the copy-free form moves the value and hands back the same bytes.
//!
//! Case (iii): a `const` bound to a copy of a parameter's place, or of a field or
//! element of a parameter or local, is only read while its source does not change,
//! so the binding borrows the source (R1) and the copy goes.
//!
//! Case (v): a copy of an owned local or an `own` parameter at its last use, where
//! the value is taken over (an append, a dictionary key or set member, a case
//! payload, a constructor field, a list element, an `own` argument, an assignment,
//! a return), becomes `own value` (a bare `value` when returned).
//!
//! Case (vi): a copy that is the key of a dictionary store `d[copy(k)] = v`, the member of `sets.add(mut s, copy(k))`, or
//! the key of `dicts.add(mut d, copy(k), delta)` or `dicts.append_to(mut d, copy(k), item)`.
//! The store copies a key written as a place only when it is new, so `d[k] = v` and `sets.include(mut s, k)` give the
//! same entries without the copy an existing key throws away, and `dicts.add` and `dicts.append_to` borrow their key
//! the same way. Case (v) comes first for a store: a key that is an owned local at its last use is moved with `own k`,
//! which copies nothing at all (the two `dicts` functions take no `own` key, so they only lose the copy).
//!
//! Case (vii): a copy of a value that is already new (a call that returns a fresh result, a module constant, a
//! concatenation) duplicates a temporary; the copy-free form hands the temporary over in any position.
//!
//! Case (viii): a copy of a borrowed value (a call's declared borrowed result, an option's default, an element read) in a
//! position that only reads it (a read-only argument of a call or of a function value, a printed value, an f-string
//! hole, a `const`) is followed to the one local the value borrows, and judged as a copy of that local's place is. A
//! `const` that copies a whole local the function owns borrows it the same way.
//!
//! A field of a local moves with the local: case (v) writes `own record.field` where nothing reads the record again.
//!
//! A return copy preserves the declared owning result contract. Removing it
//! would require a source-written `from` clause, so this pass leaves it intact.
//!
//! It fires only where the copy-free form provably checks, because a false
//! positive is a defect: the shape is exact (a source-spelled `.copy()` of a
//! plain local), a view is never moved or passed through, case (ii) refuses a
//! loop (the move would run again on the next iteration), a conditional (the
//! copied value would reach the binding on one path only) and any later use or
//! view of the source. The edit writes `own value` when it replaces a copy by a
//! move; a read-only replacement stays unmarked.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const display_name = @import("display_name.zig");
const origins = @import("origins.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");
const reads = @import("needless_copy_reads.zig");
const return_borrow = @import("return_borrow.zig");
const from_advice = @import("from_advice.zig");
const take_repair = @import("copy_take_repair.zig");
const provider_types = @import("provider_types.zig");
const owned_types = @import("owned_types.zig");
const copy_loop_edits = @import("copy_loop_edits.zig");

/// The warning code, and the lint rule that reads it (`L_NEEDLESS_COPY`).
pub const code = "W_NEEDLESS_COPY";
/// The hint code of a copy a move would replace where no repair is certain (`L_COPY_MOVE` reads it).
pub const move_code = "W_COPY_MOVE";
/// Deeper nesting than this is not lowered by hand, so the pass does not read it.
const depth_limit = 32;

/// A `W_COPY_MOVE` hint whose advice `check` judges against the callers in the program (F-8, F-27): the advice to
/// declare the result `from` a parameter (`result`), or to consume a list parameter with `for x in own` (`argument`).
pub const Judged = struct {
    /// Which advice the hint gives: a caller may keep the result, or the argument it passes.
    form: enum { result, argument },
    /// The parameter the advice names, a slice of the message.
    parameter: []const u8,
};

/// The advice of a hint `check` keeps only when no caller in the program needs the copy, or null for any other diagnostic.
/// The check judges these hints against every caller, whether its body was checked or stood in (`sema_summaries.CopyMoves`),
/// and `src/main.zig: copyMoveKept` judges them where no summary stands in.
pub fn judgedByCallers(diagnostic_code: []const u8, message: []const u8) ?Judged {
    if (!std.mem.eql(u8, diagnostic_code, move_code)) return null;
    const result_opening = "copies a place of `";
    const loop_opening = "is copied out of each element of `";
    const result = std.mem.indexOf(u8, message, result_opening);
    const loop = if (std.mem.indexOf(u8, message, "an `own` parameter") != null) std.mem.indexOf(u8, message, loop_opening) else null;
    const rest = if (result) |at| message[at + result_opening.len ..] else if (loop) |at| message[at + loop_opening.len ..] else return null;
    const end = std.mem.indexOfScalar(u8, rest, '`') orelse return null;
    return .{ .form = if (result != null) .result else .argument, .parameter = rest[0..end] };
}

/// What a copy's parent node makes of it: only the first four shapes read their
/// operand, and only the `initialize` shape is a store.
const Context = union(enum) {
    /// The copy is an argument of a declared function at `position`.
    call_argument: struct { function: typed.FunctionId, position: usize, call: typed.NodeId },
    /// The copy is an argument of a call through a function value, at `position` of the invoke node `call`.
    invoke_argument: struct { position: usize, call: typed.NodeId },
    /// The copy is a printed value read inside `span`.
    print_argument: source.Span,
    /// The copy is the text one stream write writes, inside `span`.
    stream_text: source.Span,
    /// The copy is an f-string hole read inside the format's `span`.
    format_hole: source.Span,
    /// The copy initializes a local binding.
    initialize: typed.StatementId,
    /// The copy is a value a constructor, a case payload, a container store or an assignment takes over (case v).
    moved,
    /// The copy is the key of the dictionary or set write `operation` (case vi).
    store_key: typed.NodeId,
    /// The copy is a returned value (case v).
    returned,
    /// Any other position: the pass never fires there.
    other,
};

/// The copy nodes of one program and what each one's parent makes of it.
const Contexts = struct {
    memory: std.mem.Allocator,
    map: std.AutoHashMapUnmanaged(typed.NodeId, Context) = .empty,

    /// Index every copy node by the parent position that consumes it. A function a summary stood in for is not walked for its
    /// initializers: its copies are replayed, never judged, so nothing asks for their contexts.
    fn init(memory: std.mem.Allocator, program: typed.Program, stubs: []const ?origins.Fact) std.mem.Allocator.Error!Contexts {
        var contexts: Contexts = .{ .memory = memory };
        errdefer contexts.map.deinit(memory);
        for (program.nodes, 0..) |node, index| try contexts.indexNode(program, node, @fromBackingInt(@intCast(index)));
        for (program.functions, 0..) |function, index| {
            if (origins.standIn(stubs, index) != null) continue;
            try contexts.indexFunction(program, function);
        }
        return contexts;
    }

    /// Record the copies one node consumes: a call's arguments, a printed value, a record's fields, a container write.
    fn indexNode(self: *Contexts, program: typed.Program, node: typed.Node, call_id: typed.NodeId) std.mem.Allocator.Error!void {
        switch (node.data) {
            .call => |call| for (call.arguments, 0..) |argument, position| {
                const value = inherited(program, argument);
                if (!isCopy(program, value)) continue;
                try self.put(value, .{ .call_argument = .{ .function = call.function, .position = position, .call = call_id } });
            },
            .invoke => |invoke| for (invoke.arguments, 0..) |argument, position| {
                const value = inherited(program, argument);
                if (!isCopy(program, value)) continue;
                try self.put(value, .{ .invoke_argument = .{ .position = position, .call = call_id } });
            },
            .print => |print| for (print.arguments) |argument| {
                const value = inherited(program, argument);
                if (!isCopy(program, value)) continue;
                try self.put(value, .{ .print_argument = node.span });
            },
            .stream_write => |write| {
                const value = inherited(program, write.text);
                if (isCopy(program, value)) try self.put(value, .{ .stream_text = node.span });
            },
            .format => |format| for (format.pieces) |piece| switch (piece) {
                .literal => {},
                .hole => |hole| {
                    const value = inherited(program, hole.value);
                    if (isCopy(program, value)) try self.put(value, .{ .format_hole = node.span });
                },
            },
            .variant => |variant| if (variant.value) |payload| {
                // `fail value` hands the failure over bare, as `return value` hands a result over.
                const failure = if (typed.resultShape(node.ty, program.records)) |shape| variant.tag == shape.error_tag else false;
                const value = inherited(program, payload);
                if (failure and isCopy(program, value)) try self.put(value, .returned) else try self.putMoved(program, payload);
            },
            .update => |update| for (update.fields) |field| try self.putMoved(program, field.value),
            .replace => |replace| try self.putMoved(program, replace.value),
            .record => |fields| for (fields) |field| try self.putMoved(program, field.value),
            .buffer_operation => |operation| switch (operation.kind) {
                .append => for (operation.arguments) |argument| try self.putMoved(program, argument),
                .write => try self.putStore(program, operation.arguments, call_id),
                .setdefault => try self.putStore(program, operation.arguments[0..1], call_id),
                else => {},
            },
            else => {},
        }
    }

    /// Record the copies one function's statements consume: a binding's initializer, an assignment, a return, and a field
    /// write that stages its value in a temporary (`<tmp> = copy(x)`, then `update(.., field = <tmp>)`).
    fn indexFunction(self: *Contexts, program: typed.Program, function: typed.Function) std.mem.Allocator.Error!void {
        var body = try walk.Walker.init(self.memory, program, function.scope.body);
        defer body.deinit();
        var staged: std.AutoHashMapUnmanaged(usize, typed.NodeId) = .empty;
        defer staged.deinit(self.memory);
        while (try body.next()) |item| switch (item) {
            .expression => |id| try self.takeStaged(program, program.nodes[@backingInt(id)], &staged),
            .statement => |statement| try self.indexStatement(program, function, statement, &staged),
        };
    }

    /// An update, or a list or dictionary write (`items[0] = copy(x)`), that reads a temporary a copy was staged in takes the copy
    /// over. The first operand of a write is the index or key, which only reads.
    fn takeStaged(self: *Contexts, program: typed.Program, node: typed.Node, staged: *const std.AutoHashMapUnmanaged(usize, typed.NodeId)) std.mem.Allocator.Error!void {
        switch (node.data) {
            .update => |update| for (update.fields) |field| try self.takeOne(program, field.value, staged),
            .buffer_operation => |operation| if (operation.kind == .write and operation.arguments.len > 1) {
                for (operation.arguments[1..]) |argument| try self.takeOne(program, argument, staged);
            },
            else => {},
        }
    }

    /// The copy staged in the temporary `value` reads, if any, is taken over by the node that reads it.
    fn takeOne(self: *Contexts, program: typed.Program, value: typed.NodeId, staged: *const std.AutoHashMapUnmanaged(usize, typed.NodeId)) std.mem.Allocator.Error!void {
        const read = switch (program.nodes[@backingInt(inherited(program, value))].data) {
            .local => |slot| @backingInt(slot),
            else => return,
        };
        if (staged.get(read)) |copied| try self.map.put(self.memory, copied, .moved);
    }

    /// Record the copy one statement consumes, and remember a copy staged in a lowering temporary.
    fn indexStatement(self: *Contexts, program: typed.Program, function: typed.Function, statement: typed.StatementId, staged: *std.AutoHashMapUnmanaged(usize, typed.NodeId)) std.mem.Allocator.Error!void {
        switch (program.statements[@backingInt(statement)].data) {
            .initialize => |store| {
                const value = inherited(program, store.value);
                if (!isCopy(program, value)) return;
                try self.put(value, .{ .initialize = statement });
                const slot = @backingInt(store.slot);
                if (slot < function.scope.locals.len and isTemporary(function.scope.locals[slot])) try staged.put(self.memory, slot, value);
            },
            // An assignment to a declared local takes its value over; one to a lowering temporary is part of a
            // larger expression (a field write), which `takeStaged` follows.
            .assign => |store| if (@backingInt(store.slot) < function.scope.locals.len and !isTemporary(function.scope.locals[@backingInt(store.slot)])) {
                try self.putMoved(program, store.value);
            },
            .ret => |value| {
                const copied = inherited(program, value);
                if (isCopy(program, copied)) try self.put(copied, .returned);
                try self.putWrapped(program, copied);
            },
            else => {},
        }
    }

    /// The `Ok` or `Some` a failing or optional function's `return` puts around its value is written nowhere: the typed tree
    /// spans it over the value or over the whole statement, where a written `Ok(...)` ends at its closing parenthesis. A copy
    /// that constructor wraps, as the value of a `return`, is a returned value as a bare one is, though the constructor named it
    /// first as a value it takes over. Any other constructor of a copy (a field, an assignment, an argument) keeps that context.
    fn putWrapped(self: *Contexts, program: typed.Program, wrapper: typed.NodeId) std.mem.Allocator.Error!void {
        const node = program.nodes[@backingInt(wrapper)];
        const payload = switch (node.data) {
            .variant => |variant| variant.value orelse return,
            else => return,
        };
        if (node.span.end != program.nodes[@backingInt(payload)].span.end) return;
        const copied = inherited(program, payload);
        if (isCopy(program, copied)) try self.map.put(self.memory, copied, .returned);
    }

    /// Record the operands of the dictionary or set write `store`: a copied key is a store key (case vi), a copied value
    /// is taken over (case v).
    fn putStore(self: *Contexts, program: typed.Program, operands: []const typed.NodeId, store: typed.NodeId) std.mem.Allocator.Error!void {
        for (operands, 0..) |operand, position| {
            const value = inherited(program, operand);
            if (position == 0 and isCopy(program, value)) {
                try self.put(value, .{ .store_key = store });
            } else try self.putMoved(program, operand);
        }
    }

    /// Record a copy that its parent takes over (case v).
    fn putMoved(self: *Contexts, program: typed.Program, id: typed.NodeId) std.mem.Allocator.Error!void {
        const value = inherited(program, id);
        if (isCopy(program, value)) try self.put(value, .moved);
    }

    /// Record one copy's context; the first parent to name it wins.
    fn put(self: *Contexts, id: typed.NodeId, context: Context) std.mem.Allocator.Error!void {
        const entry = try self.map.getOrPut(self.memory, id);
        if (entry.found_existing) return;
        entry.value_ptr.* = context;
    }

    /// Release the parent index.
    fn deinit(self: *Contexts) void {
        self.map.deinit(self.memory);
    }

    /// What one node's parent makes of it.
    fn get(self: *const Contexts, id: typed.NodeId) Context {
        return self.map.get(id) orelse .other;
    }
};

/// One function's statements and expressions in walk order.
const BodyItems = struct { function: typed.FunctionId, list: []const walk.Item };

/// How many stores initialize each local of one function, and the first value stored, found
/// in one walk of the body. `soleInitializer` asks the same question of one slot with a
/// walk of its own; a pass that asks about many slots of a function reads this instead.
const Initializers = struct {
    function: typed.FunctionId,
    entries: []Entry,

    /// One local's initializations: how many stores write it (saturating at two) and the first value.
    const Entry = struct { count: u8 = 0, value: typed.NodeId = undefined };

    /// Release the index.
    fn deinit(self: Initializers, memory: std.mem.Allocator) void {
        memory.free(self.entries);
    }

    /// The value one local was initialized with, when exactly one store writes it.
    fn sole(self: Initializers, slot: usize) ?typed.NodeId {
        const entry = self.entries[slot];
        return if (entry.count == 1) entry.value else null;
    }
};

/// The value a lowering wrapper stands for: a `block_value` whose whole body is
/// one temporary's initialization hands over that temporary's value, so
/// `bag.items.copy()` reaches the call as `copy(bag.items)` through it.
pub fn inherited(program: typed.Program, id: typed.NodeId) typed.NodeId {
    var current = id;
    var depth: usize = 0;
    while (depth < depth_limit) : (depth += 1) {
        const block = switch (program.nodes[@backingInt(current)].data) {
            .block_value => |value| value,
            else => return current,
        };
        const statements = switch (program.statements[@backingInt(block.body)].data) {
            .block => |items| items,
            else => return current,
        };
        if (statements.len != 1) return current;
        if (program.statements[@backingInt(statements[0])].data != .initialize) return current;
        current = block.value;
    }
    return current;
}

/// Whether `id` is a `.copy()` operation with no arguments on a managed value.
pub fn isCopy(program: typed.Program, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    if (node.view) return false;
    return switch (node.data) {
        .buffer_operation => |operation| operation.kind == .copy and operation.arguments.len == 0,
        else => false,
    };
}

/// One warning pass over a checked program.
/// The answers of `viewedAnywhere` for one function, by the reference slot and the (at most two) skipped slots plus one.
const ViewedAnswers = struct { function: typed.FunctionId, answers: std.AutoHashMapUnmanaged([3]usize, bool) };

const Pass = struct {
    memory: std.mem.Allocator,
    program: typed.Program,
    src: source.Source,
    contexts: Contexts,
    sink: *diagnostic.Sink,
    /// The initializations of the function being warned, built when first asked about.
    initializers: ?Initializers = null,
    /// The copies a function-level hint already covers, so the per-copy hints leave them alone.
    hinted: std.AutoHashMapUnmanaged(typed.NodeId, void) = .empty,
    /// The statements and expressions of the function being warned, in walk order, built when first asked about.
    items: ?BodyItems = null,
    /// What `viewedAnywhere` answered for the function being warned (FR26): the repair and the hint of one copy ask it of the same
    /// element, and each scan walks the locals and the whole body.
    viewed: ?ViewedAnswers = null,
    /// The program's owned record types (`owned_types.table`), built when first asked about (`noManagedPart`).
    owned: ?[]const bool = null,

    /// Emit one warning for every copy whose repair this pass proves.
    ///
    /// `stubs` marks a function whose body a semantic summary stood in for: its
    /// checked tree is the parameters alone, so the copy warnings its real body
    /// carried are replayed from that summary instead, exactly as the binding
    /// warnings are.
    fn run(self: *Pass, stubs: []const ?origins.Fact) std.mem.Allocator.Error!void {
        for (self.program.functions, 0..) |function, index| {
            if (function.policy.host != null) continue;
            if (origins.standIn(stubs, index) != null) continue;
            try self.warnFunction(function);
        }
    }

    /// Emit the warnings of one checked function body.
    fn warnFunction(self: *Pass, function: typed.Function) std.mem.Allocator.Error!void {
        try self.warnReturnsFrom(function);
        const writes = try self.writesOf(function);
        defer self.memory.free(writes);
        var parents: ?reads.Body = null;
        defer if (parents) |*built| built.deinit();
        for (try self.bodyItems(function)) |item| {
            const id = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            if (!isCopy(self.program, id) or self.hinted.contains(id)) continue;
            if (!try self.warnCopy(function, writes, &parents, id)) try self.warnMove(function, id);
        }
    }

    /// Emit the warning of one copy whose repair this pass proves; false when it proves none.
    fn warnCopy(self: *Pass, function: typed.Function, writes: []const Write, parents: *?reads.Body, id: typed.NodeId) std.mem.Allocator.Error!bool {
        const node = self.program.nodes[@backingInt(id)];
        const slot = @backingInt(node.data.buffer_operation.owner);
        if (slot >= function.scope.locals.len) return false;
        if (try self.freshOperand(function, slot)) {
            try self.warnFresh(node);
            return true;
        }
        // The standard library is the compiler's: its copies are not the user's to repair.
        if (std.mem.startsWith(u8, self.src.locate(node.span.start).path, "@stdlib/")) return false;
        if (function.scope.locals[slot].origin == .iteration and switch (self.contexts.get(id)) {
            .moved, .returned => true,
            else => false,
        }) {
            const moved = try self.warnLoopMove(function, id, node);
            return moved;
        }
        // A copy of a record or a list reads the element through a compiler temporary: the loop over a call's list is found
        // through it, and any other shape goes on to the cases below.
        if (isTemporary(function.scope.locals[slot]) and switch (self.contexts.get(id)) {
            .moved, .returned => true,
            else => false,
        }) {
            if (try self.warnLoopMove(function, id, node)) return true;
        }
        // A dictionary key may be a view a loop or an element read bound: the store only reads it (case vi).
        const store_key = self.contexts.get(id) == .store_key or self.libraryKey(id);
        // A copy of a borrowed value (a call's borrowed result, an option's default) has no receiver of its own; the
        // read-only positions follow it to the one local it borrows (case viii).
        var borrowed_value = false;
        const place = (if (store_key) try self.keyReceiver(function, slot) else try self.receiverOf(function, slot)) orelse found: {
            if (store_key or !readsBorrow(self.contexts.get(id))) return false;
            borrowed_value = true;
            break :found (try self.borrowedReceiver(function, slot)) orelse return false;
        };
        if (!self.plainValue(place.local, node.ty, store_key)) return false;
        // A reasoned site waiver silences the warning as well as the rule: a
        // copy that is the point of the code stays, deliberately.
        if (try waived(self.src, node.span)) return false;
        const receiver = receiverText(self.src, node.span) orelse return false;
        var replacement = receiver;
        var edit_span = node.span;
        // Whether the repair is a move, written `own x`: a value with no managed part takes no marker (`noManagedPart`).
        var moves = false;
        var message = switch (self.contexts.get(id)) {
            .call_argument => |argument| (if (self.libraryKey(id))
                try self.libraryKeyRepair(function, place, node.span, writes, id)
            else
                try self.callRepair(place, receiver, node.span, writes, argument)) orelse moved: {
                if (!ownArgument(self.program, argument.function, argument.position)) return false;
                const move_message = (try self.moveRepair(function, place, receiver, id, .moved)) orelse return false;
                replacement = try std.fmt.allocPrint(self.memory, "own {s}", .{receiver});
                moves = true;
                break :moved move_message;
            },
            .moved => moved: {
                const move_message = (try self.moveRepair(function, place, receiver, id, .moved)) orelse return false;
                replacement = try std.fmt.allocPrint(self.memory, "own {s}", .{receiver});
                moves = true;
                break :moved move_message;
            },
            .store_key => |store| key: {
                if (try self.moveRepair(function, place, receiver, id, .moved)) |move_message| {
                    replacement = try std.fmt.allocPrint(self.memory, "own {s}", .{receiver});
                    moves = true;
                    break :key move_message;
                }
                const repair = (try self.keyRepair(function, place, .{ .store = store, .copy = id }, writes)) orelse return false;
                if (repair.rewrite) |call| {
                    replacement = call;
                    edit_span = self.program.nodes[@backingInt(store)].span;
                }
                break :key repair.message;
            },
            .returned => returned: {
                const move_message = (try self.moveRepair(function, place, receiver, id, .returned)) orelse return false;
                // A bare return moves a whole local; a field of one is a move out of its record, and says so.
                if (!place.direct) replacement = try std.fmt.allocPrint(self.memory, "own {s}", .{receiver});
                moves = true;
                break :returned move_message;
            },
            .invoke_argument => |argument| (try self.invokeRepair(place, receiver, node.span, writes, argument)) orelse return false,
            .print_argument => |span| if (self.conflicts(place, span, node.span, writes)) return false else try printRepair(self.memory, receiver),
            .stream_text => |span| if (self.conflicts(place, span, node.span, writes)) return false else try streamRepair(self.memory, receiver),
            .format_hole => |span| if (self.conflicts(place, span, node.span, writes)) return false else try formatRepair(self.memory, receiver),
            .initialize => |statement| initialization: {
                const moved = if (borrowed_value) null else try self.initializeRepair(function, place, receiver, statement);
                if (moved) |move_message| {
                    replacement = try std.fmt.allocPrint(self.memory, "own {s}", .{receiver});
                    moves = true;
                    break :initialization move_message;
                }
                break :initialization (try self.constBindingRepair(try self.bodyOf(function, parents), place, id, receiver, statement)) orelse return false;
            },
            .other => return false,
        };
        if (moves and try self.noManagedPart(node.ty, place.local.ty)) {
            replacement = receiver;
            message = try std.fmt.allocPrint(self.memory, "`{s}` holds no managed value, so `copy({s})` copies nothing a plain use would not: write `{s}`", .{ receiver, receiver, receiver });
        }
        try self.sink.appendFix(.{
            .severity = .warning,
            .code = code,
            .span = node.span,
            .message = message,
        }, .{ .span = edit_span, .text = replacement });
        return true;
    }
    /// Case (vii): the copy duplicates a value that is already new, a call that returns a fresh result, a module
    /// constant, a concatenation, a literal record. The copy-free form hands the temporary over, so the copy is a second
    /// allocation of the same bytes in any position that accepts a fresh value, and every position does.
    fn freshOperand(self: *Pass, function: typed.Function, slot: usize) std.mem.Allocator.Error!bool {
        if (!isTemporary(function.scope.locals[slot])) return false;
        var value = (try self.onlyInitializer(function, slot)) orelse return false;
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            const node = self.program.nodes[@backingInt(value)];
            if (node.view) return false;
            switch (node.data) {
                .block_value => |block| value = block.value,
                // A named place is not new: the copy of it is what the other cases judge.
                .local, .field, .index => return false,
                else => return self.owningValue(function, value, 0),
            }
        }
        return false;
    }

    /// The case (vii) warning for the copy `node`: its edit keeps only the copied expression.
    fn warnFresh(self: *Pass, node: typed.Node) std.mem.Allocator.Error!void {
        if (try waived(self.src, node.span)) return;
        const receiver = receiverText(self.src, node.span) orelse return;
        const message = try std.fmt.allocPrint(self.memory, "`{s}` already yields a new value, so the copy only duplicates a temporary; write `{s}` without it", .{ receiver, receiver });
        try self.sink.appendFix(.{ .severity = .warning, .code = code, .span = node.span, .message = message }, .{ .span = node.span, .text = receiver });
    }

    /// Case (viii): where the borrowed value a copy duplicates reads from. A call's declared borrowed result, an option's
    /// default (`opt.unwrap_or(b"")`) and an element or field read all borrow one named local; a copy of such a value is
    /// judged against that local exactly as a copy of the local's own place is. Null when the value borrows nothing or
    /// more than one local, or when the chain is not one this pass understands.
    fn borrowedReceiver(self: *Pass, function: typed.Function, slot: usize) std.mem.Allocator.Error!?Receiver {
        const value = (try self.onlyInitializer(function, slot)) orelse return null;
        const named = switch (try self.borrowOf(function, value, 0)) {
            .root => |found| found,
            .fresh, .unknown => return null,
        };
        // A loop variable stands for an element of the list it iterates: the loan is on that list.
        const root = (try self.rootSlot(function, named)) orelse return null;
        const owner = function.scope.locals[root];
        if (owner.ownership.view or owner.usage.temporary) return null;
        if (std.mem.startsWith(u8, owner.name, "<")) return null;
        return .{ .local = owner, .slot = root, .direct = false, .uncertain_root = owner.origin != .parameter and !try self.owningSource(function, root) };
    }

    /// What a value borrows: nothing (a literal, a call's fresh result), exactly one named local, or something this pass
    /// cannot place.
    const Borrow = union(enum) { fresh, root: usize, unknown };

    /// The named local `id` borrows from, found through call sources, option defaults, projections and element reads.
    fn borrowOf(self: *Pass, function: typed.Function, id: typed.NodeId, depth: usize) std.mem.Allocator.Error!Borrow {
        if (depth > depth_limit) return .unknown;
        const node = self.program.nodes[@backingInt(id)];
        switch (node.data) {
            .integer, .boolean, .unit, .blob => return .fresh,
            .array => |values| {
                var found: Borrow = .fresh;
                for (values) |value| found = joinBorrows(found, try self.borrowOf(function, value, depth + 1));
                return found;
            },
            .borrow_selection => |selection| return joinBorrows(
                try self.borrowOf(function, selection.first, depth + 1),
                try self.borrowOf(function, selection.second, depth + 1),
            ),
            .call => |call| {
                if (@backingInt(call.function) >= self.program.functions.len) return .unknown;
                const signature = self.program.functions[@backingInt(call.function)].signature;
                if (signature.return_origin == .unknown) return .unknown;
                var found: Borrow = .fresh;
                for (return_borrow.effectiveSources(self.program.records, signature)) |position| {
                    if (position >= call.arguments.len) return .unknown;
                    found = joinBorrows(found, try self.borrowOf(function, call.arguments[position], depth + 1));
                }
                return found;
            },
            .block_value, .local, .field, .index, .buffer_operation => {
                if (node.data == .buffer_operation and node.data.buffer_operation.kind != .read) return .unknown;
                if (try self.keyRoot(function, id, depth)) |named| return .{ .root = named };
                // A lowering wrapper hands its value on; a slice block is a view of its base, which this case does not place.
                if (node.data == .block_value and !node.view) return self.borrowOf(function, node.data.block_value.value, depth + 1);
                return .unknown;
            },
            else => return .unknown,
        }
    }

    /// A copy no repair above is certain for: say which cheaper form fits, when the source is not read again. The hint is
    /// `W_COPY_MOVE`, report only; where the rewrite is certain the form is a `W_NEEDLESS_COPY` repair instead.
    fn warnMove(self: *Pass, function: typed.Function, id: typed.NodeId) std.mem.Allocator.Error!void {
        if (function.type_arguments.len != 0) return;
        const node = self.program.nodes[@backingInt(id)];
        if (std.mem.startsWith(u8, self.src.locate(node.span.start).path, "@stdlib/")) return;
        switch (self.contexts.get(id)) {
            .moved, .returned, .initialize => {},
            .call_argument => |argument| if (!ownArgument(self.program, argument.function, argument.position)) return,
            else => return,
        }
        if (try waivedAs(self.src, node.span, "copy-move")) return;
        const receiver = receiverText(self.src, node.span) orelse return;
        if (try self.warnTake(function, id, node, receiver)) return;
        if (try self.warnTakeOr(function, node)) return;
        if (try self.warnLoopHint(function, id, node, receiver)) return;
        _ = try self.warnMatchOwn(function, id, node, receiver);
    }

    /// The spelling that takes over what a copy duplicates, and the copy it replaces, as the source accepts them where the copy
    /// stands (FR21). A value taken over (a store, a constructor, an `own` argument, a binding) is written `own x`; a returned
    /// or failed name is written bare, `return x` or `fail x`, because `return own x` is `E_OWN_MARKER`; a returned field
    /// of one takes the marker, `return own x.f`.
    fn moveSpelling(self: *Pass, context: Context, node: typed.Node, receiver: []const u8) std.mem.Allocator.Error!MoveSpelling {
        if (context != .returned) return .{
            .edit = try std.fmt.allocPrint(self.memory, "own {s}", .{receiver}),
            .original = try std.fmt.allocPrint(self.memory, "copy({s})", .{receiver}),
        };
        const word = returnWord(self.src, node.span);
        return .{
            .edit = if (isName(receiver))
                try std.fmt.allocPrint(self.memory, "{s} {s}", .{ word, receiver })
            else
                try std.fmt.allocPrint(self.memory, "{s} own {s}", .{ word, receiver }),
            .original = try std.fmt.allocPrint(self.memory, "{s} copy({s})", .{ word, receiver }),
        };
    }

    /// The match payload slot the local `slot` is, or the one a plain field read of it came from: a fielded pattern binds the
    /// payload and projects its fields into locals of their own.
    fn matchBinding(self: *Pass, function: typed.Function, slot: usize) std.mem.Allocator.Error!?usize {
        var current = slot;
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            if (current >= function.scope.locals.len) return null;
            if (function.scope.locals[current].origin == .pattern) return current;
            var value = (try self.onlyInitializer(function, current)) orelse return current;
            var inner: usize = 0;
            while (inner < depth_limit) : (inner += 1) switch (self.program.nodes[@backingInt(value)].data) {
                .field => |field| value = field.base,
                .block_value => |block| value = block.value,
                .local => |next| {
                    current = @backingInt(next);
                    break;
                },
                else => return current,
            } else return null;
        }
        return null;
    }

    /// Case (xiv): the copy duplicates the payload `p` of a `match r:` on a local `r` the function owns and reads nowhere after
    /// the match. `match own r:` consumes the owner, so `p` owns its payload and `own p` replaces the copy. The match
    /// holds `r`, so nothing else in its arms may read `r`. Where the rewrite is certain (`matchOwnRepair`) the finding is a
    /// `W_NEEDLESS_COPY` repair of both edits; the rest keeps the `W_COPY_MOVE` hint (an `if r is Some(p):` has no `own` spelling).
    fn warnMatchOwn(self: *Pass, function: typed.Function, id: typed.NodeId, node: typed.Node, receiver: []const u8) std.mem.Allocator.Error!bool {
        const copied = @backingInt(node.data.buffer_operation.owner);
        if (copied >= function.scope.locals.len or function.scope.locals[copied].origin == .iteration) return false;
        const payload = (try self.matchBinding(function, copied)) orelse return false;
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const match = switch (self.program.statements[@backingInt(statement)].data) {
                .match => |value| value,
                else => continue,
            };
            for (match.arms) |arm| {
                if (!bindsSlot(arm, payload)) continue;
                const owner = switch (self.program.nodes[@backingInt(match.value)].data) {
                    .local => |slot| @backingInt(slot),
                    else => return false,
                };
                const root = function.scope.locals[owner];
                if (root.ownership.view or isTemporary(root) or root.ty.capabilityIndex() != null) return false;
                const owned = (root.origin == .local and try self.owningSource(function, owner)) or try self.consumingBinding(function, owner);
                if (!owned) return false;
                const span = self.program.statements[@backingInt(statement)].span;
                if (try self.usedAfter(function, owner, span)) return false;
                if (try self.usedAfter(function, copied, node.span)) return false;
                if (try self.viewedAnywhere(function, owner, &.{ payload, copied })) return false;
                const found: OwnedMatch = .{ .statement = statement, .value = match.value, .owner = owner, .payload = payload };
                if (try self.matchOwnRepair(function, id, node, found)) return true;
                const message = try std.fmt.allocPrint(
                    self.memory,
                    "`{s}` is not used after this match: `match own {s}:` makes `{s}` an owned payload, so `{s}` replaces the copy",
                    .{ root.name, root.name, receiver, (try self.moveSpelling(self.contexts.get(id), node, receiver)).edit },
                );
                return self.hint(node.span, message);
            }
        }
        return false;
    }

    /// The `match` a payload copy sits in and the owner it matches: the statement, its scrutinee node, the owner's slot and the
    /// payload binding the copy reads.
    const OwnedMatch = struct { statement: typed.StatementId, value: typed.NodeId, owner: usize, payload: usize };

    /// Case (xiv) as a repair: `match r:` becomes `match own r:` and the copy of the payload becomes `own p` (a returned name is
    /// written bare). Two edits, the head's first and the copy's in `more`; every arm that copies a payload of the one match
    /// reports the same head edit, which `fix` applies once. Null of the repair, and so the hint, where the owner is not a plain
    /// name after a bare `match`, is read inside the match, is declared outside a loop the match runs in, or the payload is read
    /// or held elsewhere around the copy.
    fn matchOwnRepair(self: *Pass, function: typed.Function, id: typed.NodeId, node: typed.Node, found: OwnedMatch) std.mem.Allocator.Error!bool {
        const statement = self.program.statements[@backingInt(found.statement)];
        const match = statement.data.match;
        if (match.exclusive or match.borrowed) return false;
        const scrutinee = self.program.nodes[@backingInt(found.value)];
        const root = function.scope.locals[found.owner];
        if (!std.mem.eql(u8, self.src.text(scrutinee.span), root.name)) return false;
        // A bind-or-else, `const p = r else:`, is a match of its own kind that takes `own` in the same place, in front of `r`.
        const written = if (match.continuation)
            constBindHead(self.src, statement.span.start, scrutinee.span.start)
        else
            bareMatchHead(self.src, statement.span.start, scrutinee.span.start);
        if (!written) return false;
        if (try self.readInside(function, found.owner, statement.span, found.value)) return false;
        // An option an earlier `if`, `elif` or `while` condition tests is read as its payload where that test holds (`if r is None:
        // return`), and `own r` there is no option any more (`E_ELSE_OPERAND`): any such condition above the statement withholds.
        if (try self.testedBefore(function, found.owner, statement.span.start)) return false;
        if (try self.runsAgain(function, found.statement, root.declaration)) return false;
        const place: Receiver = .{ .local = function.scope.locals[found.payload], .slot = found.payload, .direct = true, .uncertain_root = false };
        if (try self.usedAfter(function, found.payload, node.span)) return false;
        if (try self.heldAround(function, place, id, .named)) return false;
        const receiver = receiverText(self.src, node.span) orelse return false;
        const replacement = if (self.contexts.get(id) == .returned and isName(receiver))
            receiver
        else
            try std.fmt.allocPrint(self.memory, "own {s}", .{receiver});
        const message = if (match.continuation)
            try std.fmt.allocPrint(
                self.memory,
                "`{s}` is not used after this binding, so `own {s}` in front of `else` makes `{s}` an owned payload and the copy becomes a move",
                .{ root.name, root.name, function.scope.locals[found.payload].name },
            )
        else
            try std.fmt.allocPrint(
                self.memory,
                "`{s}` is not used after this match, so `match own {s}:` makes `{s}` an owned payload and the copy becomes a move",
                .{ root.name, root.name, function.scope.locals[found.payload].name },
            );
        const head: source.Span = .{ .start = scrutinee.span.start, .end = scrutinee.span.start };
        try self.sink.appendFix(.{ .severity = .warning, .code = code, .span = node.span, .message = message }, .{ .span = head, .text = "own " });
        const last = &self.sink.items.items[self.sink.items.items.len - 1];
        last.provenance.fix.?.more = try self.memory.dupe(diagnostic.Edit, &.{.{ .span = node.span, .text = replacement }});
        return true;
    }

    /// Whether the condition of an `if`, `elif` or `while` that starts before `before` reads the local `owner`. The checker narrows an
    /// option such a condition tests (the typed tree keeps no mark of it on the later read), so the repair does not guess where.
    fn testedBefore(self: *Pass, function: typed.Function, owner: usize, before: usize) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| self.program.statements[@backingInt(value)],
                .expression => continue,
            };
            const condition = switch (statement.data) {
                .branch => |branch| branch.condition,
                .loop => |loop| loop.condition,
                else => continue,
            };
            if (statement.span.start >= before) continue;
            const tested = self.program.nodes[@backingInt(condition)].span;
            // The condition a `for` loop generates spans its whole loop; only a condition written ahead of `before` tests anything.
            if (tested.end > before) continue;
            if (try self.readWithin(function, owner, tested)) return true;
        }
        return false;
    }

    /// Whether a loop that starts after `declared` holds the statement `target`: the loop runs the statement again, and what it
    /// consumes is gone from the second pass on.
    fn runsAgain(self: *Pass, function: typed.Function, target: typed.StatementId, declared: source.Span) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| {
            const id = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const outer = self.program.statements[@backingInt(id)];
            switch (outer.data) {
                .loop, .range_loop => {},
                else => continue,
            }
            if (!try self.contains(id, target)) continue;
            if (declared.start < outer.span.start or declared.start >= outer.span.end) return true;
        }
        return false;
    }

    /// Case (xiii): every `return` of a function copies a place of one parameter (`return Some(copy(path[:end]))`), or hands
    /// back a constant (`None`, `""`, `[]`). Declaring the result `from` that parameter returns the places themselves, and a
    /// caller that only reads the result copies nothing. The signature is a contract with every caller, so this is a hint: the
    /// pass cannot see the callers in other modules or in test files, and a caller that stores the result needs its own copy.
    /// A project check that can see them all makes it a repair where that is certain (`copy_from_repair.zig`).
    fn warnReturnsFrom(self: *Pass, function: typed.Function) std.mem.Allocator.Error!void {
        if (function.type_arguments.len != 0 or function.policy.c_abi or function.signature.return_origin != .fresh) return;
        if (!return_borrow.managed(self.program.records, function.signature.return_type)) return;
        if (std.mem.startsWith(u8, self.src.locate(function.declaration.start).path, "@stdlib/")) return;
        var copies: std.ArrayList(typed.NodeId) = .empty;
        defer copies.deinit(self.memory);
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const value = switch (self.program.statements[@backingInt(statement)].data) {
                .ret => |returned| returned,
                else => continue,
            };
            if (!try self.returnShape(function, value, &copies, 0)) return;
        }
        if (copies.items.len == 0) return;
        var root: ?usize = null;
        for (copies.items) |copy_id| {
            const owner = @backingInt(self.program.nodes[@backingInt(copy_id)].data.buffer_operation.owner);
            const place = (try self.receiverOf(function, owner)) orelse (try self.borrowedReceiver(function, owner)) orelse return;
            if (place.local.origin != .parameter or place.local.ownership.view) return;
            if (!plainParameter(self.program, function, place.slot) and !mutParameter(self.program, function, place.slot)) return;
            if (root != null and root.? != place.slot) return;
            root = place.slot;
        }
        // A source that cannot lend the result makes the `from` advice false whatever the callers do.
        if (!from_advice.lends(self.program, function, root.?)) return;
        const first = self.program.nodes[@backingInt(copies.items[0])];
        if (try waivedAs(self.src, first.span, "copy-move")) return;
        const parameter = function.scope.locals[root.?].name;
        const spelled_function = try display_name.spelled(self.memory, function.name);
        defer display_name.release(self.memory, spelled_function, function.name);
        const message = try std.fmt.allocPrint(
            self.memory,
            "every return of `{s}` copies a place of `{s}`: if every caller only reads the result, declare it `from {s}` and " ++
                "return the places themselves, so no caller copies; if a caller keeps the result, the copy is needed there",
            .{ spelled_function, parameter, parameter },
        );
        _ = try self.hint(first.span, message);
        for (copies.items) |copy_id| try self.hinted.put(self.memory, copy_id, {});
    }

    /// Whether one returned value is a copy, a constant (`from_advice.constant`), or an option or result wrapping one; the
    /// copies found are appended. Anything else (a local, a call, a new value) is a shape this hint does not name.
    fn returnShape(self: *Pass, function: typed.Function, id: typed.NodeId, copies: *std.ArrayList(typed.NodeId), depth: usize) std.mem.Allocator.Error!bool {
        if (depth > depth_limit) return false;
        const value = inherited(self.program, id);
        const node = self.program.nodes[@backingInt(value)];
        if (isCopy(self.program, value)) {
            if (!std.mem.startsWith(u8, std.mem.trim(u8, self.src.text(node.span), " \t\r\n"), "copy")) return false;
            try copies.append(self.memory, value);
            return true;
        }
        switch (node.data) {
            .variant => |variant| {
                const step = return_borrow.step(self.program.records, node.ty) orelse return false;
                // The failure of a result and the `None` of an option hold nothing borrowed.
                if (variant.tag != step.tag) return true;
                const payload = variant.value orelse return true;
                return self.returnShape(function, payload, copies, depth + 1);
            },
            // A new value beside a borrowed return is `E_BORROW_MIXED`: only a constant may stand there.
            else => return from_advice.constant(self.program, id) or from_advice.constant(self.program, value),
        }
    }

    /// Append one `W_COPY_MOVE` hint at `span`.
    fn hint(self: *Pass, span: source.Span, message: []const u8) std.mem.Allocator.Error!bool {
        try self.sink.items.append(self.sink.allocator, .{ .severity = .warning, .code = move_code, .span = span, .message = message });
        return true;
    }

    /// Case (xi): `copy(opt.unwrap_or(default))` where `opt` is an option the function owns and reads nowhere else, or a
    /// fresh call result. `options.take_or(own opt, default)` returns the payload, or the default, without the copy.
    fn warnTakeOr(self: *Pass, function: typed.Function, node: typed.Node) std.mem.Allocator.Error!bool {
        const owner = @backingInt(node.data.buffer_operation.owner);
        if (owner >= function.scope.locals.len or !isTemporary(function.scope.locals[owner])) return false;
        const value = (try self.onlyInitializer(function, owner)) orelse return false;
        const selection = switch (self.program.nodes[@backingInt(value)].data) {
            .borrow_selection => |found| found,
            else => return false,
        };
        if (selection.kind != .optional_default) return false;
        if (!try self.owningValue(function, selection.second, 0)) return false;
        const first = self.program.nodes[@backingInt(selection.first)];
        const copy_span = node.span;
        const option = self.src.text(first.span);
        switch (first.data) {
            .local => |slot| {
                const root = @backingInt(slot);
                const local = function.scope.locals[root];
                if (isTemporary(local) or local.ownership.view or local.origin != .local) return false;
                if (!try self.owningSource(function, root)) return false;
                if (try self.usedAfter(function, root, copy_span)) return false;
                if (try self.viewedAnywhere(function, root, &.{owner})) return false;
                const default = self.src.text(self.program.nodes[@backingInt(selection.second)].span);
                // `own option` moves the local: not in a loop the local outlives, not under a statement whose head reads it.
                const certain = takeOrSpelled(function, option, default) and !try self.optionHeld(function, root, selection.first, copy_span);
                if (certain and try self.takeOrRepair(copy_span, "is not used again, so", true, option, default)) return true;
                return self.takeOrHint(copy_span, "is not used again, so", "own ", option, default);
            },
            .call => {
                if (!try self.owningValue(function, selection.first, 0)) return false;
                const default = self.src.text(self.program.nodes[@backingInt(selection.second)].span);
                if (takeOrSpelled(function, option, default) and try self.takeOrRepair(copy_span, "returns a new option, so", false, option, default)) return true;
                return self.takeOrHint(copy_span, "returns a new option, so", "", option, default);
            },
            else => return false,
        }
    }

    /// Whether moving the option local `root` at the copy `copy_span` would not check, where `first` is the read of the option the
    /// copy makes: a loop around the copy that the option was declared before, a `match` or `with` around it whose head reads the
    /// option, a branch whose condition holds the copy, or another read of the option in the statement that holds the copy.
    /// (`heldAround` asks the same of a copy of a place, and counts the read inside `opt.unwrap_or(d)` as another.)
    fn optionHeld(self: *Pass, function: typed.Function, root: usize, first: typed.NodeId, copy_span: source.Span) std.mem.Allocator.Error!bool {
        const declared = function.scope.locals[root].declaration;
        var outermost: ?source.Span = null;
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| self.program.statements[@backingInt(value)],
                .expression => continue,
            };
            if (statement.span.start > copy_span.start or statement.span.end < copy_span.end) continue;
            switch (statement.data) {
                .loop, .range_loop => if (declared.start < statement.span.start or declared.start >= statement.span.end) return true,
                .match => |match| if (try self.mentions(match.value, root)) return true,
                .branch => |branch| if (try self.conditionHolds(branch.condition, root, copy_span)) return true,
                .with_scope => |scope| if (try self.scopeHolds(function, statement.span, scope, root)) return true,
                .block => {},
                .initialize, .assign => |store| if (!isTemporary(function.scope.locals[@backingInt(store.slot)]) and !try self.spansLoop(function, statement.span)) {
                    outermost = wider(outermost, statement.span);
                },
                else => if (!try self.spansLoop(function, statement.span)) {
                    outermost = wider(outermost, statement.span);
                },
            }
        }
        const holding = outermost orelse return true;
        for (try self.bodyItems(function)) |item| {
            const id = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            if (id == first) continue;
            const node = self.program.nodes[@backingInt(id)];
            if (refersTo(node, root) and inside(holding, node.span)) return true;
        }
        return false;
    }

    /// The `options.take_or` repair: the copy becomes the call, and the unit gains `import options` when it has none. Returns
    /// whether the repair was written; false leaves the hint (`takeOrSpelled` says where the call may be written).
    fn takeOrRepair(self: *Pass, copy_span: source.Span, why: []const u8, named: bool, option: []const u8, default: []const u8) std.mem.Allocator.Error!bool {
        const import = take_repair.importEdit(self.memory, self.src, copy_span) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InternalError => return false,
        };
        const call = try take_repair.takeOrCall(self.memory, named, option, default);
        const message = try std.fmt.allocPrint(self.memory, "`{s}` {s} `{s}` returns its payload without the copy", .{ option, why, call });
        try self.sink.appendFix(.{ .severity = .warning, .code = code, .span = copy_span, .message = message }, .{ .span = copy_span, .text = call });
        if (import) |line| {
            const last = &self.sink.items.items[self.sink.items.items.len - 1];
            last.provenance.fix.?.more = try self.memory.dupe(diagnostic.Edit, &.{line});
        }
        return true;
    }

    /// The `options.take_or` hint: `why` says why the option may be consumed, `marker` is `own ` for a named option.
    fn takeOrHint(self: *Pass, span: source.Span, why: []const u8, marker: []const u8, option: []const u8, default: []const u8) std.mem.Allocator.Error!bool {
        const message = try std.fmt.allocPrint(
            self.memory,
            "`{s}` {s} `options.take_or({s}{s}, {s})` returns its payload without the copy",
            .{ option, why, marker, option, default },
        );
        return self.hint(span, message);
    }

    /// Case (xii): a loop copies each element `x` of a list into storage and the list is not read after the loop, but it is a
    /// parameter, a field or a call result, not a local the loop can consume. A consuming loop (`for x in own xs`) moves
    /// each element, so the list must be an owned local or an `own` parameter: the hint says so.
    fn warnLoopHint(self: *Pass, function: typed.Function, id: typed.NodeId, node: typed.Node, receiver: []const u8) std.mem.Allocator.Error!bool {
        const owner = @backingInt(node.data.buffer_operation.owner);
        const element = (try self.elementOf(function, owner)) orelse return false;
        const name = function.scope.locals[element].name;
        if (self.contexts.get(id) == .initialize) return false;
        const header = (try self.iterationHeader(function, element)) orelse return false;
        // A loop over `enumerate(xs)`, `zip(..)` or `reversed(xs)` is not a loop over `xs`: `for x in own xs` would lose the
        // index, the pairing or the order (FR21), and `own` has no spelling inside those calls.
        if (!iteratesDirectly(self.src, self.program.nodes[@backingInt(header.source)].span)) return false;
        if (header.fresh) {
            if (try self.usedAfter(function, element, node.span)) return false;
            // A view of the element (`const head = one[0:1]`) that is read after the copy would be invalidated by the move, which
            // the checker refuses (V3): the hint is withheld there. A view nothing reads again does not stop the move (FR27).
            if (try self.viewedLive(function, element, &.{}, node.span)) return false;
            // Where the move is certain the hint is a repair (COPY-A2c): a copied field `x.f`, an `own` argument.
            if (try self.loopRepair(function, id, node, .{ .element = element, .header = header, .receiver = receiver })) return true;
            // The consuming loop takes the call's result itself (F-16): the hint names that spelling.
            const call = self.src.text(self.program.nodes[@backingInt(header.source)].span);
            const spelling = try self.moveSpelling(self.contexts.get(id), node, receiver);
            const fresh_message = try std.fmt.allocPrint(
                self.memory,
                "`{s}` is copied out of each element of a list the call returns; `for {s} in own {s}:` hands the " ++
                    "elements over, so write `{s}` in place of `{s}`",
                .{ receiver, name, call, spelling.edit, spelling.original },
            );
            return self.hint(node.span, fresh_message);
        }
        const list = function.scope.locals[header.list];
        if (list.ownership.view or isTemporary(list) or list.ty.capabilityIndex() != null) return false;
        // An owned list (an owned local, an `own` parameter, a payload a `match` or a bind-or-else takes from a fresh value) is
        // repaired below where case (ix) left the copy (COPY-A2c).
        const owned = header.whole and (try self.owningSource(function, header.list) or try self.consumingBinding(function, header.list));
        const lent = list.origin == .parameter and header.whole and !self.plainListParameter(function, header.list);
        if (lent and !owned) return false;
        const loop_span = self.program.statements[@backingInt(header.loop)].span;
        if (try self.usedAfter(function, header.list, loop_span)) return false;
        if (try self.readInside(function, header.list, loop_span, header.source)) return false;
        if (try self.usedAfter(function, element, node.span)) return false;
        // A view of the list or of an element that is read again is invalidated by the consuming loop (V3), so the hint says
        // nothing; a view that nothing reads from the copy on, or after the loop, is not (FR27; `warnLoopMove` stays the broader).
        if (try self.viewedLive(function, header.list, &.{ header.collection, element }, node.span)) return false;
        if (try self.viewedLive(function, element, &.{}, node.span)) return false;
        // A loop around the consuming loop runs it again, and the list is gone after the first run unless it is made in that loop
        // (`warnLoopMove` asks the same): the hint said nothing there only because a view of the list happened to exist (FR27).
        const outer = try self.insideLoop(function, header.loop);
        if (outer != null and outer.? != header.loop and !(list.declaration.start >= self.program.statements[@backingInt(outer.?)].span.start)) return false;
        if (owned) {
            if (try self.loopRepair(function, id, node, .{ .element = element, .header = header, .receiver = receiver })) return true;
            if (list.origin == .parameter) return false;
        }
        const message = try std.fmt.allocPrint(
            self.memory,
            "`{s}` is copied out of each element of `{s}`, which nothing reads after the loop; `for {s} in own {s}` hands the elements over when `{s}` is an owned local or an `own` parameter{s}",
            .{ receiver, list.name, name, list.name, list.name, if (list.origin == .parameter) " (each of its callers then gives its list with `own`)" else "" },
        );
        return self.hint(node.span, message);
    }

    /// What `loopRepair` reads of a copy a loop hint names: the element it copies from, the loop's header, the receiver text.
    const LoopCopy = struct { element: usize, header: IterationHeader, receiver: []const u8 };

    /// COPY-A2c: case (ix) for the copies a loop hint names over a list the call returns or an owned list (an owned local, an
    /// `own` parameter), where the hint's conditions hold: a field of the element (`copy(x.f)` to `own x.f`) or a copy an `own`
    /// argument takes. It asks what case (ix) asks beyond the hint: no view of the element or the list anywhere, and nothing
    /// around the copy that holds the element. The edits are case (ix)'s (`copy_loop_edits.loopFix`).
    fn loopRepair(self: *Pass, function: typed.Function, id: typed.NodeId, node: typed.Node, copy: LoopCopy) std.mem.Allocator.Error!bool {
        if (function.type_arguments.len != 0 or try waived(self.src, node.span)) return false;
        const header = copy.header;
        if (try self.viewedAnywhere(function, copy.element, &.{})) return false;
        if (!header.fresh and try self.viewedAnywhere(function, header.list, &.{ header.collection, copy.element })) return false;
        const place: Receiver = .{ .local = function.scope.locals[copy.element], .slot = copy.element, .direct = true, .uncertain_root = false };
        if (try self.heldAround(function, place, id, if (header.fresh) .loop_element else .named)) return false;
        if (!header.fresh and try self.loopAroundList(function, header)) return false;
        if (try self.copiedElsewhere(function, id, copy.element)) return false;
        const returned = self.contexts.get(id) == .returned and isName(copy.receiver);
        const list = if (header.fresh) self.src.text(self.program.nodes[@backingInt(header.source)].span) else function.scope.locals[header.list].name;
        const found = try copy_loop_edits.loopFix(self.memory, .{ .insert = header.insert, .copy = node.span, .receiver = copy.receiver, .returned = returned });
        const message = try copy_loop_edits.moveMessage(self.memory, header.fresh, list, function.scope.locals[copy.element].name);
        try self.sink.items.append(self.sink.allocator, .{ .severity = .warning, .code = code, .span = node.span, .message = message, .provenance = .{ .fix = found } });
        return true;
    }

    /// Whether a copy other than `id` reads the element `element` or a field of it. Once the loop takes the list that copy is
    /// of an owned element, which the pass then names again (a `take` hint for the other fields of one record): a warning
    /// the repair would cause, so the hint stays.
    fn copiedElsewhere(self: *Pass, function: typed.Function, id: typed.NodeId, element: usize) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| {
            const other = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            if (other == id or !isCopy(self.program, other)) continue;
            const owner = @backingInt(self.program.nodes[@backingInt(other)].data.buffer_operation.owner);
            if (owner >= function.scope.locals.len) continue;
            if ((try self.elementOf(function, owner)) == element) return true;
        }
        return false;
    }

    /// Whether a loop around the consuming loop of `header` was entered after its list was declared, and so would run the
    /// consuming loop again over a list already taken (a list made in `for net in nets:` and consumed in `for sp in spokes:`
    /// inside it). Every loop around it must hold the list's declaration; a loop's own lowered statements span it exactly.
    fn loopAroundList(self: *Pass, function: typed.Function, header: IterationHeader) std.mem.Allocator.Error!bool {
        const inner = self.program.statements[@backingInt(header.loop)].span;
        const declared = function.scope.locals[header.list].declaration.start;
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| self.program.statements[@backingInt(value)],
                .expression => continue,
            };
            if (statement.data != .loop and statement.data != .range_loop) continue;
            const around = statement.span.start <= inner.start and statement.span.end >= inner.end;
            const same = statement.span.start == inner.start and statement.span.end == inner.end;
            if (around and !same and declared < statement.span.start) return true;
        }
        return false;
    }

    /// Whether the parameter `slot` is one a caller lends for the call (plain, not `mut`, not `own`): the loop over it
    /// copies because the caller keeps the list.
    fn plainListParameter(self: *Pass, function: typed.Function, slot: usize) bool {
        return plainParameter(self.program, function, slot);
    }

    /// The iteration local a copy's operand reads from (the local itself, or a field of it), or null.
    fn elementOf(self: *Pass, function: typed.Function, owner: usize) std.mem.Allocator.Error!?usize {
        var slot = owner;
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            if (slot >= function.scope.locals.len) return null;
            if (function.scope.locals[slot].origin == .iteration) return slot;
            if (!isTemporary(function.scope.locals[slot])) return null;
            var value = (try self.onlyInitializer(function, slot)) orelse return null;
            var inner: usize = 0;
            while (inner < depth_limit) : (inner += 1) {
                switch (self.program.nodes[@backingInt(value)].data) {
                    .block_value => |block| value = block.value,
                    .field => |field| value = field.base,
                    .local => |next| {
                        slot = @backingInt(next);
                        break;
                    },
                    else => return null,
                }
            } else return null;
        }
        return null;
    }

    /// Where a hint or a repair that moves a value out of a place with `take` stands: the local that holds the place, its
    /// path and the compiler temporaries that carry the read.
    const TakePlace = struct { slot: usize, chain: FieldChain, fields: bool, path: [8]usize = undefined, path_len: usize = 0 };

    /// Case (x): the copy duplicates a field or an element of a local, and nothing reads that place again. `take(mut place)`
    /// moves the value out and leaves the type's default (an empty collection, `None`) behind, so the other fields and
    /// elements stay readable. The place must be mutable for the call: a `mut` local or parameter gets the repair, a
    /// `const` local the hint to declare it `mut`.
    fn warnTake(self: *Pass, function: typed.Function, id: typed.NodeId, node: typed.Node, receiver: []const u8) std.mem.Allocator.Error!bool {
        const owner = @backingInt(node.data.buffer_operation.owner);
        const place = (try self.takePlace(function, owner)) orelse return false;
        const root = function.scope.locals[place.slot];
        if (root.ownership.view or root.usage.temporary or root.ty.capabilityIndex() != null) return false;
        // A parameter's place outlives the call: `take` would leave the default behind in the caller's storage.
        if (root.origin != .local or !try self.owningSource(function, place.slot)) return false;
        if (!self.takeable(node.ty)) return false;
        const copy_span = node.span;
        // In a loop the place is read again on the next iteration, whatever follows the copy in the text.
        if (try self.inLoopOutside(function, root, copy_span)) return false;
        if (!try self.placeUnread(function, id, place, copy_span)) return false;
        if (try self.viewedAnywhere(function, place.slot, place.chain.slots[0..place.chain.len])) return false;
        if (try self.payloadView(function, place.slot, copy_span)) return false;
        if (try self.mutArgumentBeside(function, id, place.slot)) return false;
        if (root.mutable) {
            const message = try std.fmt.allocPrint(self.memory, "`{s}` is not read again, so `take(mut {s})` moves it out and leaves the default behind", .{ receiver, receiver });
            const text = try std.fmt.allocPrint(self.memory, "take(mut {s})", .{receiver});
            try self.sink.appendFix(.{ .severity = .warning, .code = code, .span = copy_span, .message = message }, .{ .span = copy_span, .text = text });
            return true;
        }
        // A `const` local needs two edits, the copy and the `const` word of its declaration, applied together. A declaration
        // with no such word (a loop variable, one name of several) is the hint.
        if (take_repair.constWord(self.src.bytes, root.declaration, root.name)) |word| {
            const message = try std.fmt.allocPrint(self.memory, "`{s}` is not read again, so `take(mut {s})` moves it out and leaves the default behind, and `{s}` is declared `mut`", .{ receiver, receiver, root.name });
            const text = try std.fmt.allocPrint(self.memory, "take(mut {s})", .{receiver});
            try self.sink.appendFix(.{ .severity = .warning, .code = code, .span = copy_span, .message = message }, .{ .span = copy_span, .text = text });
            const last = &self.sink.items.items[self.sink.items.items.len - 1];
            last.provenance.fix.?.more = try self.memory.dupe(diagnostic.Edit, &.{take_repair.mutEdit(word)});
            return true;
        }
        const message = try std.fmt.allocPrint(self.memory, "`{s}` is not read again: declare `{s}` with `mut`, then `take(mut {s})` moves it out", .{ receiver, root.name, receiver });
        try self.sink.items.append(self.sink.allocator, .{ .severity = .warning, .code = move_code, .span = copy_span, .message = message });
        return true;
    }

    /// Whether a local of `function` that no statement stores into, the payload a `match`, an `is` test or a bind-or-else binds
    /// (`const at = sc.at_v else: ...`), may borrow `reference` and still be live where the copy at `copy_span` stands.
    /// `viewedAnywhere` finds a view by its initializer and takes such a local, which has none, for an owner. The checker refuses a
    /// `take` of the place while the payload is read after it, or while a `match` around the copy holds a view of the payload
    /// (`const vgs = level_constant(at) else:` holds `at` to the end of its block): `E_SINGLE_OWNER_OVERLAP`. A payload whose last
    /// read is before the copy, as in `if framed.watch is Some(watch): ... take(mut framed.user)`, is over.
    fn payloadView(self: *Pass, function: typed.Function, reference: usize, copy_span: source.Span) std.mem.Allocator.Error!bool {
        for (function.scope.locals, 0..) |other, slot| {
            if (slot == reference or other.origin != .local or isTemporary(other)) continue;
            // A payload bound after the copy borrows nothing yet.
            if (other.declaration.start > copy_span.start) continue;
            if (!other.ownership.view and !return_borrow.managed(self.program.records, other.ty)) continue;
            if (try self.stored(function, slot)) continue;
            if (!try self.patternBorrowsFrom(function, slot, reference)) continue;
            if (try self.usedAfter(function, slot, copy_span) or try self.heldByMatch(function, slot, copy_span)) return true;
        }
        return false;
    }

    /// Whether a `match` statement around the copy at `copy_span` reads the local `slot` in its scrutinee: the match holds it
    /// until its arm ends.
    fn heldByMatch(self: *Pass, function: typed.Function, slot: usize, copy_span: source.Span) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| self.program.statements[@backingInt(value)],
                .expression => continue,
            };
            const match = switch (statement.data) {
                .match => |value| value,
                else => continue,
            };
            if (inside(statement.span, copy_span) and try self.mentions(match.value, slot)) return true;
        }
        return false;
    }

    /// Whether a statement of `function` initializes or assigns the local `slot`.
    fn stored(self: *Pass, function: typed.Function, slot: usize) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const store = switch (self.program.statements[@backingInt(statement)].data) {
                .initialize => |value| value,
                .assign => |value| value,
                else => continue,
            };
            if (@backingInt(store.slot) == slot) return true;
        }
        return false;
    }

    /// The local, the temporaries and the kind of path (fields only, or an element somewhere) of a copy's operand when it is
    /// a field or element place of one named local.
    /// Whether the copy `id` is an argument of a direct call another argument of which passes the local `slot` `mut`
    /// (`keep(mut state, copy(state.name))`, FR67): `take(mut state.name)` there would change `state` while the call holds
    /// it, which M5 refuses, so the copy stays.
    fn mutArgumentBeside(self: *Pass, function: typed.Function, id: typed.NodeId, slot: usize) std.mem.Allocator.Error!bool {
        const argument = switch (self.contexts.get(id)) {
            .call_argument => |value| value,
            else => return false,
        };
        const node = self.program.nodes[@backingInt(argument.call)];
        if (node.data != .call or @backingInt(argument.function) >= self.program.functions.len) return false;
        const mutates = self.program.functions[@backingInt(argument.function)].signature.declared_mutates;
        for (node.data.call.arguments, 0..) |other, position| {
            if (position == argument.position) continue;
            if (std.mem.indexOfScalar(u16, mutates, @intCast(position)) == null) continue;
            const root = rootLocal(self.program, other, 0) orelse continue;
            if ((try self.rootSlot(function, root)) == slot) return true;
        }
        return false;
    }

    fn takePlace(self: *Pass, function: typed.Function, owner: usize) std.mem.Allocator.Error!?TakePlace {
        var chain: FieldChain = .{};
        var path: [8]usize = undefined;
        var path_len: usize = 0;
        var slot = owner;
        var fields = true;
        var depth: usize = 0;
        var seen_step = false;
        while (depth < depth_limit) : (depth += 1) {
            if (slot >= function.scope.locals.len) return null;
            // A loop variable or a match binding is a read-only name, not a place `take` can write.
            if (function.scope.locals[slot].origin == .iteration or function.scope.locals[slot].origin == .pattern) return null;
            if (!isTemporary(function.scope.locals[slot])) {
                if (!seen_step) return null;
                std.mem.reverse(usize, path[0..path_len]);
                return .{ .slot = slot, .chain = chain, .fields = fields, .path = path, .path_len = path_len };
            }
            if (chain.len == chain.slots.len) return null;
            chain.slots[chain.len] = slot;
            chain.len += 1;
            var value = (try self.onlyInitializer(function, slot)) orelse return null;
            var inner: usize = 0;
            while (inner < depth_limit) : (inner += 1) {
                switch (self.program.nodes[@backingInt(value)].data) {
                    .block_value => |block| value = block.value,
                    .field => |field| {
                        seen_step = true;
                        if (path_len == path.len) return null;
                        path[path_len] = field.index;
                        path_len += 1;
                        value = field.base;
                    },
                    .index => |index| {
                        if (!self.listType(self.program.nodes[@backingInt(index.base)].ty)) return null;
                        seen_step = true;
                        fields = false;
                        value = index.base;
                    },
                    .buffer_operation => |operation| {
                        if (operation.kind != .read or @backingInt(operation.owner) >= function.scope.locals.len) return null;
                        // `take` reaches a list element, never a dictionary value.
                        if (!self.listType(function.scope.locals[@backingInt(operation.owner)].ty)) return null;
                        seen_step = true;
                        fields = false;
                        slot = @backingInt(operation.owner);
                        break;
                    },
                    .local => |next| {
                        slot = @backingInt(next);
                        break;
                    },
                    else => return null,
                }
            } else return null;
        }
        return null;
    }

    /// Whether a type is a list, the one collection whose elements `take` reaches.
    fn listType(self: *const Pass, ty: typed.Type) bool {
        if (!ty.isAggregate() or ty.recordIndex() >= self.program.records.len) return false;
        const record = self.program.records[ty.recordIndex()];
        return record.isCollection() and record.collection.kind == .list;
    }

    /// Whether `span` sits in a loop that the local `root` is declared outside of, so the loop reaches it again.
    fn inLoopOutside(self: *Pass, function: typed.Function, root: typed.Local, span: source.Span) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| self.program.statements[@backingInt(value)],
                .expression => continue,
            };
            switch (statement.data) {
                .loop, .range_loop => {},
                else => continue,
            }
            if (span.start < statement.span.start or span.end > statement.span.end) continue;
            if (root.declaration.start < statement.span.start) return true;
        }
        return false;
    }

    /// Whether `take` can leave a default behind for a value of this type: a collection, an option, or a record whose
    /// fields all have defaults.
    fn takeable(self: *const Pass, ty: typed.Type) bool {
        if (!ty.isAggregate() or ty.recordIndex() >= self.program.records.len) return false;
        const record = self.program.records[ty.recordIndex()];
        if (record.isCollection() or return_borrow.step(self.program.records, ty) != null) return true;
        if (!record.isRecord() or record.shape.variants != null) return false;
        for (record.fields) |field| if (field.default_value == null) return false;
        return record.fields.len != 0;
    }

    /// Whether nothing reads the place of the copy `copy_id` after it: every later reference to the local is a field
    /// projection that leaves the copied field alone, and the statement that holds the copy reads the place nowhere else.
    /// An element place needs the local unreferenced afterwards.
    fn placeUnread(self: *Pass, function: typed.Function, copy_id: typed.NodeId, place: TakePlace, copy_span: source.Span) std.mem.Allocator.Error!bool {
        var body = try walk.Walker.init(self.memory, self.program, function.scope.body);
        defer body.deinit();
        var parents: ?reads.Body = null;
        defer if (parents) |*built| built.deinit();
        while (try body.next()) |item| {
            switch (item) {
                .statement => |statement_id| {
                    const statement = self.program.statements[@backingInt(statement_id)];
                    const store = switch (statement.data) {
                        .initialize => |value| value,
                        .assign => |value| value,
                        else => continue,
                    };
                    if (@backingInt(store.slot) == place.slot and statement.span.start > copy_span.end) return false;
                },
                .expression => |id| {
                    const node = self.program.nodes[@backingInt(id)];
                    if (!refersTo(node, place.slot)) continue;
                    if (id == copy_id or node.span.end <= copy_span.end) continue;
                    if (!place.fields or node.data != .local) return false;
                    const projected = try self.projection(try self.bodyOf(function, &parents), id);
                    if (!disjoint(place.path[0..place.path_len], projected.fields[0..projected.len])) return false;
                },
            }
        }
        return true;
    }

    /// The field projections above a reference to a local: `row.a.b` read through the `.local` node `id` is `[a, b]`.
    const Projection = struct { fields: [8]usize = undefined, len: usize = 0, whole: bool = false };

    fn projection(self: *Pass, body: *reads.Body, id: typed.NodeId) std.mem.Allocator.Error!Projection {
        _ = self;
        var found: Projection = .{};
        var current = id;
        while (body.parents.get(current)) |parent| {
            const expression = switch (parent) {
                .expression => |value| value,
                .statement => break,
            };
            const field = switch (body.program.nodes[@backingInt(expression)].data) {
                .field => |value| value,
                else => break,
            };
            if (field.base != current or found.len == found.fields.len) break;
            found.fields[found.len] = field.index;
            found.len += 1;
            current = expression;
        }
        found.whole = found.len == 0;
        return found;
    }

    /// Case (ix): `for x in xs` copies each element `x` into storage and `xs` is a local nothing reads after the loop. The
    /// consuming loop `for x in own xs` makes `x` an owned element, so `own x` moves it. The repair has two edits, the
    /// `own` in the header and the one at the copy; it holds when `xs` is owned and dead after the loop, nothing else in
    /// the loop reads `xs`, `x` is not read after the copy, and no loop around this one runs it twice.
    fn warnLoopMove(self: *Pass, function: typed.Function, id: typed.NodeId, node: typed.Node) std.mem.Allocator.Error!bool {
        if (function.type_arguments.len != 0) return false;
        const position: enum { moved, returned } = switch (self.contexts.get(id)) {
            .moved => .moved,
            .returned => .returned,
            else => return false,
        };
        if (try waived(self.src, node.span)) return false;
        const receiver = receiverText(self.src, node.span) orelse return false;
        var element = @backingInt(node.data.buffer_operation.owner);
        // A copy of a record or a list reads the element through a compiler temporary (`<collection> = reading`): the loop that
        // binds the element is found through it, and only for a call's list (FR25), where the copy must be of the element itself.
        // The loop variable is found first, from the temporary's own initializer (indexed), and the loop only then: most copies of a
        // temporary are of something else, and the search for a loop walks the body.
        const header = if (function.scope.locals[element].origin == .iteration)
            (try self.iterationHeader(function, element)) orelse return false
        else blk: {
            if (!isName(receiver)) return false;
            const bound = (try self.elementOf(function, element)) orelse return false;
            if (!std.mem.eql(u8, receiver, function.scope.locals[bound].name)) return false;
            const through = (try self.iterationHeader(function, bound)) orelse return false;
            if (!through.fresh) return false;
            element = bound;
            break :blk through;
        };
        if (!header.whole) return false;
        // `for i, x in enumerate(xs)` is not a loop over `xs`: `own` goes nowhere in it, and in front of the call it is
        // `E_ITERATION` (FR21).
        if (!iteratesDirectly(self.src, self.program.nodes[@backingInt(header.source)].span)) return false;
        if (header.fresh) return self.moveFreshElement(function, id, node, .{ .element = element, .header = header, .position = position == .returned });
        const list = function.scope.locals[header.list];
        if (list.ownership.view or isTemporary(list) or list.ty.capabilityIndex() != null) return false;
        if (list.origin != .local and list.origin != .parameter) return false;
        if (!try self.owningSource(function, header.list)) return false;
        const loop_span = self.program.statements[@backingInt(header.loop)].span;
        if (try self.usedAfter(function, header.list, loop_span)) return false;
        if (try self.viewedAnywhere(function, header.list, &.{ header.collection, element })) return false;
        // Nothing else in the loop reads the list or the element after the copy, and no loop around runs the move twice.
        if (try self.readInside(function, header.list, loop_span, header.source)) return false;
        if (try self.usedAfter(function, element, node.span)) return false;
        if (try self.viewedAnywhere(function, element, &.{})) return false;
        const outer = try self.insideLoop(function, header.loop);
        if (outer != null and outer.? != header.loop and !(list.declaration.start >= self.program.statements[@backingInt(outer.?)].span.start)) return false;
        const place: Receiver = .{ .local = function.scope.locals[element], .slot = element, .direct = true, .uncertain_root = false };
        if (try self.heldAround(function, place, id, .named)) return false;
        const replacement = switch (position) {
            .moved => try std.fmt.allocPrint(self.memory, "own {s}", .{receiver}),
            .returned => receiver,
        };
        const name = function.scope.locals[element].name;
        const message = try std.fmt.allocPrint(
            self.memory,
            "`{s}` is not used after the loop, so `for {s} in own {s}` makes `{s}` an owned element and the copy becomes a move",
            .{ list.name, name, list.name, receiver },
        );
        try self.sink.appendFix(.{ .severity = .warning, .code = code, .span = node.span, .message = message }, .{ .span = .{ .start = header.insert, .end = header.insert }, .text = "own " });
        const last = &self.sink.items.items[self.sink.items.items.len - 1];
        last.provenance.fix.?.more = try self.memory.dupe(diagnostic.Edit, &.{.{ .span = node.span, .text = replacement }});
        return true;
    }

    /// The loop that takes a call's list, the element it binds and whether the copy is returned or failed (a bare name) rather
    /// than moved into a store (`own` name).
    const FreshMove = struct { element: usize, header: IterationHeader, position: bool };

    /// Case (ix) for a list a call returns (F-16, FR25): `for x in own CALL():` takes the list, which nothing else names, so
    /// each `x` owns its element and the copy of it becomes a move. The call is one whose result is not lent by an argument
    /// (`owningValue`, the checker's own test), the loop reads its list directly, and the element is neither read after the
    /// copy, viewed, nor moved in a loop that runs it twice (`heldAround`). The list has no name to read, so nothing else
    /// of case (ix) applies. Any other shape keeps the `W_COPY_MOVE` hint (`warnLoopHint`).
    fn moveFreshElement(self: *Pass, function: typed.Function, id: typed.NodeId, node: typed.Node, move: FreshMove) std.mem.Allocator.Error!bool {
        const element = move.element;
        const receiver = receiverText(self.src, node.span) orelse return false;
        if (try self.usedAfter(function, element, node.span)) return false;
        if (try self.viewedAnywhere(function, element, &.{})) return false;
        const place: Receiver = .{ .local = function.scope.locals[element], .slot = element, .direct = true, .uncertain_root = false };
        if (try self.heldAround(function, place, id, .loop_element)) return false;
        const call = self.src.text(self.program.nodes[@backingInt(move.header.source)].span);
        const name = function.scope.locals[element].name;
        const message = try std.fmt.allocPrint(
            self.memory,
            "the list `{s}` returns is named by nothing else, so `for {s} in own {s}` makes `{s}` an owned element and the copy becomes a move",
            .{ call, name, call, name },
        );
        const replacement = if (move.position) receiver else try std.fmt.allocPrint(self.memory, "own {s}", .{receiver});
        try self.sink.appendFix(.{ .severity = .warning, .code = code, .span = node.span, .message = message }, .{ .span = .{ .start = move.header.insert, .end = move.header.insert }, .text = "own " });
        const last = &self.sink.items.items[self.sink.items.items.len - 1];
        last.provenance.fix.?.more = try self.memory.dupe(diagnostic.Edit, &.{.{ .span = node.span, .text = replacement }});
        return true;
    }

    /// Where the loop that binds the iteration local `element` takes its list: the loop, the compiler temporary that
    /// holds the list, the named local it reads, the expression node that reads it, and the byte where an `own` goes.
    const IterationHeader = struct { loop: typed.StatementId, collection: usize, list: usize, source: typed.NodeId, insert: usize, whole: bool = true, fresh: bool = false };

    /// The header of the loop that binds `element` from a named local list, or null for any other source.
    fn iterationHeader(self: *Pass, function: typed.Function, element: usize) std.mem.Allocator.Error!?IterationHeader {
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const loop = switch (self.program.statements[@backingInt(statement)].data) {
                .loop => |value| value,
                else => continue,
            };
            const items = switch (self.program.statements[@backingInt(loop.body)].data) {
                .block => |value| value,
                else => continue,
            };
            const read = for (items) |child| {
                const store = switch (self.program.statements[@backingInt(child)].data) {
                    .initialize => |value| value,
                    else => continue,
                };
                if (@backingInt(store.slot) == element) break store.value;
            } else continue;
            const collection = switch (self.program.nodes[@backingInt(read)].data) {
                .buffer_operation => |operation| if (operation.kind == .read) @backingInt(operation.owner) else continue,
                else => continue,
            };
            const source_node = (try self.onlyInitializer(function, collection)) orelse return null;
            // The list is a local or a field path of one; a call result has no name to consume.
            var origin = source_node;
            var whole = true;
            var steps: usize = 0;
            while (steps < depth_limit) : (steps += 1) switch (self.program.nodes[@backingInt(origin)].data) {
                .field => |field| {
                    whole = false;
                    origin = field.base;
                },
                .block_value => |block| origin = block.value,
                else => break,
            };
            const declaration = function.scope.locals[element].declaration;
            const insert = inSource(self.src, declaration.end) orelse return null;
            const named = switch (self.program.nodes[@backingInt(origin)].data) {
                .local => |slot| @backingInt(slot),
                // A fresh list has no name to consume: the hint says to bind it first.
                .call => if (whole and try self.owningValue(function, origin, 0))
                    return .{ .loop = statement, .collection = collection, .list = collection, .source = source_node, .insert = insert, .fresh = true }
                else
                    return null,
                else => return null,
            };
            if (named >= function.scope.locals.len or isTemporary(function.scope.locals[named])) return null;
            return .{ .loop = statement, .collection = collection, .list = named, .source = source_node, .insert = insert, .whole = whole };
        }
        return null;
    }

    /// Whether the local `slot` is referred to inside `span`, other than by the node `except`.
    fn readInside(self: *Pass, function: typed.Function, slot: usize, span: source.Span, except: typed.NodeId) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| {
            const id = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            if (id == except) continue;
            const node = self.program.nodes[@backingInt(id)];
            if (!refersTo(node, slot)) continue;
            if (node.span.start >= span.start and node.span.end <= span.end) return true;
        }
        return false;
    }

    /// Whether local `slot` is read anywhere inside `span`.
    fn readWithin(self: *Pass, function: typed.Function, slot: usize, span: source.Span) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| {
            const id = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            const node = self.program.nodes[@backingInt(id)];
            if (refersTo(node, slot) and node.span.start >= span.start and node.span.end <= span.end) return true;
        }
        return false;
    }

    /// The store a copied key belongs to, and the copy.
    const KeyStore = struct { store: typed.NodeId, copy: typed.NodeId };

    /// Case (vi): the copy is the key of `d[copy(k)] = v` or of `sets.add(mut s, copy(k))`. The store copies a key
    /// written as a place only when it is new, so the copy-free `d[k] = v` or `sets.include(mut s, k)` stores the same
    /// entries. It holds only when the key is a plain place of a plain value (never a slice or a call result), when no
    /// operand of the store writes the key's root, and when the store is written in exactly the form that borrows its key.
    /// A set call is rewritten whole, with its head renamed, and the new call is `rewrite`.
    fn keyRepair(self: *Pass, function: typed.Function, place: Receiver, key: KeyStore, writes: []const Write) std.mem.Allocator.Error!?KeyRepair {
        if (function.type_arguments.len != 0) return null;
        const store_node = self.program.nodes[@backingInt(key.store)];
        // The standard library's own bodies spell the method forms its homes lower to; they are not guest code to repair.
        if (std.mem.startsWith(u8, self.src.locate(store_node.span.start).path, "@stdlib/")) return null;
        const copy_node = self.program.nodes[@backingInt(key.copy)];
        const operation = store_node.data.buffer_operation;
        if (operation.arguments.len != 2 or @backingInt(operation.owner) >= function.scope.locals.len) return null;
        const owner_type = function.scope.locals[@backingInt(operation.owner)].ty;
        if (!owner_type.isAggregate()) return null;
        const schema = self.program.records[owner_type.recordIndex()];
        if (schema.collection.kind != .dictionary) return null;
        if (!(try self.keyIsPlace(function, key.copy))) return null;
        // A slice expression is a view the store refuses; a named local that holds a view is read and copied like any other.
        const operand = copy_node.data.buffer_operation.owner;
        if (std.mem.startsWith(u8, function.scope.locals[@backingInt(operand)].name, "<") and try self.sliceCopy(function, key.copy)) return null;
        if (self.conflicts(place, store_node.span, copy_node.span, writes)) return null;
        const receiver = receiverText(self.src, copy_node.span) orelse return null;
        if (typed.isSet(schema)) {
            const call = (try setIncludeCall(self.memory, self.src, store_node.span, copy_node.span, receiver)) orelse return null;
            const message = try std.fmt.allocPrint(self.memory, "`sets.include` copies `{s}` only when the set does not hold it yet, so pass `{s}` itself rather than a copy", .{ receiver, receiver });
            return .{ .message = message, .rewrite = call };
        }
        if (operation.kind == .setdefault) {
            if (!setdefaultKey(self.src, copy_node.span, store_node.span)) return null;
            const message = try std.fmt.allocPrint(self.memory, "`dicts.setdefault` copies `{s}` only when it is a new key, so pass `{s}` itself rather than a copy", .{ receiver, receiver });
            return .{ .message = message, .rewrite = null };
        }
        if (!indexStore(self.src, copy_node.span, store_node.span)) return null;
        const message = try std.fmt.allocPrint(self.memory, "a dictionary store copies `{s}` only when it is a new key, so write `{s}` itself rather than a copy", .{ receiver, receiver });
        return .{ .message = message, .rewrite = null };
    }

    /// A key repair: its message, and the whole call it replaces when the copy alone is not the edit.
    const KeyRepair = struct { message: []const u8, rewrite: ?[]const u8 };

    /// Whether the key a copy duplicates is a place the store may borrow (what the checker marks as a borrowed key): a
    /// local, a field or an element, not a call, an operator or a slice.
    fn keyIsPlace(self: *Pass, function: typed.Function, copy_id: typed.NodeId) std.mem.Allocator.Error!bool {
        const slot = @backingInt(self.program.nodes[@backingInt(copy_id)].data.buffer_operation.owner);
        if (slot >= function.scope.locals.len) return false;
        if (!std.mem.startsWith(u8, function.scope.locals[slot].name, "<")) return true;
        const value = (try self.onlyInitializer(function, slot)) orelse return false;
        return self.placeShape(function, value, 0);
    }

    fn placeShape(self: *Pass, function: typed.Function, id: typed.NodeId, depth: usize) bool {
        if (depth > depth_limit) return false;
        const node = self.program.nodes[@backingInt(id)];
        if (node.view or node.own) return false;
        return switch (node.data) {
            .local, .field, .index => true,
            .block_value => |block| self.placeShape(function, block.value, depth + 1),
            .buffer_operation => |read| blk: {
                if (read.kind != .read or @backingInt(read.owner) >= function.scope.locals.len) break :blk false;
                const owner = function.scope.locals[@backingInt(read.owner)].ty;
                break :blk owner.isAggregate() and self.program.records[owner.recordIndex()].collection.kind != .string;
            },
            else => false,
        };
    }

    /// One place a function changes or moves, with the expression's span, so
    /// a copy remains when another operand would invalidate its borrowed form.
    const Write = struct { root: usize, span: source.Span };

    /// Where a copy's receiver lives: the local it borrows and whether the
    /// receiver is that local itself. A field or element receiver lowers through
    /// a compiler temporary, which is not a name the source spelled, so the
    /// place is the temporary's owner root instead.
    const Receiver = struct {
        local: typed.Local,
        slot: usize,
        direct: bool,
        /// A named loan can alias another root, so argument effects need a
        /// stronger proof than comparing its local slot with a written slot.
        uncertain_root: bool,
    };

    /// Resolve the receiver of a copy. A temporary is followed through its one
    /// initializer to the field, index or local it was bound to; the copy-free
    /// form then hands over the place the source named.
    fn receiverOf(self: *Pass, function: typed.Function, slot: usize) std.mem.Allocator.Error!?Receiver {
        const local = function.scope.locals[slot];
        if (!local.usage.temporary) return .{
            .local = local,
            .slot = slot,
            .direct = true,
            .uncertain_root = local.origin != .parameter and !try self.owningSource(function, slot),
        };
        if (!std.mem.startsWith(u8, local.name, "<")) return null;
        if (local.ownership.view) return null;
        const root = (try self.rootSlot(function, slot)) orelse return null;
        const owner = function.scope.locals[root];
        if (owner.ownership.view or owner.usage.temporary) return null;
        if (std.mem.startsWith(u8, owner.name, "<")) return null;
        return .{
            .local = owner,
            .slot = root,
            .direct = try self.wholeReceiver(function, slot),
            .uncertain_root = owner.origin != .parameter and !try self.owningSource(function, root),
        };
    }

    /// Where the key of a store lives (case vi): the named local it is, or the named local a field or element
    /// reaches. Unlike `receiverOf`, the root may be a view, since the store only reads the key. A key that does not
    /// root at a named local, such as a call result, has no place.
    fn keyReceiver(self: *Pass, function: typed.Function, slot: usize) std.mem.Allocator.Error!?Receiver {
        const local = function.scope.locals[slot];
        // A loop variable is a binding the lowering declares, so it is a named place here although its usage is a temporary's.
        if (!std.mem.startsWith(u8, local.name, "<")) return .{ .local = local, .slot = slot, .direct = true, .uncertain_root = false };
        const value = (try self.onlyInitializer(function, slot)) orelse return null;
        const root = (try self.keyRoot(function, value, 0)) orelse return null;
        const owner = function.scope.locals[root];
        return .{ .local = owner, .slot = root, .direct = false, .uncertain_root = false };
    }

    /// The named local a key expression reads from: through fields, elements and the temporaries lowering rooted.
    fn keyRoot(self: *Pass, function: typed.Function, id: typed.NodeId, depth: usize) std.mem.Allocator.Error!?usize {
        if (depth > depth_limit) return null;
        return switch (self.program.nodes[@backingInt(id)].data) {
            .local => |slot| try self.namedSlot(function, @backingInt(slot), depth),
            .field => |field| try self.keyRoot(function, field.base, depth + 1),
            .index => |index| try self.keyRoot(function, index.base, depth + 1),
            .block_value => |block| try self.keyRoot(function, block.value, depth + 1),
            .buffer_operation => |read| if (read.kind == .read) try self.namedSlot(function, @backingInt(read.owner), depth) else null,
            else => null,
        };
    }

    /// `slot` when it is a binding the program or the loop lowering named, else the named slot its one initializer reads.
    fn namedSlot(self: *Pass, function: typed.Function, slot: usize, depth: usize) std.mem.Allocator.Error!?usize {
        if (slot >= function.scope.locals.len) return null;
        if (!std.mem.startsWith(u8, function.scope.locals[slot].name, "<")) return slot;
        const initializer = (try self.onlyInitializer(function, slot)) orelse return null;
        return self.keyRoot(function, initializer, depth + 1);
    }

    /// Whole wrapper and record copies also use receiver temporaries. Follow
    /// local aliases without treating that lowering as a field-level borrow.
    fn wholeReceiver(self: *Pass, function: typed.Function, slot: usize) std.mem.Allocator.Error!bool {
        var current = slot;
        var remaining: usize = depth_limit;
        while (remaining != 0) : (remaining -= 1) {
            if (current >= function.scope.locals.len) return false;
            if (!isTemporary(function.scope.locals[current])) return true;
            const value = (try self.onlyInitializer(function, current)) orelse return false;
            current = switch (self.program.nodes[@backingInt(value)].data) {
                .local => |local| @backingInt(local),
                else => return false,
            };
        }
        return false;
    }

    /// The named local a place roots at, following the compiler temporaries a
    /// field, element or slice access lowers through.
    fn rootSlot(self: *Pass, function: typed.Function, slot: usize) std.mem.Allocator.Error!?usize {
        var current = slot;
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            if (current >= function.scope.locals.len) return null;
            const local = function.scope.locals[current];
            if (!local.usage.temporary) return current;
            const initializer = (try self.onlyInitializer(function, current)) orelse return null;
            current = rootLocal(self.program, initializer, 0) orelse return null;
        }
        return null;
    }

    /// The value one temporary was initialized with, when exactly one store
    /// writes it.
    fn onlyInitializer(self: *Pass, function: typed.Function, slot: usize) std.mem.Allocator.Error!?typed.NodeId {
        if (slot >= function.scope.locals.len) return soleInitializer(self.memory, self.program, function, slot);
        if (self.initializers) |built| if (built.function == function.id) return built.sole(slot);
        try self.indexInitializers(function);
        return self.initializers.?.sole(slot);
    }

    /// Every statement and expression of `function`'s body in walk order, walked once per function: the repairs ask many
    /// questions of one body, and each used to walk it again. The slice is valid until the pass moves to another function.
    fn bodyItems(self: *Pass, function: typed.Function) std.mem.Allocator.Error![]const walk.Item {
        if (self.items) |cached| {
            if (cached.function == function.id) return cached.list;
            self.memory.free(cached.list);
            self.items = null;
        }
        var list: std.ArrayList(walk.Item) = .empty;
        defer list.deinit(self.memory);
        var body = try walk.Walker.init(self.memory, self.program, function.scope.body);
        defer body.deinit();
        while (try body.next()) |item| try list.append(self.memory, item);
        const owned = try self.memory.dupe(walk.Item, list.items);
        self.items = .{ .function = function.id, .list = owned };
        return owned;
    }

    /// Index every initialization of `function` with one walk of its body. The index belongs
    /// to the pass from the allocation on, so a walk that fails midway leaves nothing to leak.
    fn indexInitializers(self: *Pass, function: typed.Function) std.mem.Allocator.Error!void {
        if (self.initializers) |built| built.deinit(self.memory);
        self.initializers = null;
        const entries = try self.memory.alloc(Initializers.Entry, function.scope.locals.len);
        @memset(entries, .{});
        self.initializers = .{ .function = function.id, .entries = entries };
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const store = switch (self.program.statements[@backingInt(statement)].data) {
                .initialize => |value| value,
                else => continue,
            };
            const slot = @backingInt(store.slot);
            if (slot >= entries.len) continue;
            if (entries[slot].count == 0) entries[slot].value = store.value;
            entries[slot].count +|= 1;
        }
    }

    /// Whether a value of type `ty`, read from a place of type `base`, has no managed part: the ownership check refuses `own`
    /// on it (`E_OWN_MARKER`, "a scalar has no managed storage to transfer"), so a move of it is written bare. The test is
    /// the check's own, `owned_types.isOwned` over the program's owned types, with the three values it still lets carry the
    /// marker (`writtenMarker`): a `@linear` owner or a field of one, and a value that held a capability before 5C.
    fn noManagedPart(self: *Pass, ty: typed.Type, base: typed.Type) std.mem.Allocator.Error!bool {
        const records = self.program.records;
        if (typed.linear(ty, records) or typed.linear(base, records) or provider_types.holdsFormerLeaf(records, ty)) return false;
        if (self.owned == null) self.owned = try owned_types.table(self.memory, self.program);
        return !owned_types.isOwned(self.owned.?, ty);
    }

    /// Whether the copied value is a plain managed value a borrow or a move may
    /// hand over: its owner is not a view or a temporary, and its type is not a
    /// capability, a resource or a borrowed view.
    fn plainValue(self: *const Pass, owner: typed.Local, ty: typed.Type, store_key: bool) bool {
        // A store's key may be a view or a lowering-declared binding such as a loop variable: the store only reads it.
        if (!store_key and (owner.ownership.view or owner.usage.temporary)) return false;
        if (std.mem.startsWith(u8, owner.name, "<")) return false;
        if (ty.capabilityIndex() != null or ty.isFile()) return false;
        if (typed.moveOnly(ty, self.program.records)) return false;
        return true;
    }

    /// Every mutation or move in one function body, keyed by its root local:
    /// declared `mut` and `own` arguments of direct calls and callbacks, and
    /// collection operations that mutate their owner.
    fn writesOf(self: *Pass, function: typed.Function) std.mem.Allocator.Error![]Write {
        var writes: std.ArrayList(Write) = .empty;
        for (try self.bodyItems(function)) |item| {
            const id = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            const node = self.program.nodes[@backingInt(id)];
            switch (node.data) {
                .call => |call| {
                    if (@backingInt(call.function) >= self.program.functions.len) continue;
                    const callee = self.program.functions[@backingInt(call.function)];
                    try self.argumentWrites(function, &writes, call.arguments, .{
                        .mutates = callee.signature.declared_mutates,
                        .own = callee.scope.own_parameters,
                        .span = node.span,
                    });
                },
                .invoke => |invoke| {
                    const signature = @import("callables.zig").signature(self.program.nodes[@backingInt(invoke.callee)].ty, self.program.records) orelse continue;
                    try self.argumentWrites(function, &writes, invoke.arguments, .{
                        .mutates = signature.mutates,
                        .own = signature.own,
                        .span = node.span,
                    });
                },
                .buffer_operation => |operation| if (operation.kind.mutates()) {
                    const slot = (try self.rootSlot(function, @backingInt(operation.owner))) orelse continue;
                    try writes.append(self.memory, .{ .root = slot, .span = node.span });
                },
                else => {},
            }
        }
        return writes.items;
    }

    const ArgumentEffects = struct { mutates: []const u16, own: []const bool, span: source.Span };

    fn argumentWrites(self: *Pass, function: typed.Function, writes: *std.ArrayList(Write), arguments: []const typed.NodeId, effects: ArgumentEffects) std.mem.Allocator.Error!void {
        for (arguments, 0..) |argument, position| {
            const takes = position < effects.own.len and effects.own[position];
            const changes = std.mem.indexOfScalar(u16, effects.mutates, @intCast(position)) != null;
            if (!takes and !changes) continue;
            const root = rootLocal(self.program, argument, 0) orelse continue;
            const slot = (try self.rootSlot(function, root)) orelse continue;
            try writes.append(self.memory, .{ .root = slot, .span = effects.span });
        }
    }

    /// Case (i) through a read-only parameter: the callee only reads the
    /// argument, so passing the receiver borrows it exactly as passing its copy
    /// did. The callee must not return a view of that argument, and no other
    /// argument may write the same local.
    fn callRepair(self: *Pass, place: Receiver, receiver: []const u8, copy_span: source.Span, writes: []const Write, argument: anytype) !?[]const u8 {
        const program = self.program;
        if (@backingInt(argument.function) >= program.functions.len) return null;
        const callee = program.functions[@backingInt(argument.function)];
        const position = argument.position;
        if (!reads.parameterReadOnly(program, self.src, argument.function, position)) return null;
        if (callee.signature.return_origin == .unknown) return null;
        if (std.mem.indexOfScalar(u16, return_borrow.effectiveSources(program.records, callee.signature), @intCast(position)) != null) return null;
        // Passing the receiver itself borrows it for the whole call, so nothing
        // the call writes may share the receiver's root: `lst(xs, push(mut xs))`
        // and `swap_first(pins, mut pins)` both need their copy.
        if (self.conflicts(place, program.nodes[@backingInt(argument.call)].span, copy_span, writes)) return null;
        const callee_name = try display_name.spelled(self.memory, callee.name);
        defer display_name.release(self.memory, callee_name, callee.name);
        const message = try std.fmt.allocPrint(self.memory, "`{s}` only reads `{s}`, so pass `{s}` itself rather than a copy", .{
            callee_name, receiver, receiver,
        });
        return message;
    }

    /// Case (i) through a function value: a call through a callable type reads a plain parameter, as a direct call does.
    /// The callable's type says which positions it writes or takes and what its result borrows; its body is unknown, but
    /// a plain parameter is lent for the call and cannot be kept.
    fn invokeRepair(self: *Pass, place: Receiver, receiver: []const u8, copy_span: source.Span, writes: []const Write, argument: @FieldType(Context, "invoke_argument")) !?[]const u8 {
        const program = self.program;
        const call = program.nodes[@backingInt(argument.call)];
        const callee = program.nodes[@backingInt(call.data.invoke.callee)];
        const callable = @import("callables.zig").signature(callee.ty, program.records) orelse return null;
        const position = argument.position;
        if (position >= callable.parameters.len) return null;
        if (std.mem.indexOfScalar(u16, callable.mutates, @intCast(position)) != null) return null;
        if (position < callable.own.len and callable.own[position]) return null;
        const parameter = callable.parameters[position];
        if (parameter.capabilityIndex() != null or parameter.isFile() or typed.moveOnly(parameter, program.records)) return null;
        switch (callable.return_origin) {
            .unknown => return null,
            .params => |sources| if (std.mem.indexOfScalar(u16, sources, @intCast(position)) != null) return null,
            .fresh => {},
        }
        if (self.conflicts(place, call.span, copy_span, writes)) return null;
        const message = try std.fmt.allocPrint(self.memory, "`{s}` only reads `{s}`, so pass `{s}` itself rather than a copy", .{ self.src.text(callee.span), receiver, receiver });
        return message;
    }

    /// Whether the copy `id` is the key argument of the standard library's `dicts.add` or `dicts.append_to`, which borrow it.
    fn libraryKey(self: *const Pass, id: typed.NodeId) bool {
        const argument = switch (self.contexts.get(id)) {
            .call_argument => |value| value,
            else => return false,
        };
        if (argument.position != 1 or @backingInt(argument.function) >= self.program.functions.len) return false;
        const callee = self.program.functions[@backingInt(argument.function)];
        if (!std.mem.startsWith(u8, callee.name, "dicts::add[") and !std.mem.startsWith(u8, callee.name, "dicts::append_to[")) return false;
        return std.mem.eql(u8, self.src.locate(callee.declaration.start).path, "@stdlib/dicts.selka");
    }

    /// Case (vi) for `dicts.add` and `dicts.append_to`: the key is a plain place that the call does not write, so passing
    /// it itself gives the same entries, copied only when the key is new.
    fn libraryKeyRepair(self: *Pass, function: typed.Function, place: Receiver, copy_span: source.Span, writes: []const Write, id: typed.NodeId) std.mem.Allocator.Error!?[]const u8 {
        if (function.type_arguments.len != 0) return null;
        if (std.mem.startsWith(u8, self.src.locate(copy_span.start).path, "@stdlib/")) return null;
        const argument = self.contexts.get(id).call_argument;
        if (!(try self.keyIsPlace(function, id))) return null;
        const slot = @backingInt(self.program.nodes[@backingInt(id)].data.buffer_operation.owner);
        if (std.mem.startsWith(u8, function.scope.locals[slot].name, "<") and try self.sliceCopy(function, id)) return null;
        if (self.conflicts(place, self.program.nodes[@backingInt(argument.call)].span, copy_span, writes)) return null;
        const callee = self.program.functions[@backingInt(argument.function)];
        const receiver = receiverText(self.src, copy_span) orelse return null;
        const name = if (std.mem.startsWith(u8, callee.name, "dicts::add[")) "dicts.add" else "dicts.append_to";
        const message = try std.fmt.allocPrint(self.memory, "`{s}` copies `{s}` only when it is a new key, so pass `{s}` itself rather than a copy", .{ name, receiver, receiver });
        return message;
    }

    /// Case (iii): a `const` bound to a copy of a parameter's place, or of a field or element of a parameter or
    /// of a local, binds a borrow once the copy goes (R1). The copy-free form is sound when the binding is only
    /// read while its source does not change. This proof conservatively handles
    /// plain parameters and projections; whole owned locals use the move proof.
    fn constBindingRepair(self: *Pass, body: *reads.Body, place: Receiver, copy_id: typed.NodeId, receiver: []const u8, statement: typed.StatementId) std.mem.Allocator.Error!?[]const u8 {
        const function = body.function;
        // An alias of a declared loan can be invalidated by its lender even
        // when no write names the alias itself. Withhold this borrow repair
        // unless the root is a parameter or independently owned storage.
        if (place.uncertain_root) return null;
        const store = switch (self.program.statements[@backingInt(statement)].data) {
            .initialize => |value| value,
            else => return null,
        };
        if (store.unpack != null or @backingInt(store.slot) >= function.scope.locals.len) return null;
        const destination = function.scope.locals[@backingInt(store.slot)];
        if (destination.mutable or destination.origin != .local or destination.ownership.view or destination.usage.temporary) return null;
        if (std.mem.startsWith(u8, destination.name, "<")) return null;
        if (place.direct) switch (place.local.origin) {
            .parameter => if (!plainParameter(self.program, function, place.slot)) return null,
            // A whole local the function owns: the binding borrows it read-only (B9), and the quiet check below refuses any
            // write or move of it while the binding is live.
            .local => if (place.local.ownership.view or isTemporary(place.local)) return null,
            else => return null,
        } else switch (place.local.origin) {
            .local => {},
            // A `mut` parameter is caller storage the binding reads through: the quiet check below refuses any write to it.
            .parameter => if (!plainParameter(self.program, function, place.slot) and !mutParameter(self.program, function, place.slot)) return null,
            else => return null,
        }
        if (try self.sliceCopy(function, copy_id)) return null;
        const span = self.program.statements[@backingInt(statement)].span;
        const end = (try body.bindingEnd(@backingInt(store.slot), span)) orelse return null;
        const copy_span = self.program.nodes[@backingInt(copy_id)].span;
        if (!try body.quietBetween(place.slot, span.start, end, copy_span)) return null;
        const message = try std.fmt.allocPrint(self.memory, "`{s}` only reads `{s}` while it is live, so bind `{s}` itself rather than a copy", .{
            destination.name, receiver, receiver,
        });
        return message;
    }

    /// Whether the operand of a copy is a slice: a view of its source, which a binding does not borrow as a value. The
    /// operand is a compiler temporary whose initializer is followed while it is a temporary or a local; a named local
    /// is an owner, so it is not a slice unless it is a view.
    fn sliceCopy(self: *Pass, function: typed.Function, copy_id: typed.NodeId) std.mem.Allocator.Error!bool {
        var slot = @backingInt(self.program.nodes[@backingInt(copy_id)].data.buffer_operation.owner);
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            if (slot >= function.scope.locals.len) return true;
            const local = function.scope.locals[slot];
            if (local.ownership.view) return true;
            if (!std.mem.startsWith(u8, local.name, "<")) return false;
            const value = (try self.onlyInitializer(function, slot)) orelse return true;
            const node = self.program.nodes[@backingInt(value)];
            if (node.view) return true;
            switch (node.data) {
                .buffer_operation => |operation| return isSliceKind(operation.kind),
                .block_value => |block| {
                    const inner = self.program.nodes[@backingInt(block.value)];
                    if (inner.view) return true;
                    switch (inner.data) {
                        .buffer_operation => |operation| return isSliceKind(operation.kind),
                        .local => |read| slot = @backingInt(read),
                        else => return false,
                    }
                },
                .local => |read| slot = @backingInt(read),
                else => return false,
            }
        }
        return true;
    }

    /// The body parents of `function`, built on first use.
    fn bodyOf(self: *Pass, function: typed.Function, slot: *?reads.Body) std.mem.Allocator.Error!*reads.Body {
        if (slot.* == null) {
            slot.* = try reads.Body.init(self.memory, self.program, self.src, function);
        }
        return &slot.*.?;
    }

    /// Whether every initialization of `slot` produces a value the binding owns:
    /// a call or other fresh result, never a field, element or local the source
    /// value still holds.
    fn owningSource(self: *Pass, function: typed.Function, slot: usize) std.mem.Allocator.Error!bool {
        return self.owningSourceAt(function, slot, 0);
    }

    fn owningSourceAt(self: *Pass, function: typed.Function, slot: usize, depth: usize) std.mem.Allocator.Error!bool {
        if (depth > depth_limit or slot >= function.scope.locals.len) return false;
        const local = function.scope.locals[slot];
        if (local.ownership.view) return false;
        if (local.origin == .parameter) return slot < function.scope.own_parameters.len and function.scope.own_parameters[slot];
        if (local.origin != .local) return false;
        var found = false;
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const store = switch (self.program.statements[@backingInt(statement)].data) {
                .initialize => |value| value,
                .assign => |value| value,
                else => continue,
            };
            if (@backingInt(store.slot) != slot) continue;
            found = true;
            const value = self.program.nodes[@backingInt(store.value)];
            // A field write lowers to `slot = update(<alias of slot>, field = new)`: the local keeps its own storage when each
            // new field value is owned.
            if (value.data == .update) {
                if (!try self.selfUpdate(function, slot, value.data.update, depth)) return false;
                continue;
            }
            if (value.data == .local) {
                if (isTemporary(local)) return false;
                // An unmarked store of a named local borrows it: a `const` alias (B9), or a `mut` local stored more than
                // once from places (4f).
                if (!value.own) return false;
            }
            if (!try self.owningValue(function, store.value, depth + 1)) return false;
        }
        return found;
    }

    /// Whether `update` rebuilds the local `slot` from an alias of itself with owned values in its fields.
    fn selfUpdate(self: *Pass, function: typed.Function, slot: usize, update: @FieldType(@FieldType(typed.Node, "data"), "update"), depth: usize) std.mem.Allocator.Error!bool {
        const base = switch (self.program.nodes[@backingInt(update.base)].data) {
            .local => |alias| @backingInt(alias),
            else => return false,
        };
        if (base >= function.scope.locals.len or !isTemporary(function.scope.locals[base])) return false;
        // The alias is initialized from the local itself, once per field written (the lowering repeats it).
        var body = try walk.Walker.init(self.memory, self.program, function.scope.body);
        defer body.deinit();
        var found = false;
        while (try body.next()) |item| {
            const statement = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const store = switch (self.program.statements[@backingInt(statement)].data) {
                .initialize => |value| value,
                else => continue,
            };
            if (@backingInt(store.slot) != base) continue;
            const aliased = switch (self.program.nodes[@backingInt(store.value)].data) {
                .local => |alias| @backingInt(alias),
                else => return false,
            };
            if (aliased != slot) return false;
            found = true;
        }
        if (!found) return false;
        for (update.fields) |field| if (!try self.owningPayload(function, field.value, depth + 1)) return false;
        return true;
    }

    /// Whether one expression produces a value its binding owns.
    ///
    // twin-drift-ok: this is the `src/core` ownership pass's value-kind list
    // read from `src/`: `src/` cannot import `src/core`, so this module keeps
    // its own conservative copy rather than sharing `matchOwnsTemporary`, and a
    // kind it does not know is not owning.
    fn owningValue(self: *Pass, function: typed.Function, id: typed.NodeId, depth: usize) std.mem.Allocator.Error!bool {
        if (depth > depth_limit) return false;
        const node = self.program.nodes[@backingInt(id)];
        if (node.view) return false;
        return switch (node.data) {
            // A declared borrowed result supplies no owner for this binding.
            .call => |call| if (@backingInt(call.function) < self.program.functions.len)
                self.program.functions[@backingInt(call.function)].signature.return_origin != .unknown and
                    return_borrow.effectiveSources(self.program.records, self.program.functions[@backingInt(call.function)].signature).len == 0
            else
                false,
            .invoke => |invoke| if (@import("callables.zig").signature(self.program.nodes[@backingInt(invoke.callee)].ty, self.program.records)) |signature|
                signature.return_origin == .fresh
            else
                false,
            .variant => |variant| if (variant.value) |payload| self.owningPayload(function, payload, depth + 1) else true,
            .record => |fields| result: {
                for (fields) |field| if (!try self.owningPayload(function, field.value, depth + 1)) break :result false;
                break :result true;
            },
            .array => |values| result: {
                for (values) |value| if (!try self.owningPayload(function, value, depth + 1)) break :result false;
                break :result true;
            },
            .acquire_buffer, .blob, .file_access, .file_method => true,
            // `take(mut place)` and `exchange(mut place, value)` move the place's old value out to the binding, which owns it.
            .place_exchange => true,
            // Concatenation and formatting build a new value (case v's owned locals are mostly these).
            .binary, .format => true,
            .cast, .wrap, .unwrap => |value| self.owningValue(function, value, depth + 1),
            .propagate => |propagate| self.owningValue(function, propagate.value, depth + 1),
            // An explicitly moved whole local supplies its owned storage.
            // The destination binding distinguishes an unmarked const borrow.
            .local => |slot| self.owningSourceAt(function, @backingInt(slot), depth + 1),
            .block_value => |block| self.owningValue(function, block.value, depth + 1),
            .buffer_operation => |operation| switch (operation.kind) {
                .copy,
                .pop,
                .exchange,
                .pop_key,
                .pop_default,
                .decode,
                .from_hex,
                .scalar_count,
                .scalar_count_range,
                .parse_int,
                .parse_float,
                .parse_f32,
                .parse_int_range,
                .parse_float_range,
                .split,
                .splitlines,
                .split_whitespace,
                .to_list,
                => true,
                else => false,
            },
            else => false,
        };
    }

    fn owningPayload(self: *Pass, function: typed.Function, value: typed.NodeId, depth: usize) std.mem.Allocator.Error!bool {
        if (!return_borrow.managed(self.program.records, self.program.nodes[@backingInt(value)].ty)) return true;
        return self.owningValue(function, value, depth);
    }

    /// Whether any write to the receiver's root lies inside `enclosing` and
    /// outside the copy's own lowering: the copy then snapshots a value the
    /// same expression changes, which is exactly what it is for.
    fn conflicts(self: *const Pass, place: Receiver, enclosing: source.Span, copy_span: source.Span, writes: []const Write) bool {
        _ = self;
        for (writes) |write| {
            if (write.root != place.slot and !place.uncertain_root) continue;
            if (!inside(enclosing, write.span)) continue;
            if (inside(copy_span, write.span)) continue;
            return true;
        }
        return false;
    }

    /// Case (ii): a copy that initializes a local is the last use of an owned
    /// local, so the copy-free form moves the value into the same binding.
    /// Case (v): a copy of an owned local or an `own` parameter at its last use, in a position that takes the value over
    /// (a constructor field, a case payload, an `own` argument, a container store, an assignment, a return). The value is
    /// never read again, so `own x` (a bare `x` when returned) moves it and hands over the same bytes. It is refused in a
    /// generic instance, inside a loop the value was not declared in (the move would run again), inside a match or other
    /// statement whose head reads the value (it is held), beside another read of it in the same statement, after which a
    /// later use or a view of it could not check.
    fn moveRepair(self: *Pass, function: typed.Function, place: Receiver, receiver: []const u8, copy_id: typed.NodeId, position: enum { moved, returned }) std.mem.Allocator.Error!?[]const u8 {
        if (function.type_arguments.len != 0) return null;
        if (place.local.ownership.view) return null;
        // A field of a dead local moves with it: `own record.field` consumes the record, which nothing reads again.
        const field = !place.direct;
        const chain = if (field) (try self.fieldPath(function, copy_id)) orelse return null else FieldChain{};
        // A payload binding of a match that consumes a fresh result owns its payload, as a local does.
        const payload = (place.local.origin == .pattern or place.local.origin == .local) and try self.consumingBinding(function, place.slot);
        if (!payload and place.local.origin != .local and place.local.origin != .parameter) return null;
        if (isTemporary(place.local)) return null;
        if (!payload and !try self.owningSource(function, place.slot)) return null;
        const copy_span = self.program.nodes[@backingInt(copy_id)].span;
        if (try self.readsAfterCopy(function, place.slot, copy_span)) return null;
        if (try self.viewedAnywhere(function, place.slot, chain.slots[0..chain.len])) return null;
        if (try self.heldAround(function, place, copy_id, .named)) return null;
        const message = switch (position) {
            .returned => if (field)
                try std.fmt.allocPrint(self.memory, "`{s}` is never used again, so return `own {s}` and the copy becomes a move", .{ place.local.name, receiver })
            else
                try std.fmt.allocPrint(self.memory, "`{s}` is never used again, so return `{s}` itself and the copy becomes a move", .{ receiver, receiver }),
            .moved => if (field)
                try std.fmt.allocPrint(self.memory, "`{s}` is never used again, so pass `own {s}` and the copy becomes a move", .{ place.local.name, receiver })
            else
                try std.fmt.allocPrint(self.memory, "`{s}` is never used again, so pass `own {s}` and the copy becomes a move", .{ receiver, receiver }),
        };
        return message;
    }

    /// Whether `slot` is a payload binding of a `match` that consumes a fresh value (a call, a constructor): the match is
    /// not a borrow of a place, so each binding owns what it binds.
    fn consumingBinding(self: *Pass, function: typed.Function, slot: usize) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const match = switch (self.program.statements[@backingInt(statement)].data) {
                .match => |value| value,
                else => continue,
            };
            for (match.arms) |arm| {
                if (!bindsSlot(arm, slot)) continue;
                if (match.borrowed or match.exclusive) return false;
                return self.freshScrutinee(function, match.value, 0);
            }
        }
        return false;
    }

    /// Whether the `match` scrutinee `id` is a fresh value, whose payload bindings own what they bind: a call whose result is
    /// not declared to borrow, a constructor, a read of a file or a decode (a library function or a capability's method is a
    /// node of its own, not a call), or the block that stages such a call's operands (a slice argument) and ends in it.
    fn freshScrutinee(self: *Pass, function: typed.Function, id: typed.NodeId, depth: usize) std.mem.Allocator.Error!bool {
        if (depth > depth_limit) return false;
        const scrutinee = self.program.nodes[@backingInt(id)];
        return switch (scrutinee.data) {
            // A call whose result is declared to borrow (`from`) still lends its payload (R3).
            .call => |call| @backingInt(call.function) < self.program.functions.len and
                self.program.functions[@backingInt(call.function)].signature.return_origin == .fresh,
            .invoke => |invoke| if (@import("callables.zig").signature(self.program.nodes[@backingInt(invoke.callee)].ty, self.program.records)) |callable|
                callable.return_origin == .fresh
            else
                false,
            .variant, .record => true,
            .block_value => |block| self.freshScrutinee(function, block.value, depth + 1),
            .file_access, .buffer_operation => self.owningValue(function, id, 0),
            else => false,
        };
    }

    /// The compiler temporaries that carry a field path's read.
    const FieldChain = struct { slots: [4]usize = undefined, len: usize = 0 };

    /// The temporaries of the copy `copy_id` when it duplicates a plain field path of a named local (`record.a.b`), with no
    /// element read, slice or cast between: the place a field move names. Null for any other operand.
    fn fieldPath(self: *Pass, function: typed.Function, copy_id: typed.NodeId) std.mem.Allocator.Error!?FieldChain {
        var chain: FieldChain = .{};
        var slot = @backingInt(self.program.nodes[@backingInt(copy_id)].data.buffer_operation.owner);
        var seen_field = false;
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            if (slot >= function.scope.locals.len) return null;
            if (!isTemporary(function.scope.locals[slot])) return if (seen_field) chain else null;
            if (chain.len == chain.slots.len) return null;
            chain.slots[chain.len] = slot;
            chain.len += 1;
            var value = (try self.onlyInitializer(function, slot)) orelse return null;
            var inner: usize = 0;
            while (inner < depth_limit) : (inner += 1) {
                switch (self.program.nodes[@backingInt(value)].data) {
                    .block_value => |block| value = block.value,
                    .field => |field| {
                        seen_field = true;
                        value = field.base;
                    },
                    .local => |next| {
                        slot = @backingInt(next);
                        break;
                    },
                    else => return null,
                }
            } else return null;
        }
        return null;
    }

    /// How `heldAround` judges the statements around a copy.
    const Held = enum {
        /// A copy of a named place: every statement around it counts, the widest is the one that holds the copy.
        named,
        /// A copy of the element a loop over a call's list binds (FR25): a condition that reads the element does not hold it
        /// (its borrow ends with the condition, `if reading.key == key: return reading` checks, FR21), and the statement that
        /// holds the copy is not one the loop generates, which span the whole loop and its header.
        loop_element,
    };

    /// Whether a move of `place` at the copy `copy_id` would not check: a loop around the copy that the value was not declared
    /// in, a statement around it whose head (a match scrutinee, a loop source, the condition the copy is part of) reads the
    /// value, or another read of the value in the statement that holds the copy. The condition of an `if` that holds the copy in
    /// a body only reads the value, and that borrow is over before the body runs.
    fn heldAround(self: *Pass, function: typed.Function, place: Receiver, copy_id: typed.NodeId, mode: Held) std.mem.Allocator.Error!bool {
        const copy_span = self.program.nodes[@backingInt(copy_id)].span;
        const declared = place.local.declaration;
        const parameter = place.local.origin == .parameter;
        var outermost: ?source.Span = null;
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| self.program.statements[@backingInt(value)],
                .expression => continue,
            };
            if (statement.span.start > copy_span.start or statement.span.end < copy_span.end) continue;
            // The statements a loop over a call's list generates (the element's binding, the iteration check) span the whole
            // loop, header included: they are not the source statement that holds the copy.
            const generated = mode == .loop_element and statement.span.start <= declared.start and declared.start < statement.span.end;
            // What a loop generates is spelled over the whole loop: it is not the statement that holds a copy in the body.
            const loop_made = generated or switch (statement.data) {
                .loop, .range_loop, .block, .branch, .match, .with_scope => false,
                else => try self.spansLoop(function, statement.span),
            };
            switch (statement.data) {
                .loop, .range_loop => if (parameter or declared.start < statement.span.start or declared.start >= statement.span.end) return true,
                .match => |match| if (try self.mentions(match.value, place.slot)) return true,
                .branch => |branch| if (mode == .named and try self.conditionHolds(branch.condition, place.slot, copy_span)) return true,
                .with_scope => |scope| if (try self.scopeHolds(function, statement.span, scope, place.slot)) return true,
                .block => {},
                .initialize, .assign => |store| if (!isTemporary(function.scope.locals[@backingInt(store.slot)]) and !loop_made) {
                    outermost = wider(outermost, statement.span);
                },
                else => if (!loop_made) {
                    outermost = wider(outermost, statement.span);
                },
            }
        }
        const statement_span = outermost orelse return true;
        for (try self.bodyItems(function)) |item| {
            const id = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            if (id == copy_id) continue;
            const node = self.program.nodes[@backingInt(id)];
            if (!refersTo(node, place.slot)) continue;
            if (!inside(statement_span, node.span)) continue;
            if (try self.stagesCopy(function, copy_id, id)) continue;
            if (!try self.copiedBefore(function, copy_id, id)) return true;
        }
        return false;
    }

    /// Whether `span` is the whole of a loop statement: what a loop generates (the binding of its element, the step that
    /// counts it) is spelled over the loop, and is not the statement that holds a copy in the body.
    fn spansLoop(self: *Pass, function: typed.Function, span: source.Span) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| switch (item) {
            .statement => |id| {
                const statement = self.program.statements[@backingInt(id)];
                if (statement.span.start != span.start or statement.span.end != span.end) continue;
                if (statement.data == .loop or statement.data == .range_loop) return true;
            },
            .expression => {},
        };
        return false;
    }

    /// Whether the local `slot` is read after the copy at `copy_span` on a path that can follow it. Nothing follows a `return` or
    /// a `fail`: a copy inside one is followed by the rest of its own statement only, wherever later statements stand in the
    /// source (a later `return` reads the value on a path the copy never takes). Any other copy is followed by what the source
    /// puts after it.
    fn readsAfterCopy(self: *Pass, function: typed.Function, slot: usize, copy_span: source.Span) std.mem.Allocator.Error!bool {
        var leaving: ?source.Span = null;
        for (try self.bodyItems(function)) |item| switch (item) {
            .statement => |id| {
                const statement = self.program.statements[@backingInt(id)];
                if (statement.data == .ret and inside(statement.span, copy_span)) leaving = statement.span;
            },
            .expression => {},
        };
        const rest = leaving orelse return self.usedAfter(function, slot, copy_span);
        for (try self.bodyItems(function)) |item| switch (item) {
            .expression => |id| {
                const node = self.program.nodes[@backingInt(id)];
                if (refersTo(node, slot) and node.span.start > copy_span.end and node.span.end <= rest.end) return true;
            },
            .statement => {},
        };
        return false;
    }

    /// Whether the `with` statement at `with_span` holds `slot` until its body ends: the scope's own variable, a task group (its
    /// tasks may have been given the value), or a head that names the value. What the body reads is the body's own business.
    fn scopeHolds(self: *Pass, function: typed.Function, with_span: source.Span, scope: @FieldType(@FieldType(typed.Statement, "data"), "with_scope"), slot: usize) std.mem.Allocator.Error!bool {
        if (@backingInt(scope.slot) == slot or self.tasksHold(scope.resource)) return true;
        return self.headReads(function, with_span, scope.body, slot);
    }

    /// Whether a `with` scope is a task group: its tasks read their arguments until the block ends, so the body may not move what
    /// one of them was given (`E_TASK_LOAN`), and the head does not name it.
    fn tasksHold(self: *Pass, resource: ?typed.NodeId) bool {
        const open = resource orelse return true;
        return self.program.nodes[@backingInt(open)].data == .task_group_open;
    }

    /// Whether the head of the `with` statement at `with_span` (all of it but the body) reads `slot`: the scope holds what its
    /// head names until the body ends. The body runs once, and what it reads is the body's own business.
    fn headReads(self: *Pass, function: typed.Function, with_span: source.Span, body: typed.StatementId, slot: usize) std.mem.Allocator.Error!bool {
        const body_span = self.program.statements[@backingInt(body)].span;
        for (try self.bodyItems(function)) |item| switch (item) {
            .expression => |id| {
                const node = self.program.nodes[@backingInt(id)];
                if (refersTo(node, slot) and inside(with_span, node.span) and !inside(body_span, node.span)) return true;
            },
            .statement => {},
        };
        return false;
    }

    /// Whether `other`, a read of the copied local in the statement of the copy `copy_id`, is part of another copy that is
    /// evaluated before it: both copies are operands of one record, list or call (not nested in a binary operator, a format or
    /// another call), the other's in an earlier operand. A record's fields and a list's elements run in the order the typed
    /// tree lists them, and a call's arguments in the order written, which `evaluation_order` maps to parameter positions. The
    /// earlier copy has made its value by then, so the later one may move; a call's earlier copy must be an `own` argument.
    fn copiedBefore(self: *Pass, function: typed.Function, copy_id: typed.NodeId, other: typed.NodeId) std.mem.Allocator.Error!bool {
        const read = self.program.nodes[@backingInt(other)].span;
        if (try self.appendedBefore(function, copy_id, read)) return true;
        for (try self.bodyItems(function)) |item| switch (item) {
            .expression => |id| {
                const data = self.program.nodes[@backingInt(id)].data;
                const count = switch (data) {
                    .record => |fields| fields.len,
                    .array => |values| values.len,
                    .call => |call| call.arguments.len,
                    else => continue,
                };
                var later: ?usize = null;
                for (0..count) |position| {
                    if (inherited(self.program, operandAt(data, position)) == copy_id) later = evaluationRank(data, position);
                }
                for (0..count) |position| {
                    const operand = operandAt(data, position);
                    if (!inside(self.program.nodes[@backingInt(operand)].span, read) or !isCopy(self.program, inherited(self.program, operand))) continue;
                    // An earlier argument to a read-only parameter is deleted, not kept as a copy: the pair would pass the value and move it.
                    if (data == .call and !ownArgument(self.program, data.call.function, position)) continue;
                    const rank = evaluationRank(data, position) orelse continue;
                    if (rank < (later orelse continue)) return true;
                }
            },
            .statement => {},
        };
        return false;
    }

    /// Whether the read at `read` lies in an element of a list literal that precedes the element the copy `copy_id` is, and is a
    /// copy itself: the literal's elements are appended to one compiler temporary, in the order written.
    fn appendedBefore(self: *Pass, function: typed.Function, copy_id: typed.NodeId, read: source.Span) std.mem.Allocator.Error!bool {
        var list: ?usize = null;
        for (try self.bodyItems(function)) |item| switch (item) {
            .expression => |id| switch (self.program.nodes[@backingInt(id)].data) {
                .buffer_operation => |operation| if (operation.kind == .append and operation.arguments.len == 1 and inherited(self.program, operation.arguments[0]) == copy_id) {
                    list = @backingInt(operation.owner);
                },
                else => {},
            },
            .statement => {},
        };
        const owner = list orelse return false;
        if (owner >= function.scope.locals.len or !isTemporary(function.scope.locals[owner])) return false;
        const copy_span = self.program.nodes[@backingInt(copy_id)].span;
        for (try self.bodyItems(function)) |item| switch (item) {
            .expression => |id| switch (self.program.nodes[@backingInt(id)].data) {
                .buffer_operation => |operation| if (operation.kind == .append and operation.arguments.len == 1 and @backingInt(operation.owner) == owner) {
                    const element = self.program.nodes[@backingInt(operation.arguments[0])].span;
                    if (inside(element, read) and element.end <= copy_span.start and isCopy(self.program, inherited(self.program, operation.arguments[0]))) return true;
                },
                else => {},
            },
            .statement => {},
        };
        return false;
    }

    /// The operand of a record, a list literal or a call at `position`.
    fn operandAt(data: @FieldType(typed.Node, "data"), position: usize) typed.NodeId {
        return switch (data) {
            .record => |fields| fields[position].value,
            .array => |values| values[position],
            .call => |call| call.arguments[position],
            else => unreachable,
        };
    }

    /// When the operand at `position` of a record, a list literal or a call runs among its siblings: a call's arguments run in
    /// the order written, and `evaluation_order[written]` is the parameter position the written argument fills.
    fn evaluationRank(data: @FieldType(typed.Node, "data"), position: usize) ?usize {
        return switch (data) {
            .call => |call| if (call.evaluation_order.len == 0) position else std.mem.indexOfScalar(usize, call.evaluation_order, position),
            else => position,
        };
    }

    /// Whether `candidate` is a read that only lowers the copy `copy_id`: a copy of a record, list or dictionary binds a
    /// compiler temporary to the value first (`<collection> = piece`), and that read goes with the copy a move replaces.
    fn stagesCopy(self: *Pass, function: typed.Function, copy_id: typed.NodeId, candidate: typed.NodeId) std.mem.Allocator.Error!bool {
        var slot = @backingInt(self.program.nodes[@backingInt(copy_id)].data.buffer_operation.owner);
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            if (slot >= function.scope.locals.len or !isTemporary(function.scope.locals[slot])) return false;
            const value = (try self.onlyInitializer(function, slot)) orelse return false;
            if (value == candidate) return true;
            // A field path's read is the field nodes above the local; the local inside them goes with the copy too.
            var inner = value;
            var steps: usize = 0;
            while (steps < depth_limit) : (steps += 1) switch (self.program.nodes[@backingInt(inner)].data) {
                .field => |field| {
                    if (field.base == candidate) return true;
                    inner = field.base;
                },
                else => break,
            };
            slot = switch (self.program.nodes[@backingInt(inner)].data) {
                .local => |next| @backingInt(next),
                else => return false,
            };
        }
        return false;
    }

    /// Whether a branch's `condition` holds `slot` against a copy at `copy_span`: a copy inside the condition is read there, and
    /// the move would not be the last read of its statement. A condition that only reads the value before a body that holds the
    /// copy has ended its borrow, as a boolean does, so the body may give the value away.
    fn conditionHolds(self: *Pass, condition: typed.NodeId, slot: usize, copy_span: source.Span) std.mem.Allocator.Error!bool {
        const span = self.program.nodes[@backingInt(condition)].span;
        if (copy_span.start >= span.start and copy_span.end <= span.end) return self.mentions(condition, slot);
        return false;
    }

    /// Whether the expression `id` reads local `slot` anywhere in its subtree.
    fn mentions(self: *Pass, id: typed.NodeId, slot: usize) std.mem.Allocator.Error!bool {
        const span = self.program.nodes[@backingInt(id)].span;
        for (self.program.nodes) |node| {
            if (!refersTo(node, slot)) continue;
            if (node.span.start >= span.start and node.span.end <= span.end) return true;
        }
        return false;
    }

    fn initializeRepair(
        self: *Pass,
        function: typed.Function,
        place: Receiver,
        receiver: []const u8,
        statement: typed.StatementId,
    ) std.mem.Allocator.Error!?[]const u8 {
        // A concrete specialization does not authorize a marker edit in the
        // shared source template, where another instance may be scalar.
        if (function.type_arguments.len != 0) return null;
        const store = switch (self.program.statements[@backingInt(statement)].data) {
            .initialize => |value| value,
            else => return null,
        };
        if (store.unpack != null) return null;
        if (@backingInt(store.slot) >= function.scope.locals.len) return null;
        const destination = function.scope.locals[@backingInt(store.slot)];
        if (destination.origin != .local or destination.ownership.view) return null;
        // A lowered receiver initializes a compiler temporary, not a binding the
        // source declared, so its copy is part of a larger expression.
        if (destination.usage.temporary or std.mem.startsWith(u8, destination.name, "<")) return null;
        // The copied value is an owned local, not a parameter or caller storage,
        // and the binding owns it directly rather than a field of another value
        // (field-level moves are not part of this plan).
        if (!place.direct or place.local.origin != .local or place.local.ownership.view) return null;
        // The binding must hold a value of its own: a local bound from a field,
        // an element or another local (a match payload, a projection) borrows
        // its source, so moving it would be a refusal the checker reports.
        if (!try self.owningSource(function, place.slot)) return null;
        // A move out of a loop runs again on the next iteration, and a move with
        // a later use or a live view would not check: the copy is still needed.
        const span = self.program.statements[@backingInt(statement)].span;
        if ((try self.insideLoop(function, statement)) != null) return null;
        if (try self.usedAfter(function, place.slot, span)) return null;
        if (try self.viewedAnywhere(function, place.slot, &.{})) return null;
        const message = try std.fmt.allocPrint(self.memory, "`{s}` is never used again, so bind `own {s}` and the copy becomes a move", .{
            receiver, receiver,
        });
        return message;
    }

    /// The innermost loop whose body or step contains `target`, or null.
    fn insideLoop(self: *Pass, function: typed.Function, target: typed.StatementId) std.mem.Allocator.Error!?typed.StatementId {
        var pending: std.ArrayList(typed.StatementId) = .empty;
        defer pending.deinit(self.memory);
        try pending.append(self.memory, function.scope.body);
        while (pending.pop()) |id| {
            const data = self.program.statements[@backingInt(id)].data;
            if (data == .loop or data == .range_loop) {
                if (try self.contains(id, target)) return id;
            }
            switch (data) {
                .block => |items| for (items) |child| try pending.append(self.memory, child),
                .branch => |branch| {
                    try pending.append(self.memory, branch.then_body);
                    if (branch.else_body) |else_body| try pending.append(self.memory, else_body);
                },
                .match => |match| for (match.arms) |arm| try pending.append(self.memory, arm.body),
                .with_scope => |scope| try pending.append(self.memory, scope.body),
                .loop => |loop| {
                    if (loop.step) |step| try pending.append(self.memory, step);
                    try pending.append(self.memory, loop.body);
                },
                .range_loop => |range| {
                    const parts = range.plan();
                    for (parts.setup) |setup| try pending.append(self.memory, setup);
                    if (parts.loop.step) |step| try pending.append(self.memory, step);
                    try pending.append(self.memory, parts.loop.body);
                },
                else => {},
            }
        }
        return null;
    }

    /// Whether the statement subtree rooted at `root` contains `target`.
    fn contains(self: *Pass, root: typed.StatementId, target: typed.StatementId) std.mem.Allocator.Error!bool {
        if (root == target) return true;
        var pending: std.ArrayList(typed.StatementId) = .empty;
        defer pending.deinit(self.memory);
        try pending.append(self.memory, root);
        while (pending.pop()) |id| {
            const data = self.program.statements[@backingInt(id)].data;
            switch (data) {
                .block => |items| for (items) |child| {
                    if (child == target) return true;
                    try pending.append(self.memory, child);
                },
                .branch => |branch| {
                    if (branch.then_body == target) return true;
                    try pending.append(self.memory, branch.then_body);
                    if (branch.else_body) |else_body| {
                        if (else_body == target) return true;
                        try pending.append(self.memory, else_body);
                    }
                },
                .match => |match| for (match.arms) |arm| {
                    if (arm.body == target) return true;
                    try pending.append(self.memory, arm.body);
                },
                .with_scope => |scope| {
                    if (scope.body == target) return true;
                    try pending.append(self.memory, scope.body);
                },
                .loop => |loop| {
                    if (loop.body == target) return true;
                    try pending.append(self.memory, loop.body);
                    if (loop.step) |step| {
                        if (step == target) return true;
                        try pending.append(self.memory, step);
                    }
                },
                .range_loop => |range| {
                    const parts = range.plan();
                    for (parts.setup) |setup| {
                        if (setup == target) return true;
                        try pending.append(self.memory, setup);
                    }
                    if (parts.loop.body == target) return true;
                    try pending.append(self.memory, parts.loop.body);
                    if (parts.loop.step) |step| {
                        if (step == target) return true;
                        try pending.append(self.memory, step);
                    }
                },
                else => {},
            }
        }
        return false;
    }

    /// Whether the source local `reference` is referenced after `span`.
    fn usedAfter(self: *Pass, function: typed.Function, index: usize, span: source.Span) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| switch (item) {
            .expression => |id| {
                const node = self.program.nodes[@backingInt(id)];
                if (!refersTo(node, index)) continue;
                if (node.span.start > span.end) return true;
            },
            .statement => |id| {
                const statement = self.program.statements[@backingInt(id)];
                const store = switch (statement.data) {
                    .initialize => |value| value,
                    .assign => |value| value,
                    else => continue,
                };
                if (@backingInt(store.slot) != index) continue;
                if (statement.span.start > span.end) return true;
            },
        };
        return false;
    }

    /// Whether a view of the source local exists in the function. A move
    /// invalidates an owner's views, so a view would turn the repair into a
    /// refusal; the pass never proves a repair that could do that.
    fn viewedAnywhere(self: *Pass, function: typed.Function, reference: usize, skip: []const usize) std.mem.Allocator.Error!bool {
        if (skip.len > 2) return self.viewedScan(function, reference, skip, null);
        if (self.viewed) |*memo| if (memo.function != function.id) {
            memo.answers.deinit(self.memory);
            self.viewed = null;
        };
        if (self.viewed == null) self.viewed = .{ .function = function.id, .answers = .empty };
        const key: [3]usize = .{ reference, if (skip.len > 0) skip[0] + 1 else 0, if (skip.len > 1) skip[1] + 1 else 0 };
        if (self.viewed.?.answers.get(key)) |known| return known;
        const found = try self.viewedScan(function, reference, skip, null);
        try self.viewed.?.answers.put(self.memory, key, found);
        return found;
    }

    /// The question a hint asks (FR27): whether a view of `reference` is still read when the copy at `span` moves the element or
    /// consumes the list. A view that nothing reads from the copy on is not invalidated, which the checker accepts, so the hint
    /// is given; `viewedAnywhere`, the repair's broader question, is asked first and shared with it, so a function with no view
    /// at all costs nothing more. A view the scan cannot place (a pattern binding, a loop's variable, a `mut` local that stores
    /// borrows, a call's returned view) counts as read.
    fn viewedLive(self: *Pass, function: typed.Function, reference: usize, skip: []const usize, span: source.Span) std.mem.Allocator.Error!bool {
        if (!try self.viewedAnywhere(function, reference, skip)) return false;
        return self.viewedScan(function, reference, skip, span);
    }

    /// Whether `slot`, a view found by the scan, is read when the copy at `span` runs: after the copy in the source, or inside a
    /// loop around the copy that it was declared before (the next iteration reads it again).
    fn viewReadFrom(self: *Pass, function: typed.Function, slot: usize, span: source.Span) std.mem.Allocator.Error!bool {
        if (try self.usedAfter(function, slot, span)) return true;
        var declared: ?usize = null;
        for (try self.bodyItems(function)) |item| switch (item) {
            .statement => |id| {
                const statement = self.program.statements[@backingInt(id)];
                const store = switch (statement.data) {
                    .initialize => |value| value,
                    else => continue,
                };
                if (@backingInt(store.slot) == slot) declared = if (declared) |first| @min(first, statement.span.start) else statement.span.start;
            },
            .expression => {},
        };
        const first = declared orelse return true;
        for (try self.bodyItems(function)) |item| switch (item) {
            .statement => |id| {
                const statement = self.program.statements[@backingInt(id)];
                switch (statement.data) {
                    .loop, .range_loop => {},
                    else => continue,
                }
                if (statement.span.start > span.start or statement.span.end < span.end or first >= statement.span.start) continue;
                if (try self.readWithin(function, slot, statement.span)) return true;
            },
            .expression => {},
        };
        return false;
    }

    /// Whether the call at `call` lies in the scrutinee of a `match` (or of a bind-or-else, `const x = f(a) else:`) whose arm holds
    /// the copy at `copy`: the match keeps what its scrutinee lends until the arm ends, so the view is read when the copy runs.
    fn scrutineeHolds(self: *Pass, function: typed.Function, call: source.Span, copy: source.Span) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| {
            const id = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const match = switch (self.program.statements[@backingInt(id)].data) {
                .match => |value| value,
                else => continue,
            };
            const scrutinee = self.program.nodes[@backingInt(match.value)].span;
            if (call.start < scrutinee.start or call.end > scrutinee.end) continue;
            for (match.arms) |arm| {
                const body = if (arm.unpack) |unpack| unpack.body else arm.body;
                const span = self.program.statements[@backingInt(body)].span;
                if (span.start <= copy.start and copy.end <= span.end) return true;
            }
        }
        return false;
    }

    /// The scan `viewedAnywhere` memoizes: whether a local of `function` other than `reference` and the `skip` slots is a view or a
    /// borrow of `reference`, or a call returns a view of it. With `live`, the copy's span: a view that is read from there on only.
    fn viewedScan(self: *Pass, function: typed.Function, reference: usize, skip: []const usize, live: ?source.Span) std.mem.Allocator.Error!bool {
        for (function.scope.locals, 0..) |other, slot| {
            if (slot == reference or std.mem.indexOfScalar(usize, skip, slot) != null) continue;
            // Receiver temporaries serve a single lowered expression; they do
            // not keep a source binding's loan alive after that expression.
            // Explicit views and named aliases still need their root checked.
            if (isTemporary(other) and !other.ownership.view) continue;
            if (!other.ownership.view and !return_borrow.managed(self.program.records, other.ty)) continue;
            if (!isTemporary(other) and try self.owningSource(function, slot)) continue;
            const value = (try self.onlyInitializer(function, slot)) orelse {
                // A pattern binding borrows its match's scrutinee; an iteration loan has no ordinary initializer here.
                // Without its root proof, a move repair is not certain.
                if (other.origin == .pattern) {
                    if (try self.patternBorrowsFrom(function, slot, reference)) return true;
                    continue;
                }
                if (other.origin == .iteration) return true;
                // A `mut` local stored more than once may hold a borrow of any of its stores (4f).
                if (try self.storesBorrowFrom(function, slot, reference, 0)) return true;
                continue;
            };
            if (try self.borrowsFrom(function, value, reference, 0)) {
                if (live) |span| if (!try self.viewReadFrom(function, slot, span)) continue;
                return true;
            }
        }
        // A call that returns a view of the source binds one too.
        for (try self.bodyItems(function)) |item| {
            const id = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            const node = self.program.nodes[@backingInt(id)];
            const call = switch (node.data) {
                .call => |value| value,
                else => continue,
            };
            // A returned view that a local holds was judged with that local; one a call leaves in an expression ends with its
            // statement, so a call that is over before the copy starts (FR27) leaves nothing for the move to invalidate.
            if (live) |span| if (node.span.end < span.start and !try self.scrutineeHolds(function, node.span, span)) continue;
            if (@backingInt(call.function) >= self.program.functions.len) continue;
            const signature = self.program.functions[@backingInt(call.function)].signature;
            for (return_borrow.effectiveSources(self.program.records, signature)) |position| {
                if (position >= call.arguments.len) continue;
                const root = rootLocal(self.program, call.arguments[position], 0) orelse continue;
                if (root == reference) return true;
            }
        }
        return false;
    }

    /// Borrow provenance used only to withhold an uncertain copy repair. Local
    /// aliases and declared call sources remain loans even without slice flags.
    fn borrowsFrom(self: *Pass, function: typed.Function, id: typed.NodeId, reference: usize, depth: usize) std.mem.Allocator.Error!bool {
        if (depth > depth_limit) return true;
        const node = self.program.nodes[@backingInt(id)];
        return switch (node.data) {
            .local => |slot| self.localBorrowsFrom(function, @backingInt(slot), reference, depth + 1),
            .field => |field| self.borrowsFrom(function, field.base, reference, depth + 1),
            .index => |index| self.borrowsFrom(function, index.base, reference, depth + 1),
            .wrap, .unwrap, .cast => |value| self.borrowsFrom(function, value, reference, depth + 1),
            .propagate => |value| self.borrowsFrom(function, value.value, reference, depth + 1),
            .variant => |variant| if (variant.value) |value| self.borrowsFrom(function, value, reference, depth + 1) else false,
            .block_value => |block| if (node.view)
                if (sliceBase(self.program, block, 0)) |slot| self.localBorrowsFrom(function, slot, reference, depth + 1) else true
            else
                self.borrowsFrom(function, block.value, reference, depth + 1),
            .borrow_selection => |selection| try self.borrowsFrom(function, selection.first, reference, depth + 1) or
                try self.borrowsFrom(function, selection.second, reference, depth + 1),
            .call => |call| self.callBorrowsFrom(function, call, reference, depth + 1),
            .buffer_operation => |operation| switch (operation.kind) {
                .read, .get, .setdefault, .key_at, .value_at, .strip, .lstrip, .rstrip, .slice, .slice_bytes, .slice_step => blk: {
                    if (try self.localBorrowsFrom(function, @backingInt(operation.owner), reference, depth + 1)) break :blk true;
                    // `mapping.get(key, fallback)` may answer the fallback itself, so the result borrows that argument too.
                    for (operation.arguments) |argument| if (try self.borrowsFrom(function, argument, reference, depth + 1)) break :blk true;
                    break :blk false;
                },
                else => false,
            },
            else => false,
        };
    }

    fn callBorrowsFrom(self: *Pass, function: typed.Function, call: anytype, reference: usize, depth: usize) std.mem.Allocator.Error!bool {
        if (@backingInt(call.function) >= self.program.functions.len) return true;
        const signature = self.program.functions[@backingInt(call.function)].signature;
        if (signature.return_origin == .unknown) return true;
        for (return_borrow.effectiveSources(self.program.records, signature)) |position| {
            if (position >= call.arguments.len) return true;
            if (try self.borrowsFrom(function, call.arguments[position], reference, depth)) return true;
        }
        return false;
    }

    fn localBorrowsFrom(self: *Pass, function: typed.Function, slot: usize, reference: usize, depth: usize) std.mem.Allocator.Error!bool {
        if (slot == reference) return true;
        if (depth > depth_limit or slot >= function.scope.locals.len) return true;
        if (!isTemporary(function.scope.locals[slot]) and try self.owningSourceAt(function, slot, depth + 1)) return false;
        const value = (try self.onlyInitializer(function, slot)) orelse return self.storesBorrowFrom(function, slot, reference, depth + 1);
        return self.borrowsFrom(function, value, reference, depth + 1);
    }

    /// Whether the match payload binding `slot` may borrow `reference`: its match's scrutinee does, or the match is not found.
    fn patternBorrowsFrom(self: *Pass, function: typed.Function, slot: usize, reference: usize) std.mem.Allocator.Error!bool {
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const match = switch (self.program.statements[@backingInt(statement)].data) {
                .match => |value| value,
                else => continue,
            };
            for (match.arms) |arm| if (bindsSlot(arm, slot)) return self.borrowsFrom(function, match.value, reference, 0);
        }
        return true;
    }

    /// Whether any store to local `slot` borrows from `reference`: a `mut` local stored more than once from places holds a
    /// borrow of each (4f).
    fn storesBorrowFrom(self: *Pass, function: typed.Function, slot: usize, reference: usize, depth: usize) std.mem.Allocator.Error!bool {
        if (depth > depth_limit) return true;
        for (try self.bodyItems(function)) |item| {
            const statement = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const store = switch (self.program.statements[@backingInt(statement)].data) {
                .initialize => |value| value,
                .assign => |value| value,
                else => continue,
            };
            if (@backingInt(store.slot) != slot) continue;
            if (try self.borrowsFrom(function, store.value, reference, depth + 1)) return true;
        }
        return false;
    }
};

/// Whether a local is a compiler temporary: flagged as one, or named in angle brackets, which the source never spells.
/// The longer of two spans that both contain one point, or `next` when there is none yet: the source statement that holds a
/// copy contains the statements its own expression lowers through (a list literal's appends, a receiver's staging).
fn wider(current: ?source.Span, next: source.Span) source.Span {
    const known = current orelse return next;
    return if (next.end - next.start > known.end - known.start) next else known;
}

/// Whether two field paths below one local name different fields: they differ at the first index both have.
fn disjoint(left: []const usize, right: []const usize) bool {
    for (left[0..@min(left.len, right.len)], right[0..@min(left.len, right.len)]) |a, b| if (a != b) return true;
    return false;
}

/// Two borrows together: nothing joins to the other, the same local to itself, and two locals to something this pass
/// cannot place.
fn joinBorrows(a: Pass.Borrow, b: Pass.Borrow) Pass.Borrow {
    return switch (a) {
        .unknown => .unknown,
        .fresh => b,
        .root => |left| switch (b) {
            .fresh => a,
            .root => |right| if (left == right) a else .unknown,
            .unknown => .unknown,
        },
    };
}

/// Whether the position a copy sits in only reads its value for as long as it is live (case viii may follow it to the
/// local it borrows): a read-only argument, a printed value, a stream write, an f-string hole or a `const` binding.
fn readsBorrow(context: Context) bool {
    return switch (context) {
        .call_argument, .invoke_argument, .print_argument, .stream_text, .format_hole, .initialize => true,
        else => false,
    };
}

/// Whether a match arm binds local `slot`, as its payload or as one of its unpacked fields.
fn bindsSlot(arm: typed.MatchArm, slot: usize) bool {
    if (arm.slot) |bound| if (@backingInt(bound) == slot) return true;
    const unpack = arm.unpack orelse return false;
    for (unpack.fields) |field| if (field) |bound| if (@backingInt(bound) == slot) return true;
    return false;
}

/// Whether the callee's parameter at `position` is spelled `own`, so the argument there is taken over.
fn ownArgument(program: typed.Program, callee: typed.FunctionId, position: usize) bool {
    if (@backingInt(callee) >= program.functions.len) return false;
    const function = program.functions[@backingInt(callee)];
    return position < function.scope.own_parameters.len and function.scope.own_parameters[position];
}

fn isTemporary(local: typed.Local) bool {
    return local.usage.temporary or std.mem.startsWith(u8, local.name, "<");
}

/// Whether a buffer operation makes a slice, which is a view of its owner (`slice`, `slice_bytes` and `slice_step`).
fn isSliceKind(kind: @import("buffer_operations.zig").Kind) bool {
    return switch (kind) {
        .slice, .slice_bytes, .slice_step => true,
        else => false,
    };
}

/// Whether slot `slot` is a parameter a const-binding borrow may read through: a plain parameter, not `mut`, not
/// `own`, not a capability, file, move-only or borrowed view.
fn plainParameter(program: typed.Program, function: typed.Function, slot: usize) bool {
    if (slot >= function.signature.parameter_count or slot >= function.scope.locals.len) return false;
    const local = function.scope.locals[slot];
    if (local.origin != .parameter or local.mutable) return false;
    if (slot < function.scope.own_parameters.len and function.scope.own_parameters[slot]) return false;
    if (local.ty.capabilityIndex() != null or local.ty.isFile()) return false;
    if (typed.moveOnly(local.ty, program.records)) return false;
    return true;
}

/// Whether slot `slot` is a `mut` parameter (not `own`, a capability, a file or move-only) that a const-binding borrow of one of its
/// fields or elements may read through while nothing writes it.
fn mutParameter(program: typed.Program, function: typed.Function, slot: usize) bool {
    if (slot >= function.signature.parameter_count or slot >= function.scope.locals.len) return false;
    const local = function.scope.locals[slot];
    if (local.origin != .parameter or !local.mutable) return false;
    if (slot < function.scope.own_parameters.len and function.scope.own_parameters[slot]) return false;
    if (local.ty.capabilityIndex() != null or local.ty.isFile()) return false;
    return !typed.moveOnly(local.ty, program.records);
}

/// The rule name a site waiver writes for this warning.
const rule = "needless-copy";

/// Whether a `# lint: allow needless-copy reason="..."` comment on the line
/// above `span` waives it. The lint rule reads the same comment through the
/// same line-above rule (`lint.isWaived`), so a waived copy reports nowhere.
fn waived(src: source.Source, span: source.Span) std.mem.Allocator.Error!bool {
    return waivedAs(src, span, rule);
}

/// Whether a `# lint: allow <name> reason="..."` comment on the line above `span` waives the finding named `name`.
fn waivedAs(src: source.Source, span: source.Span, name: []const u8) std.mem.Allocator.Error!bool {
    const marker = "# lint:";
    // A waiver applies from the line just above the site, so only that line is
    // read: scanning the whole program once per copy site made the check
    // quadratic in program size (20 s of a 25 s check at 400k lines).
    const start = @min(span.start, src.bytes.len);
    const line_break = std.mem.lastIndexOfScalar(u8, src.bytes[0..start], '\n') orelse return false;
    const above_start = if (std.mem.lastIndexOfScalar(u8, src.bytes[0..line_break], '\n')) |previous| previous + 1 else 0;
    const offset = std.mem.indexOf(u8, src.bytes[above_start..line_break], marker) orelse return false;
    const at = above_start + offset;
    if (!std.mem.eql(u8, src.locate(at).path, src.locate(start).path)) return false;
    const comment = src.bytes[at..line_break];
    const after = std.mem.trim(u8, comment[marker.len..], " \t");
    if (!std.mem.startsWith(u8, after, "allow")) return false;
    const rest = std.mem.trim(u8, after["allow".len..], " \t");
    const space = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
    if (!std.mem.eql(u8, rest[0..space], name)) return false;
    const at_reason = std.mem.indexOf(u8, comment, "reason=") orelse return false;
    const reason = std.mem.trim(u8, comment[at_reason + "reason=".len ..], " \t\"'");
    return reason.len != 0;
}

/// The value one local was initialized with, when exactly one store writes it:
/// a compiler temporary has one, so its data's named origin can be followed.
pub fn soleInitializer(memory: std.mem.Allocator, program: typed.Program, function: typed.Function, slot: usize) std.mem.Allocator.Error!?typed.NodeId {
    var found: ?typed.NodeId = null;
    var body = try walk.Walker.init(memory, program, function.scope.body);
    defer body.deinit();
    while (try body.next()) |item| {
        const statement = switch (item) {
            .statement => |value| value,
            .expression => continue,
        };
        const store = switch (program.statements[@backingInt(statement)].data) {
            .initialize => |value| value,
            else => continue,
        };
        if (@backingInt(store.slot) != slot) continue;
        if (found != null) return null;
        found = store.value;
    }
    return found;
}

/// The repairs of the copies of parameter `parameter` of `program.functions[function]` that this pass proves only once the
/// parameter is declared `own` (`W_COPY_FOR_STORE`, `copy_for_store.zig`): the pass runs over the function twice, with the
/// parameter as declared and with it `own` (an `own` parameter is an owning source, so its last use is a move), and each
/// `W_NEEDLESS_COPY` edit of a copy of the parameter that only the second run makes is returned: `copy(p)` to `own p`, or
/// to `p` for a returned value. A copy the first run already repairs is left to that warning. Owned by `memory`, an arena.
/// The pass reads the function's own flags from the function it is given and every callee's from `program`, so a call of
/// the function inside its own body still sees the parameter as declared: ask only for a function that does not call itself.
pub fn provedWithOwn(memory: std.mem.Allocator, program: typed.Program, src: source.Source, function: usize, parameter: usize) std.mem.Allocator.Error![]const diagnostic.Edit {
    const declared = program.functions[function];
    const own = try memory.alloc(bool, @max(declared.signature.parameter_count, declared.scope.own_parameters.len));
    @memset(own, false);
    @memcpy(own[0..declared.scope.own_parameters.len], declared.scope.own_parameters);
    own[parameter] = true;
    var with_own = declared;
    with_own.scope.own_parameters = own;
    // The copies of the parameter, by their span: only their repairs count.
    var spans: std.AutoHashMapUnmanaged(source.Span, void) = .empty;
    var plain_spans: std.AutoHashMapUnmanaged(source.Span, void) = .empty;
    var found: std.ArrayList(diagnostic.Edit) = .empty;
    const run = program;
    for ([_]typed.Function{ declared, with_own }, 0..) |checked, round| {
        var sink: diagnostic.Sink = .{ .allocator = memory };
        var pass: Pass = .{ .memory = memory, .program = run, .src = src, .contexts = .{ .memory = memory }, .sink = &sink };
        defer pass.contexts.deinit();
        defer pass.hinted.deinit(memory);
        defer if (pass.items) |cached| memory.free(cached.list);
        defer if (pass.viewed) |*memo| memo.answers.deinit(memory);
        defer if (pass.initializers) |built| built.deinit(memory);
        defer if (pass.owned) |table| memory.free(table);
        // The parent index of this one function's nodes, as `Contexts.init` builds it for the whole program.
        var body = try walk.Walker.init(memory, run, checked.scope.body);
        defer body.deinit();
        while (try body.next()) |item| switch (item) {
            .expression => |id| {
                const node = run.nodes[@backingInt(id)];
                try pass.contexts.indexNode(run, node, id);
                if (round == 0 and isCopy(run, id) and @backingInt(node.data.buffer_operation.owner) == parameter) try spans.put(memory, node.span, {});
            },
            .statement => {},
        };
        try pass.contexts.indexFunction(run, checked);
        try pass.warnFunction(checked);
        for (sink.items.items) |item| {
            if (!std.mem.eql(u8, item.code, code)) continue;
            const fix = item.provenance.fix orelse continue;
            if (fix.more.len != 0 or !spans.contains(fix.edit.span)) continue;
            if (round == 0) {
                try plain_spans.put(memory, fix.edit.span, {});
            } else if (!plain_spans.contains(fix.edit.span)) try found.append(memory, fix.edit);
        }
    }
    return found.toOwnedSlice(memory);
}

/// The diagnostics this pass gives one function body as `function` holds it, whose `own` flags may differ from the program's:
/// `copy_loop_repair.zig` compares a list parameter as declared and `own`. Owned by `memory`, an arena.
pub fn warnOne(memory: std.mem.Allocator, program: typed.Program, src: source.Source, function: typed.Function) std.mem.Allocator.Error![]const diagnostic.Diagnostic {
    var sink: diagnostic.Sink = .{ .allocator = memory };
    var pass: Pass = .{ .memory = memory, .program = program, .src = src, .contexts = .{ .memory = memory }, .sink = &sink };
    defer pass.contexts.deinit();
    defer pass.hinted.deinit(memory);
    defer if (pass.items) |cached| memory.free(cached.list);
    defer if (pass.viewed) |*memo| memo.answers.deinit(memory);
    defer if (pass.initializers) |built| built.deinit(memory);
    defer if (pass.owned) |table| memory.free(table);
    var body = try walk.Walker.init(memory, program, function.scope.body);
    defer body.deinit();
    while (try body.next()) |item| switch (item) {
        .expression => |id| try pass.contexts.indexNode(program, program.nodes[@backingInt(id)], id),
        .statement => {},
    };
    try pass.contexts.indexFunction(program, function);
    try pass.warnFunction(function);
    return sink.items.items;
}

/// Whether the copy sits in the index of an assignment, `target[copy(k)] = value`: the form whose key a dictionary borrows.
fn indexStore(src: source.Source, copy: source.Span, store: source.Span) bool {
    const bytes = src.bytes;
    if (copy.start <= store.start or copy.end >= bytes.len) return false;
    var before = copy.start;
    while (before > store.start and (bytes[before - 1] == ' ' or bytes[before - 1] == '\t')) before -= 1;
    if (before == store.start or bytes[before - 1] != '[') return false;
    var after = copy.end;
    while (after < bytes.len and (bytes[after] == ' ' or bytes[after] == '\t')) after += 1;
    if (after >= bytes.len or bytes[after] != ']') return false;
    after += 1;
    while (after < bytes.len and (bytes[after] == ' ' or bytes[after] == '\t')) after += 1;
    return after < bytes.len and bytes[after] == '=' and (after + 1 >= bytes.len or bytes[after + 1] != '=');
}

/// Whether `store` is `module.setdefault(mut mapping, copy(k), fallback)` with the copy as its key: a qualified call whose
/// second argument is the copy.
fn setdefaultKey(src: source.Source, copy: source.Span, store: source.Span) bool {
    const text = src.text(store);
    const open = std.mem.indexOfScalar(u8, text, '(') orelse return false;
    const head = std.mem.trimEnd(u8, text[0..open], " \t");
    const dot = std.mem.lastIndexOfScalar(u8, head, '.') orelse return false;
    if (!std.mem.eql(u8, head[dot + 1 ..], "setdefault") or dot == 0) return false;
    if (copy.start < store.start + open or copy.end > store.end) return false;
    const before = std.mem.trimEnd(u8, src.bytes[store.start + open + 1 .. copy.start], " \t\r\n");
    const after = std.mem.trimStart(u8, src.bytes[copy.end..store.end], " \t\r\n");
    // `mut mapping,` comes first and the fallback follows: the key is the one argument between two commas.
    return std.mem.endsWith(u8, before, ",") and std.mem.startsWith(u8, after, ",") and std.mem.count(u8, before, ",") == 1;
}

/// `sets.add(mut s, copy(k))` rewritten as `sets.include(mut s, k)`, when `store` is exactly that call: a qualified `add`
/// whose last argument is the copy. Null for a literal, a comprehension or any other write of a set.
fn setIncludeCall(memory: std.mem.Allocator, src: source.Source, store: source.Span, copy: source.Span, receiver: []const u8) std.mem.Allocator.Error!?[]const u8 {
    const text = src.text(store);
    const open = std.mem.indexOfScalar(u8, text, '(') orelse return null;
    const head = std.mem.trimEnd(u8, text[0..open], " \t");
    const dot = std.mem.lastIndexOfScalar(u8, head, '.') orelse return null;
    if (!std.mem.eql(u8, head[dot + 1 ..], "add") or dot == 0) return null;
    for (head[0..dot]) |byte| if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return null;
    if (copy.end > store.end or copy.start < store.start + open) return null;
    // The copy is the call's last argument: only the closing parenthesis follows it.
    if (!std.mem.eql(u8, std.mem.trim(u8, src.bytes[copy.end..store.end], " \t\r\n"), ")")) return null;
    const rewritten = try std.fmt.allocPrint(memory, "{s}include{s}{s}{s}", .{
        text[0 .. dot + 1],
        text[dot + 1 + "add".len .. copy.start - store.start],
        receiver,
        src.bytes[copy.end..store.end],
    });
    return rewritten;
}

/// The edit that takes over a copy's value and the text of the copy it replaces, both as written in the source.
const MoveSpelling = struct { edit: []const u8, original: []const u8 };

/// Whether the source between the start of a `match` statement and its scrutinee is `match` and white space alone: no `own`,
/// `mut` or parenthesis there, so `own ` goes in front of the scrutinee as written.
fn bareMatchHead(src: source.Source, statement_start: usize, scrutinee_start: usize) bool {
    if (scrutinee_start <= statement_start or scrutinee_start > src.bytes.len) return false;
    const head = src.bytes[statement_start..scrutinee_start];
    if (!std.mem.startsWith(u8, head, "match")) return false;
    const gap = head["match".len..];
    if (gap.len == 0) return false;
    for (gap) |byte| if (byte != ' ' and byte != '\t') return false;
    return true;
}

/// Whether the source between the start of a bind-or-else statement and its scrutinee is `const NAME = ` and nothing else: no `mut`
/// (whose binding takes the payload over with a second one) and no `own` already, so `own ` goes in front of the scrutinee.
fn constBindHead(src: source.Source, statement_start: usize, scrutinee_start: usize) bool {
    if (scrutinee_start <= statement_start or scrutinee_start > src.bytes.len) return false;
    const head = src.bytes[statement_start..scrutinee_start];
    if (!std.mem.startsWith(u8, head, "const ") or !std.mem.endsWith(u8, head, "= ")) return false;
    return isName(std.mem.trim(u8, head["const ".len .. head.len - "= ".len], " \t"));
}

/// Whether `text` is a bare name (letters, digits and underscores), not a field or an element of one.
fn isName(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    return true;
}

/// The word that hands a copy back, `return` or `fail`: the keyword written just before it.
fn returnWord(src: source.Source, span: source.Span) []const u8 {
    var index = span.start;
    while (index > 0 and (src.bytes[index - 1] == ' ' or src.bytes[index - 1] == '\t')) index -= 1;
    return if (std.mem.endsWith(u8, src.bytes[0..index], "fail")) "fail" else "return";
}

/// Whether the iterable of the loop whose source expression is at `span` is that expression and nothing around it:
/// `for x in xs:` and `for x in xs():` yes, `for i, x in enumerate(xs):`, `zip(xs, ys)` or `reversed(xs)` no (the `in` before
/// it and the `:` after it are the whole of its surroundings).
fn iteratesDirectly(src: source.Source, span: source.Span) bool {
    var before = span.start;
    while (before > 0 and (src.bytes[before - 1] == ' ' or src.bytes[before - 1] == '\t')) before -= 1;
    if (before < 3 or !std.mem.eql(u8, src.bytes[before - 2 .. before], "in")) return false;
    if (src.bytes[before - 3] != ' ' and src.bytes[before - 3] != '\t') return false;
    var after = span.end;
    while (after < src.bytes.len and (src.bytes[after] == ' ' or src.bytes[after] == '\t')) after += 1;
    return after < src.bytes.len and src.bytes[after] == ':';
}

/// Whether `options.take_or(option, default)` can be written in `function`: no local is called `options` (it would be the
/// name's meaning, not the module), and neither text holds a comment.
fn takeOrSpelled(function: typed.Function, option: []const u8, default: []const u8) bool {
    for (function.scope.locals) |local| if (std.mem.eql(u8, local.name, "options")) return false;
    return std.mem.indexOfScalar(u8, option, '#') == null and std.mem.indexOfScalar(u8, default, '#') == null;
}

/// The receiver text of a source-spelled copy: `copy(xs)` yields `xs`. The pass
/// only fires on this exact spelling, so the edit that deletes the call cannot
/// delete anything else.
fn receiverText(src: source.Source, span: source.Span) ?[]const u8 {
    const text = std.mem.trim(u8, src.text(span), " \t\r\n");
    const name = "copy";
    if (!std.mem.startsWith(u8, text, name)) return null;
    var index: usize = name.len;
    while (index < text.len and (text[index] == ' ' or text[index] == '\t')) index += 1;
    if (index >= text.len or text[index] != '(') return null;
    if (text[text.len - 1] != ')') return null;
    const receiver = std.mem.trim(u8, text[index + 1 .. text.len - 1], " \t\r\n");
    if (receiver.len == 0) return null;
    if (std.mem.indexOfScalar(u8, receiver, ',') != null) return null;
    return unwrapParentheses(receiver);
}

/// The receiver without the parentheses that enclose all of it: `copy((a.b))` repairs to `a.b`.
fn unwrapParentheses(receiver: []const u8) []const u8 {
    var text = receiver;
    while (text.len >= 2 and text[0] == '(' and text[text.len - 1] == ')') {
        var depth: usize = 0;
        for (text, 0..) |byte, index| {
            if (byte == '(') depth += 1;
            if (byte == ')') depth -= 1;
            // The opening parenthesis closes before the end: the pair does not enclose the whole receiver.
            if (depth == 0 and index != text.len - 1) return text;
        }
        text = std.mem.trim(u8, text[1 .. text.len - 1], " \t\r\n");
    }
    return text;
}

/// Case (i) through a printed value: `print` reads what it prints.
fn printRepair(memory: std.mem.Allocator, receiver: []const u8) ![]const u8 {
    return std.fmt.allocPrint(memory, "print only reads `{s}`, so print `{s}` itself rather than a copy", .{
        receiver, receiver,
    });
}

/// Case (i) through a stream write: `write` reads the text it writes.
fn streamRepair(memory: std.mem.Allocator, receiver: []const u8) ![]const u8 {
    return std.fmt.allocPrint(memory, "write only reads `{s}`, so write `{s}` itself rather than a copy", .{
        receiver, receiver,
    });
}

/// Case (i) through an f-string hole: the hole reads its value.
fn formatRepair(memory: std.mem.Allocator, receiver: []const u8) ![]const u8 {
    return std.fmt.allocPrint(memory, "an f-string hole only reads `{s}`, so write `{{{s}}}` rather than a copy", .{
        receiver, receiver,
    });
}

/// The byte after `in` and the spaces that follow it, when the source continues from `at` with ` in `: the start of a
/// `for` header's list.
fn inSource(src: source.Source, at: usize) ?usize {
    var index = at;
    while (index < src.bytes.len and (src.bytes[index] == ' ' or src.bytes[index] == '\t')) index += 1;
    if (!std.mem.startsWith(u8, src.bytes[index..], "in") or index + 2 >= src.bytes.len) return null;
    index += 2;
    if (src.bytes[index] != ' ' and src.bytes[index] != '\t') return null;
    while (index < src.bytes.len and (src.bytes[index] == ' ' or src.bytes[index] == '\t')) index += 1;
    return index;
}

/// Whether `inner` lies inside `outer`.
fn inside(outer: source.Span, inner: source.Span) bool {
    return inner.start >= outer.start and inner.end <= outer.end;
}

/// Whether any node reads or writes the local `reference`.
fn refersTo(node: typed.Node, reference: usize) bool {
    return switch (node.data) {
        .local => |slot| @backingInt(slot) == reference,
        .buffer_operation => |operation| @backingInt(operation.owner) == reference,
        .resource_io => |io| @backingInt(io.owner) == reference,
        .accept_resource => |slot| @backingInt(slot) == reference,
        else => false,
    };
}

/// The root local a slice block borrows: the value of its first initialization.
fn sliceBase(program: typed.Program, block: @FieldType(@FieldType(typed.Node, "data"), "block_value"), depth: usize) ?usize {
    if (depth > depth_limit) return null;
    const children = switch (program.statements[@backingInt(block.body)].data) {
        .block => |items| items,
        else => return null,
    };
    if (children.len == 0) return null;
    const store = switch (program.statements[@backingInt(children[0])].data) {
        .initialize => |value| value,
        else => return null,
    };
    return rootLocal(program, store.value, depth + 1);
}

/// The root local of a value's fields, indexes, casts and slices.
fn rootLocal(program: typed.Program, id: typed.NodeId, depth: usize) ?usize {
    if (depth > depth_limit) return null;
    const node = program.nodes[@backingInt(id)];
    return switch (node.data) {
        .local => |slot| @backingInt(slot),
        .field => |field| rootLocal(program, field.base, depth + 1),
        .index => |index| rootLocal(program, index.base, depth + 1),
        .cast, .wrap, .unwrap => |value| rootLocal(program, value, depth + 1),
        .block_value => |block| if (node.view)
            // A slice block borrows its base, which its first initialization
            // names; its value is the slice itself.
            sliceBase(program, block, depth + 1)
        else
            rootLocal(program, block.value, depth + 1),
        // A slice is a view of its owner, and an element read is a place inside it (`items[i]`, `by_root[key]`).
        .buffer_operation => |operation| if (node.view or operation.kind == .slice or operation.kind == .read) @backingInt(operation.owner) else null,
        else => null,
    };
}

/// Emit `W_NEEDLESS_COPY` for every copy whose repair this pass proves.
pub fn warn(
    memory: std.mem.Allocator,
    program: typed.Program,
    src: source.Source,
    stubs: []const ?origins.Fact,
    _: []const bool,
    sink: *diagnostic.Sink,
) std.mem.Allocator.Error!void {
    var pass: Pass = .{ .memory = memory, .program = program, .src = src, .contexts = try Contexts.init(memory, program, stubs), .sink = sink };
    defer pass.contexts.deinit();
    defer pass.hinted.deinit(memory);
    defer if (pass.items) |cached| memory.free(cached.list);
    defer if (pass.viewed) |*memo| memo.answers.deinit(memory);
    defer if (pass.initializers) |built| built.deinit(memory);
    defer if (pass.owned) |table| memory.free(table);
    try pass.run(stubs);
}
