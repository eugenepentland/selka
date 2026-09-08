//! Typed noncapturing callbacks preserve signatures, effects and ordinary ownership transfers.
const std = @import("std");
const print = std.debug.print;
const t = std.testing;
const language = @import("compiler.zig");
fn run(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "callback.my", source);
    defer c.deinit();
    const outcome = c.execute(t.allocator) catch |err| {
        for (c.diagnostics.items) |d| print("{s}: {s} ({s})\n", .{ d.code, d.message, c.src.text(d.span) });
        return err;
    };
    try t.expectEqual(expected, outcome.value);
    const generated = try c.emitC(t.allocator);
    defer t.allocator.free(generated);
}
// spec: CALLBACK-1
test "callbacks infer function values and invoke passed exact signatures" {
    try run("fn inc(x:i64)->i64 effects(){return x+1;}fn main()->i64{let f=inc;return f(4);}", 5);
    try run("fn inc(x:i64)->i64 effects(){return x+1;}fn apply(f:fn(i64)->i64 effects(),x:i64)->i64{return f(x);}" ++
        "fn main()->i64{return apply(inc,8);}", 9);
}

test "callbacks retain values through records arrays and ordinary generic forwarding" {
    try run("type F=fn(i64)->i64 effects();struct Box<T:copy>{value:T}" ++
        "fn inc(x:i64)->i64 effects(){return x+1;}fn get<T:copy>(b:Box<T>)->T{return b.value;}" ++
        "fn repeat<T:copy>(f:F,x:i64,tag:T)->i64{discard tag;return f(f(x));}" ++
        "fn main()->i64{let b=new Box<F>{value:inc};let all=new [1]F [get::<F>(b)];let f=all[0];return repeat::<bool>(f,5,true);}", 7);
    try run("fn inc(x:i64)->i64 effects(){return x+1;}fn choose()->fn(i64)->i64 effects() {return inc;}" ++
        "fn main()->i64{let f=choose();return f(8);}", 9);
}

test "callbacks transfer owned arguments and preserve result handling" {
    try run("buffer B:i64;result A{ok:B,err:i64}result S{ok:i64,err:i64}" ++
        "fn consume(b:B)->S effects(){return new S.ok(cast<i64>(capacity_buffer(b)));}" ++
        "fn apply(f:fn(B)->S effects(),b:B)->S{return f(b);}" ++
        "fn main(heap:allocator)->i64{match acquire_buffer<A>(heap,3){A.ok(b)=>{match apply(consume,b){S.ok(n)=>{return n;},S.err(e)=>{return e;}}},A.err(e)=>{return e;}}}", 3);
}

fn reject(source: []const u8, code: []const u8) !void {
    const complete = try std.mem.concat(t.allocator, u8, &.{ source, if (std.mem.indexOf(u8, source, "fn main") == null) "fn main()->i64{return 0;}" else "" });
    defer t.allocator.free(complete);
    var c = try language.Compilation.init(t.allocator, "invalid-callback.my", complete);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

test "callbacks reject signature effect ownership and unsupported capture mismatches" {
    try reject("fn f(x:i64)->i64{return x;}fn main()->i64{let cb=f;return cb(1);}", "E_CALLBACK_EFFECTS");
    try reject("fn f(x:i64)->i64 effects(host){return x;}fn use(cb:fn(i64)->i64 effects())->i64{return cb(1);}" ++
        "fn main()->i64{return use(f);}", "E_TYPE");
    try reject("fn f(x:bool)->i64 effects(){return 1;}fn use(cb:fn(i64)->i64 effects())->i64{return cb(1);}" ++
        "fn main()->i64{return use(f);}", "E_TYPE");
    try reject("fn use(cb:fn(i64)->i64 effects(host))->i64 effects(){return cb(1);}", "E_EFFECT_BOUND");
    try reject("fn f<T:copy>(x:T)->T effects(){return x;}fn main()->i64{let cb=f;return 0;}", "E_CALLBACK_TYPE");
    try run("fn inc(x:i64)->i64 effects(){return x+1;}fn f<T:copy>(cb:fn(T)->T effects(),x:T)->T{return cb(x);}fn main()->i64{return f::<i64>(inc,5);}", 6);
    try reject("result R{ok:i64,err:i64}fn use(cb:fn()->R effects())->i64{let value=cb();return 0;}", "E_RESULT_UNHANDLED");
    try reject("buffer B:i64;fn use(cb:fn(B)->i64 effects(),b:B)->i64{discard cb(b);discard cb(b);return 0;}", "E_OWNED_CONSUMED");
    try reject("fn f()->i64 effects(){return 1;}fn main()->i64{let a=f;let b=f;if a==b{return 1;}return 0;}", "E_TYPE");
}

const allocation_source = "struct Box{value:[2]i64}fn make(ctx:&i64,n:i64)->Box effects(){return new Box{value:new [2]i64 [n+read_ref(ctx),n+1]};}" ++
    "fn apply<T:copy>(f:fn(&T,i64)->Box effects(),ctx:&T,n:i64)->Box{return f(ctx,n);}" ++
    "fn main()->i64{let context=0;borrow context as ctx{let a=apply::<i64>(make,ctx,7);let f=make;let b=f(ctx,9);return a.value[0]+b.value[1];}}";

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "allocation-callback.my", allocation_source);
    defer c.deinit();
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var copy = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer copy.deinit();
    try t.expectEqual(@as(i64, 17), (try copy.execute(allocator)).value);
    const generated = try copy.emitC(allocator);
    defer allocator.free(generated);
}

test "callbacks compile format execute and emit under every failed allocation" {
    try allocationScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocationScenario, .{});
}

const module_source = "module main;import std_collections as c;" ++
    "fn descending(a:i64,b:i64)->bool effects(){return a>b;}fn twice(x:i64)->i64 effects(){return x*2;}" ++
    "fn main()->i64{let mut a=new [4]i64 [3,1,4,2];borrow mut a[0..4] as view{" ++
    "discard c::sort_by_i64(view,descending);discard c::transform_i64(view,twice);}return a[0]*10+a[3];}";
fn moduleRead(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    if (module_source.len > limit) return error.TooLarge;
    return allocator.dupe(u8, module_source);
}

test "callbacks drive standard library sorting and visitors across module boundaries" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = moduleRead });
    defer program.deinit();
    try t.expectEqual(@as(i64, 82), (try language.vm.run(t.allocator, program.compilation.code.?)).value);
    const generated = try program.compilation.emitC(t.allocator);
    defer t.allocator.free(generated);
}

test "callbacks reject forged target signatures and invalid dynamic calls" {
    const source = "fn f(x:i64)->i64 effects(){return x;}fn g(x:bool)->i64 effects(){return 0;}" ++
        "fn main()->i64{let cb=f;return cb(1);}";
    var c = try language.Compilation.init(t.allocator, "forged-callback.my", source);
    defer c.deinit();
    try c.emit();
    const original = c.code.?;
    const functions = try t.allocator.dupe(language.bytecode.Function, original.functions);
    defer t.allocator.free(functions);
    const main_index = @backingInt(original.main);
    const instructions = try t.allocator.dupe(language.bytecode.Instruction, functions[main_index].scope.instructions);
    defer t.allocator.free(instructions);
    functions[main_index].scope.instructions = instructions;
    var program = original;
    program.functions = functions;
    const instruction = try functionInstruction(instructions);
    const saved = instruction.*;
    instruction.op.function_value.function = @fromBackingInt(1);
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
    instruction.* = saved;
    instruction.op.function_value.function = @fromBackingInt(functions.len);
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
    instruction.* = saved;
}

fn functionInstruction(instructions: []language.bytecode.Instruction) !*language.bytecode.Instruction {
    for (instructions) |*instruction| if (instruction.op == .function_value) return instruction;
    try t.expect(false);
    unreachable;
}

test "callbacks preserve early result propagation and recursive frame limits" {
    try run("buffer B:i64;result A{ok:B,err:i64}result W{ok:i64,err:i64}" ++
        "fn consume(b:B,n:i64)->i64 effects(){discard b;return n;}" ++
        "fn work(heap:allocator)->W{let b=try acquire_buffer<A>(heap,1);let cb=consume;return new W.ok(cb(b,try new W.err(7)));}" ++
        "fn main(heap:allocator)->i64{match work(heap){W.ok(n)=>{return n;},W.err(e)=>{return e;}}}", 7);
    var c = try language.Compilation.init(t.allocator, "recursive-callback.my", "fn main()->i64 effects(){let recurse=main;return recurse();}");
    defer c.deinit();
    const outcome = try c.executeWithOptions(t.allocator, .{ .max_frames = 8 });
    try t.expectEqualStrings("R_FRAME_LIMIT", outcome.trap.code);
}

test "callbacks reject malformed invoke metadata and dynamically mismatched signatures" {
    const source = "fn f(x:i64)->i64 effects(){return x;}fn g(x:bool)->i64 effects(){return 0;}" ++
        "fn main()->i64{let unused=g;discard unused;let cb=f;return cb(1);}";
    var c = try language.Compilation.init(t.allocator, "malformed-invoke.my", source);
    defer c.deinit();
    try c.emit();
    var program = c.code.?;
    const functions = try t.allocator.dupe(language.bytecode.Function, program.functions);
    defer t.allocator.free(functions);
    const main_index = @backingInt(program.main);
    const instructions = try t.allocator.dupe(language.bytecode.Instruction, functions[main_index].scope.instructions);
    defer t.allocator.free(instructions);
    functions[main_index].scope.instructions = instructions;
    program.functions = functions;
    const other_signature = (try functionInstruction(instructions)).op.function_value.ty;
    for (instructions) |*instruction| {
        if (instruction.op != .invoke) continue;
        const saved = instruction.*;
        instruction.op.invoke.ty = .i64;
        try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
        instruction.op.invoke.ty = other_signature;
        // Stack-height validation cannot prove a dynamically selected callback's type.
        try language.bytecode.validate(t.allocator, program);
        try t.expectError(error.InternalError, language.vm.run(t.allocator, program));
        instruction.* = saved;
        const outcome = try language.vm.run(t.allocator, program);
        try t.expectEqual(@as(i64, 1), outcome.value);
        return;
    }
    try t.expect(false);
}

// spec: CALLBACK-CONTEXT-1
test "readonly callback contexts borrow records and slices synchronously without allocation" {
    try run("struct Context{offset:i64}" ++
        "fn add(ctx:&Context,x:i64)->i64 effects(){return read_ref(ctx).offset+x;}" ++
        "fn apply<C:storable,T:copy>(ctx:&C,cb:fn(&C,T)->T effects(),x:T)->T noalloc{return cb(ctx,x);}" ++
        "fn main()->i64{let context=new Context{offset:7};borrow context as ctx{return apply::<Context,i64>(ctx,add,5);}}", 12);
    try run("fn at(ctx:&[]i64,index:i64)->i64 effects(){return read_slice(ctx,cast<u64>(index));}" ++
        "fn apply<C:copy,T:copy>(ctx:&[]C,cb:fn(&[]C,T)->C effects(),x:T)->C noalloc{return cb(ctx,x);}" ++
        "fn main()->i64{let context=new [2]i64 [9,13];borrow context[0..2] as ctx{return apply::<i64,i64>(ctx,at,1);}}", 13);
}

test "callback contexts reject escapes writes wrong kinds aliases and effect widening" {
    try reject("fn escape(ctx:&i64)->i64 effects(){return ctx;}", "E_REFERENCE_VALUE");
    try reject("struct Box{ctx:i64}fn escape(ctx:&i64)->Box effects(){return new Box{ctx:ctx};}", "E_REFERENCE_VALUE");
    try reject("fn use(cb:fn(&mut i64)->i64 effects())->i64{return 0;}", "E_CALLBACK_TYPE");
    try reject("fn read(ctx:&i64)->i64 effects(){return read_ref(ctx);}fn main()->i64{let cb=read;let x=3;return cb(x);}", "E_REFERENCE_SCOPE");
    try reject("fn read(ctx:&i64)->i64 effects(){return read_ref(ctx);}fn main()->i64{let cb=read;let x=new [1]i64 [3];borrow x[0..1] as ctx{return cb(ctx);}}", "E_REFERENCE_KIND");
    try reject("fn use(ctx:&i64,cb:fn(&i64)->i64 effects(allocation))->i64 noalloc{return cb(ctx);}", "E_EFFECT_BOUND");
}

const ContextFixture = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const source = @embedFile("stdlib/fixtures/callback_context.my");
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        if (source.len > limit) return error.TooLarge;
        return allocator.dupe(u8, source);
    }
};
// spec: CALLBACK-ALGORITHMS-1
test "generic collection callbacks sort search and filter borrowed JSON document IDs with explicit ties" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = ContextFixture.read });
    defer program.deinit();
    const outcome = try language.vm.run(t.allocator, program.compilation.code.?);
    try t.expectEqual(@as(i64, 42), outcome.value);
    const generated = try program.compilation.emitC(t.allocator);
    defer t.allocator.free(generated);
}

test "callback context loans preserve alias and region limits in concrete and generic bodies" {
    try reject("fn pair(a:&i64,b:&i64)->i64 effects(){return read_ref(a)+read_ref(b);}" ++
        "fn main()->i64{let cb=pair;let mut x=1;borrow mut x as ctx{return cb(ctx,ctx);}}", "E_BORROW_CONFLICT");
    try reject("fn pair<T:copy>(ctx:&mut T,cb:fn(&T,&T)->T effects())->T{return cb(ctx,ctx);}", "E_BORROW_CONFLICT");
    try reject("fn read(ctx:&allocator)->allocator effects(){return read_ref(ctx);}" ++
        "fn leak(heap:allocator)->allocator{let cb=read;arena heap as scratch{borrow scratch as ctx{return cb(ctx);}}}", "E_ARENA_ESCAPE");
    try reject("fn leak<T:copy>(heap:allocator,cb:fn(&allocator)->allocator effects())->allocator{" ++
        "arena heap as scratch{borrow scratch as ctx{return cb(ctx);}}}", "E_ARENA_ESCAPE");
    try reject("fn write(ctx:&i64)->i64 effects(){write_ref(ctx,3);return 0;}", "E_REFERENCE_READ_ONLY");
    try reject("fn target(ctx:&i64)->&i64 from ctx effects(){return ctx;}fn main()->i64{let cb=target;return 0;}", "E_CALLBACK_TYPE");
    try reject("fn wrong<T:copy,U:copy>(ctx:&T,cb:fn(&T,U)->T effects(),value:T)->T{return cb(ctx,value);}", "E_GENERIC_TYPE");
    try reject("fn allocate(ctx:&i64)->i64 effects(allocation){return read_ref(ctx);}" ++
        "fn apply(ctx:&i64,cb:fn(&i64)->i64 effects())->i64{return cb(ctx);}" ++
        "fn main()->i64{let x=1;borrow x as ctx{return apply(ctx,allocate);}}", "E_TYPE");
}

test "borrowed callback invoke validates reference count and context metadata" {
    var c = try language.Compilation.init(t.allocator, "callback-metadata.my", "fn read(ctx:&i64)->i64 effects(){return read_ref(ctx);}fn main()->i64{let cb=read;let x=5;borrow x as ctx{return cb(ctx);}}");
    defer c.deinit();
    try c.emit();
    var program = c.code.?;
    const functions = try t.allocator.dupe(language.bytecode.Function, program.functions);
    defer t.allocator.free(functions);
    const index = @backingInt(program.main);
    const instructions = try t.allocator.dupe(language.bytecode.Instruction, functions[index].scope.instructions);
    defer t.allocator.free(instructions);
    functions[index].scope.instructions = instructions;
    program.functions = functions;
    const instruction = try invokeInstruction(instructions);
    const saved = instruction.*;
    instruction.op.invoke.references = &.{};
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
    instruction.op.invoke.references = &.{@fromBackingInt(99999)};
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
    instruction.* = saved;
    try t.expectEqual(@as(i64, 5), (try language.vm.run(t.allocator, program)).value);
}

fn invokeInstruction(instructions: []language.bytecode.Instruction) !*language.bytecode.Instruction {
    for (instructions) |*instruction| if (instruction.op == .invoke) return instruction;
    try t.expect(false);
    unreachable;
}
