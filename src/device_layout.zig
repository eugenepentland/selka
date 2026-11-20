//! A device described instead of scripted (MCU-NOC4A): the `memory`, `place`, `stack`, `boot` and `hooks` keys of a `devices` entry,
//! their checks, and the linker script the compiler writes from them.
//!
//! The script is the board's own (`bringup/selka-flash/link.ld`, `selka-ram/link.ld`, `scripts/bare/qemu/link.ld`) with each
//! number computed from the regions: vectors at the start of their region, or after the boot stage's 256 bytes; code and
//! read-only data; `.data` (with `.ramfunc` first) copied from the code region when that is another region; `.bss`; the heap up to
//! the stack; and the symbols the bare runtime reads (`__stack_top`, `__stack_limit`, `__data_*`, `__bss_*`, `__heap_*`). A named
//! boot stage is a `.boot2` section made of the sealed bytes, so the ELF itself is bootable.
const std = @import("std");
const boot = @import("device_boot.zig");
const hooks = @import("device_hooks.zig");

/// The raw keys of a device entry beyond `target`, `linker_script`, `links`, `include`, `image` and `uf2_family`, as JSON gives
/// them: `memory` is `{"NAME": [ORIGIN, LENGTH]}`, `place` is `{"vectors": R, "code": R, "data": R}`, `stack` is `"SIZE"` or
/// `["SIZE", "REGION"]`, `boot` names a stage and `hooks` is `{"HOOK": "MODULE.FUNCTION"}`.
pub const Startup = struct {
    memory: ?std.json.ArrayHashMap([2][]const u8) = null,
    place: ?std.json.ArrayHashMap([]const u8) = null,
    stack: ?std.json.Value = null,
    boot: ?[]const u8 = null,
    hooks: ?std.json.ArrayHashMap([]const u8) = null,
};

/// One named region of memory.
pub const Region = struct { name: []const u8, origin: u32, length: u32 };

/// The stack: its size and the region whose end is its top.
pub const Stack = struct { size: u32, region: usize };

/// A described device: its regions, the regions (by index) that hold the vectors, the code and the data (with `.bss` and the heap),
/// the stack, and the boot stage's name.
pub const Layout = struct {
    regions: []const Region,
    vectors: usize,
    code: usize,
    data: usize,
    stack: Stack,
    boot: ?[]const u8,
};

/// What `parse` found: no description (a device with a named script, or only hooks), a layout, or the line that refuses it.
pub const Result = union(enum) { absent, layout: Layout, refused: []const u8 };

/// The most regions a device may have.
const most_regions = 16;
/// The least room the heap must keep, which the script asserts.
const least_heap = 4096;
/// Where the vector table sits after a boot stage.
const after_boot = 0x100;

/// Check a device's keys and make its layout. `linker_script` says the entry names a script too. A refusal is written into
/// `buffer` (which the caller keeps for as long as it shows the line).
pub fn parse(arena: std.mem.Allocator, startup: Startup, linker_script: bool, buffer: []u8) std.mem.Allocator.Error!Result {
    if (startup.hooks) |bound| for (bound.map.keys(), bound.map.values()) |name, function| {
        if (hooks.named(name) == null) return refuse(buffer, "unknown hook \"{s}\"; the hooks are {s}", .{ name, hooks.names_text });
        if (!hooks.wellFormed(function)) return refuse(buffer, "hook \"{s}\" must name a function as MODULE.FUNCTION, not \"{s}\"", .{ name, function });
    };
    const memory = startup.memory orelse {
        if (startup.place != null or startup.stack != null or startup.boot != null)
            return refuse(buffer, "a device's place, stack and boot describe its memory: add \"memory\"", .{});
        return .absent;
    };
    if (linker_script) return refuse(buffer, "a device names a linker_script or describes its memory, not both", .{});
    const regions = switch (try regionsOf(arena, memory, buffer)) {
        .regions => |found| found,
        .refused => |line| return .{ .refused = line },
    };
    const parts = switch (try partsOf(startup.place, regions, buffer)) {
        .parts => |found| found,
        .refused => |line| return .{ .refused = line },
    };
    const stack = switch (stackOf(startup.stack, regions, parts.data, buffer)) {
        .stack => |found| found,
        .refused => |line| return .{ .refused = line },
    };
    if (startup.boot) |name| {
        if (boot.code(name) == null) return refuse(buffer, "unknown boot stage \"{s}\"; the boot stages are {s}", .{ name, boot.names_text });
        if (parts.vectors != parts.code) return refuse(buffer, "boot \"{s}\" starts the code region \"{s}\", which must hold the vectors too", .{ name, regions[parts.code].name });
        if (regions[parts.code].length < boot.sealed_size + after_boot) return refuse(buffer, "region \"{s}\" is too small for the boot stage and the vectors", .{regions[parts.code].name});
    }
    return .{ .layout = .{ .regions = regions, .vectors = parts.vectors, .code = parts.code, .data = parts.data, .stack = stack, .boot = startup.boot } };
}

fn refuse(buffer: []u8, comptime format: []const u8, arguments: anytype) Result {
    return .{ .refused = std.fmt.bufPrint(buffer, format, arguments) catch buffer };
}

const Regions = union(enum) { regions: []const Region, refused: []const u8 };

/// The regions `memory` names: valid names, origins and lengths below 4 GiB, not overlapping.
fn regionsOf(arena: std.mem.Allocator, memory: std.json.ArrayHashMap([2][]const u8), buffer: []u8) std.mem.Allocator.Error!Regions {
    const names = memory.map.keys();
    if (names.len == 0) return .{ .refused = refuse(buffer, "memory names no region", .{}).refused };
    if (names.len > most_regions) return .{ .refused = refuse(buffer, "memory names {d} regions, at most {d}", .{ names.len, most_regions }).refused };
    const regions = try arena.alloc(Region, names.len);
    for (names, memory.map.values(), regions) |name, pair, *region| {
        if (!validName(name)) return .{ .refused = refuse(buffer, "a region's name is lowercase letters, digits and '_' (at most 16), not \"{s}\"", .{name}).refused };
        const origin = parseSize(pair[0]) orelse 0xFFFFFFFFF;
        const length = parseSize(pair[1]) orelse 0;
        if (origin > 0xFFFFFFFE) return .{ .refused = refuse(buffer, "region \"{s}\": the origin must be \"0x...\" or decimal text below 4 GiB, not \"{s}\"", .{ name, pair[0] }).refused };
        if (length == 0 or origin + length > 0xFFFFFFFF) return .{ .refused = refuse(buffer, "region \"{s}\": the length must be a size such as \"2044K\", \"2M\" or \"0x1FF000\", above 0 and ending below 4 GiB, not \"{s}\"", .{ name, pair[1] }).refused };
        region.* = .{ .name = name, .origin = @intCast(origin), .length = @intCast(length) };
    }
    for (regions, 0..) |first, at| for (regions[at + 1 ..]) |second| {
        if (first.origin < end(second) and second.origin < end(first))
            return .{ .refused = refuse(buffer, "regions \"{s}\" and \"{s}\" overlap", .{ first.name, second.name }).refused };
    };
    return .{ .regions = regions };
}

/// The end of `region`, which fits 32 bits (`regionsOf` checked).
fn end(region: Region) u32 {
    return region.origin + region.length;
}

fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 16 or std.ascii.isDigit(name[0])) return false;
    for (name) |byte| if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte) and byte != '_') return false;
    return true;
}

/// A size or an address as the key spells it: decimal or `0x` hex digits, then an optional `K` (1024) or `M` (1048576).
fn parseSize(text: []const u8) ?u64 {
    var digits = text;
    var scale: u64 = 1;
    if (digits.len != 0 and (digits[digits.len - 1] == 'K' or digits[digits.len - 1] == 'M')) {
        scale = if (digits[digits.len - 1] == 'K') 1024 else 1024 * 1024;
        digits = digits[0 .. digits.len - 1];
    }
    const base: u8 = if (std.mem.startsWith(u8, digits, "0x")) 16 else 10;
    if (base == 16) digits = digits[2..];
    if (digits.len == 0) return null;
    const value = std.fmt.parseUnsigned(u64, digits, base) catch return null;
    return std.math.mul(u64, value, scale) catch null;
}

const Parts = struct { vectors: usize, code: usize, data: usize };
const PartsResult = union(enum) { parts: Parts, refused: []const u8 };

fn indexOf(regions: []const Region, name: []const u8) ?usize {
    for (regions, 0..) |region, at| if (std.mem.eql(u8, region.name, name)) return at;
    return null;
}

/// Where the vectors, the code and the data go: `place`'s choices, else the code in `flash` and the data in `ram`, or everything in
/// `ram` when there is no `flash`; the vectors go where the code goes.
fn partsOf(place: ?std.json.ArrayHashMap([]const u8), regions: []const Region, buffer: []u8) std.mem.Allocator.Error!PartsResult {
    var chosen: [3]?[]const u8 = @splat(null);
    const parts = [_][]const u8{ "vectors", "code", "data" };
    if (place) |given| for (given.map.keys(), given.map.values()) |part, region| {
        const at = for (parts, 0..) |name, index| {
            if (std.mem.eql(u8, name, part)) break index;
        } else return .{ .refused = refuse(buffer, "place names vectors, code and data, not \"{s}\"", .{part}).refused };
        if (indexOf(regions, region) == null) return .{ .refused = refuse(buffer, "place.{s} names the region \"{s}\", which memory does not have", .{ part, region }).refused };
        chosen[at] = region;
    };
    const data = if (chosen[2]) |name| indexOf(regions, name).? else indexOf(regions, "ram") orelse
        return .{ .refused = refuse(buffer, "memory needs a region named \"ram\" for the data, or place.data naming one", .{}).refused };
    const code = if (chosen[1]) |name| indexOf(regions, name).? else indexOf(regions, "flash") orelse data;
    const vectors = if (chosen[0]) |name| indexOf(regions, name).? else code;
    return .{ .parts = .{ .vectors = vectors, .code = code, .data = data } };
}

const StackResult = union(enum) { stack: Stack, refused: []const u8 };

/// The stack `value` describes, `"SIZE"` in the data's region or `["SIZE", "REGION"]`: a size that is a multiple of 8, in a region
/// whose end is a multiple of 8 and that has room (a stack in the data's region leaves the heap at least `least_heap`).
fn stackOf(value: ?std.json.Value, regions: []const Region, data: usize, buffer: []u8) StackResult {
    const given = value orelse return .{ .refused = refuse(buffer, "a device that describes its memory needs a stack: \"16K\" or [\"8K\", \"REGION\"]", .{}).refused };
    var size_text: []const u8 = "";
    var region = data;
    switch (given) {
        .string => |text| size_text = text,
        .array => |pair| {
            if (pair.items.len != 2 or pair.items[0] != .string or pair.items[1] != .string)
                return .{ .refused = refuse(buffer, "stack is \"SIZE\" or [\"SIZE\", \"REGION\"]", .{}).refused };
            size_text = pair.items[0].string;
            region = indexOf(regions, pair.items[1].string) orelse
                return .{ .refused = refuse(buffer, "stack names the region \"{s}\", which memory does not have", .{pair.items[1].string}).refused };
        },
        else => return .{ .refused = refuse(buffer, "stack is \"SIZE\" or [\"SIZE\", \"REGION\"]", .{}).refused },
    }
    const size = parseSize(size_text) orelse 0;
    if (size == 0 or size % 8 != 0 or size > 0xFFFFFFF)
        return .{ .refused = refuse(buffer, "the stack's size must be a size such as \"16K\", above 0 and a multiple of 8, not \"{s}\"", .{size_text}).refused };
    if (end(regions[region]) % 8 != 0) return .{ .refused = refuse(buffer, "region \"{s}\" ends at {d}, and a stack at its top needs an end that is a multiple of 8", .{ regions[region].name, end(regions[region]) }).refused };
    const room: u64 = if (region == data) @as(u64, regions[region].length) -| least_heap else regions[region].length;
    if (size > room)
        return .{ .refused = refuse(buffer, "the stack of {d} bytes does not fit region \"{s}\" of {d} bytes{s}", .{ size, regions[region].name, regions[region].length, if (region == data) " with a heap of 4096 bytes" else "" }).refused };
    return .{ .stack = .{ .size = @intCast(size), .region = region } };
}

/// The linker script of `layout`, in the order and spelling of the board's own scripts.
pub fn generate(arena: std.mem.Allocator, layout: Layout) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const data = layout.regions[layout.data];
    const code = layout.regions[layout.code];
    const vectors = layout.regions[layout.vectors];
    const copied = layout.data != layout.code;
    const stack_shared = layout.stack.region == layout.data;
    const stack_region = layout.regions[layout.stack.region];
    try out.appendSlice(arena, "/* Written by selka from a device's `memory` description (MCU-NOC4A): the layout the bare runtime reads. */\nMEMORY {\n");
    for (layout.regions, 0..) |region, at| {
        const attributes = if (at == layout.data) "rwx" else if (at == layout.code or at == layout.vectors) "rx" else "rw";
        const length = if (at == layout.data and stack_shared) region.length - layout.stack.size else region.length;
        try out.print(arena, "  {s} ({s}) : ORIGIN = 0x{X}, LENGTH = 0x{X}\n", .{ try upper(arena, region.name), attributes, region.origin, length });
    }
    try out.print(arena, "}}\n__stack_top = 0x{X};\n__stack_limit = __stack_top - 0x{X};\nENTRY(myl_bare_reset)\nSECTIONS {{\n", .{ end(stack_region), layout.stack.size });
    const code_name = try upper(arena, code.name);
    const data_name = try upper(arena, data.name);
    const vectors_name = try upper(arena, vectors.name);
    if (layout.boot) |name| {
        const sealed = boot.seal(boot.code(name).?);
        try out.print(arena, "  .boot2 ORIGIN({s}) : {{\n", .{code_name});
        for (0..sealed.len / 16) |row| {
            try out.appendSlice(arena, "   ");
            for (0..4) |column| try out.print(arena, " LONG(0x{X:0>8})", .{std.mem.readInt(u32, sealed[row * 16 + column * 4 ..][0..4], .little)});
            try out.append(arena, '\n');
        }
        try out.print(arena, "  }} > {s}\n  .vectors ORIGIN({s}) + 0x{X} : {{ KEEP(*(.vectors)) }} > {s}\n", .{ code_name, code_name, after_boot, vectors_name });
    } else try out.print(arena, "  .vectors : {{ KEEP(*(.vectors)) }} > {s}\n", .{vectors_name});
    try out.print(arena, "  .text : {{ *(.text*) *(.rodata*){s} }} > {s}\n", .{ if (copied) " . = ALIGN(4);" else "", code_name });
    try out.print(arena, "  .data : {{ . = ALIGN(4); __data_start = .; *(.ramfunc*) . = ALIGN(4); *(.data*) . = ALIGN(4); __data_end = .; }} > {s}", .{data_name});
    if (copied) try out.print(arena, " AT > {s}\n  __data_load = LOADADDR(.data);\n", .{code_name}) else try out.appendSlice(arena, "\n  __data_load = __data_start;\n");
    try out.print(arena, "  .bss (NOLOAD) : {{ . = ALIGN(4); __bss_start = .; *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; }} > {s}\n  __heap_start = .;\n", .{data_name});
    if (stack_shared) try out.appendSlice(arena, "  __heap_end = __stack_limit;\n") else try out.print(arena, "  __heap_end = ORIGIN({s}) + LENGTH({s});\n", .{ data_name, data_name });
    if (copied) try out.appendSlice(arena, "  __flash_image_end = LOADADDR(.data) + SIZEOF(.data);\n");
    if (layout.boot != null) try out.print(arena, "  ASSERT(SIZEOF(.boot2) == {d}, \"the boot stage is {d} bytes\")\n  ASSERT(ADDR(.vectors) == ORIGIN({s}) + 0x{X}, \"the vector table must follow the boot stage\")\n", .{ boot.sealed_size, boot.sealed_size, code_name, after_boot });
    try out.appendSlice(arena, "  ASSERT(__heap_start + 4K <= __heap_end, \"the image leaves no heap\")\n  /DISCARD/ : { *(.ARM.exidx*) *(.ARM.extab*) *(.comment) *(.note*) }\n}\n");
    return out.items;
}

fn upper(arena: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.ascii.allocUpperString(arena, name);
}

/// A `Startup` read from the JSON text of a device entry, for the tests.
fn startupOf(arena: std.mem.Allocator, text: []const u8) !Startup {
    return std.json.parseFromSliceLeaky(Startup, arena, text, .{ .ignore_unknown_fields = true });
}

/// The layout `text` describes, or the line that refuses it.
fn layoutOf(arena: std.mem.Allocator, text: []const u8, buffer: []u8) !Result {
    return parse(arena, try startupOf(arena, text), false, buffer);
}

const flash_description =
    \\{"memory": {"flash": ["0x10000000", "2044K"], "ram": ["0x20000000", "252K"]}, "boot": "rp2040-read-03h", "stack": "16K"}
;
const qemu_description =
    \\{"memory": {"boot": ["0x0", "1K"], "ram": ["0x20000000", "264K"]}, "place": {"vectors": "boot", "code": "ram"}, "stack": "16K"}
;

test "the RP2040 flash description makes the script of selka-flash/link.ld: the numbers, the sections and the boot stage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buffer: [256]u8 = undefined;
    const layout = (try layoutOf(arena.allocator(), flash_description, &buffer)).layout;
    const text = try generate(arena.allocator(), layout);
    for ([_][]const u8{
        "  FLASH (rx) : ORIGIN = 0x10000000, LENGTH = 0x1FF000\n  RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 0x3B000\n",
        "__stack_top = 0x2003F000;\n__stack_limit = __stack_top - 0x4000;\nENTRY(myl_bare_reset)\n",
        "  .boot2 ORIGIN(FLASH) : {\n",
        "  } > FLASH\n  .vectors ORIGIN(FLASH) + 0x100 : { KEEP(*(.vectors)) } > FLASH\n",
        "  .text : { *(.text*) *(.rodata*) . = ALIGN(4); } > FLASH\n",
        "*(.ramfunc*) . = ALIGN(4); *(.data*) . = ALIGN(4); __data_end = .; } > RAM AT > FLASH\n  __data_load = LOADADDR(.data);\n",
        "  .bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > RAM\n  __heap_start = .;\n  __heap_end = __stack_limit;\n",
        "  __flash_image_end = LOADADDR(.data) + SIZEOF(.data);\n  ASSERT(SIZEOF(.boot2) == 256, ",
    }) |piece| try std.testing.expect(std.mem.indexOf(u8, text, piece) != null);
    // The 64 words of the sealed stage: the first is the code's first four bytes, the last is the checksum.
    try std.testing.expect(std.mem.indexOf(u8, text, "LONG(0x4B0CB500)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "LONG(0xE11EF9DF)") != null);
    try std.testing.expectEqual(@as(usize, 64), std.mem.count(u8, text, "LONG("));
}

test "the QEMU description makes the script of scripts/bare/qemu/link.ld: vectors at 0, everything else in RAM, no copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buffer: [256]u8 = undefined;
    const layout = (try layoutOf(arena.allocator(), qemu_description, &buffer)).layout;
    const text = try generate(arena.allocator(), layout);
    for ([_][]const u8{
        "  BOOT (rx) : ORIGIN = 0x0, LENGTH = 0x400\n  RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 0x3E000\n",
        "__stack_top = 0x20042000;\n__stack_limit = __stack_top - 0x4000;\n",
        "  .vectors : { KEEP(*(.vectors)) } > BOOT\n  .text : { *(.text*) *(.rodata*) } > RAM\n",
        "} > RAM\n  __data_load = __data_start;\n",
        "  __heap_end = __stack_limit;\n  ASSERT(__heap_start + 4K <= __heap_end,",
    }) |piece| try std.testing.expect(std.mem.indexOf(u8, text, piece) != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "__flash_image_end") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, ".boot2") == null);
}

test "a stack in a region of its own leaves the heap the whole data region (selka-ram: 252K of RAM, 8K of SRAM4 and SRAM5 for the stack)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buffer: [256]u8 = undefined;
    const layout = (try layoutOf(arena.allocator(),
        \\{"memory": {"ram": ["0x20000000", "252K"], "sram45": ["0x20040000", "8K"]}, "stack": ["8K", "sram45"]}
    , &buffer)).layout;
    const text = try generate(arena.allocator(), layout);
    try std.testing.expect(std.mem.indexOf(u8, text, "RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 0x3F000\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "__stack_top = 0x20042000;\n__stack_limit = __stack_top - 0x2000;\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "__heap_end = ORIGIN(RAM) + LENGTH(RAM);\n") != null);
}

/// The refusal `text` meets, or the empty string when it is accepted.
fn refusalOf(arena: std.mem.Allocator, text: []const u8, buffer: []u8) ![]const u8 {
    return switch (try layoutOf(arena, text, buffer)) {
        .refused => |line| line,
        else => "",
    };
}

test "a described device is refused with a line that names the key, the region or the stage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var buffer: [320]u8 = undefined;
    try std.testing.expectEqualStrings("unknown boot stage \"rp2350\"; the boot stages are rp2040-read-03h", try refusalOf(a,
        \\{"memory": {"flash": ["0x10000000", "2M"], "ram": ["0x20000000", "256K"]}, "boot": "rp2350", "stack": "16K"}
    , &buffer));
    try std.testing.expectEqualStrings("regions \"flash\" and \"ram\" overlap", try refusalOf(a,
        \\{"memory": {"flash": ["0x10000000", "2M"], "ram": ["0x101FF000", "256K"]}, "stack": "16K"}
    , &buffer));
    try std.testing.expectEqualStrings("a device's place, stack and boot describe its memory: add \"memory\"", try refusalOf(a, "{\"stack\": \"16K\"}", &buffer));
    try std.testing.expectEqualStrings("a device that describes its memory needs a stack: \"16K\" or [\"8K\", \"REGION\"]", try refusalOf(a,
        \\{"memory": {"ram": ["0x20000000", "264K"]}}
    , &buffer));
    try std.testing.expectEqualStrings("memory needs a region named \"ram\" for the data, or place.data naming one", try refusalOf(a,
        \\{"memory": {"sram": ["0x20000000", "264K"]}, "stack": "16K"}
    , &buffer));
    try std.testing.expectEqualStrings("place.code names the region \"rom\", which memory does not have", try refusalOf(a,
        \\{"memory": {"ram": ["0x20000000", "264K"]}, "place": {"code": "rom"}, "stack": "16K"}
    , &buffer));
    try std.testing.expectEqualStrings("place names vectors, code and data, not \"stack\"", try refusalOf(a,
        \\{"memory": {"ram": ["0x20000000", "264K"]}, "place": {"stack": "ram"}, "stack": "16K"}
    , &buffer));
    try std.testing.expectEqualStrings("the stack of 270336 bytes does not fit region \"ram\" of 270336 bytes with a heap of 4096 bytes", try refusalOf(a,
        \\{"memory": {"ram": ["0x20000000", "264K"]}, "stack": "264K"}
    , &buffer));
    try std.testing.expectEqualStrings("the stack's size must be a size such as \"16K\", above 0 and a multiple of 8, not \"7\"", try refusalOf(a,
        \\{"memory": {"ram": ["0x20000000", "264K"]}, "stack": "7"}
    , &buffer));
    try std.testing.expectEqualStrings("region \"ram\": the length must be a size such as \"2044K\", \"2M\" or \"0x1FF000\", above 0 and ending below 4 GiB, not \"0\"", try refusalOf(a,
        \\{"memory": {"ram": ["0x20000000", "0"]}, "stack": "16K"}
    , &buffer));
    try std.testing.expectEqualStrings("a region's name is lowercase letters, digits and '_' (at most 16), not \"Ram\"", try refusalOf(a,
        \\{"memory": {"Ram": ["0x20000000", "264K"]}, "stack": "16K"}
    , &buffer));
    try std.testing.expectEqualStrings("boot \"rp2040-read-03h\" starts the code region \"flash\", which must hold the vectors too", try refusalOf(a,
        \\{"memory": {"flash": ["0x10000000", "2M"], "ram": ["0x20000000", "256K"]}, "place": {"vectors": "ram"}, "boot": "rp2040-read-03h", "stack": "16K"}
    , &buffer));
    try std.testing.expectEqualStrings("unknown hook \"stop\"; the hooks are start, write, exit, core_register, core1_launch, core_stop, lock, unlock", try refusalOf(a,
        \\{"hooks": {"stop": "board.stop"}}
    , &buffer));
    try std.testing.expectEqualStrings("hook \"write\" must name a function as MODULE.FUNCTION, not \"log_write\"", try refusalOf(a,
        \\{"hooks": {"write": "log_write"}}
    , &buffer));
    // A device with a named script is refused when it also describes its memory, but hooks go beside a script.
    const both = try parse(a, try startupOf(a, qemu_description), true, &buffer);
    try std.testing.expectEqualStrings("a device names a linker_script or describes its memory, not both", both.refused);
    const only_hooks = try parse(a, try startupOf(a, "{\"hooks\": {\"start\": \"board.start\"}}"), true, &buffer);
    try std.testing.expect(only_hooks == .absent);
}

test "sizes are decimal or hex, with K and M, and an overlong or malformed one is no size" {
    try std.testing.expectEqual(@as(?u64, 2093056), parseSize("2044K"));
    try std.testing.expectEqual(@as(?u64, 2097152), parseSize("2M"));
    try std.testing.expectEqual(@as(?u64, 0x1FF000), parseSize("0x1FF000"));
    try std.testing.expectEqual(@as(?u64, 16384), parseSize("16384"));
    try std.testing.expectEqual(@as(?u64, null), parseSize("K"));
    try std.testing.expectEqual(@as(?u64, null), parseSize("0x"));
    try std.testing.expectEqual(@as(?u64, null), parseSize("12G"));
    try std.testing.expectEqual(@as(?u64, null), parseSize("-1"));
}
