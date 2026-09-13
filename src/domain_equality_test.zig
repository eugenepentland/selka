//! Scalar domain equality preserves nominal boundaries without exposing backing values.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const typed = @import("typed.zig");
const declarations = "domain Id:u64{fn make(n:u64)->Id{return wrap<Id>(n);}}" ++
    "domain Other:u64{fn make(n:u64)->Other{return wrap<Other>(n);}}";
const comparison = declarations ++ "fn main()->i64{if Id.make(18446744073709551615u64)==Id.make(18446744073709551615u64){return 1;}return 0;}";

fn expectValue(allocator: std.mem.Allocator, source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(allocator, "equality.my", source);
    defer compilation.deinit();
    try t.expectEqual(expected, (try compilation.execute(allocator)).value);
}

fn allocationFailures(allocator: std.mem.Allocator) !void {
    try expectValue(allocator, comparison, 1);
}

test "domain equality releases operands on allocation failures" {
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocationFailures, .{});
}

fn domainComparison(code: language.bytecode.Program) !*language.bytecode.Instruction {
    for (code.functions) |function| for (function.scope.instructions) |*instruction| {
        if (instruction.op == .cmp_domain) return @constCast(instruction);
    };
    return error.TestUnexpectedResult;
}

test "domain equality bytecode rejects invalid comparison schemas and mismatched operand identities" {
    var compilation = try language.Compilation.init(t.allocator, "bytecode.my", comparison);
    defer compilation.deinit();
    try compilation.emit();
    const code = compilation.code.?;
    const dump = try @import("disassemble.zig").dump(t.allocator, code, compilation.src);
    defer t.allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "CMP_DOMAIN Id eq") != null);
    try language.bytecode.validate(t.allocator, code);
    const instruction = try domainComparison(code);
    const original = instruction.*;
    defer instruction.* = original;
    for ([_]typed.Type{ .i64, .bool, @fromBackingInt(999999) }) |invalid| {
        instruction.op.cmp_domain.ty = invalid;
        try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, code));
    }
    // Other is a valid domain schema, but the stack still contains Id values.
    instruction.op.cmp_domain.ty = code.records[1].id;
    try language.bytecode.validate(t.allocator, code);
    try t.expectError(error.InternalError, language.vm.run(t.allocator, code));
}

test "domain equality emits native comparisons without a feature rejection" {
    var compilation = try language.Compilation.init(t.allocator, "native.my", comparison);
    defer compilation.deinit();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

const Modules = struct {
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, if (context == null)
            "module main;import left as a;import bridge as b;fn main()->i64{if a::Id.make(9u64)==b::make(9u64){return 1;}return 0;}"
        else
            "module main;import left as a;import right as b;fn main()->i64{_ = a::Id.make(9u64)==b::Id.make(9u64);return 0;}");
        if (std.mem.eql(u8, path, "bridge.my")) return allocator.dupe(u8, "module bridge;import left as alias;export make;fn make(n:u64)->alias::Id{return alias::Id.make(n);}");
        if (std.mem.eql(u8, path, "left.my")) return allocator.dupe(u8, "module left;export Id;" ++ declarations);
        if (std.mem.eql(u8, path, "right.my")) return allocator.dupe(u8, "module right;export Id;" ++ declarations);
        return error.NotFound;
    }
};

test "domain equality resolves declaration identity through module aliases" {
    var marker: u8 = 0;
    for ([_]?*anyopaque{ null, &marker }) |context| {
        var project = language.project.Project.init(t.allocator);
        defer project.deinit();
        try project.load(.{ .context = context, .read = Modules.read }, "main", .{});
        var index = try language.interfaces.build(&project);
        var compilation = try language.project_compile.Compilation.init(&index);
        if (context == null) {
            try compilation.emit();
            try t.expectEqual(@as(i64, 1), (try language.vm.run(t.allocator, compilation.code.?)).value);
        } else {
            try t.expectError(error.SourceError, compilation.check());
            try t.expectEqualStrings("E_TYPE", compilation.diagnostics.items.items[0].code);
        }
    }
}
