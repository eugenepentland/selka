//! `case_name(value)` and `Kind.from_name(text)` in Core: a chain of tag tests (the shape a `match` over the cases lowers to)
//! that ends in the case's static name, or in the case a name spells. Both reach here as a typed `cast` (`enum_cases.zig`):
//! an enum value to `str`, or a `str` or `bytes` to an option of the enum.
const std = @import("std");
const ir = @import("ir.zig");
const typed = @import("selka").typed;

/// Allocation or a representation the lowering does not know stops this stage.
pub const Error = error{ OutOfMemory, Unsupported };

/// A static text of `family` (`str` or `bytes`) that spells `text`.
fn literal(comptime Context: type, b: Context, text: []const u8, family: ir.Type, span: u32) Error!ir.Ref {
    const index = b.mb.module.strings.items.len;
    try b.mb.module.strings.append(b.allocator(), text);
    return b.detached(.{ .op = .str_const, .ty = family, .data = index, .span = span });
}

/// `case_name(value)`: the declared name of the case `value` holds, as a `str` constant. The last case needs no test.
pub fn name(comptime Context: type, b: Context, value: ir.Ref, cases: []const typed.Variant, span: u32) Error!ir.Ref {
    if (cases.len == 0) return b.mb.refuse("case_name of an enum with no cases", span);
    const tag = try b.emit(.{ .op = .union_tag, .ty = .u32, .a = value, .span = span });
    const result = try b.synthetic(.str);
    const join = try b.newBlock();
    for (cases, 0..) |case, index| {
        const text = try literal(Context, b, case.name, .str, span);
        if (index + 1 == cases.len) {
            try b.write(result, b.current.?, text);
            try b.jump(join);
            break;
        }
        const expected = try b.constant(.u32, @intCast(index));
        const is_case = try b.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = expected, .data = @backingInt(ir.Predicate.eq), .span = span });
        const hit = try b.newBlock();
        const next = try b.newBlock();
        try b.branch(is_case, hit, next, span);
        try b.seal(hit);
        try b.seal(next);
        b.enter(hit);
        try b.write(result, hit, text);
        try b.jump(join);
        b.enter(next);
    }
    try b.seal(join);
    b.enter(join);
    return b.read(result, join);
}

/// `Kind.from_name(text)`: `Some(case)` for the first case whose name equals `text` (a `str`, `bytes` or a view of either),
/// else `None`. `target` is the option's own type and `option` its tags.
pub fn fromName(comptime Context: type, b: Context, text: ir.Ref, target: ir.Type, option: anytype, cases: []const typed.Variant, span: u32) Error!ir.Ref {
    const family: ir.Type = switch (b.typeOfRef(text)) {
        .str, .str_view => .str,
        .bytes, .bytes_view => .bytes,
        else => return b.mb.refuse("from_name of a value that is not text", span),
    };
    const member_type = b.module().compound(b.module().storageType(target)).@"union"[option.some];
    const result = try b.synthetic(target);
    const join = try b.newBlock();
    for (cases, 0..) |case, index| {
        const spelled = try literal(Context, b, case.name, family, span);
        const same = try b.equal(text, spelled, span);
        const hit = try b.newBlock();
        const next = try b.newBlock();
        try b.branch(same, hit, next, span);
        try b.seal(hit);
        try b.seal(next);
        b.enter(hit);
        const member = try b.emit(.{ .op = .union_make, .ty = member_type, .data = index, .span = span });
        const some = try b.emit(.{ .op = .union_make, .ty = target, .a = member, .data = option.some, .span = span });
        try b.write(result, hit, some);
        try b.jump(join);
        b.enter(next);
    }
    const none = try b.emit(.{ .op = .union_make, .ty = target, .data = option.none, .span = span });
    try b.write(result, b.current.?, none);
    try b.jump(join);
    try b.seal(join);
    b.enter(join);
    return b.read(result, join);
}
