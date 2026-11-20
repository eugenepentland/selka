//! Register access on a device (MCU-B1D): on a target that provides `main` its `Registers` (`Target.provides`), each
//! `registers.read8/16/32` and `write8/16/32` is one volatile load or store of its width at the address, inline.
//!
//! Until emission the access is what `build_registers.zig` built on every target: a call of an opaque runtime function
//! (`myl_core_registers_read32` and the rest, `runtime_c` linkage). No Core pass removes, merges or reorders a runtime
//! call: they read and write everything they are given (`effects.zig`), are never pure, and keep their order in the
//! block. Here the call becomes the access itself, and LLVM keeps every volatile access, its width and its order. The
//! handle is not read: a device has one register space. On every other target the call stays a call of the simulated
//! bank (`runtime/core_registers.c`), and this file changes nothing.
//!
//! The `cpu` operations (MCU-NOC1) are the same kind of call until here, where each becomes its instruction as LLVM inline
//! assembly with a memory clobber (`instructions`): LLVM moves no memory access across one, and nothing is called.
const std = @import("std");
const ir = @import("ir.zig");
const target_description = @import("target.zig");

/// The emitter's failures: allocation, and an operand it cannot name.
pub const Error = @import("emit_cap.zig").Error;

/// One access: its runtime function, the LLVM integer it moves and whether it stores.
const Access = struct { symbol: []const u8, llvm: []const u8, bytes: u8, store: bool };

const accesses = [_]Access{
    .{ .symbol = "myl_core_registers_read8", .llvm = "i8", .bytes = 1, .store = false },
    .{ .symbol = "myl_core_registers_read16", .llvm = "i16", .bytes = 2, .store = false },
    .{ .symbol = "myl_core_registers_read32", .llvm = "i32", .bytes = 4, .store = false },
    .{ .symbol = "myl_core_registers_write8", .llvm = "i8", .bytes = 1, .store = true },
    .{ .symbol = "myl_core_registers_write16", .llvm = "i16", .bytes = 2, .store = true },
    .{ .symbol = "myl_core_registers_write32", .llvm = "i32", .bytes = 4, .store = true },
};

/// One `cpu` instruction: its runtime function, the assembly, and whether it answers PRIMASK or takes the value to set.
const Instruction = struct { symbol: []const u8, assembly: []const u8, primask: enum { none, answers, takes } };

const instructions = [_]Instruction{
    .{ .symbol = "myl_core_registers_cpu_wait_for_event", .assembly = "wfe", .primask = .none },
    .{ .symbol = "myl_core_registers_cpu_wait_for_interrupt", .assembly = "wfi", .primask = .none },
    .{ .symbol = "myl_core_registers_cpu_send_event", .assembly = "sev", .primask = .none },
    .{ .symbol = "myl_core_registers_cpu_barrier", .assembly = "dsb sy\\0Aisb sy", .primask = .none },
    .{ .symbol = "myl_core_registers_cpu_breakpoint", .assembly = "bkpt #0", .primask = .none },
    .{ .symbol = "myl_core_registers_cpu_interrupts_disable", .assembly = "mrs $0, primask\\0Acpsid i", .primask = .answers },
    .{ .symbol = "myl_core_registers_cpu_interrupts_set", .assembly = "msr primask, $0", .primask = .takes },
};

/// The instruction `function` is on `target`, or null: on a target without registers, and for every other function.
fn instructionOf(target: target_description.Target, function: *const ir.Function) ?*const Instruction {
    if (!target.provides(.registers) or function.signature.linkage != .runtime_c) return null;
    for (&instructions) |*instruction| if (std.mem.eql(u8, function.name, instruction.symbol)) return instruction;
    return null;
}

/// The access `function` is on `target`, or null: on a target without registers, and for every other function.
fn accessOf(target: target_description.Target, function: *const ir.Function) ?*const Access {
    if (!target.provides(.registers) or function.signature.linkage != .runtime_c) return null;
    for (&accesses) |*access| if (std.mem.eql(u8, function.name, access.symbol)) return access;
    return null;
}

/// Whether `function` needs no declaration on `target`: its calls are emitted as accesses or instructions (`runtimeCall`).
pub fn declaration(target: target_description.Target, function: *const ir.Function) bool {
    return accessOf(target, function) != null or instructionOf(target, function) != null;
}

/// Emit `inst`, a call of a register access or a `cpu` instruction on a target with registers, as the volatile load or
/// store or the instruction itself; false for every other instruction, which the caller emits as before.
pub fn runtimeCall(comptime Context: type, context: Context, out: *std.ArrayList(u8), name: []const u8, inst: ir.Inst) Error!bool {
    if (inst.op != .call) return false;
    const callee = &context.state.module.functions.items[inst.a.index()];
    if (instructionOf(context.state.options.target, callee)) |instruction| return emitInstruction(Context, context, out, name, inst, instruction);
    const access = accessOf(context.state.options.target, callee) orelse return false;
    const operands = context.function.operands(inst.data);
    const address = try context.value(operands[1]);
    try out.print(context.a(), "  {s}.at = inttoptr i32 {s} to ptr\n", .{ name, address });
    if (access.store) {
        const stored = try context.value(operands[2]);
        try out.print(context.a(), "  store volatile {s} {s}, ptr {s}.at, align {d}\n", .{ access.llvm, stored, name, access.bytes });
    } else {
        try out.print(context.a(), "  {s} = load volatile {s}, ptr {s}.at, align {d}\n", .{ name, access.llvm, name, access.bytes });
    }
    return true;
}

/// The instruction as one `asm sideeffect` call; its memory clobber keeps every load and store on its side of it.
fn emitInstruction(comptime Context: type, context: Context, out: *std.ArrayList(u8), name: []const u8, inst: ir.Inst, instruction: *const Instruction) Error!bool {
    switch (instruction.primask) {
        .none => try out.print(context.a(), "  call void asm sideeffect \"{s}\", \"{s}\"()\n", .{ instruction.assembly, "~{memory}" }),
        .answers => try out.print(context.a(), "  {s} = call i32 asm sideeffect \"{s}\", \"{s}\"()\n", .{ name, instruction.assembly, "=r,~{memory}" }),
        .takes => {
            const value = try context.value(context.function.operands(inst.data)[1]);
            try out.print(context.a(), "  call void asm sideeffect \"{s}\", \"{s}\"(i32 {s})\n", .{ instruction.assembly, "r,~{memory}", value });
        },
    }
    return true;
}
