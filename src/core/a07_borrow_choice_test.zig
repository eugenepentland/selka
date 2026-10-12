//! Exact two-root producer identities for generated text and optional selections.
const std = @import("std");
const ir = @import("ir.zig");
const selections = @import("borrow_selection.zig");

fn call(marker: u32, ty: ir.Type) ir.Inst {
    return .{ .op = .call, .ty = ty, .a = @fromBackingInt(marker), .data = (ir.ExtraSlice{ .start = 0, .len = 3 }).pack() };
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "A07 borrowed text choice markers prove exact inputs and reject owned signatures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .zero_rc = true };
    inline for (.{ selections.Kind.min_text, selections.Kind.max_text }) |kind| {
        const marker = try selections.declareChoice(a, &module, kind, .str, .str);
        var function: ir.Function = .{ .name = "choose", .signature = .{ .params = &.{ .str, .str, .str }, .ret = .void } };
        for (0..3) |index| try function.insts.append(a, .{ .op = .param, .ty = .str, .data = index });
        try function.extra.appendSlice(a, &.{ @fromBackingInt(0), @fromBackingInt(0), @fromBackingInt(1) });
        try std.testing.expect((try selections.call(&module, &function, call(marker, .str))) != null);
        function.extra.items[0] = @fromBackingInt(1);
        try std.testing.expect((try selections.call(&module, &function, call(marker, .str))) != null);
        function.extra.items[0] = @fromBackingInt(2);
        try std.testing.expectError(error.UnsupportedInstruction, selections.call(&module, &function, call(marker, .str)));
        function.extra.items[0] = @fromBackingInt(0);
        module.functions.items[marker].signature.owned = 1;
        try std.testing.expectError(error.UnsupportedInstruction, selections.call(&module, &function, call(marker, .str)));
        module.functions.items[marker].signature.owned = 0;
        try module.functions.items[marker].insts.append(a, .{ .op = .ret, .ty = .void });
        try std.testing.expectError(error.UnsupportedInstruction, selections.declaration(&module, &module.functions.items[marker]));
    }
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "A07 optional choice markers require the exact borrowed payload tag and box" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .zero_rc = true };
    const record = try module.intern(a, .{ .record = &.{ .str, .i64, .str } });
    const box = try module.intern(a, .{ .box = record });
    for ([_]ir.Type{ .str, box }) |payload| {
        const result = if (payload == box) record else payload;
        const option = try module.intern(a, .{ .@"union" = &.{ .void, payload } });
        const marker = try selections.declareChoice(a, &module, .optional_default, option, result);
        var function: ir.Function = .{ .name = "unwrap", .signature = .{ .params = &.{ option, result }, .ret = .void } };
        try function.insts.appendSlice(a, &.{
            .{ .op = .param, .ty = option, .data = 0 },
            .{ .op = .param, .ty = result, .data = 1 },
            .{ .op = .union_payload, .ty = payload, .a = @fromBackingInt(0), .data = 1 },
        });
        var selected: ir.Ref = @fromBackingInt(2);
        if (payload == box) {
            try function.insts.append(a, .{ .op = .box_get, .ty = result, .a = selected });
            selected = @fromBackingInt(3);
        }
        try function.extra.appendSlice(a, &.{ selected, @fromBackingInt(0), @fromBackingInt(1) });
        try std.testing.expect((try selections.call(&module, &function, call(marker, result))) != null);
        function.insts.items[2].data = 0;
        try std.testing.expectError(error.UnsupportedInstruction, selections.call(&module, &function, call(marker, result)));
        function.insts.items[2].data = 1;
        function.insts.items[2].op = .union_take;
        try std.testing.expectError(error.UnsupportedInstruction, selections.call(&module, &function, call(marker, result)));
        function.insts.items[2].op = .union_payload;
        if (payload == box) {
            function.insts.items[3].op = .box_take;
            try std.testing.expectError(error.UnsupportedInstruction, selections.call(&module, &function, call(marker, result)));
        }
    }
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "A07 borrowed choice identities refuse malformed shape and external authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .zero_rc = true };
    try std.testing.expectError(error.UnsupportedInstruction, selections.declareChoice(a, &module, .min_text, .bytes, .bytes));
    const invalid = try module.intern(a, .{ .@"union" = &.{ .void, .str, .str } });
    try std.testing.expectError(error.UnsupportedInstruction, selections.declareChoice(a, &module, .optional_default, invalid, .str));
    const marker = try selections.declareChoice(a, &module, .max_text, .str, .str);
    module.functions.items[marker].signature.linkage = .extern_c;
    try std.testing.expectError(error.UnsupportedInstruction, selections.declaration(&module, &module.functions.items[marker]));
    module.functions.items[marker].signature.linkage = .runtime_c;
    module.functions.items[marker].name = "myl_core_borrow_choice_v1_unknown_5_5";
    try std.testing.expectError(error.UnsupportedInstruction, selections.declaration(&module, &module.functions.items[marker]));
}
