//! `value is PATTERN`: the test of which case an enum, a union, an Option or a Result holds, as a `bool`.
//!
//! The parser builds a `match` for the test (`ast.Node.variant_test`): one arm per listed case, each with an empty body,
//! then a wildcard. The match is checked as any other, so the qualifiers, the duplicates, the payload arities and the
//! refusals of an unhandled result all read as they do in a `match`. What this file adds is the lowering: the checked
//! match is kept, its listed arms now set a hidden `bool` to true and every other arm to false, and the test is the block
//! that runs the match and reads the `bool`, as `x is None` does.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const collections = @import("collection_lower.zig");
const Error = diagnostic.Error;

/// The code of a pattern that binds names where no `if`, `elif` or `while` condition holds it.
pub const binding_code = "E_IS_BINDING";
/// The code of an `is` test whose operand has no cases to test.
pub const operand_code = "E_IS_OPERAND";
/// Why a binding pattern is refused outside the whole condition of an `if`, `elif` or `while`.
pub const binding_message = "a pattern that binds names can only be the whole condition of an `if`, `elif` or `while`, where the names belong to its body; use `match` anywhere else";
/// Why an operand without cases is refused.
pub const operand_message = "`is` tests which case an enum, a union, an Option or a Result holds; this value has no cases";
/// The payload of the syntax node.
pub const Test = @FieldType(@FieldType(ast.Node, "data"), "variant_test");

/// Check a test whose pattern binds nothing and type it as a `bool`.
pub fn check(comptime Checker: type, self: *Checker, node: ast.Node, test_node: Test) Error!typed.Node {
    if (test_node.binds) return self.sink.fail(binding_code, node.span, binding_message);
    try self.hintOptionOperand(test_node.value);
    const value = try self.expression(test_node.value);
    const value_type = self.nodes.items[@backingInt(value)].ty;
    const operand_span = self.syntax.nodes.items[@backingInt(test_node.value)].span;
    if (!value_type.isAggregate() or self.catalog.records[value_type.recordIndex()].shape.variants == null)
        return self.sink.fail(operand_code, operand_span, operand_message);
    const checked = try self.statement(test_node.check);
    const index = @backingInt(checked.id);
    const matched = switch (self.statements.items[index].data) {
        .match => |found| found,
        else => return error.InternalError,
    };
    if (matched.arms.len < test_node.explicit) return error.InternalError;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const slot = try b.local(.bool);
    const yes = try b.stmt(.{ .initialize = .{ .slot = slot, .value = try b.node(.bool, .{ .boolean = true }) } });
    const no = try b.stmt(.{ .initialize = .{ .slot = slot, .value = try b.node(.bool, .{ .boolean = false }) } });
    const arms = try self.allocator.alloc(typed.MatchArm, matched.arms.len);
    for (matched.arms, arms, 0..) |arm, *out, position| out.* = .{ .tag = arm.tag, .slot = null, .body = if (position < test_node.explicit) yes else no };
    self.statements.items[index].data = .{ .match = .{ .value = matched.value, .arms = arms } };
    return b.block(&.{checked.id}, try b.read(slot));
}
