//! In-memory instruction records with source maps; there is no bytecode loader.
const Span = @import("source.zig").Span;
const typed = @import("typed.zig");
pub const Predicate = enum { eq, ne, lt, le, gt, ge };
pub const Equality = enum { eq, ne };
pub const Instruction = struct {
    span: Span,
    op: union(enum) {
        push_i64: i64,
        push_bool: bool,
        load_local: typed.LocalId,
        store_local: typed.LocalId,
        add_i64_checked,
        sub_i64_checked,
        mul_i64_checked,
        neg_i64_checked,
        cmp_i64: Predicate,
        cmp_bool: Equality,
        not_bool,
        ret,
    },
};
pub const Function = struct { id: typed.FunctionId, name: []const u8, locals: []const typed.Local = &.{}, instructions: []const Instruction };
pub const Program = struct { functions: []const Function };
pub fn validate(program: Program) error{InternalError}!void {
    if (program.functions.len != 1) return error.InternalError;
    for (program.functions, 0..) |function, i| {
        if (@backingInt(function.id) != i) return error.InternalError;
        var height: usize = 0;
        var returned = false;
        for (function.instructions) |instruction| {
            if (returned) return error.InternalError;
            switch (instruction.op) {
                .push_i64, .push_bool => height += 1,
                .load_local => |slot| {
                    if (@backingInt(slot) >= function.locals.len) return error.InternalError;
                    height += 1;
                },
                .store_local => |slot| {
                    if (@backingInt(slot) >= function.locals.len or height == 0) return error.InternalError;
                    height -= 1;
                },
                .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .cmp_i64, .cmp_bool => {
                    if (height < 2) return error.InternalError;
                    height -= 1;
                },
                .neg_i64_checked, .not_bool => if (height < 1) {
                    return error.InternalError;
                },
                .ret => {
                    if (height != 1) return error.InternalError;
                    returned = true;
                },
            }
        }
        if (!returned) return error.InternalError;
    }
}
