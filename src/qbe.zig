//! Independent native QBE units. Source locations never enter native artifact bytes.
const zero_failure_result = " call $memset(l %empty, w 0, l {d})\n";
const slice_abi = ":myl_slice";
const scalar_lower = @import("qbe_scalar.zig");
const zero_local = @import("qbe_format.zig").zero_local;
const arena_lower = @import("qbe_arena.zig");
const borrow_lower = @import("qbe_borrow.zig");
const rc_borrow = @import("qbe_rc_borrow.zig");
const liveness = @import("qbe_liveness.zig");
const ownership = @import("ownership.zig");
const cow_lower = @import("qbe_cow.zig");
const value_semantics = @import("value_semantics.zig");
const runtime_mode = @import("runtime_mode.zig");
const rc_frame = @import("qbe_rc_frame.zig");
const moves_module = @import("qbe_moves.zig");
const range_keys = @import("qbe_range_keys.zig");
const loop_facts = @import("qbe_loop_facts.zig");
const loop_version = @import("qbe_loop_version.zig");
const managed_lower = @import("qbe_managed.zig");
const error_trace = @import("qbe_error_trace.zig");
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
const fragments = @import("qbe_fragments.zig");
const exports = @import("qbe_exports.zig");
/// Failures producing independent QBE native units.
pub const GenerateError = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const frame_module = @import("qbe_frame.zig");
const drop_local = frame_module.drop_local;
/// Headroom `qbe_stack.c` keeps between the frame floor and the guard page.
const frame_headroom: u64 = 65536;
/// The largest frame the native stack carries; a bigger one is heap-backed.
const native_frame_limit: u64 = 32768;
/// The `dbgloc` column that marks an entry guard's frame-failure call; defined
/// beside the entry guard in `qbe_frame.zig`.
pub const frame_map_guard_column = frame_module.frame_map_guard_column;
/// Where one function's frame lives: on the native stack, bounded by
/// `native_frame_limit`, or in a heap block of this many bytes that the
/// prologue allocates and every return path releases.
const Frame = union(enum) { native, heap: u64 };
const store_scalar = " storel {d}, %s{d}\n";
/// An unconditional jump to an instruction label: its prefix, then its pc.
const jump_label = " jmp @{s}{d}\n";
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
    @"export": ?exports.Export = null,
    /// Set when a lean manifest names this unit's stored text instead of
    /// carrying it: the text's digest, the lines the native build reads
    /// without compiling it and the digest of its stored metadata
    /// (`QBE-FRAGMENT-REUSE-1`, `EMIT-META-1`).
    stored: ?Stored = null,
    /// An executable build's manifest: no export or test-dependency facts.
    executable: bool = false,

    /// The manifest shape of one unit: its text and metadata inline, or, for a
    /// stored unit, `il_digest`, `il_facts` and `meta_digest` in their place.
    pub fn jsonStringify(self: Unit, jw: anytype) !void {
        try jw.beginObject();
        if (!self.executable) {
            try jw.objectField("test_dependencies");
            try jw.write(self.test_dependencies);
        }
        try jw.objectField("name");
        try jw.write(self.name);
        try jw.objectField("symbol");
        try jw.write(self.symbol);
        if (self.stored) |stored| {
            try jw.objectField("il_digest");
            try jw.write(stored.digest);
            try jw.objectField("il_facts");
            try jw.write(stored.facts);
            try jw.objectField("meta_digest");
            try jw.write(stored.meta);
            if (stored.record) |record| {
                try jw.objectField("meta");
                try jw.beginWriteRaw();
                try jw.writer.writeAll(record);
                jw.endWriteRaw();
            }
        } else {
            try jw.objectField("il");
            try jw.write(self.il);
            try jw.objectField("locations");
            try jw.write(self.locations);
            try jw.objectField("messages");
            try jw.write(self.messages);
            try jw.objectField("inlines");
            try jw.write(self.inlines);
        }
        if (!self.executable) {
            try jw.objectField("export");
            try jw.write(self.@"export");
        }
        try jw.endObject();
    }
};
/// A unit text kept in the fragment store: its hex digest and build facts,
/// the hex digest of its stored metadata once `metaPass` has named it, and
/// that record itself when this emission computed it.
const Stored = struct { digest: []const u8, facts: []const u8, meta: []const u8 = "", record: ?[]const u8 = null };

/// One unit's stored metadata (`EMIT-META-1`): its name, its positions and
/// assertion messages in the compact spelling (`BUILD-POSITIONS-1`) and its
/// inline frames — everything the build's function tables read besides the
/// unit's symbol.
const MetaRecord = struct {
    unit: Unit,
    /// The record as one JSON object.
    pub fn jsonStringify(self: MetaRecord, jw: *std.json.Stringify) std.json.Stringify.Error!void {
        try jw.beginObject();
        try jw.objectField("name");
        try jw.write(self.unit.name);
        try writeCompactPositions(self.unit, jw);
        try jw.objectField("inlines");
        try jw.write(self.unit.inlines);
        try jw.endObject();
    }
};

/// A lean unit's per-instruction positions and assertion messages
/// (`BUILD-POSITIONS-1`): `paths` lists each distinct source path once, in
/// first-use order; `positions` is one `path:line:column` entry per
/// instruction, space separated, `path` indexing `paths`; and `assertions`
/// pairs each instruction that has a message with that message. It carries
/// exactly what `locations` and `messages` do in a fifth of the bytes, and
/// the build reads it without allocating a JSON value per instruction.
fn writeCompactPositions(unit: Unit, jw: *std.json.Stringify) std.json.Stringify.Error!void {
    var paths: [compact_path_limit][]const u8 = undefined;
    var known: usize = 0;
    for (unit.locations) |location| {
        if (pathIndex(paths[0..known], location.path) != null) continue;
        if (known == paths.len) {
            // More source paths than the table holds: spell the unit out.
            try jw.objectField("locations");
            try jw.write(unit.locations);
            try jw.objectField("messages");
            return jw.write(unit.messages);
        }
        paths[known] = location.path;
        known += 1;
    }
    try jw.objectField("paths");
    try jw.write(paths[0..known]);
    try jw.objectField("positions");
    try jw.beginWriteRaw();
    try jw.writer.writeByte('"');
    for (unit.locations, 0..) |location, pc| {
        if (pc != 0) try jw.writer.writeByte(' ');
        try jw.writer.print("{d}:{d}:{d}", .{ pathIndex(paths[0..known], location.path).?, location.line, location.column });
    }
    try jw.writer.writeByte('"');
    jw.endWriteRaw();
    try jw.objectField("assertions");
    try jw.beginArray();
    for (unit.messages, 0..) |message, pc| {
        if (message.len == 0) continue;
        try jw.beginArray();
        try jw.write(pc);
        try jw.write(message);
        try jw.endArray();
    }
    try jw.endArray();
}
/// A unit's instructions come from its own module and from the modules of the
/// callees inlined into it; a unit with more distinct paths than this keeps the
/// spelled-out `locations` and `messages` instead.
const compact_path_limit = 256;
fn pathIndex(paths: []const []const u8, path: []const u8) ?usize {
    for (paths, 0..) |known, index| if (known.ptr == path.ptr and known.len == path.len or std.mem.eql(u8, known, path)) return index;
    return null;
}

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

fn generateImpl(allocator: std.mem.Allocator, program_in: bytecode.Program, src: Source, sink: *diagnostic.Sink, interface: native_interface.Interface, requested: ?[]const bool) GenerateError![]u8 {
    // ARENA-BOUNDED-1: a whole program's units and facts outgrow the standard
    // arena's half-again nodes (a 752 MB reservation, 21 MB touched, at a
    // million lines); this arena reserves at most one chunk ahead.
    var arena = @import("chunked_arena.zig").ChunkedArena.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // EMIT-STANDIN-1: a stand-in emission lowers more functions as it goes,
    // so it works on its own copy of the function table and its own selection.
    const standins: ?*fragments.Standins = if (interface.reuse) |configured| configured.standins else null;
    const selected: ?[]const bool = if (standins) |state| state.selected else requested;
    var program = program_in;
    if (standins != null) program.functions = try a.dupe(bytecode.Function, program_in.functions);
    var layouts = native_types.Catalog.initRecords(a, program.records) catch |err| return layoutError(err);
    defer layouts.deinit();
    const shape: Shape = if (interface.reuse) |configured| .{ .lean = configured.lean, .executable = configured.executable } else .{};
    const units = try a.alloc(Unit, program.functions.len);
    // An executable build reads no export facts, so it marks no roots.
    const exported = try exports.rootMask(a, program, if (shape.executable) &.{} else interface.roots);
    for (program.functions, units, 0..) |function, *unit, index| {
        const emit = selected == null or selected.?[index];
        unit.* = .{
            .name = function.name,
            .symbol = try symbol(a, function.name),
            .il = "",
            .locations = &.{},
            .messages = &.{},
            .inlines = &.{},
            .@"export" = if (emit) try exports.describeMarked(a, program, index, exported) else null,
            .executable = shape.executable,
        };
        // A lean unit's metadata is read from the store, or computed once
        // its key misses, by `metaPass` (EMIT-META-1).
        if (emit and !shape.lean) try fillPositions(a, program, src, index, unit);
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
        .backing = allocator,
        .program = program,
        .units = units,
        .states = states,
        .layouts = &layouts,
        .sink = sink,
        .arenas = arenas,
        .selected = selected,
        .step_checks = interface.policy.step_checks,
        .frame_checks = interface.policy.frame_checks,
        .pure = &.{},
        // COW-UNIQUE-1: the value-semantics switch enables the checks by
        // default; an explicit internal policy can request counting.
        .cow = if (interface.policy.cow != .off) interface.policy.cow else if (value_semantics.enabled()) .checks else .off,
    };
    var reuse: Reuse = try .init(a, pass, interface.reuse);
    try runPasses(&pass, &reuse, src, standins, shape.lean);
    const canonical = if (requested) |mask| try selectedUnits(a, units, mask) else units;
    const emitted = try appendBorrowedUnits(pass, src, canonical, requested);
    const entry_function = program.functions[@backingInt(program.main)];
    const entry_parameters = try a.alloc([]const u8, entry_function.signature.parameter_count);
    const entry_parameter_names = try a.alloc([]const u8, entry_function.signature.parameter_count);
    for (entry_parameters, entry_function.scope.locals[0..entry_parameters.len]) |*parameter, local| parameter.* = layouts.identity(local.ty) catch |err| return layoutError(err);
    for (entry_parameter_names, entry_function.scope.locals[0..entry_parameter_names.len]) |*name, local| name.* = local.name;
    const entry_argv_element = if (entry_function.signature.parameter_count != 0) entry_adapter.argvElement(entry_function.scope.locals[0].ty, program.records) else null;
    const entry_argv = if (entry_argv_element) |element| native_descriptors.symbol(a, &layouts, element) catch |err| return layoutError(err) else null;
    const descriptors = native_descriptors.generate(a, &layouts) catch |err| return layoutError(err);
    const owners = if (runtime_mode.enabled())
        @import("rc_descriptors.zig").generate(a, &layouts) catch |err| return layoutError(err)
    else
        "";
    const renderers = @import("native_render.zig").generate(a, &layouts, program, states) catch |err| return layoutError(err);
    // A program that neither prints nor renders a value into text carries no
    // renderers, and copies nothing.
    const runtime_data = if (renderers.len == 0 and owners.len == 0) descriptors else try std.mem.concat(a, u8, &.{ descriptors, renderers, owners });
    // Wire types and codecs serve only a library's embedding API.
    const wire_types = if (shape.executable) null else (qbe_wire.describe(a, &layouts) catch |err| return layoutError(err)).types;
    const codecs = if (shape.executable) null else @import("qbe_codecs.zig").describe(a, program, &layouts) catch |err| return layoutError(err);
    const text_format = textFormat(program, &reuse);
    const host = @import("qbe_host.zig").describe(a, program, &layouts) catch |err| return layoutError(err);
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
        .runtime_contract = runtime_mode.identity(),
        // Where a lean manifest's stored texts and metadata live, by digest.
        .store = if (shape.lean) try interface.reuse.?.store.textRoot() else null,
        .functions = emitted,
        .entry = if (requested == null) units[@backingInt(program.main)].symbol else "",
    }, .{});
}

/// Emit once with roots everywhere to learn which functions can allocate,
/// then again with the analysis in hand (a call to a function that cannot
/// collect needs no root push at its call site), then name each lean unit's
/// metadata. A stand-in emission (EMIT-STANDIN-1) first settles which
/// functions it must lower, and afterwards leaves their records.
fn runPasses(pass: *EmitPass, reuse: *Reuse, src: Source, standins: ?*fragments.Standins, lean: bool) GenerateError!void {
    const allocates = if (standins) |state| stood: {
        reuse.standin = try StandIn.init(pass.allocator, pass.program, state, src);
        if (runtime_mode.enabled()) {
            // RC certificates require every physical body, including transitive
            // immortal helpers. Stored semantic summaries are not certificates.
            @memset(state.selected, true);
            try state.lower.run(state.lower.context, state);
            try reinline(pass.*, &reuse.standin.?);
            try reuse.forget(pass.allocator, pass.program);
        }
        pass.arenas = arenasPresent(pass.program, reuse);
        break :stood try standInPasses(pass, reuse);
    } else plain: {
        const own = try firstPass(pass.*, reuse);
        pass.pure = try allocateAnalysis(pass.allocator, pass.program, own, reuse);
        break :plain own;
    };
    try secondPass(pass.*, reuse);
    if (lean) try metaPass(pass.*, reuse, src);
    if (reuse.standin != null) try recordStandIns(pass.*, reuse, allocates);
    if (reuse.configured) |configured| configured.store.flush();
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

/// Alternate entries have their own symbol and frame map; pass indices stay canonical.
fn appendBorrowedUnits(pass: EmitPass, src: Source, canonical: []const Unit, requested: ?[]const bool) GenerateError![]const Unit {
    if (!runtime_mode.enabled()) return canonical;
    const a = pass.allocator;
    var result: std.ArrayList(Unit) = .empty;
    try result.appendSlice(a, canonical);
    var catalog = try @import("rc_shape.zig").Catalog.init(a, pass.layouts);
    defer catalog.deinit();
    for (pass.program.functions, 0..) |function, index| {
        if (requested) |mask| if (!mask[index]) continue;
        const proof = (@import("rc_calls.zig").borrowedIn(a, &catalog, pass.program.functions, function, runtime_mode.identity()) catch |err| return layoutError(err)) orelse continue;
        const emitted = try emitEntry(pass, index, a, proof);
        var unit = pass.units[index];
        unit.symbol = try rc_borrow.symbol(a, unit.symbol);
        unit.il = emitted.text;
        unit.stored = null;
        unit.@"export" = null;
        try fillPositions(a, pass.program, src, index, &unit);
        try result.append(a, unit);
    }
    return result.toOwnedSlice(a);
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
    for (program.functions) |function| if (@import("invariant_callbacks.zig").isName(function.name)) {
        if (!selected[@backingInt(function.id)]) return error.InternalError;
    };
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
/// that also clears the source, an explicit drop, a match arm's payload
/// binding, which blits the payload into the arm's slot, or a `ref_local`,
/// which hands the slot's storage to a callee that writes through it.
fn writtenLocal(function: bytecode.Function, slot: usize) bool {
    for (function.scope.instructions) |instruction| switch (instruction.op) {
        .store_local, .move_local, .drop_local, .ref_local => |target| if (@backingInt(target) == slot) return true,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| if (arm.slot) |target| if (@backingInt(target) == slot) return true,
        else => {},
    };
    return false;
}

/// Whether the instruction at `pc` writes local `index`: a whole-value store, a
/// move, an explicit drop, a match arm's payload binding into it, or a
/// `ref_local` handing its storage to a callee that writes through it.
fn writesLocalAt(f: bytecode.Function, pc: usize, index: usize) bool {
    return switch (f.scope.instructions[pc].op) {
        .store_local, .move_local, .drop_local, .ref_local => |target| @backingInt(target) == index,
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
        .store_local, .move_local, .drop_local, .ref_local => |target| if (@backingInt(target) == slot) return true,
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

const il_passes = @import("qbe_il_passes.zig");
const stripUnreferencedLabels = il_passes.stripUnreferencedLabels;
const elideUnobservablePositions = il_passes.elideUnobservablePositions;
const sinkPositions = il_passes.sinkPositions;
const callSitePositions = il_passes.callSitePositions;
const haltFailurePaths = il_passes.haltFailurePaths;
const stickyTrap = il_passes.stickyTrap;
const dropUnusedRoots = il_passes.dropUnusedRoots;
const dropUnusedSlots = il_passes.dropUnusedSlots;
const slotDefinition = il_passes.slotDefinition;
const dropUnusedHeap = il_passes.dropUnusedHeap;

/// Whether one instruction names a local slot at all, as a value it reads or
/// writes or as the receiver an operation is bound to. Used to prove that a
/// temporary has no reader other than the pair a fusion replaces.
fn mentionsLocal(op: @FieldType(bytecode.Instruction, "op"), slot: typed.LocalId) bool {
    switch (op) {
        .begin_arena, .end_arena, .move_local, .drop_local, .load_local, .ref_local, .store_local => |other| return other == slot,
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

const roots_module = @import("qbe_roots.zig");
const pureCalleeName = roots_module.pureCalleeName;

/// One whole-program emission pass, shared by the measurement pass and the
/// pass that uses its result.
const EmitPass = struct {
    allocator: std.mem.Allocator,
    /// Backs the per-function scratch arena, which is reset after every unit so
    /// one emission never holds more than one function's lowering garbage.
    backing: std.mem.Allocator,
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
    pure: []const bool,
    /// The copy-on-write code every unit carries (`COW-UNIQUE-1`).
    cow: @import("native_interface.zig").Cow = .off,
};

/// Lower one function into text allocated from `scratch`, with the pass's
/// current allocation analysis. Its operand stacks are returned beside it.
const EmittedEntry = struct { text: []const u8, states: []?[]const typed.Type };
fn emitOne(pass: EmitPass, index: usize, scratch: std.mem.Allocator) GenerateError!EmittedEntry {
    return emitEntry(pass, index, scratch, null);
}

fn emitEntry(pass: EmitPass, index: usize, scratch: std.mem.Allocator, certificate: ?@import("rc_model.zig").BorrowCertificate) GenerateError!EmittedEntry {
    var emitter = Emitter{
        .allocator = scratch,
        .program = pass.program,
        .function = pass.program.functions[index],
        .units = pass.units,
        .layouts = pass.layouts,
        .sink = pass.sink,
        .output = .init(scratch),
        .scratch = .init(scratch),
        .arenas = pass.arenas,
        .step_checks = pass.step_checks,
        .frame_checks = pass.frame_checks,
        .entry = index == @backingInt(pass.program.main),
        .pure = pass.pure,
        .cow = if (pass.cow == .off) null else try cow_lower.request(scratch, pass.cow == .counting),
    };
    const name = if (certificate != null) try rc_borrow.symbol(scratch, pass.units[index].symbol) else pass.units[index].symbol;
    const text = try emitter.emit(name, certificate);
    return .{ .text = text, .states = emitter.states };
}

/// The fragment reuse one emission runs with: the configured store, the
/// per-build key memo, each function's first-pass key, the symbols of every
/// unit (for `unitAllocates`), and the facts a second-pass key reads about
/// each named function (`QBE-FRAGMENT-REUSE-1`).
const Reuse = struct {
    configured: ?fragments.Reuse,
    keys: ?fragments.Keys,
    local: []fragments.Digest,
    symbols: std.StringHashMapUnmanaged(void),
    writes: []?[]const bool,
    targets: ?fragments.Digest = null,
    /// Each emitted function's second-pass key, which its metadata key extends.
    finals: []fragments.Digest,
    /// EMIT-STANDIN-1: what an emission that lowers only some functions keeps
    /// about each one, or null for an emission that lowers them all.
    standin: ?StandIn = null,

    fn init(a: std.mem.Allocator, pass: EmitPass, configured: ?fragments.Reuse) GenerateError!Reuse {
        var symbols: std.StringHashMapUnmanaged(void) = .empty;
        errdefer symbols.deinit(a);
        for (pass.units) |unit| try symbols.put(a, unit.symbol, {});
        const writes = try a.alloc(?[]const bool, pass.program.functions.len);
        errdefer a.free(writes);
        @memset(writes, null);
        const local = try a.alloc(fragments.Digest, pass.program.functions.len);
        errdefer a.free(local);
        return .{
            .configured = configured,
            .keys = if (configured != null) try fragments.Keys.init(a, pass.program) else null,
            .local = local,
            .symbols = symbols,
            .writes = writes,
            .finals = try a.alloc(fragments.Digest, pass.program.functions.len),
        };
    }
    /// The record function `index`'s unit is taken from, when it stays unlowered.
    fn stood(self: *const Reuse, index: usize) ?*const fragments.Record {
        const standin = self.standin orelse return null;
        if (standin.standins.selected[index]) return null;
        return standin.standins.records[index];
    }
    /// Forget every memo that reads function bodies, after some changed.
    fn forget(self: *Reuse, a: std.mem.Allocator, program: bytecode.Program) GenerateError!void {
        self.keys = try fragments.Keys.init(a, program);
        @memset(self.writes, null);
        self.targets = null;
    }
    /// Which parameters of function `index` its own body writes: the one fact
    /// about a callee's body (`blindCall`) that a caller's unit reads.
    fn parameterWrites(self: *Reuse, a: std.mem.Allocator, program: bytecode.Program, index: usize) GenerateError![]const bool {
        if (self.writes[index]) |known| return known;
        if (self.stood(index)) |record| return record.facts.writes;
        const function = program.functions[index];
        const count = @min(function.signature.parameter_count, function.scope.locals.len);
        const flags = try a.alloc(bool, count);
        for (flags, 0..) |*flag, parameter| {
            flag.* = false;
            for (0..function.scope.instructions.len) |at| if (writesLocalAt(function, at, parameter)) {
                flag.* = true;
                break;
            };
        }
        self.writes[index] = flags;
        return flags;
    }
    /// The digest of the program's function-value target set, over every
    /// lowered function's instructions and every stood-in function's record.
    fn valueTargets(self: *Reuse, a: std.mem.Allocator, program: bytecode.Program) GenerateError!fragments.Digest {
        if (self.targets) |known| return known;
        var names: std.ArrayList([]const u8) = .empty;
        for (program.functions, 0..) |function, index| {
            if (self.stood(index)) |record| {
                try names.appendSlice(a, record.facts.values);
                continue;
            }
            for (function.scope.instructions) |instruction| switch (instruction.op) {
                .function_value => |value| if (@backingInt(value.function) < program.functions.len) try names.append(a, program.functions[@backingInt(value.function)].name),
                else => {},
            };
        }
        self.targets = fragments.targetsDigest(names.items);
        return self.targets.?;
    }
    /// The second-pass key of function `index` under allocation analysis `pure`.
    fn final(self: *Reuse, a: std.mem.Allocator, program: bytecode.Program, index: usize, pure: []const bool) GenerateError!fragments.Digest {
        var key: fragments.Final = .init(self.local[index]);
        for (try self.keys.?.callees(index)) |callee| key.callee(callee < pure.len and pure[callee], try self.parameterWrites(a, program, callee));
        if (invokes(program.functions[index])) key.targets(try self.valueTargets(a, program));
        return key.finish();
    }
};

/// Whether a function invokes a function value.
fn invokes(function: bytecode.Function) bool {
    for (function.scope.instructions) |instruction| if (instruction.op == .invoke) return true;
    return false;
}

/// EMIT-STANDIN-1 per-emission state: the stand-ins the frontend chose, the
/// function and record names, each function's inline key, and — for each
/// lowered function — its stored unit answer, its metadata digest and the
/// sources its positions fall in, from which its record is made.
const StandIn = struct {
    standins: *fragments.Standins,
    functions: std.StringHashMapUnmanaged(u32),
    records: std.StringHashMapUnmanaged(u32),
    inline_keys: []fragments.Digest,
    answers: []?fragments.Unit,
    metas: []?fragments.Digest,
    sources: [][]const u32,
    digests: SourceDigests,
    /// The function table the emission works on, into which newly lowered
    /// bodies are inlined.
    working: []bytecode.Function,

    fn init(a: std.mem.Allocator, program: bytecode.Program, standins: *fragments.Standins, src: Source) GenerateError!StandIn {
        var functions: std.StringHashMapUnmanaged(u32) = .empty;
        errdefer functions.deinit(a);
        for (program.functions, 0..) |function, index| try functions.put(a, function.name, @intCast(index));
        var records: std.StringHashMapUnmanaged(u32) = .empty;
        errdefer records.deinit(a);
        for (program.records, 0..) |record, index| try records.put(a, record.name, @intCast(index));
        const count = program.functions.len;
        const answers = try a.alloc(?fragments.Unit, count);
        errdefer a.free(answers);
        @memset(answers, null);
        const metas = try a.alloc(?fragments.Digest, count);
        errdefer a.free(metas);
        @memset(metas, null);
        const sources = try a.alloc([]const u32, count);
        errdefer a.free(sources);
        @memset(sources, &.{});
        const inline_keys = try a.alloc(fragments.Digest, count);
        errdefer a.free(inline_keys);
        return .{
            .standins = standins,
            .functions = functions,
            .records = records,
            .inline_keys = inline_keys,
            .answers = answers,
            .metas = metas,
            .sources = sources,
            .digests = try .init(a, src),
            .working = @constCast(program.functions),
        };
    }
    /// The indices of the functions `names` names, skipping any that no
    /// longer exist.
    fn indices(self: *const StandIn, a: std.mem.Allocator, names: []const []const u8) GenerateError![]const u32 {
        var out: std.ArrayList(u32) = .empty;
        for (names) |name| if (self.functions.get(name)) |index| try out.append(a, index);
        return out.items;
    }
};

/// EMIT-STANDIN-1: run the first pass and the allocation analysis over the
/// lowered functions and the stood-in records, then select every stood-in
/// function whose record no longer matches what its unit would read, lower
/// those too, and repeat until no record is stale. Returns each function's
/// own allocation fact.
fn standInPasses(pass: *EmitPass, reuse: *Reuse) GenerateError![]bool {
    const standin = &reuse.standin.?;
    const standins = standin.standins;
    while (true) {
        const own = try firstPass(pass.*, reuse);
        pass.pure = try allocateAnalysis(pass.allocator, pass.program, own, reuse);
        try inlineKeys(pass.*, reuse);
        var grew = false;
        for (standins.records, standins.selected) |record, *chosen| {
            const stored = record orelse continue;
            if (chosen.*) continue;
            const now = try snapshotOf(pass.*, reuse, stored.reads, stored.facts.marks.invokes);
            if (std.mem.eql(u8, &now, &stored.snapshot)) continue;
            chosen.* = true;
            grew = true;
        }
        if (!grew) return own;
        try standins.lower.run(standins.lower.context, standins);
        try reinline(pass.*, standin);
        pass.arenas = arenasPresent(pass.program, reuse);
        try reuse.forget(pass.allocator, pass.program);
    }
}

/// Inline the selected functions' bodies again after more were lowered, and
/// put the results in the emission's function table.
fn reinline(pass: EmitPass, standin: *StandIn) GenerateError!void {
    const standins = standin.standins;
    const lowered: bytecode.Program = .{ .functions = standins.pre, .main = pass.program.main, .records = pass.program.records };
    const inlined = @import("bytecode_inline.zig").inlineProgram(pass.allocator, lowered) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
    for (standins.selected, standin.working, inlined.functions) |chosen, *function, result| {
        if (chosen) function.scope = result.scope;
    }
}

/// Each function's inline key: zero unless the inliner may splice it into a
/// caller, and then the digest of the body a caller splices.
fn inlineKeys(pass: EmitPass, reuse: *Reuse) GenerateError!void {
    const standin = &reuse.standin.?;
    for (standin.inline_keys, 0..) |*key, index| {
        if (reuse.stood(index)) |record| {
            key.* = record.facts.inline_key;
        } else if (standin.standins.selected[index] and @import("bytecode_inline.zig").eligibleFunction(pass.program, index)) {
            key.* = try reuse.keys.?.bodyDigest(index);
        } else key.* = @splat(0);
    }
}

/// Whether any function opens an arena scope, reading a stood-in function's
/// record in place of its body.
fn arenasPresent(program: bytecode.Program, reuse: *const Reuse) bool {
    for (program.functions, 0..) |function, index| {
        if (reuse.stood(index)) |record| {
            if (record.facts.marks.arena) return true;
        } else if (arena_lower.opens(function)) return true;
    }
    return false;
}

/// Whether any function needs the text runtime, reading a stood-in
/// function's record in place of its body.
fn textFormat(program: bytecode.Program, reuse: *const Reuse) bool {
    for (program.functions, 0..) |function, index| {
        if (reuse.stood(index)) |record| {
            if (record.facts.marks.text) return true;
        } else if (needsText(program, function)) return true;
    }
    return false;
}

/// Whether one function's body needs the text runtime.
fn needsText(program: bytecode.Program, function: bytecode.Function) bool {
    for (function.scope.instructions) |instruction| if (needsTextRuntime(program, instruction.op)) return true;
    return false;
}

/// The digest of everything a unit reads outside its function's own source:
/// the whole-program switches, and for each function it names that
/// function's interface, inline key, allocation fact and parameter writes;
/// the schema of every record it reaches; the function-value target set
/// when it invokes a function value; and every source its positions fall in.
/// A stood-in unit is current exactly while this equals its record's.
fn snapshotOf(pass: EmitPass, reuse: *Reuse, reads: fragments.Reads, invoking: bool) GenerateError!fragments.Digest {
    const standin = &reuse.standin.?;
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("standin-snapshot-v1");
    for ([_]bool{ pass.step_checks, pass.frame_checks, pass.arenas }) |flag| hash.update(&.{@intFromBool(flag)});
    for (reads.names) |name| {
        snapshotText(&hash, name);
        const index = standin.functions.get(name) orelse {
            hash.update("missing");
            continue;
        };
        hash.update(&try reuse.keys.?.interfaceDigest(index));
        hash.update(&standin.inline_keys[index]);
        hash.update(&.{@intFromBool(pass.pure[index])});
        const writes = try reuse.parameterWrites(pass.allocator, pass.program, index);
        snapshotCount(&hash, writes.len);
        for (writes) |flag| hash.update(&.{@intFromBool(flag)});
    }
    for (reads.records) |name| {
        snapshotText(&hash, name);
        const index = standin.records.get(name) orelse {
            hash.update("missing");
            continue;
        };
        hash.update(&try reuse.keys.?.recordDigest(index));
    }
    if (invoking) hash.update(&try reuse.valueTargets(pass.allocator, pass.program));
    for (reads.sources) |path| {
        snapshotText(&hash, path);
        const digest = (try standin.digests.digestAt(path)) orelse {
            hash.update("missing");
            continue;
        };
        hash.update(&digest);
    }
    var out: fragments.Digest = undefined;
    hash.final(&out);
    return out;
}
fn snapshotText(hash: *std.crypto.hash.Blake3, text: []const u8) void {
    snapshotCount(hash, text.len);
    hash.update(text);
}
fn snapshotCount(hash: *std.crypto.hash.Blake3, count: usize) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, count, .little);
    hash.update(&bytes);
}

/// What function `index`'s unit read about the rest of the program.
fn readsOf(pass: EmitPass, reuse: *Reuse, index: usize) GenerateError!fragments.Reads {
    const standin = &reuse.standin.?;
    const a = pass.allocator;
    const callees = try reuse.keys.?.callees(index);
    const names = try a.alloc([]const u8, callees.len);
    for (callees, names) |callee, *name| name.* = pass.program.functions[callee].name;
    const reached = try reuse.keys.?.reach(index);
    const records = try a.alloc([]const u8, reached.len);
    for (reached, records) |record, *name| name.* = pass.program.records[record].name;
    const origins = standin.sources[index];
    const paths = try a.alloc([]const u8, origins.len);
    for (origins, paths) |origin, *path| path.* = standin.digests.path(origin);
    return .{ .names = names, .records = records, .sources = paths };
}

/// Whether a lowered function may leave a record: one that prints or renders
/// a value into text is always lowered, since the program's renderers are
/// read from its body, and so is one that names an expression lambda, whose
/// name moves with the source around it.
fn recordable(pass: EmitPass, reuse: *Reuse, index: usize) GenerateError!bool {
    const function = pass.program.functions[index];
    if (rendersText(function, pass.program.records)) return false;
    for (function.scope.instructions) |instruction| if (instruction.op == .print) return false;
    for (try reuse.keys.?.callees(index)) |callee| {
        if (std.mem.startsWith(u8, pass.program.functions[callee].name, "lambda@")) return false;
    }
    return true;
}

/// The names of the functions one lowered function calls after inlining, and
/// of those it takes as values (one per instruction, as the target set counts them).
fn calledNames(a: std.mem.Allocator, program: bytecode.Program, function: bytecode.Function) GenerateError![2][]const []const u8 {
    var calls: std.ArrayList([]const u8) = .empty;
    var values: std.ArrayList([]const u8) = .empty;
    for (function.scope.instructions) |instruction| switch (instruction.op) {
        .call => |id| if (@backingInt(id) < program.functions.len) {
            const name = program.functions[@backingInt(id)].name;
            for (calls.items) |known| {
                if (std.mem.eql(u8, known, name)) break;
            } else try calls.append(a, name);
        },
        .function_value => |value| if (@backingInt(value.function) < program.functions.len) try values.append(a, program.functions[@backingInt(value.function)].name),
        else => {},
    };
    return .{ calls.items, values.items };
}

/// EMIT-STANDIN-1: give every stood-in unit its record's answer, and leave a
/// fresh record for every lowered function that may have one.
fn recordStandIns(pass: EmitPass, reuse: *Reuse, allocates: []const bool) GenerateError!void {
    const standin = &reuse.standin.?;
    const store = reuse.configured.?.store;
    const a = pass.allocator;
    for (pass.program.functions, pass.units, 0..) |function, *unit, index| {
        if (reuse.stood(index)) |record| {
            unit.stored = .{ .digest = try a.dupe(u8, &std.fmt.bytesToHex(record.unit.il, .lower)), .facts = record.unit.facts, .meta = try a.dupe(u8, &std.fmt.bytesToHex(record.meta, .lower)) };
            unit.test_dependencies = record.unit.dependencies;
            store.statistics.standin.reused += 1;
            continue;
        }
        store.statistics.standin.lowered += 1;
        const key = standin.standins.keys[index] orelse continue;
        const answer = standin.answers[index] orelse continue;
        const meta = standin.metas[index] orelse continue;
        if (!try recordable(pass, reuse, index)) continue;
        const reads = try readsOf(pass, reuse, index);
        const named = try calledNames(a, pass.program, function);
        const marks: fragments.Marks = .{ .invokes = invokes(function), .arena = arena_lower.opens(function), .text = needsText(pass.program, function) };
        try store.rememberRecord(key, .{
            .name = function.name,
            .unit = answer,
            .meta = meta,
            .snapshot = try snapshotOf(pass, reuse, reads, marks.invokes),
            .facts = .{
                .inline_key = standin.inline_keys[index],
                .allocates = allocates[index],
                .calls = named[0],
                .writes = try reuse.parameterWrites(a, pass.program, index),
                .values = named[1],
                .marks = marks,
            },
            .reads = reads,
        });
    }
}

/// First pass: learn, per emitted function, whether its own text allocates.
/// Units are lowered with roots everywhere and then discarded; a stored answer
/// for an unchanged first-pass key skips the lowering.
fn firstPass(pass: EmitPass, reuse: *Reuse) GenerateError![]bool {
    const program = pass.program;
    const allocates = try pass.allocator.alloc(bool, program.functions.len);
    @memset(allocates, false);
    var scratch = std.heap.ArenaAllocator.init(pass.backing);
    defer scratch.deinit();
    for (0..program.functions.len) |index| {
        if (pass.selected != null and !pass.selected.?[index]) {
            // A stood-in unit's own allocation fact is its record's.
            if (reuse.stood(index)) |record| allocates[index] = record.facts.allocates;
            continue;
        }
        if (reuse.configured) |configured| {
            const body_key = try reuse.keys.?.local(index, flagsOf(pass, index));
            reuse.local[index] = @import("qbe_rc_cache.zig").key(pass.allocator, pass.program, pass.layouts, index, body_key) catch |err| return layoutError(err);
            if (try configured.store.first(reuse.local[index])) |answer| {
                allocates[index] = answer;
                continue;
            }
        }
        defer _ = scratch.reset(.retain_capacity);
        const emitted = try emitOne(pass, index, scratch.allocator());
        allocates[index] = unitAllocates(emitted.text, &reuse.symbols);
        if (reuse.configured) |configured| try configured.store.rememberFirst(reuse.local[index], allocates[index]);
    }
    return allocates;
}

/// Second pass: emit (or reuse) every selected unit with the allocation
/// analysis in hand, and record its checked dependency facts. Only the unit
/// text and the operand stacks a `str` renderer needs outlive one function.
fn secondPass(pass: EmitPass, reuse: *Reuse) GenerateError!void {
    const a = pass.allocator;
    const program = pass.program;
    var scratch = std.heap.ArenaAllocator.init(pass.backing);
    defer scratch.deinit();
    for (program.functions, pass.units, pass.states, 0..) |function, *unit, *stacks, index| {
        if (pass.selected != null and !pass.selected.?[index]) continue;
        defer _ = scratch.reset(.retain_capacity);
        const key = if (reuse.configured != null) try reuse.final(a, program, index, pass.pure) else undefined;
        reuse.finals[index] = key;
        if (reuse.configured) |configured| if (try configured.store.unit(key)) |answer| {
            unit.test_dependencies = answer.dependencies;
            if (reuse.standin) |standin| standin.answers[index] = answer;
            if (configured.lean) {
                unit.stored = try storedUnit(a, answer);
            } else {
                unit.il = configured.store.read(answer.il) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.FragmentMissing => return error.InternalError,
                };
            }
            if (rendersText(function, program.records)) stacks.* = try analyzedStates(pass, index, scratch.allocator());
            continue;
        };
        const emitted = try emitOne(pass, index, scratch.allocator());
        unit.test_dependencies = test_dependencies.describe(a, program, index, emitted.text, pass.layouts, emitted.states) catch |err| return layoutError(err);
        if (rendersText(function, program.records)) stacks.* = try copyStates(a, emitted.states);
        if (reuse.configured) |configured| {
            const answer = try configured.store.remember(key, emitted.text, unit.test_dependencies.?);
            if (reuse.standin) |standin| standin.answers[index] = answer;
            if (configured.lean) {
                unit.stored = try storedUnit(a, answer);
                continue;
            }
        }
        unit.il = try a.dupe(u8, emitted.text);
    }
}

/// The whole-program switches a unit's first-pass key covers.
fn flagsOf(pass: EmitPass, index: usize) fragments.Flags {
    return .{
        .step_checks = pass.step_checks,
        .frame_checks = pass.frame_checks,
        .arenas = pass.arenas,
        .entry = index == @backingInt(pass.program.main),
        .cow = pass.cow,
        .runtime = runtime_mode.get(),
    };
}

/// The lean manifest fields of one stored unit. Its text's path is the
/// manifest's `store` joined with the digest, so no unit spells it.
fn storedUnit(a: std.mem.Allocator, answer: fragments.Unit) GenerateError!Stored {
    return .{ .digest = try a.dupe(u8, &std.fmt.bytesToHex(answer.il, .lower)), .facts = answer.facts };
}

/// Which manifest one emission writes: `lean` names stored texts and metadata
/// by digest, and `executable` leaves out what only a library build reads.
const Shape = struct { lean: bool = false, executable: bool = false };

/// Compute one unit's per-instruction positions and assertion messages and
/// its inline frames into `a`.
fn fillPositions(a: std.mem.Allocator, program: bytecode.Program, src: Source, index: usize, unit: *Unit) GenerateError!void {
    const code = program.functions[index].scope.instructions;
    const locations = try a.alloc(Location, code.len);
    const messages = try a.alloc([]const u8, code.len);
    for (code, locations, messages) |instruction, *location, *message| {
        const value = src.locate(instruction.span.start);
        location.* = .{ .path = value.path, .line = value.line, .column = value.column };
        // ERROR-TRACE-1: a converting `?` never traps, so its slot names the
        // union case the error trace reports it wrapped the error in.
        message.* = if (instruction.op == .assert_true) instruction.op.assert_true.message else try error_trace.conversionCase(a, program.records, instruction.op) orelse "";
    }
    unit.locations = locations;
    unit.messages = messages;
    unit.inlines = try inlineFrames(a, program, code);
}

/// EMIT-META-1: name every emitted lean unit's metadata by the digest of its
/// stored text. The metadata key (`fragments.MetaKey`) is the unit's
/// second-pass key plus the digest of each source its instructions' positions
/// fall in, so a unit whose function and sources are unchanged reads its digest
/// from the store without locating a single instruction; only a miss computes
/// positions, messages and inline frames, renders them and stores the text.
fn metaPass(pass: EmitPass, reuse: *Reuse, src: Source) GenerateError!void {
    const store = reuse.configured.?.store;
    var own: SourceDigests = undefined;
    const sources = if (reuse.standin) |*standin| &standin.digests else own: {
        own = try .init(pass.allocator, src);
        break :own &own;
    };
    var scratch = std.heap.ArenaAllocator.init(pass.backing);
    defer scratch.deinit();
    for (pass.units, 0..) |*unit, index| {
        if (pass.selected != null and !pass.selected.?[index]) continue;
        defer _ = scratch.reset(.retain_capacity);
        var key: fragments.MetaKey = .init(reuse.finals[index]);
        try sources.fold(&key, pass.program.functions[index].scope.instructions);
        if (reuse.standin) |standin| standin.sources[index] = try pass.allocator.dupe(u32, sources.last.items);
        const identity = key.finish();
        if (try store.meta(identity)) |digest| {
            unit.stored.?.meta = try pass.allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
            if (reuse.standin) |standin| standin.metas[index] = digest;
            continue;
        }
        var positioned = unit.*;
        try fillPositions(scratch.allocator(), pass.program, src, index, &positioned);
        const text = try std.json.Stringify.valueAlloc(scratch.allocator(), MetaRecord{ .unit = positioned }, .{});
        const digest = try store.rememberMeta(identity, text);
        unit.stored.?.meta = try pass.allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
        if (reuse.standin) |standin| standin.metas[index] = digest;
        // The build needs a fresh record in any case, since the metadata
        // it belongs to changed; handing it over inline saves reading it back.
        unit.stored.?.record = try pass.allocator.dupe(u8, text);
    }
}

/// The digest of each source of a merged program, computed the first time a
/// unit's positions fall in it, and a stamp per source so one unit folds each
/// source into its metadata key once, in first-use order.
const SourceDigests = struct {
    allocator: std.mem.Allocator,
    src: Source,
    digests: []?fragments.Digest,
    stamps: []usize,
    stamp: usize = 0,
    /// The sources the last `fold` added, in first-use order.
    last: std.ArrayList(u32) = .empty,
    /// Each source's path, for looking a stored source up by it.
    paths: std.StringHashMapUnmanaged(u32) = .empty,

    fn init(a: std.mem.Allocator, src: Source) GenerateError!SourceDigests {
        const count = @max(1, src.origins.len);
        const digests = try a.alloc(?fragments.Digest, count);
        errdefer a.free(digests);
        @memset(digests, null);
        const stamps = try a.alloc(usize, count);
        @memset(stamps, 0);
        return .{ .allocator = a, .src = src, .digests = digests, .stamps = stamps };
    }
    /// Add to `key` every source `code`'s positions fall in, in first-use order.
    fn fold(self: *SourceDigests, key: *fragments.MetaKey, code: []const bytecode.Instruction) GenerateError!void {
        self.stamp += 1;
        self.last.clearRetainingCapacity();
        var current: ?usize = null;
        for (code) |instruction| {
            const origin = self.originOf(instruction.span.start, current);
            current = origin;
            if (self.stamps[origin] == self.stamp) continue;
            self.stamps[origin] = self.stamp;
            key.source(self.digest(origin));
            try self.last.append(self.allocator, @intCast(origin));
        }
    }
    /// The path of source `origin`.
    fn path(self: *const SourceDigests, origin: usize) []const u8 {
        return if (self.src.origins.len == 0) self.src.path else self.src.origins[origin].original.path;
    }
    /// The digest of the source at `wanted`, or null when no source has that path.
    fn digestAt(self: *SourceDigests, wanted: []const u8) GenerateError!?fragments.Digest {
        if (self.paths.count() == 0) for (0..self.digests.len) |origin| try self.paths.put(self.allocator, self.path(origin), @intCast(origin));
        const origin = self.paths.get(wanted) orelse return null;
        return self.digest(origin);
    }
    /// The index of the source `offset` falls in, as `Source.locate` finds
    /// it: the last one starting at or before it. `hint` is tried first,
    /// since consecutive instructions almost always share a source.
    fn originOf(self: *const SourceDigests, offset: usize, hint: ?usize) usize {
        const origins = self.src.origins;
        if (origins.len == 0) return 0;
        if (hint) |at| {
            const next = if (at + 1 < origins.len) origins[at + 1].start else std.math.maxInt(usize);
            if (origins[at].start <= offset and offset < next) return at;
        }
        var low: usize = 0;
        var high = origins.len;
        while (low + 1 < high) {
            const mid = low + (high - low) / 2;
            if (origins[mid].start <= offset) low = mid else high = mid;
        }
        return low;
    }
    fn digest(self: *SourceDigests, origin: usize) fragments.Digest {
        if (self.digests[origin]) |known| return known;
        const source = if (self.src.origins.len == 0) self.src else self.src.origins[origin].original;
        const computed = fragments.sourceDigest(source.path, source.bytes);
        self.digests[origin] = computed;
        return computed;
    }
};

/// Whether `native_render` reads this function's operand stacks: only a
/// conversion to a managed text record names a type it cannot see otherwise
/// (`rendersConversion` needs the operand's type only for those), so an integer
/// narrowing never costs a reused unit its operand analysis.
fn rendersText(function: bytecode.Function, records: []const typed.Record) bool {
    for (function.scope.instructions) |instruction| switch (instruction.op) {
        .cast_integer => |target| {
            if (!target.isAggregate() or target.recordIndex() >= records.len) continue;
            const record = records[target.recordIndex()];
            if (record.managed and record.collection.kind == .string) return true;
        },
        else => {},
    };
    return false;
}

/// Operand stacks of a reused unit, from the same analysis emission runs. A
/// host or C-ABI function is lowered without one, exactly as when emitted.
fn analyzedStates(pass: EmitPass, index: usize, scratch: std.mem.Allocator) GenerateError![]const ?[]const typed.Type {
    const function = pass.program.functions[index];
    if (function.policy.c_abi or function.policy.host != null) return &.{};
    const ir = @import("native_ir.zig").analyze(scratch, pass.program, function) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
    return copyStates(pass.allocator, ir.states);
}

/// Copy per-pc operand stacks out of one function's scratch arena.
fn copyStates(a: std.mem.Allocator, states: []const ?[]const typed.Type) GenerateError![]const ?[]const typed.Type {
    const copied = try a.alloc(?[]const typed.Type, states.len);
    for (states, copied) |state, *out| out.* = if (state) |stack| try a.dupe(typed.Type, stack) else null;
    return copied;
}

/// Per function, whether it can allocate or reach a call that can, transitively.
/// A direct `.call` to a function this leaves false cannot start a collection,
/// so the caller omits the root protocol around it. `own` is each function's
/// answer from its own first-pass text (`unitAllocates`), so the analysis
/// cannot drift from the lowering it describes.
fn allocateAnalysis(a: std.mem.Allocator, program: bytecode.Program, own: []const bool, reuse: *const Reuse) GenerateError![]bool {
    const may = try a.dupe(bool, own);
    // A stood-in function's calls after inlining are its record's (EMIT-STANDIN-1).
    const stood = try a.alloc(?[]const u32, program.functions.len);
    @memset(stood, null);
    if (reuse.standin) |standin| for (stood, 0..) |*calls, index| {
        const record = reuse.stood(index) orelse continue;
        calls.* = try standin.indices(a, record.facts.calls);
    };
    var changed = true;
    while (changed) {
        changed = false;
        for (program.functions, stood, 0..) |function, recorded, index| {
            if (may[index]) continue;
            if (recorded) |calls| {
                for (calls) |callee| if (may[callee]) {
                    may[index] = true;
                    changed = true;
                    break;
                };
                continue;
            }
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
/// `symbols` holds every unit's symbol, so each call costs one lookup rather
/// than a scan of the whole program.
fn unitAllocates(text: []const u8, symbols: *const std.StringHashMapUnmanaged(void)) bool {
    if (callsIndirectly(text)) return true;
    var rest = text;
    while (std.mem.indexOf(u8, rest, "call $")) |at| {
        rest = rest[at + "call $".len ..];
        const stop = std.mem.indexOfAny(u8, rest, "( \n") orelse rest.len;
        const name = rest[0..stop];
        const runtime = pureCalleeName(name) or frameCallee(name);
        if (!runtime and !symbols.contains(name)) return true;
        rest = rest[stop..];
    }
    return false;
}

const callsIndirectly = roots_module.callsIndirectly;

fn frameCallee(name: []const u8) bool {
    for (frame_callees) |candidate| if (std.mem.eql(u8, name, candidate)) return true;
    return false;
}

/// One read of a local into an operand slot: the local, the slot and the pc of
/// the reading instruction.
const LocalRead = struct { index: usize, slot: usize, pc: usize };

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
    /// Emit the value guards of integer `+ - *` and of list, fixed-array and
    /// `bytes` element access. Always true, except while a check-free loop
    /// copy lowers an instruction its guard proved cannot fail
    /// (`QBE-LOOP-VERSION-1`); every other guard ignores it.
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
    /// The liveness of every local, solved once and read by root planning,
    /// the ownership analysis and the move planner alike
    /// (`OWNERSHIP-ANALYSIS-1`).
    live: ?liveness.Solution = null,
    /// The ownership analysis of this function (`OWNERSHIP-ANALYSIS-1`).
    ownership: ?ownership.Analysis = null,
    /// The aggregate copies this function skips (`QBE-MOVE-ELIDE-1`).
    moves: moves_module.Plan = .{},
    /// The borrowed locals a published owner covers (`QBE-BORROW-ROOT-1`).
    coverage: @import("qbe_cover.zig").Coverage = .{},
    /// The pc whose published-root flags `published_flags` holds.
    published_pc: usize = std.math.maxInt(usize),
    /// Per local, whether the safepoint at `published_pc` publishes it.
    published_flags: []const bool = &.{},
    /// The slices lowered as described dictionary keys and where their spans
    /// live (`DICT-RANGE-KEY-1`).
    range_keys: range_keys.Plan = .{},
    /// The loops lowered twice, behind a guard (`QBE-LOOP-VERSION-1`).
    loop_plan: loop_facts.Plan = .{},
    /// Set while the check-free copy of a versioned loop is being lowered.
    version: ?*loop_version.Active = null,
    /// Set while the original copy of a versioned loop is being lowered, whose
    /// header label the guard took.
    original: ?*const loop_facts.Loop = null,
    /// The copy-on-write plan of this function, when the build emits one
    /// (`COW-UNIQUE-1`).
    cow: ?*cow_lower.State = null,

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
    pub fn isBranchTarget(self: *Emitter, pc: usize) bool {
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
    fn emit(self: *Emitter, name: []const u8, certificate: ?@import("rc_model.zig").BorrowCertificate) GenerateError![]const u8 {
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
        try self.planOwnership();
        if (runtime_mode.enabled()) {
            self.cow.?.rc = try @import("qbe_rc_state.zig").build(Emitter, self, ir.stack_capacity);
            const rc = self.cow.?.rc.?;
            if (certificate) |proof| {
                rc.contract.result = .{ .borrowed = proof };
            } else if ((@import("rc_readonly_calls.zig").identity(&rc.catalog, self.program.functions, f, runtime_mode.identity()) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError) != null) {
                rc.readonly = true;
                rc.active = false;
            }
        }
        if (!runtime_mode.enabled()) self.range_keys = try self.planRangeKeys();
        // QBE-LOOP-VERSION-1: only a build whose value guards are on has
        // anything to prove, and step accounting counts every instruction the
        // original executes, so a counted build keeps one copy.
        const version_loops = self.checks and !self.step_checks;
        if (version_loops) self.loop_plan = try loop_facts.plan(self.allocator, .{
            .program = self.program,
            .function = f,
            .states = self.states,
            .box_cow = self.cow != null and value_semantics.enabled(),
        });
        if (self.cow) |state| try cow_lower.Lower(Emitter).veto(self, state);
        if (runtime_mode.enabled()) try @import("qbe_rc_dictionary_tail.zig").finalize(Emitter, self);
        if (runtime_mode.enabled()) try @import("qbe_rc_empty_locals.zig").finalize(Emitter, self);
        if (runtime_mode.enabled()) try @import("qbe_rc_empty_frame.zig").finalize(Emitter, self);
        try self.findRoots();
        if (self.needsRootProtocol()) self.live_roots = try self.rootLiveness();
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
    /// Solve liveness once, run the ownership analysis over it and plan the
    /// aggregate copies it proves unnecessary (`OWNERSHIP-ANALYSIS-1`,
    /// `QBE-MOVE-ELIDE-1`). Root planning reads the same solution.
    fn planOwnership(self: *Emitter) GenerateError!void {
        const locals = self.function.scope.locals;
        const pinned = try self.allocator.alloc(bool, locals.len);
        for (locals, pinned) |local, *pin| pin.* = (try self.layout(local.ty)).drop;
        const input: liveness.Input = .{ .function = self.function, .states = self.states, .pinned = pinned };
        self.live = try liveness.solve(self.allocator, input);
        // COW write-back and pending receivers have implicit parent/key uses.
        // Extend liveness with them and repeat ownership planning until every
        // copy, borrow and move proof reads that final lifetime.
        while (true) {
            self.ownership = ownership.analyze(self.allocator, .{ .program = self.program, .function = self.function, .states = self.states, .live = self.live.? }) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InternalError => return error.InternalError,
            };
            if (self.cow) |state| {
                if (try cow_lower.Lower(Emitter).plan(self, state)) {
                    try liveness.extend(self.allocator, input, self.live.?);
                    continue;
                }
            }
            break;
        }
        if (!runtime_mode.enabled()) self.moves = try moves_module.Lower(Emitter).plan(self);
        self.coverage = try @import("qbe_cover.zig").Lower(Emitter).plan(self);
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
            try self.print(" %empty =l alloc8 {d}\n", .{@max(8, return_bytes)});
            if (self.cow == null) try self.print(zero_failure_result, .{@max(8, return_bytes)});
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
        if (self.entry and !runtime_mode.enabled()) try self.requireAccounting();
        const inert_resume = try @import("qbe_rc_inert_return.zig").emit(Emitter, self);
        try arena_lower.Lower(Emitter).mark(self);
        if (self.heap_frame) {
            if (!try @import("qbe_rc_admission.zig").allocate(Emitter, self, frame.heap)) {
                try self.print(" %frame_memory =l call $myl_qbe_frame_allocate(l %ctx, l {d})\n", .{frame.heap});
                try self.checkFailure("allocation_failure");
            }
            try self.allocateStorage(capacity);
            try self.allocateTemporaries(.all);
        }
        try self.allocateDynamicTemporaries();
        try self.initializeStorage();
        if (self.has_roots) try self.print(" %heap =l call $myl_qbe_heap(l %ctx)\n", .{});
        try rc_frame.Lower(Emitter).enter(self);
        if (self.entry and runtime_mode.enabled()) try self.requireAccounting();
        if (self.needsRootProtocol()) try self.print(" %root_mark =l call $myl_qbe_root_mark(l %ctx)\n", .{});
        if (self.step_checks) try self.print(" %maxsteps =l add %ctx, 16\n", .{});
        try @import("qbe_rc_inert_return.zig").enterBody(Emitter, self, inert_resume);
        try self.emitInstructions();
        if (self.step_checks) try self.print("@step_limit\n call $myl_qbe_fail_step(l %ctx)\n jmp @failure\n@failure\n", .{}) else try self.print("@failure\n", .{});
        try cow_lower.Lower(Emitter).clearScopes(self);
        try rc_frame.Lower(Emitter).cleanup(self);
        try rc_frame.Lower(Emitter).leave(self);
        try arena_lower.Lower(Emitter).restore(self);
        if (self.needsRootProtocol()) try root_lower.restoreFrameRoots(self);
        if (self.heap_frame) try self.print(" call $myl_qbe_frame_release(l %ctx, l %frame_memory)\n jmp @allocation_failure\n@allocation_failure\n", .{});
        try self.leaveFrame();
        // QBE-COLD-FAILRET-1: only failed paths return `%empty`. Initializing
        // it in the entry block makes every successful aggregate-returning
        // call pay for a zero value it never reads.
        if (return_bytes != 0 and self.cow != null) try self.print(zero_failure_result, .{@max(8, return_bytes)});
        try self.print(" ret {s}\n@entry_failure\n", .{if (return_bytes == 0) "0" else "%empty"});
        if (return_bytes != 0 and self.cow != null) try self.print(zero_failure_result, .{@max(8, return_bytes)});
        try self.print(" ret {s}\n}}\n", .{if (return_bytes == 0) "0" else "%empty"});
        var text = try self.output.toOwnedSlice();
        // With no step check, the only reason to store a position is a trap trace
        // or an `assert` message, and both are emitted by a body that mentions a
        // failure path. With a step check, every instruction can fail, so every
        // instruction keeps its position. The frame map stores none at all: each
        // call names its own position for the return-address table instead.
        if (self.frameMap()) {
            text = try callSitePositions(self.allocator, text, name);
        } else if (!self.step_checks) {
            text = try elideUnobservablePositions(self.allocator, text, !self.stickyFlagTest());
            text = try sinkPositions(self.allocator, text);
        }
        text = try dropUnusedRoots(self.allocator, text);
        text = try dropUnusedHeap(self.allocator, text);
        text = try dropUnusedSlots(self.allocator, text);
        if (!self.stickyFlagTest()) text = try haltFailurePaths(self.allocator, text);
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
        self.version = null;
        self.original = null;
    }
    /// Find the slices this function can describe instead of build.
    fn planRangeKeys(self: *Emitter) GenerateError!range_keys.Plan {
        const addressed = try self.allocator.alloc(bool, self.function.scope.locals.len);
        for (addressed, 0..) |*flag, index| flag.* = self.byReference(index) or self.callerStorage(index);
        return range_keys.plan(self.allocator, .{
            .program = self.program,
            .function = self.function,
            .states = self.states,
            .branch_targets = self.branch_targets,
            .by_reference = addressed,
        }, self.arenas);
    }
    /// A value-semantics projection of a recursive box may copy a pinned child
    /// before yielding its private body, so root and borrow planning treat it
    /// as a safepoint. Pure boxes, ordinary fields and switch-off code stay inert.
    pub fn boxProjectionAt(self: *Emitter, pc: usize, op: @FieldType(bytecode.Instruction, "op")) bool {
        if (self.cow == null or !value_semantics.enabled() or op != .get_field) return false;
        if (pc >= self.states.len) return false;
        const stack = self.states[pc] orelse return false;
        if (stack.len == 0) return false;
        const owner = stack[stack.len - 1];
        return owner.isAggregate() and self.program.records[owner.recordIndex()].collection.box and
            value_semantics.needsCopy(self.program.records, owner);
    }
    fn findRoots(self: *Emitter) GenerateError!void {
        const f = self.function;
        for (f.scope.locals) |local| self.has_roots = self.has_roots or (try self.layout(local.ty)).trace;
        for (self.states) |state| if (state) |stack| {
            for (stack) |ty| self.has_roots = self.has_roots or (try self.layout(ty)).trace;
        };
        for (f.scope.instructions, 0..) |instruction, pc| {
            if (self.states[pc] == null) continue;
            self.has_safepoints = self.has_safepoints or allocates(instruction.op) or self.boxProjectionAt(pc, instruction.op);
        }
        // COW-UNIQUE-1: every copy a check or share makes is an allocation.
        if (self.cow) |state| self.has_safepoints = self.has_safepoints or state.plan.active();
    }
    const frame_lower = frame_module.Lower(Emitter);
    pub const abiStackBytes = frame_lower.abiStackBytes;
    pub const allocateSlot = frame_lower.allocateSlot;
    pub const allocateIndex = frame_lower.allocateIndex;
    pub const allocateDynamicTemporaries = frame_lower.allocateDynamicTemporaries;
    pub const allocateNativeStorage = frame_lower.allocateNativeStorage;
    pub const allocateStorage = frame_lower.allocateStorage;
    pub const allocateTemporaries = frame_lower.allocateTemporaries;
    pub const dropOperand = frame_lower.dropOperand;
    pub const enterFrame = frame_lower.enterFrame;
    pub const frameBytes = frame_lower.frameBytes;
    pub const frameLeaf = frame_lower.frameLeaf;
    pub const frameMap = frame_lower.frameMap;
    pub const initializeStorage = frame_lower.initializeStorage;
    pub const leaveFrame = frame_lower.leaveFrame;
    pub const packArgument = frame_lower.packArgument;
    pub const packedCallback = frame_lower.packedCallback;
    pub const packedParameters = frame_lower.packedParameters;
    pub const possibleTemporaryBytes = frame_lower.possibleTemporaryBytes;
    pub const requireAccounting = frame_lower.requireAccounting;
    pub const returnStorageBytes = frame_lower.returnStorageBytes;
    pub const returnValue = frame_lower.returnValue;
    pub const zeroTracedLocal = frame_lower.zeroTracedLocal;
    const declaredTemporaryBytes = frame_module.declaredTemporaryBytes;
    /// Whether local `index` holds the address of a parameter this function
    /// only reads. Every other local holds its value.
    pub fn byReference(self: *Emitter, index: usize) bool {
        return index < self.by_reference.len and self.by_reference[index] != .none;
    }
    /// Whether local `index` holds an address into a managed list's backing
    /// storage rather than storage the frame itself owns. Such a slot is only
    /// meaningful across the inert run the borrow was proved over, so the root
    /// protocol never reads it.
    pub fn borrowsElement(self: *Emitter, index: usize) bool {
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
        if (self.callerStorage(index) and !try self.borrowableLocal(index, slot)) {
            // A `mut` array parameter is written through while this operand
            // could still be read, so the operand is a snapshot of the caller's
            // array exactly as an ordinary local's would be.
            const caller = try self.load("l", index);
            return self.print(" blit %v{d}, %agg{d}, {d}\n storel %agg{d}, %s{d}\n", .{ caller, self.pc, (try self.layout(ty)).size, self.pc, slot });
        }
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
        return self.borrowableAt(.{ .index = index, .slot = slot, .pc = self.pc });
    }
    /// `borrowableLocal` for a read of local `read.index` into operand slot
    /// `read.slot` by the instruction at `read.pc`, which the move planner
    /// (`qbe_moves.zig`) asks before any instruction is lowered.
    pub fn borrowableAt(self: *Emitter, read: LocalRead) GenerateError!bool {
        const index = read.index;
        const slot = read.slot;
        const value = try self.layout(self.function.scope.locals[index].ty);
        if (value.drop) return false;
        if (self.pendingReference(index, read.pc)) return false;
        // A zero-length aggregate copies nothing; it keeps the scratch the
        // frame protocol places after the entry block, because that scratch is
        // what stops QBE folding a null-like address into the load.
        if (value.size == 0) return false;
        // A match binding's elided COW rebind leaves this slot untouched.
        // Name its storage directly; storeLocal drops the redundant store.
        if (value_copy_lower.selfStore(self, read.pc + 2, index)) return true;
        // The consumer is the first instruction whose own execution leaves the
        // stack at or below the operand this read pushes. Every instruction
        // before it either pushed another operand above ours or read ours; in
        // both cases our value stayed in its frame slot, because nothing in the
        // window writes the local and no branch enters it without passing
        // through this read. A call in the window runs with this frame suspended
        // and reads the operand during its own execution, so the address it was
        // handed stays valid.
        var consumer = read.pc + 1;
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
        // A real value copy reads the source into private scratch before it
        // marks or replaces any collection. It consumes the source address.
        if (op == .value_copy) return value_copy_lower.copies(self, consumer);
        // A match arm's payload binding copies out of the scrutinee. Naming the
        // scrutinee's slot would copy a region onto itself, so that arm keeps
        // the scratch copy the other locals use.
        if (op == .switch_variant) for (op.switch_variant.arms) |arm| if (arm.slot) |target| if (@backingInt(target) == index) return false;
        return consumesOperand(op);
    }
    /// Whether local `index` is a `mut` fixed-array parameter, or under value
    /// semantics a `mut` record parameter (`VALUE-SEMANTICS-3`). Its slot holds
    /// the caller's address, as a read-only parameter's does, but this function
    /// writes the caller's value through it: an element or field write lands
    /// in the caller's variable, and no entry copy is ever taken.
    pub fn callerStorage(self: *Emitter, index: usize) bool {
        const signature = self.function.signature;
        if (index >= signature.parameter_count) return false;
        for (signature.declared_mutates) |position| if (position == index)
            return typed.referenceMut(self.program.records, self.function.scope.locals[index].ty);
        return false;
    }
    /// Whether an operand already on the stack below the read at this pc is a
    /// `ref_local` of local `index`: the call that consumes both will write
    /// through that address, so this read cannot name the same storage. The
    /// operands below were all pushed at or after the last instruction that ran
    /// with an empty stack, so the scan stops there.
    fn pendingReference(self: *Emitter, index: usize, at: usize) bool {
        const below = self.states[at] orelse return true;
        if (below.len == 0) return false;
        var pc = at;
        while (pc > 0) {
            pc -= 1;
            switch (self.function.scope.instructions[pc].op) {
                .ref_local => |target| if (@backingInt(target) == index) return true,
                else => {},
            }
            const before = self.states[pc] orelse return true;
            if (before.len == 0) return false;
        }
        return false;
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
            if (writtenLocal(f, index) and !self.callerStorage(index)) continue;
            flags[index] = .value;
        }
        if (runtime_mode.enabled()) return flags;
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
            .stand_in,
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
        for (0..self.function.scope.instructions.len) |pc| {
            if (self.states[pc] == null) continue;
            // COW-HOIST-1: the checks a loop's entry edges run come first.
            try cow_lower.Lower(Emitter).entry(self, pc);
            // QBE-LOOP-VERSION-1: a versioned loop's guard and check-free copy
            // go in front of its header; the original follows unchanged.
            if (self.loop_plan.at(pc)) |loop| {
                if (try loop_version.Lower(Emitter).emit(self, loop)) self.original = loop;
            }
            try self.emitAt(pc);
            if (self.original) |loop| if (pc == loop.back) {
                self.original = null;
            };
        }
    }
    /// The label prefix of a jump to `target`: inside the check-free copy a
    /// target in its loop is the copy's own instruction, inside the original
    /// copy the header is the original's (the guard took the ordinary label),
    /// and everything else is the ordinary instruction label.
    pub fn labelPrefix(self: *const Emitter, target: usize) []const u8 {
        if (cow_lower.Lower(Emitter).enters(self, target)) return "ce";
        if (self.version) |active| {
            if (target >= active.loop.head and target <= active.loop.back) return "fi";
        } else if (self.original) |loop| {
            if (target == loop.head) return "oi";
        }
        return "i";
    }
    /// Lower `jump_if_false target` with its condition in operand slot `h - 1`.
    fn conditionalJump(self: *Emitter, target: usize, h: usize) GenerateError!void {
        // QBE-LOOP-VERSION-1: a condition the guard proved false on every
        // iteration (a proven index's `< 0` test) always jumps.
        if (self.loopAction()) |action| if (action.effect == .taken) return self.print(jump_label, .{ self.labelPrefix(target), target });
        const v = try self.load("s", h - 1);
        try self.print(" jnz %v{d}, @next{d}, @{s}{d}\n", .{ v, self.serial, self.labelPrefix(target), target });
    }
    /// Open the block of the instruction at `pc` under label `@<prefix><pc>`.
    pub fn headerLabel(self: *Emitter, pc: usize, prefix: []const u8) GenerateError!void {
        // The position marker is not budget metadata: trap traces and
        // `assert` messages read the frame's current pc, so it is emitted
        // even where the step check is not.
        try self.print("@{s}{d}\n storel {d}, %position\n", .{ prefix, pc, pc });
    }
    /// What the check-free copy may assume at the current instruction, or
    /// null outside one (`QBE-LOOP-VERSION-1`).
    pub fn loopAction(self: *const Emitter) ?loop_facts.Action {
        const active = self.version orelse return null;
        if (self.pc < active.loop.head or self.pc > active.loop.back) return null;
        return active.loop.actions[self.pc - active.loop.head];
    }
    /// The element storage address the guard loaded for the current
    /// instruction's receiver, when the check-free copy may use it.
    pub fn loopStorage(self: *const Emitter) ?usize {
        const action = self.loopAction() orelse return null;
        const node = action.receiver orelse return null;
        return self.version.?.storages[node];
    }
    /// The element value the guard read for the current instruction, when the
    /// check-free copy may use it in place of the read.
    pub fn loopValue(self: *const Emitter) ?usize {
        const action = self.loopAction() orelse return null;
        const node = action.value orelse return null;
        return self.version.?.values[node];
    }
    /// The storage, length and generation a presized append at the current
    /// instruction writes through, when the check-free copy may skip its
    /// capacity test (`QBE-LOOP-VERSION-1`).
    pub fn loopAppend(self: *const Emitter) ?struct { storage: usize, state: loop_version.Appending } {
        const action = self.loopAction() orelse return null;
        if (action.effect != .presized) return null;
        const storage = self.loopStorage() orelse return null;
        return .{ .storage = storage, .state = self.version.?.appending orelse return null };
    }
    /// Whether a lowered check-free copy names an allocating callee, which
    /// would make it a safepoint its plan did not allow for.
    pub fn copyAllocates(_: *const Emitter, text: []const u8) bool {
        return loweredAllocates(text);
    }
    /// Lower the instruction at `pc` into its own block.
    pub fn emitAt(self: *Emitter, pc: usize) GenerateError!void {
        const instruction = self.function.scope.instructions[pc];
        const stack = self.states[pc] orelse return;
        {
            const own = if (self.version != null) "fi" else if (self.original != null and self.original.?.head == pc) "oi" else "i";
            try self.headerLabel(pc, own);
            if (self.step_checks) try self.step();
            self.pc = pc;
            try cow_lower.Lower(Emitter).before(self, pc, stack);
            self.expireFusedDecode(pc);
            // QBE-LOOP-VERSION-1: an instruction whose guards the loop's own
            // guard proved is lowered without them.
            const checks = self.checks;
            defer self.checks = checks;
            if (self.loopAction()) |action| if (action.unchecked) {
                self.checks = false;
            };
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
                .stand_in,
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
            try @import("qbe_rc_ops.zig").after(Emitter, self, instruction.op, stack);
            try cow_lower.Lower(Emitter).after(self, pc);
            try @import("qbe_rc_edges.zig").after(Emitter, self, instruction.op);
            // An instruction whose successor has a body falls through into it;
            // only a real terminator (or a successor that emits nothing) jumps.
            const falls = pc + 1 < self.states.len and self.states[pc + 1] != null;
            switch (instruction.op) {
                .ret, .jump, .jump_if_false, .switch_variant => {},
                else => if (!falls) try self.print(jump_label, .{ self.labelPrefix(pc + 1), pc + 1 }),
            }
            if (instruction.op == .jump_if_false) {
                if (falls) try self.print("@next{d}\n", .{self.serial}) else try self.print("@next{d}\n jmp @{s}{d}\n", .{ self.serial, self.labelPrefix(pc + 1), pc + 1 });
            }
        }
    }
    const root_lower = roots_module.Lower(Emitter);
    const value_copy_lower = @import("qbe_value_copy.zig").Lower(Emitter);
    /// Whether the `value_copy` at `pc` makes a real copy (`VALUE-SEMANTICS-2`).
    pub const valueCopies = value_copy_lower.copies;
    pub const needsRootProtocol = root_lower.needsRootProtocol;
    pub const restoreRoots = root_lower.restoreRoots;
    pub const rootLiveness = root_lower.rootLiveness;
    pub const rootedSafepoint = root_lower.rootedSafepoint;
    pub const roots = root_lower.roots;
    const allocates = roots_module.allocates;
    const pureCallee = roots_module.pureCallee;
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
        return value.kind == .record or value.kind == .array or value.kind == .variant or value.kind == .niche or value.kind == .domain;
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
    /// Record that `%v{value}` is the storage word of a managed container, the
    /// start of its element storage block, whose elements have `element`'s
    /// layout (LLVM-ELEMENT-CLASS-1). It says everything `markObject` says, and
    /// also that the block is an allocation of its own that no object header
    /// or payload overlaps, and that it only ever holds elements of one size
    /// and one kind: GC references (`r`) or plain values (`v`). The LLVM
    /// adapter gives such accesses their own alias scope per kind. A comment
    /// line, so QBE's assembly is byte-identical with or without it.
    pub fn markElements(self: *Emitter, value: usize, element: typed.Type) GenerateError!void {
        const shape = try self.layout(element);
        try self.print(" # myl-elem %v{d} {d}{s}\n", .{ value, shape.size, if (shape.copy == .reference) "r" else "v" });
    }
    /// Select case `tag` of the variant of type `ty` stored at `pointer`. A
    /// tagged variant stores the tag word at its start. A niche optional
    /// (QBE-NICHE-1) has no tag word: `None` is the null reference, stored
    /// here, and `Some` is selected by the payload write that follows.
    pub fn writeTag(self: *Emitter, ty: typed.Type, tag: usize, pointer: usize) GenerateError!void {
        const value = try self.layout(ty);
        if (value.kind != .niche) return self.print(" storew {d}, %v{d}\n", .{ tag, pointer });
        if (tag != value.fields[0].tag.?) try self.print(" storel 0, %v{d}\n", .{pointer});
    }
    /// Load the active case tag of the variant of type `ty` stored at
    /// `pointer` into a fresh `l` temporary. A niche optional's tag is whether
    /// its reference word is null (QBE-NICHE-1).
    pub fn readTag(self: *Emitter, ty: typed.Type, pointer: usize) GenerateError!usize {
        const value = try self.layout(ty);
        const tag = self.temp();
        if (value.kind != .niche) {
            try self.print(" %v{d} =l loaduw %v{d}\n", .{ tag, pointer });
            return tag;
        }
        const word = self.temp();
        const present: []const u8 = if (value.fields[0].tag.? == 1) "cnel" else "ceql";
        try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l {s} %v{d}, 0\n", .{ word, pointer, tag, present, word });
        return tag;
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
        }
        const pins = try cow_lower.Lower(Emitter).pinIndirect(self, signature, args, base + 1);
        if (packed_args) for (args, 0..) |arg, i| try self.packArgument(i, arg);
        const value = self.temp();
        const indirect = try self.largeValue(signature.return_type);
        try @import("qbe_rc_admission.zig").invoke(Emitter, self, signature.parameters, base + 1);
        try self.print(" %v{d} ={s} call %v{d}(l %ctx", .{ value, if (indirect) "l" else try self.abiType(signature.return_type), function_pointer });
        if (indirect) try self.print(", l %aux{d}", .{self.pc});
        if (packed_args) {
            try self.print(", l %arguments", .{});
        } else {
            for (args, signature.parameters) |arg, ty| try self.print(", {s} %v{d}", .{ try self.argumentType(ty), arg });
        }
        try self.print(")\n", .{});
        try cow_lower.Lower(Emitter).unpin(self, pins);
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
        }
        // COW-PIN-1: a list or dictionary a `mut` parameter receives stays
        // unshared until the call returns.
        const pins = try cow_lower.Lower(Emitter).pin(self, callee, args, h - count);
        if (packed_args) for (args, 0..) |arg, i| try self.packArgument(i, arg);
        try @import("qbe_rc_ops.zig").callEntry(Emitter, self, callee, h - count);
        const v = self.temp();
        const canonical = self.units[@backingInt(target)].symbol;
        const callee_symbol = if (try rc_borrow.certificate(Emitter, self, callee) != null) try rc_borrow.symbol(self.allocator, canonical) else canonical;
        try self.print(" %v{d} ={s} call ${s}(l %ctx", .{ v, try self.returnType(callee), callee_symbol });
        const indirect = try self.largeResult(callee);
        if (indirect) try self.print(", l %aux{d}", .{self.pc});
        if (packed_args) {
            try self.print(", l %arguments", .{});
        } else {
            for (args, callee.scope.locals[0..callee.signature.parameter_count]) |arg, local| try self.print(", {s} %v{d}", .{ try self.parameterType(local), arg });
        }
        try self.print(")\n", .{});
        try cow_lower.Lower(Emitter).unpin(self, pins);
        if (indirect) try self.print(" storel %aux{d}, %s{d}\n", .{ self.pc, h - count }) else try self.store(h - count, v);
    }
    /// Lower `store_local` of operand slot `h - 1` into local `slot`.
    fn storeLocal(self: *Emitter, slot: typed.LocalId, h: usize) GenerateError!void {
        const index = @backingInt(slot);
        if (value_copy_lower.selfStore(self, self.pc, index)) return;
        // QBE-MOVE-ELIDE-1: an alias's value already sits in the slot
        // it names, and an update written in place into this local's
        // own slot left nothing to copy.
        if (self.moves.aliased(index)) return;
        const ty = self.function.scope.locals[index].ty;
        // QBE-CTORFWD-1 and QBE-ARRAYWRITE-1: the instruction before
        // this store may already have written this local where it
        // lives — a constructor field by field, a `replace` one
        // element — leaving nothing to copy.
        const forwarded = self.moves.placed(self.pc) or try @import("qbe_aggregate.zig").storeForwarded(@TypeOf(self), self, self.pc, index);
        // QBE-ELEMENT-ADDRESS-1: an iteration local that names its
        // element in place holds the checked address the read produced,
        // so the store keeps that word instead of copying the element
        // into the frame and reading it back out of there.
        if (self.callerStorage(index)) {
            // A `mut` array parameter stores into the caller's array.
            if (!forwarded) {
                const caller = try self.load("l", index);
                try self.print(" blit %v{d}, %v{d}, {d}\n", .{ try self.load("s", h - 1), caller, (try self.layout(ty)).size });
            }
        } else if (self.byReference(index)) {
            try self.print(" storel %v{d}, %l{d}\n", .{ try self.load("s", h - 1), index });
        } else if (!forwarded) {
            const v = try self.load("s", h - 1);
            if ((try self.layout(ty)).drop) {
                try self.print(drop_local, .{ try self.descriptor(ty), index });
            }
            if (scalar(ty, self.program.records)) try self.print(" storel %v{d}, %l{d}\n", .{ v, index }) else try self.print(" blit %v{d}, %l{d}, {d}\n", .{ v, index, (try self.layout(ty)).size });
        }
        if (self.range_keys.role(self.pc) == .store) try range_keys.Lower(Emitter).store(self, index, h - 1);
    }
    fn emitOp(self: *Emitter, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) GenerateError!void {
        const h = stack.len;
        if (try @import("qbe_rc_locals.zig").emit(Emitter, self, op, stack)) return;
        switch (op) {
            .acquire_resource, .complete_resource, .resource_io, .restrict_resource, .dir_resource, .host_resource => try @import("qbe_resources.zig").Lower(Emitter).emit(self, op, stack),
            .external_read, .stand_in, .environment_get, .environment_only, .environment_names => try @import("qbe_boundaries.zig").emit(self, op, stack),
            .begin_arena, .end_arena, .arena_escape => try arena_lower.Lower(Emitter).emit(self, op, stack),
            .print => |output| try @import("qbe_io.zig").Lower(Emitter).emit(self, output, stack),
            .stream_write => |write| try @import("qbe_io.zig").Lower(Emitter).write(self, write, stack),
            .file_access => |call| try @import("qbe_files.zig").Lower(Emitter).access(self, call, stack),
            .file_method => |call| try @import("qbe_files.zig").Lower(Emitter).method(self, call, stack),
            .try_result => |propagate| {
                if (try @import("qbe_rc_aggregate.zig").propagation(Emitter, self, propagate, stack)) return;
                const source = try self.load("s", h - 1);
                const input_offset = (try self.layout(propagate.input)).payload_offset;
                if (typed.resultShape(propagate.input, self.program.records)) |input| {
                    const output = typed.resultShape(propagate.output, self.program.records).?;
                    const tag = try self.readTag(propagate.input, source);
                    const success = self.temp();
                    try self.print(" %v{d} =l ceql %v{d}, {d}\n", .{ success, tag, input.ok_tag });
                    try self.print(" jnz %v{d}, @tryok{d}, @tryerror{d}\n@tryerror{d}\n", .{ success, tag, tag, tag });
                    // ERROR-TRACE-1: a failing `?` appends its site to the trace.
                    try error_trace.Lower(Emitter).propagation(self, input, output);
                    const pointer = try self.aggregatePointer();
                    try self.writeTag(propagate.output, output.error_tag, pointer);
                    const slot = try self.address(pointer, (try self.layout(propagate.output)).payload_offset);
                    const payload = try self.readValue(try self.address(source, input_offset), input.error_type);
                    if (input.error_type == output.error_type) {
                        try self.writeValue(slot, payload, input.error_type);
                    } else {
                        // The error type is a case payload of the enclosing error union, so
                        // wrap the whole incoming error value in that case.
                        const error_tag = typed.wrappingCase(self.program.records, output.error_type, input.error_type) orelse return error.InternalError;
                        try self.writeTag(output.error_type, error_tag, slot);
                        try self.writeValue(try self.address(slot, (try self.layout(output.error_type)).payload_offset), payload, input.error_type);
                    }
                    for (stack[0 .. h - 1], 0..) |ty, slot_index| try self.dropOperand(slot_index, ty);
                    try self.store(0, pointer);
                    try self.print(" jmp @{s}{d}\n@tryok{d}\n", .{ self.labelPrefix(propagate.error_target), propagate.error_target, tag });
                    try self.store(h - 1, try self.readValue(try self.address(source, input_offset), input.ok_type));
                } else if (prelude.optionShape(propagate.input, self.program.records)) |input| {
                    const output = prelude.optionShape(propagate.output, self.program.records).?;
                    const tag = try self.readTag(propagate.input, source);
                    const success = self.temp();
                    try self.print(" %v{d} =l ceql %v{d}, {d}\n", .{ success, tag, input.some });
                    try self.print(" jnz %v{d}, @tryok{d}, @tryerror{d}\n@tryerror{d}\n", .{ success, tag, tag, tag });
                    const pointer = try self.aggregatePointer();
                    try self.writeTag(propagate.output, output.none, pointer);
                    for (stack[0 .. h - 1], 0..) |ty, slot| try self.dropOperand(slot, ty);
                    try self.store(0, pointer);
                    try self.print(" jmp @{s}{d}\n@tryok{d}\n", .{ self.labelPrefix(propagate.error_target), propagate.error_target, tag });
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
            .ref_local => |slot| {
                // The argument a `mut` array parameter receives: the address of
                // this frame's variable, or the caller's address a `mut` array
                // parameter of this function already holds.
                const index = @backingInt(slot);
                if (self.byReference(index)) try self.store(h, try self.load("l", index)) else try self.print(" storel %l{d}, %s{d}\n", .{ index, h });
            },
            .load_local, .move_local => |slot| {
                // QBE-MOVE-ELIDE-1: an alias reads the slot that holds its value
                // (an alias is never moved from, so a move resolves to itself).
                const index = self.moves.resolve(@backingInt(slot));
                const ty = self.function.scope.locals[index].ty;
                try self.readLocal(index, h);
                if (self.range_keys.role(self.pc) == .load) try range_keys.Lower(Emitter).load(self, index, h);
                if (op == .move_local and (try self.layout(ty)).drop) try self.zeroTracedLocal(index, ty);
            },
            .store_local => |slot| try self.storeLocal(slot, h),
            .drop_local => |slot| {
                const ty = self.function.scope.locals[@backingInt(slot)].ty;
                if ((try self.layout(ty)).drop) {
                    try self.print(drop_local, .{ try self.descriptor(ty), @backingInt(slot) });
                } else if ((try self.layout(ty)).trace) try self.zeroTracedLocal(@backingInt(slot), ty);
            },
            .pop, .acknowledge => try self.dropOperand(h - 1, stack[h - 1]),
            .wrap_domain, .unwrap_domain => {},
            .value_copy => |copy| try value_copy_lower.emit(self, copy, stack),
            .jump => |target| try self.print(jump_label, .{ self.labelPrefix(target), target }),
            .assert_true => |assertion| {
                const v = try self.load("s", h - 1);
                const failure = switch (assertion.kind) {
                    .statement => "myl_qbe_fail_assert",
                    .requires => "myl_qbe_fail_requires",
                    .ensures => "myl_qbe_fail_ensures",
                    .invariant => "myl_qbe_fail_invariant",
                };
                try self.require(v, failure);
            },
            .jump_if_false => |target| try self.conditionalJump(target, h),
            .ret => {
                const v = try self.load("s", h - 1);
                // ERROR-TRACE-1: a returned `Err` the code did not just build appends its site.
                try error_trace.Lower(Emitter).returning(self, v, self.isBranchTarget(self.pc));
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
