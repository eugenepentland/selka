//! Generic fixed arrays preserve shape, nominal identity, borrowing, and universal checking.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const factories = "domain Component:u64{fn make(n:u64)->Component{return wrap<Component>(n);}}" ++
    "domain Net:u64{fn make(n:u64)->Net{return wrap<Net>(n);}}";
const helpers = "fn pair<T:copy>(a:T,b:T)->[2]T{return new [2]T[a,b];}" ++
    "fn contains<T:equality>(a:[2]T,n:T)->bool{let mut i=0u64;while i<len(a){if a[i]==n{return true;}i=i+1u64;}return false;}";
fn value(allocator: std.mem.Allocator, source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(allocator, "arrays.my", source);
    defer compilation.deinit();
    try t.expectEqual(expected, (try compilation.execute(allocator)).value);
}
fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bad-arrays.my", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
const membership = factories ++ helpers ++ "fn main()->i64{" ++
    "let components=pair::<Component>(Component.make(1u64),Component.make(2u64));" ++
    "let nets=pair::<Net>(Net.make(8u64),Net.make(9u64));" ++
    "if contains::<Component>(components,Component.make(2u64)) && !contains::<Component>(components,Component.make(8u64)) && contains::<Net>(nets,Net.make(9u64)){return 1;}return 0;}";
// spec: GENERIC-ARRAY-1
test "generic array membership reuses code across nominal IDs without mixing domains" {
    try value(t.allocator, membership, 1);
    try reject(factories ++ helpers ++ "fn main()->i64{discard contains::<Component>(pair::<Net>(Net.make(1u64),Net.make(2u64)),Component.make(1u64));return 0;}", "E_TYPE");
}

test "generic arrays nest substitute across calls and match concrete helper shapes" {
    try value(t.allocator, helpers ++
        "fn matrix<T:copy>(x:T)->[2][2]T{return pair::<[2]T>(pair::<T>(x,x),pair::<T>(x,x));}" ++
        "fn concrete(a:[2]i64)->i64{return a[0]+a[1];}" ++
        "fn caller<T:copy>(x:T)->i64{discard matrix::<T>(x);return concrete(pair::<i64>(3,4));}" ++
        "fn main()->i64{let a=matrix::<i64>(9);return a[1][0]+caller::<bool>(true);}", 16);
    try value(t.allocator, "fn empty<T:copy>()->[0]T{return new [0]T[];}fn main()->i64{return cast<i64>(len(empty::<bool>()));}", 0);
}

test "generic array templates reject invalid uncalled bodies and invalid lengths" {
    const cases = [_]struct { source: []const u8, code: []const u8 }{
        .{ .source = "fn f<T:copy,U:copy>(a:[2]T)->[2]U{return a;}", .code = "E_GENERIC_TYPE" },
        .{ .source = "fn f<T:copy>(a:T)->[2]T{return new [2]T[a];}", .code = "E_ARRAY_LENGTH" },
        .{ .source = "fn f<T:copy>(a:[2]T)->T{return a[0]+a[1];}", .code = "E_GENERIC_OPERATION" },
        .{ .source = "fn f<T:copy>(a:[2]T)->bool{return a[0]==a[1];}", .code = "E_GENERIC_OPERATION" },
        .{ .source = "fn f<T:equality>(a:[2]T)->bool{return a==a;}", .code = "E_GENERIC_OPERATION" },
        .{ .source = "fn f<T:copy>(a:[2]T)->[3]T{return a;}", .code = "E_GENERIC_TYPE" },
        .{ .source = "fn f<T:copy>(a:[2]T)->T{return a[true];}", .code = "E_GENERIC_OPERATION" },
        .{ .source = "fn f<T:copy>(a:T)->[2]T{return new [2]T[a,true];}", .code = "E_GENERIC_TYPE" },
        .{ .source = "fn f<T:copy>(a:[2]Missing)->i64{return 0;}", .code = "E_UNKNOWN_TYPE" },
        .{ .source = "fn f<T:copy>(a:[1u64]T)->i64{return 0;}", .code = "E_ARRAY_LENGTH" },
        .{ .source = "fn f<T:copy>(a:[18446744073709551615]T)->i64{return 0;}", .code = "E_ARRAY_LENGTH" },
        .{ .source = "fn f<T:copy>(a:[T]i64)->i64{return 0;}", .code = "E_GENERIC_ARRAY_KEY" },
        .{ .source = "enum Key{a,b}fn f<T:copy>(a:[Key]T)->i64{return 0;}", .code = "E_GENERIC_ARRAY_KEY" },
    };
    for (cases) |case| {
        const source = try std.mem.concat(t.allocator, u8, &.{ case.source, "fn main()->i64{return 0;}" });
        defer t.allocator.free(source);
        try reject(source, case.code);
    }
}

const views = "fn window<T:copy>(a:&[2]T)->&[]T from a{borrow a[0..2] as s{return s;}}" ++
    "fn edit<T:copy>(x:T,y:T)->T{let mut a=new [2]T[x,y];let original=a;" ++
    "borrow mut a[0..2] as s{write_slice(s,0,y);}a=replace(a,1,x);" ++
    "borrow a as whole{borrow window::<T>(whole) as part{discard read_slice(part,0);}}return original[0];}";
test "generic array mutations views and returned input slices preserve snapshots" {
    try value(t.allocator, views ++ "fn main()->i64{return edit::<i64>(7,9);}", 7);
    try reject("fn f<T:copy>(x:T)->T{let mut a=new [1]T[x];borrow mut a[0..1] as s{return a[0];}}fn main()->i64{return 0;}", "E_BORROW_CONFLICT");
    try reject("fn f<T:copy>(input:&[]T,x:T)->&[]T from input{let a=new [1]T[x];borrow a[0..1] as s{return s;}}fn main()->i64{return 0;}", "E_RETURN_LIFETIME");
}

fn allocations(allocator: std.mem.Allocator) !void {
    try value(allocator, membership, 1);
    try value(allocator, views ++ "fn main()->i64{return edit::<i64>(7,9);}", 7);
}
test "generic array specialization and execution clean up under allocation failure" {
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocations, .{});
}

test "generic array runtime indexing retains traps and source locations" {
    var compilation = try language.Compilation.init(t.allocator, "bounds.my", helpers ++
        "fn at<T:copy>(a:[2]T,i:u64)->T{return a[i];}fn main()->i64{return at::<i64>(pair::<i64>(1,2),2u64);}");
    defer compilation.deinit();
    const result = try compilation.execute(t.allocator);
    try t.expectEqualStrings("R_INDEX_BOUNDS", result.trap.code);
    try t.expectEqualStrings("a[i]", compilation.src.text(result.trap.span));
}

const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "module main;import collection as c;import model as m;fn main()->i64{" ++
            "if c::contains::<m::Id>(c::pair::<m::Id>(m::Id.make(3),m::Id.make(5)),m::Id.make(5)){return 1;}return 0;}");
        if (std.mem.eql(u8, path, "collection.my")) return allocator.dupe(u8, "module collection;export pair;export contains;" ++ helpers);
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8, "module model;export Id;domain Id:i64{fn make(n:i64)->Id{return wrap<Id>(n);}}");
        return error.NotFound;
    }
};
fn moduleScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 1), (try language.vm.run(allocator, compilation.code.?)).value);
}
test "exported generic arrays resolve imported nominal arguments across source relocation" {
    try moduleScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), moduleScenario, .{});
}

test "generic arrays retain concrete identity reuse and formatter round trips" {
    var compilation = try language.Compilation.init(t.allocator, "format.my", helpers ++
        "fn main()->i64{let a:[2]i64=pair::<i64>(1,2);let b=pair::<i64>(3,4);return a[0]+b[1];}");
    defer compilation.deinit();
    try compilation.check();
    var count: usize = 0;
    for (compilation.program.?.records) |record| {
        if (record.shape.array) |shape| if (shape.element == .i64 and shape.length == 2) {
            count += 1;
        };
    }
    try t.expectEqual(@as(usize, 1), count);
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try value(t.allocator, formatted, 5);
    var again = try language.Compilation.init(t.allocator, "again.my", formatted);
    defer again.deinit();
    const stable = try again.format(t.allocator);
    defer t.allocator.free(stable);
    try t.expectEqualStrings(formatted, stable);
}

test "generic arrays retain copy obligations and arena escape checks" {
    try reject("resource File:filesystem;" ++ helpers ++ "fn owner(x:File)->[2]File{return pair::<File>(x,x);}fn main()->i64{return 0;}", "E_GENERIC_ARGUMENT");
    try reject("result R{ok:i64,err:i64}" ++ helpers ++ "fn main()->i64{discard pair::<R>(new R.ok(1),new R.err(2));return 0;}", "E_GENERIC_ARGUMENT");
    try value(t.allocator, "resource File:filesystem;" ++ helpers ++
        "fn main()->i64{let empty=new [0]File[];discard pair::<[0]File>(empty,empty);return 1;}", 1);
    try reject(helpers ++ "fn f<T:copy>(heap:allocator)->[2]allocator{arena heap as child{return pair::<allocator>(child,child);}}fn main()->i64{return 0;}", "E_ARENA_ESCAPE");
    try reject(helpers ++ "fn bad(heap:allocator)->[2]allocator{arena heap as child{return pair::<allocator>(child,child);}}fn main()->i64{return 0;}", "E_ARENA_ESCAPE");
}

test "expanding generic array recursion stops at the specialization budget" {
    try reject("fn grow<T:copy>(x:T)->i64{return grow::<[1]T>(new [1]T[x]);}fn main()->i64{return grow::<i64>(1);}", "E_GENERIC_LIMIT");
    var compilation = try language.Compilation.init(t.allocator, "shape-budget.my", "fn grow<T:copy>(x:T)->i64{discard new [2]T[x,x];return grow::<[1]T>(new [1]T[x]);}fn main()->i64{return grow::<i64>(1);}");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_GENERIC_LIMIT", compilation.diagnostics.items[0].code);
    try t.expectEqualStrings("generic array specialization exceeds 4096 distinct shapes", compilation.diagnostics.items[0].message);
}
