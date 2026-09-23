//! The frame map: call-site positions recovered from return addresses.
//!
//! A fast executable (no step and no frame accounting) links no frame record.
//! Its IL instead names, before every call, the bytecode position that call
//! belongs to (`dbgloc PC+1`). Both backends turn that into assembly the build
//! can read back:
//!
//! * QBE prints each `dbgloc` as a `.loc FILE LINE` directive. QBE never
//!   inlines, so the position is the whole story.
//! * The LLVM adapter attaches a debug location to each call whose
//!   discriminator is a pseudo-probe call index (`experiments/llvm-backend`).
//!   LLVM prints a `.pseudoprobe GUID INDEX ... [@ GUID:INDEX ...]` directive
//!   right before the call, and when it inlined guest functions into one
//!   another the `@` list names every caller the call was inlined through. A
//!   runtime helper LLVM inlines has no debug information of its own, so its
//!   calls carry the location — and the probe — of the call it replaced.
//!
//! `annotate` rewrites one assembly file: every positioned call is followed by
//! a local label, the `.file`/`.loc`/`.pseudoprobe` directives and the probe
//! descriptor sections are removed, and a table is appended with one entry per
//! logical frame of each call site — innermost first, each naming the unit's
//! metadata and the position. The runtime walks the frame-pointer chain when a
//! trap fires and looks each return address up there (`src/qbe_runtime.c`), so
//! no frame bookkeeping runs on the call path.
const std = @import("std");

/// The section the runtime reads through `__start_`/`__stop_` symbols.
pub const section = "mylang_frame_map";
/// `dbgloc` column that marks the entry guard's frame-failure call: the trace of
/// a stack-floor failure starts at the caller, exactly as when the record was
/// linked only after the guard, so the runtime skips a frame found here. The
/// LLVM adapter gives the same call probe index 0.
pub const guard_column: u32 = 1;
/// Bit set in an entry's position word for an entry-guard call site.
pub const guard_flag: u32 = 0x8000_0000;
/// Bit set in an entry's position word when the entry is a caller the previous
/// entry's function was inlined into, at this entry's position.
pub const caller_flag: u32 = 0x4000_0000;
/// Bit set in every entry of assembly that carries call-frame information
/// (`.cfi_startproc`): LLVM's, whose guest functions keep no frame pointer, so
/// the runtime unwinds such a program by its unwind tables. QBE keeps a frame
/// pointer and emits no CFI, and its entries leave the bit clear.
pub const unwind_flag: u32 = 0x2000_0000;

/// Failures while annotating assembly.
pub const Error = error{ OutOfMemory, FrameMapMismatch };

/// One logical frame of a call site: the unit it belongs to and its word.
const Frame = struct { unit: []const u8, word: u32 };
/// One positioned call: its return label and its frames, innermost first.
const Site = struct { label: usize, first: usize, count: usize };
/// A parsed `.pseudoprobe` directive: the innermost function's GUID and call
/// index, and the inlining callers from outermost to innermost.
const Probe = struct { guid: u64, index: u32, callers: []const Caller };
const Caller = struct { guid: u64, index: u32 };
/// A parsed `.loc` directive.
const Loc = struct { file: u32, line: u32, column: u32 };

/// Whether `line` is an x86-64 call instruction in AT&T syntax.
fn callInstruction(line: []const u8) bool {
    const trimmed = std.mem.trimStart(u8, line, " \t");
    inline for (.{ "callq", "call" }) |mnemonic| {
        if (std.mem.startsWith(u8, trimmed, mnemonic) and trimmed.len > mnemonic.len and
            (trimmed[mnemonic.len] == ' ' or trimmed[mnemonic.len] == '\t')) return true;
    }
    return false;
}

/// Whether `line` is a machine instruction rather than a directive, label or comment.
fn instruction(line: []const u8) bool {
    if (line.len == 0 or (line[0] != ' ' and line[0] != '\t')) return false;
    const trimmed = std.mem.trimStart(u8, line, " \t");
    return trimmed.len != 0 and trimmed[0] != '.' and trimmed[0] != '#';
}

/// The directive word a line starts with, after indentation.
fn directive(line: []const u8) []const u8 {
    const trimmed = std.mem.trimStart(u8, line, " \t");
    const end = std.mem.indexOfAny(u8, trimmed, " \t") orelse trimmed.len;
    return trimmed[0..end];
}

/// The symbol a non-local label line defines, or null. Local labels (`.L…`) and
/// numeric labels do not start a new function.
fn globalLabel(line: []const u8) ?[]const u8 {
    if (line.len == 0 or std.mem.indexOfScalar(u8, " \t.#", line[0]) != null) return null;
    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    const name = line[0..colon];
    if (name.len == 0 or std.ascii.isDigit(name[0])) return null;
    for (name) |byte| if (!symbolByte(byte)) return null;
    return name;
}

/// Whether `byte` may appear in an assembler symbol name.
fn symbolByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "_.$", byte) != null;
}

/// A numbered `.file N ["dir"] "name"` directive: its number and the last quoted
/// string, which is the file name the frontend set to the unit's symbol.
fn fileDirective(line: []const u8) ?struct { number: u32, name: []const u8 } {
    var tokens = std.mem.tokenizeAny(u8, std.mem.trimStart(u8, line, " \t"), " \t");
    _ = tokens.next();
    const number_text = tokens.next() orelse return null;
    const number = std.fmt.parseInt(u32, number_text, 10) catch return null;
    const last_quote = std.mem.lastIndexOfScalar(u8, line, '"') orelse return null;
    const first_quote = std.mem.lastIndexOfScalar(u8, line[0..last_quote], '"') orelse return null;
    return .{ .number = number, .name = line[first_quote + 1 .. last_quote] };
}

/// A `.loc FILE LINE [COLUMN] ...` directive's three numbers.
fn locDirective(line: []const u8) ?Loc {
    var tokens = std.mem.tokenizeAny(u8, std.mem.trimStart(u8, line, " \t"), " \t");
    _ = tokens.next();
    const file = std.fmt.parseInt(u32, tokens.next() orelse return null, 10) catch return null;
    const number = std.fmt.parseInt(u32, tokens.next() orelse return null, 10) catch return null;
    const column = if (tokens.next()) |text| std.fmt.parseInt(u32, text, 10) catch 0 else 0;
    return .{ .file = file, .line = number, .column = column };
}

/// A `.pseudoprobe GUID INDEX TYPE ATTR [DISCRIMINATOR] [@ GUID:INDEX ...] FN`
/// directive. The `@` list is printed outermost caller first.
fn probeDirective(allocator: std.mem.Allocator, line: []const u8) Error!?Probe {
    var tokens = std.mem.tokenizeAny(u8, std.mem.trimStart(u8, line, " \t"), " \t");
    _ = tokens.next();
    const guid = std.fmt.parseInt(u64, tokens.next() orelse return null, 10) catch return null;
    const index = std.fmt.parseInt(u32, tokens.next() orelse return null, 10) catch return null;
    var callers: std.ArrayList(Caller) = .empty;
    errdefer callers.deinit(allocator);
    var expect_site = false;
    while (tokens.next()) |token| {
        if (std.mem.eql(u8, token, "@")) {
            expect_site = true;
            continue;
        }
        if (!expect_site) continue;
        expect_site = false;
        const colon = std.mem.indexOfScalar(u8, token, ':') orelse return error.FrameMapMismatch;
        try callers.append(allocator, .{
            .guid = std.fmt.parseInt(u64, token[0..colon], 10) catch return error.FrameMapMismatch,
            .index = std.fmt.parseInt(u32, token[colon + 1 ..], 10) catch return error.FrameMapMismatch,
        });
    }
    return .{ .guid = guid, .index = index, .callers = try callers.toOwnedSlice(allocator) };
}

/// The operand of a `.quad`/`.byte`/`.ascii` data line.
fn operand(line: []const u8) []const u8 {
    const trimmed = std.mem.trimStart(u8, line, " \t");
    const space = std.mem.indexOfAny(u8, trimmed, " \t") orelse return "";
    return std.mem.trim(u8, trimmed[space..], " \t");
}

/// Everything one assembly file says about positions, gathered before the
/// sites are resolved: probe descriptors may follow the code that names them.
const Scan = struct {
    allocator: std.mem.Allocator,
    files: std.AutoHashMapUnmanaged(u32, []const u8) = .empty,
    names: std.AutoHashMapUnmanaged(u64, []const u8) = .empty,
    kept: std.ArrayList([]const u8) = .empty,
    /// Per positioned call, its index in `kept` and what named its position.
    calls: std.ArrayList(Call) = .empty,

    const Call = struct { line: usize, function: []const u8, loc: ?Loc, probe: ?Probe };

    fn deinit(self: *Scan) void {
        self.files.deinit(self.allocator);
        self.names.deinit(self.allocator);
        self.kept.deinit(self.allocator);
        for (self.calls.items) |call| if (call.probe) |probe| self.allocator.free(probe.callers);
        self.calls.deinit(self.allocator);
    }

    /// Read every line, keeping the ones the assembler still needs.
    fn read(self: *Scan, text: []const u8) Error!void {
        var function: []const u8 = "";
        var loc: ?Loc = null;
        var probe: ?Probe = null;
        errdefer if (probe) |pending| self.allocator.free(pending.callers);
        var descriptor = false;
        var guid: ?u64 = null;
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            const word = directive(line);
            if (std.mem.eql(u8, word, ".section") or std.mem.eql(u8, word, ".text") or std.mem.eql(u8, word, ".data") or std.mem.eql(u8, word, ".bss")) {
                descriptor = std.mem.indexOf(u8, line, ".pseudo_probe_desc") != null;
                guid = null;
                if (descriptor) continue;
            }
            if (descriptor) {
                try self.descriptorLine(word, line, &guid);
                continue;
            }
            if (std.mem.eql(u8, word, ".file")) {
                if (fileDirective(line)) |file| {
                    try self.files.put(self.allocator, file.number, file.name);
                    continue;
                }
            } else if (std.mem.eql(u8, word, ".loc")) {
                if (locDirective(line)) |parsed| {
                    loc = parsed;
                    continue;
                }
            } else if (std.mem.eql(u8, word, ".pseudoprobe")) {
                if (probe) |pending| self.allocator.free(pending.callers);
                probe = try probeDirective(self.allocator, line);
                continue;
            } else if (globalLabel(line)) |name| {
                function = name;
                loc = null;
            }
            try self.kept.append(self.allocator, line);
            if (!instruction(line)) continue;
            if (callInstruction(line) and (probe != null or (loc != null and loc.?.line != 0))) {
                try self.calls.append(self.allocator, .{ .line = self.kept.items.len - 1, .function = function, .loc = loc, .probe = probe });
                probe = null;
            }
            if (probe) |pending| self.allocator.free(pending.callers);
            probe = null;
        }
        if (probe) |pending| self.allocator.free(pending.callers);
    }

    /// One line of a `.pseudo_probe_desc` section: `.quad GUID`, `.quad HASH`,
    /// `.byte LENGTH`, `.ascii "NAME"`. Only the GUID and the name matter.
    fn descriptorLine(self: *Scan, word: []const u8, line: []const u8, guid: *?u64) Error!void {
        if (std.mem.eql(u8, word, ".quad") and guid.* == null) {
            // LLVM prints the descriptor's GUID as a signed 64-bit value and the
            // probe's as an unsigned one; both name the same bits.
            const text = operand(line);
            guid.* = std.fmt.parseInt(u64, text, 10) catch @bitCast(std.fmt.parseInt(i64, text, 10) catch return error.FrameMapMismatch);
        } else if (std.mem.eql(u8, word, ".ascii")) {
            const quoted = operand(line);
            if (quoted.len < 2 or quoted[0] != '"' or quoted[quoted.len - 1] != '"') return error.FrameMapMismatch;
            try self.names.put(self.allocator, guid.* orelse return error.FrameMapMismatch, quoted[1 .. quoted.len - 1]);
            guid.* = null;
        }
    }

    /// The frames of one positioned call, innermost first.
    fn frames(self: *Scan, call: Call, out: *std.ArrayList(Frame)) Error!void {
        if (call.probe) |probe| {
            const unit = self.names.get(probe.guid) orelse return error.FrameMapMismatch;
            const word: u32 = if (probe.index == 0) guard_flag else probe.index - 1;
            try out.append(self.allocator, .{ .unit = unit, .word = word });
            var index = probe.callers.len;
            while (index > 0) {
                index -= 1;
                const caller = probe.callers[index];
                if (caller.index == 0) return error.FrameMapMismatch;
                const name = self.names.get(caller.guid) orelse return error.FrameMapMismatch;
                try out.append(self.allocator, .{ .unit = name, .word = (caller.index - 1) | caller_flag });
            }
            return;
        }
        const at = call.loc.?;
        const unit = self.files.get(at.file) orelse return error.FrameMapMismatch;
        // Without a probe nothing was inlined around this call, so its position
        // must be the function it sits in: anything else would lose a frame.
        if (!std.mem.eql(u8, unit, call.function)) return error.FrameMapMismatch;
        const pc = at.line - 1;
        if (pc >= unwind_flag) return error.FrameMapMismatch;
        try out.append(self.allocator, .{ .unit = unit, .word = if (at.column == guard_column) pc | guard_flag else pc });
    }
};

/// Rewrite one assembly file for the frame map. Text with no position
/// directive at all is returned unchanged (as a copy), so a unit lowered under
/// any other protocol assembles exactly as before. A position that cannot be
/// resolved to a unit, or a call positioned in another unit's function without
/// an inlining record, fails the build rather than lose a frame from a trace.
pub fn annotate(allocator: std.mem.Allocator, text: []const u8) Error![]u8 {
    var scan: Scan = .{ .allocator = allocator };
    defer scan.deinit();
    try scan.read(text);
    if (scan.kept.items.len == std.mem.count(u8, text, "\n") + 1 and scan.calls.items.len == 0) return allocator.dupe(u8, text);
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(allocator);
    var sites: std.ArrayList(Site) = .empty;
    defer sites.deinit(allocator);
    var labels: std.AutoHashMapUnmanaged(usize, usize) = .empty;
    defer labels.deinit(allocator);
    for (scan.calls.items, 0..) |call, label| {
        const first = frames.items.len;
        try scan.frames(call, &frames);
        try sites.append(allocator, .{ .label = label, .first = first, .count = frames.items.len - first });
        try labels.put(allocator, call.line, label);
    }
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const w = &out.writer;
    for (scan.kept.items, 0..) |line, index| {
        if (index != 0) w.writeByte('\n') catch return error.OutOfMemory;
        w.writeAll(line) catch return error.OutOfMemory;
        if (labels.get(index)) |label| w.print("\n.Lmyl_fm_{d}:", .{label}) catch return error.OutOfMemory;
    }
    if (sites.items.len != 0) {
        const unwind: u32 = if (std.mem.indexOf(u8, text, ".cfi_startproc") != null) unwind_flag else 0;
        w.print("\n\t.section\t{s},\"aR\",@progbits\n\t.p2align\t2\n", .{section}) catch return error.OutOfMemory;
        for (sites.items) |site| {
            for (frames.items[site.first .. site.first + site.count]) |frame| {
                w.print("\t.long\t.Lmyl_fm_{d}-.\n\t.long\t{d}\n\t.long\t{s}_meta-.\n", .{ site.label, frame.word | unwind, frame.unit }) catch return error.OutOfMemory;
            }
        }
    }
    return out.toOwnedSlice() catch error.OutOfMemory;
}

/// Whether an IL unit was lowered for the frame map, which is what decides
/// whether its assembly needs `annotate` and whether a full-LTO link must go
/// through assembly first.
pub fn usesFrameMap(il: []const u8) bool {
    return std.mem.startsWith(u8, il, "dbgfile ") or std.mem.indexOf(u8, il, "\ndbgfile ") != null;
}

// spec: QBE-FRAMEMAP-ASM-1
test "a positioned call gets a return label and a table entry naming its unit" {
    const a = std.testing.allocator;
    const input = ".file 1 \"myl_f_ab\"\n.text\n.globl myl_f_ab\nmyl_f_ab:\n\tpushq %rbp\n" ++
        "\t.loc 1 8\n\tcallq myl_f_cd\n\t.loc 1 1 1\n\tcallq myl_qbe_fail_frame\n\t.loc 1 0 0\n\tcallq memcpy\n\tret";
    const output = try annotate(a, input);
    defer a.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, ".loc") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".file") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "callq myl_f_cd\n.Lmyl_fm_0:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "callq myl_qbe_fail_frame\n.Lmyl_fm_1:") != null);
    // A call with no position (line 0) is not a site.
    try std.testing.expect(std.mem.indexOf(u8, output, "callq memcpy\n.Lmyl_fm") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\t.long\t.Lmyl_fm_0-.\n\t.long\t7\n\t.long\tmyl_f_ab_meta-.\n") != null);
    // The guard column sets the guard bit of the position word.
    try std.testing.expect(std.mem.indexOf(u8, output, "\t.long\t.Lmyl_fm_1-.\n\t.long\t2147483648\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".section\tmylang_frame_map,\"aR\",@progbits") != null);
}

// spec-case: QBE-FRAMEMAP-ASM-1
test "an inlined call names every frame it was inlined through, innermost first" {
    const a = std.testing.allocator;
    const input = "\t.text\nmain:\n\t.pseudoprobe\t200 3 2 0 @ 100:7 main\n\tcallq\tfail\n" ++
        "\t.pseudoprobe\t200 0 2 0 @ 100:9 main\n\tcallq\tmyl_qbe_fail_frame\n" ++
        "\t.section\t.pseudo_probe_desc,\"G\",@progbits,.pseudo_probe_desc_f,comdat\n\t.quad\t100\n\t.quad\t0\n\t.byte\t7\n\t.ascii\t\"myl_f_a\"\n" ++
        "\t.section\t.pseudo_probe_desc,\"G\",@progbits,.pseudo_probe_desc_g,comdat\n\t.quad\t200\n\t.quad\t0\n\t.byte\t7\n\t.ascii\t\"myl_f_b\"\n" ++
        "\t.section\t.pseudo_probe_desc,\"G\",@progbits,.pseudo_probe_desc_h,comdat\n\t.quad\t-2\n\t.quad\t0\n\t.byte\t7\n\t.ascii\t\"myl_f_c\"\n" ++
        "\t.text\nother:\n\t.pseudoprobe\t18446744073709551614 5 2 0 other\n\tcallq\tg\n";
    const output = try annotate(a, input);
    defer a.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "pseudo") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\t.long\t.Lmyl_fm_0-.\n\t.long\t2\n\t.long\tmyl_f_b_meta-.\n\t.long\t.Lmyl_fm_0-.\n\t.long\t1073741830\n\t.long\tmyl_f_a_meta-.\n") != null);
    // Probe index 0 is the inlined callee's entry guard; its caller is reported.
    try std.testing.expect(std.mem.indexOf(u8, output, "\t.long\t.Lmyl_fm_1-.\n\t.long\t2147483648\n\t.long\tmyl_f_b_meta-.\n\t.long\t.Lmyl_fm_1-.\n\t.long\t1073741832\n") != null);
    // A descriptor GUID printed signed names the same function as its unsigned probe.
    try std.testing.expect(std.mem.indexOf(u8, output, "\t.long\t.Lmyl_fm_2-.\n\t.long\t4\n\t.long\tmyl_f_c_meta-.\n") != null);
}

// spec-case: QBE-FRAMEMAP-ASM-1
test "assembly with call-frame information marks its entries for the unwinder" {
    const a = std.testing.allocator;
    const input = ".file 1 \"myl_f_ab\"\nmyl_f_ab:\n\t.cfi_startproc\n\t.loc 1 8\n\tcallq g\n\t.cfi_endproc\n";
    const output = try annotate(a, input);
    defer a.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "\t.long\t.Lmyl_fm_0-.\n\t.long\t536870919\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".cfi_startproc") != null);
}

// spec-case: QBE-FRAMEMAP-ASM-1
test "assembly without positions is left exactly as it was" {
    const a = std.testing.allocator;
    const input = ".text\n.globl f\nf:\n\tcallq g\n\tret\n";
    const output = try annotate(a, input);
    defer a.free(output);
    try std.testing.expectEqualStrings(input, output);
    try std.testing.expect(!usesFrameMap(input));
    try std.testing.expect(usesFrameMap("dbgfile \"myl_f_ab\"\nexport function"));
}

// spec-case: QBE-FRAMEMAP-ASM-1
test "a call positioned in another unit's file without an inlining record fails the build" {
    const a = std.testing.allocator;
    const inlined = ".file 1 \"myl_f_callee\"\nmyl_f_caller:\n\t.loc 1 4 0\n\tcallq h\n";
    try std.testing.expectError(error.FrameMapMismatch, annotate(a, inlined));
    const unnamed = "main:\n\t.pseudoprobe\t999 3 2 0 main\n\tcallq\tfail\n";
    try std.testing.expectError(error.FrameMapMismatch, annotate(a, unnamed));
}

// spec-case: QBE-FRAMEMAP-ASM-1
test "probeDirective reads an inline stack and refuses a malformed caller" {
    const a = std.testing.allocator;
    const probe = (try probeDirective(a, "\t.pseudoprobe\t5 3 2 0 @ 1:4 @ 2:6 main")).?;
    defer a.free(probe.callers);
    try std.testing.expectEqual(@as(u64, 5), probe.guid);
    try std.testing.expectEqual(@as(u32, 3), probe.index);
    try std.testing.expectEqual(@as(usize, 2), probe.callers.len);
    try std.testing.expectEqual(@as(u32, 6), probe.callers[1].index);
    try std.testing.expectError(error.FrameMapMismatch, probeDirective(a, "\t.pseudoprobe\t5 3 2 0 @ 1-4 main"));
}
