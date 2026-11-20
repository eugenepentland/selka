//! Rule P4 is refused in two layers: the front end refuses a type that stores an open file where the type is declared
//! (`record_layouts.zig`), and Core refuses a local or a return of one (`single_owner_files.zig`). Both read what a record stores
//! from `typed.Record.eachStored`, so they must give the same verdict for every shape. Core is reached the way its other tests
//! reach it: records built by hand, with the front end bypassed.
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const files = @import("single_owner_files.zig");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");

const span: language.source.Span = .{ .start = 3, .end = 9 };

fn record(index: usize, name: []const u8) typed.Record {
    return .{ .id = @fromBackingInt(typed.Type.record_base + index), .name = name, .declaration = span, .fields = &.{} };
}

const holds_file = [_]typed.Field{.{ .name = "held", .declaration = span, .ty = .file }};
const holds_text_file = [_]typed.Field{.{ .name = "held", .declaration = span, .ty = .text_file }};
const holds_int = [_]typed.Field{.{ .name = "held", .declaration = span, .ty = .i64 }};
const holds_second = [_]typed.Field{.{ .name = "held", .declaration = span, .ty = @fromBackingInt(typed.Type.record_base + 1) }};

/// Whether the front end refuses `records` where they are declared, as `E_WITH_RESOURCE` of rule P4 and nothing else.
fn frontEndRefuses(a: std.mem.Allocator, records: []typed.Record) !bool {
    var facts: language.record_layouts.Facts = .{};
    defer facts.deinit(a);
    var sink: language.diagnostic.Sink = .{ .allocator = a };
    defer sink.deinit();
    const refused = if (language.record_layouts.validateFrom(a, records, &facts, &sink)) |_| false else |err| if (err == error.SourceError) true else return err;
    if (!refused) {
        try std.testing.expectEqual(@as(usize, 0), sink.items.items.len);
        return false;
    }
    try std.testing.expectEqualStrings("E_WITH_RESOURCE", sink.items.items[0].code);
    try std.testing.expectEqual(language.ownership_rules.Rule.P4, sink.items.items[0].provenance.rule.?);
    return true;
}

/// Whether Core's walk refuses a local or a return whose type is the first record, with the front end bypassed.
fn coreRefuses(a: std.mem.Allocator, records: []const typed.Record) !bool {
    var walk = try files.Walk.init(a, records.len);
    defer walk.deinit();
    return if (walk.supported(records, records[0].id)) |_| false else |err| if (err == error.StoredFile) true else return err;
}

/// The two layers' verdicts on `records`, whose first record is the type under test, must both be `refused`.
fn agree(a: std.mem.Allocator, records: []typed.Record, refused: bool) !void {
    try std.testing.expectEqual(refused, try frontEndRefuses(a, records));
    try std.testing.expectEqual(refused, try coreRefuses(a, records));
}

fn single(a: std.mem.Allocator, shape: typed.Record, refused: bool) !void {
    var records = [_]typed.Record{shape};
    try agree(a, &records, refused);
}

test "P4 in both layers: a field, a nested record, a generic instance and a text file are refused" {
    var holder = record(0, "Holder");
    holder.fields = &holds_file;
    try single(std.testing.allocator, holder, true);
    holder.fields = &holds_text_file;
    try single(std.testing.allocator, holder, true);
    var instance = record(0, "Box[File]");
    instance.fields = &holds_file;
    try single(std.testing.allocator, instance, true);
    var nested = [_]typed.Record{ record(0, "Outer"), record(1, "Inner") };
    nested[0].fields = &holds_second;
    nested[1].fields = &holds_file;
    try agree(std.testing.allocator, &nested, true);
    var clean = [_]typed.Record{ record(0, "Outer"), record(1, "Inner") };
    clean[0].fields = &holds_second;
    clean[1].fields = &holds_int;
    try agree(std.testing.allocator, &clean, false);
}

test "P4 in both layers: a list, a dictionary key, a dictionary value and a set element are refused" {
    var list = record(0, "File[]");
    list.managed = true;
    list.shape = .{ .buffer = .file };
    try single(std.testing.allocator, list, true);
    var value = list;
    value.collection = .{ .kind = .dictionary, .key = .i64 };
    try single(std.testing.allocator, value, true);
    var key = value;
    key.collection = .{ .kind = .dictionary, .key = .file };
    key.shape = .{ .buffer = .i64 };
    try single(std.testing.allocator, key, true);
    var set = key;
    set.collection = .{ .kind = .dictionary, .key = .file, .set = true };
    try single(std.testing.allocator, set, true);
    var clean = key;
    clean.collection = .{ .kind = .dictionary, .key = .i64 };
    try single(std.testing.allocator, clean, false);
}

test "P4 in both layers: a fixed array of one file is refused, one of no elements stores nothing" {
    var array = record(0, "FixedArray[File, 1]");
    array.shape = .{ .array = .{ .element = .file, .length = 1 } };
    try single(std.testing.allocator, array, true);
    array.shape = .{ .array = .{ .element = .text_file, .length = 0 } };
    try single(std.testing.allocator, array, false);
}

test "P4 in both layers: an option or enum payload and a callback parameter or result are refused" {
    const payload = [_]typed.Variant{ .{ .name = "some", .declaration = span, .payload = .file }, .{ .name = "none", .declaration = span, .payload = null } };
    var option = record(0, "File?");
    option.shape = .{ .variants = .{ .is_union = true, .cases = &payload } };
    try single(std.testing.allocator, option, true);
    var parameter = record(0, "func(File) -> int");
    parameter.contract.callback = .{ .parameters = &.{.file}, .return_type = .i64 };
    try single(std.testing.allocator, parameter, true);
    var result = record(0, "func() -> File");
    result.contract.callback = .{ .parameters = &.{}, .return_type = .file };
    try single(std.testing.allocator, result, true);
    var clean = record(0, "func(int) -> int");
    clean.contract.callback = .{ .parameters = &.{.i64}, .return_type = .i64 };
    try single(std.testing.allocator, clean, false);
}

test "P4 in both layers: a fallible variant hands its file on, in a declaration, a local and a return" {
    const hands_on = [_]typed.Variant{ .{ .name = "ok", .declaration = span, .payload = .file }, .{ .name = "err", .declaration = span, .payload = .i64 } };
    var opened = record(0, "Opened");
    opened.shape = .{ .variants = .{ .fallible = true, .is_union = true, .cases = &hands_on } };
    try single(std.testing.allocator, opened, false);
    // The same type written in a program: the front end accepts the declaration, and Core accepts a parameter and a return of it.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try support.checkedProgram(a,
        \\result Got:
        \\    ok: File,
        \\    err: int
        \\func forward(own got: Got) -> Got:
        \\    return got
        \\func main() -> int:
        \\    return 0
    );
    var failure: unique.Failure = .{};
    try unique.check(a, program, &failure);
    try std.testing.expectEqualStrings("", failure.message);
}
