//! The `text-slice-octets` lint rule's analysis (F-74): a slice of a `str` whose bound counts octets without having
//! found them. `text[0:WIDTH - 1]`, `kind[0:1]` and `text[at:at + 1]` pass `check` and every test whose texts are ASCII,
//! and trap `R_TEXT_BOUNDARY` at the first text whose character ends in the middle of the cut.
//!
//! A bound is reported when the source writes it as an integer literal, a module constant, an expression over those, or
//! the other bound plus or minus a literal. A bound that is a found offset (`strings.find`, a position a loop reads
//! out of the text), a length (`len(...)`), a variable of any kind, or the start `0` is never reported, and a slice of
//! `bytes` or of a list is not a text slice. The analysis reads the checked syntax for the bounds and the checked tree
//! for the type of the slice, which are joined by the span of the slice expression.
//!
//! A slice of a text the program wrote in place is left out too, since both sides are known to the author: a text literal
//! (`"héllo"[0:1]`) and a name the same function bound once to an ASCII text literal (`const data = "abcdefghijkl"`,
//! `data[i % 4:i % 4 + 2]`).
//!
//! One shape is left out because the program has already found its cut: a literal start `N` of a text that the same
//! function has just tested with `strings.starts_with(text, "prefix")` for an ASCII prefix of at least `N` octets,
//! the strip of a known prefix (`url[7:]` after `starts_with(url, "http://")`), which cannot fall inside a character.
//!
//! The length of a text literal or of a module constant is a fixed width like the number it is (F-77):
//! `line[len("content-length:"):]` and `line[len(PREFIX):len(line)]` are reported, in every position a bound is read (alone,
//! in a sum with a literal, as the base of the other bound). A cut at exactly that width is quiet where the program has
//! tested for it, which is narrower than the ASCII-prefix shape above: see `Region`.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");

/// Why a bound counts octets it did not find.
pub const Reason = enum {
    /// An integer literal: `kind[0:1]`.
    literal,
    /// A module constant, or an expression over constants and literals: `text[0:WIDTH - 1]`.
    constant,
    /// The other bound plus or minus a literal: `text[at:at + 1]`.
    derived,
    /// The length of a text literal, alone or in a sum with a literal: `line[len("content-length:"):]`.
    literal_length,
    /// The length of a module constant, alone or in a sum: `line[len(PREFIX):len(line)]`.
    constant_length,

    /// The words the message uses for the bound.
    pub fn label(self: Reason) []const u8 {
        return switch (self) {
            .literal => "an integer literal",
            .constant => "a constant",
            .derived => "the other bound plus or minus a literal",
            .literal_length => "the length of a text literal",
            .constant_length => "the length of a constant",
        };
    }

    /// How much a bound written with this reason depends on: a sum takes the larger of its parts, and two literals stay a literal.
    fn rank(self: Reason) u8 {
        return switch (self) {
            .literal => 0,
            .literal_length => 1,
            .constant => 2,
            .constant_length => 3,
            .derived => 4,
        };
    }
};

/// Which bound of the slice is reported.
pub const Side = enum {
    start,
    end,

    /// The word the message uses for the bound.
    pub fn label(self: Side) []const u8 {
        return @tagName(self);
    }
};

/// One reported slice of a `str`.
pub const Site = struct {
    /// The slice expression, `text[at:at + 1]`.
    span: source.Span,
    /// The function whose checked body holds it.
    function: typed.FunctionId,
    side: Side,
    reason: Reason,
    /// The `strings.starts_with` or `strings.ends_with` call that guards this text over the cut but tests another text
    /// than the cut measures: the guard is nearly there, and the message names it and the width the cut measures.
    nearly: ?source.Span = null,
    /// The bound the slice reports, `len("content-length:")` or `PREFIX` as the source spells it: the width the cut measures.
    bound: source.Span,
};

/// The module constants of the program, by the text of their names.
const Constants = struct {
    names: std.StringHashMapUnmanaged(void) = .empty,

    fn declares(self: Constants, name: []const u8) bool {
        return self.names.contains(name);
    }
};

/// A `strings.starts_with(base, "prefix")` call: where it is, the source text of the tested text, and how many octets
/// the ASCII prefix has. A prefix with a non-ASCII octet guards nothing.
const Guard = struct { at: usize, base: []const u8, length: usize };

/// A `const NAME = "text"` whose text is ASCII, in the function declared before `at`: the name's text is the author's own.
const LiteralBinding = struct { at: usize, name: []const u8 };

/// What one run reads.
pub const Input = struct {
    program: typed.Program,
    syntax: ast.Program,
    src: source.Source,
};

/// Every slice of a `str` in the checked bodies of `input.program` that the rule reports, in source order within each
/// function, once for each source position (a generic function's instances share theirs).
pub fn find(memory: std.mem.Allocator, input: Input) std.mem.Allocator.Error![]const Site {
    var constants: Constants = .{};
    for (input.syntax.functions) |function| {
        if (function.policy.constant) try constants.names.put(memory, input.src.text(function.name), {});
    }
    var slices: std.AutoHashMapUnmanaged(source.Span, ast.NodeId) = .empty;
    for (input.syntax.nodes.items, 0..) |node, index| {
        if (node.data != .slice or node.data.slice.step != null) continue;
        try slices.put(memory, node.span, @fromBackingInt(index));
    }
    var seen: std.AutoHashMapUnmanaged(source.Span, void) = .empty;
    var sites: std.ArrayList(Site) = .empty;
    if (slices.count() == 0) return sites.items;
    const guards = try prefixGuards(memory, input);
    const literals = try literalBindings(memory, input);
    const regions = try guardRegions(memory, input, constants);
    for (input.program.functions) |function| {
        var walker = try walk.Walker.init(memory, input.program, function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            const id = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            const node = input.program.nodes[@backingInt(id)];
            const operation = switch (node.data) {
                .buffer_operation => |value| value,
                else => continue,
            };
            if (operation.kind != .slice_bytes) continue;
            const slot = @backingInt(operation.owner);
            if (slot >= function.scope.locals.len or !isText(input.program, function.scope.locals[slot].ty)) continue;
            const syntax_id = slices.get(node.span) orelse continue;
            if (seen.contains(node.span)) continue;
            const slice = input.syntax.nodes.items[@backingInt(syntax_id)].data.slice;
            const verdict = judge(.{ .input = input, .constants = constants, .regions = regions }, .{ .span = node.span, .base = slice.base }, slice.start, slice.end) orelse continue;
            if (stripsTestedPrefix(input, guards, function.declaration.start, node.span.start, slice)) continue;
            if (cutsWrittenText(input, literals, function.declaration.start, node.span.start, slice.base)) continue;
            try seen.put(memory, node.span, {});
            try sites.append(memory, .{ .span = node.span, .function = function.id, .side = verdict.side, .reason = verdict.reason, .nearly = verdict.nearly, .bound = verdict.bound });
        }
    }
    return sites.items;
}

/// Every `starts_with` call of the program whose prefix is an ASCII text literal, in source order.
fn prefixGuards(memory: std.mem.Allocator, input: Input) std.mem.Allocator.Error![]const Guard {
    var guards: std.ArrayList(Guard) = .empty;
    for (input.syntax.nodes.items) |node| {
        const call = switch (node.data) {
            .call => |value| value,
            else => continue,
        };
        if (call.arguments.len != 2) continue;
        // With `import strings` the parser keeps `strings.starts_with` in the call's name.
        const name = input.src.text(call.name);
        if (!std.mem.eql(u8, name, "starts_with") and !std.mem.endsWith(u8, name, ".starts_with")) continue;
        const prefix = switch (input.syntax.nodes.items[@backingInt(call.arguments[1])].data) {
            .text => |bytes| bytes,
            else => continue,
        };
        for (prefix) |byte| if (byte >= 0x80) break else {} else {
            const tested = input.syntax.nodes.items[@backingInt(call.arguments[0])].span;
            try guards.append(memory, .{ .at = node.span.start, .base = input.src.text(tested), .length = prefix.len });
        }
    }
    return guards.items;
}

/// Whether `slice` is a literal start `N` of a text that the function (declared at `declared`) tested before the slice
/// (at `at`) with an ASCII prefix of at least `N` octets: the cut is inside that prefix, so it is on a character.
fn stripsTestedPrefix(input: Input, guards: []const Guard, declared: usize, at: usize, slice: anytype) bool {
    const start = slice.start orelse return false;
    const literal = switch (input.syntax.nodes.items[@backingInt(start)].data) {
        .integer => |span| std.fmt.parseInt(usize, input.src.text(span), 10) catch return false,
        else => return false,
    };
    const base = input.src.text(input.syntax.nodes.items[@backingInt(slice.base)].span);
    for (guards) |guard| {
        if (guard.at < declared or guard.at >= at or guard.length < literal) continue;
        if (std.mem.eql(u8, guard.base, base)) return true;
    }
    return false;
}

/// Every immutable local bound to an ASCII text literal, in source order.
fn literalBindings(memory: std.mem.Allocator, input: Input) std.mem.Allocator.Error![]const LiteralBinding {
    var found: std.ArrayList(LiteralBinding) = .empty;
    for (input.syntax.statements.items) |statement| {
        const binding = switch (statement.data) {
            .binding => |value| value,
            else => continue,
        };
        if (binding.mutable) continue;
        const text = switch (input.syntax.nodes.items[@backingInt(binding.value)].data) {
            .text => |bytes| bytes,
            else => continue,
        };
        if (!ascii(text)) continue;
        try found.append(memory, .{ .at = statement.span.start, .name = input.src.text(binding.name) });
    }
    return found.items;
}

fn ascii(bytes: []const u8) bool {
    for (bytes) |byte| if (byte >= 0x80) return false;
    return true;
}

/// Whether the text a slice cuts is one the program wrote in place: a text literal, or a name the function (declared at
/// `declared`) bound to an ASCII text literal before the slice (at `at`).
fn cutsWrittenText(input: Input, literals: []const LiteralBinding, declared: usize, at: usize, base: ast.NodeId) bool {
    const node = input.syntax.nodes.items[@backingInt(base)];
    switch (node.data) {
        .text => return true,
        .name => |name| {
            const spelled = input.src.text(name);
            for (literals) |literal| {
                if (literal.at >= declared and literal.at < at and std.mem.eql(u8, literal.name, spelled)) return true;
            }
            return false;
        },
        else => return false,
    }
}

/// Whether `ty` is the language's text type.
fn isText(program: typed.Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    return program.records[ty.recordIndex()].collection.kind == .string;
}

/// The bound a slice reports and why, or null when both bounds are found offsets, lengths or absent.
const Verdict = struct { side: Side, reason: Reason, bound: source.Span, nearly: ?source.Span = null };

/// The slice being judged: its expression and the text it cuts.
const Cut = struct { span: source.Span, base: ast.NodeId };

/// What the judgement of a slice reads besides the slice: the program, its module constants and the guard regions.
const Reading = struct { input: Input, constants: Constants, regions: []const Region };

/// Judge the two bounds of one slice: the end first, since it is the one a width or a one-octet step writes.
fn judge(reading: Reading, cut: Cut, start: ?ast.NodeId, end: ?ast.NodeId) ?Verdict {
    if (end) |bound| {
        if (isZero(reading.input, bound)) return null;
        if (candidate(reading, cut, .end, bound, start)) |verdict| return verdict;
    }
    if (start) |bound| {
        if (isZero(reading.input, bound)) return null;
        if (candidate(reading, cut, .start, bound, end)) |verdict| return verdict;
    }
    return null;
}

/// The verdict for one bound: reported when the source writes it (or derives it from the `other` bound) and no guard of the
/// function has tested the text it measures, else null.
fn candidate(reading: Reading, cut: Cut, side: Side, bound: ast.NodeId, other: ?ast.NodeId) ?Verdict {
    const reason = written(reading.input, reading.constants, bound) orelse blk: {
        const base = other orelse return null;
        if (!derives(reading.input, reading.constants, bound, base)) return null;
        break :blk Reason.derived;
    };
    const held = guarded(reading, cut, bound, other);
    if (held.holds) return null;
    return .{ .side = side, .reason = reason, .bound = reading.input.syntax.nodes.items[@backingInt(bound)].span, .nearly = held.nearly };
}

/// Whether a bound is a literal or an expression over literals, module constants and the lengths of text literals and
/// constants, and which of those it is.
fn written(input: Input, constants: Constants, id: ast.NodeId) ?Reason {
    const node = input.syntax.nodes.items[@backingInt(id)];
    switch (node.data) {
        .integer => return .literal,
        // A constant of another module is read as `module.NAME`, which the parser keeps whole in a name.
        .name => |name| return if (constants.declares(afterLastDot(input.src.text(name)))) .constant else null,
        .field => |field| return if (constants.declares(input.src.text(field.name))) .constant else null,
        // `len("content-length:")` and `len(PREFIX)` are the numbers they are (F-77); the length of anything else is found.
        .length => |operand| {
            const fixed = fixedOf(input, constants, operand) orelse return null;
            return if (fixed == .literal) .literal_length else .constant_length;
        },
        .unary => |unary| {
            if (unary.op != .neg) return null;
            return written(input, constants, unary.operand);
        },
        .binary => |binary| {
            switch (binary.op) {
                .add, .sub, .mul, .floor_div => {},
                else => return null,
            }
            const left = written(input, constants, binary.left) orelse return null;
            const right = written(input, constants, binary.right) orelse return null;
            if (left == .literal and right == .literal) return .literal;
            return if (left.rank() >= right.rank()) left else right;
        },
        else => return null,
    }
}

/// The part of a possibly qualified name after its last dot: `config.NAME_WIDTH` is `NAME_WIDTH`.
fn afterLastDot(name: []const u8) []const u8 {
    return name[if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| dot + 1 else 0..];
}

/// Whether `id` is `other` plus or minus a fixed width, or a fixed width plus `other`: the same source text as `other` on one
/// side of `+` or `-` and an integer literal, or the length of a text literal or constant, on the other.
fn derives(input: Input, constants: Constants, id: ast.NodeId, other: ast.NodeId) bool {
    const binary = switch (input.syntax.nodes.items[@backingInt(id)].data) {
        .binary => |value| value,
        else => return false,
    };
    if (binary.op != .add and binary.op != .sub) return false;
    const reference = input.src.text(input.syntax.nodes.items[@backingInt(other)].span);
    if (isFixedWidth(input, constants, binary.right) and sameText(input, binary.left, reference)) return true;
    return binary.op == .add and isFixedWidth(input, constants, binary.left) and sameText(input, binary.right, reference);
}

/// Whether `id` is an integer literal or the length of a text literal or a module constant.
fn isFixedWidth(input: Input, constants: Constants, id: ast.NodeId) bool {
    return switch (input.syntax.nodes.items[@backingInt(id)].data) {
        .integer => true,
        .length => |operand| fixedOf(input, constants, operand) != null,
        else => false,
    };
}

fn sameText(input: Input, id: ast.NodeId, reference: []const u8) bool {
    return std.mem.eql(u8, input.src.text(input.syntax.nodes.items[@backingInt(id)].span), reference);
}

/// Whether a start bound is the literal `0`, which begins every text on a character.
fn isZero(input: Input, id: ast.NodeId) bool {
    const node = input.syntax.nodes.items[@backingInt(id)];
    if (node.data != .integer) return false;
    return std.mem.eql(u8, input.src.text(node.data.integer), "0");
}

/// A width the program wrote: the bytes of a text literal, or the spelling of a module constant.
const Fixed = union(enum) {
    literal: []const u8,
    constant: []const u8,

    fn same(self: Fixed, other: Fixed) bool {
        return switch (self) {
            .literal => |bytes| other == .literal and std.mem.eql(u8, bytes, other.literal),
            .constant => |name| other == .constant and std.mem.eql(u8, name, other.constant),
        };
    }
};

/// The width an expression names: a text literal's bytes, or a module constant (alone, `NAME` or `module.NAME`). Null for
/// anything else.
fn fixedOf(input: Input, constants: Constants, id: ast.NodeId) ?Fixed {
    const node = input.syntax.nodes.items[@backingInt(id)];
    return switch (node.data) {
        .text => |bytes| .{ .literal = bytes },
        .name => |name| if (constants.declares(afterLastDot(input.src.text(name)))) .{ .constant = input.src.text(node.span) } else null,
        .field => |field| if (constants.declares(input.src.text(field.name))) .{ .constant = input.src.text(node.span) } else null,
        else => null,
    };
}

/// Which end of the text a guard tests.
const GuardSide = enum { starts, ends };

/// A stretch of one function's source in which `strings.starts_with(base, X)` (or `strings.ends_with`) holds, because the
/// program tested it and control reaches the stretch only where the test passed. This is all the guard rule recognises:
///
/// - the `then` branch of an `if` (or `elif`) whose condition is the test, alone or one conjunct of an `and` chain;
/// - the `else` branch of an `if` whose condition is `not TEST`, alone or one disjunct of an `or` chain;
/// - the rest of the enclosing block after an `if` that has no `else`, whose condition is `not TEST` (or an `or` chain with
///   that disjunct) and whose body leaves (`return`, `fail`, `break`, `continue`, or branches that all do).
///
/// The text must be a name, a field chain or an element read of such a chain whose index is a literal or a name, spelled the
/// same in the test and in the cut; and neither the root names in it nor an index name may be written anywhere in the
/// stretch (an assignment, a write through a field or element, a `mut` or `own` argument). A test that is not written
/// as `strings.starts_with(TEXT, X)` or `strings.ends_with(TEXT, X)` (a loop condition, a negation of a conjunction, a
/// call through another name) guards nothing.
const Region = struct {
    side: GuardSide,
    /// The source text of the tested text.
    base: []const u8,
    /// The tested prefix or suffix, when it is a text literal or a module constant.
    fixed: ?Fixed,
    /// The test's call expression.
    call: source.Span,
    from: usize,
    to: usize,
};

/// One `starts_with` or `ends_with` call found in a condition.
const GuardCall = struct { side: GuardSide, base: ast.NodeId, argument: ast.NodeId, call: source.Span };

/// Where the regions of every function are read: the syntax, the writes of the whole program by name, and the regions so far.
const Collector = struct {
    memory: std.mem.Allocator,
    input: Input,
    constants: Constants,
    writes: std.StringHashMapUnmanaged(std.ArrayList(usize)) = .empty,
    regions: std.ArrayList(Region) = .empty,

    fn statementOf(self: *const Collector, id: ast.StatementId) ast.Statement {
        return self.input.syntax.statements.items[@backingInt(id)];
    }

    fn nodeOf(self: *const Collector, id: ast.NodeId) ast.Node {
        return self.input.syntax.nodes.items[@backingInt(id)];
    }

    /// The name at the root of a place: `args` in `args[3]` and in `request.path`.
    fn rootOf(self: *const Collector, id: ast.NodeId) ?[]const u8 {
        var current = id;
        while (true) switch (self.nodeOf(current).data) {
            .name => |name| return self.input.src.text(name),
            .field => |field| current = field.base,
            .index => |element| current = element.base,
            else => return null,
        };
    }

    fn noteWrite(self: *Collector, name: []const u8, at: usize) std.mem.Allocator.Error!void {
        const slot = try self.writes.getOrPut(self.memory, name);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(self.memory, at);
    }

    /// Every place the program writes, by the name at its root: an assignment, a write through a field or an element, a
    /// list operation, a `mut` argument, and an `own` argument (which consumes the place).
    fn collectWrites(self: *Collector) std.mem.Allocator.Error!void {
        for (self.input.syntax.statements.items) |statement| switch (statement.data) {
            .assignment => |assignment| try self.noteWrite(self.input.src.text(assignment.name), statement.span.start),
            else => {},
        };
        for (self.input.syntax.nodes.items) |node| {
            const target: ast.NodeId = switch (node.data) {
                .field_assignment => |assignment| assignment.target,
                .index_assignment => |assignment| assignment.target,
                .list_operation => |operation| operation.base,
                .mut_argument => |operand| operand,
                .own_argument => |operand| operand,
                else => continue,
            };
            if (self.rootOf(target)) |name| try self.noteWrite(name, node.span.start);
        }
    }

    /// Whether any of `names` is written inside `from..to`.
    fn writtenIn(self: *const Collector, names: []const []const u8, from: usize, to: usize) bool {
        for (names) |name| {
            const positions = self.writes.get(name) orelse continue;
            for (positions.items) |at| if (at >= from and at < to) return true;
        }
        return false;
    }

    /// The names a tested text reads, or false when it is not a plain name, field chain or element read of one.
    fn namesOf(self: *const Collector, id: ast.NodeId, names: *std.ArrayList([]const u8)) std.mem.Allocator.Error!bool {
        switch (self.nodeOf(id).data) {
            .name => |name| {
                try names.append(self.memory, self.input.src.text(name));
                return true;
            },
            .field => |field| return self.namesOf(field.base, names),
            .index => |element| {
                if (!try self.namesOf(element.base, names)) return false;
                return self.indexNames(element.index, names);
            },
            else => return false,
        }
    }

    /// The names an element index reads: a literal, a name, or a sum or difference of those.
    fn indexNames(self: *const Collector, id: ast.NodeId, names: *std.ArrayList([]const u8)) std.mem.Allocator.Error!bool {
        switch (self.nodeOf(id).data) {
            .integer => return true,
            .name => |name| {
                try names.append(self.memory, self.input.src.text(name));
                return true;
            },
            .binary => |binary| {
                if (binary.op != .add and binary.op != .sub) return false;
                const left = try self.indexNames(binary.left, names);
                const right = try self.indexNames(binary.right, names);
                return left and right;
            },
            else => return false,
        }
    }

    /// The `starts_with` or `ends_with` call `id` is, in function or method form.
    fn guardCall(self: *const Collector, id: ast.NodeId) ?GuardCall {
        const node = self.nodeOf(id);
        switch (node.data) {
            .call => |call| {
                if (call.arguments.len != 2) return null;
                const side = sideOf(self.input.src.text(call.name)) orelse return null;
                return .{ .side = side, .base = call.arguments[0], .argument = call.arguments[1], .call = node.span };
            },
            .method_call => |call| {
                if (call.arguments.len != 1) return null;
                const side = sideOf(self.input.src.text(call.name)) orelse return null;
                return .{ .side = side, .base = call.base, .argument = call.arguments[0], .call = node.span };
            },
            else => return null,
        }
    }

    /// The tests that hold when `id` is true: the conjuncts of an `and` chain.
    fn whenTrue(self: *const Collector, id: ast.NodeId, out: *std.ArrayList(GuardCall), depth: usize) std.mem.Allocator.Error!void {
        if (depth > 16) return;
        const node = self.nodeOf(id);
        if (node.data == .binary and node.data.binary.op == .logical_and) {
            try self.whenTrue(node.data.binary.left, out, depth + 1);
            return self.whenTrue(node.data.binary.right, out, depth + 1);
        }
        if (self.guardCall(id)) |guard| try out.append(self.memory, guard);
    }

    /// The tests that hold when `id` is false: `not TEST`, and the `not TEST` disjuncts of an `or` chain.
    fn whenFalse(self: *const Collector, id: ast.NodeId, out: *std.ArrayList(GuardCall), depth: usize) std.mem.Allocator.Error!void {
        if (depth > 16) return;
        const node = self.nodeOf(id);
        if (node.data == .binary and node.data.binary.op == .logical_or) {
            try self.whenFalse(node.data.binary.left, out, depth + 1);
            return self.whenFalse(node.data.binary.right, out, depth + 1);
        }
        if (node.data == .unary and node.data.unary.op == .not) {
            if (self.guardCall(node.data.unary.operand)) |guard| try out.append(self.memory, guard);
        }
    }

    /// Record `guard` as holding over `from..to`, unless its text is not a plain place or is written inside the stretch.
    fn hold(self: *Collector, guard: GuardCall, from: usize, to: usize) std.mem.Allocator.Error!void {
        if (from >= to) return;
        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(self.memory);
        if (!try self.namesOf(guard.base, &names)) return;
        if (self.writtenIn(names.items, from, to)) return;
        try self.regions.append(self.memory, .{
            .side = guard.side,
            .base = self.input.src.text(self.nodeOf(guard.base).span),
            .fixed = fixedOf(self.input, self.constants, guard.argument),
            .call = guard.call,
            .from = from,
            .to = to,
        });
    }

    /// Whether every path through `id` ends in `return`, `fail`, `break` or `continue`.
    fn leaves(self: *const Collector, id: ast.StatementId, depth: usize) bool {
        if (depth > 16) return false;
        const statement = self.statementOf(id);
        return switch (statement.data) {
            .ret, .fail, .loop_exit => true,
            .block => |children| children.len != 0 and self.leaves(children[children.len - 1], depth + 1),
            .branch => |branch| if (branch.else_body) |other| self.leaves(branch.then_body, depth + 1) and self.leaves(other, depth + 1) else false,
            .match => |match| blk: {
                if (match.arms.len == 0) break :blk false;
                for (match.arms) |arm| if (!self.leaves(arm.body, depth + 1)) break :blk false;
                break :blk true;
            },
            else => false,
        };
    }

    /// Read the statement `id` and everything nested in it.
    fn visit(self: *Collector, id: ast.StatementId, depth: usize) std.mem.Allocator.Error!void {
        if (depth > 64) return;
        const statement = self.statementOf(id);
        switch (statement.data) {
            .block => |children| for (children, 0..) |child, index| {
                try self.visit(child, depth + 1);
                const item = self.statementOf(child);
                const branch = switch (item.data) {
                    .branch => |value| value,
                    else => continue,
                };
                if (branch.else_body != null or !self.leaves(branch.then_body, 0) or index + 1 == children.len) continue;
                var guards: std.ArrayList(GuardCall) = .empty;
                defer guards.deinit(self.memory);
                try self.whenFalse(branch.condition, &guards, 0);
                const end = self.statementOf(children[children.len - 1]).span.end;
                for (guards.items) |guard| try self.hold(guard, item.span.end, end);
            },
            .branch => |branch| {
                var guards: std.ArrayList(GuardCall) = .empty;
                defer guards.deinit(self.memory);
                try self.whenTrue(branch.condition, &guards, 0);
                const then_span = self.statementOf(branch.then_body).span;
                for (guards.items) |guard| try self.hold(guard, then_span.start, then_span.end);
                try self.visit(branch.then_body, depth + 1);
                if (branch.else_body) |other| {
                    guards.clearRetainingCapacity();
                    try self.whenFalse(branch.condition, &guards, 0);
                    const else_span = self.statementOf(other).span;
                    for (guards.items) |guard| try self.hold(guard, else_span.start, else_span.end);
                    try self.visit(other, depth + 1);
                }
            },
            .loop => |loop| try self.visit(loop.body, depth + 1),
            .for_each => |each| try self.visit(each.body, depth + 1),
            .for_range => |range| try self.visit(range.body, depth + 1),
            .with_scope => |scope| try self.visit(scope.body, depth + 1),
            .match => |match| for (match.arms) |arm| try self.visit(arm.body, depth + 1),
            else => {},
        }
    }
};

/// Whether a callee's name is `starts_with` or `ends_with`, qualified or not.
fn sideOf(name: []const u8) ?GuardSide {
    if (std.mem.eql(u8, name, "starts_with") or std.mem.endsWith(u8, name, ".starts_with")) return .starts;
    if (std.mem.eql(u8, name, "ends_with") or std.mem.endsWith(u8, name, ".ends_with")) return .ends;
    return null;
}

/// Every `Region` of the program's functions.
fn guardRegions(memory: std.mem.Allocator, input: Input, constants: Constants) std.mem.Allocator.Error![]const Region {
    var collector: Collector = .{ .memory = memory, .input = input, .constants = constants };
    try collector.collectWrites();
    for (input.syntax.functions) |function| {
        if (function.policy.builtin or function.policy.host != null or function.policy.constant) continue;
        try collector.visit(function.body, 0);
    }
    return collector.regions.items;
}

/// What a guard region would have to say to make one bound safe: the end of the text it tests, and the prefix or suffix
/// (a literal or constant by its spelling, or any literal of that many octets).
const Want = struct { side: GuardSide, fixed: ?Fixed = null, width: ?usize = null };

/// What a bound is a cut at the end of: `len(P)` or `N` at the end of a prefix, `len(text) - len(S)` or `len(text) - N` at the
/// start of a suffix (`other` is the other bound, which must read `len(text)`). Null for any other bound.
fn wanted(input: Input, constants: Constants, bound: ast.NodeId, other: ?ast.NodeId, base: []const u8) ?Want {
    const node = input.syntax.nodes.items[@backingInt(bound)];
    switch (node.data) {
        .length => |operand| return .{ .side = .starts, .fixed = fixedOf(input, constants, operand) orelse return null },
        .integer => |span| return .{ .side = .starts, .width = std.fmt.parseInt(usize, input.src.text(span), 10) catch return null },
        .binary => |binary| {
            if (binary.op != .sub) return null;
            const reference = other orelse return null;
            const whole = input.syntax.nodes.items[@backingInt(reference)];
            const measured = switch (whole.data) {
                .length => |operand| input.src.text(input.syntax.nodes.items[@backingInt(operand)].span),
                else => return null,
            };
            if (!std.mem.eql(u8, measured, base) or !sameText(input, binary.left, input.src.text(whole.span))) return null;
            const right = input.syntax.nodes.items[@backingInt(binary.right)];
            return switch (right.data) {
                .length => |operand| .{ .side = .ends, .fixed = fixedOf(input, constants, operand) orelse return null },
                .integer => |span| .{ .side = .ends, .width = std.fmt.parseInt(usize, input.src.text(span), 10) catch return null },
                else => null,
            };
        },
        else => return null,
    }
}

/// What the guards of the function say about one bound: whether a test makes the cut safe, and when none does, the test that
/// covers the cut but names another text.
const Held = struct { holds: bool = false, nearly: ?source.Span = null };

/// Whether a region of the function covers `cut`, tests the text it cuts, and names the same prefix or suffix as `bound`.
fn guarded(reading: Reading, cut: Cut, bound: ast.NodeId, other: ?ast.NodeId) Held {
    const input = reading.input;
    const base = input.src.text(input.syntax.nodes.items[@backingInt(cut.base)].span);
    const want = wanted(input, reading.constants, bound, other, base) orelse return .{};
    var held: Held = .{};
    for (reading.regions) |region| {
        if (region.side != want.side or region.from > cut.span.start or cut.span.end > region.to) continue;
        if (!std.mem.eql(u8, region.base, base)) continue;
        const same = if (region.fixed) |fixed| blk: {
            if (want.fixed) |fixed_want| break :blk fixed.same(fixed_want);
            break :blk fixed == .literal and fixed.literal.len == want.width.?;
        } else false;
        if (same) return .{ .holds = true };
        held.nearly = region.call;
    }
    return held;
}
