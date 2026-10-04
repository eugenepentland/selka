//! Instruction lowering and module assembly for the LLVM translator
//! (LLVM-ZIG-1): each QBE instruction becomes LLVM lines over the emitter's
//! slots, each block ends in an explicit terminator (QBE's fall-through
//! becomes a branch), and the module around the function declares every
//! global, helper and intrinsic the body named.
const std = @import("std");
const il = @import("qbe_build_llvm_il.zig");
const classes = @import("qbe_build_llvm_classes.zig");
const runtime = @import("qbe_build_llvm_runtime.zig");
const emit = @import("qbe_build_llvm_emit.zig");

const Error = il.Error;
const Instruction = il.Instruction;
const Operand = il.Operand;
const Emitter = emit.Emitter;
const Lines = emit.Lines;
/// An ordinary wrapped arithmetic result.
const arithmetic_line = "  %{s} = {s} {s} {s}, {s}";
/// `ret void`: the end of a function with no register result.
const ret_void = "  ret void";
/// `!N = !{...}`: one metadata list.
const list_line = "!{d} = !{{{s}}}";
/// One scope's single-member list, `!(scope + 1) = !{!scope}`.
const member_line = "!{d} = !{{!{d}}}";

/// Render one translated unit as a self-contained LLVM module.
pub fn module(e: *Emitter) Error![]const u8 {
    var out: Lines = .empty;
    try out.appendSlice(e.arena, &.{ "target triple = \"x86_64-unknown-linux-gnu\"", "" });
    try function(e, &out);
    try globals(e, &out);
    try declarations(e, &out);
    const attributes = e.module.attributes.keys();
    if (attributes.len != 0) {
        const sorted = try e.arena.dupe([]const u8, attributes);
        std.mem.sort([]const u8, sorted, {}, lessString);
        try out.append(e.arena, "");
        try e.line(&out, "attributes #0 = {{ {s} }}", .{try std.mem.join(e.arena, " ", sorted)});
    }
    if (e.module.metadata.alias) {
        try out.append(e.arena, "\n!0 = distinct !{!0, !\"mylang memory classes\"}\n!1 = distinct !{!1, !0, !\"frame\"}\n!2 = distinct !{!2, !0, !\"foreign\"}\n!3 = !{!1}\n!4 = !{!2}");
        try elementMetadata(e, &out);
    }
    try e.module.frame_map.metadata(e.arena, &out);
    const text = try std.mem.join(e.arena, "\n", out.items);
    return std.mem.concat(e.arena, u8, &.{ text, "\n" });
}

fn lessString(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// Every global the body referenced: a callable one is declared as a
/// function (its address is taken), anything else as external storage.
fn globals(e: *Emitter, out: *Lines) Error!void {
    const names = e.module.globals.keys();
    if (names.len == 0) return;
    try out.append(e.arena, "");
    const sorted = try e.arena.dupe([]const u8, names);
    std.mem.sort([]const u8, sorted, {}, lessString);
    for (sorted) |name| {
        if (std.mem.eql(u8, name, e.unit.function.name)) continue;
        if (e.module.declarations.contains(name)) continue;
        if (try e.knownSignature(name)) |known| {
            try e.declare(name, known);
            continue;
        }
        try e.line(out, "@{s} = external global i8, align 8", .{name});
    }
}

fn declarations(e: *Emitter, out: *Lines) Error!void {
    const names = try e.arena.dupe([]const u8, e.module.declarations.keys());
    std.mem.sort([]const u8, names, {}, lessString);
    var any = false;
    for (names) |name| {
        const declaration = e.module.declarations.get(name).?;
        if (declaration.origin == .undefined) continue;
        if (!any) try out.append(e.arena, "");
        any = true;
        var rendered: Lines = .empty;
        for (declaration.parameters) |parameter| try rendered.append(e.arena, switch (parameter) {
            .scalar => |llvm| llvm,
            .aggregate => |abi| if (abi.indirect) try e.print("ptr byval({s}) align {d}", .{ abi.storage, abi.alignment }) else abi.value.?,
        });
        var result: []const u8 = undefined;
        switch (declaration.result) {
            .scalar => |llvm| result = llvm,
            .aggregate => |abi| if (abi.indirect) {
                try rendered.insert(e.arena, 0, try e.print("ptr sret({s}) align {d}", .{ abi.storage, abi.alignment }));
                result = "void";
            } else {
                result = abi.value.?;
            },
        }
        const attributes = try declarationAttributes(e, name);
        const separator: []const u8 = if (attributes.len != 0) " " else "";
        try e.line(out, "declare {s}{s} @{s}({s}){s}{s}", .{ runtime.callingConvention(name), result, name, try std.mem.join(e.arena, ", ", rendered.items), separator, attributes });
    }
}

/// The attributes one runtime declaration carries: a fail helper is `cold`,
/// and `noreturn` too when every call to it in this unit is followed by `hlt`.
fn declarationAttributes(e: *Emitter, name: []const u8) Error![]const u8 {
    const attributes = runtime.attributes(name);
    if (!std.mem.startsWith(u8, name, il.fail_prefix)) return attributes;
    const extra: []const u8 = if (halting(e, name)) "noreturn cold" else "cold";
    if (attributes.len == 0) return extra;
    return e.print("{s} {s}", .{ attributes, extra });
}

fn halting(e: *const Emitter, name: []const u8) bool {
    var halts = false;
    for (e.unit.function.blocks.items) |block| for (block.instructions.items, 0..) |instruction, index| {
        const target = instruction.directTarget() orelse continue;
        if (!std.mem.eql(u8, target, name)) continue;
        const next = index + 1 < block.instructions.items.len and block.instructions.items[index + 1].opcode == .hlt;
        if (!next) return false;
        halts = true;
    };
    return halts;
}

fn elementMetadata(e: *Emitter, out: *Lines) Error!void {
    const kinds = e.module.element_kinds.items;
    var scopes: Lines = .empty;
    for (0..kinds.len) |index| try scopes.append(e.arena, try e.print("!{d}", .{emit.element_base + 3 * index}));
    const base = emit.object_scope;
    try e.line(out, "!{d} = distinct !{{!{d}, !0, !\"object\"}}", .{ base, base });
    try e.line(out, member_line, .{ base + 1, base });
    try e.line(out, list_line, .{ base + 2, try joinWith(e, "!1", scopes.items) });
    // LLVM-RC-PREFIX-1: a prefix word is apart from the frame, every object
    // and every element storage block.
    if (e.module.metadata.prefix) try prefixMetadata(e, out, scopes.items);
    if (e.module.metadata.rc_state) try stateMetadata(e, out, scopes.items);
    for (kinds, 0..) |kind, index| {
        const scope = emit.element_base + 3 * index;
        var others: Lines = .empty;
        try others.append(e.arena, try e.print("!{d}", .{base}));
        for (scopes.items, 0..) |other, position| if (position != index) try others.append(e.arena, other);
        try e.line(out, "!{d} = distinct !{{!{d}, !0, !\"element {s}\"}}", .{ scope, scope, kind });
        try e.line(out, member_line, .{ scope + 1, scope });
        try e.line(out, list_line, .{ scope + 2, try joinWith(e, "!1", others.items) });
    }
    for (e.module.scope_lists.items) |list| {
        var members: Lines = .empty;
        for (list.members) |member| try members.append(e.arena, try e.print("!{d}", .{member}));
        try e.line(out, list_line, .{ list.number, try std.mem.join(e.arena, ", ", members.items) });
    }
}

/// The RC prefix scope, its list, and the list of every scope it never aliases.
fn prefixMetadata(e: *Emitter, out: *Lines, elements: []const []const u8) Error!void {
    const prefix = emit.prefix_scope;
    var apart: Lines = .empty;
    try apart.append(e.arena, try e.print("!{d}", .{emit.object_scope}));
    try apart.appendSlice(e.arena, elements);
    try e.line(out, "!{d} = distinct !{{!{d}, !0, !\"rc prefix\"}}", .{ prefix, prefix });
    try e.line(out, member_line, .{ prefix + 1, prefix });
    try e.line(out, list_line, .{ prefix + 2, try joinWith(e, "!1", apart.items) });
}

/// RC-SCOPE-IL-1: runtime heap/state/journal words never occupy guest storage.
fn stateMetadata(e: *Emitter, out: *Lines, elements: []const []const u8) Error!void {
    const scope = emit.rc_state_scope;
    var apart: Lines = .empty;
    try apart.append(e.arena, try e.print("!{d}", .{emit.object_scope}));
    if (e.module.metadata.prefix) try apart.append(e.arena, try e.print("!{d}", .{emit.prefix_scope}));
    try apart.appendSlice(e.arena, elements);
    try e.line(out, "!{d} = distinct !{{!{d}, !0, !\"rc state\"}}", .{ scope, scope });
    try e.line(out, member_line, .{ scope + 1, scope });
    try e.line(out, list_line, .{ scope + 2, try joinWith(e, "!1", apart.items) });
}

fn joinWith(e: *Emitter, first: []const u8, rest: []const []const u8) Error![]const u8 {
    var all: Lines = .empty;
    try all.append(e.arena, first);
    try all.appendSlice(e.arena, rest);
    return std.mem.join(e.arena, ", ", all.items);
}

// ---------------------------------------------------------------------------
// The function
// ---------------------------------------------------------------------------

/// The LLVM parameter list: scalars keep their machine type, aggregates follow
/// AMD64 SysV (register values, or `byval`), a large result an `sret` pointer.
fn parameterShapes(e: *Emitter) Error![]const []const u8 {
    const own = &e.unit.function;
    var out: Lines = .empty;
    if (try e.abiOf(own.result, false)) |abi| if (abi.indirect) try e.line(&out, "ptr sret({s}) align {d} %p_sret", .{ abi.storage, abi.alignment });
    const classified = try e.parameterAbis(try letters(e), own.result);
    for (own.parameters, classified) |parameter, shape| {
        switch (shape) {
            .scalar => try e.line(&out, "{s} %p_{s}", .{ try e.letterType(parameter.letter), parameter.name }),
            .aggregate => |abi| if (abi.indirect) {
                try e.line(&out, "ptr byval({s}) align {d} %p_{s}", .{ abi.storage, abi.alignment, parameter.name });
            } else {
                try e.line(&out, "{s} %p_{s}", .{ abi.value.?, parameter.name });
            },
        }
    }
    return out.items;
}

fn letters(e: *Emitter) Error![]const []const u8 {
    const parameters = e.unit.function.parameters;
    const out = try e.arena.alloc([]const u8, parameters.len);
    for (parameters, out) |parameter, *letter| letter.* = parameter.letter;
    return out;
}

/// The LLVM return type: an aggregate result is returned by value.
fn returnType(e: *Emitter) Error![]const u8 {
    const result = e.unit.function.result orelse return "void";
    const abi = (try e.abiOf(result, false)) orelse return e.letterType(result);
    return if (abi.indirect) "void" else abi.value.?;
}

/// Render the function: its definition line, every slot, the parameter
/// prologue, then the blocks in order.
fn function(e: *Emitter, out: *Lines) Error!void {
    const own = &e.unit.function;
    const rendered = try parameterShapes(e);
    const result = try returnType(e);
    if (e.options.target_cpu.len != 0) try e.module.attributes.put(e.arena, try e.print("\"target-cpu\"=\"{s}\"", .{e.options.target_cpu}), {});
    if (e.options.target_features.len != 0) try e.module.attributes.put(e.arena, try e.print("\"target-features\"=\"{s}\"", .{e.options.target_features}), {});
    for (e.module.frame_map.attributes()) |attribute| try e.module.attributes.put(e.arena, attribute, {});
    const reference: []const u8 = if (e.module.attributes.count() != 0 or !own.exported) " #0" else "";
    if (!own.exported) try e.module.attributes.put(e.arena, "noinline", {});
    const subprogram = if (e.module.frame_map.active) try e.print(" !dbg !{d}", .{classes.frame_map_metadata_base + 1}) else "";
    const first = own.blocks.items[0].label;
    try e.line(out, "define dllexport {s} @{s}({s}){s}{s} {{", .{ result, own.name, try std.mem.join(e.arena, ", ", rendered), reference, subprogram });
    try e.line(out, "{s}:", .{try label(e, first)});
    for (own.parameters) |parameter| _ = try e.slot(parameter.name);
    for (own.blocks.items) |block| for (block.instructions.items) |instruction| {
        if (instruction.dest) |dest| _ = try e.slot(dest);
    };
    try out.appendSlice(e.arena, e.names.slot_lines.items);
    try prologue(e, out);
    const blocks = own.blocks.items;
    for (blocks, 0..) |block, index| {
        if (!std.mem.eql(u8, block.label, first)) try e.line(out, "{s}:", .{try label(e, block.label)});
        const following = if (index + 1 < blocks.len) blocks[index + 1].label else null;
        try emitBlock(e, out, block, following);
    }
    try out.append(e.arena, "}");
}

/// Store each parameter into its slot; an aggregate arrives as its address.
fn prologue(e: *Emitter, out: *Lines) Error!void {
    const own = &e.unit.function;
    const classified = try e.parameterAbis(try letters(e), own.result);
    for (own.parameters, classified) |parameter, shape| {
        const held = try e.slot(parameter.name);
        var value = try e.print("%p_{s}", .{parameter.name});
        if (shape == .aggregate) {
            const abi = shape.aggregate;
            var local = try e.print("p_{s}", .{parameter.name});
            if (!abi.indirect) {
                local = try e.fresh("param");
                try e.line(out, emit.alloca_line, .{ local, abi.storage, abi.alignment });
                try e.line(out, "  store {s} %p_{s}, ptr %{s}, align {d}", .{ abi.value.?, parameter.name, local, abi.alignment });
            }
            const address = try e.fresh("addr");
            try e.line(out, emit.address_line, .{ address, local });
            value = try e.print("%{s}", .{address});
        }
        try e.line(out, "  store {s} {s}, ptr %{s}, align {d}", .{ held.llvm, value, held.pointer, @min(held.size, 8) });
    }
}

/// The LLVM label of a QBE block label.
fn label(e: *Emitter, block_label: []const u8) Error![]const u8 {
    const name = try e.arena.dupe(u8, std.mem.trimStart(u8, block_label, "@"));
    std.mem.replaceScalar(u8, name, '.', '_');
    return e.print("bb_{s}", .{name});
}

/// Render one block, making QBE's implicit fall-through an explicit branch
/// and storing the phi inputs it hands its successors before its branch.
fn emitBlock(e: *Emitter, out: *Lines, block: *const il.Block, following: ?[]const u8) Error!void {
    const terminator = block.terminator();
    const explicit = if (terminator) |last| isTerminator(last.opcode) else false;
    const body = if (explicit) block.instructions.items[0 .. block.instructions.items.len - 1] else block.instructions.items;
    e.names.block = .{};
    for (body, 0..) |instruction, position| {
        e.names.block.position = position;
        try emitInstruction(e, out, instruction);
        if (instruction.dest) |dest| {
            try e.names.block.positions.put(e.arena, dest, position);
            try e.names.block.definitions.put(e.arena, dest, instruction);
        }
    }
    e.names.block.position = body.len;
    if (e.facts.rewrites.phi_stores.get(block.label)) |pending| for (pending.items) |store| {
        const name = store.instruction.dest.?;
        const value = try e.render(out, store.value, e.llvmOf(name));
        try e.storeSlot(out, name, value);
    };
    if (explicit) {
        try emitInstruction(e, out, terminator.?);
    } else if (following) |next| {
        try e.line(out, "  br label %{s}", .{try label(e, next)});
    } else try out.append(e.arena, "  unreachable");
}

fn isTerminator(opcode: il.Opcode) bool {
    return opcode == .ret or opcode == .jmp or opcode == .jnz or opcode == .hlt;
}

/// Render one instruction as zero or more LLVM lines.
fn emitInstruction(e: *Emitter, out: *Lines, instruction: *const Instruction) Error!void {
    var lines: Lines = .empty;
    const opcode = instruction.opcode;
    switch (opcode) {
        .alloc4 => try onAlloc(e, &lines, instruction, 4),
        .alloc8 => try onAlloc(e, &lines, instruction, 8),
        .alloc16 => try onAlloc(e, &lines, instruction, 16),
        .blit => try onBlit(e, &lines, instruction),
        .copy => try define(e, &lines, instruction, try e.render(&lines, instruction.args[0], e.llvmOf(instruction.dest.?))),
        .neg => try onNeg(e, &lines, instruction),
        .not => try onNot(e, &lines, instruction),
        .ret => try onRet(e, &lines, instruction),
        .jmp => try e.line(&lines, "  br label %{s}", .{try label(e, instruction.extra.label)}),
        .jnz => try onJnz(e, &lines, instruction),
        .call => {
            try onCall(e, &lines, instruction);
            try e.module.frame_map.positionCalls(e.arena, lines.items);
        },
        .phi => {},
        .hlt => try lines.append(e.arena, "  unreachable"),
        .dbgloc => e.module.frame_map.location = instruction.extra.position,
        else => if (opcode.isComparison()) {
            try onCompare(e, &lines, instruction);
        } else if (opcode.isConversion()) {
            try onConversion(e, &lines, instruction);
        } else if (opcode.isLoad()) {
            try onLoad(e, &lines, instruction);
        } else if (opcode.isStore()) {
            try onStore(e, &lines, instruction);
        } else try onArithmetic(e, &lines, instruction),
    }
    try out.appendSlice(e.arena, lines.items);
}

/// Store one instruction's result into its destination slot.
fn define(e: *Emitter, lines: *Lines, instruction: *const Instruction, value: []const u8) Error!void {
    try e.storeSlot(lines, instruction.dest.?, value);
}

// -- memory --------------------------------------------------------------

/// One stack allocation, kept where the source put it.
fn onAlloc(e: *Emitter, lines: *Lines, instruction: *const Instruction, alignment: u64) Error!void {
    const size = try e.render(lines, instruction.args[0], "i64");
    const raw = try e.fresh("mem");
    const pointer = try e.fresh("ptr");
    try e.line(lines, "  %{s} = alloca i8, i64 {s}, align {d}", .{ raw, size, alignment });
    if (e.facts.rewrites.scalar_addresses.contains(instruction.dest.?)) {
        try e.names.scalar_pointers.put(e.arena, instruction.dest.?, try e.print("%{s}", .{raw}));
    }
    if (e.facts.rewrites.scalar_slots.contains(instruction.dest.?)) return;
    try e.line(lines, emit.address_line, .{ pointer, raw });
    try define(e, lines, instruction, try e.print("%{s}", .{pointer}));
}

/// `blit src, dst, size`: a byte copy of possibly overlapping ranges.
fn onBlit(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    try e.declareIntrinsic("llvm.memmove.p0.p0.i64", &.{ "ptr", "ptr", "i64", "i1" }, "void");
    const source = try e.render(lines, instruction.args[0], "i64");
    const destination = try e.render(lines, instruction.args[1], "i64");
    const size = try e.render(lines, instruction.args[2], "i64");
    const source_pointer = try e.address(lines, source);
    const destination_pointer = try e.address(lines, destination);
    const alias = try e.aliasOfBoth(instruction.args[0], instruction.args[1]);
    try e.line(lines, "  call void @llvm.memmove.p0.p0.i64(ptr {s}, ptr {s}, i64 {s}, i1 false){s}", .{ destination_pointer, source_pointer, size, alias });
}

/// One load, signed or unsigned, widened to the destination's width.
fn onLoad(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    const shape = il.loadShape(instruction.opcode);
    const llvm = e.llvmOf(instruction.dest.?);
    const pointer = try accessPointer(e, lines, instruction.args[0]);
    const loaded = try e.fresh("ld");
    const loaded_type: []const u8 = switch (instruction.opcode) {
        .loadd => "double",
        .loads => "float",
        else => il.intName(shape.bits),
    };
    try e.line(lines, "  %{s} = load {s}, ptr {s}, align {d}{s}", .{ loaded, loaded_type, pointer, @max(1, shape.bits / 8), try e.aliasOf(instruction.args[0]) });
    var value = try e.print("%{s}", .{loaded});
    const target_bits = emit.bitWidth(llvm);
    if (!emit.isFloat(loaded_type) and target_bits != null and shape.bits < target_bits.?) {
        const widened = try e.fresh("ext");
        const operation: []const u8 = if (shape.signed) "sext" else "zext";
        try e.line(lines, "  %{s} = {s} {s} %{s} to {s}", .{ widened, operation, loaded_type, loaded, llvm });
        value = try e.print("%{s}", .{widened});
    }
    try define(e, lines, instruction, value);
}

/// One store of the low bits of a value; a same-width reinterpretation is a bitcast.
fn onStore(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    const bits = il.storeBits(instruction.opcode);
    const stored_type: []const u8 = switch (instruction.opcode) {
        .stored => "double",
        .stores => "float",
        else => il.intName(bits),
    };
    const source = instruction.args[0];
    const source_llvm = if (source.tempName()) |name| e.llvmOf(name) else stored_type;
    var value = try e.render(lines, source, source_llvm);
    if (!std.mem.eql(u8, source_llvm, stored_type)) value = try e.widen(lines, value, source_llvm, stored_type);
    const pointer = try accessPointer(e, lines, instruction.args[1]);
    try e.line(lines, "  store {s} {s}, ptr {s}, align {d}{s}", .{ stored_type, value, pointer, @max(1, bits / 8), try e.aliasOf(instruction.args[1]) });
}

/// The pointer a load or store uses: an element sum from a marked storage
/// word in this block becomes a `getelementptr i8` from that word
/// (LLVM-ELEMENT-GEP-1), anything else an `inttoptr` of the integer.
fn accessPointer(e: *Emitter, lines: *Lines, argument: Operand) Error![]const u8 {
    if (argument.tempName()) |name| if (e.names.scalar_pointers.get(name)) |pointer| return pointer;
    if (try prefixPointer(e, lines, argument)) |pointer| return pointer;
    const chain = (try elementChain(e, argument)) orelse return e.address(lines, try e.render(lines, argument, "i64"));
    var pointer = try e.address(lines, try e.loadSlot(lines, chain.base));
    for (chain.offsets) |offset| {
        const value = try e.render(lines, offset, "i64");
        const gep = try e.fresh("egep");
        try e.line(lines, "  %{s} = getelementptr i8, ptr {s}, i64 {s}", .{ gep, pointer, value });
        pointer = try e.print("%{s}", .{gep});
    }
    return pointer;
}

/// LLVM-RC-PREFIX-1: a marked RC prefix address as a `getelementptr i8`
/// from its payload, so LLVM tells the owner, hold and mark words of one
/// payload apart and forwards a count it just stored.
fn prefixPointer(e: *Emitter, lines: *Lines, argument: Operand) Error!?[]const u8 {
    if (!e.options.pointers.element_gep) return null;
    const name = argument.tempName() orelse return null;
    const base = e.facts.rewrites.prefix_bases.get(name) orelse return null;
    const payload = try e.address(lines, try e.render(lines, base.payload, "i64"));
    const gep = try e.fresh("rgep");
    try e.line(lines, "  %{s} = getelementptr i8, ptr {s}, i64 {d}", .{ gep, payload, base.offset });
    const pointer = try e.print("%{s}", .{gep});
    return pointer;
}

const Chain = struct { base: []const u8, offsets: []const Operand };

/// `(base, offsets)` when an address is a singly-defined `add` emitted
/// earlier in this block, followed through further such `add`s down to a
/// marked managed address, with at least one variable offset.
fn elementChain(e: *Emitter, argument: Operand) Error!?Chain {
    if (!e.options.pointers.element_gep) return null;
    var name = argument.tempName() orelse return null;
    var offsets: std.ArrayList(Operand) = .empty;
    var use_position = e.names.block.position;
    const objects = &e.unit.function.hints.objects;
    for (0..8) |_| {
        if (objects.contains(name) and e.facts.single.contains(name)) {
            var variable = false;
            for (offsets.items) |offset| variable = variable or offset.refName() != null;
            if (!variable) return null;
            std.mem.reverse(Operand, offsets.items);
            return .{ .base = name, .offsets = offsets.items };
        }
        const position = e.names.block.positions.get(name) orelse return null;
        if (!e.facts.single.contains(name) or position >= use_position) return null;
        const definition = e.names.block.definitions.get(name).?;
        if (!elementSum(e, definition, position)) return null;
        const step = follow(e, definition) orelse return null;
        try offsets.append(e.arena, step.offset);
        name = step.name;
        use_position = position;
    }
    return null;
}

/// Whether a definition is an `=l add` of two operands whose temporaries are
/// singly defined and not redefined in this block after `position`.
fn elementSum(e: *const Emitter, definition: *const Instruction, position: usize) bool {
    const typed = definition.qbe_type != null and std.mem.eql(u8, definition.qbe_type.?, "l");
    if (definition.opcode != .add or !typed or definition.args.len != 2) return false;
    for (definition.args) |operand| {
        switch (operand) {
            .global => return false,
            .temp => |ref| {
                if (!e.facts.single.contains(ref.name)) return false;
                const later = e.names.block.positions.get(ref.name) orelse continue;
                if (later >= position) return false;
            },
            else => {},
        }
    }
    return true;
}

/// Which operand of an element sum the chain follows: a marked address
/// first, else an operand defined by another `add` in this block.
fn follow(e: *const Emitter, definition: *const Instruction) ?struct { name: []const u8, offset: Operand } {
    const left = definition.args[0];
    const right = definition.args[1];
    const pairs = [2][2]Operand{ .{ left, right }, .{ right, left } };
    for (pairs) |pair| if (pair[0].refName()) |name| {
        if (e.unit.function.hints.objects.contains(name)) return .{ .name = name, .offset = pair[1] };
    };
    for (pairs) |pair| if (pair[0].refName()) |name| {
        const defined = e.names.block.definitions.get(name) orelse continue;
        if (defined.opcode == .add) return .{ .name = name, .offset = pair[1] };
    };
    return null;
}

// -- values --------------------------------------------------------------

/// Integer or floating arithmetic, whichever the destination carries; an
/// `add` of an object address is a `getelementptr`, and a checked operation
/// computes its overflow intrinsics (LLVM-OVERFLOW-INTRINSIC-1).
fn onArithmetic(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    if (instruction.opcode == .umulh) return multiplyHigh(e, lines, instruction);
    const name = instruction.dest.?;
    const kind = e.typeOf(name);
    const llvm = kind.llvm();
    var operation: []const u8 = il.integerInstruction(instruction.opcode);
    if (kind.kind == .float) operation = floatInstruction(instruction.opcode) orelse
        return e.fail(try e.print("{s}:{d}: `{s}` is not defined on floats", .{ e.unit.function.name, instruction.line, @tagName(instruction.opcode) }));
    const left = try e.render(lines, instruction.args[0], llvm);
    const right = try e.render(lines, instruction.args[1], llvm);
    const result = try e.fresh("op");
    if (pointerIndex(e, instruction, llvm)) |index| {
        const base = if (index == 0) left else right;
        const offset = if (index == 0) right else left;
        const base_pointer = try e.address(lines, base);
        const gep = try e.fresh("gep");
        try e.line(lines, "  %{s} = getelementptr i8, ptr {s}, i64 {s}", .{ gep, base_pointer, offset });
        try e.line(lines, emit.address_line, .{ result, gep });
    } else if (e.facts.overflow.producers.get(instruction)) |stems| {
        if (kind.kind == .int and std.mem.eql(u8, llvm, "i64")) {
            const ordinary = e.facts.overflow.ordinary_results.contains(instruction);
            if (ordinary) try e.line(lines, arithmetic_line, .{ result, operation, llvm, left, right });
            try checkedArithmetic(e, lines, instruction, stems.items, .{ left, right, result }, ordinary);
        } else try e.line(lines, arithmetic_line, .{ result, operation, llvm, left, right });
    } else try e.line(lines, arithmetic_line, .{ result, operation, llvm, left, right });
    try define(e, lines, instruction, try e.print("%{s}", .{result}));
}

/// Exact unsigned high-half multiplication, widened before taking the high bits.
fn multiplyHigh(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    const kind = e.typeOf(instruction.dest.?);
    if (kind.kind != .int) return e.fail("`umulh` requires integer operands");
    const llvm = kind.llvm();
    const wide: []const u8 = if (std.mem.eql(u8, llvm, "i64")) "i128" else "i64";
    const shift: u8 = if (std.mem.eql(u8, llvm, "i64")) 64 else 32;
    const left = try e.fresh("wide");
    const right = try e.fresh("wide");
    const product = try e.fresh("product");
    const high = try e.fresh("high");
    const result = try e.fresh("op");
    try e.line(lines, "  %{s} = zext {s} {s} to {s}", .{ left, llvm, try e.render(lines, instruction.args[0], llvm), wide });
    try e.line(lines, "  %{s} = zext {s} {s} to {s}", .{ right, llvm, try e.render(lines, instruction.args[1], llvm), wide });
    try e.line(lines, "  %{s} = mul {s} %{s}, %{s}", .{ product, wide, left, right });
    try e.line(lines, "  %{s} = lshr {s} %{s}, {d}", .{ high, wide, product, shift });
    try e.line(lines, "  %{s} = trunc {s} %{s} to {s}", .{ result, wide, high, llvm });
    try define(e, lines, instruction, try e.print("%{s}", .{result}));
}

fn floatInstruction(opcode: il.Opcode) ?[]const u8 {
    return switch (opcode) {
        .add => "fadd",
        .sub => "fsub",
        .mul => "fmul",
        .div => "fdiv",
        else => null,
    };
}

/// The operand of an `=l add` that holds an object address, if any.
fn pointerIndex(e: *const Emitter, instruction: *const Instruction, llvm: []const u8) ?usize {
    if (instruction.opcode != .add or !std.mem.eql(u8, llvm, "i64")) return null;
    for (instruction.args, 0..) |argument, index| switch (argument) {
        .global => return index,
        .temp => |ref| if (e.facts.pointers.contains(ref.name)) return index,
        else => {},
    };
    return null;
}

/// Compute a checked `add`/`sub`/`mul` with its overflow intrinsics: the
/// first intrinsic's wrapped value is the result, bit for bit. An affine
/// literal-bound hint retains the equivalent ordinary add/sub result.
fn checkedArithmetic(e: *Emitter, lines: *Lines, instruction: *const Instruction, stems: []const classes.Stem, values: [3][]const u8, ordinary: bool) Error!void {
    for (stems, 0..) |stem, index| {
        const intrinsic = try e.print("llvm.{s}.with.overflow.i64", .{@tagName(stem)});
        try e.declareIntrinsic(intrinsic, &.{ "i64", "i64" }, "{ i64, i1 }");
        const pair = try e.fresh("ovpair");
        const bit = try e.fresh("ov");
        try e.line(lines, "  %{s} = call {{ i64, i1 }} @{s}(i64 {s}, i64 {s})", .{ pair, intrinsic, values[0], values[1] });
        if (index == 0 and !ordinary) try e.line(lines, "  %{s} = extractvalue {{ i64, i1 }} %{s}, 0", .{ values[2], pair });
        try e.line(lines, "  %{s} = extractvalue {{ i64, i1 }} %{s}, 1", .{ bit, pair });
        try e.names.overflow_bits.put(e.arena, .{ .producer = instruction, .stem = stem }, try e.print("%{s}", .{bit}));
    }
}

/// One comparison, whose result is an integer holding 0 or 1.
fn onCompare(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    const shape = il.comparison(instruction.opcode);
    const llvm = e.llvmOf(instruction.dest.?);
    if (e.facts.overflow.flags.get(instruction)) |flag| {
        if (e.names.overflow_bits.get(.{ .producer = flag.producer, .stem = flag.stem })) |bit| {
            return define(e, lines, instruction, try e.widen(lines, bit, "i1", llvm));
        }
    }
    var left: []const u8 = undefined;
    if (e.facts.stack_guard == instruction) {
        try e.declareIntrinsic("llvm.stacksave", &.{}, "ptr");
        const stack = try e.fresh("stack");
        const integer = try e.fresh("stackaddr");
        try e.line(lines, "  %{s} = call ptr @llvm.stacksave()", .{stack});
        try e.line(lines, emit.address_line, .{ integer, stack });
        left = try e.print("%{s}", .{integer});
    } else left = try e.render(lines, instruction.args[0], shape.operand);
    const right = try e.render(lines, instruction.args[1], shape.operand);
    const compared = try e.fresh("cmp");
    const operation: []const u8 = if (shape.float) "fcmp" else "icmp";
    try e.line(lines, "  %{s} = {s} {s} {s} {s}, {s}", .{ compared, operation, shape.predicate, shape.operand, left, right });
    try define(e, lines, instruction, try e.widen(lines, try e.print("%{s}", .{compared}), "i1", llvm));
}

/// `neg` on an integer or a float.
fn onNeg(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    const kind = e.typeOf(instruction.dest.?);
    const llvm = kind.llvm();
    const value = try e.render(lines, instruction.args[0], llvm);
    const result = try e.fresh("neg");
    if (kind.kind == .float) {
        try e.line(lines, "  %{s} = fneg {s} {s}", .{ result, llvm, value });
    } else try e.line(lines, "  %{s} = sub {s} 0, {s}", .{ result, llvm, value });
    try define(e, lines, instruction, try e.print("%{s}", .{result}));
}

/// `not` on an integer.
fn onNot(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    const llvm = e.llvmOf(instruction.dest.?);
    const value = try e.render(lines, instruction.args[0], llvm);
    const result = try e.fresh("not");
    try e.line(lines, "  %{s} = xor {s} {s}, -1", .{ result, llvm, value });
    try define(e, lines, instruction, try e.print("%{s}", .{result}));
}

/// One conversion between widths or bit patterns.
fn onConversion(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    const opcode = instruction.opcode;
    const dest = instruction.dest.?;
    const llvm = e.llvmOf(dest);
    if (opcode.isExtension()) {
        const source_llvm = il.intName(il.extensionWidth(opcode));
        const value = try e.render(lines, instruction.args[0], source_llvm);
        const result = try e.fresh("ext");
        const signed = opcode == .extsw or opcode == .extsh or opcode == .extsb;
        try e.line(lines, "  %{s} = {s} {s} {s} to {s}", .{ result, if (signed) "sext" else "zext", source_llvm, value, llvm });
        return define(e, lines, instruction, try e.print("%{s}", .{result}));
    }
    if (opcode == .cast) {
        const target = e.facts.types.get(dest) orelse return e.fail(try e.print("{s}: cast into an untyped temporary", .{e.unit.function.name}));
        const source_name = instruction.args[0].refName() orelse return e.fail(try e.print("{s}: cast of a literal", .{e.unit.function.name}));
        const source_llvm = e.llvmOf(source_name);
        const value = try e.render(lines, instruction.args[0], source_llvm);
        const result = try e.fresh("cast");
        try e.line(lines, "  %{s} = bitcast {s} {s} to {s}", .{ result, source_llvm, value, target.llvm() });
        const held = try e.slot(dest);
        return e.line(lines, "  store {s} %{s}, ptr %{s}, align {d}", .{ target.llvm(), result, held.pointer, @min(held.size, 8) });
    }
    const source_llvm = try e.letterType(il.conversionLetters(opcode).source);
    const value = try e.render(lines, instruction.args[0], source_llvm);
    if (switch (opcode) {
        .sltof, .ultof, .swtof, .uwtof => true,
        else => false,
    }) {
        const result = try e.fresh("cv");
        const signed = opcode == .sltof or opcode == .swtof;
        try e.line(lines, "  %{s} = {s} {s} {s} to {s}", .{ result, if (signed) "sitofp" else "uitofp", source_llvm, value, llvm });
        return define(e, lines, instruction, try e.print("%{s}", .{result}));
    }
    try define(e, lines, instruction, try e.widen(lines, value, source_llvm, llvm));
}

// -- control -------------------------------------------------------------

/// `ret` with the function's own result type.
fn onRet(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    const result = e.unit.function.result orelse return lines.append(e.arena, ret_void);
    if (try e.abiOf(result, false)) |abi| return retAggregate(e, lines, instruction, abi);
    const llvm = try e.letterType(result);
    if (instruction.args.len == 0) return e.line(lines, "  ret {s} 0", .{llvm});
    const value = try e.render(lines, instruction.args[0], llvm);
    try e.line(lines, "  ret {s} {s}", .{ llvm, value });
}

/// Return an aggregate by value, loaded from the address the IL names.
fn retAggregate(e: *Emitter, lines: *Lines, instruction: *const Instruction, abi: emit.Abi) Error!void {
    if (abi.indirect) {
        if (instruction.args.len == 0) {
            try e.declareIntrinsic("llvm.memset.p0.i64", &.{ "ptr", "i8", "i64", "i1" }, "void");
            try e.line(lines, "  call void @llvm.memset.p0.i64(ptr %p_sret, i8 0, i64 {d}, i1 false)", .{abi.size});
            return lines.append(e.arena, ret_void);
        }
        const pointer = try e.address(lines, try e.render(lines, instruction.args[0], "i64"));
        try e.declareIntrinsic("llvm.memmove.p0.p0.i64", &.{ "ptr", "ptr", "i64", "i1" }, "void");
        try e.line(lines, "  call void @llvm.memmove.p0.p0.i64(ptr %p_sret, ptr {s}, i64 {d}, i1 false)", .{ pointer, abi.size });
        return lines.append(e.arena, ret_void);
    }
    if (instruction.args.len == 0) return e.line(lines, "  ret {s} zeroinitializer", .{abi.value.?});
    const pointer = try e.address(lines, try e.render(lines, instruction.args[0], "i64"));
    const value = try e.fresh("ret");
    try e.line(lines, "  %{s} = load {s}, ptr {s}, align {d}", .{ value, abi.value.?, pointer, abi.alignment });
    try e.line(lines, "  ret {s} %{s}", .{ abi.value.?, value });
}

/// A conditional branch on a non-zero integer.
fn onJnz(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    const condition = try e.render(lines, instruction.args[0], "i64");
    const tested = try e.fresh("cond");
    try e.line(lines, "  %{s} = icmp ne i64 {s}, 0", .{ tested, condition });
    const targets = instruction.extra.branch;
    try e.line(lines, "  br i1 %{s}, label %{s}, label %{s}", .{ tested, try label(e, targets[0]), try label(e, targets[1]) });
}

/// A call whose result is the instruction's destination; an aggregate
/// result's address is the destination's value.
fn onCall(e: *Emitter, lines: *Lines, instruction: *const Instruction) Error!void {
    const wanted = if (instruction.dest) |dest| e.llvmOf(dest) else null;
    const reserved = e.names.call_buffers.get(instruction);
    const result_pointer = if (reserved) |buffer| buffer.pointer else null;
    const call: emit.Call = .{ .target = instruction.extra.target, .args = instruction.args, .wanted = wanted, .annotated = instruction.qbe_type, .result_pointer = result_pointer };
    const rendered = try e.renderCall(lines, call);
    // ERROR-TRACE-5: a trace recorder call costs its caller nothing to inline.
    if (instruction.directTarget()) |target| if (runtime.traceRecorder(target)) {
        const last = &lines.items[lines.items.len - 1];
        last.* = try e.print("{s} {s}", .{ last.*, runtime.free_call });
    };
    if (instruction.dest == null) return;
    const abi = rendered.aggregate orelse return define(e, lines, instruction, rendered.value);
    var storage: []const u8 = undefined;
    if (abi.indirect) {
        storage = std.mem.trimStart(u8, rendered.value, "%");
    } else {
        storage = result_pointer orelse try e.fresh("aggret");
        if (result_pointer == null) try e.line(lines, emit.alloca_line, .{ storage, abi.storage, abi.alignment });
        try e.line(lines, "  store {s} {s}, ptr %{s}, align {d}", .{ abi.value.?, rendered.value, storage, abi.alignment });
    }
    const integer = try e.fresh("addr");
    try e.line(lines, emit.address_line, .{ integer, storage });
    try define(e, lines, instruction, try e.print("%{s}", .{integer}));
}
