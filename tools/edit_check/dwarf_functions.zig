//! From an instrumented binary to the source functions each of its coverage counters
//! belongs to.
//!
//! `-ffuzz` gives every counter one entry in the `__sancov_pcs1` table: the address of
//! the code it counts. This file reads the binary's DWARF (version 4, which the pinned
//! Zig's LLVM backend emits) and finds, for every table entry, the source function
//! (file and declaration line) of the subprogram that contains the address and of every
//! `DW_TAG_inlined_subroutine` that contains it, so code inlined into a caller counts
//! for the inlined function as well as the caller. Inlined code often has no counter of
//! its own (a block without a branch is counted at its start, in the caller's code), so
//! every counter of a function that inlines another also belongs to the inlined
//! function: that over-approximates when the inlined call is on a path not taken, and
//! never misses a test that ran it. A generic instance or an `__anon_` clone has the
//! declaration line of the function it was made from.
const std = @import("std");
const dw = std.dwarf;

/// A source function as the debug information names it.
pub const Key = struct {
    /// Index into `Table.files`.
    file: u32,
    /// Declaration line, 1-based.
    line: u32,
};

/// The functions of every counter of one binary.
pub const Table = struct {
    /// Repo-relative paths of the source files that hold the keys' functions.
    files: [][]const u8,
    /// Every distinct function the counters belong to.
    keys: []Key,
    /// `offsets[i]..offsets[i + 1]` indexes `key_ids` for counter `i`.
    offsets: []u32,
    /// Indices into `keys`.
    key_ids: []u32,

    /// The keys of counter `index`, innermost last.
    pub fn keysOf(table: Table, index: usize) []const u32 {
        return table.key_ids[table.offsets[index]..table.offsets[index + 1]];
    }

    /// How many counters the binary has.
    pub fn counters(table: Table) usize {
        return table.offsets.len - 1;
    }

    /// Release everything the table owns.
    pub fn deinit(table: *Table, gpa: std.mem.Allocator) void {
        for (table.files) |path| gpa.free(path);
        gpa.free(table.files);
        gpa.free(table.keys);
        gpa.free(table.offsets);
        gpa.free(table.key_ids);
        table.* = undefined;
    }
};

/// What can go wrong reading a binary.
pub const Error = error{ NotElf64, MissingSection, UnsupportedDwarf, BadDwarf, OutOfMemory };

/// Sections of the binary the reader needs.
const Sections = struct {
    info: []const u8,
    abbrev: []const u8,
    str: []const u8,
    ranges: []const u8,
    line: []const u8,
    pcs: []const u8,
    counters: usize,
};

fn findSections(elf: []const u8) Error!Sections {
    if (elf.len < 64 or !std.mem.eql(u8, elf[0..4], "\x7fELF") or elf[4] != 2 or elf[5] != 1) return error.NotElf64;
    const table_offset = std.mem.readInt(u64, elf[0x28..][0..8], .little);
    const entry_size = std.mem.readInt(u16, elf[0x3a..][0..2], .little);
    const count = std.mem.readInt(u16, elf[0x3c..][0..2], .little);
    const names_index = std.mem.readInt(u16, elf[0x3e..][0..2], .little);
    const header = struct {
        fn at(bytes: []const u8, base: u64, size: u16, index: usize) []const u8 {
            return bytes[base + size * index ..][0..size];
        }
    };
    const names_header = header.at(elf, table_offset, entry_size, names_index);
    const names_offset = std.mem.readInt(u64, names_header[0x18..][0..8], .little);
    var found: Sections = .{ .info = &.{}, .abbrev = &.{}, .str = &.{}, .ranges = &.{}, .line = &.{}, .pcs = &.{}, .counters = 0 };
    var have: u8 = 0;
    for (0..count) |index| {
        const entry = header.at(elf, table_offset, entry_size, index);
        const name_offset = std.mem.readInt(u32, entry[0..4], .little);
        const offset = std.mem.readInt(u64, entry[0x18..][0..8], .little);
        const size = std.mem.readInt(u64, entry[0x20..][0..8], .little);
        const name = std.mem.sliceTo(elf[names_offset + name_offset ..], 0);
        const bytes = elf[offset..][0..size];
        if (std.mem.eql(u8, name, ".debug_info")) {
            found.info = bytes;
            have |= 1;
        } else if (std.mem.eql(u8, name, ".debug_abbrev")) {
            found.abbrev = bytes;
            have |= 2;
        } else if (std.mem.eql(u8, name, ".debug_str")) {
            found.str = bytes;
            have |= 4;
        } else if (std.mem.eql(u8, name, ".debug_ranges")) {
            found.ranges = bytes;
        } else if (std.mem.eql(u8, name, ".debug_line")) {
            found.line = bytes;
            have |= 8;
        } else if (std.mem.eql(u8, name, "__sancov_pcs1")) {
            found.pcs = bytes;
            have |= 16;
        } else if (std.mem.eql(u8, name, "__sancov_cntrs")) {
            found.counters = size;
        }
    }
    if (have != 31) return error.MissingSection;
    return found;
}

/// A cursor over a byte slice.
const Cursor = struct {
    bytes: []const u8,
    pos: usize = 0,

    fn int(c: *Cursor, comptime T: type) Error!T {
        if (c.pos + @sizeOf(T) > c.bytes.len) return error.BadDwarf;
        defer c.pos += @sizeOf(T);
        return std.mem.readInt(T, c.bytes[c.pos..][0..@sizeOf(T)], .little);
    }
    fn uleb(c: *Cursor) Error!u64 {
        var result: u64 = 0;
        var shift: u6 = 0;
        while (true) {
            if (c.pos >= c.bytes.len) return error.BadDwarf;
            const byte = c.bytes[c.pos];
            c.pos += 1;
            if (shift < 64) result |= @as(u64, byte & 0x7f) << shift;
            if (byte & 0x80 == 0) return result;
            shift +|= 7;
        }
    }
    fn skip(c: *Cursor, count: u64) Error!void {
        if (c.pos + count > c.bytes.len) return error.BadDwarf;
        c.pos += @intCast(count);
    }
    fn cstring(c: *Cursor) Error![]const u8 {
        const rest = c.bytes[c.pos..];
        const end = std.mem.findScalar(u8, rest, 0) orelse return error.BadDwarf;
        c.pos += end + 1;
        return rest[0..end];
    }
};

const Attr = struct { name: u64, form: u64 };
const Abbrev = struct { tag: u64, children: bool, attrs: []const Attr };

/// The attribute values the reader keeps from a DIE.
const Values = struct {
    decl_file: u32 = 0,
    decl_line: u32 = 0,
    origin: u64 = 0,
    specification: u64 = 0,
    low: ?u64 = null,
    high: ?u64 = null,
    high_is_offset: bool = false,
    ranges: ?u64 = null,
    stmt_list: ?u64 = null,
    comp_dir: []const u8 = "",
};

const Die = struct {
    offset: u64,
    tag: u64,
    cu: u32,
    /// For an inlined subroutine, the index of the subprogram it was inlined into.
    owner: u32,
    values: Values,
};

const Interval = struct { lo: u64, hi: u64, key: u32 };

const none = std.math.maxInt(u32);

/// Per-compile-unit file table: absolute paths, index 0 is file number 1.
const UnitFiles = struct { paths: []const ?u32 };

/// Build the table for the binary `elf`; paths under `repo_root` become repo-relative.
pub fn load(gpa: std.mem.Allocator, elf: []const u8, repo_root: []const u8) Error!Table {
    const sections = try findSections(elf);
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var files: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (files.items) |path| gpa.free(path);
        files.deinit(gpa);
    }
    var file_ids: std.StringHashMapUnmanaged(u32) = .empty;
    var dies: std.ArrayList(Die) = .empty;
    var unit_files: std.ArrayList([]const ?u32) = .empty;
    var abbrevs: std.AutoHashMapUnmanaged(u64, std.AutoHashMapUnmanaged(u64, Abbrev)) = .empty;
    var by_offset: std.AutoHashMapUnmanaged(u64, u32) = .empty;

    var info: Cursor = .{ .bytes = sections.info };
    var unit_index: u32 = 0;
    while (info.pos < sections.info.len) : (unit_index += 1) {
        const unit_start = info.pos;
        const length = try info.int(u32);
        if (length == 0xffffffff) return error.UnsupportedDwarf;
        const unit_end = info.pos + length;
        if (unit_end > sections.info.len) return error.BadDwarf;
        if (try info.int(u16) != 4) return error.UnsupportedDwarf;
        const abbrev_offset = try info.int(u32);
        if (try info.int(u8) != 8) return error.UnsupportedDwarf;
        const table = try abbrevTable(arena, &abbrevs, sections.abbrev, abbrev_offset);
        var first_die = true;
        // Open DIEs with children: the index of the recorded subprogram or inlined subroutine, if it is one.
        var open: std.ArrayList(u32) = .empty;
        while (info.pos < unit_end) {
            const offset = info.pos;
            const code = try info.uleb();
            if (code == 0) {
                _ = open.pop();
                continue;
            }
            const abbrev = table.get(code) orelse return error.BadDwarf;
            var values: Values = .{};
            for (abbrev.attrs) |attr| try readAttribute(&info, attr, unit_start, sections.str, &values);
            var recorded: u32 = none;
            if (first_die) {
                first_die = false;
                try unit_files.append(arena, try fileTable(arena, gpa, &files, &file_ids, sections.line, values, repo_root));
            } else if (abbrev.tag == dw.TAG.subprogram or abbrev.tag == dw.TAG.inlined_subroutine) {
                recorded = @intCast(dies.items.len);
                try by_offset.put(arena, offset, recorded);
                var owner: u32 = none;
                var depth = open.items.len;
                while (depth > 0) : (depth -= 1) {
                    const candidate = open.items[depth - 1];
                    if (candidate != none and dies.items[candidate].tag == dw.TAG.subprogram) {
                        owner = candidate;
                        break;
                    }
                }
                try dies.append(arena, .{ .offset = offset, .tag = abbrev.tag, .cu = unit_index, .owner = owner, .values = values });
            }
            if (abbrev.children) try open.append(arena, recorded);
        }
        info.pos = unit_end;
    }

    var keys: std.ArrayList(Key) = .empty;
    errdefer keys.deinit(gpa);
    var key_ids: std.AutoHashMapUnmanaged(Key, u32) = .empty;
    var intervals: std.ArrayList(Interval) = .empty;
    const die_keys = try arena.alloc(u32, dies.items.len);
    for (dies.items, die_keys) |die, *die_key| {
        die_key.* = none;
        const key = resolve(die, dies.items, &by_offset, unit_files.items) orelse continue;
        const slot = try key_ids.getOrPut(arena, key);
        if (!slot.found_existing) {
            slot.value_ptr.* = @intCast(keys.items.len);
            try keys.append(gpa, key);
        }
        die_key.* = slot.value_ptr.*;
        try collectIntervals(arena, &intervals, die, sections.ranges, slot.value_ptr.*);
    }
    // A function that inlines another owns the inlined function's key on all of its own ranges.
    for (dies.items, die_keys) |die, key| {
        if (die.tag != dw.TAG.inlined_subroutine or die.owner == none or key == none) continue;
        try collectIntervals(arena, &intervals, dies.items[die.owner], sections.ranges, key);
    }
    std.mem.sortUnstable(Interval, intervals.items, {}, struct {
        fn less(_: void, a: Interval, b: Interval) bool {
            return if (a.lo != b.lo) a.lo < b.lo else a.hi > b.hi;
        }
    }.less);

    const count = sections.pcs.len / 8;
    const order = try arena.alloc(u32, count);
    for (order, 0..) |*slot, index| slot.* = @intCast(index);
    const pcs: [*]align(1) const u64 = @ptrCast(sections.pcs.ptr);
    std.mem.sortUnstable(u32, order, pcs[0..count], struct {
        fn less(table: []align(1) const u64, a: u32, b: u32) bool {
            return table[a] < table[b];
        }
    }.less);

    const per_counter = try arena.alloc(std.ArrayList(u32), count);
    @memset(per_counter, .empty);
    var active: std.ArrayList(u32) = .empty;
    var next: usize = 0;
    for (order) |index| {
        const pc = pcs[index];
        if (pc == 1) continue;
        while (next < intervals.items.len and intervals.items[next].lo <= pc) : (next += 1) try active.append(arena, @intCast(next));
        var kept: usize = 0;
        for (active.items) |candidate| {
            if (intervals.items[candidate].hi <= pc) continue;
            active.items[kept] = candidate;
            kept += 1;
        }
        active.shrinkRetainingCapacity(kept);
        for (active.items) |candidate| {
            const key = intervals.items[candidate].key;
            if (std.mem.findScalar(u32, per_counter[index].items, key) == null) try per_counter[index].append(arena, key);
        }
    }

    const offsets = try gpa.alloc(u32, count + 1);
    errdefer gpa.free(offsets);
    var total: usize = 0;
    for (per_counter, 0..) |list, index| {
        offsets[index] = @intCast(total);
        total += list.items.len;
    }
    offsets[count] = @intCast(total);
    const flat = try gpa.alloc(u32, total);
    errdefer gpa.free(flat);
    for (per_counter, 0..) |list, index| @memcpy(flat[offsets[index]..][0..list.items.len], list.items);
    return .{
        .files = try files.toOwnedSlice(gpa),
        .keys = try keys.toOwnedSlice(gpa),
        .offsets = offsets,
        .key_ids = flat,
    };
}

fn abbrevTable(
    arena: std.mem.Allocator,
    cache: *std.AutoHashMapUnmanaged(u64, std.AutoHashMapUnmanaged(u64, Abbrev)),
    section: []const u8,
    offset: u64,
) Error!*const std.AutoHashMapUnmanaged(u64, Abbrev) {
    const slot = try cache.getOrPut(arena, offset);
    if (slot.found_existing) return slot.value_ptr;
    slot.value_ptr.* = .empty;
    var cursor: Cursor = .{ .bytes = section, .pos = offset };
    while (true) {
        const code = try cursor.uleb();
        if (code == 0) break;
        const tag = try cursor.uleb();
        const children = try cursor.int(u8) != 0;
        var attrs: std.ArrayList(Attr) = .empty;
        while (true) {
            const name = try cursor.uleb();
            const form = try cursor.uleb();
            if (name == 0 and form == 0) break;
            if (form == dw.FORM.implicit_const) _ = try cursor.uleb();
            try attrs.append(arena, .{ .name = name, .form = form });
        }
        try slot.value_ptr.put(arena, code, .{ .tag = tag, .children = children, .attrs = try attrs.toOwnedSlice(arena) });
    }
    return slot.value_ptr;
}

/// Read one attribute value, keeping it in `values` when the reader uses it.
fn readAttribute(c: *Cursor, attr: Attr, unit_start: usize, str: []const u8, values: *Values) Error!void {
    var number: u64 = 0;
    var text: []const u8 = "";
    switch (attr.form) {
        dw.FORM.addr, dw.FORM.data8, dw.FORM.ref8, dw.FORM.ref_sig8 => number = try c.int(u64),
        dw.FORM.data4, dw.FORM.ref4, dw.FORM.sec_offset, dw.FORM.ref_addr => number = try c.int(u32),
        dw.FORM.data2, dw.FORM.ref2 => number = try c.int(u16),
        dw.FORM.data1, dw.FORM.ref1, dw.FORM.flag => number = try c.int(u8),
        dw.FORM.udata, dw.FORM.ref_udata, dw.FORM.sdata => number = try c.uleb(),
        dw.FORM.flag_present => number = 1,
        dw.FORM.strp => {
            const offset = try c.int(u32);
            if (offset >= str.len) return error.BadDwarf;
            text = std.mem.sliceTo(str[offset..], 0);
        },
        dw.FORM.string => text = try c.cstring(),
        dw.FORM.exprloc, dw.FORM.block => try c.skip(try c.uleb()),
        dw.FORM.block1 => try c.skip(try c.int(u8)),
        dw.FORM.block2 => try c.skip(try c.int(u16)),
        dw.FORM.block4 => try c.skip(try c.int(u32)),
        else => return error.UnsupportedDwarf,
    }
    switch (attr.name) {
        dw.AT.decl_file => values.decl_file = @intCast(number),
        dw.AT.decl_line => values.decl_line = @intCast(number),
        dw.AT.abstract_origin => values.origin = if (attr.form == dw.FORM.ref_addr) number else unit_start + number,
        dw.AT.specification => values.specification = if (attr.form == dw.FORM.ref_addr) number else unit_start + number,
        dw.AT.low_pc => values.low = number,
        dw.AT.high_pc => {
            values.high = number;
            values.high_is_offset = attr.form != dw.FORM.addr;
        },
        dw.AT.ranges => values.ranges = number,
        dw.AT.stmt_list => values.stmt_list = number,
        dw.AT.comp_dir => values.comp_dir = text,
        else => {},
    }
}

/// The file table of a unit: for each file number (from 1), its id in `files`, or null for
/// a file outside the repo.
fn fileTable(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    files: *std.ArrayList([]const u8),
    file_ids: *std.StringHashMapUnmanaged(u32),
    section: []const u8,
    unit: Values,
    repo_root: []const u8,
) Error![]const ?u32 {
    const stmt = unit.stmt_list orelse return &.{};
    var c: Cursor = .{ .bytes = section, .pos = stmt };
    const length = try c.int(u32);
    const end = c.pos + length;
    if (try c.int(u16) != 4) return error.UnsupportedDwarf;
    const header_length = try c.int(u32);
    const program = c.pos + header_length;
    _ = try c.int(u8); // minimum instruction length
    _ = try c.int(u8); // maximum operations per instruction
    _ = try c.int(u8); // default is_stmt
    _ = try c.int(i8); // line base
    _ = try c.int(u8); // line range
    const opcode_base = try c.int(u8);
    try c.skip(opcode_base -| 1);
    var directories: std.ArrayList([]const u8) = .empty;
    while (true) {
        const name = try c.cstring();
        if (name.len == 0) break;
        try directories.append(arena, name);
    }
    var result: std.ArrayList(?u32) = .empty;
    while (c.pos < program and c.pos < end) {
        const name = try c.cstring();
        if (name.len == 0) break;
        const directory = try c.uleb();
        _ = try c.uleb(); // modification time
        _ = try c.uleb(); // length
        const base = if (directory == 0) unit.comp_dir else if (directory <= directories.items.len) directories.items[directory - 1] else "";
        const joined = if (std.fs.path.isAbsolute(name)) name else if (std.fs.path.isAbsolute(base))
            try std.fs.path.join(arena, &.{ base, name })
        else
            try std.fs.path.join(arena, &.{ unit.comp_dir, base, name });
        const resolved = try std.fs.path.resolve(arena, &.{joined});
        try result.append(arena, try internRepoPath(arena, gpa, files, file_ids, resolved, repo_root));
    }
    return result.toOwnedSlice(arena);
}

fn internRepoPath(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    files: *std.ArrayList([]const u8),
    file_ids: *std.StringHashMapUnmanaged(u32),
    absolute: []const u8,
    repo_root: []const u8,
) Error!?u32 {
    if (!std.mem.startsWith(u8, absolute, repo_root) or absolute.len <= repo_root.len or absolute[repo_root.len] != '/') return null;
    const relative = absolute[repo_root.len + 1 ..];
    if (std.mem.startsWith(u8, relative, ".zig-cache/") or std.mem.startsWith(u8, relative, "zig-out/")) return null;
    const slot = try file_ids.getOrPut(arena, relative);
    if (!slot.found_existing) {
        slot.value_ptr.* = @intCast(files.items.len);
        try files.append(gpa, try gpa.dupe(u8, relative));
    }
    return slot.value_ptr.*;
}

/// The source function of a subprogram or inlined subroutine: its own declaration, or its
/// origin's (concrete and inlined instances carry only a reference).
fn resolve(die: Die, dies: []const Die, by_offset: *const std.AutoHashMapUnmanaged(u64, u32), unit_files: []const []const ?u32) ?Key {
    var current = die;
    for (0..6) |_| {
        if (current.values.decl_line != 0) {
            const table = unit_files[current.cu];
            const file = current.values.decl_file;
            if (file == 0 or file > table.len) return null;
            return .{ .file = table[file - 1] orelse return null, .line = current.values.decl_line };
        }
        const next_offset = if (current.values.origin != 0) current.values.origin else current.values.specification;
        if (next_offset == 0) return null;
        const next = by_offset.get(next_offset) orelse return null;
        current = dies[next];
    }
    return null;
}

/// Append the address ranges of a concrete subprogram or inlined subroutine as intervals for `key`.
fn collectIntervals(arena: std.mem.Allocator, intervals: *std.ArrayList(Interval), die: Die, ranges: []const u8, key: u32) Error!void {
    const values = die.values;
    if (values.low) |low| {
        if (values.high) |high| {
            const hi = if (values.high_is_offset) low + high else high;
            if (hi > low) try intervals.append(arena, .{ .lo = low, .hi = hi, .key = key });
        }
        return;
    }
    const offset = values.ranges orelse return;
    var c: Cursor = .{ .bytes = ranges, .pos = offset };
    var base: u64 = 0;
    while (c.pos + 16 <= ranges.len) {
        const begin = try c.int(u64);
        const end = try c.int(u64);
        if (begin == 0 and end == 0) return;
        if (begin == std.math.maxInt(u64)) {
            base = end;
            continue;
        }
        if (end > begin) try intervals.append(arena, .{ .lo = base + begin, .hi = base + end, .key = key });
    }
}
