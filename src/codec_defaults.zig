//! The declared defaults `json.decode` gives a missing member (CODEC-1, step 1): "a missing member takes the field's
//! declared default, and a field without a default is required". A default is a source expression, checked where a
//! constructor builds it; a decoder builds the record in Core, so the checker makes one function per defaulted field
//! of every record a `json.decode` instance of the program reads, named `@default:Record.field`, whose body is the
//! checked default. `core/build_json.zig` calls it when the member is absent. The name is reserved like a boundary
//! validator's (`invariant_callbacks.zig`): no source can spell it, and the tools that skip compiler-made functions skip it.
//! Each such record with `@invariant` also gets `@holds:Record` (`sema_contracts.invariantTest`), which tests its clauses
//! without trapping, so a decoded value that breaks them makes `json.decode` fail with kind `invariant`.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const codec_form = @import("codec_form.zig");
const collections = @import("collection_lower.zig");
const Error = diagnostic.Error;

/// The reserved prefix of a default's function; `core/build_json.zig` looks the function up by it.
pub const prefix = "@default:";

/// The name of the function that builds the default of `field` of the record `record`.
pub fn functionName(allocator: std.mem.Allocator, record: []const u8, field: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}.{s}", .{ prefix, record, field });
}

/// Whether `name` is a `json.decode` instance (`json::decode[app::Store]`).
fn decodes(function: typed.Function) bool {
    return function.policy.builtin and std.mem.startsWith(u8, function.name, "json::decode[");
}

/// The records the `json.decode` instances among `checked` read, each once, in the order they are first met.
fn decodedRecords(allocator: std.mem.Allocator, checked: []const typed.Function, records: []const typed.Record) std.mem.Allocator.Error![]const typed.Type {
    var seen: std.AutoHashMapUnmanaged(typed.Type, void) = .empty;
    defer seen.deinit(allocator);
    var found: std.ArrayList(typed.Type) = .empty;
    var work: std.ArrayList(typed.Type) = .empty;
    defer work.deinit(allocator);
    for (checked) |function| {
        if (!decodes(function)) continue;
        const shape = typed.resultShape(function.signature.return_type, records) orelse continue;
        try work.append(allocator, shape.ok_type);
    }
    while (work.pop()) |ty| {
        if ((try seen.getOrPut(allocator, ty)).found_existing) continue;
        switch (codec_form.kind(ty, records)) {
            .record => {
                try found.append(allocator, ty);
                for (records[ty.recordIndex()].fields) |field| try work.append(allocator, field.ty);
            },
            .variants => for (records[ty.recordIndex()].shape.variants.?.cases) |case| if (case.payload) |payload| try work.append(allocator, payload),
            .list => try work.append(allocator, records[ty.recordIndex()].shape.buffer.?),
            .fixed_array => try work.append(allocator, records[ty.recordIndex()].shape.array.?.element),
            else => {},
        }
    }
    return found.toOwnedSlice(allocator);
}

/// One function per defaulted field of every record a `json.decode` instance among `checked` reads, and the invariant
/// test of each such record that carries `@invariant`.
pub fn functions(comptime Checker: type, self: *Checker, checked: []const typed.Function) Error![]typed.Function {
    var out: std.ArrayList(typed.Function) = .empty;
    const wanted = try decodedRecords(self.allocator, checked, self.catalog.records);
    for (wanted) |ty| {
        const record = self.catalog.records[ty.recordIndex()];
        for (record.fields) |field| {
            if (field.default_value == null) continue;
            try out.append(self.allocator, try defaultFunction(Checker, self, record, field));
        }
        // A record with `@invariant` gets its test, `@holds:Record`: a decoded value that breaks it is an error of kind
        // `invariant`, not a trap (CODEC-INV).
        if (try @import("sema_contracts.zig").invariantTest(Checker, self, ty)) |test_function| try out.append(self.allocator, test_function);
    }
    return out.toOwnedSlice(self.allocator);
}

/// The function whose body returns the checked default of `field`, as a constructor that leaves it out builds it.
fn defaultFunction(comptime Checker: type, self: *Checker, record: typed.Record, field: typed.Field) Error!typed.Function {
    @import("sema_contracts.zig").resetSynthetic(Checker, self);
    self.return_type = field.ty;
    const written: ast.NodeId = @fromBackingInt(field.default_value.?);
    const value = try self.defaultExpected(written, field.ty);
    try self.requireConstantDefault(written, value);
    const b: collections.Builder(Checker) = .{ .checker = self, .span = field.declaration };
    const ret = try b.stmt(.{ .ret = value });
    const body = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{ret}) });
    self.statements.items[@backingInt(body)].terminates = true;
    return .{
        .id = @fromBackingInt(0),
        .name = try functionName(self.allocator, record.name, field.name),
        .declaration = field.declaration,
        .signature = .{ .return_type = field.ty, .parameter_count = 0 },
        .scope = .{ .body_complete = true, .body = body, .locals = try self.locals.toOwnedSlice(self.allocator) },
    };
}
