//! The targets a build can choose (`target.zig`): the host keeps the single-target
//! compiler's text and keys, and the bare Cortex-M0+ target's text has none of the
//! host's x86, thread or unwinder marks.
const std = @import("std");
const support = @import("test_support.zig");
const targets = @import("target.zig");
const language = @import("selka");

test "the host provides every capability family `main` may ask for but `Registers`, the bare target only `Host` and `Registers`, in `capabilityIndex` order" {
    const types = [_]language.typed.Type{ .clock_cap, .random_cap, .filesystem_cap, .network_cap, .environment_cap, .stream_cap, .host_cap, .process_cap, .input_cap, .stop_cap };
    try std.testing.expectEqual(types.len + 1, std.enums.values(targets.Capability).len);
    for (types, std.enums.values(targets.Capability)[0..types.len]) |ty, family| try expectFamily(ty, family);
    try std.testing.expect(targets.host.provides(.stream) and !targets.thumbv6m_none.provides(.filesystem));
    try std.testing.expectEqual(@as(?u4, 10), language.typed.Type.registers_cap.capabilityIndex());
    try std.testing.expectEqual(@as(u4, 10), @backingInt(targets.Capability.registers));
    try std.testing.expect(targets.thumbv6m_none.provides(.registers) and !targets.host.provides(.registers));
    try std.testing.expect(targets.thumbv6m_none.provides(.host) and targets.host.provides(.host));
}

/// `family` is the capability of `ty`, the host provides it and the bare target provides it only when it is `Host`.
fn expectFamily(ty: language.typed.Type, family: targets.Capability) !void {
    try std.testing.expectEqual(@backingInt(family), ty.capabilityIndex().?);
    try std.testing.expect(targets.host.provides(family));
    try std.testing.expectEqual(family == .host, targets.thumbv6m_none.provides(family));
}

test "a target names the families it provides, in `capabilityIndex` order, for the refusal of another" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("`Host` and `Registers`", try targets.thumbv6m_none.providedNames(arena.allocator()));
    const hosted = try targets.host.providedNames(arena.allocator());
    try std.testing.expect(std.mem.startsWith(u8, hosted, "`Clock`, `Entropy`, `Filesystem`, "));
    try std.testing.expect(std.mem.endsWith(u8, hosted, "`Input` and `Stop`"));
    try std.testing.expectEqualStrings("Entropy", targets.Capability.entropy.typeName());
}

/// A summing loop the host vectorizes with AVX2, a list the allocator's free lists serve,
/// and a split on one byte, which calls `memchr`.
const summing =
    \\import strings
    \\
    \\func checksum(values: int[]) -> int:
    \\    mut total = 0
    \\    for v in values:
    \\        total = total + v * 31
    \\    return total
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    mut values: int[] = []
    \\    for i in range(16):
    \\        append(mut values, i)
    \\    const parts = strings.split(args[0], ",")
    \\    print(out, checksum(values) + len(parts))
    \\    return 0
    \\
;

test "the host target's release text keeps its AVX2 calls, thread-local free lists, unwind tables and 64-bit memchr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmTextFor(arena.allocator(), summing, targets.host);
    try std.testing.expect(std.mem.indexOf(u8, text, "@llvm.x86.avx2.") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "thread_local(localexec)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, " uwtable") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "declare ptr @memchr(ptr, i32, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "!dbg") != null);
}

test "the bare target's release text is scalar, single-threaded, has no unwind tables, a 32-bit memchr and line metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmTextFor(arena.allocator(), summing, targets.thumbv6m_none);
    try std.testing.expect(std.mem.indexOf(u8, text, "llvm.x86") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "<8 x i32>") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "thread_local") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "uwtable") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "declare ptr @memchr(ptr, i32, i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@memchr(ptr, i32, i64)") == null);
    // The emitted text keeps the one-core runtime's plain free lists: only the driver's two-core flavour rewrites them.
    try std.testing.expect(std.mem.indexOf(u8, text, "@myl_core_free_lists = external global") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "emutls") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "!dbg") != null);
}

/// Lists a function returns and its caller drops: the free lists' inline fast path is in the text.
const returned_lists =
    \\func numbers(count: int) -> int[]:
    \\    mut values: int[] = []
    \\    for i in range(count):
    \\        append(mut values, i)
    \\    return values
    \\
    \\func main(args: str[]) -> int:
    \\    mut total = 0
    \\    for round in range(4):
    \\        for value in numbers(10 + round + len(args)):
    \\            total += value
    \\    return total % 256
    \\
;

test "the two-core flavour's text asks the runtime for the calling core's free lists at every access, and declares no plain ones" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmTextFor(arena.allocator(), returned_lists, targets.thumbv6m_none);
    const cores = try @import("emit_llvm.zig").perCoreFreeLists(arena.allocator(), text);
    try std.testing.expect(std.mem.indexOf(u8, cores, "@__emutls_v.myl_core_free_lists = external global { i32, i32, ptr, ptr }") != null);
    try std.testing.expect(std.mem.indexOf(u8, cores, "call ptr @__emutls_get_address(ptr @__emutls_v.myl_core_free_lists)") != null);
    try std.testing.expect(std.mem.indexOf(u8, cores, "@myl_core_free_lists") == null);
    // Each access is one call: as many as the text had accesses of the plain free lists.
    const accesses = std.mem.count(u8, text, "ptr @myl_core_free_lists");
    try std.testing.expect(accesses != 0);
    try std.testing.expectEqual(accesses, std.mem.count(u8, cores, "call ptr @__emutls_get_address("));
}

test "the host target hashes and writes exactly the single-target compiler's seven fields; the bare target adds its own" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const host = try std.json.Stringify.valueAlloc(arena.allocator(), targets.host, .{});
    try std.testing.expectEqualStrings(
        \\{"triple":"","cpu_flags":["-march=native","-mllvm","-x86-experimental-pref-innermost-loop-alignment=6"],"vector_bits":256,"x86_avx2":true,"user_address_bits":47,"c_abi":"sysv_x86_64","traps":"dwarf_lines"}
    , host);
    const generic = try std.json.Stringify.valueAlloc(arena.allocator(), targets.generic_256, .{});
    try std.testing.expect(std.mem.indexOf(u8, generic, "\"x86_avx2\":false,\"user_address_bits\":47") != null);
    const bare = try std.json.Stringify.valueAlloc(arena.allocator(), targets.thumbv6m_none, .{});
    try std.testing.expect(std.mem.indexOf(u8, bare, "\"name\":\"thumbv6m-none\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bare, "\"cc_target\":\"thumb-freestanding-eabi\"") != null);
}

test "--target names the host and the bare Cortex-M0+ target, and nothing else" {
    try std.testing.expectEqual(&targets.x86_64_linux_avx2, targets.byName("x86_64-linux").?);
    try std.testing.expectEqual(&targets.thumbv6m_none, targets.byName("thumbv6m-none").?);
    try std.testing.expect(targets.byName("thumbv7em-none") == null);
    try std.testing.expectEqualStrings("x86_64-linux, thumbv6m-none", targets.names);
    try std.testing.expect(targets.host.runsHere());
    try std.testing.expect(!targets.thumbv6m_none.runsHere());
    try std.testing.expectEqualStrings("-Wl,-e,myl_bare_reset", targets.thumbv6m_none.system.runtime.bare.link[4]);
    try std.testing.expectEqualStrings("bare/core_bare_heap.c", targets.thumbv6m_none.system.runtime.bare.units[0].files[10]);
    try std.testing.expectEqualStrings("bare/core_bare.c", targets.thumbv6m_none.system.runtime.bare.units[0].files[11]);
    try std.testing.expectEqualStrings("bare/core_bare_cores.c", targets.thumbv6m_none.system.runtime.bare.units[0].files[12]);
    try std.testing.expectEqualStrings("-Os", targets.thumbv6m_none.system.runtime.bare.compile[0]); // its own unit flags, never the lean list's -enable-ipra
    // Every flavour's flags: emulated TLS (each core's copy of the runtime's state) is the two-core flavour's alone.
    try std.testing.expectEqual(@as(usize, 4), targets.thumbv6m_none.system.runtime.bare.c_flags.len);
    try std.testing.expectEqualStrings("i32", targets.thumbv6m_none.sizeType());
    try std.testing.expectEqualStrings("i64", targets.host.sizeType());
}

test "a --release bare build compiles the runtime's main unit with the terse-trap define, and only that unit" {
    const units = targets.thumbv6m_none.system.runtime.bare.units;
    try std.testing.expectEqual(@as(usize, 1), units[0].release.len);
    try std.testing.expectEqualStrings("-DMYL_BARE_TERSE", units[0].release[0]);
    try std.testing.expectEqual(@as(usize, 0), units[1].release.len);
    try std.testing.expectEqualStrings("-flto", targets.thumbv6m_none.system.runtime.bare.release[0]);
}

test "only the two-core flavour of the bare runtime's main unit defines MYL_BARE_CORES, uses emulated TLS and, in --release, stays machine code" {
    const units = targets.thumbv6m_none.system.runtime.bare.units;
    try std.testing.expectEqual(@as(usize, 2), units[0].cores.flags.len);
    try std.testing.expectEqualStrings("-DMYL_BARE_CORES", units[0].cores.flags[0]);
    try std.testing.expectEqualStrings("-femulated-tls", units[0].cores.flags[1]);
    // Link-time code generation would lower its thread-local variables to native TLS, which a bare image has no segment for.
    try std.testing.expectEqual(@as(usize, 1), units[0].cores.release.len);
    try std.testing.expectEqualStrings("-fno-lto", units[0].cores.release[0]);
    try std.testing.expectEqual(@as(usize, 0), units[1].cores.flags.len + units[1].cores.release.len);
    for (units[0].flags) |flag| try std.testing.expect(std.mem.indexOf(u8, flag, "CORES") == null);
    for (units[0].release) |flag| try std.testing.expect(std.mem.indexOf(u8, flag, "CORES") == null);
}

test "only the fault decoder's flavour of the bare runtime's main unit defines MYL_BARE_FREESTANDING, and it adds nothing to the second core's" {
    const units = targets.thumbv6m_none.system.runtime.bare.units;
    try std.testing.expectEqual(@as(usize, 1), units[0].freestanding.flags.len);
    try std.testing.expectEqualStrings("-DMYL_BARE_FREESTANDING", units[0].freestanding.flags[0]);
    try std.testing.expectEqual(@as(usize, 0), units[0].freestanding.release.len);
    try std.testing.expectEqual(@as(usize, 0), units[1].freestanding.flags.len + units[1].freestanding.release.len);
    for (units[0].flags) |flag| try std.testing.expect(std.mem.indexOf(u8, flag, "FREESTANDING") == null);
    for (units[0].release) |flag| try std.testing.expect(std.mem.indexOf(u8, flag, "FREESTANDING") == null);
    for (units[0].cores.flags) |flag| try std.testing.expect(std.mem.indexOf(u8, flag, "FREESTANDING") == null);
}

/// A list of text, a dictionary with integer keys and a text slice: element sizes, the dictionary probe's offsets into
/// the runtime's `core_dict_meta`, and the runtime's two-word span result.
const pointers =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut names: str[] = []
    \\    for a in args:
    \\        append(mut names, a + "!")
    \\    mut seen: dict[int, int] = {}
    \\    seen[len(names)] = 3
    \\    const head = names[0][0:2]
    \\    print(out, len(head) + seen[1])
    \\    return 0
    \\
;

test "the bare target's text lays a pointer out in 4 bytes and takes the runtime's structure results through memory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmTextFor(arena.allocator(), pointers, targets.thumbv6m_none);
    // A text element is 4 bytes in its layout and its growth, and the probe reads `index` and `elen` at 4 and 16.
    try std.testing.expect(std.mem.indexOf(u8, text, "[i32 4, i32 1, i32 -1, i32 0, i32 0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "[i32 8, i32 1, i32 -1") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "%index_at = getelementptr inbounds i8, ptr %meta, i64 4\n  %index = load ptr, ptr %index_at, align 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "%elen_at = getelementptr inbounds i8, ptr %meta, i64 16") != null);
    // AAPCS returns a 16-byte structure through memory the caller passes first.
    try std.testing.expect(std.mem.indexOf(u8, text, "declare void @myl_core_ir_str_slice_span(ptr sret({ i64, i64 }) align 8, ptr, i64, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "declare { i64, i64 }") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "(ptr sret({ i64, i64 }) align 8 %stack") != null);
}

test "the host target's text keeps 8-byte pointers and the runtime's structure results in registers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmTextFor(arena.allocator(), pointers, targets.host);
    try std.testing.expect(std.mem.indexOf(u8, text, "[i32 8, i32 1, i32 -1, i32 0, i32 0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "%index_at = getelementptr inbounds i8, ptr %meta, i64 8\n  %index = load ptr, ptr %index_at, align 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "%elen_at = getelementptr inbounds i8, ptr %meta, i64 32") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "declare { i64, i64 } @myl_core_ir_str_slice_span(ptr, i64, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "sret({ i64, i64 })") == null);
}

test "a pointer is 8 bytes on the host and 4 on the bare target; only AAPCS returns a C structure through memory" {
    const c_abi = @import("c_abi.zig");
    const meta = @import("emit_dict_span.zig").Meta;
    try std.testing.expectEqual(@as(u32, 8), targets.host.pointerBytes());
    try std.testing.expectEqual(@as(u32, 4), targets.thumbv6m_none.pointerBytes());
    try std.testing.expectEqual(meta{ .index = 8, .hashes = 16, .dead = 24, .elen = 32, .pointer = 8 }, meta.of(8));
    try std.testing.expectEqual(meta{ .index = 4, .hashes = 8, .dead = 12, .elen = 16, .pointer = 4 }, meta.of(4));
    try std.testing.expect(c_abi.returnsInMemory(.aapcs, "{ ptr, i64 }") and !c_abi.returnsInMemory(.sysv_x86_64, "{ ptr, i64 }"));
    try std.testing.expect(!c_abi.returnsInMemory(.aapcs, "ptr") and !c_abi.returnsInMemory(.aapcs, "i64"));
}

test "a task group or handle list element is stored as a pointer at the target's width, as its layout says" {
    const emit_llvm = @import("emit_llvm.zig");
    const ir = @import("ir.zig");
    const bare: ir.Module = .{ .lowering = .{ .pointer_bytes = 4 } };
    const host: ir.Module = .{};
    for ([_]ir.Type{ .task_group, .task_handle }) |ty| {
        try std.testing.expectEqualStrings("ptr", emit_llvm.storageType(ty));
        try std.testing.expectEqual(bare.size(ty), emit_llvm.elementSize(&bare, ty));
        try std.testing.expectEqual(@as(u32, 8), emit_llvm.elementSize(&host, ty));
    }
}

test "a sort key's text and bytes fields keep the host's 8-wide codes when a pointer is 4 bytes" {
    const build_fn = @import("build_fn.zig");
    const ir = @import("ir.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .lowering = .{ .pointer_bytes = 4 } };
    const key = try module.intern(a, .{ .record = &.{ .str, .i32, .bytes } });
    const shape = build_fn.keyShape(module, key).?;
    // Three fields: text 8 wide (3, not 7, which means bytes), a 4-wide signed integer (4) and bytes (7).
    try std.testing.expectEqual(@as(u64, 3 | (3 << 4) | (4 << 8) | (7 << 12)), shape.shape);
    try std.testing.expectEqual(@as(u64, module.fieldOffset(key, 1)), (shape.offsets >> 8) & 255);
    try std.testing.expectEqual(@as(u64, 4), module.fieldOffset(key, 1));
    const descriptor = (try build_fn.recordKeyDescriptor(a, module, key)).?;
    try std.testing.expectEqual(@as(usize, 48), descriptor.len);
    try std.testing.expectEqualSlices(u8, &.{ 3, 8, 0, 4, 4, 8 }, &.{ descriptor[8], descriptor[9], descriptor[24], descriptor[25], descriptor[40], descriptor[41] });
}

/// Fail unless `text` holds every one of `pieces`.
fn expectAll(text: []const u8, pieces: []const []const u8) !void {
    for (pieces) |piece| try std.testing.expect(std.mem.indexOf(u8, text, piece) != null);
}

/// Every register access width, read and written, through the `Registers` `main` receives.
const register_access =
    \\import registers
    \\
    \\func main(args: str[], reg: Registers) -> int:
    \\    registers.write8(reg, 0x40000000, 1)
    \\    registers.write16(reg, 0x40000002, 2)
    \\    registers.write32(reg, 0x40000004, 3)
    \\    const total = int(registers.read8(reg, 0x40000010)) + int(registers.read16(reg, 0x40000012))
    \\    return total + int(registers.read32(reg, 0x40000014)) + len(args)
    \\
;

test "on the bare target each register read and write is one volatile load or store of its width at the address, no call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmTextFor(arena.allocator(), register_access, targets.thumbv6m_none);
    // Each operation's body is the access at its address parameter; LLVM inlines the six small bodies into `main`.
    try expectAll(text, &.{ "store volatile i8 %p2, ptr %v3.at, align 1", "store volatile i16 %p2, ptr %v3.at, align 2", "store volatile i32 %p2, ptr %v3.at, align 4" });
    try expectAll(text, &.{ "%v2 = load volatile i8, ptr %v2.at, align 1", "%v2 = load volatile i16, ptr %v2.at, align 2", "%v2 = load volatile i32, ptr %v2.at, align 4" });
    try expectAll(text, &.{ "%v3.at = inttoptr i32 %p1 to ptr", "%v2.at = inttoptr i32 %p1 to ptr" });
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_registers_") == null);
}

test "on the host a register read and write stays a call of the simulated bank, with no volatile access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmTextFor(arena.allocator(), register_access, targets.host);
    try expectAll(text, &.{ "@myl_core_registers_write8(", "@myl_core_registers_write16(", "@myl_core_registers_write32(", "@myl_core_registers_read8(", "@myl_core_registers_read16(", "@myl_core_registers_read32(" });
    try std.testing.expect(std.mem.indexOf(u8, text, "volatile") == null and std.mem.indexOf(u8, text, "inttoptr") == null);
}

test "a device build names the simulated-only register function a unit calls, and none for the reads and writes" {
    const build_registers = @import("build_registers.zig");
    try std.testing.expectEqualStrings("registers.simulated", build_registers.simulatedCall("  %r = call i64 @myl_core_registers_simulated()").?);
    try std.testing.expectEqualStrings("registers.script32", build_registers.simulatedCall("declare void @myl_core_registers_script32(i64, i32, ptr)").?);
    try std.testing.expect(build_registers.simulatedCall("  %v = call i32 @myl_core_registers_read32(i64 0, i32 4)") == null);
    // A private `cpu` reader is named by the public function over it (MCU-NOC1); an instruction is no simulated call.
    try std.testing.expectEqualStrings("cpu.event_operation", build_registers.simulatedCall("  %k = call i64 @myl_core_registers_cpu_event_kind(i64 %r, i64 0)").?);
    try std.testing.expect(build_registers.simulatedCall("  call void @myl_core_registers_cpu_send_event(i64 %r)") == null);
}

test "--cpu: the flags are the host's with the model's -march, and a native build keeps the flags it always had" {
    const rest = [_][]const u8{ "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6" };
    try std.testing.expectEqualSlices([]const u8, &([_][]const u8{"-march=native"} ++ rest), targets.host.cpu_flags);
    const v3 = targets.host.forCpu(.x86_64_v3).?;
    try std.testing.expectEqualSlices([]const u8, &([_][]const u8{"-march=x86_64_v3"} ++ rest), v3.cpu_flags);
    try std.testing.expectEqual(&targets.x86_64_linux_avx2, targets.x86_64_linux_avx2.forCpu(.native).?);
    try std.testing.expect(v3.isHost() and v3.runsHere());
    try std.testing.expectEqual(targets.Cpu.x86_64_v3, v3.cpuModel());
    try std.testing.expectEqual(targets.Cpu.native, targets.host.cpuModel());
    try std.testing.expectEqual(targets.Cpu.native, targets.thumbv6m_none.cpuModel());
    // A bare target has no x86 CPU to choose; naming `native` for it changes nothing.
    try std.testing.expect(targets.thumbv6m_none.forCpu(.x86_64_v3) == null);
    try std.testing.expectEqual(&targets.thumbv6m_none, targets.thumbv6m_none.forCpu(.native).?);
}

test "--cpu: the two models are the two words `--cpu` spells, and any other word is refused naming both" {
    try std.testing.expectEqual(targets.Cpu.native, targets.Cpu.parse("native").?);
    try std.testing.expectEqual(targets.Cpu.x86_64_v3, targets.Cpu.parse("x86-64-v3").?);
    try std.testing.expect(targets.Cpu.parse("x86_64_v3") == null);
    try std.testing.expect(targets.Cpu.parse("") == null);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("unknown --cpu value `bogus`; the values are `native` and `x86-64-v3`", try targets.Cpu.unknown(arena.allocator(), "bogus"));
}

test "--cpu: a x86-64-v3 unit never gets a native unit's key, and the native key is the one the flags it always had make" {
    const unit_cache = @import("unit_cache.zig");
    const settings: unit_cache.Settings = .{ .tool = @splat(1), .cpu = @splat(2), .runtime = @splat(3) };
    const native = unit_cache.key(settings, "unit text");
    var v3_settings = settings;
    v3_settings.target = targets.host.forCpu(.x86_64_v3).?;
    const v3 = unit_cache.key(v3_settings, "unit text");
    try std.testing.expect(!std.mem.eql(u8, &native, &v3));
    // Pinned against the flags, not a digest: a host target spelled out with today's flags keys as the default does, and one
    // spelled out with only the -march changed keys as the model does.
    var today = targets.host;
    today.cpu_flags = &.{ "-march=native", "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6" };
    var today_settings = settings;
    today_settings.target = &today;
    try std.testing.expectEqual(native, unit_cache.key(today_settings, "unit text"));
    var floor = targets.host;
    floor.cpu_flags = &.{ "-march=x86_64_v3", "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6" };
    var floor_settings = settings;
    floor_settings.target = &floor;
    try std.testing.expectEqual(v3, unit_cache.key(floor_settings, "unit text"));
}

test "--cpu: the target a pass hashes as JSON differs by the model's flags, and the native one is the host's seven fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const native = try std.json.Stringify.valueAlloc(arena.allocator(), targets.host, .{});
    const v3 = try std.json.Stringify.valueAlloc(arena.allocator(), targets.host.forCpu(.x86_64_v3).?.*, .{});
    try std.testing.expect(std.mem.indexOf(u8, native, "\"-march=native\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, v3, "\"-march=x86_64_v3\"") != null and std.mem.indexOf(u8, v3, "native") == null);
}
