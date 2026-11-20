//! Familiar floating expressions lower to the existing binary64 VM operations.
const std = @import("std");
const typed = @import("typed.zig");
const ast = @import("ast.zig");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const number_literal = @import("number_literal.zig");
/// The code every legacy text conversion reports.
pub const numeric_parse_code = "E_NUMERIC_PARSE";

/// A legacy text conversion, `int(text)` or `float(text)`: where its callee
/// name and whole call sit, its one operand's source text, whether that
/// operand binds as tightly as a method receiver, and whether the checker
/// accepts the `str` method form at this call (generic bodies do not yet).
pub const TextConversion = struct { name: Span, call: Span, operand: []const u8, primary: bool, method: bool = true };

/// Diagnose a legacy text conversion with the repair that reaches the builtin
/// parser, `parse_int(text)`. Where something in scope claims that name (a user
/// function such as a `parse_int` wrapper would capture the call and recurse),
/// there is no edit: the `str` method form `text.parse_int()` that this repair
/// once wrote was removed (W13, slices 2 and 5), so the message names the rename that
/// exposes the builtin instead.
pub fn rejectTextConversion(sink: *diagnostic.Sink, conversion: TextConversion, target: []const u8, claimed: bool) diagnostic.Error {
    if (claimed) {
        const message = std.fmt.allocPrint(
            sink.allocator,
            "cannot automatically replace this text conversion with {s}: {s} resolves to a user declaration or binding here, " ++
                "and the `str` method form was removed; rename that binding to expose the builtin, or edit the parsing call explicitly",
            .{ target, target },
        ) catch return error.OutOfMemory;
        sink.items.append(sink.allocator, .{ .code = numeric_parse_code, .span = conversion.name, .message = message }) catch {
            sink.allocator.free(message);
            return error.OutOfMemory;
        };
        return error.SourceError;
    }
    return sink.failFix(numeric_parse_code, conversion.name, "parse text explicitly with parse_int or parse_float; int and float convert numbers", .{ .span = conversion.name, .text = target });
}

/// Whether an operand's syntax binds at least as tightly as a method call's
/// receiver, so `operand.parse_int()` needs no parentheses around it.
pub fn primaryOperand(node: ast.Node) bool {
    return switch (node.data) {
        .name, .field, .call, .method_call, .index, .slice, .text, .format => true,
        else => false,
    };
}

/// Diagnostic code for an operation whose floating operands differ in width (`f32` against `float`),
/// or that mixes `f32` with an integer. Its repair writes the conversion.
pub const float_width_code = "E_FLOAT_WIDTH";

/// Ordinary float is a compiler-created binary64 domain, independent of user domains.
pub fn isFloat(ty: typed.Type, records: []const typed.Record) bool {
    return isDomain(ty, records, "float", .u64);
}

/// `f32` is the compiler-created binary32 domain, over its 32 bit pattern as `u32`.
pub fn isF32(ty: typed.Type, records: []const typed.Record) bool {
    return isDomain(ty, records, "f32", .u32);
}

/// The shape of a `Simd[T, N]` value (its lanes), or null for any other type.
pub fn vectorShape(ty: typed.Type, records: []const typed.Record) ?typed.Array {
    if (!ty.isAggregate()) return null;
    const array = records[ty.recordIndex()].shape.array orelse return null;
    return if (array.vector) array else null;
}

/// Whether a type is either floating domain: `float` or `f32`.
pub fn isBinaryFloat(ty: typed.Type, records: []const typed.Record) bool {
    return isFloat(ty, records) or isF32(ty, records);
}

fn isDomain(ty: typed.Type, records: []const typed.Record, name: []const u8, bits: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = records[ty.recordIndex()];
    return record.declaration.start == 0 and record.declaration.end == 0 and
        record.shape.domain == bits and std.mem.eql(u8, record.name, name);
}

/// Append checked intermediate nodes in the compilation arena. `float_type` is the
/// domain the result wraps (`float` or `f32`); its bit pattern is `u64` or `u32`.
pub const Builder = struct {
    arena: std.mem.Allocator,
    nodes: *std.ArrayList(typed.Node),
    span: Span,
    float_type: typed.Type,
    records: []const typed.Record,

    /// Retain a checked expression in the caller-owned compilation arena.
    pub fn append(self: Builder, value: typed.Node) std.mem.Allocator.Error!typed.NodeId {
        const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.arena, value);
        return id;
    }
    fn node(self: Builder, ty: typed.Type, data: @FieldType(typed.Node, "data")) typed.Node {
        return .{ .span = self.span, .ty = ty, .data = data };
    }
    /// Whether this builder works in binary32.
    pub fn narrow(self: Builder) bool {
        return isF32(self.float_type, self.records);
    }
    /// The bit-pattern type of the domain this builder wraps.
    fn bitsType(self: Builder) typed.Type {
        return if (self.narrow()) .u32 else .u64;
    }
    /// The width-specific spelling of a binary64 operation.
    fn spelled(self: Builder, binary64: typed.BinaryOp) typed.BinaryOp {
        if (!self.narrow()) return binary64;
        return switch (binary64) {
            .f64_add => .f32_add,
            .f64_sub => .f32_sub,
            .f64_mul => .f32_mul,
            .f64_div => .f32_div,
            .f64_eq => .f32_eq,
            .f64_lt => .f32_lt,
            .f64_le => .f32_le,
            else => unreachable,
        };
    }
    /// The width-specific spelling of a unary binary64 operation.
    fn unaryOp(self: Builder, binary64: typed.UnaryOp) typed.UnaryOp {
        if (!self.narrow()) return binary64;
        return switch (binary64) {
            .f64_sqrt => .f32_sqrt,
            .f64_floor => .f32_floor,
            .f64_ceil => .f32_ceil,
            .f64_trunc => .f32_trunc,
            .f64_abs => .f32_abs,
            .f64_neg => .f32_neg,
            .f64_from_i64 => .f32_from_i64,
            .f64_from_u64 => .f32_from_u64,
            .f64_to_i8 => .f32_to_i8,
            .f64_to_i16 => .f32_to_i16,
            .f64_to_i32 => .f32_to_i32,
            .f64_to_i64 => .f32_to_i64,
            .f64_to_u8 => .f32_to_u8,
            .f64_to_u16 => .f32_to_u16,
            .f64_to_u32 => .f32_to_u32,
            .f64_to_u64 => .f32_to_u64,
            else => unreachable,
        };
    }
    fn bits(self: Builder, input: typed.NodeId) std.mem.Allocator.Error!typed.NodeId {
        return self.append(self.node(self.bitsType(), .{ .unwrap = input }));
    }
    /// The bit pattern of a floating value of either domain, read at that value's own width.
    fn unwrapValue(self: Builder, value: typed.NodeId) std.mem.Allocator.Error!typed.NodeId {
        const ty = self.nodes.items[@backingInt(value)].ty;
        return self.append(self.node(if (isF32(ty, self.records)) .u32 else .u64, .{ .unwrap = value }));
    }
    fn wrap(self: Builder, value: typed.NodeId) typed.Node {
        return self.node(self.float_type, .{ .wrap = value });
    }
    /// Preserve IEEE literal rounding and reject overflowing decimal constants. A
    /// text ending in `f32` is a binary32 literal, rounded directly to binary32.
    pub fn literal(self: Builder, text: []const u8, sink: *diagnostic.Sink) diagnostic.Error!typed.Node {
        // Source tokens are unsigned; a leading `-` comes from compiler-written constants such as `-1.0`.
        const negative = text.len != 0 and text[0] == '-';
        const body = if (negative) text[1..] else text;
        if (self.narrow()) {
            const magnitude = switch (try number_literal.floatAs(f32, self.arena, body)) {
                .ok => |value| value,
                .bad => |problem| return sink.fail(problem.code, self.span, problem.message),
            };
            const value = if (negative) -magnitude else magnitude;
            if (!std.math.isFinite(value)) return sink.fail("E_FLOAT_RANGE", self.span, "floating-point literal overflows binary32");
            return self.constant(@as(u32, @bitCast(value)));
        }
        const magnitude = switch (try number_literal.float(self.arena, body)) {
            .ok => |value| value,
            .bad => |problem| return sink.fail(problem.code, self.span, problem.message),
        };
        const value = if (negative) -magnitude else magnitude;
        if (!std.math.isFinite(value)) return sink.fail("E_FLOAT_RANGE", self.span, "floating-point literal overflows binary64");
        return self.constant(@bitCast(value));
    }
    /// A floating value given as its bit pattern: what `literal` builds from source text
    /// and what a folded float constant becomes at each use.
    pub fn constant(self: Builder, encoded: u64) std.mem.Allocator.Error!typed.Node {
        const input = try self.append(self.node(self.bitsType(), .{ .integer = encoded }));
        return self.wrap(input);
    }
    /// Numeric negation preserves negative zero and the existing NaN policy.
    pub fn negate(self: Builder, value: typed.NodeId) std.mem.Allocator.Error!typed.Node {
        return self.unary(.f64_neg, value);
    }
    /// Convert a checked fixed-width integer to the nearest value of this domain.
    pub fn fromInteger(self: Builder, value: typed.NodeId) std.mem.Allocator.Error!typed.Node {
        const ty = self.nodes.items[@backingInt(value)].ty;
        const wide: typed.Type = if (ty == .u64) .u64 else .i64;
        const input = if (ty == wide) value else try self.append(self.node(wide, .{ .cast = value }));
        const encoded = try self.append(self.node(self.bitsType(), .{ .unary = .{ .op = self.unaryOp(if (wide == .u64) .f64_from_u64 else .f64_from_i64), .operand = input, .op_span = self.span } }));
        return self.wrap(encoded);
    }
    /// Truncate towards zero into a fixed-width integer, trapping before conversion
    /// for nonfinite or out-of-range results.
    pub fn toInteger(self: Builder, value: typed.NodeId, target: typed.Type) std.mem.Allocator.Error!typed.Node {
        const input = try self.unwrapValue(value);
        const to: typed.UnaryOp = switch (target) {
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
        // The conversion reads the value's width: an f32 source spells its f32 operation.
        const source_ty = self.nodes.items[@backingInt(value)].ty;
        const narrowed: typed.UnaryOp = if (isF32(source_ty, self.records)) switch (to) {
            .f64_to_i8 => .f32_to_i8,
            .f64_to_i16 => .f32_to_i16,
            .f64_to_i32 => .f32_to_i32,
            .f64_to_i64 => .f32_to_i64,
            .f64_to_u8 => .f32_to_u8,
            .f64_to_u16 => .f32_to_u16,
            .f64_to_u32 => .f32_to_u32,
            .f64_to_u64 => .f32_to_u64,
            else => unreachable,
        } else to;
        return self.node(target, .{ .unary = .{ .op = narrowed, .operand = input, .op_span = self.span } });
    }
    /// Apply one binary64 unary operation (spelled for this domain's width), keeping the result in the domain.
    pub fn unary(self: Builder, op: typed.UnaryOp, value: typed.NodeId) std.mem.Allocator.Error!typed.Node {
        const input = try self.bits(value);
        const result = try self.append(self.node(self.bitsType(), .{ .unary = .{ .op = self.unaryOp(op), .operand = input, .op_span = self.span } }));
        return self.wrap(result);
    }
    /// Convert a value of the other floating domain: `float` widens an `f32` exactly, and `f32`
    /// rounds a `float` to the nearest binary32 value.
    pub fn convert(self: Builder, value: typed.NodeId, source: typed.Type) std.mem.Allocator.Error!typed.Node {
        const input = try self.unwrapValue(value);
        const op: typed.UnaryOp = if (isF32(source, self.records)) .f64_from_f32 else .f32_from_f64;
        const result = try self.append(self.node(if (op == .f64_from_f32) .u64 else .u32, .{ .unary = .{ .op = op, .operand = input, .op_span = self.span } }));
        return self.wrap(result);
    }
    /// A fused multiply-add of three values of this domain, `a * b + c` with one rounding.
    pub fn fma(self: Builder, a: typed.NodeId, b: typed.NodeId, c: typed.NodeId) std.mem.Allocator.Error!typed.Node {
        const input_a = try self.unwrapValue(a);
        const input_b = try self.unwrapValue(b);
        const input_c = try self.unwrapValue(c);
        const result = try self.append(self.node(self.bitsType(), .{ .float_fma = .{ .a = input_a, .b = input_b, .c = input_c, .op_span = self.span } }));
        return self.wrap(result);
    }
    /// Numeric equality compares floating values rather than their raw bit representations.
    pub fn binary(self: Builder, op: ast.BinaryOp, left: typed.NodeId, right: typed.NodeId, sink: *diagnostic.Sink) diagnostic.Error!typed.Node {
        var lhs = try self.bits(left);
        var rhs = try self.bits(right);
        const operation: typed.BinaryOp = self.spelled(switch (op) {
            .add => .f64_add,
            .sub => .f64_sub,
            .mul => .f64_mul,
            .div, .python_div, .floor_div, .floor_rem => .f64_div,
            .eq, .ne => .f64_eq,
            .lt, .gt => .f64_lt,
            .le, .ge => .f64_le,
            else => return sink.fail("E_FLOAT_OPERATION", self.span, "float supports arithmetic and numeric comparison"),
        });
        if (op == .gt or op == .ge) std.mem.swap(typed.NodeId, &lhs, &rhs);
        const comparison = operation == self.spelled(.f64_eq) or operation == self.spelled(.f64_lt) or operation == self.spelled(.f64_le);
        const result = self.node(if (comparison) .bool else self.bitsType(), .{ .binary = .{ .op = operation, .left = lhs, .right = rhs, .op_span = self.span } });
        if (op == .floor_div or op == .floor_rem) {
            const quotient = try self.append(result);
            const floor = try self.append(self.node(self.bitsType(), .{ .unary = .{ .op = self.unaryOp(.f64_floor), .operand = quotient, .op_span = self.span } }));
            if (op == .floor_div) return self.wrap(floor);
            const product = try self.append(self.node(self.bitsType(), .{ .binary = .{ .op = self.spelled(.f64_mul), .left = floor, .right = rhs, .op_span = self.span } }));
            const remainder = try self.append(self.node(self.bitsType(), .{ .binary = .{ .op = self.spelled(.f64_sub), .left = lhs, .right = product, .op_span = self.span } }));
            return self.wrap(remainder);
        }
        if (op == .ne) return self.node(.bool, .{ .unary = .{ .op = .not, .operand = try self.append(result), .op_span = self.span } });
        return if (comparison) result else self.wrap(try self.append(result));
    }
};
