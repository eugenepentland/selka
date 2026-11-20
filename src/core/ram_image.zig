//! The image check of `@freestanding(ram)` functions (MCU-NOC2B). The check at check time (`../freestanding.zig`) proves
//! that a `ram` function calls only `ram` functions, `extern func`s and inline built-ins; it cannot see what the code
//! generator adds: a call of a library routine (`__aeabi_uidiv` for a division, `__aeabi_lmul`, `memcpy` for a record
//! copy), a jump table, a constant placed in read-only data. So after a device link the linked ELF is read, and every
//! address the code of each `ram` function refers to must lie in RAM or outside the image's flash.
//!
//! - **RAM** is an allocated section that is writable, that is loaded somewhere else than it runs (its segment's load
//!   address is not its address: start-up copies it from flash), or that lies within the initialised data: the extent from
//!   `__data_start` to `__data_end`, which every bare linker script defines for start-up (`runtime/bare/core_bare.c`) and
//!   which the program writes as it runs, so it is RAM whatever copies it. The last rule is for an image that runs from RAM
//!   (the boot ROM loads it straight into RAM, `__data_load == __data_start`): its `.data` holds only `.ramfunc` code when
//!   the program has no initialised variable, and a section of code only is neither writable nor loaded elsewhere. It
//!   cannot count `.text` or `.rodata`, which no script puts inside the data extent. `.ramfunc` goes first in `.data` in
//!   the library's linker scripts, so a `ram` function is in RAM; one that is not (a device script that never placed
//!   `.ramfunc`, or placed it with the code in flash) is refused.
//! - **Flash** is every other allocated section with contents: `.vectors`, `.text`, `.rodata`. On QEMU those are in RAM
//!   too, and the check treats them as a device's flash, so a program proved on QEMU keeps the promise on a device.
//! - Anything else (a peripheral, the ROM, the stack) is outside the image and allowed.
//!
//! Code is told from data by the ARM mapping symbols the assembler writes (`$t` starts Thumb code, `$d` data: AAELF32
//! 5.5.5); an image without them is refused, since the check could not tell them apart. In code, every `bl`, `b`, `cbz`,
//! literal `ldr` and `adr` is decoded and its target checked; a call that reaches a linker thunk (`__*Thunk_NAME`, put in
//! RAM beside its caller) is checked at `NAME`. In data (a literal pool, an inline table), every word whose value lies in
//! flash is taken for an address and refused, conservatively: an integer constant equal to a flash address is refused too.
//! One exception: the address of a fault's source path (a failed check passes it in `r1`, `freestanding_emitted.zig`), which
//! the function never reads, recognised as a word pointing at one of the program's path strings.
//! An indirect branch (`bx rN`, `blx rN`) is not followed: its target comes from a register, which a `ram` function fills
//! only from its literal data (checked), its parameters or RAM; Selka has no function value in freestanding code.
const std = @import("std");
const product = @import("selka").product;

/// What a reference from a `ram` function's code is, for the message.
pub const Kind = enum {
    /// A `bl` to code in flash.
    call,
    /// A `b` or `cbz` to code in flash.
    branch,
    /// A literal `ldr` of a word in flash.
    read,
    /// An `adr`, or a word of the function's literal data, that holds an address in flash.
    address,
    /// The function itself is not in RAM: the linker script did not place `.ramfunc` there.
    unplaced,
    /// The image has no mapping symbols, so code cannot be told from data.
    unmapped,
    /// The output is not a 32-bit little-endian ARM ELF the check can read.
    unreadable,
};

/// One broken promise: the `ram` function (its symbol), what it does, where in it, the address it reaches and the symbol and
/// section there (empty when none).
pub const Finding = struct { function: []const u8, kind: Kind, at: u32 = 0, target: u32 = 0, symbol: []const u8 = "", section: []const u8 = "" };

/// The image to check: its bytes, the symbols of the `ram` functions (`my.NAME`) and the program's source paths, which a
/// fault's `r1` points at.
pub const Request = struct { elf: []const u8, functions: []const []const u8, paths: []const []const u8 };

const Section = struct { name: []const u8, kind: u32, addr: u32, offset: u32, size: u32, alloc: bool, ram: bool };
const Symbol = struct { name: []const u8, value: u32, size: u32, info: u8, section: u16 };

const shf_write = 1;
const shf_alloc = 2;
const sht_symtab = 2;
const sht_nobits = 8;
const stt_func = 2;
const em_arm = 40;

const Malformed = error{Malformed};

fn word(bytes: []const u8, at: u64) Malformed!u32 {
    if (at + 4 > bytes.len) return error.Malformed;
    return std.mem.readInt(u32, bytes[@intCast(at)..][0..4], .little);
}

fn half(bytes: []const u8, at: u64) Malformed!u16 {
    if (at + 2 > bytes.len) return error.Malformed;
    return std.mem.readInt(u16, bytes[@intCast(at)..][0..2], .little);
}

fn cString(bytes: []const u8, at: u64) []const u8 {
    if (at >= bytes.len) return "";
    const rest = bytes[@intCast(at)..];
    return rest[0 .. std.mem.indexOfScalar(u8, rest, 0) orelse rest.len];
}

/// Where an address is.
const Place = enum { outside, ram, flash };

const Image = struct {
    elf: []const u8,
    sections: []const Section,
    symbols: []const Symbol,

    fn read(a: std.mem.Allocator, elf: []const u8) (Malformed || error{OutOfMemory})!Image {
        if (elf.len < 52 or !std.mem.eql(u8, elf[0..4], "\x7fELF") or elf[4] != 1 or elf[5] != 1) return error.Malformed;
        if (try half(elf, 18) != em_arm) return error.Malformed;
        const sections = try readSections(a, elf);
        const symbols = try readSymbols(a, elf, sections);
        if (dataExtent(symbols)) |extent| for (sections) |*section| {
            if (section.alloc and section.size != 0 and section.addr >= extent.start and @as(u64, section.addr) + section.size <= extent.end) section.ram = true;
        };
        return .{ .elf = elf, .sections = sections, .symbols = symbols };
    }

    fn sectionOf(self: Image, address: u32) ?Section {
        for (self.sections) |section| {
            if (section.alloc and section.size != 0 and address >= section.addr and address - section.addr < section.size) return section;
        }
        return null;
    }

    fn place(self: Image, address: u32) Place {
        const section = self.sectionOf(address) orelse return .outside;
        return if (section.ram) .ram else .flash;
    }

    /// The name of the symbol that holds `address`: one whose extent covers it, else the nearest one before it in its section.
    fn symbolAt(self: Image, address: u32) []const u8 {
        var nearest: ?Symbol = null;
        for (self.symbols) |symbol| {
            if (symbol.name.len == 0 or mapping(symbol.name) != null or symbol.info & 0xf > stt_func) continue;
            const start = symbol.value & ~@as(u32, 1);
            if (start > address) continue;
            if (symbol.size != 0 and address - start < symbol.size) return symbol.name;
            if (nearest == null or start > nearest.?.value & ~@as(u32, 1)) nearest = symbol;
        }
        const found = nearest orelse return "";
        const section = self.sectionOf(address) orelse return "";
        const start = found.value & ~@as(u32, 1);
        return if (start >= section.addr) found.name else "";
    }

    fn bytesAt(self: Image, address: u32, length: u32) ?[]const u8 {
        const section = self.sectionOf(address) orelse return null;
        if (section.kind == sht_nobits or address - section.addr + @as(u64, length) > section.size) return null;
        const at = @as(u64, section.offset) + (address - section.addr);
        if (at + length > self.elf.len) return null;
        return self.elf[@intCast(at)..][0..length];
    }

    fn find(self: Image, name: []const u8) ?Symbol {
        for (self.symbols) |symbol| if (std.mem.eql(u8, symbol.name, name)) return symbol;
        return null;
    }
};

fn readSections(a: std.mem.Allocator, elf: []const u8) (Malformed || error{OutOfMemory})![]Section {
    const table = try word(elf, 32);
    const entry = try half(elf, 46);
    const count = try half(elf, 48);
    const names_index = try half(elf, 50);
    if (names_index >= count) return error.Malformed;
    const names_offset = try word(elf, @as(u64, table) + @as(u64, names_index) * entry + 16);
    const segments = try readSegments(a, elf);
    const sections = try a.alloc(Section, count);
    for (sections, 0..) |*section, index| {
        const header = @as(u64, table) + index * entry;
        const flags = try word(elf, header + 8);
        const addr = try word(elf, header + 12);
        const size = try word(elf, header + 20);
        const alloc = flags & shf_alloc != 0;
        section.* = .{
            .name = cString(elf, @as(u64, names_offset) + try word(elf, header)),
            .kind = try word(elf, header + 4),
            .addr = addr,
            .offset = try word(elf, header + 16),
            .size = size,
            .alloc = alloc,
            .ram = alloc and (flags & shf_write != 0 or copied(segments, addr)),
        };
    }
    return sections;
}

/// A loadable segment: where it runs (`vaddr`, `memsz` bytes) and where it is loaded (`paddr`).
const Segment = struct { vaddr: u32, paddr: u32, memsz: u32 };

fn readSegments(a: std.mem.Allocator, elf: []const u8) (Malformed || error{OutOfMemory})![]Segment {
    const table = try word(elf, 28);
    const entry = try half(elf, 42);
    const count = try half(elf, 44);
    var list: std.ArrayList(Segment) = .empty;
    for (0..count) |index| {
        const header = @as(u64, table) + index * entry;
        const load = 1;
        if (try word(elf, header) != load) continue;
        try list.append(a, .{ .vaddr = try word(elf, header + 8), .paddr = try word(elf, header + 12), .memsz = try word(elf, header + 20) });
    }
    return list.items;
}

/// The initialised data's extent, `__data_start` up to `__data_end`: null when the image defines no such pair, or an empty one.
fn dataExtent(symbols: []const Symbol) ?struct { start: u32, end: u32 } {
    var start: ?u32 = null;
    var end: ?u32 = null;
    for (symbols) |symbol| {
        if (std.mem.eql(u8, symbol.name, "__data_start")) start = symbol.value;
        if (std.mem.eql(u8, symbol.name, "__data_end")) end = symbol.value;
    }
    const from = start orelse return null;
    const to = end orelse return null;
    return if (to > from) .{ .start = from, .end = to } else null;
}

/// Whether the segment that runs at `address` is loaded elsewhere: start-up copies it there from flash.
fn copied(segments: []const Segment, address: u32) bool {
    for (segments) |segment| {
        if (address >= segment.vaddr and address - segment.vaddr < segment.memsz) return segment.paddr != segment.vaddr;
    }
    return false;
}

fn readSymbols(a: std.mem.Allocator, elf: []const u8, sections: []const Section) (Malformed || error{OutOfMemory})![]Symbol {
    const table = try word(elf, 32);
    const entry = try half(elf, 46);
    var list: std.ArrayList(Symbol) = .empty;
    for (sections, 0..) |section, index| {
        if (section.kind != sht_symtab) continue;
        const link = try word(elf, @as(u64, table) + index * entry + 24);
        if (link >= sections.len) return error.Malformed;
        const strings = sections[link].offset;
        var at: u64 = section.offset;
        while (at + 16 <= @as(u64, section.offset) + section.size) : (at += 16) {
            try list.append(a, .{
                .name = cString(elf, @as(u64, strings) + try word(elf, at)),
                .value = try word(elf, at + 4),
                .size = try word(elf, at + 8),
                .info = if (at + 12 < elf.len) elf[@intCast(at + 12)] else 0,
                .section = try half(elf, at + 14),
            });
        }
    }
    return list.items;
}

/// Whether `name` is a mapping symbol, and whether it starts code (`$t`, `$a`) or data (`$d`).
fn mapping(name: []const u8) ?bool {
    if (name.len < 2 or name[0] != '$' or (name.len > 2 and name[2] != '.')) return null;
    return switch (name[1]) {
        't', 'a' => true,
        'd' => false,
        else => null,
    };
}

/// One stretch of a function: code or data.
const Mark = struct { at: u32, code: bool };

fn markOrder(_: void, left: Mark, right: Mark) bool {
    return left.at < right.at;
}

/// The first broken promise of the `ram` functions in `request.elf`, or null when every one keeps it. A function the image
/// does not hold (inlined into its every caller and removed) is not checked: its code is in its callers. A function LLVM
/// cloned (`my.NAME.constprop.0`) is checked under its own name too.
pub fn check(a: std.mem.Allocator, request: Request) error{OutOfMemory}!?Finding {
    if (request.functions.len == 0) return null;
    const image = Image.read(a, request.elf) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.Malformed => .{ .function = request.functions[0], .kind = .unreadable },
    };
    // A stripped image has no symbols to find the functions by.
    if (image.symbols.len == 0) return .{ .function = request.functions[0], .kind = .unmapped };
    var scan: Scan = .{ .a = a, .image = image, .paths = request.paths };
    for (request.functions) |function| {
        for (image.symbols) |symbol| {
            if (symbol.info & 0xf != stt_func or !clone(symbol.name, function)) continue;
            if (try scan.function(function, symbol)) |found| return found;
        }
    }
    return null;
}

/// Whether symbol `name` is `function` or a clone LLVM made of it (`function.SUFFIX`).
fn clone(name: []const u8, function: []const u8) bool {
    return std.mem.startsWith(u8, name, function) and (name.len == function.len or name[function.len] == '.');
}

const Scan = struct {
    a: std.mem.Allocator,
    image: Image,
    paths: []const []const u8,
    /// The function being scanned: its name and extent.
    name: []const u8 = "",
    start: u32 = 0,
    end: u32 = 0,

    fn function(self: *Scan, name: []const u8, symbol: Symbol) error{OutOfMemory}!?Finding {
        self.name = name;
        self.start = symbol.value & ~@as(u32, 1);
        self.end = self.start +| symbol.size;
        const home = self.image.sectionOf(self.start);
        if (home == null or !home.?.ram) return .{ .function = name, .kind = .unplaced, .target = self.start, .section = if (home) |section| section.name else "" };
        var marks: std.ArrayList(Mark) = .empty;
        var mapped = false;
        for (self.image.symbols) |candidate| {
            const code = mapping(candidate.name) orelse continue;
            mapped = true;
            if (candidate.section != symbol.section or candidate.value < self.start or candidate.value >= self.end) continue;
            try marks.append(self.a, .{ .at = candidate.value, .code = code });
        }
        if (!mapped) return .{ .function = name, .kind = .unmapped, .target = self.start, .section = home.?.name };
        std.mem.sort(Mark, marks.items, {}, markOrder);
        // A Thumb function starts in code unless a mapping symbol at its first byte says otherwise.
        var from = self.start;
        var code = true;
        for (marks.items) |mark| {
            if (mark.at > from) if (try self.stretch(from, mark.at, code)) |found| return found;
            from = @max(from, mark.at);
            code = mark.code;
        }
        return self.stretch(from, self.end, code);
    }

    fn stretch(self: *Scan, from: u32, to: u32, code: bool) error{OutOfMemory}!?Finding {
        const bytes = self.image.bytesAt(from, to - from) orelse return null;
        return if (code) self.instructions(from, bytes) else self.data(from, bytes);
    }

    /// Decode the Thumb instructions in `bytes` (at `base`) and check the address each one that names one reaches.
    fn instructions(self: *Scan, base: u32, bytes: []const u8) ?Finding {
        var offset: usize = 0;
        while (offset + 2 <= bytes.len) {
            const at = base + @as(u32, @intCast(offset));
            const first = std.mem.readInt(u16, bytes[offset..][0..2], .little);
            const wide = first >> 11 == 0b11101 or first >> 11 == 0b11110 or first >> 11 == 0b11111;
            if (wide and offset + 4 > bytes.len) break;
            const reference = if (wide) wideReference(at, first, std.mem.readInt(u16, bytes[offset + 2 ..][0..2], .little)) else narrowReference(at, first);
            offset += if (wide) 4 else 2;
            const found = reference orelse continue;
            if (self.reach(found.kind, at, found.target)) |broken| return broken;
        }
        return null;
    }

    /// Check every word of the data in `bytes` (at `base`): one whose value lies in flash is an address the code holds.
    fn data(self: *Scan, base: u32, bytes: []const u8) ?Finding {
        var offset: usize = (4 - base % 4) % 4;
        while (offset + 4 <= bytes.len) : (offset += 4) {
            const value = std.mem.readInt(u32, bytes[offset..][0..4], .little);
            const target = if (self.image.place(value) == .flash) value else value & ~@as(u32, 1);
            if (self.image.place(target) != .flash or self.faultPath(target)) continue;
            return self.finding(.address, base + @as(u32, @intCast(offset)), target);
        }
        return null;
    }

    /// Whether `address` is the first byte of one of the program's source paths, NUL-terminated: what a fault passes in `r1`.
    fn faultPath(self: *Scan, address: u32) bool {
        for (self.paths) |path| {
            const bytes = self.image.bytesAt(address, @intCast(path.len + 1)) orelse continue;
            if (std.mem.eql(u8, bytes[0..path.len], path) and bytes[path.len] == 0) return true;
        }
        return false;
    }

    /// The finding for `kind` at `at` reaching `target`, or null when `target` is the function itself, in RAM (a thunk there
    /// is followed to the symbol it calls) or outside the image.
    fn reach(self: *Scan, kind: Kind, at: u32, target: u32) ?Finding {
        if (target >= self.start and target < self.end) return null;
        switch (self.image.place(target)) {
            .outside => return null,
            .flash => return self.finding(kind, at, target),
            .ram => {
                if (kind != .call and kind != .branch) return null;
                const holder = self.image.symbolAt(target);
                const marker = "Thunk_";
                const split = std.mem.lastIndexOf(u8, holder, marker) orelse return null;
                if (!std.mem.startsWith(u8, holder, "__")) return null;
                const called = self.image.find(holder[split + marker.len ..]) orelse return self.finding(kind, at, target);
                const address = called.value & ~@as(u32, 1);
                return if (self.image.place(address) == .flash) self.finding(kind, at, address) else null;
            },
        }
    }

    fn finding(self: *Scan, kind: Kind, at: u32, target: u32) Finding {
        const section = self.image.sectionOf(target);
        return .{ .function = self.name, .kind = kind, .at = at, .target = target, .symbol = self.image.symbolAt(target), .section = if (section) |s| s.name else "" };
    }
};

/// An address an instruction names: a branch or call target, a literal it loads or an address it forms.
const Reference = struct { kind: Kind, target: u32 };

fn signExtend(value: u32, bits: u5) u32 {
    const shift: u5 = @intCast(32 - @as(u6, bits));
    return @bitCast(@as(i32, @bitCast(value << shift)) >> shift);
}

/// The address a 16-bit Thumb instruction at `at` names, if any: `b<cond>`, `b`, `cbz`/`cbnz`, a literal `ldr`, `adr`.
fn narrowReference(at: u32, instruction: u16) ?Reference {
    const pc = at +% 4;
    const aligned = pc & ~@as(u32, 3);
    if (instruction & 0xf000 == 0xd000 and (instruction >> 8) & 0xf < 0xe)
        return .{ .kind = .branch, .target = pc +% (signExtend(instruction & 0xff, 8) << 1) };
    if (instruction & 0xf800 == 0xe000) return .{ .kind = .branch, .target = pc +% (signExtend(instruction & 0x7ff, 11) << 1) };
    if (instruction & 0xf500 == 0xb100) return .{ .kind = .branch, .target = pc + ((((instruction >> 9) & 1) << 6) | (((instruction >> 3) & 0x1f) << 1)) };
    if (instruction & 0xf800 == 0x4800) return .{ .kind = .read, .target = aligned + (@as(u32, instruction & 0xff) << 2) };
    if (instruction & 0xf800 == 0xa000) return .{ .kind = .address, .target = aligned + (@as(u32, instruction & 0xff) << 2) };
    return null;
}

/// The address a 32-bit Thumb instruction at `at` names, if any: `bl`, `b.w` (both conditions) and a literal `ldr.w`.
fn wideReference(at: u32, first: u16, second: u16) ?Reference {
    const pc = at +% 4;
    if (first & 0xf800 == 0xf000 and second & 0x8000 == 0x8000) {
        const s: u32 = (first >> 10) & 1;
        const j1: u32 = (second >> 13) & 1;
        const j2: u32 = (second >> 11) & 1;
        if (second & 0x5000 == 0x0000) {
            // `b<cond>.w` (T3): S:J2:J1:imm6:imm11:0.
            if ((first >> 6) & 0xe == 0xe) return null;
            const offset = (s << 20) | (j2 << 19) | (j1 << 18) | (@as(u32, first & 0x3f) << 12) | (@as(u32, second & 0x7ff) << 1);
            return .{ .kind = .branch, .target = pc +% signExtend(offset, 21) };
        }
        // `bl` (T1) and `b.w` (T4): S:I1:I2:imm10:imm11:0 with I = not (J xor S).
        const offset = (s << 24) | ((~(j1 ^ s) & 1) << 23) | ((~(j2 ^ s) & 1) << 22) | (@as(u32, first & 0x3ff) << 12) | (@as(u32, second & 0x7ff) << 1);
        const kind: Kind = if (second & 0x5000 == 0x5000) .call else if (second & 0x5000 == 0x1000) .branch else return null;
        return .{ .kind = kind, .target = pc +% signExtend(offset, 25) };
    }
    if (first & 0xff7f == 0xf85f) {
        const aligned = pc & ~@as(u32, 3);
        const distance: u32 = second & 0xfff;
        return .{ .kind = .read, .target = if (first & 0x80 != 0) aligned +% distance else aligned -% distance };
    }
    return null;
}

/// What a library routine of the Arm run-time ABI (or compiler-rt) does, for the advice: the operation that needs it.
fn routine(symbol: []const u8) ?[]const u8 {
    const Row = struct { prefix: []const u8, what: []const u8 };
    const rows = [_]Row{
        .{ .prefix = "__aeabi_uidiv", .what = "a division or remainder (`//`, `%`) of 32-bit integers by a value that is not a constant: this CPU has no divide instruction. Divide by a constant (a power of two becomes a shift), or call an `extern func` whose C is in `.ramfunc`" },
        .{ .prefix = "__aeabi_idiv", .what = "a division or remainder (`//`, `%`) of 32-bit integers by a value that is not a constant: this CPU has no divide instruction. Divide by a constant (a power of two becomes a shift), or call an `extern func` whose C is in `.ramfunc`" },
        .{ .prefix = "__aeabi_uldivmod", .what = "a division or remainder of 64-bit integers (`int`, `i64`, `u64`): use 32-bit integers and a constant divisor" },
        .{ .prefix = "__aeabi_ldivmod", .what = "a division or remainder of 64-bit integers (`int`, `i64`, `u64`): use 32-bit integers and a constant divisor" },
        .{ .prefix = "__aeabi_lmul", .what = "a multiplication of 64-bit integers (`int`, `i64`, `u64`), or the overflow check of a 32-bit one: use 32-bit integers, or `wrapping_mul` where wrapping is meant" },
        .{ .prefix = "__mulodi4", .what = "the overflow check of a multiplication of 64-bit integers (`int`, `i64`, `u64`): use 32-bit integers" },
        .{ .prefix = "__muldi3", .what = "a multiplication of 64-bit integers (`int`, `i64`, `u64`): use 32-bit integers" },
        .{ .prefix = "__aeabi_ll", .what = "a shift of a 64-bit integer by a value that is not a constant: use 32-bit integers or a constant shift" },
        .{ .prefix = "__aeabi_lasr", .what = "a shift of a 64-bit integer by a value that is not a constant: use 32-bit integers or a constant shift" },
        .{ .prefix = "__aeabi_memcpy", .what = "a copy of a large record or array, which the code generator makes with `memcpy`: copy fewer bytes, or field by field" },
        .{ .prefix = "__aeabi_memmove", .what = "a copy of a large record or array, which the code generator makes with `memmove`: copy fewer bytes, or field by field" },
        .{ .prefix = "memcpy", .what = "a copy of a large record or array, which the code generator makes with `memcpy`: copy fewer bytes, or field by field" },
        .{ .prefix = "memmove", .what = "a copy of a large record or array, which the code generator makes with `memmove`: copy fewer bytes, or field by field" },
        .{ .prefix = "__aeabi_mem", .what = "filling a large record or array, which the code generator does with `memset`: fill fewer bytes, or field by field" },
        .{ .prefix = "memset", .what = "filling a large record or array, which the code generator does with `memset`: fill fewer bytes, or field by field" },
        .{ .prefix = "__aeabi_f", .what = "floating-point arithmetic, which this CPU does in library routines: use integers" },
        .{ .prefix = "__aeabi_d", .what = "floating-point arithmetic, which this CPU does in library routines: use integers" },
        .{ .prefix = "__aeabi_i2", .what = "a conversion between integers and floating point, which this CPU does in library routines: use integers" },
        .{ .prefix = "__aeabi_ui2", .what = "a conversion between integers and floating point, which this CPU does in library routines: use integers" },
        .{ .prefix = "__", .what = "a library routine the code generator calls for an operation this CPU has no instruction for" },
    };
    for (rows) |row| if (std.mem.startsWith(u8, symbol, row.prefix)) return row.what;
    return null;
}

/// The name a reader knows a symbol by: a Selka function's without `my.`, a compiler-rt routine's without the local
/// prefix Zig's compiler-rt gives it (`compiler_rt.mulXi3.__aeabi_lmul` is `__aeabi_lmul`).
fn selkaName(symbol: []const u8) []const u8 {
    if (product.guestName(symbol)) |name| return name;
    if (std.mem.startsWith(u8, symbol, "compiler_rt.")) if (std.mem.lastIndexOfScalar(u8, symbol, '.')) |dot| return symbol[dot + 1 ..];
    return symbol;
}

/// The diagnostic of `found`: the code, the Selka function, the symbol or kind of data it reached, and what to do.
pub fn message(a: std.mem.Allocator, found: Finding) error{OutOfMemory}![]const u8 {
    const head = "error[" ++ diagnostic_code ++ "]: the @freestanding(ram) function `{s}` ";
    const function = selkaName(found.function);
    return switch (found.kind) {
        .unplaced => std.fmt.allocPrint(a, head ++ "is at 0x{x:0>8} in `{s}`, which the image does not load into RAM: the device's linker script must put the section `.ramfunc` in RAM with the initialised data (`*(.ramfunc*)` first in `.data`, which start-up copies from flash)\n", .{ function, found.target, found.section }),
        .unmapped => std.fmt.allocPrint(a, head ++ "cannot be checked: the image has no symbol table, or no ARM mapping symbols (`$t`, `$d`) to tell its code from its data; do not strip the image the build links\n", .{function}),
        .unreadable => std.fmt.allocPrint(a, head ++ "cannot be checked: the output is not a 32-bit little-endian ARM ELF\n", .{function}),
        .call, .branch => {
            const name = if (found.symbol.len != 0) selkaName(found.symbol) else "code";
            const verb = if (found.kind == .call) "calls" else "branches to";
            if (routine(name)) |what| return std.fmt.allocPrint(a, head ++ "{s} `{s}` at 0x{x:0>8} in flash (`{s}`), from 0x{x:0>8}: {s}\n", .{ function, verb, name, found.target, found.section, found.at, what });
            const advice = if (std.mem.startsWith(u8, found.symbol, product.guest_symbol_prefix)) "a @freestanding(ram) function calls only RAM code" else "an `extern func` a `ram` function calls must be C placed in `.ramfunc` (`__attribute__((section(\".ramfunc\")))`), which the linker script loads into RAM";
            return std.fmt.allocPrint(a, head ++ "{s} `{s}` at 0x{x:0>8} in flash (`{s}`), from 0x{x:0>8}: {s}\n", .{ function, verb, name, found.target, found.section, found.at, advice });
        },
        .read, .address => {
            const name = if (found.symbol.len != 0) found.symbol else "data";
            const verb = if (found.kind == .read) "reads" else "holds the address of";
            return std.fmt.allocPrint(a, head ++ "{s} `{s}` at 0x{x:0>8} in flash (`{s}`), from 0x{x:0>8}: a table or constant the code generator placed in read-only data (a `match` over many cases, a constant array, a large constant record), which cannot be read while the flash is busy: compute it, or keep it in a local\n", .{ function, verb, selkaName(name), found.target, found.section, found.at });
        },
    };
}

/// The code of every refusal of the image check.
pub const diagnostic_code = "E_FREESTANDING_RAM";

/// The symbols of the `@freestanding(ram)` functions an emitted unit defines (`define ... @"my.NAME"(...) ...
/// "no-jump-tables"="true" section ".ramfunc"`), appended to `functions`, and of the `registers` reads and writes it placed
/// in RAM beside them (the section alone), appended to `helpers`: the check takes the first before the second, so a
/// refusal names a function the source declared first.
pub fn ramSymbols(a: std.mem.Allocator, text: []const u8, functions: *std.ArrayList([]const u8), helpers: *std.ArrayList([]const u8)) error{OutOfMemory}!void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "define ") or std.mem.indexOf(u8, line, " section \".ramfunc\"") == null) continue;
        const at = std.mem.indexOfScalar(u8, line, '@') orelse continue;
        const quoted = at + 1 < line.len and line[at + 1] == '"';
        const close = (if (quoted) std.mem.indexOfScalarPos(u8, line, at + 2, '"') else std.mem.indexOfScalarPos(u8, line, at + 1, '(')) orelse continue;
        const name = line[at + @as(usize, if (quoted) 2 else 1) .. close];
        try (if (std.mem.indexOf(u8, line, "\"no-jump-tables\"") != null) functions else helpers).append(a, name);
    }
}

/// The source paths an emitted unit's fault sites name (`@myl.path.N = private constant [K x i8] c"PATH\00"`), decoded
/// and appended to `out`.
pub fn faultPaths(a: std.mem.Allocator, text: []const u8, out: *std.ArrayList([]const u8)) error{OutOfMemory}!void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "@myl.path.")) continue;
        const open = std.mem.indexOf(u8, line, "c\"") orelse continue;
        const close = std.mem.lastIndexOfScalar(u8, line, '"') orelse continue;
        if (close <= open + 2) continue;
        var decoded: std.ArrayList(u8) = .empty;
        var at = open + 2;
        while (at < close) {
            if (line[at] == '\\' and at + 2 < close) {
                try decoded.append(a, std.fmt.parseInt(u8, line[at + 1 .. at + 3], 16) catch 0);
                at += 3;
            } else {
                try decoded.append(a, line[at]);
                at += 1;
            }
        }
        if (decoded.items.len != 0 and decoded.items[decoded.items.len - 1] == 0) decoded.items.len -= 1;
        try out.append(a, decoded.items);
    }
}

test "the Thumb decoder finds the target of a bl, a b, a literal ldr and an adr" {
    // `bl` from 0x20000000 to 0x10000100: offset 0xf0000100 - 4 = -0x0fffff04, out of a bl's reach on a real CPU (a thunk
    // would carry it), but the encoding round-trips; and a short one, 0x20000000 -> 0x20000010 (offset 12).
    const short = wideReference(0x20000000, 0xf000, 0xf806).?;
    try std.testing.expectEqual(Kind.call, short.kind);
    try std.testing.expectEqual(@as(u32, 0x20000010), short.target);
    const back = wideReference(0x20000100, 0xf7ff, 0xff7e).?;
    try std.testing.expectEqual(@as(u32, 0x20000000), back.target);
    try std.testing.expectEqual(@as(u32, 0x20000008), narrowReference(0x20000000, 0xe002).?.target);
    try std.testing.expectEqual(@as(u32, 0x20000002), narrowReference(0x20000006, 0xd1fc).?.target);
    const literal = narrowReference(0x20000002, 0x4801).?;
    try std.testing.expectEqual(Kind.read, literal.kind);
    try std.testing.expectEqual(@as(u32, 0x20000008), literal.target);
    try std.testing.expectEqual(Kind.address, narrowReference(0x20000000, 0xa001).?.kind);
    // `udf #83`, `bx lr` and `adds` name nothing.
    try std.testing.expect(narrowReference(0, 0xde53) == null);
    try std.testing.expect(narrowReference(0, 0x4770) == null);
    try std.testing.expect(narrowReference(0, 0x1c40) == null);
}

test "mapping symbols, clones and the routine advice" {
    try std.testing.expectEqual(@as(?bool, true), mapping("$t"));
    try std.testing.expectEqual(@as(?bool, false), mapping("$d.12"));
    try std.testing.expect(mapping("$x") == null and mapping("$tab") == null and mapping("main") == null);
    try std.testing.expect(clone("my.f.constprop.0", "my.f") and clone("my.f", "my.f") and !clone("my.fg", "my.f"));
    try std.testing.expect(std.mem.indexOf(u8, routine("__aeabi_uidivmod").?, "no divide instruction") != null);
    try std.testing.expect(std.mem.indexOf(u8, routine("__aeabi_lmul").?, "64-bit") != null);
    try std.testing.expect(routine("erase_sector") == null);
}

test "the ram symbols and fault paths of an emitted unit" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const text = "@myl.path.0 = private constant [8 x i8] c\"a\\5Cb.selka\\00\"\ndefine internal fastcc void @\"my.w\"(i32 %p0) nounwind section \".ramfunc\" {\ndefine internal fastcc i32 @\"my.f\"(i32 %p0) nounwind \"no-jump-tables\"=\"true\" section \".ramfunc\" {\ndefine internal fastcc i32 @\"my.g\"(i32 %p0) nounwind {\n";
    var symbols: std.ArrayList([]const u8) = .empty;
    var helpers: std.ArrayList([]const u8) = .empty;
    try ramSymbols(arena.allocator(), text, &symbols, &helpers);
    try std.testing.expectEqual(@as(usize, 1), symbols.items.len);
    try std.testing.expectEqualStrings("my.f", symbols.items[0]);
    try std.testing.expectEqualStrings("my.w", helpers.items[0]);
    var paths: std.ArrayList([]const u8) = .empty;
    try faultPaths(arena.allocator(), text, &paths);
    try std.testing.expectEqualStrings("a\\b.selka", paths.items[0]);
}

test "the initialised data's extent needs both symbols and a range that is not empty" {
    const start: Symbol = .{ .name = "__data_start", .value = 0x20001880, .size = 0, .info = 0, .section = 3 };
    const end: Symbol = .{ .name = "__data_end", .value = 0x200018d8, .size = 0, .info = 0, .section = 3 };
    const extent = dataExtent(&.{ start, .{ .name = "my.f", .value = 0, .size = 4, .info = 2, .section = 3 }, end }).?;
    try std.testing.expectEqual(@as(u32, 0x20001880), extent.start);
    try std.testing.expectEqual(@as(u32, 0x200018d8), extent.end);
    try std.testing.expect(dataExtent(&.{start}) == null);
    try std.testing.expect(dataExtent(&.{end}) == null);
    try std.testing.expect(dataExtent(&.{ start, .{ .name = "__data_end", .value = start.value, .size = 0, .info = 0, .section = 3 } }) == null);
}
