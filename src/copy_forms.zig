//! Which zero-copy form fits a copy that stays inside a loop (zero-copy part 4).
//!
//! The copy-in-loop lint names the form from where the copy goes, not from the loop:
//!
//! - **borrow**: the checker already proved the copy-free form (`W_NEEDLESS_COPY` without a move), so `selka fix` deletes it;
//! - **own**: the copy's source is not read again, so a move replaces it (`own x`, `take(mut x.f)`, `for x in own xs`);
//! - **span**: the copy is a slice of text or bytes kept past the call, which a `spans.Span` into the source stores without
//!   the text;
//! - **symbol**: the copy is the same name, read from a place the loop does not write, on every iteration, which a
//!   `symbols` table interns once and stores as a key;
//! - **loop_take**, **loop_param**: the copy is a `str` that a span and a symbol cannot hold (both take `bytes`), read from the
//!   element of a `for x in xs` loop; a list the function owns is taken by `for x in own xs`, and a borrowed list parameter would
//!   need to be an `own` one first;
//! - **transfer**: none of these; the copy is a real transfer and the lint says nothing more.
//!
//! The judgement reads the checked program and the checker's own warnings. It is advice, so it errs toward `transfer`.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");

/// Nesting deeper than this is not followed, and the judgement falls back to `transfer`.
const depth_limit = 32;

/// The zero-copy form that fits one copy.
pub const Form = enum { borrow, own, span, symbol, loop_take, loop_param, transfer };

/// What one judgement reads: the checked program, its source, and the checker's warnings.
pub const Request = struct {
    memory: std.mem.Allocator,
    program: typed.Program,
    src: source.Source,
    diagnostics: []const diagnostic.Diagnostic,
};

/// The form that fits the copy that starts at byte `at` of the merged source.
pub fn judge(request: Request, at: usize) std.mem.Allocator.Error!Form {
    for (request.diagnostics) |item| {
        if (item.span.start != at) continue;
        if (std.mem.eql(u8, item.code, "W_COPY_MOVE")) return .own;
        if (!std.mem.eql(u8, item.code, "W_NEEDLESS_COPY")) continue;
        const fix = item.provenance.fix orelse continue;
        return if (movesValue(fix)) .own else .borrow;
    }
    const function = functionAt(request.program, at) orelse return .transfer;
    var scan = try Scan.init(request, function, at);
    defer scan.deinit();
    return scan.form();
}

/// Whether a repair writes a move (`own x`, `take(mut x.f)`, a consuming loop) rather than deleting the copy.
fn movesValue(fix: diagnostic.Fix) bool {
    if (std.mem.startsWith(u8, fix.edit.text, "own ") or std.mem.startsWith(u8, fix.edit.text, "take(mut ")) return true;
    return fix.more.len != 0;
}

/// The function whose declaration or body holds byte `at`.
fn functionAt(program: typed.Program, at: usize) ?typed.Function {
    for (program.functions) |function| {
        const body = program.statements[@backingInt(function.scope.body)].span;
        const first = @min(function.declaration.start, body.start);
        const last = @max(function.declaration.end, body.end);
        if (at >= first and at < last) return function;
    }
    return null;
}

/// One function body, walked once for the copy at a position.
const Scan = struct {
    request: Request,
    function: typed.Function,
    copy: ?typed.NodeId = null,
    /// The sole initialization of every local the body initializes once; a local initialized twice answers null.
    initializers: std.AutoHashMapUnmanaged(u32, ?typed.NodeId) = .empty,
    loops: std.ArrayList(source.Span) = .empty,

    fn init(request: Request, function: typed.Function, at: usize) std.mem.Allocator.Error!Scan {
        var scan: Scan = .{ .request = request, .function = function };
        errdefer scan.deinit();
        var body = try walk.Walker.init(request.memory, request.program, function.scope.body);
        defer body.deinit();
        while (try body.next()) |item| switch (item) {
            .expression => |id| {
                const node = request.program.nodes[@backingInt(id)];
                if (scan.copy != null or node.span.start != at or node.view) continue;
                switch (node.data) {
                    .buffer_operation => |operation| if (operation.kind == .copy and operation.arguments.len == 0) {
                        scan.copy = id;
                    },
                    else => {},
                }
            },
            .statement => |id| {
                const statement = request.program.statements[@backingInt(id)];
                switch (statement.data) {
                    .loop, .range_loop => try scan.loops.append(request.memory, statement.span),
                    .initialize => |store| {
                        const entry = try scan.initializers.getOrPut(request.memory, @intCast(@backingInt(store.slot)));
                        entry.value_ptr.* = if (entry.found_existing) null else store.value;
                    },
                    else => {},
                }
            },
        };
        return scan;
    }

    fn deinit(self: *Scan) void {
        self.initializers.deinit(self.request.memory);
        self.loops.deinit(self.request.memory);
    }

    /// The form the copy found at the position fits.
    fn form(self: *Scan) std.mem.Allocator.Error!Form {
        const id = self.copy orelse return .transfer;
        const node = self.request.program.nodes[@backingInt(id)];
        if (!self.isText(node.ty)) return .transfer;
        const owner = @backingInt(node.data.buffer_operation.owner);
        const place = self.operand(owner) orelse return .transfer;
        const stored = try self.storedForm(node, place);
        if (stored == .transfer or !self.isString(node.ty)) return stored;
        return self.textForm(place);
    }

    /// The form that stores a copied text or bytes without the copy: a span for a slice, a symbol for a name the loop repeats.
    fn storedForm(self: *Scan, node: typed.Node, place: Operand) std.mem.Allocator.Error!Form {
        if (place.slice) return .span;
        const root = place.root orelse return .transfer;
        const loop = self.innermostLoop(node.span) orelse return .transfer;
        const local = self.function.scope.locals[root];
        if (local.origin == .iteration or local.origin == .pattern) return .transfer;
        if (local.origin != .parameter and local.declaration.start >= loop.start) return .transfer;
        return if (try self.writtenIn(root, loop)) .transfer else .symbol;
    }

    /// Whether a type is a `str`: the one text a span and a symbol cannot stand for, since both hold `bytes`.
    fn isString(self: *const Scan, ty: typed.Type) bool {
        return self.request.program.records[ty.recordIndex()].collection.kind == .string;
    }

    /// The form for a copied `str` that `storedForm` would give a span or a symbol, which `str` is refused for: the loop that
    /// takes the elements when the copy reads one and the function owns their list, `loop_param` when the list is a borrowed
    /// parameter, and a real transfer for anything else (a slice is a new text, and a name read outside a `for` loop is stored).
    fn textForm(self: *const Scan, place: Operand) Form {
        const element = place.element orelse return .transfer;
        const list = self.elementList(element) orelse return .transfer;
        const local = self.function.scope.locals[list];
        if (local.origin == .parameter) return if (local.ownership.owned_parameter) .loop_take else .loop_param;
        return if (self.ownsList(list)) .loop_take else .transfer;
    }

    /// The local that holds the list a `for x in xs` loop walks, when `element` is the loop's `x`: the checker initializes `x`
    /// from a read of a hidden `<collection>` owner, which holds the named list.
    fn elementList(self: *const Scan, element: usize) ?usize {
        const entry = self.initializers.get(@intCast(element)) orelse return null;
        const value = entry orelse return null;
        const read = switch (self.request.program.nodes[@backingInt(value)].data) {
            .buffer_operation => |operation| if (operation.kind == .read) operation else return null,
            else => return null,
        };
        const hidden = @backingInt(read.owner);
        if (hidden >= self.function.scope.locals.len) return null;
        if (!std.mem.eql(u8, self.function.scope.locals[hidden].name, "<collection>")) return null;
        const iterable = (self.initializers.get(@intCast(hidden)) orelse return null) orelse return null;
        const list = switch (self.request.program.nodes[@backingInt(iterable)].data) {
            .local => |slot| @backingInt(slot),
            else => return null,
        };
        if (list >= self.function.scope.locals.len or self.function.scope.locals[list].usage.temporary) return null;
        return list;
    }

    /// Whether a named local list is one the function owns: a `const` or `mut` that holds a list of its own, not a borrow of
    /// another place or an element of one.
    fn ownsList(self: *const Scan, list: usize) bool {
        const local = self.function.scope.locals[list];
        if (local.origin != .local or local.ownership.view or !local.written()) return false;
        const entry = self.initializers.get(@intCast(list)) orelse return false;
        const value = entry orelse return false;
        return switch (self.request.program.nodes[@backingInt(value)].data) {
            .local, .field, .index => false,
            .buffer_operation => |operation| switch (operation.kind) {
                .read, .slice, .slice_bytes, .slice_step => false,
                else => true,
            },
            else => true,
        };
    }

    /// Whether a type is the text or the bytes of a managed buffer, the values a span or a symbol stands for.
    fn isText(self: *const Scan, ty: typed.Type) bool {
        if (!ty.isAggregate() or ty.recordIndex() >= self.request.program.records.len) return false;
        const record = self.request.program.records[ty.recordIndex()];
        return record.isCollection() and (record.collection.kind == .string or record.collection.kind == .bytes);
    }

    /// What a copy's receiver temporary holds: a slice of something, or the named local a place reads, and the nearest `for`
    /// loop element it was read through.
    const Operand = struct { slice: bool = false, root: ?usize = null, element: ?usize = null };

    fn operand(self: *const Scan, owner: usize) ?Operand {
        var slot = owner;
        var element: ?usize = null;
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            if (slot >= self.function.scope.locals.len) return null;
            const local = self.function.scope.locals[slot];
            if (local.ownership.view) return .{ .slice = true };
            const temporary = local.usage.temporary or std.mem.startsWith(u8, local.name, "<");
            if (!temporary) return .{ .root = slot, .element = element };
            if (element == null and local.origin == .iteration and !std.mem.startsWith(u8, local.name, "<")) element = slot;
            const entry = self.initializers.get(@intCast(slot)) orelse return null;
            var value = entry orelse return null;
            var inner: usize = 0;
            while (inner < depth_limit) : (inner += 1) {
                const node = self.request.program.nodes[@backingInt(value)];
                if (node.view) return .{ .slice = true };
                switch (node.data) {
                    .block_value => |block| value = block.value,
                    .field => |field| value = field.base,
                    .index => |index| value = index.base,
                    .buffer_operation => |operation| switch (operation.kind) {
                        .slice, .slice_bytes, .slice_step => return .{ .slice = true },
                        .read => {
                            slot = @backingInt(operation.owner);
                            break;
                        },
                        else => return null,
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

    /// The smallest loop statement that holds `span`.
    fn innermostLoop(self: *const Scan, span: source.Span) ?source.Span {
        var best: ?source.Span = null;
        for (self.loops.items) |loop| {
            if (span.start < loop.start or span.end > loop.end) continue;
            if (best == null or loop.end - loop.start < best.?.end - best.?.start) best = loop;
        }
        return best;
    }

    /// Whether the body assigns, appends to or passes as `mut` the local `root` (or a temporary that stands for it) inside
    /// `loop`.
    fn writtenIn(self: *Scan, root: usize, loop: source.Span) std.mem.Allocator.Error!bool {
        const program = self.request.program;
        var body = try walk.Walker.init(self.request.memory, program, self.function.scope.body);
        defer body.deinit();
        while (try body.next()) |item| {
            const written = switch (item) {
                .statement => |id| self.storesIn(program.statements[@backingInt(id)], root, loop),
                .expression => |id| self.writesIn(program.nodes[@backingInt(id)], root, loop),
            };
            if (written) return true;
        }
        return false;
    }

    /// Whether the statement stores to `root` inside `loop`.
    fn storesIn(self: *const Scan, statement: typed.Statement, root: usize, loop: source.Span) bool {
        _ = self;
        if (statement.span.start < loop.start or statement.span.end > loop.end) return false;
        const store = switch (statement.data) {
            .assign => |value| value,
            .initialize => |value| value,
            else => return false,
        };
        return @backingInt(store.slot) == root;
    }

    /// Whether the expression mutates `root` inside `loop`: a writing buffer operation, or a `mut` argument of a call.
    fn writesIn(self: *const Scan, node: typed.Node, root: usize, loop: source.Span) bool {
        if (node.span.start < loop.start or node.span.end > loop.end) return false;
        const program = self.request.program;
        switch (node.data) {
            .buffer_operation => |operation| return operation.kind.mutates() and self.reaches(@backingInt(operation.owner), root),
            .call => |call| {
                if (@backingInt(call.function) >= program.functions.len) return false;
                const signature = program.functions[@backingInt(call.function)].signature;
                for (signature.declared_mutates) |position| {
                    if (position < call.arguments.len and self.argumentReaches(call.arguments[position], root)) return true;
                }
                return false;
            },
            else => return false,
        }
    }

    /// Whether the local `slot` is `root` or a temporary initialized from it.
    fn reaches(self: *const Scan, slot: usize, root: usize) bool {
        var current = slot;
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            if (current == root) return true;
            if (current >= self.function.scope.locals.len) return false;
            const entry = self.initializers.get(@intCast(current)) orelse return false;
            const value = entry orelse return false;
            current = switch (self.request.program.nodes[@backingInt(value)].data) {
                .local => |next| @backingInt(next),
                else => return false,
            };
        }
        return false;
    }

    /// Whether an argument expression is the local `root`, a field of it or an element of it.
    fn argumentReaches(self: *const Scan, id: typed.NodeId, root: usize) bool {
        var current = id;
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            switch (self.request.program.nodes[@backingInt(current)].data) {
                .local => |slot| return self.reaches(@backingInt(slot), root),
                .field => |field| current = field.base,
                .index => |index| current = index.base,
                .block_value => |block| current = block.value,
                .buffer_operation => |operation| return operation.kind == .read and self.reaches(@backingInt(operation.owner), root),
                else => return false,
            }
        }
        return false;
    }
};
