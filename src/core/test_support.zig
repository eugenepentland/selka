//! Helpers the new core's unit tests share: check a single-file program from
//! source text and build or render its Core IR.
const std = @import("std");
const language = @import("mylang");
const ir = @import("ir.zig");
const build = @import("build.zig");
const print = @import("print.zig");
const emit_llvm = @import("emit_llvm.zig");

/// Everything checking, building or emitting a test program can fail with.
pub const Error = language.diagnostic.Error || build.Error || emit_llvm.Error;

/// Check `source` as a header-less program and build its Core IR in `arena`.
pub fn buildSource(arena: std.mem.Allocator, source: []const u8, refusal: *build.Refusal) Error!ir.Module {
    var unit = try language.Compilation.init(arena, "test.my", source);
    try unit.check();
    return build.buildModule(arena, unit.program.?, refusal);
}

/// The textual Core IR of `source`.
pub fn irText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    const module = try buildSource(arena, source, &refusal);
    return print.module(arena, &module);
}

fn firstLine(_: *const anyopaque, offset: u32) emit_llvm.Location {
    return .{ .line = 1, .column = offset + 1 };
}

/// The LLVM IR of `source`, with every trap located at line 1.
pub fn llvmText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    const module = try buildSource(arena, source, &refusal);
    const context: u8 = 0;
    return emit_llvm.emitModule(arena, &module, .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = "test.my", .main_parameters = &.{"out"} });
}
