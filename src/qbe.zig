//! Independent native QBE units. Source locations never enter native artifact bytes.
const slice_abi = ":myl_slice";
const scalar_lower = @import("qbe_scalar.zig");
const zero_local = @import("qbe_format.zig").zero_local;
const arena_lower = @import("qbe_arena.zig");
const borrow_lower = @import("qbe_borrow.zig");
const liveness = @import("qbe_liveness.zig");
const managed_lower = @import("qbe_managed.zig");
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const native_types = @import("native_types.zig");
const diagnostic = @import("diagnostic.zig");
const Source = @import("source.zig").Source;
const entry_adapter = @import("entry_adapter.zig");
const native_descriptors = @import("native_descriptors.zig");
const test_dependencies = @import("native_test_dependencies.zig");
const native_interface = @import("native_interface.zig");
const prelude = @import("prelude.zig");
const qbe_wire = @import("qbe_wire.zig");
/// Failures producing independent QBE native units.
pub const GenerateError = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const drop_local = " call $myl_native_owned_drop(l %heap, l extern ${s}, l %l{d})\n";
/// Headroom `qbe_stack.c` keeps between the frame floor and the guard page.
const frame_headroom: u64 = 65536;
/// The largest frame the native stack carries; a bigger one is heap-backed.
const native_frame_limit: u64 = 32768;
/// Where one function's frame lives: on the native stack, bounded by
/// `native_frame_limit`, or in a heap block of this many bytes that the
/// prologue allocates and every return path releases.
const Frame = union(enum) { native, heap: u64 };
const store_scalar = " storel {d}, %s{d}\n";
const Location = struct { path: []const u8, line: usize, column: usize };
/// One contiguous splice of an inlined callee body into a caller: the callee's
/// metadata symbol, the caller pc range its body occupies, the callee-local pc
/// the range starts at, and the caller pc whose location entry is the call site.
const InlineFrame = struct {
    callee: []const u8,
    start: usize,
    end: usize,
    callee_start: usize,
    call_position: usize,
};
/// One independently linkable unit plus the per-program-counter metadata the
/// generated C tables carry: a source location and an `assert` message, with
/// an empty message for every pc that is not an assertion, and the inlined
/// callee splices whose frames a trap trace must replay.
const Unit = struct {
    test_dependencies: ?test_dependencies.Metadata = null,
    name: []const u8,
    symbol: []const u8,
    il: []const u8,
    locations: []const Location,
    messages: []const []const u8,
    inlines: []const InlineFrame,
    @"export": ?@import("qbe_exports.zig").Export = null,
};

/// Generate a JSON manifest whose independently linkable functions have stable names.
pub fn generate(allocator: std.mem.Allocator, program: bytecode.Program, src: Source, sink: *diagnostic.Sink) GenerateError![]u8 {
    return generateWithInterface(allocator, program, src, sink, .{});
}

/// Include authoritative public exports and an immutable interface schema snapshot.
pub fn generateWithInterface(allocator: std.mem.Allocator, program: bytecode.Program, src: Source, sink: *diagnostic.Sink, interface: native_interface.Interface) GenerateError![]u8 {
    return generateImpl(allocator, program, src, sink, interface, null);
}

/// Emit only selected independently linkable units. `selected` is indexed by the
/// full bytecode function id and must mark every direct callee, every indirect
/// target and every codec method the manifest runtime metadata refers to.
pub fn generateSelectedWithInterface(allocator: std.mem.Allocator, program: bytecode.Program, src: Source, sink: *diagnostic.Sink, interface: native_interface.Interface, selected: []const bool) GenerateError![]u8 {
    if (selected.len != program.functions.len) return error.InternalError;
    try validateSelection(allocator, program, selected);
    return generateImpl(allocator, program, src, sink, interface, selected);
}

fn generateImpl(allocator: std.mem.Allocator, program: bytecode.Program, src: Source, sink: *diagnostic.Sink, interface: native_interface.Interface, selected: ?[]const bool) GenerateError![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var layouts = native_types.Catalog.initRecords(a, program.records) catch |err| return layoutError(err);
    defer layouts.deinit();
    const units = try a.alloc(Unit, program.functions.len);
    for (program.functions, units, 0..) |function, *unit, index| {
        const emit = selected == null or selected.?[index];
        const locations = try a.alloc(Location, if (emit) function.scope.instructions.len else 0);
        const messages = try a.alloc([]const u8, if (emit) function.scope.instructions.len else 0);
        if (emit) for (function.scope.instructions, locations, messages) |instruction, *location, *message| {
            const value = src.locate(instruction.span.start);
            location.* = .{ .path = value.path, .line = value.line, .column = value.column };
            message.* = if (instruction.op == .assert_true) instruction.op.assert_true else "";
        };
        unit.* = .{
            .name = function.name,
            .symbol = try symbol(a, function.name),
            .il = "",
            .locations = locations,
            .messages = messages,
            .inlines = if (emit) try inlineFrames(a, program, function.scope.instructions) else &.{},
            .@"export" = if (emit) try @import("qbe_exports.zig").describe(a, program, index, interface.roots) else null,
        };
    }
    const arenas = arena_lower.present(program);
    // A `str` conversion names only its target type, so the renderers a program
    // needs are read back from each lowered function's typed operand stacks.
    const states = try a.alloc([]const ?[]const typed.Type, program.functions.len);
    @memset(states, &.{});
    // Emit once with roots everywhere to learn which functions can allocate,
    // then again with the analysis in hand: a call to a function that cannot
    // collect needs no root push at its call site.
    var pass: EmitPass = .{
        .allocator = a,
        .program = program,
        .units = units,
        .states = states,
        .layouts = &layouts,
        .sink = sink,
        .arenas = arenas,
        .selected = selected,
        .step_checks = interface.policy.step_checks,
        .frame_checks = interface.policy.frame_checks,
        .checks = interface.policy.checks,
        .pure = &.{},
    };
    try emitPass(pass);
    pass.pure = try allocateAnalysis(a, program, units);
    try emitPass(pass);
    const entry_function = program.functions[@backingInt(program.main)];
    const entry_parameters = try a.alloc([]const u8, entry_function.signature.parameter_count);
    const entry_parameter_names = try a.alloc([]const u8, entry_function.signature.parameter_count);
    for (entry_parameters, entry_function.scope.locals[0..entry_parameters.len]) |*parameter, local| parameter.* = layouts.identity(local.ty) catch |err| return layoutError(err);
    for (entry_parameter_names, entry_function.scope.locals[0..entry_parameter_names.len]) |*name, local| name.* = local.name;
    const entry_argv_element = if (entry_function.signature.parameter_count != 0) entry_adapter.argvElement(entry_function.scope.locals[0].ty, program.records) else null;
    const entry_argv = if (entry_argv_element) |element| native_descriptors.symbol(a, &layouts, element) catch |err| return layoutError(err) else null;
    const descriptors = native_descriptors.generate(a, &layouts) catch |err| return layoutError(err);
    const renderers = @import("native_render.zig").generate(a, &layouts, program, states) catch |err| return layoutError(err);
    // A program that neither prints nor renders a value into text carries no
    // renderers, and copies nothing.
    const runtime_data = if (renderers.len == 0) descriptors else try std.mem.concat(a, u8, &.{ descriptors, renderers });
    const wire_types = (qbe_wire.describe(a, &layouts) catch |err| return layoutError(err)).types;
    const codecs = @import("qbe_codecs.zig").describe(a, program, &layouts) catch |err| return layoutError(err);
    var text_format = false;
    for (program.functions) |function| for (function.scope.instructions) |instruction| {
        if (needsTextRuntime(program, instruction.op)) text_format = true;
    };
    const host = @import("qbe_host.zig").describe(a, program, &layouts) catch |err| return layoutError(err);
    const emitted = if (selected) |mask| try selectedUnits(a, units, mask) else units;
    return std.json.Stringify.valueAlloc(allocator, .{
        .host = host,
        .text_format = text_format,
        .entry_parameters = entry_parameters,
        .entry_parameter_names = entry_parameter_names,
        .entry_argv_element = entry_argv,
        .wire_types = wire_types,
        .codecs = codecs,
        .schema = interface.schema,
        .runtime_data = runtime_data,
        .version = "qbe-units-v1",
        .abi = test_dependencies.abi,
        .functions = emitted,
        .entry = if (selected == null) units[@backingInt(program.main)].symbol else "",
    }, .{});
}

fn selectedUnits(allocator: std.mem.Allocator, units: []const Unit, selected: []const bool) GenerateError![]const Unit {
    var count: usize = 0;
    for (selected) |flag| count += @intFromBool(flag);
    const result = try allocator.alloc(Unit, count);
    var index: usize = 0;
    for (units, selected) |unit, flag| if (flag) {
        result[index] = unit;
        index += 1;
    };
    return result;
}

fn validateSelection(allocator: std.mem.Allocator, program: bytecode.Program, selected: []const bool) GenerateError!void {
    var address_taken: std.ArrayList(typed.FunctionId) = .empty;
    defer address_taken.deinit(allocator);
    for (program.functions) |function| for (function.scope.instructions) |instruction| {
        if (instruction.op == .function_value) try address_taken.append(allocator, instruction.op.function_value.function);
    };
    for (program.functions, selected) |function, emit| {
        if (!emit) continue;
        for (function.scope.instructions) |instruction| {
            // An inline table names the callee's metadata, so that unit must be
            // emitted too; a splice only exists for a pre-inline direct callee,
            // which the selection closure already contains.
            if (instruction.inline_origin) |origin| if (!selected[@backingInt(origin.callee)]) return error.InternalError;
            switch (instruction.op) {
                .call => |target| if (!selected[@backingInt(target)]) return error.InternalError,
                .function_value => |value| if (!selected[@backingInt(value.function)]) return error.InternalError,
                .invoke => for (address_taken.items) |target| if (!selected[@backingInt(target)]) return error.InternalError,
                else => {},
            }
        }
    }
    for (program.records) |record| {
        const codec = record.contract.codec orelse continue;
        if (!selected[@backingInt(codec.decode)] or !selected[@backingInt(codec.encode)]) return error.InternalError;
    }
}

/// Group one function's per-instruction inline provenance into the contiguous
/// splices the runtime walks. Each maximal run of spliced instructions sharing a
/// callee and call site becomes one record naming the callee's metadata symbol,
/// the caller pc range it occupies and the callee-local pc that range starts at.
fn inlineFrames(allocator: std.mem.Allocator, program: bytecode.Program, code: []const bytecode.Instruction) GenerateError![]const InlineFrame {
    var frames: std.ArrayList(InlineFrame) = .empty;
    var index: usize = 0;
    while (index < code.len) {
        const origin = code[index].inline_origin orelse {
            index += 1;
            continue;
        };
        var end = index + 1;
        while (end < code.len) : (end += 1) {
            const next = code[end].inline_origin orelse break;
            const previous = code[end - 1].inline_origin.?;
            if (@backingInt(next.callee) != @backingInt(origin.callee)) break;
            if (next.call_position != origin.call_position) break;
            if (next.callee_pc != previous.callee_pc + 1) break;
        }
        try frames.append(allocator, .{
            .callee = try symbol(allocator, program.functions[@backingInt(origin.callee)].name),
            .start = index,
            .end = end,
            .callee_start = origin.callee_pc,
            .call_position = origin.call_position,
        });
        index = end;
    }
    return frames.toOwnedSlice(allocator);
}

/// Whether one operation needs the shared Zig text runtime unit: `str(value)`
/// formatting, the pinned `int(text)` and `float(text)` grammar, or the same
/// canonical float spelling appended straight into a byte buffer.
fn needsTextRuntime(program: bytecode.Program, op: @FieldType(bytecode.Instruction, "op")) bool {
    switch (op) {
        .cast_integer => |target| return target.isAggregate() and program.records[target.recordIndex()].collection.kind == .string,
        .buffer_operation => |operation| return switch (operation.kind) {
            .parse_int, .parse_float, .parse_int_range, .parse_float_range, .buffer_append_float => true,
            else => false,
        },
        else => return false,
    }
}

fn symbol(a: std.mem.Allocator, name: []const u8) ![]const u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(name, &hash, .{});
    return std.fmt.allocPrint(a, "myl_f_{s}", .{std.fmt.bytesToHex(hash, .lower)});
}
fn layoutError(err: native_types.Error) GenerateError {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
/// Whether the native value is represented in one scalar register, and which
/// aggregate fields its record carries. One shared predicate, so the copied
/// value manifest and this emitter cannot answer it differently.
const scalar = qbe_wire.scalar;
const ownedPointer = qbe_wire.ownedPointer;

/// One match payload binding that names the payload inside its scrutinee instead
/// of copying it: the binding local, the scrutinee local it points into, and the
/// union's payload offset.
const ArmAddress = struct { slot: usize, source: usize, offset: u64, indirect: bool };

/// Whether any instruction writes local `slot`: a whole-value store, a move
/// that also clears the source, an explicit drop, or a match arm's payload
/// binding, which blits the payload into the arm's slot.
fn writtenLocal(function: bytecode.Function, slot: usize) bool {
    for (function.scope.instructions) |instruction| switch (instruction.op) {
        .store_local, .move_local, .drop_local => |target| if (@backingInt(target) == slot) return true,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| if (arm.slot) |target| if (@backingInt(target) == slot) return true,
        else => {},
    };
    return false;
}

/// Whether the instruction at `pc` writes local `index`: a whole-value store, a
/// move, an explicit drop, or a match arm's payload binding into it.
fn writesLocalAt(f: bytecode.Function, pc: usize, index: usize) bool {
    return switch (f.scope.instructions[pc].op) {
        .store_local, .move_local, .drop_local => |target| @backingInt(target) == index,
        .switch_variant => |dispatch| armWrites(dispatch.arms, index),
        else => false,
    };
}

/// Whether any arm of a dispatch binds its payload into local `index`.
fn armWrites(arms: []const @import("bytecode_model.zig").SwitchArm, index: usize) bool {
    for (arms) |arm| if (arm.slot) |target| if (@backingInt(target) == index) return true;
    return false;
}

/// Whether any instruction other than a match's payload binding writes `slot`.
/// A binding writes the slot by design, so a projected binding is checked with
/// this instead of `writtenLocal`: everything else that could write it — a whole
/// value store, a move, an explicit drop — would leave the address the binding
/// holds stale or the value it names released.
fn writtenOutsideBindings(f: bytecode.Function, slot: usize) bool {
    for (f.scope.instructions) |instruction| switch (instruction.op) {
        .store_local, .move_local, .drop_local => |target| if (@backingInt(target) == slot) return true,
        else => {},
    };
    return false;
}

/// Whether one instruction ends the life of the operand it reads: it pops the
/// operand, overwrites the operand slot with its own result, or reads it as an
/// argument or a returned value. Instructions that leave the operand on the
/// stack — a load, a move, a push, a domain wrap, a jump, or an arena boundary
/// — are not on this list, and neither are the provider and resource
/// operations, whose stack effects are not worth re-deriving for a case that
/// never reads an aggregate operand by address.
///
/// QBE-CTORREAD-1: a record or variant constructor reads each field operand
/// once, writes it into the destination and pops it, so it ends that operand's
/// life like any other reader. The destination is either this pc's own scratch
/// or a local `constructorDestination` already proved no reachable instruction
/// reads, so a field read out of a named local's slot can never be the region
/// the constructor is writing.
fn consumesOperand(op: @FieldType(bytecode.Instruction, "op")) bool {
    return switch (op) {
        .get_field,
        .make_record,
        .make_variant,
        .switch_variant,
        .array_length,
        .get_index,
        .update_record,
        .replace_index,
        .store_local,
        .pop,
        .acknowledge,
        .try_result,
        .ret,
        .call,
        .invoke,
        .assert_true,
        .jump_if_false,
        .print,
        .stream_write,
        .binary_integer,
        .cmp_i64,
        .cmp_bool,
        .cmp_enum,
        .cmp_domain,
        .cast_integer,
        .neg_integer,
        => true,
        else => false,
    };
}

/// The digits of a line that is exactly an instruction label (`@i12`), or null
/// when the line is anything else.
fn pcLabel(line: []const u8) ?[]const u8 {
    if (line.len < 3 or line[0] != '@' or line[1] != 'i') return null;
    for (line[2..]) |byte| if (!std.ascii.isDigit(byte)) return null;
    return line[2..];
}

/// Record every `@i<digits>` token a line mentions. A definition line never
/// mentions itself, so callers skip labels before calling this.
fn collectLabelReferences(a: std.mem.Allocator, referenced: *std.StringHashMapUnmanaged(void), line: []const u8) GenerateError!void {
    var rest = line;
    while (std.mem.indexOf(u8, rest, "@i")) |at| {
        const start = at + 2;
        var end = start;
        while (end < rest.len and std.ascii.isDigit(rest[end])) end += 1;
        if (end > start) try referenced.put(a, rest[start..end], {});
        rest = rest[start..];
    }
}

/// Drop the instruction labels no branch names. Straight-line instructions
/// share one block, and a block boundary forces QBE to materialize every live
/// value, so an unreferenced label costs exactly as much as a real one.
fn stripUnreferencedLabels(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    var referenced: std.StringHashMapUnmanaged(void) = .empty;
    defer referenced.deinit(a);
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| try lines.append(a, line);
    for (lines.items) |line| {
        if (pcLabel(line) != null) continue;
        try collectLabelReferences(a, &referenced, line);
    }
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    for (lines.items) |line| {
        if (pcLabel(line)) |digits| if (!referenced.contains(digits)) continue;
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}

/// The prologue line that computes the frame position address every store uses.
/// The record temp differs per function, so this is a prefix.
const position_address = " %position =l add ";

/// The pc of a line that stores one instruction's frame position, or null when
/// the line is anything else. Every emitted instruction opens with one, so these
/// lines also delimit instruction bodies for `elideUnobservablePositions`.
fn positionStore(line: []const u8) ?[]const u8 {
    const prefix = " storel ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    const comma = std.mem.indexOf(u8, rest, ", %position") orelse return null;
    return rest[0..comma];
}

/// Whether a line defines one of the function-level labels the epilogue owns.
/// They end the last instruction's body: a `@failure` in the epilogue is not a
/// reason for the instruction before it to store a position.
fn functionLabel(line: []const u8) bool {
    inline for (.{ "@step_limit", "@failure", "@allocation_failure", "@entry_failure" }) |label| {
        if (std.mem.eql(u8, line, label)) return true;
    }
    return false;
}

/// Drop the frame-position store from instructions no diagnostic can observe.
/// The stored pc exists so a trap trace and an `assert` message name the right
/// instruction, so an instruction whose body cannot fail and is not a call site
/// does not need it: the next instruction that can be observed stores its own.
/// Bodies are delimited by the position stores themselves, which is why this
/// pass runs before unreferenced labels are stripped. In `fast` mode the sticky
/// test is gone, so a call — not the literal text `failure` — is what makes a
/// body observable: any callee can trap and will name this frame's call site.
fn elideUnobservablePositions(a: std.mem.Allocator, text: []const u8, fast: bool) GenerateError![]u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| try lines.append(a, line);
    // A body ends at the next store or at the epilogue, so the observable
    // instructions are known before any line is written.
    var observable: std.ArrayList(usize) = .empty;
    defer observable.deinit(a);
    var index: usize = 0;
    while (index < lines.items.len) : (index += 1) {
        if (positionStore(lines.items[index]) == null) continue;
        var end = index + 1;
        while (end < lines.items.len and positionStore(lines.items[end]) == null and !functionLabel(lines.items[end])) end += 1;
        for (lines.items[index..end]) |body| {
            if (std.mem.indexOf(u8, body, "failure") == null and !(fast and std.mem.indexOf(u8, body, "call $") != null)) continue;
            try observable.append(a, index);
            break;
        }
    }
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    for (lines.items, 0..) |line, at| {
        if (positionStore(line) != null) {
            if (std.mem.indexOfScalar(usize, observable.items, at) == null) continue;
        } else if (observable.items.len == 0 and std.mem.startsWith(u8, line, position_address)) {
            // The frame position has no other reader, so a function that stores
            // none does not need it computed either.
            continue;
        }
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}

/// Move each instruction's frame-position store off its hot path and into the
/// cold block that raises its own trap. A body that names a call other than a
/// `myl_qbe_fail_*` helper keeps its store at the top: a guest callee, runtime
/// helper or provider can trap on its own, and the trace it builds reads this
/// frame's position. A body whose only trap path is a `myl_qbe_fail_*` call gets
/// one store in front of each such call instead, so every pc a trace can name is
/// exactly the pc the store named before, and the loop body carries no store.
fn sinkPositions(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| try lines.append(a, line);
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    var index: usize = 0;
    while (index < lines.items.len) {
        const pc = positionStore(lines.items[index]) orelse {
            try kept.append(a, lines.items[index]);
            index += 1;
            continue;
        };
        var end = index + 1;
        while (end < lines.items.len and positionStore(lines.items[end]) == null and !functionLabel(lines.items[end])) end += 1;
        const body = lines.items[index + 1 .. end];
        var deferred = true;
        for (body) |line| {
            if (std.mem.indexOf(u8, line, "call $") == null) continue;
            if (std.mem.indexOf(u8, line, "call $myl_qbe_fail_") != null) continue;
            deferred = false;
        }
        if (!deferred) {
            try kept.append(a, lines.items[index]);
            try kept.appendSlice(a, body);
        } else {
            for (body) |line| {
                if (std.mem.indexOf(u8, line, "call $myl_qbe_fail_") != null) {
                    try kept.append(a, try std.fmt.allocPrint(a, " storel {s}, %position", .{pc}));
                }
                try kept.append(a, line);
            }
        }
        index = end;
    }
    return std.mem.join(a, "\n", kept.items);
}

/// Whether a lowered body can leave `ctx->trap` set and fall through to the next
/// instruction. A `myl_qbe_fail_*` helper, and any call the body follows with the
/// `jmp @failure` that unwinds, fails the instruction outright; every other call
/// either returns with the trap set — a guest call, `myl_qbe_int_binary`, a
/// provider read — or is a helper that cannot set it at all.
fn stickyTrap(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    // A non-fail call whose very next line may be the `jmp @failure` that makes
    // it an outright failure rather than a returned one.
    var awaiting = false;
    var sticky = false;
    while (lines.next()) |line| {
        if (awaiting) {
            awaiting = false;
            if (std.mem.eql(u8, line, " jmp @failure")) continue;
        }
        const at = std.mem.indexOf(u8, line, "call $") orelse continue;
        const rest = line[at + "call $".len ..];
        const stop = std.mem.indexOfAny(u8, rest, "( \n") orelse rest.len;
        if (std.mem.startsWith(u8, rest[0..stop], "myl_qbe_fail_")) continue;
        sticky = true;
        awaiting = true;
    }
    return sticky;
}

/// Whether one instruction names a local slot at all, as a value it reads or
/// writes or as the receiver an operation is bound to. Used to prove that a
/// temporary has no reader other than the pair a fusion replaces.
fn mentionsLocal(op: @FieldType(bytecode.Instruction, "op"), slot: typed.LocalId) bool {
    switch (op) {
        .begin_arena, .end_arena, .move_local, .drop_local, .load_local, .store_local => |other| return other == slot,
        .buffer_operation => |operation| return operation.owner == slot,
        .resource_io => |operation| return operation.owner == slot,
        .file_method => |method| return method.owner == slot,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |bound| if (bound == slot) return true;
        },
        else => {},
    }
    return false;
}

/// A `bytes` slice whose only reader is the `.decode` two instructions later:
/// the range decoder is called there instead, so the intermediate byte string
/// is never built. Holds the receiver and endpoints as SSA references taken
/// while the slice is lowered, because the slots they came from are overwritten
/// by the slice's own result.
const FusedDecode = struct {
    /// pc of the decode that consumes the slice.
    pc: usize,
    /// SSA reference to the byte-string receiver.
    input: usize,
    /// SSA references to the clamped range endpoints.
    start: usize,
    end: usize,
};

/// The prologue call that computes the shared heap pointer.
const heap_call = " %heap =l call $myl_qbe_heap(l %ctx)";

/// Frozen byte offset of `myl_native_heap.roots`, matched by the
/// `_Static_assert(offsetof(myl_native_heap, roots) == 16, ...)` in
/// `src/qbe_runtime.c`. Generated root pushes and restores read and write this
/// field directly, so it must change only together with the header.
const heap_roots_offset: u64 = 16;

/// One live root at a safepoint: the `%root{i}` slot that receives it, the
/// slot or pointer the traced value is read from, and the descriptor naming the
/// traced layout.
const RootSlot = struct {
    /// Index of the `%root{i}` slot this root occupies.
    index: usize,
    /// IL reference to the slot holding the traced value (`%l{i}`, `%s{i}`) when
    /// `copy` is set, or to the storage the collector walks directly.
    source: []const u8,
    /// Whether `source` names a slot that holds the traced value itself. The
    /// push copies the slot into the record's value word and points the traced
    /// address at that copy, so the collector never takes the slot's address and
    /// QBE can keep it in a register. An aggregate's `source` is already the
    /// storage address the collector must walk, so it is stored as it stands.
    copy: bool,
    /// Descriptor symbol naming the traced layout.
    descriptor: []const u8,
};

/// Runtime callees a lowering may name that allocate nothing and can collect
/// no garbage. A caller that only reaches these (or a `myl_qbe_fail_*` trap
/// helper, matched by prefix) therefore needs no roots around the instruction.
/// Everything else — a guest function, a collection constructor, a print sink,
/// a provider — stays a safepoint.
const pure_callees = [_][]const u8{
    "memset",
    "myl_native_owned_drop",
    "myl_native_list_get",
    // The pinned number grammar and the validating scalar count read their input
    // in place: no allocation, so a function whose only calls are these starts no
    // collection and needs neither a root protocol nor a safepoint.
    "myl_native_number_parse",
    "myl_native_text_compare",
    "myl_native_text_payload",
    "myl_native_bytes_number_parse",
    "myl_native_bytes_range",
    "myl_native_bytes_scalar_count",
    "myl_qbe_int_cast",
    "myl_qbe_int_neg",
    "myl_qbe_int_binary",
    "myl_qbe_float_check",
    "myl_qbe_float_canonical",
    "myl_qbe_float_unary",
    // The read-only collection surfaces: a dictionary probe, a byte search and
    // the octet copy the inlined buffer append performs all take a `const`
    // receiver, walk storage the caller already holds, and allocate nothing. The
    // one write any of them makes is the hash a text caches in its own header, so
    // a frame whose only calls are these never reaches a collection and needs no
    // root record around them.
    "myl_native_dictionary_read",
    "myl_native_dictionary_contains",
    "myl_native_dictionary_length",
    "myl_native_dictionary_key_at",
    "myl_native_dictionary_value_at",
    "myl_native_bytes_find",
    "myl_native_bytes_find_any",
    "myl_native_bytes_starts_with",
    "myl_native_bytes_ends_with",
    "myl_native_bytes_has_byte",
    "myl_native_bytes_copy_octets",
};

/// Frame and prologue plumbing that allocates nothing. It appears in a unit
/// that has no allocating operation at all, so it must not by itself make the
/// function look like it can collect.
const frame_callees = [_][]const u8{
    "myl_qbe_enter_at_sized",
    "myl_qbe_leave",
    "myl_qbe_root_mark",
    "myl_qbe_root_restore",
    "myl_qbe_heap",
    "myl_qbe_require_step_accounting",
    "myl_qbe_require_frame_accounting",
    "myl_qbe_frame_release",
};

/// A call names a callee that allocates nothing and can collect nothing: one
/// of the pure runtime helpers or a `myl_qbe_fail_*` cold trap helper.
fn pureCalleeName(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "myl_qbe_fail_")) return true;
    for (pure_callees) |candidate| if (std.mem.eql(u8, name, candidate)) return true;
    return false;
}

/// One whole-program emission pass, shared by the measurement pass and the
/// pass that uses its result.
const EmitPass = struct {
    allocator: std.mem.Allocator,
    program: bytecode.Program,
    units: []Unit,
    states: [][]const ?[]const typed.Type,
    layouts: *native_types.Catalog,
    sink: *diagnostic.Sink,
    arenas: bool,
    selected: ?[]const bool,
    step_checks: bool,
    /// Whether generated code enforces the `--max-frames` ceiling itself.
    frame_checks: bool,
    /// Whether generated code carries the overflow, cast and bounds guards
    /// (`--unchecked` turns them off; see `native_interface.Policy.checks`).
    checks: bool,
    pure: []const bool,
};

/// Lower every selected function into its unit, overwriting any previous text.
fn emitPass(pass: EmitPass) GenerateError!void {
    for (pass.program.functions, pass.units, pass.states, 0..) |function, *unit, *stacks, index| {
        if (pass.selected != null and !pass.selected.?[index]) continue;
        var emitter = Emitter{
            .allocator = pass.allocator,
            .program = pass.program,
            .function = function,
            .units = pass.units,
            .layouts = pass.layouts,
            .sink = pass.sink,
            .output = .init(pass.allocator),
            .scratch = .init(pass.allocator),
            .arenas = pass.arenas,
            .step_checks = pass.step_checks,
            .frame_checks = pass.frame_checks,
            .checks = pass.checks,
            .entry = index == @backingInt(pass.program.main),
            .pure = pass.pure,
        };
        unit.il = try emitter.emit(unit.symbol);
        stacks.* = emitter.states;
        unit.test_dependencies = test_dependencies.describe(pass.allocator, pass.program, index, unit.il, pass.layouts, emitter.states) catch |err| return layoutError(err);
    }
}

/// Per function, whether it can allocate or reach a call that can, transitively.
/// A direct `.call` to a function this leaves false cannot start a collection,
/// so the caller omits the root protocol around it. The answer is read from the
/// already-emitted text, so it cannot drift from the lowering it describes.
fn allocateAnalysis(a: std.mem.Allocator, program: bytecode.Program, units: []const Unit) GenerateError![]bool {
    const may = try a.alloc(bool, program.functions.len);
    for (units, 0..) |unit, index| may[index] = unitAllocates(unit.il, units);
    var changed = true;
    while (changed) {
        changed = false;
        for (program.functions, 0..) |function, index| {
            if (may[index]) continue;
            for (function.scope.instructions) |instruction| {
                const callee = switch (instruction.op) {
                    .call => |id| @backingInt(id),
                    else => continue,
                };
                if (may[callee]) {
                    may[index] = true;
                    changed = true;
                    break;
                }
            }
        }
    }
    // `may` is "can allocate"; the caller wants "cannot collect".
    for (may) |*value| value.* = !value.*;
    return may;
}

/// Whether a unit's text allocates on its own: any call other than a pure
/// runtime callee or another unit in this program (which the graph handles).
fn unitAllocates(text: []const u8, units: []const Unit) bool {
    if (callsIndirectly(text)) return true;
    var rest = text;
    while (std.mem.indexOf(u8, rest, "call $")) |at| {
        rest = rest[at + "call $".len ..];
        const stop = std.mem.indexOfAny(u8, rest, "( \n") orelse rest.len;
        const name = rest[0..stop];
        const runtime = pureCalleeName(name) or frameCallee(name);
        if (!runtime and !guestSymbol(name, units)) return true;
        rest = rest[stop..];
    }
    return false;
}

/// Whether the text invokes a function value (`QBE-INVOKE-SAFEPOINT-1`). The
/// callee is whatever top-level function the value names, known only at run
/// time, so the call is a safepoint and its caller can allocate — exactly like a
/// direct call to a function that can.
fn callsIndirectly(text: []const u8) bool {
    return std.mem.indexOf(u8, text, " call %") != null;
}

fn frameCallee(name: []const u8) bool {
    for (frame_callees) |candidate| if (std.mem.eql(u8, name, candidate)) return true;
    return false;
}

fn guestSymbol(name: []const u8, units: []const Unit) bool {
    for (units) |unit| if (std.mem.eql(u8, unit.symbol, name)) return true;
    return false;
}

/// Drop the root machinery and the local zero-fill from a function that never
/// pushes a root. With no actual safepoint, no collection can observe a slot,
/// and with no drop, nothing reads one before its first assignment, so both the
/// root mark and its restore, and every per-local `memset`, are dead. A function
/// that does push a root keeps all of them. An inner push is the only code that
/// computes a `%root{i}` field address; the restore is the only code that adds
/// `%heap` to the frozen root offset.
fn dropUnusedRoots(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    if (std.mem.indexOf(u8, text, "=l add %root") != null) return a.dupe(u8, text);
    // A closing arena scope scans every local declared before it through its
    // slot, assigned or not, so the zero-fill is what it reads for one the
    // body has not reached yet (`QBE-ROOTLIVE-1`).
    const drops = std.mem.indexOf(u8, text, "myl_native_owned_drop") != null or
        std.mem.indexOf(u8, text, "myl_qbe_region_retains") != null;
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        if (std.mem.startsWith(u8, line, " %root_mark =l call $myl_qbe_root_mark")) continue;
        if (std.mem.startsWith(u8, line, " storel %root_mark, ")) continue;
        if (std.mem.indexOf(u8, line, "=l add %heap, ") != null) continue;
        if (!drops and isLocalZero(line)) continue;
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}
/// Match the exact `%lN` zero-fill `initializeStorage` emits for a traced local.
fn isLocalZero(line: []const u8) bool {
    if (!std.mem.startsWith(u8, line, " call $memset(l %l")) return false;
    return std.mem.indexOf(u8, line, ", w 0, l ") != null;
}

/// Drop a slot definition no instruction reads. Every `%scratch`, `%arguments`,
/// `%l{i}`, `%s{i}` and `%agg{pc}`/`%aux{pc}` temporary is declared in the entry
/// block, and QBE cannot remove an unused `alloc8` by itself: it lowers each one
/// to a stack adjustment and pointer move. A definition whose name appears once
/// in the unit is read nowhere, so removing it is free.
fn dropUnusedSlots(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    // One pass counts every name this unit defines, so the rewrite is O(text).
    // Rescanning the unit once per definition made a unit with many slots cost
    // its own length multiplied by its slot count, which dominated the frontend
    // of every build.
    var references: SlotReferences = .{};
    defer references.deinit(a);
    try references.count(a, text);
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        if (slotDefinition(line)) |name| if (references.of(name) == 1) continue;
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}

/// Whole-unit `%name` reference counts for the slot names one unit defines. A
/// definition is dropped when its name is referenced exactly once, which is the
/// definition itself. The table is keyed by slices of the counted text, so it
/// owns no key storage and must not outlive that text. Its domain is exactly the
/// names `slotDefinition` accepts: a `%v{d}` value temporary is not a slot, so
/// `of` reports nothing for it even though the unit mentions it.
const SlotReferences = struct {
    counts: std.StringHashMapUnmanaged(usize) = .empty,

    /// Release the count table; its key slices borrow the counted text.
    fn deinit(self: *SlotReferences, allocator: std.mem.Allocator) void {
        self.counts.deinit(allocator);
    }
    /// Count every `%name` reference for each name `text` defines as a slot. A
    /// name is an identifier run, so the reference it counts is a `%` followed
    /// by that whole run: exactly the pair `nameCount` requires.
    fn count(self: *SlotReferences, allocator: std.mem.Allocator, text: []const u8) GenerateError!void {
        var scan = std.mem.splitScalar(u8, text, '\n');
        while (scan.next()) |line| {
            const name = slotDefinition(line) orelse continue;
            try self.counts.put(allocator, name, 0);
        }
        if (self.counts.count() == 0) return;
        var index: usize = 0;
        while (std.mem.indexOfScalarPos(u8, text, index, '%')) |at| {
            const start = at + 1;
            var end = start;
            while (end < text.len and isNameByte(text[end])) end += 1;
            if (end > start) {
                if (self.counts.getPtr(text[start..end])) |slot| slot.* += 1;
            }
            index = end;
        }
    }
    /// How many whole `%name` references the unit holds, matching `nameCount`.
    fn of(self: *const SlotReferences, name: []const u8) usize {
        return self.counts.get(name) orelse 0;
    }
};

/// Whether one byte may continue a QBE identifier, which is the boundary
/// `nameCount` tests after a candidate reference.
fn isNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// The slot name a line defines, when it is a named `alloc8` or heap-frame slot
/// address. `%v{d}` value temporaries are never definitions of this shape.
fn slotDefinition(line: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, " %")) return null;
    const rest = line[2..];
    const equals = std.mem.indexOf(u8, rest, " =l ") orelse return null;
    const name = rest[0..equals];
    if (name.len == 0 or name[0] == 'v') return null;
    for (name) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return null;
    const tail = rest[equals..];
    if (std.mem.indexOf(u8, tail, " alloc8 ") == null and std.mem.indexOf(u8, tail, " add %frame_memory, ") == null) return null;
    return name;
}

/// Count whole `%name` references in the text, ignoring longer identifiers.
///
/// This is the reference implementation, not the hot path: `dropUnusedSlots`
/// asks `SlotReferences` for the same number in one pass, and every counting
/// test compares against this scan. It stays because it is the definition the
/// equivalence is stated in — one text rescan per name — so a later reader can
/// see what the map must reproduce. Do not call it once per definition from the
/// rewrite again.
fn nameCount(text: []const u8, name: []const u8) usize {
    var count: usize = 0;
    var index: usize = 0;
    while (std.mem.indexOfPos(u8, text, index, name)) |at| {
        const prefixed = at > 0 and text[at - 1] == '%';
        const after = at + name.len;
        const bounded = after >= text.len or (!std.ascii.isAlphanumeric(text[after]) and text[after] != '_');
        if (prefixed and bounded) count += 1;
        index = at + name.len;
    }
    return count;
}

// spec: QBE-PROMOTE-2
test "slot reference counting equals the per-name scan it replaces" {
    const text =
        " %l1 =l alloc8 16\n" ++
        " %l10 =l alloc8 16\n" ++
        " %scratch =l alloc8 8\n" ++
        " storel %l1, %l10\n" ++
        " %v3 =l add %scratch, 8\n" ++
        " %l1x =l alloc8 8\n" ++
        " %unused =l add %frame_memory, 0\n" ++
        " call $f(l %l10, l %l1x)\n" ++
        " storew 0, %%l1\n" ++
        " %tail =l add %frame_memory, 0\n";
    var references: SlotReferences = .{};
    defer references.deinit(std.testing.allocator);
    try references.count(std.testing.allocator, text);
    const names = [_][]const u8{ "l1", "l10", "l1x", "scratch", "unused", "tail", "l", "l1xx", "absent" };
    for (names) |name| try std.testing.expectEqual(nameCount(text, name), references.of(name));
    try std.testing.expectEqual(@as(usize, 3), references.of("l1"));
    try std.testing.expectEqual(@as(usize, 1), references.of("tail"));
    // `%v3` is a value temporary, not a slot definition: the unit mentions it
    // once, and the drop rule never asks about it.
    try std.testing.expectEqual(@as(usize, 1), nameCount(text, "v3"));
    try std.testing.expectEqual(@as(usize, 0), references.of("v3"));
}

// spec-case: QBE-PROMOTE-2
test "a slot name that prefixes another is neither counted nor dropped as it" {
    const text =
        " %l1 =l alloc8 16\n" ++
        " %l10 =l alloc8 16\n" ++
        " call $use(l %l10)\n";
    const kept = try dropUnusedSlots(std.testing.allocator, text);
    defer std.testing.allocator.free(kept);
    try std.testing.expectEqualStrings(" %l10 =l alloc8 16\n call $use(l %l10)\n", kept);
}

// spec-case: QBE-PROMOTE-2
test "an unread slot definition is dropped and a read one is kept" {
    const text =
        " %unused =l alloc8 16\n" ++
        " %read =l alloc8 16\n" ++
        " storel %read, %read\n";
    const kept = try dropUnusedSlots(std.testing.allocator, text);
    defer std.testing.allocator.free(kept);
    try std.testing.expectEqualStrings(" %read =l alloc8 16\n storel %read, %read\n", kept);
}

/// The pre-change rewrite, kept as the reference the single-pass counter is
/// tested against: it rescans the whole unit once per slot definition, which is
/// exactly the cost the pass removes. Output bytes must be identical.
fn referenceDropUnusedSlots(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        if (slotDefinition(line)) |name| if (nameCount(text, name) == 1) continue;
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}

/// Compare every slot name a unit defines against the reference per-name scan,
/// so equivalence is checked over the names the unit actually declares rather
/// than only over hand-written cases.
fn expectSlotCountsMatchReference(text: []const u8, references: *const SlotReferences) !void {
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        const name = slotDefinition(line) orelse continue;
        try std.testing.expectEqual(nameCount(text, name), references.of(name));
    }
}

/// One real emitted unit, verbatim: `sexpr.parser::located` from the sexpr-port
/// project built at ReleaseFast. It declares eight slots in 1704 bytes, so the
/// per-name rescan used to walk its whole text eight times.
const recorded_unit =
    \\type :myl_slice = { l, l }
    \\type :t03f63d9a1a213b895a592d5f44a4804ce2a79a0be44ca138053f23212e67a8ff = align 8 { b 32 }
    \\type :t58a57a37ccc3996fdbd3dbe4ed5cc5eb56a0a9b47b95005d2e3ea6952a56cfc7 = align 8 { b 24 }
    \\export function :t03f63d9a1a213b895a592d5f44a4804ce2a79a0be44ca138053f23212e67a8ff $myl_f_b59e41fe30fc69ebc164c43506ed7df38506c00a2c95f0307df5a00a9552a34b(l %ctx, l %a0, l %a1) {
    \\@entry
    \\ %trap =l add %ctx, 32
    \\ %empty =l alloc8 32
    \\ call $memset(l %empty, w 0, l 32)
    \\ %l0 =l alloc8 24
    \\ %l1 =l alloc8 8
    \\ %s0 =l alloc8 8
    \\ %s1 =l alloc8 8
    \\ %s2 =l alloc8 8
    \\ %s3 =l alloc8 8
    \\ %agg7 =l alloc8 32
    \\ %v6 =l alloc8 32
    \\ %v5 =l add %ctx, 48
    \\ %v14 =l loadl %v5
    \\ storel %v14, %v6
    \\ %v15 =l add %v6, 8
    \\ storel extern $myl_f_b59e41fe30fc69ebc164c43506ed7df38506c00a2c95f0307df5a00a9552a34b_meta, %v15
    \\ %v16 =l add %v6, 16
    \\ storel 0, %v16
    \\ storel %v6, %v5
    \\ storel %a0, %l0
    \\ storel %a1, %l1
    \\ jmp @i0
    \\@i0
    \\ %v18 =l loadl %l1
    \\ storel %v18, %s0
    \\ %v19 =l loadl %l0
    \\ storel %v19, %s1
    \\ %v20 =l loadl %s1
    \\ %v21 =l add %v20, 0
    \\ %v22 =l loadl %v21
    \\ storel %v22, %s1
    \\ %v23 =l loadl %l0
    \\ storel %v23, %s2
    \\ %v24 =l loadl %s2
    \\ %v25 =l add %v24, 8
    \\ %v26 =l loadl %v25
    \\ storel %v26, %s2
    \\ %v27 =l loadl %l0
    \\ storel %v27, %s3
    \\ %v28 =l loadl %s3
    \\ %v29 =l add %v28, 16
    \\ %v30 =l loadl %v29
    \\ storel %v30, %s3
    \\ %v31 =l copy %agg7
    \\ %v32 =l add %v31, 0
    \\ %v33 =l loadl %s0
    \\ storel %v33, %v32
    \\ %v34 =l add %v31, 8
    \\ %v35 =l loadl %s1
    \\ storel %v35, %v34
    \\ %v36 =l add %v31, 16
    \\ %v37 =l loadl %s2
    \\ storel %v37, %v36
    \\ %v38 =l add %v31, 24
    \\ %v39 =l loadl %s3
    \\ storel %v39, %v38
    \\ storel %v31, %s0
    \\ %v40 =l loadl %s0
    \\ %v41 =l loadl %v6
    \\ storel %v41, %v5
    \\ ret %v40
    \\@failure
    \\ %v45 =l loadl %v6
    \\ storel %v45, %v5
    \\ ret %empty
    \\@entry_failure
    \\ ret %empty
    \\}
;

// spec-case: QBE-PROMOTE-2
test "a recorded unit is counted and rewritten exactly as the per-name scan did" {
    var references: SlotReferences = .{};
    defer references.deinit(std.testing.allocator);
    try references.count(std.testing.allocator, recorded_unit);
    try expectSlotCountsMatchReference(recorded_unit, &references);
    const rewritten = try dropUnusedSlots(std.testing.allocator, recorded_unit);
    defer std.testing.allocator.free(rewritten);
    const reference = try referenceDropUnusedSlots(std.testing.allocator, recorded_unit);
    defer std.testing.allocator.free(reference);
    try std.testing.expectEqualStrings(reference, rewritten);
}

/// Drop the `%heap` prologue call when nothing in the function reads it. QBE
/// cannot remove a call by itself, because a call may have effects, and this one
/// only computes `&ctx->heap`.
fn dropUnusedHeap(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    if (std.mem.count(u8, text, "%heap") != 1) return a.dupe(u8, text);
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        if (std.mem.eql(u8, line, heap_call)) continue;
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}

const Emitter = struct {
    allocator: std.mem.Allocator,
    program: bytecode.Program,
    function: bytecode.Function,
    units: []const Unit,
    sink: *diagnostic.Sink,
    layouts: *native_types.Catalog,
    pc: usize = 0,
    has_roots: bool = false,
    /// Whether any instruction is a safepoint, i.e. an operation whose lowering
    /// can allocate and therefore collect. A rooted function with none never
    /// pushes a root, so it needs no mark/restore either.
    has_safepoints: bool = false,
    /// Set by a lowering that linked the frame's roots itself around the one
    /// allocating branch of an instruction, so the caller must not wrap the
    /// whole body — including the non-allocating fast path — in a second root
    /// push. Cleared before every detached lowering.
    inline_roots: bool = false,
    heap_frame: bool = false,
    arenas: bool = false,
    frame_offset: u64 = 0,
    output: std.Io.Writer.Allocating,
    /// One instruction's lowered text, emitted here first so the emitter can
    /// decide whether that instruction allocates before writing its root pushes.
    scratch: std.Io.Writer.Allocating,
    states: []?[]const typed.Type = &.{},
    serial: usize = 0,
    /// Emit the per-instruction position marker and step-budget check. A build
    /// that cannot be given a runtime ceiling drops both (see `QBE-STEP-ACCOUNTING-1`).
    step_checks: bool = true,
    /// Emit the per-call depth ceiling and its counter. A build that was not given
    /// a frame ceiling omits both and refuses one at run time instead, exactly as
    /// instruction-budget accounting does.
    frame_checks: bool = true,
    /// Emit the value guards: integer overflow, narrowing casts and index
    /// bounds. `--unchecked` clears it, which also removes the frame record
    /// and its position stores when nothing is accounted (`QBE-UNCHECKED-1`).
    checks: bool = true,
    /// True for the function the runtime calls first, the only place the
    /// missing-accounting guard has to run.
    entry: bool = false,
    /// Per program function, whether it can allocate or reach a call that can.
    /// A `.call` to a function whose entry is false needs no root push at its
    /// call site, because no collection can run while it executes.
    pure: []const bool = &.{},
    /// Temps naming the native-stack frame record, `ctx->active_frame` and
    /// `ctx->frames` while a function with a linked record is being emitted.
    record: usize = 0,
    frame_active: usize = 0,
    frame_frames: usize = 0,
    linked: bool = false,
    /// Whether this leaf's own frame is small enough that its caller's floor test
    /// already covers it, so the prologue can skip its own.
    small_leaf: bool = false,
    /// The slice a later `.decode` will consume directly, recorded while its
    /// receiver and endpoints are still SSA references (see `fusibleSlice`).
    fused: ?FusedDecode = null,
    /// Per local, whether the slot holds the address of an aggregate that lives
    /// elsewhere — a parameter this function only reads, or a match arm's payload
    /// binding that names the payload inside a scrutinee this function never
    /// writes — rather than a private copy of its value.
    by_reference: []const borrow_lower.Borrow = &.{},
    /// The payload bindings whose address is stored once at entry, with the
    /// local and offset that address is derived from.
    arm_addresses: []const ArmAddress = &.{},
    /// Per instruction, whether a branch reaches it directly.
    branch_targets: []bool = &.{},
    /// Per instruction, the locals a safepoint there publishes as roots
    /// (`QBE-ROOTLIVE-1`); null publishes every traced local.
    live_roots: ?liveness.Roots = null,

    /// Shared lowering primitive for target operation emitters.
    pub fn reject(self: *Emitter, pc: usize) GenerateError {
        const span = if (self.function.scope.instructions.len > pc) self.function.scope.instructions[pc].span else @import("source.zig").Span{ .start = 0, .end = 0 };
        return self.sink.fail("E_QBE_UNSUPPORTED", span, "this operation or signature is not supported by the native QBE lowering");
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn print(self: *Emitter, comptime fmt: []const u8, args: anytype) GenerateError!void {
        self.output.writer.print(fmt, args) catch return error.OutOfMemory;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn temp(self: *Emitter) usize {
        const id = self.serial;
        self.serial += 1;
        return id;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn load(self: *Emitter, comptime kind: []const u8, slot: usize) GenerateError!usize {
        const id = self.temp();
        try self.print(" %v{d} =l loadl %{s}{d}\n", .{ id, kind, slot });
        return id;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn store(self: *Emitter, slot: usize, id: usize) GenerateError!void {
        try self.print(" storel %v{d}, %s{d}\n", .{ id, slot });
    }
    /// Whether any instruction can jump straight to `pc`, which is the only way
    /// control reaches `pc` without executing its linear predecessor. The answer
    /// comes from one pass over the unit, so a question asked once per local read
    /// costs a lookup rather than a walk of the whole function.
    fn isBranchTarget(self: *Emitter, pc: usize) bool {
        return pc < self.branch_targets.len and self.branch_targets[pc];
    }
    /// Mark every instruction a branch can reach directly.
    fn collectBranchTargets(self: *Emitter) GenerateError![]bool {
        const code = self.function.scope.instructions;
        const targets = try self.allocator.alloc(bool, code.len);
        @memset(targets, false);
        for (code) |instruction| switch (instruction.op) {
            .jump => |target| targets[target] = true,
            .jump_if_false => |target| targets[target] = true,
            .try_result => |propagate| targets[propagate.error_target] = true,
            .switch_variant => |dispatch| {
                for (dispatch.arms) |arm| targets[arm.target] = true;
            },
            else => {},
        };
        return targets;
    }
    /// The temporary local a `bytes` slice at `pc` feeds, when its only reader
    /// is the `.decode` two instructions later. `x[a:b].decode()` lowers to
    /// exactly that: the slice pushes a byte string, the next instruction stores
    /// it into a fresh temporary, and the decode reads that temporary back. The
    /// pattern is only claimed when nothing else names the temporary — another
    /// reader would observe a slice the fused form never builds — and when no
    /// branch enters either later instruction, so only the slice can have
    /// produced the value.
    pub fn fusibleSlice(self: *Emitter, pc: usize) ?usize {
        const code = self.function.scope.instructions;
        if (pc + 2 >= code.len) return null;
        if (self.states[pc + 1] == null or self.states[pc + 2] == null) return null;
        const local = switch (code[pc + 1].op) {
            .store_local => |slot| slot,
            else => return null,
        };
        const index = @backingInt(local);
        // A parameter's own slot is written by the prologue, not only by the
        // store this pattern names.
        if (index < self.function.signature.parameter_count) return null;
        switch (code[pc + 2].op) {
            .buffer_operation => |operation| {
                if (operation.kind != .decode or operation.owner != local) return null;
            },
            else => return null,
        }
        if (self.isBranchTarget(pc + 1) or self.isBranchTarget(pc + 2)) return null;
        for (code, 0..) |instruction, at| {
            if (at == pc + 1 or at == pc + 2) continue;
            if (mentionsLocal(instruction.op, local)) return null;
        }
        return index;
    }
    /// Record the slice a later decode consumes directly.
    pub fn fuseDecode(self: *Emitter, pc: usize, input: usize, start: usize, end: usize) void {
        self.fused = .{ .pc = pc, .input = input, .start = start, .end = end };
    }
    /// The fused decode this instruction performs, if any, consumed once.
    pub fn fusedDecode(self: *Emitter, pc: usize) ?FusedDecode {
        const pending = self.fused orelse return null;
        if (pending.pc != pc) return null;
        self.fused = null;
        return pending;
    }
    /// Drop a recorded fusion whose decode never ran, so it can never apply to a
    /// later instruction.
    fn expireFusedDecode(self: *Emitter, pc: usize) void {
        if (self.fused) |pending| {
            if (pc > pending.pc) self.fused = null;
        }
    }
    /// The 64-bit signed integer literal this program counter's top-of-stack
    /// operand was just pushed with, or null when that operand is not provably
    /// the literal. Only the linear predecessor can have pushed it, and only by
    /// falling through, so a pc any instruction can jump to is never claimed.
    /// The stack height must grow by exactly one across the pair, which rules
    /// out a predecessor whose slot is not the operand being read.
    pub fn pushedLiteral(self: *Emitter, pc: usize) ?i64 {
        if (pc == 0 or pc >= self.states.len) return null;
        const here = self.states[pc] orelse return null;
        const previous = self.states[pc - 1] orelse return null;
        if (here.len != previous.len + 1) return null;
        if (self.isBranchTarget(pc)) return null;
        return switch (self.function.scope.instructions[pc - 1].op) {
            .push_i64 => |value| value,
            .push_integer => |number| {
                const info = number.ty.integer() orelse return null;
                if (info.bits != 64 or !info.signed) return null;
                return std.math.cast(i64, number.value) orelse null;
            },
            else => null,
        };
    }
    fn emit(self: *Emitter, name: []const u8) GenerateError![]const u8 {
        const f = self.function;
        if (f.policy.c_abi) return @import("qbe_c_abi.zig").emit(self, name);
        if (f.policy.host != null) return @import("qbe_host_lower.zig").emit(self, name);
        if (!try self.supported(f.signature.return_type)) return self.reject(0);
        for (f.scope.locals) |local| if (!try self.supported(local.ty)) return self.reject(0);
        const ir = @import("native_ir.zig").analyze(self.allocator, self.program, f) catch |err| switch (err) {
            error.UnsupportedOperation => return self.reject(0),
            error.InternalError => return error.InternalError,
            error.OutOfMemory => return error.OutOfMemory,
        };
        self.states = ir.states;
        self.branch_targets = try self.collectBranchTargets();
        self.by_reference = try self.addressLocals();
        try self.findRoots();
        if (self.has_roots and self.has_safepoints) self.live_roots = try self.rootLiveness();
        const capacity = ir.stack_capacity;
        // QBE-FRAMEFIT-1: before the body exists, the only bound on the per-pc
        // aggregate scratch counts every buffer the lowering might declare, and
        // forwarding and the borrow rule leave most of them undeclared. A frame
        // that bound puts over the limit is lowered onto the native stack first
        // and measured from the scratch that survived; only a frame that is
        // still too big is lowered again, heap-backed, at the bound.
        const possible = try self.frameBytes(capacity, try self.possibleTemporaryBytes());
        const serial = self.serial;
        const text = try self.lower(name, capacity, .native);
        if (possible <= native_frame_limit) return text;
        if (try self.frameBytes(capacity, try declaredTemporaryBytes(text)) <= native_frame_limit) return text;
        self.restart(serial);
        return self.lower(name, capacity, .{ .heap = possible });
    }
    /// Lower the analysed function with its frame placed as `frame` says.
    fn lower(self: *Emitter, name: []const u8, capacity: usize, frame: Frame) GenerateError![]const u8 {
        const f = self.function;
        self.heap_frame = frame == .heap;
        if (self.heap_frame and try self.abiStackBytes() > native_frame_limit) return self.sink.fail("E_QBE_UNSUPPORTED", f.scope.instructions[0].span, "native ABI arguments or results exceed the 32 KiB stack safety limit");
        try self.typeDefinitions();
        try self.print("export function {s} ${s}(l %ctx", .{ try self.returnType(f), name });
        if (try self.largeResult(f)) try self.print(", l %out", .{});
        if (try self.packedParameters(f)) {
            try self.print(", l %packed", .{});
        } else {
            for (f.scope.locals[0..f.signature.parameter_count], 0..) |local, i| try self.print(", {s} %a{d}", .{ try self.parameterType(local), i });
        }
        try self.print(") {{\n@entry\n %trap =l add %ctx, 32\n", .{});
        const return_bytes = try self.returnStorageBytes();
        if (return_bytes != 0) {
            try self.print(" %empty =l alloc8 {d}\n call $memset(l %empty, w 0, l {d})\n", .{ @max(8, return_bytes), @max(8, return_bytes) });
            if (self.heap_frame) try self.print(" %return_storage =l alloc8 {d}\n", .{@max(8, return_bytes)});
        }
        // QBE promotes a slot to a temporary only when its `alloc8` sits in the
        // entry block, so a native-stack frame declares its slots before the
        // frame protocol introduces any label.
        try self.allocateNativeStorage(capacity);
        // A native frame never exceeds `native_frame_limit`, which sits well
        // inside the headroom; a heap frame is held to the size of its block.
        self.small_leaf = self.frameLeaf() and switch (frame) {
            .native => true,
            .heap => |bytes| bytes + 32 < frame_headroom,
        };
        try self.enterFrame(name);
        // A build without instruction-budget accounting cannot honor a runtime
        // step ceiling; refuse it once, before any guest instruction runs.
        if (self.entry) try self.requireAccounting();
        try arena_lower.Lower(Emitter).mark(self);
        if (self.heap_frame) {
            try self.print(" %frame_memory =l call $myl_qbe_frame_allocate(l %ctx, l {d})\n", .{frame.heap});
            try self.checkFailure("allocation_failure");
            try self.allocateStorage(capacity);
            try self.allocateTemporaries(.all);
        }
        try self.allocateDynamicTemporaries();
        try self.initializeStorage();
        if (self.has_roots) try self.print(" %heap =l call $myl_qbe_heap(l %ctx)\n", .{});
        if (self.has_roots and self.has_safepoints) try self.print(" %root_mark =l call $myl_qbe_root_mark(l %ctx)\n", .{});
        if (self.step_checks) try self.print(" %maxsteps =l add %ctx, 16\n", .{});
        try self.print(" jmp @i0\n", .{});
        try self.emitInstructions();
        if (self.step_checks) try self.print("@step_limit\n call $myl_qbe_fail_step(l %ctx)\n jmp @failure\n@failure\n", .{}) else try self.print("@failure\n", .{});
        try arena_lower.Lower(Emitter).restore(self);
        if (self.has_roots and self.has_safepoints) try self.restoreRoots();
        if (self.heap_frame) try self.print(" call $myl_qbe_frame_release(l %ctx, l %frame_memory)\n jmp @allocation_failure\n@allocation_failure\n", .{});
        try self.leaveFrame();
        try self.print(" ret {s}\n@entry_failure\n ret {s}\n}}\n", .{ if (return_bytes == 0) "0" else "%empty", if (return_bytes == 0) "0" else "%empty" });
        var text = try self.output.toOwnedSlice();
        // With no step check, the only reason to store a position is a trap trace
        // or an `assert` message, and both are emitted by a body that mentions a
        // failure path. With a step check, every instruction can fail, so every
        // instruction keeps its position.
        if (!self.step_checks) {
            text = try elideUnobservablePositions(self.allocator, text, !self.stickyFlagTest());
            text = try sinkPositions(self.allocator, text);
        }
        text = try dropUnusedRoots(self.allocator, text);
        text = try dropUnusedHeap(self.allocator, text);
        text = try dropUnusedSlots(self.allocator, text);
        return stripUnreferencedLabels(self.allocator, text);
    }
    /// Forget a lowering whose frame turned out too big for the native stack so
    /// the same analysis can be lowered again heap-backed: the temporary
    /// numbering and every mark one lowering leaves go back to where the
    /// discarded pass started, while the analysis results stay.
    fn restart(self: *Emitter, serial: usize) void {
        self.serial = serial;
        self.pc = 0;
        self.frame_offset = 0;
        self.linked = false;
        self.small_leaf = false;
        self.fused = null;
    }
    fn findRoots(self: *Emitter) GenerateError!void {
        const f = self.function;
        for (f.scope.locals) |local| self.has_roots = self.has_roots or (try self.layout(local.ty)).trace;
        for (self.states) |state| if (state) |stack| {
            for (stack) |ty| self.has_roots = self.has_roots or (try self.layout(ty)).trace;
        };
        for (f.scope.instructions, 0..) |instruction, pc| {
            if (self.states[pc] == null) continue;
            self.has_safepoints = self.has_safepoints or allocates(instruction.op);
        }
    }
    /// Declare every slot this function needs. QBE's slot promotion only looks
    /// at the entry block, so for a native-stack frame these declarations are
    /// emitted before the frame protocol's labels; a heap-backed frame derives
    /// its slots from `%frame_memory`, so they follow that allocation instead.
    fn allocateStorage(self: *Emitter, capacity: usize) GenerateError!void {
        const f = self.function;
        try self.allocateSlot("scratch", 16);
        try self.allocateSlot("arguments", try self.argumentVectorBytes());
        for (f.scope.locals, 0..) |local, i| {
            try self.allocateIndex("l", i, try self.localSlotBytes(i, local.ty));
            const placeholder = try self.placeholderBytes(i, local.ty);
            if (placeholder != 0) try self.allocateIndex("lz", i, placeholder);
        }
        for (0..capacity) |i| try self.allocateIndex("s", i, 8);
        if (self.has_roots) for (0..f.scope.locals.len + capacity) |i| try self.allocateIndex("root", i, 32);
    }
    fn allocateNativeStorage(self: *Emitter, capacity: usize) GenerateError!void {
        // A heap frame cannot derive slot addresses until its allocation has
        // succeeded; the existing heap branch emits all of its storage later.
        if (self.heap_frame) return;
        try self.allocateStorage(capacity);
        // Pure aggregate temporaries are indexed by bytecode pc and reused for
        // every execution of that instruction. Putting those buffers before the
        // block boundary makes QBE reserve them in the fixed frame. Buffers
        // passed through opaque runtime calls stay in the later class below.
        try self.allocateTemporaries(.entry);
    }
    /// Per-pc aggregate scratch. Pure transformations use entry slots; opaque
    /// runtime/provider calls retain QBE's later allocation because moving those
    /// address-taken buffers into entry miscompiles retained resource ownership.
    /// Each class still gets one pair per pc, reused by loops. Heap frames derive
    /// every address from their allocated frame block instead.
    const TemporaryPlacement = enum { entry, dynamic, all };
    fn allocateTemporaries(self: *Emitter, placement: TemporaryPlacement) GenerateError!void {
        for (self.states, 0..) |state, pc| if (state != null and self.usesTemporary(pc) and (placement == .all or (try self.temporaryInEntry(pc)) == (placement == .entry))) {
            const size = try self.temporarySize(pc);
            try self.allocateIndex("agg", pc, size);
            try self.allocateIndex("aux", pc, size);
        };
    }
    fn allocateDynamicTemporaries(self: *Emitter) GenerateError!void {
        if (self.heap_frame) return;
        // These constant-size buffers are still counted by `frameBytes`. They
        // sit below the probe at run time, within the 64 KiB reserve guarding a
        // native frame whose conservative estimate is capped at 32 KiB.
        try self.allocateTemporaries(.dynamic);
    }
    fn temporaryInEntry(self: *Emitter, pc: usize) GenerateError!bool {
        // `temporarySize` deliberately reserves at least one word, but a typed
        // zero-sized aggregate must retain the later-allocation semantics. QBE
        // can otherwise fold its entry slot and propagate a null-like address
        // through the generic load/move path.
        if (try self.hasNonEntryAggregate(pc)) return false;
        return switch (self.function.scope.instructions[pc].op) {
            .make_record, .make_variant, .get_field, .update_record, .replace_index, .get_index, .try_result => true,
            .load_local, .move_local => |slot| !try self.nonEntryType(self.function.scope.locals[@backingInt(slot)].ty),
            else => false,
        };
    }
    fn hasNonEntryAggregate(self: *Emitter, pc: usize) GenerateError!bool {
        if (self.states[pc]) |stack| for (stack) |ty| if (try self.nonEntryType(ty)) return true;
        if (pc + 1 < self.states.len) if (self.states[pc + 1]) |stack| for (stack) |ty| if (try self.nonEntryType(ty)) return true;
        return false;
    }
    fn nonEntryType(self: *Emitter, ty: typed.Type) GenerateError!bool {
        if (!ty.isAggregate()) return false;
        if (self.program.records[ty.recordIndex()].shape.array) |array| if (array.length == 0) return true;
        return (try self.layout(ty)).size == 0;
    }
    fn initializeStorage(self: *Emitter) GenerateError!void {
        const f = self.function;
        for (f.scope.locals, 0..) |local, i| {
            // A parameter is stored into its slot below, before any instruction
            // can run, so a root push can never observe it unset.
            if (i < f.signature.parameter_count) continue;
            const placeholder = try self.placeholderBytes(i, local.ty);
            if (placeholder != 0) {
                try self.print(" call $memset(l %lz{d}, w 0, l {d})\n storel %lz{d}, %l{d}\n", .{ i, placeholder, i, i });
            } else if (self.byReference(i)) {
                // A borrowed element's slot is one word and is never a root, so
                // clearing the word is all an unset slot needs.
                if ((try self.layout(local.ty)).trace) try self.print(" storel 0, %l{d}\n", .{i});
            } else if ((try self.layout(local.ty)).trace) try self.zeroTracedLocal(i, local.ty);
        }
        const packed_args = try self.packedParameters(f);
        for (f.scope.locals[0..f.signature.parameter_count], 0..) |local, i| {
            if (packed_args) try self.unpackArgument(i);
            if (scalar(local.ty, self.program.records)) {
                try self.print(" storel %a{d}, %l{d}\n", .{ i, i });
            } else if (self.byReference(i)) {
                // QBE-AGGREF-1: the slot holds the caller's address, so the
                // parameter is read through it and never copied at entry.
                try self.print(" storel %a{d}, %l{d}\n", .{ i, i });
            } else try self.print(" blit %a{d}, %l{d}, {d}\n", .{ i, i, (try self.layout(local.ty)).size });
        }
        for (self.arm_addresses) |entry| {
            // The payload already lives at a constant offset inside storage this
            // function never writes, so one store at entry gives every arm its
            // binding and no arm copies the payload out.
            const projected = self.temp();
            if (entry.indirect) {
                const base = try self.load("l", entry.source);
                try self.print(" %v{d} =l add %v{d}, {d}\n storel %v{d}, %l{d}\n", .{ projected, base, entry.offset, projected, entry.slot });
            } else try self.print(" %v{d} =l add %l{d}, {d}\n storel %v{d}, %l{d}\n", .{ projected, entry.source, entry.offset, projected, entry.slot });
        }
    }
    /// Whether local `index` holds the address of a parameter this function
    /// only reads. Every other local holds its value.
    pub fn byReference(self: *Emitter, index: usize) bool {
        return index < self.by_reference.len and self.by_reference[index] != .none;
    }
    /// Whether local `index` holds an address into a managed list's backing
    /// storage rather than storage the frame itself owns. Such a slot is only
    /// meaningful across the inert run the borrow was proved over, so the root
    /// protocol never reads it.
    fn borrowsElement(self: *Emitter, index: usize) bool {
        return index < self.by_reference.len and self.by_reference[index] == .element;
    }
    /// Push the value of local `index` onto the operand stack at `slot`.
    ///
    /// A parameter this function only reads holds the caller's address, so the
    /// operand is that address: nothing can write through it (the parameter is
    /// read-only) and it stays valid, unchanged, for the whole call. An ordinary
    /// local whose value the very next instruction alone consumes is named by
    /// its own slot the same way, one copy fewer on every field or tag read.
    /// Every other local is snapshotted into this pc's aggregate scratch exactly
    /// as before, so a value whose type owns a resource keeps owning its copy.
    fn readLocal(self: *Emitter, index: usize, slot: usize) GenerateError!void {
        const ty = self.function.scope.locals[index].ty;
        if (scalar(ty, self.program.records)) return self.store(slot, try self.load("l", index));
        if (self.byReference(index)) return self.store(slot, try self.load("l", index));
        if (try self.borrowableLocal(index, slot)) return self.print(" storel %l{d}, %s{d}\n", .{ index, slot });
        try self.print(" blit %l{d}, %agg{d}, {d}\n storel %agg{d}, %s{d}\n", .{ index, self.pc, (try self.layout(ty)).size, self.pc, slot });
    }
    /// Whether an ordinary local may stand in for a copy of its own value.
    ///
    /// It may when its type owns nothing — so no drop, `move_local` clear or
    /// arena rebind can ever release or clear the slot — and the instruction
    /// after this one is the only reader, reached by falling through rather
    /// than by a branch. That reader consumes the operand: it pops it,
    /// overwrites the operand slot with its own result, or reads it as an
    /// argument. Nothing runs in between, and a call in between runs with this
    /// frame suspended, so the slot's address is a valid stand-in for the copy
    /// for exactly as long as the operand lives.
    fn borrowableLocal(self: *Emitter, index: usize, slot: usize) GenerateError!bool {
        const value = try self.layout(self.function.scope.locals[index].ty);
        if (value.drop) return false;
        // A zero-length aggregate copies nothing; it keeps the scratch the
        // frame protocol places after the entry block, because that scratch is
        // what stops QBE folding a null-like address into the load.
        if (value.size == 0) return false;
        // The consumer is the first instruction whose own execution leaves the
        // stack at or below the operand this read pushes. Every instruction
        // before it either pushed another operand above ours or read ours; in
        // both cases our value stayed in its frame slot, because nothing in the
        // window writes the local and no branch enters it without passing
        // through this read. A call in the window runs with this frame suspended
        // and reads the operand during its own execution, so the address it was
        // handed stays valid.
        var consumer = self.pc + 1;
        while (true) {
            if (consumer >= self.function.scope.instructions.len or consumer >= self.states.len) return false;
            if (self.states[consumer] == null) return false;
            if (self.isBranchTarget(consumer) or writesLocalAt(self.function, consumer, index)) return false;
            const after = if (consumer + 1 < self.states.len) self.states[consumer + 1] else null;
            const height = if (after) |stack| stack.len else 0;
            if (height <= slot + 1) break;
            consumer += 1;
        }
        const op = self.function.scope.instructions[consumer].op;
        // A match arm's payload binding copies out of the scrutinee. Naming the
        // scrutinee's slot would copy a region onto itself, so that arm keeps
        // the scratch copy the other locals use.
        if (op == .switch_variant) for (op.switch_variant.arms) |arm| if (arm.slot) |target| if (@backingInt(target) == index) return false;
        return consumesOperand(op);
    }
    /// Mark every parameter this function never writes. Such a parameter
    /// crosses the call boundary as the address of the caller's value, which
    /// the callee reads where it is: the caller's copy at the argument site
    /// and the callee's copy into its frame both disappear, and the value is
    /// the same one either way because nothing writes through the slot.
    ///
    /// A parameter the body stores, moves, drops or binds a match payload into
    /// keeps its private slot and its entry copy, so value semantics are
    /// untouched. A move-only value is never addressed: its single owner stays
    /// the callee's copy, which `cleanupLocals` releases exactly once.
    fn addressLocals(self: *Emitter) GenerateError![]borrow_lower.Borrow {
        const f = self.function;
        const flags = try self.allocator.alloc(borrow_lower.Borrow, f.scope.locals.len);
        @memset(flags, .none);
        for (f.scope.locals[0..f.signature.parameter_count], 0..) |local, index| {
            if (self.isScalar(local.ty)) continue;
            const value = try self.layout(local.ty);
            if (value.copy != .bytes or value.drop) continue;
            // A zero-length aggregate copies nothing; it keeps the scratch the
            // frame protocol places after the entry block, because that scratch
            // is what stops QBE folding a null-like address into the load.
            if (value.size == 0) continue;
            if (writtenLocal(f, index)) continue;
            flags[index] = .value;
        }
        self.arm_addresses = try self.payloadAddresses(f, flags);
        // QBE-ELEMREF-2 and QBE-CALLREF-1: the ordinary locals one instruction
        // fills from storage this frame can name — a list element, a
        // record-returning call's result buffer — hold that address instead of
        // a copy of the value.
        try borrow_lower.Lower(Emitter).claim(self, flags);
        return flags;
    }
    /// The match payload bindings that may name the payload where it lives.
    ///
    /// A binding projected this way holds the address of the payload inside the
    /// scrutinee's own storage instead of a copy of it, so an arm that only reads
    /// fields pays no payload copy. The address is a compile-time constant —
    /// the scrutinee local's slot plus the union's payload offset — which is why
    /// it can be stored once at entry: the scrutinee is a local this function
    /// never writes, so its storage and content never move.
    ///
    /// Every projected shape is checked: the scrutinee must be produced by the
    /// `load_local` immediately before the dispatch with no branch reaching the
    /// dispatch directly (so that producer is the only one), must not itself be
    /// an address-holding local, and must never be written (`writtenLocal` covers
    /// whole-value stores, moves, drops and arm bindings, and a record binding is
    /// immutable, so a field write through it is already `E_IMMUTABLE`). The
    /// binding slot must be an aggregate that owns nothing — a drop obligation
    /// would need the copy the binding no longer has — of nonzero size, and it
    /// must never be written either. A payload that owns nothing and is never
    /// stored through is therefore safe to name in place, and the tracing
    /// protocol already reads an address-holding local through its address.
    fn payloadAddresses(self: *Emitter, f: bytecode.Function, flags: []borrow_lower.Borrow) GenerateError![]const ArmAddress {
        var projected: std.ArrayList(ArmAddress) = .empty;
        for (f.scope.instructions, 0..) |instruction, pc| switch (instruction.op) {
            .switch_variant => |dispatch| {
                if (pc == 0 or self.isBranchTarget(pc)) continue;
                const source = switch (f.scope.instructions[pc - 1].op) {
                    .load_local => |slot| @backingInt(slot),
                    else => continue,
                };
                if (source >= flags.len) continue;
                if (writtenLocal(f, source)) continue;
                // A local that already holds an address (a parameter this
                // function only reads, or another projected binding) keeps the
                // scrutinee at the caller's storage, so the payload address is
                // one load deeper but just as constant.
                const indirect = flags[source] != .none;
                const union_layout = try self.layout(dispatch.ty);
                for (dispatch.arms) |arm| {
                    const target = @backingInt(arm.slot orelse continue);
                    if (target >= flags.len or flags[target] != .none) continue;
                    const local = f.scope.locals[target];
                    if (self.isScalar(local.ty)) continue;
                    const value = try self.layout(local.ty);
                    if (value.drop or value.size == 0) continue;
                    if (writtenOutsideBindings(f, target)) continue;
                    flags[target] = .value;
                    try projected.append(self.allocator, .{ .slot = target, .source = source, .offset = union_layout.payload_offset, .indirect = indirect });
                }
            },
            else => {},
        };
        return projected.toOwnedSlice(self.allocator);
    }
    /// Whether this function links a frame record at all. QBE-UNCHECKED-1: a
    /// build that carries neither ceiling and was asked to drop its value
    /// guards has nothing left that reads the record — no step check, no depth
    /// counter, and no guard whose trap would want a trace — so the record, the
    /// stack-floor test, the `_meta` store, the link/unlink pair and every
    /// `storel N, %position` go away together. Every other policy keeps them.
    fn framesLinked(self: *const Emitter) bool {
        return self.checks or self.step_checks or self.frame_checks;
    }
    /// Link this function's native-stack frame record and enforce the logical
    /// depth ceiling and the execution-stack floor without a runtime call. The
    /// record is `{prev, function, position, native_bytes}`; generated code owns
    /// the first three words and reads `ctx->frames`/`ctx->frame_limit`/
    /// `ctx->frame_floor` at their frozen offsets. A build that links no record
    /// at all emits nothing here (see `framesLinked`).
    fn enterFrame(self: *Emitter, name: []const u8) GenerateError!void {
        if (!self.framesLinked()) return;
        const admit = self.temp();
        const stack = self.temp();
        const limit_fail = self.temp();
        const floor_fail = self.temp();
        self.frame_frames = self.temp();
        self.frame_active = self.temp();
        self.record = self.temp();
        const frames = self.temp();
        const limit_slot = self.temp();
        const limit = self.temp();
        const at_limit = self.temp();
        const floor_slot = self.temp();
        const floor = self.temp();
        const below = self.temp();
        const previous = self.temp();
        const function_slot = self.temp();
        const position_slot = self.temp();
        const next = self.temp();
        if (self.frame_checks) try self.print(
            " %v{d} =l add %ctx, 8\n %v{d} =l loadl %v{d}\n %v{d} =l add %ctx, 56\n %v{d} =l loadl %v{d}\n %v{d} =l ceql %v{d}, %v{d}\n" ++
                " jnz %v{d}, @limitfail{d}, @frameadmit{d}\n@limitfail{d}\n call $myl_qbe_fail_frame(l %ctx)\n jmp @entry_failure\n@frameadmit{d}\n",
            .{ self.frame_frames, frames, self.frame_frames, limit_slot, limit, limit_slot, at_limit, frames, limit, at_limit, limit_fail, admit, limit_fail, admit },
        );
        // A leaf's own frame is bounded at compile time, and its caller already
        // proved the frame pointer sits a whole headroom above the guard page, so a
        // leaf that stays well inside that headroom cannot reach it. The guard is
        // redundant there and one comparison per call goes away.
        const guarded = !self.small_leaf;
        // Without logical depth accounting there is no `@frameadmit` block
        // above. Still end the entry block before allocating the probe record:
        // QBE reserves every constant allocation in entry in its static frame,
        // while a later allocation lowers to a stack adjustment after that
        // frame and its register saves. The latter address is the conservative
        // physical stack position the floor comparison requires.
        if (guarded and !self.frame_checks) try self.print(" jmp @frameadmit{d}\n@frameadmit{d}\n", .{ admit, admit });
        if (guarded) try self.print(
            " %v{d} =l alloc8 32\n %v{d} =l add %ctx, 64\n %v{d} =l loadl %v{d}\n %v{d} =l cultl %v{d}, %v{d}\n" ++
                " jnz %v{d}, @floorfail{d}, @stackadmit{d}\n@floorfail{d}\n call $myl_qbe_fail_frame(l %ctx)\n jmp @entry_failure\n@stackadmit{d}\n",
            .{ self.record, floor_slot, floor, floor_slot, below, self.record, floor, below, floor_fail, stack, floor_fail, stack },
        ) else try self.print(" %v{d} =l alloc8 32\n", .{self.record});
        try self.print(
            " %v{d} =l add %ctx, 48\n %v{d} =l loadl %v{d}\n storel %v{d}, %v{d}\n %v{d} =l add %v{d}, 8\n storel extern ${s}_meta, %v{d}\n",
            .{ self.frame_active, previous, self.frame_active, previous, self.record, function_slot, self.record, name, function_slot },
        );
        if (self.frame_checks) try self.print(
            " %v{d} =l add %v{d}, 16\n storel 0, %v{d}\n storel %v{d}, %v{d}\n %v{d} =l add %v{d}, 1\n storel %v{d}, %v{d}\n",
            .{ position_slot, self.record, position_slot, self.record, self.frame_active, next, frames, next, self.frame_frames },
        ) else try self.print(
            " %v{d} =l add %v{d}, 16\n storel 0, %v{d}\n storel %v{d}, %v{d}\n",
            .{ position_slot, self.record, position_slot, self.record, self.frame_active },
        );
        try self.print(" %position =l add %v{d}, 16\n", .{self.record});
        self.linked = true;
    }
    /// Unlink this function's frame record and drop the frame count.
    /// Refuse, once at the entry point, any runtime ceiling this build omitted
    /// accounting for, so a mismatch is reported instead of silently ignored.
    fn requireAccounting(self: *Emitter) GenerateError!void {
        if (!self.step_checks) try self.print(" call $myl_qbe_require_step_accounting(l %ctx)\n", .{});
        if (!self.frame_checks) try self.print(" call $myl_qbe_require_frame_accounting(l %ctx)\n", .{});
    }
    /// Whether this function transfers control to another guest frame. A leaf's
    /// stack use is bounded at compile time, which is what lets its prologue skip
    /// the floor guard: the caller already checked the headroom.
    fn frameLeaf(self: *Emitter) bool {
        for (self.function.scope.instructions) |instruction| switch (instruction.op) {
            .call, .invoke => return false,
            else => {},
        };
        return true;
    }
    fn leaveFrame(self: *Emitter) GenerateError!void {
        if (!self.linked) return;
        const previous = self.temp();
        const frames = self.temp();
        const next = self.temp();
        if (self.frame_checks) try self.print(
            " %v{d} =l loadl %v{d}\n storel %v{d}, %v{d}\n %v{d} =l loadl %v{d}\n %v{d} =l sub %v{d}, 1\n storel %v{d}, %v{d}\n",
            .{ previous, self.record, previous, self.frame_active, frames, self.frame_frames, next, frames, next, self.frame_frames },
        ) else try self.print(
            " %v{d} =l loadl %v{d}\n storel %v{d}, %v{d}\n",
            .{ previous, self.record, previous, self.frame_active },
        );
    }
    /// Whether an instruction's own body is lowered aside for the sticky-trap
    /// test that follows it. The set is exactly the switch arm that can emit the
    /// test; an opcode outside it keeps the test unconditionally, so a set that
    /// drifts only ever costs a test that cannot fail.
    fn stickyOp(op: @FieldType(bytecode.Instruction, "op")) bool {
        return switch (op) {
            .call,
            .invoke,
            .acquire_buffer,
            .buffer_operation,
            .external_read,
            .environment_get,
            .environment_only,
            .environment_names,
            .acquire_resource,
            .complete_resource,
            .resource_io,
            .restrict_resource,
            .dir_resource,
            .host_resource,
            .mul_i64_checked,
            .div_i64_checked,
            .rem_i64_checked,
            .cast_integer,
            .neg_integer,
            .neg_i64_checked,
            .unary_float,
            => true,
            else => false,
        };
    }
    fn emitInstructions(self: *Emitter) GenerateError!void {
        const f = self.function;
        for (f.scope.instructions, 0..) |instruction, pc| {
            const stack = self.states[pc] orelse continue;
            // The position marker is not budget metadata: trap traces and
            // `assert` messages read the frame's current pc, so it is emitted
            // even where the step check is not.
            if (self.framesLinked()) try self.print("@i{d}\n storel {d}, %position\n", .{ pc, pc }) else try self.print("@i{d}\n", .{pc});
            if (self.step_checks) try self.step();
            self.pc = pc;
            self.expireFusedDecode(pc);
            // An instruction whose own body can leave `ctx->trap` set and still
            // fall through is lowered aside so the test after it can be skipped
            // when it cannot: a body naming only `myl_qbe_fail_*` helpers — every
            // one of them unwinds — never needs the sticky read.
            var sticky_text: ?[]const u8 = null;
            if (self.rootedSafepoint(instruction.op)) {
                // The opcode admits allocation, so lower it aside first and push
                // roots only if this variant's text actually names an allocating
                // callee; the common non-allocating case emits nothing extra.
                self.inline_roots = false;
                const text = try self.lowerDetached(instruction.op, stack);
                if (stickyOp(instruction.op)) sticky_text = text;
                if (self.inline_roots) {
                    // This lowering guarded its own allocating branch with a root
                    // push, so the fast path runs unrooted and the caller adds
                    // nothing around the whole body.
                    self.inline_roots = false;
                    try self.print("{s}", .{text});
                } else if (loweredAllocates(text)) {
                    const pushed = try self.roots(stack);
                    try self.print("{s}", .{text});
                    if (pushed) try self.restoreRoots();
                } else try self.print("{s}", .{text});
            } else if (stickyOp(instruction.op)) {
                sticky_text = try self.lowerDetached(instruction.op, stack);
                try self.print("{s}", .{sticky_text.?});
            } else try self.emitOp(instruction.op, stack);
            switch (instruction.op) {
                .binary_integer => |operation| {
                    if (operation.ty.integer()) |integer| {
                        if (scalar_lower.select(operation.op, integer.signed) == null and operation.op != .add and operation.op != .sub and @backingInt(operation.op) < @backingInt(typed.BinaryOp.f64_add)) try self.checkFailure("failure");
                    }
                },
                .call,
                .invoke,
                .acquire_buffer,
                .buffer_operation,
                .external_read,
                .environment_get,
                .environment_only,
                .environment_names,
                .acquire_resource,
                .complete_resource,
                .resource_io,
                .restrict_resource,
                .dir_resource,
                .host_resource,
                .mul_i64_checked,
                .div_i64_checked,
                .rem_i64_checked,
                .cast_integer,
                .neg_integer,
                .neg_i64_checked,
                .unary_float,
                => if (sticky_text == null or stickyTrap(sticky_text.?)) try self.checkFailure("failure"),
                else => {},
            }
            // An instruction whose successor has a body falls through into it;
            // only a real terminator (or a successor that emits nothing) jumps.
            const falls = pc + 1 < self.states.len and self.states[pc + 1] != null;
            switch (instruction.op) {
                .ret, .jump, .jump_if_false, .switch_variant => {},
                else => if (!falls) try self.print(" jmp @i{d}\n", .{pc + 1}),
            }
            if (instruction.op == .jump_if_false) {
                if (falls) try self.print("@next{d}\n", .{self.serial}) else try self.print("@next{d}\n jmp @i{d}\n", .{ self.serial, pc + 1 });
            }
        }
    }
    fn allocates(op: @FieldType(bytecode.Instruction, "op")) bool {
        return switch (op) {
            .cast_integer,
            .call,
            .invoke,
            .acquire_buffer,
            .buffer_operation,
            .make_record,
            .get_index,
            .binary_integer,
            .acquire_resource,
            .complete_resource,
            .resource_io,
            .file_access,
            .file_method,
            // `print` begins a sink that can allocate its buffer, so managed
            // operands and locals must be rooted across it.
            .print,
            => true,
            else => false,
        };
    }
    /// Whether an operation whose opcode may allocate actually does. Every
    /// allocation a lowering performs is a runtime call, so an instruction is
    /// only a real safepoint when its text names a callee outside the pure set.
    /// A bounds-checked byte read and an integer cast, for instance, cannot
    /// collect even though `get_index` and `cast_integer` can allocate in
    /// another variant, and this keeps them from pushing roots they never need.
    fn loweredAllocates(text: []const u8) bool {
        if (callsIndirectly(text)) return true;
        var rest = text;
        while (std.mem.indexOf(u8, rest, "call $")) |at| {
            rest = rest[at + "call $".len ..];
            const stop = std.mem.indexOfAny(u8, rest, "( \n") orelse rest.len;
            if (!pureCallee(rest[0..stop])) return true;
            rest = rest[stop..];
        }
        return false;
    }
    fn pureCallee(name: []const u8) bool {
        return pureCalleeName(name);
    }
    /// Whether an instruction needs the root protocol: its opcode admits
    /// allocation, and it is not a call to a function that cannot collect.
    fn rootedSafepoint(self: *Emitter, op: @FieldType(bytecode.Instruction, "op")) bool {
        if (!self.has_roots or !self.has_safepoints) return false;
        if (!allocates(op)) return false;
        return !self.callsPureFunction(op);
    }
    /// Whether this instruction is a direct call to a function that can neither
    /// allocate nor reach an allocation, so no collection can run inside it and
    /// the caller needs no roots across it.
    fn callsPureFunction(self: *Emitter, op: @FieldType(bytecode.Instruction, "op")) bool {
        const id = switch (op) {
            .call => |callee| @backingInt(callee),
            else => return false,
        };
        return id < self.pure.len and self.pure[id];
    }
    fn allocateIndex(self: *Emitter, kind: []const u8, index: usize, size: u64) GenerateError!void {
        try self.allocateSlot(try std.fmt.allocPrint(self.allocator, "{s}{d}", .{ kind, index }), size);
    }
    fn allocateSlot(self: *Emitter, name: []const u8, size: u64) GenerateError!void {
        if (self.heap_frame) {
            try self.print(" %{s} =l add %frame_memory, {d}\n", .{ name, self.frame_offset });
            self.frame_offset = try addFrame(self.frame_offset, size);
        } else try self.print(" %{s} =l alloc8 {d}\n", .{ name, @max(8, size) });
    }
    /// Return a value after releasing heap-backed execution storage safely.
    pub fn returnValue(self: *Emitter, value: usize) GenerateError!void {
        try self.cleanupLocals();
        try arena_lower.Lower(Emitter).restore(self);
        var output = value;
        const indirect = try self.largeResult(self.function);
        if (indirect) {
            try self.print(" blit %v{d}, %out, {d}\n", .{ value, (try self.layout(self.function.signature.return_type)).size });
            output = self.temp();
            try self.print(" %v{d} =l copy 0\n", .{output});
        }
        if (self.heap_frame) {
            const bytes = try self.returnStorageBytes();
            if (bytes != 0) {
                try self.print(" blit %v{d}, %return_storage, {d}\n", .{ value, bytes });
                output = self.temp();
                try self.print(" %v{d} =l copy %return_storage\n", .{output});
            }
            try self.print(" call $myl_qbe_frame_release(l %ctx, l %frame_memory)\n", .{});
        }
        try self.leaveFrame();
        try self.print(" ret %v{d}\n", .{output});
    }
    fn dropOperand(self: *Emitter, slot: usize, ty: typed.Type) GenerateError!void {
        if (!(try self.layout(ty)).drop) return;
        if (self.isScalar(ty)) {
            try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %s{d})\n", .{ try self.descriptor(ty), slot });
        } else {
            try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %v{d})\n", .{ try self.descriptor(ty), try self.load("s", slot) });
        }
    }
    fn cleanupLocals(self: *Emitter) GenerateError!void {
        var index = self.function.scope.locals.len;
        while (index > 0) {
            index -= 1;
            // A parameter read through the caller's address is the caller's
            // value: this frame never owned it and must not release it.
            if (self.byReference(index)) continue;
            const local = self.function.scope.locals[index];
            if (!(try self.layout(local.ty)).drop) continue;
            try self.print(drop_local, .{ try self.descriptor(local.ty), index });
        }
    }
    fn returnStorageBytes(self: *Emitter) GenerateError!u64 {
        const f = self.function;
        if (self.isScalar(f.signature.return_type) or try self.largeResult(f)) return 0;
        return @max(8, (try self.layout(f.signature.return_type)).size);
    }
    fn valueStackBytes(self: *Emitter, ty: typed.Type) GenerateError!u64 {
        if (self.isScalar(ty) or try self.largeValue(ty)) return 8;
        return addFrame(0, @max(8, (try self.layout(ty)).size));
    }
    fn parameterStackBytes(self: *Emitter, local: typed.Local) GenerateError!u64 {
        return self.valueStackBytes(local.ty);
    }
    /// Wide signatures pass normalized scalar words and aggregate pointers in one vector.
    pub fn packedParameters(self: *Emitter, function: bytecode.Function) GenerateError!bool {
        if (function.signature.parameter_count > 128) return true;
        var bytes: u64 = 0;
        for (function.scope.locals[0..function.signature.parameter_count]) |local| bytes = try addFrame(bytes, try self.parameterStackBytes(local));
        return bytes > 4096;
    }
    fn packedCallback(self: *Emitter, signature: typed.Callable) GenerateError!bool {
        if (signature.parameters.len > 128) return true;
        var bytes: u64 = 0;
        for (signature.parameters) |ty| bytes = try addFrame(bytes, try self.valueStackBytes(ty));
        return bytes > 4096;
    }
    /// Read one packed ABI parameter immediately before snapshotting its local value.
    pub fn unpackArgument(self: *Emitter, i: usize) GenerateError!void {
        const pointer = self.temp();
        try self.print(" %v{d} =l add %packed, {d}\n %a{d} =l loadl %v{d}\n", .{ pointer, i * 8, i, pointer });
    }
    fn packArgument(self: *Emitter, i: usize, value: usize) GenerateError!void {
        const pointer = self.temp();
        try self.print(" %v{d} =l add %arguments, {d}\n storel %v{d}, %v{d}\n", .{ pointer, i * 8, value, pointer });
    }
    fn argumentVectorBytes(self: *Emitter) GenerateError!u64 {
        var count: usize = 0;
        for (self.function.scope.instructions) |instruction| {
            const target: ?typed.FunctionId = switch (instruction.op) {
                .call => |id| id,
                else => null,
            };
            if (target) |id| {
                const f = self.program.functions[@backingInt(id)];
                if (try self.packedParameters(f)) count = @max(count, f.signature.parameter_count);
            }
            if (instruction.op == .invoke) {
                const sig = self.program.records[instruction.op.invoke.recordIndex()].contract.callback.?;
                if (try self.packedCallback(sig)) count = @max(count, sig.parameters.len);
            }
        }
        return @max(8, @as(u64, count) * 8);
    }
    fn resultStackBytes(self: *Emitter, function: bytecode.Function) GenerateError!u64 {
        return self.valueStackBytes(function.signature.return_type);
    }
    fn abiStackBytes(self: *Emitter) GenerateError!u64 {
        // Bounded scalar spill reserve plus exact native argument and result copies.
        var incoming: u64 = 4096;
        if (try self.packedParameters(self.function)) {
            incoming += 8;
        } else {
            for (self.function.scope.locals[0..self.function.signature.parameter_count]) |local| incoming = try addFrame(incoming, try self.parameterStackBytes(local));
        }
        incoming = try addFrame(incoming, (try self.resultStackBytes(self.function)) * 2);
        var outgoing: u64 = 0;
        for (self.function.scope.instructions) |instruction| {
            var bytes: u64 = 0;
            const target: ?typed.FunctionId = switch (instruction.op) {
                .call => |id| id,
                else => null,
            };
            if (target) |id| {
                const function = self.program.functions[@backingInt(id)];
                if (try self.packedParameters(function)) {
                    bytes = 8;
                } else {
                    for (function.scope.locals[0..function.signature.parameter_count]) |local| bytes = try addFrame(bytes, try self.parameterStackBytes(local));
                }
                bytes = try addFrame(bytes, try self.resultStackBytes(function));
            }
            if (instruction.op == .invoke) {
                const signature = self.program.records[instruction.op.invoke.recordIndex()].contract.callback.?;
                if (try self.packedCallback(signature)) {
                    bytes = 8;
                } else {
                    for (signature.parameters) |ty| bytes = try addFrame(bytes, try self.valueStackBytes(ty));
                }
                bytes = try addFrame(bytes, if (try self.largeValue(signature.return_type)) 8 else (try self.layout(signature.return_type)).size);
            }
            outgoing = @max(outgoing, bytes);
        }
        return addFrame(incoming, outgoing);
    }
    /// Clear a traced local slot whose value has just been released, so a root
    /// push can never trace a stale reference. A one-word slot is cleared with a
    /// store, which keeps it promotable; an aggregate keeps the `memset`, since
    /// the address it takes is one the aggregate's own blits need anyway.
    pub fn zeroTracedLocal(self: *Emitter, index: usize, ty: typed.Type) GenerateError!void {
        const value = try self.layout(ty);
        if (scalar(ty, self.program.records)) return self.print(" storel 0, %l{d}\n", .{index});
        try self.print(zero_local, .{ index, @max(8, value.size) });
    }
    fn usesTemporary(self: *Emitter, pc: usize) bool {
        return switch (self.function.scope.instructions[pc].op) {
            .make_record,
            .make_variant,
            .get_field,
            .update_record,
            .replace_index,
            .get_index,
            .arena_escape,
            .try_result,
            .acquire_buffer,
            .buffer_operation,
            .external_read,
            .environment_get,
            .acquire_resource,
            .complete_resource,
            .resource_io,
            .file_access,
            => true,
            .load_local, .move_local => |slot| !self.isScalar(self.function.scope.locals[@backingInt(slot)].ty),
            .call => |id| self.largeResult(self.program.functions[@backingInt(id)]) catch false,
            .invoke => |ty| self.largeValue(self.program.records[ty.recordIndex()].contract.callback.?.return_type) catch false,
            else => false,
        };
    }
    fn temporarySize(self: *Emitter, pc: usize) GenerateError!u64 {
        var size: u64 = 8;
        const op = self.function.scope.instructions[pc].op;
        if (op == .try_result) size = @max(size, (try self.layout(op.try_result.output)).size);
        if (self.states[pc]) |stack| for (stack) |ty| {
            size = @max(size, (try self.layout(ty)).size);
        };
        if (pc + 1 < self.states.len) if (self.states[pc + 1]) |stack| {
            for (stack) |ty| size = @max(size, (try self.layout(ty)).size);
        };
        return size;
    }
    /// The bytes local `index` occupies in the frame: one word when the slot
    /// holds an address (QBE-AGGREF-1, QBE-MATCHPROJ-1), the value's own size
    /// when it holds the value.
    fn localSlotBytes(self: *Emitter, index: usize, ty: typed.Type) GenerateError!u64 {
        if (self.byReference(index)) return 8;
        return @max(8, (try self.layout(ty)).size);
    }
    /// The zero-filled buffer a borrowed local's slot points at until the store
    /// that gives it its real address runs, or zero when it needs none.
    ///
    /// A root push reads every traced local's slot, including at a safepoint
    /// that runs before the store — the very case the per-local zero-fill was
    /// written for. A slot that holds an address must therefore always name a
    /// traceable value of the local's type, so it starts out naming an all-zero
    /// one, which has no reference for the collector to follow. Only a local
    /// this frame fills itself needs it: a parameter's address arrives before
    /// any instruction runs, and a local whose type traces nothing is never
    /// read by a root push.
    fn placeholderBytes(self: *Emitter, index: usize, ty: typed.Type) GenerateError!u64 {
        if (!self.byReference(index) or self.borrowsElement(index)) return 0;
        if (index < self.function.signature.parameter_count) return 0;
        const value = try self.layout(ty);
        if (!value.trace) return 0;
        return @max(8, value.size);
    }
    /// The stack bytes one outgoing argument of this type can occupy: one word
    /// for a value that crosses as a scalar or as an address, the value's own
    /// size only for a move-only aggregate that still crosses by value. The
    /// crossing answer is `qbe_wire.byAddress`, the one `argumentType` reads,
    /// so the estimate and the call can never disagree.
    fn argumentBytes(self: *Emitter, ty: typed.Type) GenerateError!u64 {
        const value = try self.layout(ty);
        if (self.isScalar(ty) or qbe_wire.byAddress(value, ty, self.program.records)) return 8;
        return @max(8, value.size);
    }
    /// Every per-pc aggregate scratch pair the lowering might declare, each at
    /// the widest operand its instruction can see: the bound `frameBytes` has
    /// to use before the body exists, and the size a heap frame is given.
    fn possibleTemporaryBytes(self: *Emitter) GenerateError!u64 {
        var size: u64 = 0;
        for (self.states, 0..) |state, pc| if (state != null and self.usesTemporary(pc)) {
            const temporary = try self.temporarySize(pc);
            size = try addFrame(size, temporary);
            size = try addFrame(size, temporary);
        };
        return size;
    }
    /// The per-pc aggregate scratch a lowered body still declares, summed from
    /// the `%agg{pc}` and `%aux{pc}` declarations that survived forwarding, the
    /// borrow rule and `dropUnusedSlots`: what the frame really carries.
    fn declaredTemporaryBytes(text: []const u8) GenerateError!u64 {
        var size: u64 = 0;
        var scan = std.mem.splitScalar(u8, text, '\n');
        while (scan.next()) |line| {
            const name = slotDefinition(line) orelse continue;
            if (!isTemporarySlot(name)) continue;
            const marker = " =l alloc8 ";
            const at = std.mem.indexOf(u8, line, marker) orelse continue;
            const bytes = std.fmt.parseInt(u64, line[at + marker.len ..], 10) catch return error.InternalError;
            size = try addFrame(size, bytes);
        }
        return size;
    }
    /// Whether a slot name is one pc's aggregate scratch: `agg` or `aux`
    /// followed by the pc.
    fn isTemporarySlot(name: []const u8) bool {
        if (name.len < 4) return false;
        if (!std.mem.eql(u8, name[0..3], "agg") and !std.mem.eql(u8, name[0..3], "aux")) return false;
        for (name[3..]) |byte| if (!std.ascii.isDigit(byte)) return false;
        return true;
    }
    /// The frame this function needs with `temporaries` bytes of per-pc
    /// aggregate scratch: every local, operand and root slot, the return and
    /// argument storage and the widest outgoing argument list, doubled to
    /// cover the spills QBE adds. On the native stack it must stay within
    /// `native_frame_limit`; a heap frame is allocated at exactly this size.
    fn frameBytes(self: *Emitter, capacity: usize, temporaries: u64) GenerateError!u64 {
        var size: u64 = (try self.argumentVectorBytes()) + 64 + @as(u64, capacity) * 8;
        for (self.function.scope.locals, 0..) |local, i| {
            size = try addFrame(size, try self.localSlotBytes(i, local.ty));
            size = try addFrame(size, try self.placeholderBytes(i, local.ty));
        }
        size = try addFrame(size, temporaries);
        if (self.has_roots) size = try addFrame(size, @as(u64, self.function.scope.locals.len + capacity) * 32);
        // A result that crosses through the caller's storage occupies nothing
        // here; any other aggregate result has its zeroed copy and, in a heap
        // frame, the copy the return path hands back.
        size = try addFrame(size, @max(16, (try self.returnStorageBytes()) * 2));
        var outgoing: u64 = 0;
        for (self.function.scope.instructions) |instruction| {
            const target: ?typed.FunctionId = switch (instruction.op) {
                .call => |id| id,
                else => null,
            };
            if (instruction.op == .invoke) {
                const signature = self.program.records[instruction.op.invoke.recordIndex()].contract.callback.?;
                var arguments: u64 = 0;
                for (signature.parameters) |ty| arguments = try addFrame(arguments, try self.argumentBytes(ty));
                outgoing = @max(outgoing, arguments);
            }
            if (target) |id| {
                const callee = self.program.functions[@backingInt(id)];
                var arguments: u64 = 0;
                for (callee.scope.locals[0..callee.signature.parameter_count]) |local| arguments = try addFrame(arguments, try self.argumentBytes(local.ty));
                outgoing = @max(outgoing, arguments);
            }
        }
        return std.math.mul(u64, try addFrame(size, outgoing), 2) catch error.InternalError;
    }
    fn addFrame(left: u64, right: u64) GenerateError!u64 {
        const aligned = std.math.add(u64, right, 7) catch return error.InternalError;
        return std.math.add(u64, left, aligned & ~@as(u64, 7)) catch error.InternalError;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn layout(self: *Emitter, ty: typed.Type) GenerateError!native_types.Layout {
        return self.layouts.layout(ty) catch |err| return layoutError(err);
    }
    /// Whether the native value is represented in one scalar register.
    pub fn isScalar(self: *Emitter, ty: typed.Type) bool {
        return scalar(ty, self.program.records);
    }
    fn supported(self: *Emitter, ty: typed.Type) GenerateError!bool {
        if (ty.isAggregate() and self.program.records[ty.recordIndex()].managed) return true;
        if (scalar(ty, self.program.records)) return true;
        const value = try self.layout(ty);
        return value.kind == .record or value.kind == .array or value.kind == .variant or value.kind == .domain;
    }
    /// Shared ABI lowering for guest and trusted host wrappers.
    pub fn abiType(self: *Emitter, ty: typed.Type) GenerateError![]const u8 {
        if (scalar(ty, self.program.records)) return "l";
        return std.fmt.allocPrint(self.allocator, ":t{s}", .{std.fmt.bytesToHex((try self.layout(ty)).hash, .lower)});
    }
    /// Large native values cross function boundaries through caller-owned storage.
    pub fn largeValue(self: *Emitter, ty: typed.Type) GenerateError!bool {
        return !self.isScalar(ty) and (try self.layout(ty)).size > 4096;
    }
    /// Large native values cross function boundaries through caller-owned storage.
    pub fn largeResult(self: *Emitter, function: bytecode.Function) GenerateError!bool {
        return self.largeValue(function.signature.return_type);
    }
    /// Shared ABI lowering for guest and trusted host wrappers.
    pub fn parameterType(self: *Emitter, local: typed.Local) GenerateError![]const u8 {
        return self.argumentType(local.ty);
    }
    /// The ABI type one value argument of this type crosses a call boundary as.
    /// QBE-AGGREF-1: an unmanaged aggregate crosses as the address of its
    /// storage. The callee either copies it into a private slot (a written
    /// parameter) or reads through it (a read-only one), so the argument copy
    /// the by-value boundary made on both sides is gone. A move-only aggregate
    /// keeps the by-value boundary and its single owner.
    ///
    /// A callback's parameters are the same boundary a direct call uses, so the
    /// two spell it from the type alone and can never disagree.
    pub fn argumentType(self: *Emitter, ty: typed.Type) GenerateError![]const u8 {
        // One decision, read here and recorded in the copied-value manifest, so
        // the generated adapter can never spell the crossing rule a second time.
        if (qbe_wire.byAddress(try self.layout(ty), ty, self.program.records)) return "l";
        return self.abiType(ty);
    }
    /// Shared ABI lowering for guest and trusted host wrappers.
    pub fn returnType(self: *Emitter, function: bytecode.Function) GenerateError![]const u8 {
        return if (try self.largeValue(function.signature.return_type)) "l" else self.abiType(function.signature.return_type);
    }
    /// Shared ABI lowering for guest and trusted host wrappers.
    pub fn typeDefinitions(self: *Emitter) GenerateError!void {
        try self.print("type :myl_slice = {{ l, l }}\n", .{});
        var seen: std.AutoHashMapUnmanaged(typed.Type, void) = .empty;
        defer seen.deinit(self.allocator);
        try seen.put(self.allocator, self.function.signature.return_type, {});
        for (self.function.scope.locals) |local| try seen.put(self.allocator, local.ty, {});
        for (self.states) |state| if (state) |stack| {
            for (stack) |ty| try seen.put(self.allocator, ty, {});
        };
        // Iterate sorted stable names so catalog insertion order never affects bytes.
        var names: std.ArrayList([]const u8) = .empty;
        var it = seen.keyIterator();
        while (it.next()) |ty| if (!scalar(ty.*, self.program.records)) {
            const value = try self.layout(ty.*);
            try names.append(self.allocator, try std.fmt.allocPrint(self.allocator, "type {s} = align {d} {{ b {d} }}\n", .{ try self.abiType(ty.*), value.alignment, @max(1, value.size) }));
        };
        std.mem.sort([]const u8, names.items, {}, struct {
            fn less(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.less);
        for (names.items) |line| try self.print("{s}", .{line});
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn descriptor(self: *Emitter, ty: typed.Type) GenerateError![]const u8 {
        return native_descriptors.symbol(self.allocator, self.layouts, ty) catch |err| return layoutError(err);
    }
    /// Lower one operation into `scratch` and return its text, leaving the main
    /// output alone so the caller can decide whether to emit root pushes first.
    fn lowerDetached(self: *Emitter, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) GenerateError![]const u8 {
        const main = self.output;
        self.scratch.writer.end = 0;
        self.output = self.scratch;
        defer {
            self.scratch = self.output;
            self.output = main;
        }
        try self.emitOp(op, stack);
        return self.output.writer.buffer[0..self.output.writer.end];
    }
    /// Whether this safepoint has at least one live traced local or operand.
    /// With none there is nothing to link, and the push and its restore are
    /// omitted, exactly as the former per-root call sequence omitted them.
    fn liveRoots(self: *Emitter, stack: []const typed.Type) GenerateError!bool {
        for (self.function.scope.locals, 0..) |local, i| if (try self.publishedRoot(i, local.ty)) return true;
        for (stack) |ty| if ((try self.layout(ty)).trace) return true;
        return false;
    }
    /// Whether local `index` is one the root protocol reads. A borrowed element
    /// is not: no collection can run while its borrow is live, and once the
    /// borrow is dead the address it holds could name storage the receiver has
    /// since reallocated or the sweep has freed.
    fn tracedRoot(self: *Emitter, index: usize, ty: typed.Type) GenerateError!bool {
        if (self.borrowsElement(index)) return false;
        return (try self.layout(ty)).trace;
    }
    /// Whether a safepoint at the current instruction publishes local `index`:
    /// the root protocol reads it and its value is live there
    /// (`QBE-ROOTLIVE-1`). A dead local's value is never read again, so a
    /// collection that frees what only it named frees garbage.
    fn publishedRoot(self: *Emitter, index: usize, ty: typed.Type) GenerateError!bool {
        if (!try self.tracedRoot(index, ty)) return false;
        const live = self.live_roots orelse return true;
        return live.has(self.pc, index);
    }
    /// Answer which locals each safepoint publishes. A local whose type owns
    /// something is pinned: the epilogue and every overwriting store release it
    /// through its slot, so it stays published wherever it was before.
    fn rootLiveness(self: *Emitter) GenerateError!liveness.Roots {
        const locals = self.function.scope.locals;
        const pinned = try self.allocator.alloc(bool, locals.len);
        defer self.allocator.free(pinned);
        for (locals, pinned) |local, *pin| pin.* = (try self.layout(local.ty)).drop;
        return liveness.analyze(self.allocator, .{ .function = self.function, .states = self.states, .pinned = pinned });
    }
    /// Whether this function keeps the root protocol at all: it has a live
    /// traced local or operand and at least one instruction that can collect.
    /// A lowering that roots only its allocating branch asks first, because
    /// without the protocol there is no `%root_mark` or root slot to link.
    pub fn needsRootProtocol(self: *Emitter) bool {
        return self.has_roots and self.has_safepoints;
    }
    /// Push every live traced local and operand as a `myl_native_root` link
    /// built from straight-line stores instead of a runtime call. The chain
    /// head is loaded once from the frozen `myl_native_heap.roots` offset, and
    /// each slot's `previous` names the link pushed before it, so the collector
    /// walks every live root. Field order matches `struct myl_native_root`.
    /// Returns whether any root was pushed.
    pub fn roots(self: *Emitter, stack: []const typed.Type) GenerateError!bool {
        if (!try self.liveRoots(stack)) return false;
        const base = self.temp();
        try self.print(" %v{d} =l add %heap, {d}\n", .{ base, heap_roots_offset });
        const head = self.temp();
        try self.print(" %v{d} =l loadl %v{d}\n", .{ head, base });
        var count: usize = 0;
        var previous = try std.fmt.allocPrint(self.allocator, "%v{d}", .{head});
        for (self.function.scope.locals, 0..) |local, i| if (try self.publishedRoot(i, local.ty)) {
            // A parameter read through the caller's address is traced where it
            // lives; every other aggregate local is traced at its own slot.
            const traced = if (self.byReference(i))
                try std.fmt.allocPrint(self.allocator, "%v{d}", .{try self.load("l", i)})
            else
                try std.fmt.allocPrint(self.allocator, "%l{d}", .{i});
            try self.pushRoot(.{ .index = count, .source = traced, .copy = scalar(local.ty, self.program.records), .descriptor = try self.descriptor(local.ty) }, previous, base);
            previous = try std.fmt.allocPrint(self.allocator, "%root{d}", .{count});
            count += 1;
        };
        for (stack, 0..) |ty, i| if ((try self.layout(ty)).trace) {
            const by_value = scalar(ty, self.program.records);
            const traced = if (by_value)
                try std.fmt.allocPrint(self.allocator, "%s{d}", .{i})
            else
                try std.fmt.allocPrint(self.allocator, "%v{d}", .{try self.load("s", i)});
            try self.pushRoot(.{ .index = count, .source = traced, .copy = by_value, .descriptor = try self.descriptor(ty) }, previous, base);
            previous = try std.fmt.allocPrint(self.allocator, "%root{d}", .{count});
            count += 1;
        };
        return true;
    }
    /// Fill one `myl_native_root` slot in place — `previous`, the traced
    /// address, the type descriptor, then the value word — and link it into the
    /// heap's chain through `base`, the address of `myl_native_heap.roots`. A
    /// scalar root is copied into the record's fourth word and the traced
    /// address points at that copy, so the slot it came from is only ever read;
    /// an aggregate root is already an address and is traced where it lives.
    fn pushRoot(self: *Emitter, slot: RootSlot, previous: []const u8, base: usize) GenerateError!void {
        const at = self.temp();
        const ty = self.temp();
        try self.print(" storel {s}, %root{d}\n %v{d} =l add %root{d}, 8\n", .{ previous, slot.index, at, slot.index });
        if (slot.copy) {
            const value = self.temp();
            const held = self.temp();
            try self.print(
                " %v{d} =l loadl {s}\n %v{d} =l add %root{d}, 24\n storel %v{d}, %v{d}\n storel %v{d}, %v{d}\n",
                .{ value, slot.source, held, slot.index, value, held, held, at },
            );
        } else try self.print(" storel {s}, %v{d}\n", .{ slot.source, at });
        try self.print(
            " %v{d} =l add %root{d}, 16\n storel extern ${s}, %v{d}\n storel %root{d}, %v{d}\n",
            .{ ty, slot.index, slot.descriptor, ty, slot.index, base },
        );
    }
    /// Restore the heap's root chain to this frame's mark with one store,
    /// replacing the former `myl_qbe_root_restore` call.
    pub fn restoreRoots(self: *Emitter) GenerateError!void {
        const base = self.temp();
        try self.print(" %v{d} =l add %heap, {d}\n storel %root_mark, %v{d}\n", .{ base, heap_roots_offset, base });
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn require(self: *Emitter, value: usize, failure: []const u8) GenerateError!void {
        const label = self.temp();
        try self.print(" jnz %v{d}, @success{d}, @failed{d}\n@failed{d}\n call ${s}(l %ctx)\n jmp @failure\n@success{d}\n", .{ value, label, label, label, failure, label });
    }
    fn step(self: *Emitter) GenerateError!void {
        const used = self.temp();
        const maximum = self.temp();
        const exhausted = self.temp();
        const next = self.temp();
        try self.print(" %v{d} =l loadl %ctx\n %v{d} =l loadl %maxsteps\n", .{ used, maximum });
        try self.print(" %v{d} =l ceql %v{d}, %v{d}\n jnz %v{d}, @step_limit, @step{d}\n@step{d}\n", .{ exhausted, used, maximum, exhausted, next, next });
        try self.print(" %v{d} =l add %v{d}, 1\n storel %v{d}, %ctx\n", .{ next, used, next });
    }
    /// Whether a sticky `ctx->trap` test belongs after this instruction's body.
    /// The fast protocol (no step and no frame accounting) omits the accounting
    /// that can fail without trapping, so every failure reaches the runtime
    /// directly through the fail helper's non-local exit; the test is dead there.
    fn stickyFlagTest(self: *Emitter) bool {
        return self.frame_checks or self.step_checks;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn checkFailure(self: *Emitter, target: []const u8) GenerateError!void {
        if (!self.stickyFlagTest()) return;
        const failed = self.temp();
        try self.print(" %v{d} =l loadl %trap\n jnz %v{d}, @{s}, @ok{d}\n@ok{d}\n", .{ failed, failed, target, failed, failed });
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn address(self: *Emitter, base: usize, offset: u64) GenerateError!usize {
        const result = self.temp();
        try self.print(" %v{d} =l add %v{d}, {d}\n", .{ result, base, offset });
        return result;
    }
    /// Record that `%v{value}` addresses memory outside this function's stack
    /// frame: a managed object header, or the element storage its header names.
    /// Both come from the managed heap, so neither can be one of this frame's
    /// `alloc*` slots, and the LLVM adapter turns that into scoped alias
    /// metadata that lets a loop keep a container header in registers. QBE's
    /// lexer drops `#` to end of line, so its assembly is byte-identical with
    /// or without the marker. See `docs/tooling/native-build.md`.
    pub fn markObject(self: *Emitter, value: usize) GenerateError!void {
        try self.print(" # myl-obj %v{d}\n", .{value});
    }
    /// Store one variant case tag at the start of a record pointer.
    pub fn writeTag(self: *Emitter, tag: usize, pointer: usize) GenerateError!void {
        try self.print(" storew {d}, %v{d}\n", .{ tag, pointer });
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn readValue(self: *Emitter, pointer: usize, ty: typed.Type) GenerateError!usize {
        if (!scalar(ty, self.program.records)) return pointer;
        const result = self.temp();
        var backing = ty;
        while (backing.isAggregate()) {
            const record = self.program.records[backing.recordIndex()];
            if (record.managed or record.contract.callback != null or ownedPointer(record)) {
                backing = .u64;
                break;
            }
            backing = record.shape.domain.?;
        }
        const load_op: []const u8 = if (backing.integer()) |info| switch (info.bits) {
            8 => if (info.signed) "loadsb" else "loadub",
            16 => if (info.signed) "loadsh" else "loaduh",
            32 => if (info.signed) "loadsw" else "loaduw",
            else => "loadl",
        } else if (backing == .bool) "loadub" else "loadl";
        if (backing == .unit) try self.print(" %v{d} =l copy 0\n", .{result}) else try self.print(" %v{d} =l {s} %v{d}\n", .{ result, load_op, pointer });
        return result;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn writeValue(self: *Emitter, pointer: usize, value: usize, ty: typed.Type) GenerateError!void {
        const size = (try self.layout(ty)).size;
        if (size == 0) return;
        if (!scalar(ty, self.program.records)) {
            try self.print(" blit %v{d}, %v{d}, {d}\n", .{ value, pointer, size });
            return;
        }
        const op: []const u8 = switch (size) {
            1 => "storeb",
            2 => "storeh",
            4 => "storew",
            else => "storel",
        };
        try self.print(" {s} %v{d}, %v{d}\n", .{ op, value, pointer });
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn aggregatePointer(self: *Emitter) GenerateError!usize {
        const pointer = self.temp();
        try self.print(" %v{d} =l copy %agg{d}\n", .{ pointer, self.pc });
        return pointer;
    }
    /// Resolve a field to its native offset and exact type.
    pub fn field(self: *Emitter, ty: typed.Type, index: usize) GenerateError!native_types.Field {
        if (self.program.records[ty.recordIndex()].isManagedRecord()) {
            const body = self.layouts.heapLayout(ty) catch |err| return layoutError(err);
            defer self.layouts.releaseLayout(body);
            return body.fields[index];
        }
        const value = try self.layout(ty);
        if (value.kind == .array) return .{ .offset = value.stride * index, .ty = value.fields[0].ty };
        return value.fields[index];
    }
    fn enumComparison(self: *Emitter, predicate_value: bytecode.Equality, height: usize) GenerateError!void {
        const right = try self.load("s", height - 1);
        const left = try self.load("s", height - 2);
        const a = self.temp();
        const b = self.temp();
        const result = self.temp();
        try self.print(" %v{d} =l loaduw %v{d}\n %v{d} =l loaduw %v{d}\n", .{ a, left, b, right });
        try self.print(" %v{d} =l {s} %v{d}, %v{d}\n", .{ result, if (predicate_value == .eq) "ceql" else "cnel", a, b });
        try self.store(height - 2, result);
    }
    fn invoke(self: *Emitter, callback_type: typed.Type, stack: []const typed.Type) GenerateError!void {
        const h = stack.len;
        const signature = self.program.records[callback_type.recordIndex()].contract.callback.?;
        const base = h - signature.valueCount() - 1;
        const function_pointer = try self.load("s", base);
        const args = try self.allocator.alloc(usize, signature.parameters.len);
        const packed_args = try self.packedCallback(signature);
        for (args, 0..) |*arg, i| {
            arg.* = try self.load("s", base + 1 + i);
            if (packed_args) try self.packArgument(i, arg.*);
        }
        const value = self.temp();
        const indirect = try self.largeValue(signature.return_type);
        try self.print(" %v{d} ={s} call %v{d}(l %ctx", .{ value, if (indirect) "l" else try self.abiType(signature.return_type), function_pointer });
        if (indirect) try self.print(", l %aux{d}", .{self.pc});
        if (packed_args) {
            try self.print(", l %arguments", .{});
        } else {
            for (args, signature.parameters) |arg, ty| try self.print(", {s} %v{d}", .{ try self.argumentType(ty), arg });
        }
        try self.print(")\n", .{});
        if (indirect) try self.print(" storel %aux{d}, %s{d}\n", .{ self.pc, base }) else try self.store(base, value);
    }
    fn acquireBuffer(self: *Emitter, ty: typed.Type, stack: []const typed.Type) GenerateError!void {
        const h = stack.len;
        const schema = self.program.records[ty.recordIndex()];
        if (!schema.managed or schema.collection.kind != .list) return self.reject(self.pc);
        const capacity = try self.load("s", h - 1);
        if (stack[h - 1].integer().?.signed) {
            const valid = self.temp();
            try self.print(" %v{d} =l csgel %v{d}, 0\n", .{ valid, capacity });
            try self.require(valid, "myl_qbe_fail_list_capacity");
        }
        const value = self.temp();
        try self.print(" %v{d} =l call $myl_native_list_new(l %heap, l extern ${s}, l %v{d})\n", .{ value, try self.descriptor(schema.shape.buffer.?), capacity });
        try self.require(value, "myl_qbe_fail_allocation");
        try self.store(h - 1, value);
    }
    fn emitCall(self: *Emitter, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) GenerateError!void {
        const h = stack.len;
        const target = op.call;
        const callee = self.program.functions[@backingInt(target)];
        const count = bytecode.valueParameterCount(callee);
        const args = try self.allocator.alloc(usize, callee.signature.parameter_count);
        const packed_args = try self.packedParameters(callee);
        for (args, 0..) |*arg, i| {
            arg.* = try self.load("s", h - count + i);
            if (packed_args) try self.packArgument(i, arg.*);
        }
        const v = self.temp();
        try self.print(" %v{d} ={s} call ${s}(l %ctx", .{ v, try self.returnType(callee), self.units[@backingInt(target)].symbol });
        const indirect = try self.largeResult(callee);
        if (indirect) try self.print(", l %aux{d}", .{self.pc});
        if (packed_args) {
            try self.print(", l %arguments", .{});
        } else {
            for (args, callee.scope.locals[0..callee.signature.parameter_count]) |arg, local| try self.print(", {s} %v{d}", .{ try self.parameterType(local), arg });
        }
        try self.print(")\n", .{});
        if (indirect) try self.print(" storel %aux{d}, %s{d}\n", .{ self.pc, h - count }) else try self.store(h - count, v);
    }
    fn emitOp(self: *Emitter, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) GenerateError!void {
        const h = stack.len;
        switch (op) {
            .acquire_resource, .complete_resource, .resource_io, .restrict_resource, .dir_resource, .host_resource => try @import("qbe_resources.zig").Lower(Emitter).emit(self, op, stack),
            .external_read, .environment_get, .environment_only, .environment_names => try @import("qbe_boundaries.zig").emit(self, op, stack),
            .begin_arena, .end_arena, .arena_escape => try arena_lower.Lower(Emitter).emit(self, op, stack),
            .print => |output| try @import("qbe_io.zig").Lower(Emitter).emit(self, output, stack),
            .stream_write => |write| try @import("qbe_io.zig").Lower(Emitter).write(self, write, stack),
            .file_access => |call| try @import("qbe_files.zig").Lower(Emitter).access(self, call, stack),
            .file_method => |call| try @import("qbe_files.zig").Lower(Emitter).method(self, call, stack),
            .try_result => |propagate| {
                const source = try self.load("s", h - 1);
                const input_offset = (try self.layout(propagate.input)).payload_offset;
                if (typed.resultShape(propagate.input, self.program.records)) |input| {
                    const output = typed.resultShape(propagate.output, self.program.records).?;
                    const tag = self.temp();
                    const success = self.temp();
                    try self.print(" %v{d} =l loaduw %v{d}\n %v{d} =l ceql %v{d}, {d}\n", .{ tag, source, success, tag, input.ok_tag });
                    try self.print(" jnz %v{d}, @tryok{d}, @tryerror{d}\n@tryerror{d}\n", .{ success, tag, tag, tag });
                    const pointer = try self.aggregatePointer();
                    try self.writeTag(output.error_tag, pointer);
                    const slot = try self.address(pointer, (try self.layout(propagate.output)).payload_offset);
                    const payload = try self.readValue(try self.address(source, input_offset), input.error_type);
                    if (input.error_type == output.error_type) {
                        try self.writeValue(slot, payload, input.error_type);
                    } else {
                        // The error type is a case payload of the enclosing error union, so
                        // wrap the whole incoming error value in that case.
                        const error_tag = typed.wrappingCase(self.program.records, output.error_type, input.error_type) orelse return error.InternalError;
                        try self.writeTag(error_tag, slot);
                        try self.writeValue(try self.address(slot, (try self.layout(output.error_type)).payload_offset), payload, input.error_type);
                    }
                    for (stack[0 .. h - 1], 0..) |ty, slot_index| try self.dropOperand(slot_index, ty);
                    try self.store(0, pointer);
                    try self.print(" jmp @i{d}\n@tryok{d}\n", .{ propagate.error_target, tag });
                    try self.store(h - 1, try self.readValue(try self.address(source, input_offset), input.ok_type));
                } else if (prelude.optionShape(propagate.input, self.program.records)) |input| {
                    const output = prelude.optionShape(propagate.output, self.program.records).?;
                    const tag = self.temp();
                    const success = self.temp();
                    try self.print(" %v{d} =l loaduw %v{d}\n %v{d} =l ceql %v{d}, {d}\n", .{ tag, source, success, tag, input.some });
                    try self.print(" jnz %v{d}, @tryok{d}, @tryerror{d}\n@tryerror{d}\n", .{ success, tag, tag, tag });
                    const pointer = try self.aggregatePointer();
                    try self.writeTag(output.none, pointer);
                    for (stack[0 .. h - 1], 0..) |ty, slot| try self.dropOperand(slot, ty);
                    try self.store(0, pointer);
                    try self.print(" jmp @i{d}\n@tryok{d}\n", .{ propagate.error_target, tag });
                    try self.store(h - 1, try self.readValue(try self.address(source, input_offset), input.element));
                } else return error.InternalError;
            },
            .function_value => |value| try self.print(" storel extern ${s}, %s{d}\n", .{ self.units[@backingInt(value.function)].symbol, h }),
            .invoke => |callback_type| try self.invoke(callback_type, stack),
            .acquire_buffer => |ty| try self.acquireBuffer(ty, stack),
            .buffer_operation => |operation| try managed_lower.Lower(Emitter).operation(self, operation, stack),
            .push_i64 => |v| try self.print(store_scalar, .{ v, h }),
            .push_integer => |v| try self.print(store_scalar, .{ v.value, h }),
            .push_bool => |v| try self.print(store_scalar, .{ @intFromBool(v), h }),
            .push_unit => try self.print(" storel 0, %s{d}\n", .{h}),
            .make_record, .get_field, .update_record, .array_length, .get_index, .replace_index, .make_variant, .switch_variant => try @import("qbe_aggregate.zig").emit(self, op, stack),
            .load_local, .move_local => |slot| {
                const index = @backingInt(slot);
                const ty = self.function.scope.locals[index].ty;
                try self.readLocal(index, h);
                if (op == .move_local and (try self.layout(ty)).drop) try self.zeroTracedLocal(index, ty);
            },
            .store_local => |slot| {
                const index = @backingInt(slot);
                const ty = self.function.scope.locals[index].ty;
                // QBE-ELEMENT-ADDRESS-1: an iteration local that names its
                // element in place holds the checked address the read produced,
                // so the store keeps that word instead of copying the element
                // into the frame and reading it back out of there.
                if (self.byReference(index)) {
                    try self.print(" storel %v{d}, %l{d}\n", .{ try self.load("s", h - 1), index });
                } else if (!try @import("qbe_aggregate.zig").storeForwarded(@TypeOf(self), self, self.pc, index)) {
                    // QBE-CTORFWD-1 and QBE-ARRAYWRITE-1: the instruction before
                    // this store already wrote this local where it lives — a
                    // constructor field by field, a `replace` one element — so
                    // there is nothing left to copy.
                    const v = try self.load("s", h - 1);
                    if ((try self.layout(ty)).drop) {
                        try self.print(drop_local, .{ try self.descriptor(ty), index });
                    }
                    if (scalar(ty, self.program.records)) try self.print(" storel %v{d}, %l{d}\n", .{ v, index }) else try self.print(" blit %v{d}, %l{d}, {d}\n", .{ v, index, (try self.layout(ty)).size });
                }
            },
            .drop_local => |slot| {
                const ty = self.function.scope.locals[@backingInt(slot)].ty;
                if ((try self.layout(ty)).drop) {
                    try self.print(drop_local, .{ try self.descriptor(ty), @backingInt(slot) });
                } else if ((try self.layout(ty)).trace) try self.zeroTracedLocal(@backingInt(slot), ty);
            },
            .pop, .acknowledge => try self.dropOperand(h - 1, stack[h - 1]),
            .wrap_domain, .unwrap_domain => {},
            .jump => |target| try self.print(" jmp @i{d}\n", .{target}),
            .assert_true => {
                const v = try self.load("s", h - 1);
                try self.require(v, "myl_qbe_fail_assert");
            },
            .jump_if_false => |target| {
                const v = try self.load("s", h - 1);
                try self.print(" jnz %v{d}, @next{d}, @i{d}\n", .{ v, self.serial, target });
            },
            .ret => {
                const v = try self.load("s", h - 1);
                try self.returnValue(v);
            },
            .call => try self.emitCall(op, stack),
            .binary_integer => |b| {
                if (b.ty.isAggregate()) return managed_lower.Lower(Emitter).binary(self, b, stack);
                try scalar_lower.Lower(Emitter).binary(self, b.op, b.ty, h);
            },
            .add_i64_checked => try scalar_lower.Lower(Emitter).binary(self, .add, .i64, h),
            .sub_i64_checked => try scalar_lower.Lower(Emitter).binary(self, .sub, .i64, h),
            .mul_i64_checked => try scalar_lower.Lower(Emitter).binary(self, .mul, .i64, h),
            .div_i64_checked => try scalar_lower.Lower(Emitter).binary(self, .div, .i64, h),
            .rem_i64_checked => try scalar_lower.Lower(Emitter).binary(self, .rem, .i64, h),
            .cmp_i64 => |p| try scalar_lower.Lower(Emitter).binary(self, predicate(p), .i64, h),
            .cmp_bool => |p| try scalar_lower.Lower(Emitter).binary(self, if (p == .eq) .eq else .ne, .u8, h),
            .cmp_enum => |comparison| try self.enumComparison(comparison.predicate, h),
            .cmp_domain => |comparison| try scalar_lower.Lower(Emitter).binary(self, if (comparison.predicate == .eq) .eq else .ne, .u64, h),
            .not_bool => {
                const operand = try self.load("s", h - 1);
                const v = self.temp();
                try self.print(" %v{d} =l xor %v{d}, 1\n", .{ v, operand });
                try self.store(h - 1, v);
            },
            .cast_integer, .neg_integer, .neg_i64_checked => {
                const ty: typed.Type = switch (op) {
                    .cast_integer, .neg_integer => |t| t,
                    else => .i64,
                };
                if (op == .cast_integer and ty.isAggregate()) return managed_lower.Lower(Emitter).cast(self, ty, stack);
                const info = ty.integer().?;
                if (op == .cast_integer) {
                    const from = stack[h - 1].integer() orelse return error.InternalError;
                    return scalar_lower.Lower(Emitter).cast(self, from, info, h);
                }
                return scalar_lower.Lower(Emitter).neg(self, info, h);
            },
            .unary_float => |unary| {
                const operand = try self.load("s", h - 1);
                const v = self.temp();
                try self.print(" %v{d} =l call $myl_qbe_float_unary(l %ctx, l {d}, l %v{d})\n", .{ v, @backingInt(unary), operand });
                try self.store(h - 1, v);
            },
        }
    }
};
fn predicate(p: bytecode.Predicate) typed.BinaryOp {
    return switch (p) {
        .eq => .eq,
        .ne => .ne,
        .lt => .lt,
        .le => .le,
        .gt => .gt,
        .ge => .ge,
    };
}

comptime {
    // These ordinals are the versioned C helper protocol, not native enum layout.
    const binary_names = .{
        "add",
        "sub",
        "mul",
        "div",
        "rem",
        "floor_div",
        "floor_rem",
        "logical_and",
        "logical_or",
        "eq",
        "ne",
        "lt",
        "le",
        "gt",
        "ge",
        "bit_and",
        "bit_or",
        "bit_xor",
        "shift_left",
        "shift_right",
        "wrapping_add",
        "wrapping_sub",
        "wrapping_mul",
        "saturating_add",
        "saturating_sub",
        "saturating_mul",
        "f64_add",
        "f64_sub",
        "f64_mul",
        "f64_div",
        "f64_eq",
        "f64_lt",
        "f64_le",
    };
    for (binary_names, 0..) |name, i| if (@backingInt(@field(typed.BinaryOp, name)) != i) @compileError("QBE runtime binary ABI changed");
    const unary_names = .{ "neg", "not", "f64_sqrt", "f64_floor", "f64_ceil", "f64_trunc", "f64_abs", "f64_neg", "f64_from_u64", "f64_to_u64", "f64_from_i64", "f64_to_i64" };
    for (unary_names, 0..) |name, i| if (@backingInt(@field(typed.UnaryOp, name)) != i) @compileError("QBE runtime unary ABI changed");
}
