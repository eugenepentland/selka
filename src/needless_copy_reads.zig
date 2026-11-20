//! Read-only uses of borrowed values, for the copy repairs of the borrowed-returns
//! plan (R6): `W_NEEDLESS_COPY` case (iii), a `const` bound to a copy that is only
//! read while its source does not change. Callee borrow facts come from signatures.
//!
//! Every answer is conservative. A value is read-only only when each of its uses
//! reads it: printing, an f-string hole, a read-only parameter, an operand, a
//! condition, a discarded result or a copy. A store, a return, a `match`, a move,
//! a `mut` or `own` argument, a binding and any use this module does not name is
//! not a read, so a `false` answer only ever stops a repair, never proves one.
const std = @import("std");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");
const source = @import("source.zig");
const return_borrow = @import("return_borrow.zig");

/// Deeper nesting than this is not read here, so the answer is `false` there.
const depth_limit = 32;

/// The standard `parallel.map` and its `map_with` variants (E1c), whose parameters are not counted as reads. Until FR59
/// the map read an owned list (R-B2), so a borrowed input or trailing argument was copied for it; it now reads a view in
/// place, and keeping these parameters out only means `W_NEEDLESS_COPY` does not yet name a copy written for the old rule.
pub fn standardMap(src: source.Source, callee: typed.Function) bool {
    if (!std.mem.eql(u8, src.locate(callee.declaration.start).path, "@stdlib/parallel.selka")) return false;
    const name = src.text(callee.declaration);
    return std.mem.eql(u8, name, "map") or std.mem.eql(u8, name, "map_results") or std.mem.startsWith(u8, name, "map_with");
}

/// Whether a builtin type holds no managed storage, so a value of it borrows nothing.
pub fn isScalar(ty: typed.Type) bool {
    return !ty.isAggregate() and !ty.isFile() and ty.capabilityIndex() == null;
}

/// Declared parameters that can read a copy-free value without taking it.
pub fn parameterReadOnly(program: typed.Program, src: source.Source, callee_id: typed.FunctionId, position: usize) bool {
    const index = @backingInt(callee_id);
    if (index >= program.functions.len) return false;
    const callee = program.functions[index];
    if (callee.policy.c_abi or callee.policy.host != null) return false;
    if (standardMap(src, callee)) return false;
    if (position >= callee.signature.parameter_count or position >= callee.scope.locals.len) return false;
    if (callee.scope.locals[position].mutable) return false;
    if (std.mem.indexOfScalar(u16, callee.signature.declared_mutates, @intCast(position)) != null) return false;
    if (position < callee.scope.own_parameters.len and callee.scope.own_parameters[position]) return false;
    const parameter = callee.scope.locals[position].ty;
    if (parameter.capabilityIndex() != null or parameter.isFile()) return false;
    return !typed.moveOnly(parameter, program.records);
}

/// The parents of every expression in one function body, with the read checks over them.
pub const Body = struct {
    memory: std.mem.Allocator,
    program: typed.Program,
    src: source.Source,
    function: typed.Function,
    parents: std.AutoHashMapUnmanaged(typed.NodeId, walk.Item) = .empty,
    /// The spans of the statements that evaluate expressions of their own (not blocks, not compiler temporaries).
    /// A use of a value is live until the end of the innermost one that holds it: a call later in the same
    /// statement still overlaps a borrow that the statement reads.
    evaluated: []source.Span = &.{},

    /// Index the parent of every expression reachable from `function`'s body, and the evaluating statements.
    pub fn init(memory: std.mem.Allocator, program: typed.Program, src: source.Source, function: typed.Function) std.mem.Allocator.Error!Body {
        var body: Body = .{ .memory = memory, .program = program, .src = src, .function = function };
        var spans: std.ArrayList(source.Span) = .empty;
        indexBody(&body, &spans) catch |err| {
            body.parents.deinit(memory);
            spans.deinit(memory);
            return err;
        };
        body.evaluated = spans.toOwnedSlice(memory) catch |err| {
            body.parents.deinit(memory);
            spans.deinit(memory);
            return err;
        };
        return body;
    }

    /// Fill the parent map and the statement spans of `body` in one walk of its function.
    fn indexBody(body: *Body, spans: *std.ArrayList(source.Span)) std.mem.Allocator.Error!void {
        var walker = try walk.Walker.init(body.memory, body.program, body.function.scope.body);
        defer walker.deinit();
        // The walker pushes an item's children on its stack as it yields the item, so they are the entries above the
        // item's old top; each expression child names the yielded item as its parent.
        while (true) {
            const before = walker.pending.items.len;
            const item = (try walker.next()) orelse break;
            for (walker.pending.items[before - 1 ..]) |child| switch (child.item) {
                .expression => |id| try body.parents.put(body.memory, id, item),
                .statement => {},
            };
            switch (item) {
                .expression => {},
                .statement => |id| {
                    const statement = body.program.statements[@backingInt(id)];
                    const evaluates = switch (statement.data) {
                        .block, .with_scope, .loop_exit => false,
                        .initialize => |store| !body.temporary(@backingInt(store.slot)),
                        else => true,
                    };
                    if (evaluates) try spans.append(body.memory, statement.span);
                },
            }
        }
    }

    /// Release the parent index and the statement spans.
    pub fn deinit(self: *Body) void {
        self.parents.deinit(self.memory);
        self.memory.free(self.evaluated);
    }

    /// The end of the innermost evaluating statement that contains `span`, or the end of `span` when none does.
    fn statementEnd(self: *const Body, span: source.Span) usize {
        var best: ?source.Span = null;
        for (self.evaluated) |candidate| {
            if (!contains(candidate, span)) continue;
            if (best == null or candidate.end - candidate.start < best.?.end - best.?.start) best = candidate;
        }
        return if (best) |found| @max(found.end, span.end) else span.end;
    }

    /// Whether each use reads a value, tracking nested temporaries and borrowed results.
    fn readOnlyAt(self: *const Body, start: typed.NodeId, nesting: usize) bool {
        if (nesting > depth_limit) return false;
        var child = start;
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            const parent = self.parents.get(child) orelse return false;
            switch (parent) {
                .statement => |statement| return self.statementReads(statement, child, nesting),
                .expression => |id| switch (self.program.nodes[@backingInt(id)].data) {
                    // Forwarding nodes hand the value on unchanged: their own parent decides.
                    .field, .cast => child = id,
                    .block_value => |block| if (block.value == child) {
                        child = id;
                    } else return false,
                    .index => |index| if (index.base == child) {
                        child = id;
                    } else return true,
                    .call => |call| {
                        const position = argumentPosition(call.arguments, child) orelse return false;
                        if (!self.readOnlyParameter(call.function, position)) return false;
                        if (!self.borrowsArgument(call.function, position)) return true;
                        child = id;
                    },
                    else => return expressionReads(self.program, id, child),
                },
            }
        }
        return false;
    }

    /// Whether the value of expression `id` is a read where it stands: a
    /// reference to a local, or an operation on it that only reads it.
    pub fn referenceReads(self: *const Body, id: typed.NodeId) bool {
        return self.referenceReadsAt(id, 0);
    }

    /// `referenceReads` with the nesting of temporaries followed so far.
    fn referenceReadsAt(self: *const Body, id: typed.NodeId, nesting: usize) bool {
        const node = self.program.nodes[@backingInt(id)];
        return switch (node.data) {
            .local => self.readOnlyAt(id, nesting),
            // A stored copy may itself receive a move-elision repair in this
            // warning batch. Follow its destination instead of relying on the
            // copy to keep the source independent after both edits apply.
            .buffer_operation => |operation| if (operation.kind == .copy)
                !spelledCopy(self.src, node.span) or self.holdsCallResult(operation.owner) or self.readOnlyAt(id, nesting)
            else
                !operation.kind.mutates() and (isScalar(node.ty) and !node.view or self.readOnlyAt(id, nesting)),
            else => false,
        };
    }

    /// Whether a call's argument at `position` may be read by the callee alone:
    /// the parameter is plain, not `mut`, not `own`, not declared to change, and
    /// not a managed capability, file or move-only value. The callee's result may
    /// still borrow it; `borrowsArgument` says so.
    pub fn readOnlyParameter(self: *const Body, callee_id: typed.FunctionId, position: usize) bool {
        return parameterReadOnly(self.program, self.src, callee_id, position);
    }

    /// Whether the result of calling `callee_id` may borrow its argument at
    /// `position`, according to its declared result contract.
    pub fn borrowsArgument(self: *const Body, callee_id: typed.FunctionId, position: usize) bool {
        const index = @backingInt(callee_id);
        if (index >= self.program.functions.len) return true;
        const signature = self.program.functions[index].signature;
        if (signature.return_origin == .unknown) return true;
        const selected = std.math.cast(u16, position) orelse return false;
        return std.mem.indexOfScalar(u16, return_borrow.effectiveSources(self.program.records, signature), selected) != null;
    }

    /// The last byte a `const` binding of `slot`, declared by the statement at
    /// `declaration`, is live: its last read, extended over every loop that holds
    /// a read but not the declaration, since the next iteration reads it again.
    /// Null when some use is not a read or the binding has no use at all.
    pub fn bindingEnd(self: *const Body, slot: usize, declaration: source.Span) std.mem.Allocator.Error!?usize {
        const refs = try self.references(slot);
        defer self.memory.free(refs);
        if (refs.len == 0) return null;
        var end: usize = declaration.end;
        for (refs) |id| {
            if (!self.readsOrStays(refs, id)) return null;
            end = @max(end, self.statementEnd(self.program.nodes[@backingInt(id)].span));
        }
        var walker = try walk.Walker.init(self.memory, self.program, self.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .expression => {},
            .statement => |id| {
                const span = self.program.statements[@backingInt(id)].span;
                const is_loop = switch (self.program.statements[@backingInt(id)].data) {
                    .loop, .range_loop => true,
                    else => false,
                };
                if (!is_loop or contains(span, declaration)) continue;
                for (refs) |ref| {
                    if (contains(span, self.program.nodes[@backingInt(ref)].span)) {
                        end = @max(end, span.end);
                        break;
                    }
                }
            },
        };
        return end;
    }

    /// Whether nothing writes or moves local `slot` between `from` and `to`, outside
    /// `exclude`: every read of it there is a read, and no statement assigns it or
    /// binds it.
    pub fn quietBetween(self: *const Body, slot: usize, from: usize, to: usize, exclude: source.Span) std.mem.Allocator.Error!bool {
        const refs = try self.references(slot);
        defer self.memory.free(refs);
        for (refs) |id| {
            const span = self.program.nodes[@backingInt(id)].span;
            if (span.start < from or span.end > to or contains(exclude, span)) continue;
            if (!self.readsOrStays(refs, id)) return false;
        }
        var walker = try walk.Walker.init(self.memory, self.program, self.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .expression => {},
            .statement => |id| {
                const statement = self.program.statements[@backingInt(id)];
                const store = switch (statement.data) {
                    .initialize => |value| value,
                    .assign => |value| value,
                    else => continue,
                };
                if (@backingInt(store.slot) != slot) continue;
                if (statement.span.start < from or statement.span.end > to or contains(exclude, statement.span)) continue;
                return false;
            },
        };
        return true;
    }

    /// Whether the reference `id` among `refs` reads its local, or is a copy of it the author wrote that a later reference
    /// keeps from being the local's last use. The batch's move repair edits only a copy at the last use, so such a copy
    /// stays a copy and still only reads the local.
    fn readsOrStays(self: *const Body, refs: []const typed.NodeId, id: typed.NodeId) bool {
        if (self.referenceReads(id)) return true;
        const node = self.program.nodes[@backingInt(id)];
        const operation = switch (node.data) {
            .buffer_operation => |value| value,
            else => return false,
        };
        if (operation.kind != .copy or !spelledCopy(self.src, node.span)) return false;
        for (refs) |other| if (self.program.nodes[@backingInt(other)].span.start > node.span.end) return true;
        return false;
    }

    /// Every expression of the body that refers to local `slot`: a read of it, or
    /// a buffer operation on it. The caller frees the slice.
    fn references(self: *const Body, slot: usize) std.mem.Allocator.Error![]typed.NodeId {
        var found: std.ArrayList(typed.NodeId) = .empty;
        self.collectReferences(slot, &found) catch |err| {
            found.deinit(self.memory);
            return err;
        };
        return found.toOwnedSlice(self.memory) catch |err| {
            found.deinit(self.memory);
            return err;
        };
    }

    /// Append every expression of the body that refers to local `slot` to `found`.
    fn collectReferences(self: *const Body, slot: usize, found: *std.ArrayList(typed.NodeId)) std.mem.Allocator.Error!void {
        var walker = try walk.Walker.init(self.memory, self.program, self.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .expression => |id| if (refersTo(self.program.nodes[@backingInt(id)], slot)) try found.append(self.memory, id),
            .statement => {},
        };
    }

    /// Whether the statement at `id` reads its value, which is `child`. A compiler temporary that
    /// holds the value (a lowered receiver, such as `len(xs)` or `xs[0]`) is read where its own uses are.
    fn statementReads(self: *const Body, id: typed.StatementId, child: typed.NodeId, nesting: usize) bool {
        return switch (self.program.statements[@backingInt(id)].data) {
            .discard => true,
            .branch => |branch| branch.condition == child,
            .loop => |loop| loop.condition == child,
            .assertion => |check| check.condition == child or check.message_value == child,
            .initialize => |store| store.value == child and store.unpack == null and self.temporary(@backingInt(store.slot)) and self.temporaryReads(@backingInt(store.slot), nesting),
            else => false,
        };
    }

    /// Whether `owner` is a compiler temporary whose one initialization is a call: a copy of it duplicates the call's
    /// result, a value no repair of this pass turns into a move of a local.
    fn holdsCallResult(self: *const Body, owner: typed.LocalId) bool {
        const slot = @backingInt(owner);
        if (!self.temporary(slot)) return false;
        var walker = walk.Walker.init(self.memory, self.program, self.function.scope.body) catch return false;
        defer walker.deinit();
        var found: ?typed.NodeId = null;
        while (walker.next() catch return false) |item| switch (item) {
            .expression => {},
            .statement => |id| {
                const store = switch (self.program.statements[@backingInt(id)].data) {
                    .initialize => |value| value,
                    else => continue,
                };
                if (@backingInt(store.slot) != slot) continue;
                if (found != null) return false;
                found = store.value;
            },
        };
        var current = found orelse return false;
        var depth: usize = 0;
        while (depth < depth_limit) : (depth += 1) {
            switch (self.program.nodes[@backingInt(current)].data) {
                .block_value => |block| current = block.value,
                .call => return true,
                else => return false,
            }
        }
        return false;
    }

    /// Whether local `slot` is a compiler temporary, whose name the source never spells.
    fn temporary(self: *const Body, slot: usize) bool {
        if (slot >= self.function.scope.locals.len) return false;
        const local = self.function.scope.locals[slot];
        return local.usage.temporary or std.mem.startsWith(u8, local.name, "<");
    }

    /// Whether every use of compiler temporary `slot` reads it.
    fn temporaryReads(self: *const Body, slot: usize, nesting: usize) bool {
        const refs = self.references(slot) catch return false;
        defer self.memory.free(refs);
        for (refs) |id| if (!self.referenceReadsAt(id, nesting + 1)) return false;
        return true;
    }
};

/// Whether the copy at `span` is one the author wrote (`copy(x)`), which a repair of the same batch may turn into a move.
/// A copy the lowering made (a slice of a list, a literal's element) is never edited, so the value it copies is only read.
fn spelledCopy(src: source.Source, span: source.Span) bool {
    const text = std.mem.trimStart(u8, src.text(span), " \t\r\n");
    return std.mem.startsWith(u8, text, "copy");
}

/// The position of `child` in a call's argument list, or null.
fn argumentPosition(arguments: []const typed.NodeId, child: typed.NodeId) ?usize {
    for (arguments, 0..) |argument, position| if (argument == child) return position;
    return null;
}

/// Whether an expression reads its operand `child`: printing, writing, operators,
/// a length, a condition and an index read the value and keep no reference to it.
fn expressionReads(program: typed.Program, id: typed.NodeId, child: typed.NodeId) bool {
    return switch (program.nodes[@backingInt(id)].data) {
        .print, .stream_write, .format, .binary, .unary, .length, .vector_binary, .vector_neg, .vector_sqrt, .vector_convert, .vector_select, .float_fma => true,
        .index => |index| index.index == child,
        else => false,
    };
}

/// Whether a node refers to local `slot` directly: a read of it or an operation on it.
fn refersTo(node: typed.Node, slot: usize) bool {
    return switch (node.data) {
        .local => |local| @backingInt(local) == slot,
        .buffer_operation => |operation| @backingInt(operation.owner) == slot,
        else => false,
    };
}

/// Whether `outer` contains `inner`.
fn contains(outer: source.Span, inner: source.Span) bool {
    return inner.start >= outer.start and inner.end <= outer.end;
}

test "contains is inclusive of both bounds" {
    const outer: source.Span = .{ .start = 4, .end = 10 };
    try std.testing.expect(contains(outer, .{ .start = 4, .end = 10 }));
    try std.testing.expect(!contains(outer, .{ .start = 3, .end = 10 }));
    try std.testing.expect(!contains(outer, .{ .start = 4, .end = 11 }));
}
