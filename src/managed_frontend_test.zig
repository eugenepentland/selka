//! Managed list generic contracts, recursive nominal layouts, and source formatting.
const std = @import("std");
const t = std.testing;
const debug = std.debug.print;
const language = @import("compiler.zig");

fn evaluate(bytes: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "managed-generic.my", bytes);
    defer compilation.deinit();
    const result = compilation.execute(t.allocator) catch |err| {
        for (compilation.diagnostics.items) |diag| debug("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(@as(i64, 42), result.value);
}
// spec: GC-GENERIC-1
test "managed generic list creation mutation and copy identity preserve shared aliases" {
    try evaluate("list Items<T:copy>:T;" ++
        "fn make<T:copy>()->Items<T>{return new_list<Items<T>>(0);}" ++
        "fn add<T:copy>(items:Items<T>,value:T)->unit{append_list(items,value);}" ++
        "fn identity<T:copy>(value:T)->T{return value;}" ++
        "fn main()->i64{let values=make::<i64>();let alias=identity(values);" ++
        "add::<i64>(alias,42);return read_list(values,0);}");
}
// spec: GC-GENERIC-2
test "managed nominal recursive list record edges allow finite reference graphs" {
    try evaluate("list Children<T:copy>:Node<T>;struct Node<T:copy>{value:T,children:Children<T>}" ++
        "fn main()->i64{let children=new_list<Children<i64>>(0);" ++
        "let node=new Node<i64>{value:42,children:children};append_list(children,node);" ++
        "let child=read_list(children,0);return child.value;}");
}
// spec: GC-GENERIC-3
test "managed nominal indirection does not admit recursive by value records" {
    var compilation = try language.Compilation.init(t.allocator, "managed-invalid.my", "list Items<T:copy>:T;struct Bad<T:copy>{nested:Bad<T>}fn main()->i64{return 0;}");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_RECURSIVE_RECORD", compilation.diagnostics.items[0].code);
}

// spec: GC-GENERIC-4
test "managed list formatting preserves contextual list case identifiers" {
    var compilation = try language.Compilation.init(t.allocator, "managed-format.my", "enum Kind{list,atom}list Values:i64;fn main()->i64{let values=new_list<Values>(0);append_list(values,42);return read_list(values,0);}");
    defer compilation.deinit();
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "new_list<Values>(0)") != null);
    try evaluate(formatted);
}

// spec: GC-GENERIC-5
test "managed lists reject nested and generic capabilities before helper alias escape" {
    const cases = [_][]const u8{
        "struct Box{value:[1]allocator}list Caps:Box;fn main()->i64{return 0;}",
        "list Caps<T:copy>:T;fn main()->i64{let values=new_list<Caps<allocator>>(0);return cast<i64>(len_list(values));}",
        "list Caps:filesystem_cap;fn main()->i64{return 0;}",
    };
    for (cases) |bytes| {
        var compilation = try language.Compilation.init(t.allocator, "managed-capability.my", bytes);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings("E_LIST_CAPABILITY", compilation.diagnostics.items[0].code);
    }
}
