//! The `testing` standard module's two counter readers, built as runtime calls.
//!
//! `@stdlib/testing.selka` declares `func __test_blocks() -> int` and
//! `func __test_allocations(on: bool) -> int` as private functions whose checked
//! bodies are placeholders; this builder replaces each body with the audited
//! runtime helper that reads the test child's own counters (B5). The spellings are
//! reserved: ordinary source that names them is `E_INTERNAL_NAME`, and the module
//! functions themselves are private, so only `testing.steps`, `testing.allocations`
//! and the growth helpers reach a counter.
const std = @import("std");
const ir = @import("ir.zig");
const tools = @import("test_builder.zig");
const language = @import("selka");

/// Allocation and an unsupported declaration are the lowering failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// The internal declarations this builder owns, in source order.
const internal = [_][]const u8{ "__test_blocks", "__test_allocations" };

/// The internal declaration `checked` names, or null for every other function.
pub fn matched(source: ?language.source.Source, checked: language.typed.Function) ?[]const u8 {
    const src = source orelse return null;
    if (!std.mem.eql(u8, src.locate(checked.declaration.start).path, "@stdlib/testing.selka")) return null;
    const name = src.text(checked.declaration);
    for (internal) |candidate| if (std.mem.eql(u8, name, candidate)) return candidate;
    return null;
}

/// Build one counter reader as a call of its runtime helper. The call keeps the
/// internal declaration's own source position, so a trap reports `testing.selka`
/// rather than the caller's first line.
pub fn build(mb: anytype, declared: ir.Function, name: []const u8) Error!ir.Function {
    var b: tools.Builder = .{ .arena = mb.allocator, .function = declared };
    const entry = try b.block();
    if (std.mem.eql(u8, name, "__test_blocks")) {
        const read = try mb.runtimeFunction("myl_core_test_blocks", &.{}, .i64, .runtime_c);
        const count = try b.put(entry, .{
            .op = .call,
            .ty = .i64,
            .a = @fromBackingInt(read),
            .data = try b.extra(&.{}),
            .span = declared.span,
        });
        _ = try b.put(entry, .{ .op = .ret, .ty = .void, .a = count });
        return b.function;
    }
    if (std.mem.eql(u8, name, "__test_allocations")) {
        const read = try mb.runtimeFunction("myl_core_test_allocations", &.{.bool}, .i64, .runtime_c);
        const on = try b.put(entry, .{ .op = .param, .ty = .bool, .data = 0 });
        const count = try b.put(entry, .{
            .op = .call,
            .ty = .i64,
            .a = @fromBackingInt(read),
            .data = try b.extra(&.{on}),
            .span = declared.span,
        });
        _ = try b.put(entry, .{ .op = .ret, .ty = .void, .a = count });
        return b.function;
    }
    return mb.refuse("unsupported testing counter declaration", declared.span);
}
