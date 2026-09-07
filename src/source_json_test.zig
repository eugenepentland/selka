//! Source programs serialize through owned bytes and must handle every boundary result.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const document_types = "buffer Words:i64;result Parsed{ok:Words,err:i64}";
const prelude = "buffer Bytes:u8;result Encoded{ok:Bytes,err:i64}result Changed{ok:bool,err:i64}";
fn run(allocator: std.mem.Allocator, source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(allocator, "source-json.my", source);
    defer compilation.deinit();
    const outcome = compilation.execute(allocator) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(expected, outcome.value);
}
const roundtrip = prelude ++ "struct Item{count:u64,ready:bool}result Decoded{ok:Item,err:i64}" ++
    "fn work(heap:allocator)->Decoded{let bytes=try json_encode::<Encoded>(heap,new Item{count:18446744073709551615u64,ready:true},4096);return " ++
    "json_decode::<Decoded>(heap,bytes,4096);}" ++
    "fn main(heap:allocator)->i64{match work(heap){Decoded.ok(item)=>{if item.count==18446744073709551615u64 && item.ready{return 17;}return 0;},Decoded.err(e)=>{return e;}}}";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    return run(allocator, roundtrip, 17);
}
// spec: SOURCE-JSON-1
test "source JSON round trips full width integers records and ownership under allocation failures" {
    try allocationScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocationScenario, .{});
}
// spec: SOURCE-JSON-2
test "source JSON rejects mutated wire bytes with checked errors and bounded output" {
    try run(t.allocator, prelude ++ "result Decoded{ok:bool,err:i64}" ++
        "fn work(heap:allocator)->Decoded{let mut bytes=try json_encode::<Encoded>(heap,true,4096);borrow mut bytes[0..len_buffer(bytes)] as " ++
        "view{write_slice(view,0,33u8);}return json_decode::<Decoded>(heap,bytes,4096);}" ++
        "fn main(heap:allocator)->i64{match work(heap){Decoded.ok(discard)=>{return 0;},Decoded.err(e)=>{return e;}}}", 1);
    try run(t.allocator, prelude ++ "fn main(heap:allocator)->i64{match json_encode::<Encoded>(heap,true,1){Encoded.ok(discard)=>{return 0;},Encoded.err(e)=>{return e;}}}", 2);
    try run(t.allocator, prelude ++ "fn main(heap:allocator)->i64{match json_encode::<Encoded>(heap,true,0){Encoded.ok(discard)=>{return 0;},Encoded.err(e)=>{return e;}}}", 4);
}
const domain = "struct Wire{n:i64}result DomainRead{ok:Positive,err:i64}domain Positive:i64{codec Wire{decode:from_wire,encode:to_wire}" ++
    "fn make(n:i64)->Positive{return wrap<Positive>(n);}fn from_wire(w:Wire)->DomainRead{if w.n<=0{return new DomainRead.err(99);}return new DomainRead.ok(wrap<Positive>(w.n));}" ++
    "fn to_wire(p:Positive)->Wire{return new Wire{n:unwrap(p)};}fn value(p:Positive)->i64{return unwrap(p);}}";
fn rejectedDomainScenario(allocator: std.mem.Allocator) !void {
    return run(allocator, prelude ++ domain ++ "result Decoded{ok:Positive,err:i64}fn work(heap:allocator)->Decoded{let bytes=try json_encode::<Encoded>(heap,Positive.make(0),4096);return " ++
        "json_decode::<Decoded>(heap,bytes,4096);}fn main(heap:allocator)->i64{match work(heap){Decoded.ok(discard)=>{return 0;},Decoded.err(e)=>{return e;}}}", 3);
}
// spec: SOURCE-JSON-3
test "source JSON uses declared domain codecs and preserves decoder rejection" {
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), rejectedDomainScenario, .{});
    const common = prelude ++ domain ++ "result Decoded{ok:Positive,err:i64}fn work(heap:allocator,n:i64)->Decoded{let bytes=try json_encode::<Encoded>(heap,Positive.make(n),4096);return " ++
        "json_decode::<Decoded>(heap,bytes,4096);}";
    try run(t.allocator, common ++ "fn main(heap:allocator)->i64{match work(heap,23){Decoded.ok(p)=>{return Positive.value(p);},Decoded.err(e)=>{return e;}}}", 23);
    try run(t.allocator, common ++ "fn main(heap:allocator)->i64{match work(heap,0){Decoded.ok(discard)=>{return 0;},Decoded.err(e)=>{return e;}}}", 3);
}
fn reject(body: []const u8, code: []const u8) !void {
    const source = try std.mem.concat(t.allocator, u8, &.{ prelude, body });
    defer t.allocator.free(source);
    var compilation = try language.Compilation.init(t.allocator, "reject-source-json.my", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
// spec: SOURCE-JSON-4
test "source JSON checks result authority data eligibility effects and consumed byte ownership" {
    try reject("fn main(heap:allocator)->i64{discard json_encode::<Encoded>(heap,true,32);return 0;}", "E_RESULT_DISCARD");
    try reject("fn main(heap:allocator)->i64 noalloc{acknowledge json_encode::<Encoded>(heap,true,32);return 0;}", "E_EFFECT_BOUND");
    try reject("fn main(heap:allocator)->i64{acknowledge json_encode::<Encoded>(true,true,32);return 0;}", "E_TYPE");
    try reject("domain Hidden:i64{}fn main(heap:allocator)->i64{acknowledge json_encode::<Encoded>(heap,heap,32);return 0;}", "E_JSON_CODEC");
    try reject("result Decoded{ok:bool,err:i64}fn main(heap:allocator)->i64{acknowledge json_decode::<Decoded>(heap,true,32);return 0;}", "E_JSON_BYTES");
}
// spec: GENERIC-JSON-1
test "source JSON generic codec promises support domain and ordinary instances without representation guessing" {
    try run(t.allocator, prelude ++ domain ++ "fn encode<T:codec>(heap:allocator,value:T)->Encoded{return json_encode::<Encoded>(heap,value,4096);}" ++
        "fn main(heap:allocator)->i64{match encode::<Positive>(heap,Positive.make(4)){Encoded.ok(bytes)=>{discard bytes;},Encoded.err(e)=>{return e;}}match " ++
        "encode::<bool>(heap,true){Encoded.ok(bytes)=>{return cast<i64>(len_buffer(bytes));},Encoded.err(e)=>{return e;}}}", 54);
    try reject("fn encode<T:copy>(heap:allocator,value:T)->Encoded{return json_encode::<Encoded>(heap,value,4096);}fn main()->i64{return 0;}", "E_JSON_CODEC");
}
// spec: SOURCE-JSON-5
test "source JSON shares VM instruction limits and releases capacity failures" {
    var compilation = try language.Compilation.init(t.allocator, "json-limits.my", roundtrip);
    defer compilation.deinit();
    var stats: @import("memory.zig").Statistics = .{};
    const limited = try compilation.executeWithOptions(t.allocator, .{ .memory = .{ .limits = .{ .max_buffer_capacity = 1 }, .statistics = &stats } });
    try t.expectEqual(@as(i64, 2), limited.value);
    try t.expectEqual(@as(usize, 0), stats.live_allocations);
    try t.expectEqual(stats.created, stats.released);
    const exhausted = try compilation.executeWithOptions(t.allocator, .{ .max_steps = 30 });
    try t.expectEqualStrings("R_STEP_LIMIT", exhausted.trap.code);
}
// spec: SOURCE-JSON-6
test "source JSON rejects type identity version duplicate fields and trailing wire data" {
    const inputs = [_][]const u8{
        "{\"version\":\"typed-json-v0\",\"type\":\"bool\",\"value\":true}",
        "{\"version\":\"typed-json-v1\",\"type\":\"i64\",\"value\":true}",
        "{\"version\":\"typed-json-v1\",\"type\":\"bool\",\"value\":true,\"value\":false}",
        "{\"version\":\"typed-json-v1\",\"type\":\"bool\",\"value\":true}false",
        "{\"version\":\"typed-json-v1\",\"type\":\"bool\",\"value\":true,\"extra\":1}",
    };
    for (inputs) |input| {
        const quoted = try std.json.Stringify.valueAlloc(t.allocator, input, .{});
        defer t.allocator.free(quoted);
        const source = try std.fmt.allocPrint(t.allocator, "{s}result Decoded{{ok:bool,err:i64}}fn work(heap:allocator)->Decoded{{let literal={s};let mut bytes=try acquire_buffer<Encoded>(heap,1024);borrow " ++
            "literal[0..len(literal)] as view{{let mut i=0u64;while i<len_slice(view){{discard try append_buffer<Changed>(bytes,read_slice(view,i));i+=1u64;}}}}" ++
            "return json_decode::<Decoded>(heap,bytes,1024);}}fn main(heap:allocator)->i64{{match work(heap){{Decoded.ok(discard)=>{{return 0;}}" ++
            ",Decoded.err(e)=>{{return e;}}}}}}", .{ prelude, quoted });
        defer t.allocator.free(source);
        try run(t.allocator, source, 1);
    }
    try reject("fn json_encode()->i64{return 9;}fn main()->i64{return 0;}", "E_RESERVED_FUNCTION");
    try reject("result Decoded{ok:bool,err:i64}fn work(heap:allocator)->Decoded{let bytes=try json_encode::<Encoded>(heap,true,1024);let value=try " ++
        "json_decode::<Decoded>(heap,bytes,1024);discard value;return json_decode::<Decoded>(heap,bytes,1024);}fn main()->i64{return 0;}", "E_OWNED_CONSUMED");
}
// spec: SOURCE-JSON-7
test "source JSON CodecFrameLimit counts parent frames when invoking a domain codec" {
    const source = prelude ++ domain ++ "fn work(heap:allocator,p:Positive)->Encoded{return json_encode::<Encoded>(heap,p,4096);}fn main(heap:allocator)->i64{let p=Positive.make(7);match " ++
        "work(heap,p){Encoded.ok(bytes)=>{discard bytes;return 7;},Encoded.err(e)=>{return e;}}}";
    var compilation = try language.Compilation.init(t.allocator, "json-frames.my", source);
    defer compilation.deinit();
    const exhausted = try compilation.executeWithOptions(t.allocator, .{ .max_frames = 2 });
    try t.expectEqualStrings("R_FRAME_LIMIT", exhausted.trap.code);
    const fits = try compilation.executeWithOptions(t.allocator, .{ .max_frames = 3 });
    try t.expectEqual(@as(i64, 7), fits.value);
}
// spec: SOURCE-JSON-8
test "source JSON bytecode rejects forged operation types and codec function identities" {
    const source = prelude ++ domain ++ "fn main(heap:allocator)->i64{match json_encode::<Encoded>(heap,Positive.make(7),4096){Encoded.ok(bytes)=>{discard bytes;return 7;},Encoded.err(e)=>{return e;}}}";
    var compilation = try language.Compilation.init(t.allocator, "json-bytecode.my", source);
    defer compilation.deinit();
    try compilation.emit();
    const program = compilation.code.?;
    try rejectInstructionTypes(program);
    try rejectCodecIdentity(program);
}
fn rejectInstructionTypes(program: language.bytecode.Program) !void {
    var changed = false;
    for (program.functions) |function| for (@constCast(function.scope.instructions)) |*instruction| {
        if (instruction.op != .json_codec) continue;
        const original = instruction.*;
        defer instruction.* = original;
        instruction.op.json_codec.input = .allocator;
        try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
        changed = true;
    };
    try t.expect(changed);
}
fn rejectCodecIdentity(program: language.bytecode.Program) !void {
    for (@constCast(program.records)) |*record| if (record.contract.codec != null) {
        const original = record.contract.codec.?;
        defer record.contract.codec = original;
        record.contract.codec.?.decode = @fromBackingInt(program.functions.len);
        try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
    };
}

// spec: PLAIN-JSON-4
test "source JSON parseDocument handles output capacity failure and releases consumed input" {
    const source = prelude ++ document_types ++
        "fn work(heap:allocator)->Parsed{let mut bytes=try acquire_buffer<Encoded>(heap,1);discard try append_buffer<Changed>(bytes,48u8);return json_parse::<Parsed>(heap,bytes,1);}" ++
        "fn main(heap:allocator)->i64{match work(heap){Parsed.ok(words)=>{return cast<i64>(len_buffer(words));},Parsed.err(e)=>{return e;}}}";
    try run(t.allocator, source, 12);
    var compilation = try language.Compilation.init(t.allocator, "plain-capacity.my", source);
    defer compilation.deinit();
    var stats: @import("memory.zig").Statistics = .{};
    const result = try compilation.executeWithOptions(t.allocator, .{ .memory = .{ .limits = .{ .max_buffer_capacity = 1 }, .statistics = &stats } });
    try t.expectEqual(@as(i64, 2), result.value);
    try t.expectEqual(@as(usize, 0), stats.live_allocations);
    try t.expectEqual(stats.created, stats.released);
}

// spec: PLAIN-JSON-5
test "plain JSON document enforces checked types effects byte ownership and forged modes" {
    try reject("result Wrong{ok:bool,err:i64}fn invalid(heap:allocator,bytes:Bytes)->Wrong{return json_parse::<Wrong>(heap,bytes,1);}fn main()->i64{return 0;}", "E_JSON_DOCUMENT");
    try reject(document_types ++ "fn invalid(heap:allocator,bytes:Bytes)->Parsed noalloc{return json_parse::<Parsed>(heap,bytes,1);}fn main()->i64{return 0;}", "E_EFFECT_BOUND");
    try reject(document_types ++ "fn invalid(heap:allocator,bytes:Bytes)->Parsed{acknowledge json_parse::<Parsed>(heap,bytes,1);return json_parse::<Parsed>(heap,bytes,1);}fn main()->i64{return 0;}", "E_OWNED_CONSUMED");
    const source = prelude ++ document_types ++
        "fn work<T:copy>(heap:allocator,unused:T)->Parsed{discard unused;let mut bytes=try acquire_buffer<Encoded>(heap,1);" ++
        "discard try append_buffer<Changed>(bytes,48u8);return json_parse::<Parsed>(heap,bytes,1);}" ++
        "fn main(heap:allocator)->i64{match work::<bool>(heap,true){Parsed.ok(words)=>{return cast<i64>(len_buffer(words));},Parsed.err(e)=>{return e;}}}";
    try run(t.allocator, source, 12);
    var compilation = try language.Compilation.init(t.allocator, "plain-mode.my", source);
    defer compilation.deinit();
    try compilation.emit();
    try rejectDocumentMode(compilation.code.?);
}
fn rejectDocumentMode(program: language.bytecode.Program) !void {
    var changed = false;
    for (program.functions) |function| for (@constCast(function.scope.instructions)) |*instruction| {
        if (instruction.op != .json_codec) continue;
        const original = instruction.*;
        defer instruction.* = original;
        instruction.op.json_codec.decode = false;
        try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
        changed = true;
    };
    try t.expect(changed);
}
