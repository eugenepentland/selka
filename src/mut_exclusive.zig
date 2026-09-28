//! MUT-EXCLUSIVE-1: the places the `mut` arguments of one call name must be
//! disjoint. A `mut` argument names a place: a root variable plus a path of
//! field, index and dictionary-key steps. Two places overlap when they have the
//! same root and every pair of steps compared in order may be equal until one
//! path ends, so a variable overlaps its own parts and a place overlaps itself.
//! Two field steps are equal exactly when they name one field. Two index or key
//! steps are provably distinct only when both are compile-time constants that
//! differ; a negative list index counts back from the end, so it may name the
//! same element as a non-negative one. Only `mut` arguments are compared: a
//! read-only argument keeps its VALUE-SEMANTICS-5 snapshot, and a `mut` call
//! nested inside another argument belongs to that inner call, which finishes
//! before the outer one begins.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const overlap_code = @import("origins.zig").overlap_code;
const Error = diagnostic.Error;

/// The value of one index or key step when the checker can prove it at
/// compile time, or `unknown` when it cannot.
const Key = union(enum) {
    unknown,
    integer: i128,
    text: []const u8,
    tag: usize,
};

/// One step of a place below its root: a field by name, or an index or key.
const Step = struct {
    /// The place expression up to and including this step.
    node: ast.NodeId,
    /// The field name, or null for an index or key step.
    field: ?[]const u8 = null,
    /// The index or key expression of an index step.
    operand: ?ast.NodeId = null,
    key: Key = .unknown,
    /// The receiver is a dictionary, whose keys never count from an end.
    keyed: bool = false,
};

/// The place one `mut` argument names, with the marker node for its span.
const Place = struct {
    argument: ast.NodeId,
    root: []const u8,
    root_node: ast.NodeId,
    steps: []const Step,
};

/// Why two compared steps may be equal without being provably so.
const StepVerdict = enum { equal, distinct, unknown_key, from_end };

/// Why two places overlap, and the depth of the first uncertain step or of the
/// shorter path, which is also where the enclosing value both share ends.
const Overlap = struct {
    reason: enum { same, contains, unknown_key, from_end },
    depth: usize,
};

/// Reject the first pair of `mut` arguments of one call whose places may
/// overlap. `arguments` is the call's operand list; only marked operands are
/// compared. The diagnostic points at the later argument in source order.
pub fn check(comptime Checker: type, self: *Checker, call_name: source.Span, arguments: []const ast.NodeId) Error!void {
    var marked: usize = 0;
    for (arguments) |argument| {
        if (self.syntax.nodes.items[@backingInt(argument)].data == .mut_argument) marked += 1;
    }
    if (marked < 2) return;
    var places: std.ArrayList(Place) = .empty;
    for (arguments) |argument| {
        if (try place(Checker, self, argument)) |found| try places.append(self.allocator, found);
    }
    for (places.items, 0..) |first, index| {
        for (places.items[index + 1 ..]) |second| {
            const overlap = compare(first, second) orelse continue;
            return report(Checker, self, call_name, .{ first, second }, overlap);
        }
    }
}

/// The place a marked argument names, or null for an unmarked argument or a
/// target the marker check already rejected as not assignable.
fn place(comptime Checker: type, self: *Checker, argument: ast.NodeId) Error!?Place {
    const nodes = self.syntax.nodes.items;
    const marker = nodes[@backingInt(argument)];
    if (marker.data != .mut_argument) return null;
    var steps: std.ArrayList(Step) = .empty;
    var at = marker.data.mut_argument;
    while (true) {
        switch (nodes[@backingInt(at)].data) {
            .name => |name| {
                std.mem.reverse(Step, steps.items);
                return .{ .argument = argument, .root = self.src.text(name), .root_node = at, .steps = steps.items };
            },
            .field => |field| {
                try steps.append(self.allocator, .{ .node = at, .field = self.src.text(field.name) });
                at = field.base;
            },
            .index => |index| {
                try steps.append(self.allocator, .{
                    .node = at,
                    .operand = index.index,
                    .key = key(Checker, self, index.index),
                    .keyed = dictionaryReceiver(Checker, self, index.base),
                });
                at = index.base;
            },
            else => return null,
        }
    }
}

/// A compile-time key: a string or bytes literal, an integer or bool
/// constant (a negated literal included) or a payload-free enum case.
fn key(comptime Checker: type, self: *Checker, operand: ast.NodeId) Key {
    switch (self.syntax.nodes.items[@backingInt(operand)].data) {
        .text, .bytes => |bytes| return .{ .text = bytes },
        else => {},
    }
    const checked = self.resolved[@backingInt(operand)] orelse return .unknown;
    const nodes = self.nodes.items;
    return switch (nodes[@backingInt(checked)].data) {
        .integer => |value| .{ .integer = value },
        .boolean => |value| .{ .integer = @intFromBool(value) },
        .unary => |unary| if (unary.op != .neg) .unknown else switch (nodes[@backingInt(unary.operand)].data) {
            .integer => |value| .{ .integer = -value },
            else => .unknown,
        },
        .variant => |variant| if (variant.value == null) .{ .tag = variant.tag } else .unknown,
        else => .unknown,
    };
}

/// Whether an index step's receiver is a dictionary, so two different constant
/// keys are distinct whatever their signs.
fn dictionaryReceiver(comptime Checker: type, self: *Checker, base: ast.NodeId) bool {
    const checked = self.resolved[@backingInt(base)] orelse return false;
    const ty = self.nodes.items[@backingInt(checked)].ty;
    if (!ty.isAggregate()) return false;
    return self.catalog.records[ty.recordIndex()].collection.kind == .dictionary;
}

/// Whether two places may overlap, and why.
fn compare(a: Place, b: Place) ?Overlap {
    if (!std.mem.eql(u8, a.root, b.root)) return null;
    const shared = @min(a.steps.len, b.steps.len);
    var uncertain: ?Overlap = null;
    for (a.steps[0..shared], b.steps[0..shared], 0..) |left, right, depth| {
        switch (compareSteps(left, right)) {
            .distinct => return null,
            .equal => {},
            .unknown_key => if (uncertain == null) {
                uncertain = .{ .reason = .unknown_key, .depth = depth };
            },
            .from_end => if (uncertain == null) {
                uncertain = .{ .reason = .from_end, .depth = depth };
            },
        }
    }
    if (uncertain) |found| return found;
    return .{ .reason = if (a.steps.len == b.steps.len) .same else .contains, .depth = shared };
}

fn compareSteps(a: Step, b: Step) StepVerdict {
    if (a.field != null and b.field != null) return if (std.mem.eql(u8, a.field.?, b.field.?)) .equal else .distinct;
    if (a.field != null or b.field != null) return .unknown_key;
    return compareKeys(a.key, b.key, a.keyed or b.keyed);
}

fn compareKeys(a: Key, b: Key, keyed: bool) StepVerdict {
    switch (a) {
        .integer => |left| if (b == .integer) {
            const right = b.integer;
            if (left == right) return .equal;
            // `xs[-1]` and `xs[2]` name one element of a three-element list.
            if (!keyed and (left < 0) != (right < 0)) return .from_end;
            return .distinct;
        },
        .text => |left| if (b == .text) return if (std.mem.eql(u8, left, b.text)) .equal else .distinct,
        .tag => |left| if (b == .tag) return if (left == b.tag) .equal else .distinct,
        .unknown => {},
    }
    return .unknown_key;
}

/// The source text of a place cut after `depth` steps: the root for zero.
fn prefixText(comptime Checker: type, self: *Checker, at: Place, depth: usize) []const u8 {
    const node = if (depth == 0) at.root_node else at.steps[depth - 1].node;
    return self.src.text(self.syntax.nodes.items[@backingInt(node)].span);
}

fn fullText(comptime Checker: type, self: *Checker, at: Place) []const u8 {
    return prefixText(Checker, self, at, at.steps.len);
}

fn argumentSpan(comptime Checker: type, self: *Checker, at: Place) source.Span {
    return self.syntax.nodes.items[@backingInt(at.argument)].span;
}

fn report(comptime Checker: type, self: *Checker, call_name: source.Span, pair: [2]Place, overlap: Overlap) Error {
    const later_second = argumentSpan(Checker, self, pair[1]).start >= argumentSpan(Checker, self, pair[0]).start;
    const first = if (later_second) pair[0] else pair[1];
    const second = if (later_second) pair[1] else pair[0];
    const why = try reason(Checker, self, .{ first, second }, overlap);
    // Copy the part when one place contains the other, otherwise the later one.
    const part = if (overlap.reason == .contains and first.steps.len > second.steps.len) first else second;
    const part_text = fullText(Checker, self, part);
    const message = try std.fmt.allocPrint(
        self.allocator,
        "`{s}` receives overlapping `mut` arguments `{s}` and `{s}`: {s}, and two `mut` arguments of one call must name disjoint places. " ++
            "Copy one into a local, pass `mut` that local and store it back (`copy = {s}`, pass `mut copy`, then `{s} = copy`), " ++
            "or pass the enclosing value `mut {s}` once",
        .{
            self.src.text(call_name),
            self.src.text(argumentSpan(Checker, self, first)),
            self.src.text(argumentSpan(Checker, self, second)),
            why,
            part_text,
            part_text,
            prefixText(Checker, self, second, overlap.depth),
        },
    );
    return self.sink.failRelated(overlap_code, argumentSpan(Checker, self, second), message, .{
        .span = argumentSpan(Checker, self, first),
        .message = "the other `mut` argument naming an overlapping place",
    });
}

fn reason(comptime Checker: type, self: *Checker, pair: [2]Place, overlap: Overlap) Error![]const u8 {
    const first = fullText(Checker, self, pair[0]);
    const second = fullText(Checker, self, pair[1]);
    return switch (overlap.reason) {
        .same => std.fmt.allocPrint(self.allocator, "both name `{s}`", .{first}),
        .contains => if (pair[0].steps.len > pair[1].steps.len)
            std.fmt.allocPrint(self.allocator, "`{s}` is part of `{s}`", .{ first, second })
        else
            std.fmt.allocPrint(self.allocator, "`{s}` is part of `{s}`", .{ second, first }),
        .unknown_key => unknownKey(Checker, self, pair, overlap.depth),
        .from_end => std.fmt.allocPrint(self.allocator, "`{s}` and `{s}` may name one element, because a negative index counts back from the end", .{ first, second }),
    };
}

fn unknownKey(comptime Checker: type, self: *Checker, pair: [2]Place, depth: usize) Error![]const u8 {
    const left = pair[0].steps[depth];
    const right = pair[1].steps[depth];
    const what = if (left.keyed) "entry" else "element";
    const first = fullText(Checker, self, pair[0]);
    const second = fullText(Checker, self, pair[1]);
    // A field meeting an index cannot be told apart; name the two places only.
    if (left.operand == null or right.operand == null)
        return std.fmt.allocPrint(self.allocator, "`{s}` and `{s}` may name one value", .{ first, second });
    const nodes = self.syntax.nodes.items;
    const left_key = self.src.text(nodes[@backingInt(left.operand.?)].span);
    const right_key = self.src.text(nodes[@backingInt(right.operand.?)].span);
    const verb = if (left.keyed) "keys" else "indices";
    return std.fmt.allocPrint(
        self.allocator,
        "`{s}` and `{s}` may name one {s}, because only two different constant {s} are provably distinct and `{s}` and `{s}` are not",
        .{ first, second, what, verb, left_key, right_key },
    );
}
