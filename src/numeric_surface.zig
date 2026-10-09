//! Familiar floating expressions lower to the existing binary64 VM operations.
const std = @import("std");
const typed = @import("typed.zig");
const ast = @import("ast.zig");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const number_literal = @import("number_literal.zig");

/// Diagnose a legacy text conversion, offering a callee edit only when its target is unclaimed.
pub fn rejectTextConversion(sink: *diagnostic.Sink, span: Span, target: []const u8, claimed: bool) diagnostic.Error {
    if (claimed) {
        const message = std.fmt.allocPrint(
            sink.allocator,
            "cannot automatically replace this text conversion with {s}: {s} resolves to a user declaration or binding; " ++
                "rename that binding to expose the builtin, or edit the parsing call explicitly",
            .{ target, target },
        ) catch return error.OutOfMemory;
        return sink.fail("E_NUMERIC_PARSE", span, message);
    }
    return sink.failFix("E_NUMERIC_PARSE", span, "parse text explicitly with parse_int or parse_float; int and float convert numbers", .{ .span = span, .text = target });
}

/// Ordinary float is a compiler-created binary64 domain, independent of user domains.
pub fn isFloat(ty: typed.Type, records: []const typed.Record) bool {
    if (!ty.isAggregate()) return false;
    const record = records[ty.recordIndex()];
    return record.declaration.start == 0 and record.declaration.end == 0 and
        record.shape.domain == .u64 and std.mem.eql(u8, record.name, "float");
}

/// Append checked intermediate nodes in the compilation arena.
pub const Builder = struct {
    arena: std.mem.Allocator,
    nodes: *std.ArrayList(typed.Node),
    span: Span,
    float_type: typed.Type,

    /// Retain a checked expression in the caller-owned compilation arena.
    pub fn append(self: Builder, value: typed.Node) std.mem.Allocator.Error!typed.NodeId {
        const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.arena, value);
        return id;
    }
    fn node(self: Builder, ty: typed.Type, data: @FieldType(typed.Node, "data")) typed.Node {
        return .{ .span = self.span, .ty = ty, .data = data };
    }
    fn bits(self: Builder, input: typed.NodeId) std.mem.Allocator.Error!typed.NodeId {
        return self.append(self.node(.u64, .{ .unwrap = input }));
    }
    fn wrap(self: Builder, value: typed.NodeId) typed.Node {
        return self.node(self.float_type, .{ .wrap = value });
    }
    /// Preserve IEEE binary64 literal rounding and reject overflowing decimal constants.
    pub fn literal(self: Builder, text: []const u8, sink: *diagnostic.Sink) diagnostic.Error!typed.Node {
        // Source tokens are unsigned; a leading `-` comes from compiler-written constants.
        const negative = text.len != 0 and text[0] == '-';
        const magnitude = switch (try number_literal.float(self.arena, if (negative) text[1..] else text)) {
            .ok => |value| value,
            .bad => |problem| return sink.fail(problem.code, self.span, problem.message),
        };
        const value = if (negative) -magnitude else magnitude;
        if (!std.math.isFinite(value)) return sink.fail("E_FLOAT_RANGE", self.span, "floating-point literal overflows binary64");
        return self.constant(@bitCast(value));
    }
    /// A binary64 value given as its bit pattern: what `literal` builds from source text
    /// and what a folded float constant becomes at each use.
    pub fn constant(self: Builder, encoded: u64) std.mem.Allocator.Error!typed.Node {
        const input = try self.append(self.node(.u64, .{ .integer = encoded }));
        return self.wrap(input);
    }
    /// Numeric negation preserves negative zero and the existing binary64 NaN policy.
    pub fn negate(self: Builder, value: typed.NodeId) std.mem.Allocator.Error!typed.Node {
        const input = try self.bits(value);
        const negated = try self.append(self.node(.u64, .{ .unary = .{ .op = .f64_neg, .operand = input, .op_span = self.span } }));
        return self.wrap(negated);
    }
    /// Convert a checked fixed-width integer to the nearest binary64 value.
    pub fn fromInteger(self: Builder, value: typed.NodeId) std.mem.Allocator.Error!typed.Node {
        const ty = self.nodes.items[@backingInt(value)].ty;
        const wide: typed.Type = if (ty == .u64) .u64 else .i64;
        const input = if (ty == wide) value else try self.append(self.node(wide, .{ .cast = value }));
        const encoded = try self.append(self.node(.u64, .{ .unary = .{ .op = if (wide == .u64) .f64_from_u64 else .f64_from_i64, .operand = input, .op_span = self.span } }));
        return self.wrap(encoded);
    }
    /// Truncate towards zero into a fixed-width integer, trapping before conversion
    /// for nonfinite or out-of-range results.
    pub fn toInteger(self: Builder, value: typed.NodeId, target: typed.Type) std.mem.Allocator.Error!typed.Node {
        const input = try self.bits(value);
        const op: typed.UnaryOp = switch (target) {
            .i8 => .f64_to_i8,
            .i16 => .f64_to_i16,
            .i32 => .f64_to_i32,
            .i64 => .f64_to_i64,
            .u8 => .f64_to_u8,
            .u16 => .f64_to_u16,
            .u32 => .f64_to_u32,
            .u64 => .f64_to_u64,
            else => unreachable,
        };
        return self.node(target, .{ .unary = .{ .op = op, .operand = input, .op_span = self.span } });
    }
    /// Apply one binary64 unary operation, keeping the result in the float domain.
    pub fn unary(self: Builder, op: typed.UnaryOp, value: typed.NodeId) std.mem.Allocator.Error!typed.Node {
        const input = try self.bits(value);
        const result = try self.append(self.node(.u64, .{ .unary = .{ .op = op, .operand = input, .op_span = self.span } }));
        return self.wrap(result);
    }
    /// Numeric equality compares floating values rather than their raw bit representations.
    pub fn binary(self: Builder, op: ast.BinaryOp, left: typed.NodeId, right: typed.NodeId, sink: *diagnostic.Sink) diagnostic.Error!typed.Node {
        var lhs = try self.bits(left);
        var rhs = try self.bits(right);
        const operation: typed.BinaryOp = switch (op) {
            .add => .f64_add,
            .sub => .f64_sub,
            .mul => .f64_mul,
            .div, .python_div, .floor_div, .floor_rem => .f64_div,
            .eq, .ne => .f64_eq,
            .lt, .gt => .f64_lt,
            .le, .ge => .f64_le,
            else => return sink.fail("E_FLOAT_OPERATION", self.span, "float supports arithmetic and numeric comparison"),
        };
        if (op == .gt or op == .ge) std.mem.swap(typed.NodeId, &lhs, &rhs);
        const comparison = operation == .f64_eq or operation == .f64_lt or operation == .f64_le;
        const result = self.node(if (comparison) .bool else .u64, .{ .binary = .{ .op = operation, .left = lhs, .right = rhs, .op_span = self.span } });
        if (op == .floor_div or op == .floor_rem) {
            const quotient = try self.append(result);
            const floor = try self.append(self.node(.u64, .{ .unary = .{ .op = .f64_floor, .operand = quotient, .op_span = self.span } }));
            if (op == .floor_div) return self.wrap(floor);
            const product = try self.append(self.node(.u64, .{ .binary = .{ .op = .f64_mul, .left = floor, .right = rhs, .op_span = self.span } }));
            const remainder = try self.append(self.node(.u64, .{ .binary = .{ .op = .f64_sub, .left = lhs, .right = product, .op_span = self.span } }));
            return self.wrap(remainder);
        }
        if (op == .ne) return self.node(.bool, .{ .unary = .{ .op = .not, .operand = try self.append(result), .op_span = self.span } });
        return if (comparison) result else self.wrap(try self.append(result));
    }
};
