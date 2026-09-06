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

// spec: DOMAIN-EQUALITY-1
test "domain equality compares every scalar backing by value" {
    for ([_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" }) |width| {
        const source = try std.fmt.allocPrint(t.allocator, "domain D:{s}{{fn make(n:{s})->D{{return wrap<D>(n);}}}}fn main()->i64{{" ++
            "let a=D.make(7{s});let b=D.make(8{s});if a==a && a!=b && !(a==b) && !(a!=a){{return 1;}}return 0;}}", .{ width, width, width, width });
        defer t.allocator.free(source);
        try expectValue(t.allocator, source, 1);
    }
    try expectValue(t.allocator, comparison, 1);
    try expectValue(t.allocator, "domain D:i64{fn make(n:i64)->D{return wrap<D>(n);}}fn main()->i64{if D.make(-9223372036854775808)==D.make(-9223372036854775808) && D.make(-1)!=D.make(1){return 1;}return 0;}", 1);
    try expectValue(t.allocator, "domain D:bool{fn make(n:bool)->D{return wrap<D>(n);}}fn main()->i64{let a=D.make(true);let b=D.make(false);if a==a && b==b && a!=b && !(a==b) && !(a!=a){return 1;}return 0;}", 1);
}

test "domain equality preserves opacity and rejects mixed IDs arithmetic ordering and integer requirements" {
    const cases = [_]struct { source: []const u8, code: []const u8 = "E_TYPE" }{
        .{ .source = "fn main()->i64{discard Id.make(1u64)==Other.make(1u64);return 0;}" },
        .{ .source = "fn main()->i64{discard Id.make(1u64)!=Other.make(1u64);return 0;}" },
        .{ .source = "fn main()->i64{discard Id.make(1u64)==1u64;return 0;}" },
        .{ .source = "fn main()->i64{discard Id.make(1u64)+Id.make(1u64);return 0;}" },
        .{ .source = "fn main()->i64{discard Id.make(1u64)<Id.make(1u64);return 0;}" },
        .{ .source = "fn main()->i64{discard unwrap(Id.make(1u64));return 0;}", .code = "E_PRIVATE_DOMAIN" },
        .{ .source = "fn same<T:integer>(a:T,b:T)->bool{return a==b;}fn main()->i64{discard same::<Id>(Id.make(1u64),Id.make(1u64));return 0;}", .code = "E_GENERIC_ARGUMENT" },
    };
    for (cases) |case| {
        const source = try std.mem.concat(t.allocator, u8, &.{ declarations, case.source });
        defer t.allocator.free(source);
        var compilation = try language.Compilation.init(t.allocator, "bad.my", source);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "domain equality participates in generic equality contracts" {
    try expectValue(t.allocator, declarations ++ "fn same<T:equality>(a:T,b:T)->bool{return a==b;}" ++
        "fn different<T:equality>(a:T,b:T)->bool{return a!=b;}" ++
        "fn main()->i64{if same::<Id>(Id.make(1u64),Id.make(1u64)) && different::<Other>(Other.make(1u64),Other.make(2u64)){return 1;}return 0;}", 1);
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

test "domain equality is explicitly deferred by the historical C emitter" {
    var compilation = try language.Compilation.init(t.allocator, "native.my", comparison);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.emitC(t.allocator));
    try t.expectEqualStrings("E_NATIVE_FEATURE", compilation.diagnostics.items[0].code);
}

const Modules = struct {
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, if (context == null)
            "module main;import left as a;import bridge as b;fn main()->i64{if a::Id.make(9u64)==b::make(9u64){return 1;}return 0;}"
        else
            "module main;import left as a;import right as b;fn main()->i64{discard a::Id.make(9u64)==b::Id.make(9u64);return 0;}");
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

test "domain equality loops and traps reclaim bounded runtime storage" {
    var compilation = try language.Compilation.init(t.allocator, "loop.my", declarations ++
        "fn main()->i64{let mut n=0u64;while Id.make(n)!=Id.make(10000u64){n=n+1u64;}return cast<i64>(n);}");
    defer compilation.deinit();
    try compilation.emit();
    var limiter = @import("test_support.zig").LimitedLiveAllocator{ .parent = t.allocator, .limit = 4096 };
    defer limiter.deinit();
    try t.expectEqual(@as(i64, 10000), (try compilation.execute(limiter.allocator())).value);
    try t.expectEqual(@as(usize, 0), limiter.live);
    try t.expectEqualStrings("R_STEP_LIMIT", (try compilation.executeWithOptions(limiter.allocator(), .{ .max_steps = 50 })).trap.code);
    try t.expectEqual(@as(usize, 0), limiter.live);
    var trapped = try language.Compilation.init(t.allocator, "order.my", declarations ++
        "fn left()->Id{return Id.make(1u64/0u64);}fn right()->Id{return Id.make(18446744073709551615u64+1u64);}" ++
        "fn main()->i64{discard left()==right();return 0;}");
    defer trapped.deinit();
    const outcome = try trapped.execute(t.allocator);
    try t.expectEqualStrings("R_DIVISION_BY_ZERO", outcome.trap.code);
    try t.expectEqualStrings("left", outcome.trap.stack.frames[0].function);
}
