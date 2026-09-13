//! Source-level managed aliases, VM rooting, effects, and storage boundaries.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");

fn execute(text: []const u8, statistics: *language.vm.GcStatistics) !language.vm.Result {
    var compilation = try language.Compilation.init(t.allocator, "managed.my", text);
    defer compilation.deinit();
    return compilation.executeWithOptions(t.allocator, .{
        .memory = .{ .gc = .{ .stress = true, .statistics = statistics } },
    }) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
}

fn reject(text: []const u8, expected: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid-managed.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(expected, compilation.diagnostics.items[0].code);
}

fn rejectAll(sources: []const []const u8, code: []const u8) !void {
    for (sources) |source| try reject(source, code);
}

// spec: GC-SOURCE-9
test "bytecode rejects managed metadata on an ordinary aggregate" {
    var compilation = try language.Compilation.init(t.allocator, "forged-managed.my", "struct Record{value:i64}fn main()->i64{return 0;}");
    defer compilation.deinit();
    try compilation.emit();
    var program = compilation.code.?;
    const records = try t.allocator.dupe(@import("typed.zig").Record, program.records);
    defer t.allocator.free(records);
    records[0].managed = true;
    program.records = records;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
}

fn allocationFailure(allocator: std.mem.Allocator, program: language.bytecode.Program) !void {
    var statistics: language.vm.GcStatistics = .{};
    const result = language.vm.runWithOptions(allocator, program, .{
        .memory = .{ .gc = .{ .stress = true, .statistics = &statistics } },
    });
    try t.expectEqual(@as(i64, 42), (try result).value);
}

// spec: GC-SOURCE-1
test "managed aliases mutate immutable bindings across helpers without allocator authority" {
    const source = "" ++
        "fn change(values:List<i64>)->unit{values.push(40);values[0u64]=42;}" ++
        "fn main()->i64{let values:List<i64>=[];let alias=values;change(alias);" ++
        "if len(values)!=1{return 1;}return values[0u64];}";
    var statistics: language.vm.GcStatistics = .{};
    const result = try execute(source, &statistics);
    try t.expectEqual(@as(i64, 42), result.value);
    try t.expectEqual(@as(u64, 1), statistics.created);
    try t.expectEqual(@as(usize, 0), statistics.live_objects);
    try t.expect(statistics.collections >= 2);
}

// spec: GC-SOURCE-2
test "managed recursive record cycle is reclaimed at an allocation before VM teardown" {
    const source = "struct Node{children:List<Node>,value:i64}" ++
        "fn cycle()->unit{let nodes:List<Node>=[];" ++
        "nodes.push(new Node{children:nodes,value:42});" ++
        "let node=nodes[0u64];let alias=node.children;alias[0u64]=node;}" ++
        "fn main()->i64{cycle();let spare:List<Node>=[];_ = spare;return 42;}";
    var statistics: language.vm.GcStatistics = .{};
    try t.expectEqual(@as(i64, 42), (try execute(source, &statistics)).value);
    try t.expectEqual(@as(u64, 2), statistics.created);
    try t.expectEqual(@as(u64, 1), statistics.reclaimed);
    try t.expect(statistics.collections >= 3);
}

// spec: GC-SOURCE-3
test "managed intermediate call arguments and record snapshots survive collection" {
    const source = "struct Holder{values:List<i64>}" ++
        "fn make()->List<i64>{let values:List<i64>=[];values.push(42);return values;}" ++
        "fn consume(first:Holder,second:List<i64>)->i64{second.push(9);let values=first.values;return values[0u64];}" ++
        "fn main()->i64{return consume(new Holder{values:make()},[]);}";
    var statistics: language.vm.GcStatistics = .{};
    try t.expectEqual(@as(i64, 42), (try execute(source, &statistics)).value);
    try t.expectEqual(@as(u64, 2), statistics.created);
    try t.expectEqual(@as(u64, 0), statistics.reclaimed);
    try t.expect(statistics.collections >= 4);
}

// spec: GC-SOURCE-4
test "managed bounds traps release all execution roots and backing" {
    for ([_][]const u8{
        "return values[0u64];",
        "values[0u64]=42;return 0;",
    }) |operation| {
        const source = try std.fmt.allocPrint(t.allocator, "fn main()->i64{{let values:List<i64>=[];{s}}}", .{operation});
        defer t.allocator.free(source);
        var statistics: language.vm.GcStatistics = .{};
        const result = try execute(source, &statistics);
        try t.expectEqualStrings("R_LIST_BOUNDS", result.trap.code);
        try t.expectEqual(@as(usize, 0), statistics.live_objects);
        try t.expectEqual(@as(usize, 0), statistics.live_capacity);
    }
}

// spec: GC-SOURCE-6
test "noalloc rejects transitive managed allocation while permitting fixed-slot mutation" {
    for ([_][]const u8{ "noalloc", "noalloc" }) |bound| {
        const create_source = try std.fmt.allocPrint(t.allocator, "fn make()->List<i64>{{return [];}}" ++
            "fn constrained()->List<i64> {s}{{return make();}}fn main()->i64{{return 0;}}", .{bound});
        defer t.allocator.free(create_source);
        try reject(create_source, "E_EFFECT_BOUND");
        const append_source = try std.fmt.allocPrint(t.allocator, "fn grow(values:List<i64>)->unit{{values.push(42);}}" ++
            "fn constrained(values:List<i64>)->unit {s}{{grow(values);}}fn main()->i64{{return 0;}}", .{bound});
        defer t.allocator.free(append_source);
        try reject(append_source, "E_EFFECT_BOUND");
    }
    const source = "" ++
        "fn fixed(values:List<i64>)->unit noalloc{values[0u64]=42;}" ++
        "fn inspect(values:List<i64>)->i64 noalloc{fixed(values);return values[0u64];}" ++
        "fn main()->i64{let values:List<i64>=[];values.push(0);return inspect(values);}";
    var statistics: language.vm.GcStatistics = .{};
    try t.expectEqual(@as(i64, 42), (try execute(source, &statistics)).value);
}

// spec: GC-SOURCE-10
test "managed source execution unwinds roots on every host allocation failure" {
    const source = "struct Holder{values:List<i64>}" ++
        "fn make()->List<i64>{let values:List<i64>=[];values.push(42);return values;}" ++
        "fn consume(first:Holder,second:List<i64>)->i64{second.push(9);let values=first.values;return values[0u64];}" ++
        "fn main()->i64{return consume(new Holder{values:make()},[]);}";
    var compilation = try language.Compilation.init(t.allocator, "managed-oom.my", source);
    defer compilation.deinit();
    try compilation.emit();
    try t.checkAllAllocationFailures(t.allocator, allocationFailure, .{compilation.code.?});
}

// spec: GC-SOURCE-11
test "managed cycles lose local and record roots on block break and continue exits" {
    const prefix = "struct Node{children:List<Node>,value:i64}struct Holder{nodes:List<Node>}";
    const cycle = "let nodes:List<Node>=[];nodes.push(new Node{children:nodes,value:42});" ++
        "let holder=new Holder{nodes:nodes};let alias=holder.nodes;if len(alias)!=1{return 1;}";
    const bodies = [_][]const u8{
        "{" ++ cycle ++ "}",
        "while true{" ++ cycle ++ "break;}",
        "let mut i=0;while i<1{i=i+1;" ++ cycle ++ "continue;}",
    };
    for (bodies) |body| {
        const source = try std.mem.concat(t.allocator, u8, &.{ prefix, "fn main()->i64{", body, "let spare:List<i64>=[];_ = spare;return 42;}" });
        defer t.allocator.free(source);
        var statistics: language.vm.GcStatistics = .{};
        try t.expectEqual(@as(i64, 42), (try execute(source, &statistics)).value);
        try t.expectEqual(@as(u64, 2), statistics.created);
        try t.expectEqual(@as(u64, 1), statistics.reclaimed);
    }
}

// spec: GC-SOURCE-7
test "managed elements reject owned resources and unchecked results" {
    try rejectAll(&.{
        "resource File:filesystem;fn main()->i64{let values:List<File>=[];return len(values);}",
        "resource File:filesystem;struct Wrapper{file:File}fn main()->i64{let values:List<Wrapper>=[];return len(values);}",
        "result Answer{ok:i64,err:i64}fn main()->i64{let values:List<Answer>=[];return len(values);}",
    }, "E_GENERIC_REQUIREMENT");
}
