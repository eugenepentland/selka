//! Shared finite runtime-schema validation and ownership/result contract propagation.
const std = @import("std");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const cell_types = @import("cell_types.zig");
const Span = @import("source.zig").Span;
const Error = diagnostic.Error;

/// The per-compilation facts the validators keep (see `record_facts.zig`).
pub const Facts = @import("record_facts.zig").Facts;

const Checker = struct {
    allocator: std.mem.Allocator,
    records: []typed.Record,
    sink: *diagnostic.Sink,
    fn finishLayout(self: *Checker, record_index: usize, schema: typed.Record) Error!void {
        const records = self.records;
        var requires_handling = schema.contract.linear;
        var can_store = schema.shape.resource == null;
        // A `@linear` record is not move-only to Core: it is an ordinary record there. Its obligation is the front end's,
        // through the pending-value tracking L1 does (`requires_handling`) and the linear rules (D-FFI-11).
        var move_only = schema.shape.resource != null;
        var linear = schema.contract.linear;
        if (schema.shape.variants) |variants| {
            requires_handling = variants.fallible;
            // A boxed payload is a shared managed reference, like a list element;
            // `boxedContents` holds its value to the list rules.
            for (variants.cases) |case| if (case.payload) |payload| if (!case.boxed) {
                requires_handling = requires_handling or typed.requiresHandling(payload, records);
                can_store = can_store and typed.storable(payload, records);
                move_only = move_only or typed.moveOnly(payload, records);
                linear = linear or typed.linear(payload, records);
            };
        } else if (schema.shape.array) |array| {
            requires_handling = array.length != 0 and typed.requiresHandling(array.element, records);
            can_store = can_store and (array.length == 0 or typed.storable(array.element, records));
            move_only = array.length != 0 and typed.moveOnly(array.element, records);
            linear = array.length != 0 and typed.linear(array.element, records);
        } else if (!schema.managed) {
            for (schema.fields) |field| if (!field.boxed) {
                requires_handling = requires_handling or typed.requiresHandling(field.ty, records);
                can_store = can_store and typed.storable(field.ty, records);
                move_only = move_only or typed.moveOnly(field.ty, records);
                linear = linear or typed.linear(field.ty, records);
            };
        }
        records[record_index].contract.linear = linear;
        if (!schema.managed and schema.shape.variants == null and schema.shape.array == null)
            try @import("linear_rules.zig").checkLinearFields(self.sink, self.allocator, records, records[record_index]);
        records[record_index].contract.storable = can_store;
        records[record_index].contract.move_only = move_only;
        records[record_index].contract.requires_handling = requires_handling;
    }
    /// Walk the records from `first` on. A settled record is complete and reaches
    /// no batch record, so the walk never enters one and it closes no cycle.
    fn validateLayouts(self: *Checker, first: usize) Error!void {
        const allocator = self.allocator;
        const sink = self.sink;
        const records = self.records;
        // Iterative DFS rejects cycles without expanding records or recursing on the host.
        const State = enum { unseen, visiting, complete };
        const states = try allocator.alloc(State, records.len - first);
        defer allocator.free(states);
        @memset(states, .unseen);
        const Visit = struct { record: usize, next_field: usize = 0 };
        var work: std.ArrayList(Visit) = .empty;
        defer work.deinit(allocator);
        for (first..records.len) |root| {
            if (states[root - first] != .unseen) continue;
            states[root - first] = .visiting;
            try work.append(allocator, .{ .record = root });
            while (work.items.len != 0) {
                const last = work.items.len - 1;
                const visit = work.items[last];
                const schema = records[visit.record];
                const container = schema.shape.array != null or schema.shape.buffer != null;
                const edge_count = if (schema.managed) @as(usize, 0) else if (schema.shape.variants) |v| v.cases.len else if (container) @as(usize, 1) else schema.fields.len;
                if (visit.next_field == edge_count) {
                    try self.finishLayout(visit.record, schema);
                    states[visit.record - first] = .complete;
                    _ = work.pop();
                    continue;
                }
                work.items[last].next_field += 1;
                const field: typed.Field = if (schema.shape.variants) |v| .{
                    .name = v.cases[visit.next_field].name,
                    .ty = v.cases[visit.next_field].payload orelse continue,
                    .declaration = v.cases[visit.next_field].declaration,
                    .boxed = v.cases[visit.next_field].boxed,
                } else if (schema.shape.array) |a| .{
                    .name = "element",
                    .ty = a.element,
                    .declaration = schema.declaration,
                } else if (schema.shape.buffer) |element| .{
                    .name = "element",
                    .ty = element,
                    .declaration = schema.declaration,
                } else schema.fields[visit.next_field];
                // A boxed edge is a pointer, so it adds nothing to the layout.
                if (!field.ty.isAggregate() or field.boxed) continue;
                const child = field.ty.recordIndex();
                if (child < first) continue;
                if (states[child - first] == .visiting) return sink.fail(diagnostic.recursive_record, field.declaration, "record fields must form a finite by-value layout; this field closes a cycle");
                if (states[child - first] == .unseen) {
                    states[child - first] = .visiting;
                    try work.append(allocator, .{ .record = child });
                }
            }
        }
    }
};
/// Check the records added since the last call (`records[facts.len..]`) and settle
/// them. Each check reads the settled facts of older records, and those never
/// change, so the diagnostics equal a whole-catalog check of the same records, in
/// the same order. A new catalog starts from empty facts.
pub fn validateFrom(allocator: std.mem.Allocator, records: []typed.Record, facts: *Facts, sink: *diagnostic.Sink) Error!void {
    const first = facts.len;
    if (first > records.len) return error.InternalError;
    try facts.grow(allocator, records.len);
    var checker: Checker = .{ .allocator = allocator, .records = records, .sink = sink };
    try checker.validateLayouts(first);
    try resultObligations(allocator, records, first);
    // Lists preserve pending Result obligations; other containers still require copyable elements.
    for (records[first..]) |schema| if (schema.isCollection()) {
        const element = schema.shape.buffer.?;
        const linear_key = if (schema.collection.key) |key| typed.linear(key, records) else false;
        if (typed.linear(element, records) or linear_key) return @import("linear_rules.zig").refuse(sink, schema.declaration, .container);
        const pending_other = schema.collection.kind != .list and typed.requiresHandling(element, records);
        if (!typed.storable(element, records) or typed.moveOnly(element, records) or pending_other) return sink.failOwnership(
            .{ .code = "E_LIST_ELEMENT", .rule = .T4 },
            schema.declaration,
            "managed collection elements cannot own resources; pending Results require a list",
        );
    };
    // A capability is a scalar handle (5C): a list, dictionary or recursive box may hold one like an integer.
    dependencies(records, first, .file, facts.file.items);
    try boxedContents(records, first, facts.file.items, sink);
    try storedFiles(records, first, facts.site.items, sink);
    try cell_types.validateFrom(records, first, facts.forbidden.items, facts.cell.items, sink);
    facts.checked += records.len - first;
    facts.len = records.len;
}

/// Result obligations follow managed list edges as well as inline fields. Each
/// batch edge and newly pending schema is visited once, including recursive lists.
/// A settled child already holds its final obligation, so it can only make its
/// batch parent pending; no settled record is ever a parent of a batch record.
fn resultObligations(allocator: std.mem.Allocator, records: []typed.Record, first: usize) std.mem.Allocator.Error!void {
    const parents = try allocator.alloc(std.ArrayList(usize), records.len - first);
    @memset(parents, .empty);
    defer {
        for (parents) |*edges| edges.deinit(allocator);
        allocator.free(parents);
    }
    var pending: std.ArrayList(usize) = .empty;
    defer pending.deinit(allocator);
    for (records[first..], first..) |schema, index| {
        for (0..resultChildCount(schema)) |position| {
            const child = resultChild(schema, position) orelse continue;
            if (!child.isAggregate()) continue;
            if (child.recordIndex() < first) {
                if (records[child.recordIndex()].contract.requires_handling) records[index].contract.requires_handling = true;
            } else try parents[child.recordIndex() - first].append(allocator, index);
        }
    }
    for (records[first..], first..) |schema, index| if (schema.contract.requires_handling) try pending.append(allocator, index);
    var cursor: usize = 0;
    while (cursor < pending.items.len) : (cursor += 1) {
        for (parents[pending.items[cursor] - first].items) |parent| {
            if (records[parent].contract.requires_handling) continue;
            records[parent].contract.requires_handling = true;
            try pending.append(allocator, parent);
        }
    }
}

/// The number of types a record inherits pending Result obligations from: an
/// array's element when it stores any, else a list's element, else each variant
/// payload, else each field. Mirrors the precedence `resultChild` reads.
fn resultChildCount(schema: typed.Record) usize {
    if (schema.shape.array) |array| return if (array.length != 0) 1 else 0;
    if (schema.shape.buffer != null) return 1;
    if (schema.shape.variants) |variants| return variants.cases.len;
    return schema.fields.len;
}

/// The type at `position` of `resultChildCount`, or null for a payload-free case.
fn resultChild(schema: typed.Record, position: usize) ?typed.Type {
    if (schema.shape.array) |array| return array.element;
    if (schema.shape.buffer) |element| return element;
    if (schema.shape.variants) |variants| return variants.cases[position].payload;
    return schema.fields[position].ty;
}

/// Named list inspection borrows storage without acknowledging its pending elements.
pub fn pendingList(records: []const typed.Record, ty: typed.Type) bool {
    return ty.isAggregate() and records[ty.recordIndex()].shape.buffer != null and
        records[ty.recordIndex()].collection.kind == .list and typed.requiresHandling(ty, records);
}

/// RECURSIVE-VALUES-2: a boxed value is shared by every copy of its holder,
/// exactly as a list element is, so it obeys the list element rules: no owned
/// resource and no pending result obligation; a capability is a scalar handle (5C) and may be boxed. Checks the boxes
/// of the records from `first` on.
fn boxedContents(records: []const typed.Record, first: usize, files: []const bool, sink: *diagnostic.Sink) Error!void {
    for (records[first..]) |schema| {
        if (schema.shape.variants) |variants| for (variants.cases) |case| {
            if (case.boxed) try boxedContent(records, files, case.payload.?, case.declaration, sink);
        };
        for (schema.fields) |field| if (field.boxed) try boxedContent(records, files, field.ty, field.declaration, sink);
    }
}
fn boxedContent(records: []const typed.Record, files: []const bool, ty: typed.Type, declaration: Span, sink: *diagnostic.Sink) Error!void {
    const owns_resource = typed.moveOnly(ty, records) or carries(ty, files, .file);
    if (!typed.storable(ty, records) or owns_resource or typed.requiresHandling(ty, records))
        return sink.failOwnership(.{ .code = diagnostic.recursive_record, .rule = .T4 }, declaration, "a recursive value type is shared through immutable boxes, so it cannot hold an owned resource or an unhandled result");
}

/// What the open-file refusal says, word for word as the ownership check's refusal of a local that holds one
/// (`file_held` in `core/single_owner.zig`).
const file_held = "an open file cannot be held inside a list, record, variant or callback type: it belongs to its `with` block; " ++
    "call its methods there, or lend it to a helper declared `mut f: File` and called as `put(mut f, data)`";

/// P4 where the type is written: no record of the batch stores an open file below its top, however a list, option, variant,
/// generic or callback type carries it. The ownership check refuses the same types when a local or a return has one, so a record
/// that holds a file is refused whether or not anything uses it. What a record stores is `typed.Record.eachStored`, which also says
/// that a fallible variant hands its file on and a fixed array of no elements stores none. `sites` says where each generic
/// instance was written (`Facts.site`).
fn storedFiles(records: []const typed.Record, first: usize, sites: []const Span, sink: *diagnostic.Sink) Error!void {
    for (records[first..], sites[first..]) |schema, site| {
        try schema.eachStored(Error, Held{ .sink = sink, .site = if (site.end != 0) site else null }, refuseFile);
    }
}

/// The sink a refusal goes to, and the spelling of a generic instance it points at instead of the instance's own field.
const Held = struct { sink: *diagnostic.Sink, site: ?Span };

fn refuseFile(held: Held, ty: typed.Type, at: Span) Error!void {
    if (ty.isFile()) return held.sink.failOwnership(.{ .code = "E_WITH_RESOURCE", .rule = .P4 }, held.site orelse at, file_held);
}
const Dependency = enum { managed, file };
fn carries(ty: typed.Type, contains: []const bool, kind: Dependency) bool {
    if (kind == .file and ty.isFile()) return true;
    return ty.isAggregate() and contains[ty.recordIndex()];
}
/// Set the carrier flags of the batch `records[first..]` by a least fixed point.
/// The flags of settled records are already final, so only the batch is computed.
fn dependencies(records: []const typed.Record, first: usize, kind: Dependency, flags: []bool) void {
    for (records[first..], flags[first..]) |schema, *contains| contains.* = kind == .managed and schema.managed;
    var changed = true;
    while (changed) {
        changed = false;
        for (records[first..], first..) |schema, index| {
            if (flags[index]) continue;
            if (recordCarries(schema, flags, kind)) {
                flags[index] = true;
                changed = true;
            }
        }
    }
}
fn recordCarries(schema: typed.Record, flags: []const bool, kind: Dependency) bool {
    // File ownership belongs to inline storage. A managed reference keeps its
    // own separate layout and must not turn its holder into a resource body.
    if (kind == .file and schema.managed) return false;
    if (schema.shape.array) |array| if (kind != .file or array.length != 0) {
        if (carries(array.element, flags, kind)) return true;
    };
    if (schema.shape.domain) |domain| if (carries(domain, flags, kind)) return true;
    // A boxed field or case holds a managed reference itself (RECURSIVE-VALUES-2).
    if (schema.shape.variants) |variants| for (variants.cases) |case| {
        if (case.boxed and kind == .managed) return true;
        if (case.payload) |payload| if (carries(payload, flags, kind)) return true;
    };
    for (schema.fields) |field| {
        if (field.boxed and kind == .managed) return true;
        if (carries(field.ty, flags, kind)) return true;
    }
    return false;
}

/// The schema of a tuple type, or null for any other type. A tuple's element
/// types are its fields in positional order, which is what keeps every consumer
/// reading one marker instead of a spelling.
pub fn tupleRecord(records: []const typed.Record, ty: typed.Type) ?typed.Record {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const schema = records[ty.recordIndex()];
    return if (schema.shape.tuple) schema else null;
}

// O0 build-time probe: the nominal requirement normally refuses this before layout.
test "ownership coverage constructed list schema reaches element refusal" {
    const span: Span = .{ .start = 0, .end = 0 };
    var records = [_]typed.Record{
        .{ .id = @fromBackingInt(0), .name = "List", .declaration = span, .managed = true, .fields = &.{}, .shape = .{ .buffer = @fromBackingInt(typed.Type.record_base + 1) } },
        .{ .id = @fromBackingInt(1), .name = "Handle", .declaration = span, .managed = false, .fields = &.{}, .shape = .{ .resource = .filesystem } },
    };
    var facts: Facts = .{};
    defer facts.deinit(std.testing.allocator);
    var sink: diagnostic.Sink = .{ .allocator = std.testing.allocator };
    defer sink.deinit();
    try std.testing.expectError(error.SourceError, validateFrom(std.testing.allocator, &records, &facts, &sink));
    try std.testing.expectEqualStrings("E_LIST_ELEMENT", sink.items.items[0].code);
}

const testing = std.testing;
const probe_span: Span = .{ .start = 4, .end = 9 };
const value_of_record_zero = [_]typed.Field{.{ .name = "value", .declaration = probe_span, .ty = @fromBackingInt(typed.Type.record_base) }};

/// A plain record `index` with the given fields, named for its place in the test.
fn plainRecord(index: usize, fields: []const typed.Field) typed.Record {
    return .{ .id = @fromBackingInt(typed.Type.record_base + index), .name = "Plain", .declaration = probe_span, .fields = fields };
}

/// Set `records[from..to]` to plain records numbered from `from`, each with `fields`.
fn fillPlain(records: []typed.Record, from: usize, to: usize, fields: []const typed.Field) void {
    for (records[from..to], from..) |*record, index| record.* = plainRecord(index, fields);
}

/// The first diagnostic a check reports, or null when the check passes.
const Outcome = struct { code: []const u8, span: Span };

/// Validate `records` in one whole-catalog pass, the reference the incremental path must match.
fn wholeCheck(allocator: std.mem.Allocator, records: []typed.Record) !?Outcome {
    var facts: Facts = .{};
    defer facts.deinit(allocator);
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    defer sink.deinit();
    validateFrom(allocator, records, &facts, &sink) catch |err| {
        if (err != error.SourceError) return err;
        return .{ .code = sink.items.items[0].code, .span = sink.items.items[0].span };
    };
    return null;
}

/// Validate `settled` records first, then the rest as a late batch, the way a
/// body that interns a generic instance after collection does.
fn batchCheck(allocator: std.mem.Allocator, records: []typed.Record, settled: usize) !?Outcome {
    var facts: Facts = .{};
    defer facts.deinit(allocator);
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    defer sink.deinit();
    try validateFrom(allocator, records[0..settled], &facts, &sink);
    validateFrom(allocator, records, &facts, &sink) catch |err| {
        if (err != error.SourceError) return err;
        return .{ .code = sink.items.items[0].code, .span = sink.items.items[0].span };
    };
    return null;
}

test "validateFrom checks each record once across calls" {
    const settled = 2000;
    const added = 10;
    const buffer = try testing.allocator.alloc(typed.Record, settled + added);
    defer testing.allocator.free(buffer);
    fillPlain(buffer, 0, settled, &.{});
    var facts: Facts = .{};
    defer facts.deinit(testing.allocator);
    var sink: diagnostic.Sink = .{ .allocator = testing.allocator };
    defer sink.deinit();
    try validateFrom(testing.allocator, buffer[0..settled], &facts, &sink);
    try testing.expectEqual(@as(usize, settled), facts.checked);
    fillPlain(buffer, settled, settled + added, &value_of_record_zero);
    try validateFrom(testing.allocator, buffer, &facts, &sink);
    try testing.expectEqual(@as(usize, settled + added), facts.checked);
    try testing.expectEqual(@as(usize, settled + added), facts.len);
    try testing.expectEqual(@as(usize, 0), sink.items.items.len);
}

test "a late record closing a by-value layout cycle is refused as a whole-catalog check refuses it" {
    const settled = 3;
    var buffer: [settled + 2]typed.Record = undefined;
    fillPlain(&buffer, 0, settled, &.{});
    const a_field = [_]typed.Field{.{ .name = "b", .declaration = .{ .start = 10, .end = 11 }, .ty = @fromBackingInt(typed.Type.record_base + settled + 1) }};
    const b_field = [_]typed.Field{.{ .name = "a", .declaration = .{ .start = 20, .end = 21 }, .ty = @fromBackingInt(typed.Type.record_base + settled) }};
    buffer[settled] = plainRecord(settled, &a_field);
    buffer[settled + 1] = plainRecord(settled + 1, &b_field);
    const late = (try batchCheck(testing.allocator, &buffer, settled)) orelse return error.TestExpectedError;
    const whole = (try wholeCheck(testing.allocator, &buffer)) orelse return error.TestExpectedError;
    try testing.expectEqualStrings(diagnostic.recursive_record, late.code);
    try testing.expectEqualStrings(whole.code, late.code);
    try testing.expectEqual(whole.span.start, late.span.start);
    try testing.expectEqual(whole.span.end, late.span.end);
    try testing.expectEqual(@as(usize, 20), late.span.start);
}

test "a late list of a settled capability carrier is accepted as a whole-catalog check accepts it" {
    const settled = 2;
    var buffer: [settled + 1]typed.Record = undefined;
    // Record 0 holds a clock capability; record 1 holds record 0. A capability is a scalar handle (5C), so a list of
    // either is an ordinary list, in a late batch as in a whole-catalog check.
    const holds_clock = [_]typed.Field{.{ .name = "clock", .declaration = probe_span, .ty = .clock_cap }};
    const holds_holder = [_]typed.Field{.{ .name = "holder", .declaration = probe_span, .ty = @fromBackingInt(typed.Type.record_base) }};
    buffer[0] = plainRecord(0, &holds_clock);
    buffer[1] = plainRecord(1, &holds_holder);
    buffer[settled] = .{
        .id = @fromBackingInt(typed.Type.record_base + settled),
        .name = "List",
        .declaration = .{ .start = 30, .end = 34 },
        .managed = true,
        .fields = &.{},
        .shape = .{ .buffer = @fromBackingInt(typed.Type.record_base + 1) },
    };
    try testing.expect((try batchCheck(testing.allocator, &buffer, settled)) == null);
    try testing.expect((try wholeCheck(testing.allocator, &buffer)) == null);
}

test "a late boxed record holding a settled file is refused as a whole-catalog check refuses it" {
    const settled = 1;
    var buffer: [settled + 1]typed.Record = undefined;
    // The settled record hands a file on (a fallible variant), the one shape that may hold a file where it is declared.
    const hands_file_on = [_]typed.Variant{.{ .name = "ok", .declaration = probe_span, .payload = .file }};
    buffer[0] = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "Opened", .declaration = probe_span, .fields = &.{}, .shape = .{
        .variants = .{ .fallible = true, .is_union = true, .cases = &hands_file_on },
    } };
    const boxed_link = [_]typed.Field{.{ .name = "next", .declaration = .{ .start = 40, .end = 44 }, .ty = @fromBackingInt(typed.Type.record_base), .boxed = true }};
    buffer[settled] = plainRecord(settled, &boxed_link);
    const late = (try batchCheck(testing.allocator, &buffer, settled)) orelse return error.TestExpectedError;
    const whole = (try wholeCheck(testing.allocator, &buffer)) orelse return error.TestExpectedError;
    try testing.expectEqualStrings(diagnostic.recursive_record, late.code);
    try testing.expectEqualStrings(whole.code, late.code);
    try testing.expectEqual(whole.span.start, late.span.start);
    try testing.expectEqual(whole.span.end, late.span.end);
}

test "a late batch of valid records settles without a diagnostic" {
    const settled = 4;
    var buffer: [settled + 3]typed.Record = undefined;
    fillPlain(&buffer, 0, settled, &.{});
    fillPlain(&buffer, settled, settled + 3, &value_of_record_zero);
    try testing.expect((try batchCheck(testing.allocator, &buffer, settled)) == null);
}

/// The first diagnostic of a whole-catalog check of one plain record with one field of type `ty` declared at `at`.
fn holdsAt(ty: typed.Type, at: Span) !?Outcome {
    const fields = [_]typed.Field{.{ .name = "held", .declaration = at, .ty = ty }};
    var records = [_]typed.Record{plainRecord(0, &fields)};
    return wholeCheck(testing.allocator, &records);
}

test "a record that stores an open file is refused where it is declared, at the field, whether or not anything uses it" {
    const at: Span = .{ .start = 11, .end = 18 };
    for ([_]typed.Type{ .file, .text_file }) |ty| {
        const refused = (try holdsAt(ty, at)) orelse return error.TestExpectedError;
        try testing.expectEqualStrings("E_WITH_RESOURCE", refused.code);
        try testing.expectEqual(at, refused.span);
    }
    try testing.expect((try holdsAt(.i64, at)) == null);
    try testing.expect((try holdsAt(.clock_cap, at)) == null);
}

test "a list, dictionary, fixed array, variant or callback that stores an open file is refused, a fallible variant that hands one on is not" {
    const at: Span = .{ .start = 30, .end = 34 };
    const base: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "Stores", .declaration = at, .fields = &.{} };
    var list = base;
    list.managed = true;
    list.shape = .{ .buffer = .file };
    var dictionary = list;
    dictionary.collection = .{ .kind = .dictionary, .key = .i64 };
    var keyed = dictionary;
    keyed.collection = .{ .kind = .dictionary, .key = .file, .set = true };
    keyed.shape = .{ .buffer = .i64 };
    var array = base;
    array.shape = .{ .array = .{ .element = .text_file, .length = 2 } };
    const payload = [_]typed.Variant{.{ .name = "open", .declaration = at, .payload = .file }};
    var variant = base;
    variant.shape = .{ .variants = .{ .is_union = true, .cases = &payload } };
    var callback = base;
    callback.contract.callback = .{ .parameters = &.{.file}, .return_type = .i64 };
    var answers = base;
    answers.contract.callback = .{ .parameters = &.{}, .return_type = .file };
    for ([_]typed.Record{ list, dictionary, keyed, array, variant, callback, answers }) |schema| {
        var records = [_]typed.Record{schema};
        const refused = (try wholeCheck(testing.allocator, &records)) orelse return error.TestExpectedError;
        try testing.expectEqualStrings("E_WITH_RESOURCE", refused.code);
        try testing.expectEqual(at, refused.span);
    }
    var handed_on = variant;
    handed_on.shape = .{ .variants = .{ .fallible = true, .is_union = true, .cases = &payload } };
    var records = [_]typed.Record{handed_on};
    try testing.expect((try wholeCheck(testing.allocator, &records)) == null);
    var empty = array;
    empty.shape = .{ .array = .{ .element = .text_file, .length = 0 } };
    records = .{empty};
    try testing.expect((try wholeCheck(testing.allocator, &records)) == null);
}
