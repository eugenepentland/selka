//! The dynamic section of `mylang cost ENTRY.my --counters FILE.json`
//! (NEW-CORE-COUNTERS-5): what a counting build's run (`docs/tooling/counters.md`)
//! recorded, per emitted function the static report lists, with the checks it
//! executed (NEW-CORE-COUNTERS-7). The static rows and
//! totals are printed exactly as without the flag; this section follows them.
const std = @import("std");
const cost = @import("cost.zig");

/// What one function did in the run: calls, count updates, uniqueness tests, copies
/// and bytes moved, and managed allocations.
pub const Dynamic = struct {
    calls: u64 = 0,
    rc: struct { retains: u64 = 0, releases: u64 = 0, runtime: u64 = 0 } = .{},
    unique: struct { tests: u64 = 0, shared: u64 = 0 } = .{},
    copies: u64 = 0,
    /// Bytes copies moved: records, lists, dictionaries, buffers and text.
    copied_bytes: u64 = 0,
    /// Bytes growth moved: lists, dictionaries, buffers and text.
    growth_bytes: u64 = 0,
    allocation: struct { blocks: u64 = 0, bytes: u64 = 0 } = .{},
};

/// The checks one function executed in the run, by what they check (NEW-CORE-COUNTERS-7).
pub const Checks = struct { bounds: u64 = 0, overflow: u64 = 0, division: u64 = 0, shift: u64 = 0, other: u64 = 0 };

/// One row of the section: a function of the static report, its run, and the checks it executed.
pub const Row = struct { name: []const u8, run: Dynamic, checks: Checks = .{} };

/// The check kinds of `emit_count.Kind` and the `Checks` field each one adds to.
const check_kinds = [_]struct { []const u8, []const u8 }{
    .{ "bounds_check", "bounds" }, .{ "overflow_check", "overflow" }, .{ "division_check", "division" }, .{ "shift_check", "shift" }, .{ "other_check", "other" },
};

/// Why the counters document cannot be used.
pub const Error = error{ OutOfMemory, InvalidCounters };

const growth_slots = [_][]const u8{ "list_grow_bytes", "realloc_moved_bytes", "dict_grow_bytes", "buffer_grow_bytes", "text_grow_bytes" };

fn number(object: std.json.ObjectMap, name: []const u8) Error!u64 {
    const value = object.get(name) orelse return 0;
    if (value != .integer or value.integer < 0) return error.InvalidCounters;
    return @intCast(value.integer);
}

fn text(object: std.json.ObjectMap, name: []const u8) Error![]const u8 {
    const value = object.get(name) orelse return error.InvalidCounters;
    if (value != .string) return error.InvalidCounters;
    return value.string;
}

fn items(root: std.json.ObjectMap, name: []const u8) Error![]const std.json.Value {
    const value = root.get(name) orelse return error.InvalidCounters;
    if (value != .array) return error.InvalidCounters;
    return value.array.items;
}

/// The rows of `report`'s functions, in its order, from a `mylang-counters-v1` document.
/// A function the run never entered has an all-zero row.
pub fn rows(a: std.mem.Allocator, report: cost.Report, document: []const u8) Error![]Row {
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, a, document, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidCounters,
    };
    if (parsed != .object) return error.InvalidCounters;
    const root = parsed.object;
    const version = root.get("version") orelse return error.InvalidCounters;
    if (version != .string or !std.mem.eql(u8, version.string, "mylang-counters-v1")) return error.InvalidCounters;
    var by_name: std.array_hash_map.String(Dynamic) = .empty;
    var checks: std.array_hash_map.String(Checks) = .empty;
    for (report.functions) |function| {
        try by_name.put(a, function.name, .{});
        try checks.put(a, function.name, .{});
    }
    for (try items(root, "functions")) |entry| {
        if (entry != .object) return error.InvalidCounters;
        const row = by_name.getPtr(try text(entry.object, "name")) orelse continue;
        row.calls += try number(entry.object, "calls");
        row.rc.runtime += try number(entry.object, "runtime_retains") + try number(entry.object, "runtime_releases");
        row.allocation.blocks += try number(entry.object, "allocs");
        row.allocation.bytes += try number(entry.object, "alloc_bytes");
        for ([_][]const u8{ "list_copy_bytes", "dict_copy_bytes", "buffer_copy_bytes", "text_copy_bytes" }) |bytes| row.copied_bytes += try number(entry.object, bytes);
        for ([_][]const u8{ "list_copies", "dict_copies", "buffer_copies", "text_copies" }) |copies| row.copies += try number(entry.object, copies);
        for (growth_slots) |slot| row.growth_bytes += try number(entry.object, slot);
    }
    for (try items(root, "sites")) |entry| {
        if (entry != .object) return error.InvalidCounters;
        const row = by_name.getPtr(try text(entry.object, "function")) orelse continue;
        const kind = try text(entry.object, "kind");
        const count = try number(entry.object, "count");
        const executed = checks.getPtr(try text(entry.object, "function")).?;
        inline for (check_kinds) |pair| {
            if (std.mem.eql(u8, kind, pair[0])) @field(executed, pair[1]) += count;
        }
        if (std.mem.eql(u8, kind, "retain")) row.rc.retains += count;
        if (std.mem.eql(u8, kind, "release") or std.mem.eql(u8, kind, "release_unique")) row.rc.releases += count;
        if (std.mem.eql(u8, kind, "unique_test")) {
            row.unique.tests += count;
            row.unique.shared += count -| try number(entry.object, "extra");
        }
        // Runtime copies are counted from the function rows above; record copies only here.
        if (std.mem.eql(u8, kind, "record_copy")) {
            row.copies += count;
            row.copied_bytes += try number(entry.object, "bytes");
        }
    }
    const result = try a.alloc(Row, report.functions.len);
    for (report.functions, result) |function, *row| row.* = .{ .name = function.name, .run = by_name.get(function.name).?, .checks = checks.get(function.name).? };
    return result;
}

/// The text section: one line per function, then the sum of the rows.
pub fn render(a: std.mem.Allocator, out: *std.ArrayList(u8), section: []const Row) std.mem.Allocator.Error!void {
    try out.appendSlice(a, "counters (one counting run; executions and bytes, not sites)\n");
    var total: Dynamic = .{};
    var executed: Checks = .{};
    for (section) |row| {
        try line(a, out, row);
        inline for (check_kinds) |pair| @field(executed, pair[1]) += @field(row.checks, pair[1]);
        total.calls += row.run.calls;
        total.rc.retains += row.run.rc.retains;
        total.rc.releases += row.run.rc.releases;
        total.rc.runtime += row.run.rc.runtime;
        total.unique.tests += row.run.unique.tests;
        total.unique.shared += row.run.unique.shared;
        total.copies += row.run.copies;
        total.copied_bytes += row.run.copied_bytes;
        total.growth_bytes += row.run.growth_bytes;
        total.allocation.blocks += row.run.allocation.blocks;
        total.allocation.bytes += row.run.allocation.bytes;
    }
    try line(a, out, .{ .name = "TOTAL", .run = total, .checks = executed });
}

fn line(a: std.mem.Allocator, out: *std.ArrayList(u8), row: Row) std.mem.Allocator.Error!void {
    const d = row.run;
    const c = row.checks;
    const format = "{s}: calls {d}; retains {d}; releases {d}; runtime count updates {d}; unique tests {d} ({d} shared); " ++
        "copies {d} ({d} bytes); growth {d} bytes; allocations {d} ({d} bytes); " ++
        "checks: bounds {d}, overflow {d}, division {d}, shift {d}, other {d}\n";
    const counts = .{ row.name, d.calls, d.rc.retains, d.rc.releases, d.rc.runtime, d.unique.tests, d.unique.shared, d.copies, d.copied_bytes, d.growth_bytes };
    try out.print(a, format, counts ++ .{ d.allocation.blocks, d.allocation.bytes, c.bounds, c.overflow, c.division, c.shift, c.other });
}
