//! The `registers` and `cpu` standard modules' operations, built as runtime calls (MCU-B1, MCU-NOC1).
//!
//! `@stdlib/registers.selka` and `@stdlib/cpu.selka` declare each operation as a `builtin func`; this builder writes its body as
//! one call of its runtime function (`runtime/core_registers.c`), which reads, writes or records on the simulated bank the
//! handle names. A bank is allocated whole by `simulated()`, so every other call allocates nothing and is allowed in a
//! `@noalloc` function (`cost.zig`, `runtimeAllocationFree`); `script32` copies its values when it is given them, so it
//! allocates too. On a device target the reads and writes are built the same way and emitted as volatile loads and stores,
//! and the `cpu` operations as their instructions (`emit_registers.zig`); a build for a device refuses the functions only a
//! simulated bank has (`simulatedCall`).
const std = @import("std");
const ir = @import("ir.zig");
const tools = @import("test_builder.zig");
const language = @import("selka");

/// Allocation and an unsupported declaration are the lowering failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Where an operation exists: on every target, only with a simulated bank (a device's registers are reached by the
/// reads and writes alone), or only on a device (starting the second core, MCU-CORE1: the bare runtime has it).
pub const Place = enum { everywhere, simulated, device };

/// One operation: its module's source path, its name in the module, its runtime function, where it exists, and the
/// function a refusal names (`registers.poke32`; a private `cpu` reader names the public function over it).
pub const Operation = struct { path: []const u8, name: []const u8, symbol: []const u8, place: Place, shown: []const u8 };

/// A `registers` operation: its runtime function is `myl_core_registers_NAME`.
fn register(comptime name: []const u8, comptime place: Place) Operation {
    return .{ .path = "@stdlib/registers.selka", .name = name, .symbol = runtime_prefix ++ name, .place = place, .shown = "registers." ++ name };
}

/// A `cpu` operation (MCU-NOC1): its runtime function is `myl_core_registers_cpu_NAME`, the name without the leading
/// underscores of a private one, and a refusal names `shown`.
fn cpu(comptime name: []const u8, comptime place: Place, comptime shown: []const u8) Operation {
    const bare = std.mem.trimStart(u8, name, "_");
    return .{ .path = "@stdlib/cpu.selka", .name = name, .symbol = runtime_prefix ++ "cpu_" ++ bare, .place = place, .shown = "cpu." ++ shown };
}

/// The operations, in the module's order. The runtime function takes the declaration's parameters and answers its result.
const operations = [_]Operation{
    register("simulated", .simulated),
    register("read8", .everywhere),
    register("read16", .everywhere),
    register("read32", .everywhere),
    register("write8", .everywhere),
    register("write16", .everywhere),
    register("write32", .everywhere),
    register("poke32", .simulated),
    register("script32", .simulated),
    register("pin32", .simulated),
    register("write_count", .simulated),
    register("write_address", .simulated),
    register("write_value", .simulated),
    register("write_width", .simulated),
    register("start_core1", .device),
    cpu("wait_for_event", .everywhere, "wait_for_event"),
    cpu("wait_for_interrupt", .everywhere, "wait_for_interrupt"),
    cpu("send_event", .everywhere, "send_event"),
    cpu("barrier", .everywhere, "barrier"),
    cpu("breakpoint", .everywhere, "breakpoint"),
    cpu("__interrupts_disable", .everywhere, "interrupts_off"),
    cpu("__interrupts_set", .everywhere, "interrupts_restore"),
    cpu("event_count", .simulated, "event_count"),
    cpu("__event_kind", .simulated, "event_operation"),
    cpu("event_writes_before", .simulated, "event_writes_before"),
    cpu("__interrupts_now", .simulated, "interrupts_are_off"),
    cpu("__write_interrupts_off", .simulated, "write_with_interrupts_off"),
};

/// The `registers` or `cpu` function only a simulated bank has whose runtime function the LLVM text `llvm` names
/// (`@symbol`), as `registers.NAME` or `cpu.NAME`, or null when it names none. A build for a device refuses such a program
/// (`E_TARGET_SIMULATED_REGISTERS`) rather than leave the symbol to fail the link.
pub fn simulatedCall(llvm: []const u8) ?[]const u8 {
    return placedCall(llvm, .simulated);
}

/// The `registers` function only a device has (`start_core1`) whose runtime function the LLVM text `llvm` names, as
/// `registers.NAME`, or null when it names none. A hosted build refuses such a program (`E_TARGET_DEVICE_REGISTERS`):
/// the hosted runtime has no second core to start.
pub fn deviceCall(llvm: []const u8) ?[]const u8 {
    return placedCall(llvm, .device);
}

/// The first operation of `place` whose runtime function `llvm` names (`@symbol(`), as the function a refusal names.
fn placedCall(llvm: []const u8, place: Place) ?[]const u8 {
    const prefix = "@" ++ runtime_prefix;
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, llvm, from, prefix)) |at| {
        from = at + prefix.len;
        const end = std.mem.indexOfScalarPos(u8, llvm, from, '(') orelse continue;
        for (&operations) |*operation| {
            if (operation.place == place and std.mem.eql(u8, llvm[at + 1 .. end], operation.symbol)) return operation.shown;
        }
    }
    return null;
}

/// The runtime function prefix of every operation: each is a scalar call that allocates nothing (`zero_rc.zig`).
pub const runtime_prefix = "myl_core_registers_";

/// The operation `checked` declares, or null for every other function.
pub fn matched(source: ?language.source.Source, checked: language.typed.Function) ?*const Operation {
    const src = source orelse return null;
    if (!checked.policy.builtin) return null;
    const path = src.locate(checked.declaration.start).path;
    const name = src.text(checked.declaration);
    for (&operations) |*operation| if (std.mem.eql(u8, path, operation.path) and std.mem.eql(u8, name, operation.name)) return operation;
    return null;
}

/// Build one operation as a call of its runtime function with the declaration's parameters. The call keeps the
/// declaration's own source position, so a trap in it reports `registers.selka` and then the caller's frames.
pub fn build(mb: anytype, declared: ir.Function, operation: *const Operation) Error!ir.Function {
    var b: tools.Builder = .{ .arena = mb.allocator, .function = declared };
    const entry = try b.block();
    const params = declared.signature.params;
    const ret = declared.signature.ret;
    const callee = try mb.runtimeFunction(operation.symbol, params, ret, .runtime_c);
    var arguments: [4]ir.Ref = undefined;
    for (params, 0..) |ty, index| {
        // Outside the block, as `build_json.zig` writes them: a parameter the ownership validator sees as borrowing from
        // the caller, which `script32`'s list view does.
        arguments[index] = try b.detached(.{ .op = .param, .ty = ty, .data = @intCast(index), .span = declared.span });
    }
    const result = try b.put(entry, .{
        .op = .call,
        .ty = ret,
        .a = @fromBackingInt(callee),
        .data = try b.extra(arguments[0..params.len]),
        .span = declared.span,
    });
    if (ret == .void) {
        _ = try b.put(entry, .{ .op = .ret, .ty = .void, .span = declared.span });
    } else {
        _ = try b.put(entry, .{ .op = .ret, .ty = .void, .a = result, .span = declared.span });
    }
    return b.function;
}
