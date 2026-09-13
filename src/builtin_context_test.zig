//! Prelude types and context-directed constructors preserve existing type rules.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const debug = std.debug;
fn run(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "builtin.my", text);
    defer compilation.deinit();
    const result = compilation.executeWithOptions(t.allocator, .{ .memory = .{ .gc = .{ .stress = true } } }) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(@as(i64, 42), result.value);
}

// spec: BUILTIN-CONTEXT-5
test "generic List Result and contextual constructors keep symbolic type parameters" {
    try run("fn singleton<T:copy>(value:T)->List<T>{let values:List<T>=[];values.push(value);return values;}" ++
        "fn answer<T:copy>(value:T)->Result<T,i64>{return Ok(value);}" ++
        "fn main()->i64{let values=singleton(42);let value=values[0];" ++
        "match answer(value){Result<i64,i64>.ok(n)=>{return n;},Result<i64,i64>.err(e)=>{return e;}}}");
}

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid-builtin.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "module main;import model;fn main()->i64{let values:List<i64>=[];values.push(42);" ++
            "match model::answer(values){Result<i64,i64>.ok(n)=>{return n;},Result<i64,i64>.err(e)=>{return e;}}}");
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8, "module model;export answer;fn answer(values:List<i64>)->Result<i64,i64>{return Ok(values[0]);}");
        return error.NotFound;
    }
};

// spec: BUILTIN-CONTEXT-8
test "builtin List and Result share identity across imported module signatures" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 42), (try language.vm.run(t.allocator, compilation.code.?)).value);
}

const ShadowModules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "module main;import model;fn main()->i64{let values:List<i64>=[];values.push(21);return values[0]+model::answer();}");
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8, "module model;export answer;struct List<T:copy>{value:T}fn answer()->i64{let value=List<i64>{value:21};return value.value;}");
        return error.NotFound;
    }
};

// spec: BUILTIN-CONTEXT-9
test "module-local List declaration shadows the prelude only inside its module" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = ShadowModules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 42), (try language.vm.run(t.allocator, compilation.code.?)).value);
}

const ConstructorModules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return allocator.dupe(u8, "module main;fn Ok(value:i64)->i64{return value+1;}fn Err(value:i64)->i64{return value-1;}" ++
            "fn combine<T:copy>(ignored:T)->i64{_ = ignored;return Ok(20)+Err(22);}" ++
            "fn main()->i64{if Ok(1)!=2{return 1;}if Err(1)!=0{return 2;}return combine(true);}");
    }
};

// spec: BUILTIN-CONTEXT-10
test "module-local Ok and Err functions shadow contextual constructors in generic and ordinary bodies" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = ConstructorModules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 42), (try language.vm.run(t.allocator, compilation.code.?)).value);
}

// spec: BUILTIN-CONTEXT-1
test "builtin List and Result resolve without imports or explicit declarations" {
    try run("fn answer()->Result<i64,i64>{return new Result<i64,i64>.ok(42);}" ++
        "fn main()->i64{let values:List<i64>=[];values.push(42);" ++
        "match answer(){Result<i64,i64>.ok(n)=>{return n;},Result<i64,i64>.err(e)=>{return e;}}}");
}

// spec: BUILTIN-CONTEXT-2
test "empty lists and Ok Err inherit binding return and argument contexts" {
    try run("fn empty()->List<i64>{return [];}" ++
        "fn answer()->Result<i64,i64>{return Ok(42);}" ++
        "fn recover(value:Result<i64,i64>)->i64{match value{Result<i64,i64>.ok(n)=>{return n;},Result<i64,i64>.err(e)=>{return e;}}}" ++
        "fn main()->i64{let values:List<i64>=[];values.push(42);" ++
        "let result:Result<i64,i64>=Err(values[0u64]);_ = result;return recover(Ok(42));}");
}

// spec: BUILTIN-CONTEXT-3
test "record fields and nested list elements propagate empty list context" {
    try run("struct Holder{values:List<i64>}fn choose(value:Holder,other:List<i64>)->i64{_ = other;let xs=value.values;xs.push(42);return xs[0u64];}" ++
        "fn main()->i64{let nested:List<List<i64>>=[];let inner:List<i64>=[];nested.push(inner);return choose(Holder{values:[]},[]);}");
}

// spec: BUILTIN-CONTEXT-4
test "Ok unit values preserve fallible result handling" {
    try run("fn done()->Result<unit,i64>{return Ok(());}" ++
        "fn main()->i64{match done(){Result<unit,i64>.ok(_)=>{return 42;},Result<unit,i64>.err(e)=>{return e;}}}");
}

// spec: BUILTIN-CONTEXT-7
test "declared List and Result types retain their own nominal identity" {
    try run("result Result{ok:i64,err:i64}" ++
        "fn answer()->Result{return Ok(42);}fn main()->i64{let values:List<i64>=[];values.push(42);" ++
        "if values[0u64]!=42{return 0;}match answer(){Result.ok(n)=>{return n;},Result.err(e)=>{return e;}}}");
}
