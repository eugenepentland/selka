//! Helpers the new core's unit tests share: check a single-file program from
//! source text and build or render its Core IR.
const std = @import("std");
const language = @import("mylang");
const ir = @import("ir.zig");
const build = @import("build.zig");
const print = @import("print.zig");
const emit_llvm = @import("emit_llvm.zig");
const facts = @import("facts.zig");
const passes = @import("passes.zig");

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

/// The textual Core IR of `source` after the release fact pass marked what it proved.
pub fn factsText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try buildSource(arena, source, &refusal);
    for (module.functions.items) |*function| {
        if (function.signature.linkage == .internal) _ = try facts.analyze(arena, function, .{});
    }
    return print.module(arena, &module);
}

/// The textual Core IR of `source` after the release passes.
pub fn optimizedText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try buildSource(arena, source, &refusal);
    _ = try passes.run(arena, &module, .trusted);
    return print.module(arena, &module);
}

/// The LLVM IR a release build of `source` emits.
pub fn releaseLlvmText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try buildSource(arena, source, &refusal);
    const result = try passes.run(arena, &module, .trusted);
    const context: u8 = 0;
    return emit_llvm.emitModule(arena, &module, .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = "test.my", .main_parameters = &.{ "args", "out" }, .facts = result.known, .vectors = result.plans });
}
