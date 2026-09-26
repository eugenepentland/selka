//! `mylang invoke` acceptance: target selection and eligibility, request
//! validation, the `native-invocation-v1` envelope, and the result/trap/timeout
//! distinction.
//!
//! Every test here is straight-line: schema fixtures are parsed once by a
//! helper and the loops that walk them live in helpers, not in test bodies.
const std = @import("std");
const testing = std.testing;
const fs = @import("qbe_build_io.zig");
const options = @import("native_test_options.zig");
const sessions = @import("native_test_session.zig");
const wire = @import("native_test_wire.zig");
const invoke = @import("invoke.zig");
const command = @import("invoke_command.zig");
const schema_json = @import("invoke_wire_schema.zig");
const runner = @import("invoke_execute.zig");
const Value = std.json.Value;

/// A checked-schema fixture shaped exactly like `language-schema-v1`: two
/// scalar arguments, a nested record result, a record argument, an unsupported
/// nested buffer, a capability argument and a domain-codec result.
const fixture =
    \\{"functions":[
    \\{"name":"tool::scale","parameters":[{"name":"value","type":"i64","mode":"value"},{"name":"factor","type":"i64","mode":"value"}],"result":"i64","effects":[],"mutates":[],"return_origin":"unknown"},
    \\{"name":"tool::sample_label","parameters":[{"name":"sample","type":"tool::Sample","mode":"value"}],"result":"i64","effects":[],"mutates":[],"return_origin":"unknown"},
    \\{"name":"tool::note_weight","parameters":[{"name":"note","type":"tool::Note","mode":"value"}],"result":"i64","effects":[],"mutates":[],"return_origin":"unknown"},
    \\{"name":"tool::probe_filesystem","parameters":[{"name":"fs","type":"filesystem_cap","mode":"value"}],"result":"i64","effects":["filesystem"],"mutates":[],"return_origin":"unknown"},
    \\{"name":"tool::announce","parameters":[{"name":"out","type":"stream_cap","mode":"value"},{"name":"value","type":"i64","mode":"value"}],"result":"i64","effects":["output"],"mutates":[],"return_origin":"unknown"},
    \\{"name":"tool::grow","parameters":[{"name":"seed","type":"i64","mode":"value"}],"result":"tool::Sample","effects":["managed_allocation"],"mutates":[],"return_origin":"unknown"}],
    \\"types":[
    \\{"name":"i64","kind":"integer","move_only":false,"opaque":false,"bits":64,"signed":true,"minimum":"-9223372036854775808","maximum":"9223372036854775807"},
    \\{"name":"bool","kind":"boolean","move_only":false,"opaque":false},
    \\{"name":"stream_cap","kind":"capability","move_only":false,"opaque":true},
    \\{"name":"filesystem_cap","kind":"capability","move_only":false,"opaque":true},
    \\{"name":"tool::Span","kind":"record","move_only":false,"opaque":false,"fields":[{"name":"low","type":"i64"},{"name":"high","type":"i64"}]},
    \\{"name":"tool::Sample","kind":"record","move_only":false,"opaque":false,"fields":[{"name":"label","type":"i64"},{"name":"span","type":"tool::Span"},{"name":"weights","type":"[3]i64"}]},
    \\{"name":"[3]i64","kind":"array","move_only":false,"opaque":false,"element":"i64","length":3},
    \\{"name":"tool::Note","kind":"record","move_only":false,"opaque":false,"fields":[{"name":"title","type":"bytes"},{"name":"weight","type":"i64"}]},
    \\{"name":"bytes","kind":"buffer","move_only":false,"opaque":true,"element":"u8"},
    \\{"name":"str","kind":"buffer","move_only":false,"opaque":true,"element":"u8"},
    \\{"name":"tool::Ratio","kind":"result","move_only":false,"requires_handling":true,"opaque":false,"cases":[{"name":"ok","payload":"i64"},{"name":"err","payload":"i64"}]},
    \\{"name":"tool::MetresWire","kind":"record","move_only":false,"opaque":false,"fields":[{"name":"count","type":"i64"}]},
    \\{"name":"tool::Metres","kind":"domain","move_only":false,"opaque":true,"codec":{"wire":"tool::MetresWire","decode":"tool::Metres::from_wire","encode":"tool::Metres::to_wire","error_type":"i64"}}]}
;

/// One parsed fixture schema owned by the caller's arena.
fn fixtureSchema(allocator: std.mem.Allocator) !Value {
    const parsed = try std.json.parseFromSlice(Value, allocator, fixture, .{ .allocate = .alloc_always });
    return parsed.value;
}

/// One named function out of the fixture schema.
fn fixtureFunction(schema: Value, name: []const u8) Value {
    return invoke.select(schema, name).?;
}

/// The wire pattern one integer property carries in a generated schema.
fn propertyPattern(schema: Value, name: []const u8) []const u8 {
    const properties = schema.object.get("properties").?;
    return properties.object.get(name).?.object.get("pattern").?.string;
}

// spec: INVOKE-4
test "the envelope version and the three documented exit statuses do not change" {
    try testing.expectEqualStrings("native-invocation-v1", invoke.envelope_version);
    try testing.expect(std.mem.indexOf(u8, command.usage, "usage: mylang invoke") != null);
    try testing.expectEqual(@as(u8, 0), invoke.exit_completed);
    try testing.expectEqual(@as(u8, 1), invoke.exit_source_or_runtime);
    try testing.expectEqual(@as(u8, 2), invoke.exit_request_or_setup);
}

// spec-case: INVOKE-4
test "every response status keeps its documented exit status and spelling" {
    try testing.expectEqualStrings("described", invoke.statusText(.described));
    try testing.expectEqualStrings("completed", invoke.statusText(.completed));
    try testing.expectEqualStrings("trap", invoke.statusText(.trap));
    try testing.expectEqualStrings("timeout", invoke.statusText(.timeout));
    try testing.expectEqualStrings("source-error", invoke.statusText(.@"source-error"));
    try testing.expectEqualStrings("invalid-request", invoke.statusText(.@"invalid-request"));
    try testing.expectEqualStrings("unsupported", invoke.statusText(.unsupported));
    try testing.expectEqualStrings("setup-failure", invoke.statusText(.@"setup-failure"));
    try testing.expectEqual(@as(u8, 0), invoke.exitStatusText("described"));
    try testing.expectEqual(@as(u8, 0), invoke.exitStatusText("completed"));
    try testing.expectEqual(@as(u8, 1), invoke.exitStatusText("trap"));
    try testing.expectEqual(@as(u8, 1), invoke.exitStatusText("timeout"));
    try testing.expectEqual(@as(u8, 1), invoke.exitStatusText("source-error"));
    try testing.expectEqual(@as(u8, 2), invoke.exitStatusText("invalid-request"));
    try testing.expectEqual(@as(u8, 2), invoke.exitStatusText("unsupported"));
    try testing.expectEqual(@as(u8, 2), invoke.exitStatusText("setup-failure"));
    try testing.expectEqual(@as(u8, 2), invoke.exitStatusText("not-a-status"));
    try testing.expect(invoke.completed(.described));
    try testing.expect(invoke.completed(.completed));
    try testing.expect(!invoke.completed(.trap));
}

// spec: INVOKE-5
test "a returned language error is a typed completed result, not a trap" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const failure = (try std.json.parseFromSlice(Value, a,
        \\{"case":"err","value":"-1"}
    , .{ .allocate = .alloc_always })).value;
    const success = (try std.json.parseFromSlice(Value, a,
        \\{"case":"ok","value":"7"}
    , .{ .allocate = .alloc_always })).value;
    try testing.expect(invoke.returnedError(failure));
    try testing.expect(!invoke.returnedError(success));
    try testing.expect(!invoke.returnedError(.{ .string = "7" }));
}

// spec-case: INVOKE-5
test "a trap response keeps its code, operation and source-mapped frames" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const detail = try invoke.trapDetail(a, "R_DIVISION_BY_ZERO (floor_div: left 7, right 0)\n  in tool::integer_divide at tool.my:39:22\n");
    try testing.expectEqualStrings("R_DIVISION_BY_ZERO", detail.code);
    try testing.expectEqualStrings("floor_div", detail.operation);
    try testing.expectEqual(@as(usize, 1), detail.frames.len);
    try testing.expectEqualStrings("tool::integer_divide", detail.frames[0].function);
    try testing.expectEqualStrings("tool.my", detail.frames[0].path);
    try testing.expectEqual(@as(u64, 39), detail.frames[0].line);
    try testing.expectEqual(@as(u64, 22), detail.frames[0].column);
    const unrelated = try invoke.trapDetail(a, "NativeTestProcessFailed: .{ .signal = .SEGV }\n");
    try testing.expectEqualStrings("", unrelated.code);
    try testing.expectEqual(@as(usize, 0), unrelated.frames.len);
}

// spec: INVOKE-3
test "a repeated argument key is found in the raw request text at any depth" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("value", (try invoke.duplicateKey(a,
        \\{"value": "1", "factor": "2", "value": "3"}
    )).?);
    try testing.expectEqualStrings("outer", (try invoke.duplicateKey(a,
        \\{"outer": {"value": "1"}, "outer": {"value": "2"}}
    )).?);
    try testing.expect((try invoke.duplicateKey(a,
        \\{"outer": {"value": "1"}, "value": "2"}
    )) == null);
    try testing.expect((try invoke.duplicateKey(a,
        \\{"message": "a, \"value\": b", "value": "2"}
    )) == null);
    try testing.expect((try invoke.duplicateKey(a, "[]")) == null);
}

// spec: INVOKE-1
test "a target is selected by its exact qualified name only" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const schema = try fixtureSchema(arena.allocator());
    try testing.expect(invoke.select(schema, "tool::scale") != null);
    try testing.expect(invoke.select(schema, "tool::hidden") == null);
    try testing.expect(invoke.select(schema, "scale") == null);
    try testing.expectEqualStrings("tool::scale", invoke.select(schema, "tool::scale").?.object.get("name").?.string);
}

// spec: INVOKE-2
test "an eligible scalar export reports its contract and needs no authority" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    const verdict = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::scale"));
    try testing.expect(verdict.eligible);
    try testing.expect(verdict.wire_supported);
    try testing.expect(verdict.refusal == null);
    try testing.expectEqual(@as(usize, 0), verdict.capabilities.len);
    try testing.expectEqual(@as(usize, 0), verdict.effects.len);
    try testing.expectEqualStrings("integer", invoke.wireKind(invoke.types(schema), "i64"));
    try testing.expectEqualStrings("record", invoke.wireKind(invoke.types(schema), "tool::Sample"));
    try testing.expectEqualStrings("injected-stream", invoke.wireKind(invoke.types(schema), "stream_cap"));
}

// spec-case: INVOKE-9
test "a record argument is executable and an unsupported nested field still names its path" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    // A record argument now executes: the copied-value adapter reads the
    // emitter's own crossing from the manifest and passes the argument buffer,
    // so the wire subset and the executable subset agree on it.
    const aggregate = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::sample_label"));
    try testing.expect(aggregate.eligible);
    try testing.expect(aggregate.wire_supported);
    try testing.expect(aggregate.refusal == null);
    // `str` is carried now, so the unsupported nested field is a byte string:
    // the text rule is the checked name `str`, not the buffer shape, and a
    // `bytes` field keeps its refusal and its path.
    const nested = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::note_weight"));
    try testing.expect(!nested.eligible);
    try testing.expect(!nested.wire_supported);
    try testing.expectEqualStrings("unsupported-type", nested.refusal.?.kind);
    try testing.expectEqualStrings("argument 'note' -> field 'title'", nested.refusal.?.path);
    const capability = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::probe_filesystem"));
    try testing.expect(!capability.eligible);
    try testing.expectEqualStrings("authority", capability.refusal.?.kind);
    try testing.expectEqual(@as(usize, 1), capability.capabilities.len);
    try testing.expectEqualStrings("filesystem_cap", capability.capabilities[0]);
    try testing.expectEqual(@as(usize, 1), capability.effects.len);
}

// spec-case: INVOKE-2
test "an injected stream is eligible and a nested aggregate result is carried" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    const streamed = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::announce"));
    try testing.expect(streamed.eligible);
    try testing.expect(streamed.wire_supported);
    try testing.expectEqual(@as(usize, 0), streamed.capabilities.len);
    try testing.expectEqual(@as(usize, 1), streamed.effects.len);
    try testing.expectEqualStrings("output", streamed.effects[0]);
    const nested = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::grow"));
    try testing.expect(nested.eligible);
    try testing.expect(nested.wire_supported);
    const described: invoke.Description = .{
        .eligible = false,
        .wire_supported = true,
        .contract = .{ .arguments = &.{}, .result = .{ .type = "i64", .wire = "integer" }, .effects = &.{}, .mutates = &.{}, .return_origin = "unknown" },
        .authority = .{ .capabilities = &.{}, .effects = &.{} },
    };
    try testing.expect(!described.eligible);
    try testing.expect(described.wire_supported);
    try testing.expect(described.unsupported == null);
}

// spec-case: INVOKE-3
test "named arguments are refused as missing, extra or malformed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    const function = fixtureFunction(schema, "tool::scale");
    const missing = (try std.json.parseFromSlice(Value, a,
        \\{"value":"1"}
    , .{ .allocate = .alloc_always })).value;
    try testing.expectEqualStrings("argument 'factor' is missing", (try invoke.nameRefusal(a, function, missing)).?.reason);
    const extra = (try std.json.parseFromSlice(Value, a,
        \\{"value":"1","factor":"2","extra":"3"}
    , .{ .allocate = .alloc_always })).value;
    try testing.expectEqualStrings("argument 'extra' is not a parameter of the selected function", (try invoke.nameRefusal(a, function, extra)).?.reason);
    const malformed = (try std.json.parseFromSlice(Value, a,
        \\{"value":1,"factor":"2"}
    , .{ .allocate = .alloc_always })).value;
    try testing.expect((try invoke.nameRefusal(a, function, malformed)) == null);
    var codec: wire.Codec = .{ .allocator = a, .types = invoke.types(schema) };
    defer codec.deinit();
    const refusal = (try invoke.arguments(&codec, a, function, malformed)).?;
    try testing.expectEqualStrings("invalid-request", refusal.kind);
    try testing.expectEqualStrings("argument 'value'", refusal.path);
    var accepted: wire.Codec = .{ .allocator = a, .types = invoke.types(schema) };
    defer accepted.deinit();
    const valid = (try std.json.parseFromSlice(Value, a,
        \\{"value":"21","factor":"2"}
    , .{ .allocate = .alloc_always })).value;
    try testing.expect((try invoke.arguments(&accepted, a, function, valid)) == null);
    try testing.expectEqual(@as(usize, 2), accepted.nodes.items.len);
    try testing.expectEqual(@as(u64, 21), accepted.nodes.items[0].bits);
}

// spec: INVOKE-6
test "the generated request schema describes decimal-string integers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    const request = try schema_json.request(a, invoke.types(schema), fixtureFunction(schema, "tool::scale"));
    try testing.expectEqualStrings("object", request.object.get("type").?.string);
    try testing.expectEqual(false, request.object.get("additionalProperties").?.bool);
    try testing.expectEqualStrings(schema_json.signed_pattern, propertyPattern(request, "value"));
    try testing.expectEqualStrings(schema_json.signed_pattern, propertyPattern(request, "factor"));
    try testing.expectEqualStrings("i64", request.object.get("properties").?.object.get("value").?.object.get("x-mylang-type").?.string);
    try testing.expect(!request.object.contains("effects"));
    try testing.expect(!request.object.contains("mutates"));
    try testing.expect(std.mem.indexOf(u8, request.object.get("$comment").?.string, "not the language-contract graph") != null);
}

// spec-case: INVOKE-6
test "the generated schema follows the nominal shape of a nested result" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    const sample = try schema_json.typeSchema(a, invoke.types(schema), "tool::Sample", 0);
    const span = sample.object.get("properties").?.object.get("span").?;
    try testing.expectEqualStrings("object", span.object.get("type").?.string);
    try testing.expectEqualStrings("tool::Span", span.object.get("x-mylang-type").?.string);
    const weights = sample.object.get("properties").?.object.get("weights").?;
    try testing.expectEqualStrings("array", weights.object.get("type").?.string);
    try testing.expectEqual(@as(i64, 3), weights.object.get("minItems").?.integer);
    const ratio = try schema_json.typeSchema(a, invoke.types(schema), "tool::Ratio", 0);
    try testing.expectEqual(@as(usize, 2), ratio.object.get("oneOf").?.array.items.len);
    const metres = try schema_json.typeSchema(a, invoke.types(schema), "tool::Metres", 0);
    try testing.expectEqualStrings("tool::Metres", metres.object.get("x-mylang-domain").?.string);
    // Text is a supported wire type now, so its schema is the string form
    // rather than a refusal; a checked name that still has no wire encoding
    // keeps reporting InvalidSchema.
    const text = try schema_json.typeSchema(a, invoke.types(schema), "str", 0);
    try testing.expectEqualStrings("string", text.object.get("type").?.string);
    try testing.expectEqualStrings("str", text.object.get("x-mylang-type").?.string);
    try testing.expectError(error.InvalidSchema, schema_json.typeSchema(a, invoke.types(schema), "no_such_type", 0));
    var codec: wire.Codec = .{ .allocator = a, .types = invoke.types(schema) };
    defer codec.deinit();
    const request = try schema_json.request(a, invoke.types(schema), fixtureFunction(schema, "tool::announce"));
    try testing.expectEqual(@as(usize, 1), request.object.get("required").?.array.items.len);
    try testing.expectEqualStrings("value", request.object.get("required").?.array.items[0].string);
}

// spec: INVOKE-7
test "describe resolves no native toolchain while an executing session does" {
    var environment: std.process.Environ.Map = .init(testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(testing.allocator, testing.io, &environment);
    defer context.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const entry = try std.fs.path.join(context.allocator, &.{ root, "main.my" });
    try context.write(entry, "module main\n\n\ndef main() -> int:\n    return 0\n");
    const opts: options.Options = .{
        .source = entry,
        .cache = try std.fs.path.join(context.allocator, &.{ root, "cache" }),
        .toolchain = .{ .zig = "no-such-zig-tool", .qbe = "no-such-qbe-tool" },
    };
    const frontend = try sessions.Session.initFrontend(context, opts);
    defer context.remove(frontend.temporary);
    try testing.expectEqualStrings("", frontend.tools.zig);
    try testing.expectEqualStrings("", frontend.tools.qbe);
    try testing.expectEqual(@as(usize, 64), frontend.hashes[0].len);
    try testing.expectEqualStrings(entry, frontend.source.entry_path);
    try testing.expectError(error.ToolNotFound, sessions.Session.init(context, opts));
}

// spec: INVOKE-8
test "the invoke command line rejects a malformed request before anything runs" {
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{"main.my"}));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function", "tool::scale" }));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function=tool::scale", "--describe", "--input=r.json" }));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function=tool::scale", "--describe", "--format=xml" }));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function=tool::scale", "--input=r.json", "--timeout=0" }));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function=tool::scale", "--input=r.json", "--max-memory=12x" }));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function=tool::scale", "--input=r.json", "--nonsense" }));
    const accepted: command.Request = try command.parse(&.{ "main.my", "--function=tool::scale", "--input=r.json", "--timeout=30", "--max-steps=100" });
    try testing.expectEqualStrings("tool::scale", accepted.function);
    try testing.expectEqualStrings("r.json", accepted.input.?);
    try testing.expectEqual(@as(?u64, 30), accepted.bounds.timeout_seconds);
    try testing.expectEqual(@as(?u64, 100), accepted.bounds.max_steps);
    const rejection: command.ParseError = error.InvalidInvocationArguments;
    try testing.expectEqualStrings("InvalidInvocationArguments", @errorName(rejection));
}

/// The installed compiler the build names beside `MYLANG_QBE`, plus the project
/// root its three-level install path (`zig-out/bin|focus/qbe`) sits under.
const Tools = struct { compiler: []const u8, root: []const u8, zig: []const u8, qbe: []const u8 };

fn tools(allocator: std.mem.Allocator) !Tools {
    const qbe = std.testing.environ.getPosix("MYLANG_QBE") orelse return error.ToolNotFound;
    const zig = std.testing.environ.getPosix("MYLANG_ZIG") orelse return error.ToolNotFound;
    const bin = std.fs.path.dirname(qbe) orelse return error.ToolNotFound;
    const out = std.fs.path.dirname(bin) orelse return error.ToolNotFound;
    const root = std.fs.path.dirname(out) orelse return error.ToolNotFound;
    return .{
        .compiler = try std.fs.path.join(allocator, &.{ bin, "mylang" }),
        .root = try allocator.dupe(u8, root),
        .zig = try allocator.dupe(u8, zig),
        .qbe = try allocator.dupe(u8, qbe),
    };
}

/// The C ABI one codec call crosses: the generated adapter's wire node, run
/// result, codec result and options. The offsets are pinned against
/// `native_embed.h` by the assertions in the test that calls this entry, so a
/// header change fails there instead of corrupting the call.
const WireNode = extern struct { type: ?[*:0]const u8, bits: u64, children: usize };
const RunFrame = extern struct { function: ?[*:0]const u8, path: ?[*:0]const u8, line: usize, column: usize };
const TrapDetail = extern struct { version: u32, present: u32, index: i64, length: u64, left: i64, right: i64, width: u64, operation: ?[*:0]const u8 };
const RunResult = extern struct {
    status: c_int,
    value: i64,
    steps: u64,
    code: ?[*:0]const u8,
    path: ?[*:0]const u8,
    line: usize,
    column: usize,
    frame_count: usize,
    omitted_frames: usize,
    frames: [16]RunFrame,
    trap_detail: TrapDetail,
};
const WireResult = extern struct { execution: RunResult, node_count: usize };
const CodecResult = extern struct { value: WireResult, domain: ?[*:0]const u8, calls: u64, rejected: c_int };
const RunOptions = extern struct { max_steps: u64, max_frames: u64, providers: ?*anyopaque, stress: u64 };
const CodecOptions = extern struct { run: RunOptions, max_calls: u64 };
/// The generated library's codec entry point, as `native_embed.h` declares it.
const CodecCall = *const fn ([*:0]const u8, [*]const WireNode, usize, ?[*]WireNode, usize, ?*const CodecOptions, *CodecResult) callconv(.c) c_int;

/// One checked invoke fixture built into a fresh native library, with the
/// session that owns the temporary directory holding it.
fn builtLibrary(a: std.mem.Allocator, context: fs.Context, cache: []const u8, resolved: Tools, qualified: []const u8) !runner.Prepared {
    const entry = try std.fs.path.join(a, &.{ resolved.root, "tests", "invoke", "tool.my" });
    // `resolved.compiler` is the installed mylang, named explicitly. Leaving it
    // null would make the session spawn *this* process, and this process is the
    // test binary: handed `native-test-graph` it runs its tests rather than
    // emitting facts, so the session and the suite would call each other
    // forever. A test that drives a native session must say which compiler it
    // means.
    const opts: options.Options = .{
        .source = entry,
        .cache = cache,
        .toolchain = .{ .zig = resolved.zig, .qbe = resolved.qbe, .compiler = resolved.compiler },
        .mode = "Debug",
    };
    var prepared = switch (try runner.check(context, opts, .native)) {
        .ok => |value| value,
        .rejected => return error.SourceRejected,
    };
    try runner.build(&prepared, qualified);
    return prepared;
}

/// Look up the generated codec entry in an already loaded library.
fn codecEntry(loaded: *std.DynLib) !CodecCall {
    return loaded.lookup(CodecCall, "mylang_native_call_codecs_v1") orelse error.MissingCodecEntry;
}

/// The three argument nodes `tool::bracket("ab")` takes: the text node and one
/// node per scalar.
fn bracketArguments() [3]WireNode {
    return .{ .{ .type = "str", .bits = 0, .children = 2 }, .{ .type = "u32", .bits = 'a', .children = 0 }, .{ .type = "u32", .bits = 'b', .children = 0 } };
}

/// Invoke one fixture function against a fresh cache and return the CLI's stdout.
/// `entry` names the fixture under `tests/invoke`, so a shape that would clutter
/// the general tool fixture can live in a library of its own.
fn invocation(allocator: std.mem.Allocator, resolved: Tools, entry: []const u8, name: []const u8, request: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = try std.fs.path.join(a, &.{ resolved.root, "tests", "invoke", entry });
    const input = try std.fs.path.join(a, &.{ resolved.root, "tests", "invoke", "requests", try std.fmt.allocPrint(a, "{s}.json", .{request}) });
    const flag = try std.fmt.allocPrint(a, "--input={s}", .{input});
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const cache = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const result = try std.process.run(a, std.testing.io, .{
        .argv = &.{ resolved.compiler, "invoke", path, "--function", name, flag, "--cache-dir", cache },
        .cwd = .inherit,
    });
    if (fs.exitCode(result.term) != 0) try std.Io.File.stderr().writeStreamingAll(std.testing.io, result.stderr);
    try testing.expectEqual(@as(u8, 0), fs.exitCode(result.term));
    return allocator.dupe(u8, result.stdout);
}

// spec: INVOKE-9
test "a nested record argument executes through the copied-value adapter" {
    const a = testing.allocator;
    const resolved = try tools(a);
    defer a.free(resolved.compiler);
    defer a.free(resolved.root);
    defer a.free(resolved.zig);
    defer a.free(resolved.qbe);
    const stdout = try invocation(a, resolved, "tool.my", "tool::sample_label", "sample");
    defer a.free(stdout);
    try testing.expect(std.mem.indexOf(u8, stdout, "\"status\":\"completed\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout, "\"value\":\"7\"") != null);
    try testing.expect(std.mem.endsWith(u8, resolved.compiler, "mylang"));
}

// spec: INVOKE-TEXT-1
test "a text argument and result round-trip through invoke with an embedded NUL preserved" {
    const a = testing.allocator;
    const resolved = try tools(a);
    defer a.free(resolved.compiler);
    defer a.free(resolved.root);
    defer a.free(resolved.zig);
    defer a.free(resolved.qbe);
    // A two-byte scalar, an astral scalar and a combining sequence arrive as one
    // wire node each and come back as the same text between the brackets.
    const unicode = try invocation(a, resolved, "tool.my", "tool::bracket", "text-unicode");
    defer a.free(unicode);
    try testing.expect(std.mem.indexOf(u8, unicode, "\"status\":\"completed\"") != null);
    try testing.expect(std.mem.indexOf(u8, unicode, "\"value\":\"[a\u{e9}\u{1f600}e\u{301}]\"") != null);
    // A NUL is an ordinary scalar, so it survives as the escaped scalar rather
    // than terminating the text.
    const nul = try invocation(a, resolved, "tool.my", "tool::bracket", "text-nul");
    defer a.free(nul);
    try testing.expect(std.mem.indexOf(u8, nul, "\"value\":\"[a\\u0000b]\"") != null);
    const empty = try invocation(a, resolved, "tool.my", "tool::bracket", "text-empty");
    defer a.free(empty);
    try testing.expect(std.mem.indexOf(u8, empty, "\"value\":\"[]\"") != null);
}

// Drives the list boundary tagged QBE-LIST-1 end to end through the public CLI,
// on both a list argument and a list result.
test "a list round-trips through invoke at every shape the codec carries" {
    const a = testing.allocator;
    const resolved = try tools(a);
    defer a.free(resolved.compiler);
    defer a.free(resolved.root);
    defer a.free(resolved.zig);
    defer a.free(resolved.qbe);
    const entry = "lists.my";
    // A list of scalars in, a scalar out: the request's JSON array becomes one
    // wire node per element and the guest reads a list it owns.
    const total = try invocation(a, resolved, entry, "lists::sum_numbers", "list-numbers");
    defer a.free(total);
    try testing.expect(std.mem.indexOf(u8, total, "\"status\":\"completed\"") != null);
    try testing.expect(std.mem.indexOf(u8, total, "\"value\":\"9\"") != null);
    // An empty list is one node with no children rather than a missing argument.
    const empty = try invocation(a, resolved, entry, "lists::sum_numbers", "list-empty");
    defer a.free(empty);
    try testing.expect(std.mem.indexOf(u8, empty, "\"value\":\"0\"") != null);
    // A list result is built fresh in guest storage and copied out one node per
    // element, so the parent never holds a guest pointer.
    const made = try invocation(a, resolved, entry, "lists::make_numbers", "list-count");
    defer a.free(made);
    try testing.expect(std.mem.indexOf(u8, made, "\"value\":[\"0\",\"1\",\"2\",\"3\"]") != null);
    // A list of text in both positions: each element is itself carried as one
    // node per Unicode scalar.
    const joined = try invocation(a, resolved, entry, "lists::join_text", "list-pieces");
    defer a.free(joined);
    try testing.expect(std.mem.indexOf(u8, joined, "\"value\":\"abc\"") != null);
    const sized = try invocation(a, resolved, entry, "lists::lengths", "list-lengths");
    defer a.free(sized);
    try testing.expect(std.mem.indexOf(u8, sized, "\"value\":[\"1\",\"2\",\"3\"]") != null);
    const bracketed = try invocation(a, resolved, entry, "lists::bracket_all", "list-text");
    defer a.free(bracketed);
    try testing.expect(std.mem.indexOf(u8, bracketed, "\"value\":[\"[hi]\",\"hi\"]") != null);
    // A nested list nests on both sides: `list[list[i64]]` in and out again.
    const rows = try invocation(a, resolved, entry, "lists::row_totals", "list-rows");
    defer a.free(rows);
    try testing.expect(std.mem.indexOf(u8, rows, "\"value\":[\"3\",\"3\"]") != null);
    const scaled = try invocation(a, resolved, entry, "lists::scale_rows", "list-scale-rows");
    defer a.free(scaled);
    try testing.expect(std.mem.indexOf(u8, scaled, "\"value\":[[\"10\",\"20\"],[\"30\"]]") != null);
}

// spec: QBE-TEXT-4
test "an undersized codec result buffer reports OutputTooSmall, not WireLimit" {
    const a = testing.allocator;
    const resolved = try tools(a);
    defer a.free(resolved.compiler);
    defer a.free(resolved.root);
    defer a.free(resolved.zig);
    defer a.free(resolved.qbe);
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    var context = try fs.Context.init(a, testing.io, &environment);
    defer context.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const cache = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    defer a.free(cache);
    const prepared = try builtLibrary(a, context, cache, resolved, "tool::bracket");
    defer context.remove(prepared.session.temporary);
    // `builtLibrary` allocates the entry path and hands it to the session's
    // options, which nothing else releases; production runs on an arena and
    // never notices, while this test allocates from the leak checker.
    defer a.free(prepared.session.options.source);
    // The Zig mirror of the C ABI is only usable while it matches the header.
    try testing.expectEqual(@as(usize, 24), @sizeOf(WireNode));
    try testing.expectEqual(@as(usize, 32), @sizeOf(RunFrame));
    try testing.expectEqual(@as(usize, 56), @sizeOf(TrapDetail));
    try testing.expectEqual(@as(usize, 640), @sizeOf(RunResult));
    try testing.expectEqual(@as(usize, 648), @sizeOf(WireResult));
    try testing.expectEqual(@as(usize, 672), @sizeOf(CodecResult));
    try testing.expectEqual(@as(usize, 40), @sizeOf(CodecOptions));
    try testing.expectEqual(@as(usize, 16), @offsetOf(WireNode, "children"));
    try testing.expectEqual(@as(usize, 24), @offsetOf(RunResult, "code"));
    try testing.expectEqual(@as(usize, 640), @offsetOf(WireResult, "node_count"));
    try testing.expectEqual(@as(usize, 664), @offsetOf(CodecResult, "rejected"));
    var loaded = try std.DynLib.open(prepared.project.executor.?.library);
    defer loaded.close();
    const call = try codecEntry(&loaded);
    const arguments = bracketArguments();
    // "[ab]" is one text node plus four scalar nodes. A four-node buffer cannot
    // hold it, and the contract is the required count plus OutputTooSmall — the
    // staging path must not clamp at the caller's capacity and report WireLimit.
    const sentinel: WireNode = .{ .type = "sentinel", .bits = 0xfeed, .children = 7 };
    var small: [4]WireNode = @splat(sentinel);
    var small_result: CodecResult = undefined;
    const too_small = call("tool::bracket", &arguments, arguments.len, &small, small.len, null, &small_result);
    try testing.expectEqual(@as(c_int, 2), too_small);
    try testing.expectEqualStrings("OutputTooSmall", std.mem.span(small_result.value.execution.code.?));
    try testing.expectEqual(@as(usize, 5), small_result.value.node_count);
    try testing.expectEqualStrings("sentinel", std.mem.span(small[0].type.?));
    try testing.expectEqual(@as(u64, 0xfeed), small[3].bits);
    // The very same call completes when the buffer is large enough, so the
    // refusal above is about capacity and nothing else.
    var roomy: [8]WireNode = @splat(sentinel);
    var roomy_result: CodecResult = undefined;
    const completed = call("tool::bracket", &arguments, arguments.len, &roomy, roomy.len, null, &roomy_result);
    try testing.expectEqual(@as(c_int, 0), completed);
    try testing.expectEqual(@as(usize, 5), roomy_result.value.node_count);
    try testing.expectEqualStrings("str", std.mem.span(roomy[0].type.?));
    try testing.expectEqual(@as(usize, 4), roomy[0].children);
    try testing.expectEqual(@as(u64, ']'), roomy[4].bits);
}

/// A checked schema whose record names itself through a list. `record Node:
/// children: list[Node]` is a legal program, so the schema is a graph and not a
/// tree; walking it without a bound is what INVOKE-10 exists to stop.
const recursive =
    \\{"functions":[
    \\{"name":"cycle::cyclic","parameters":[],"result":"List<cycle::Node>","effects":["managed_allocation"],"mutates":[],"return_origin":"unknown"}],
    \\"types":[
    \\{"name":"List<cycle::Node>","kind":"list","move_only":false,"opaque":true,"element":"cycle::Node"},
    \\{"name":"cycle::Node","kind":"record","move_only":false,"opaque":false,"fields":[{"name":"children","type":"List<cycle::Node>"}]}]}
;

// spec: INVOKE-10
test "a type that names itself through a list is refused rather than walked forever" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try std.json.parseFromSlice(Value, a, recursive, .{ .allocate = .alloc_always });
    const schema = parsed.value;
    const verdict = try invoke.eligibility(a, schema, fixtureFunction(schema, "cycle::cyclic"));
    // The walk terminates because it counts its own depth, and it reports the
    // cycle as an unsupported path instead of exhausting the stack.
    try testing.expect(!verdict.eligible);
    try testing.expect(!verdict.wire_supported);
    try testing.expectEqualStrings("unsupported-type", verdict.refusal.?.kind);
    try testing.expect(std.mem.indexOf(u8, verdict.refusal.?.reason, "nests past 64 levels") != null);
    // The path names the hop that crossed the bound, so the refusal points at a
    // place in the type rather than at the signature as a whole.
    try testing.expect(std.mem.startsWith(u8, verdict.refusal.?.path, "result"));
}

// spec: INVOKE-11
test "an export that calls another function is lowered with its call closure" {
    const a = testing.allocator;
    const resolved = try tools(a);
    defer a.free(resolved.compiler);
    defer a.free(resolved.root);
    defer a.free(resolved.zig);
    defer a.free(resolved.qbe);
    const entry = "calls.my";
    // `twice` needs no closure and is the control: if it ever fails the fixture
    // itself is broken rather than the selection.
    const once = try invocation(a, resolved, entry, "calls::twice", "call-value");
    defer a.free(once);
    try testing.expect(std.mem.indexOf(u8, once, "\"status\":\"completed\"") != null);
    try testing.expect(std.mem.indexOf(u8, once, "\"value\":\"6\"") != null);
    // `quad` calls it twice from one expression, so a one-level closure that
    // happened to include the callee would still not be enough.
    const twice = try invocation(a, resolved, entry, "calls::quad", "call-value");
    defer a.free(twice);
    try testing.expect(std.mem.indexOf(u8, twice, "\"value\":\"12\"") != null);
    // `shifted` reaches `twice` only through `quad`, which is what makes the
    // closure transitive rather than a single step.
    const chained = try invocation(a, resolved, entry, "calls::shifted", "call-value");
    defer a.free(chained);
    try testing.expect(std.mem.indexOf(u8, chained, "\"value\":\"13\"") != null);
    // A helper reached from a comprehension, and one whose result feeds a
    // builtin, are the same rule on a tool-shaped body.
    const labels = try invocation(a, resolved, "composed.my", "composed::labels_of", "buckets-two");
    defer a.free(labels);
    try testing.expect(std.mem.indexOf(u8, labels, "\"value\":[\"x\",\"y\"]") != null);
    const grand = try invocation(a, resolved, "composed.my", "composed::grand_total", "buckets-two");
    defer a.free(grand);
    try testing.expect(std.mem.indexOf(u8, grand, "\"value\":\"6\"") != null);
}

// Drives the composed boundary tagged QBE-LIST-2 end to end through the CLI.
test "a record holding a text or a list composes with Option and Result" {
    const a = testing.allocator;
    const resolved = try tools(a);
    defer a.free(resolved.compiler);
    defer a.free(resolved.root);
    defer a.free(resolved.zig);
    defer a.free(resolved.qbe);
    const entry = "composed.my";
    // A record whose fields are a text and a list crosses with both.
    const total = try invocation(a, resolved, entry, "composed::bucket_total", "bucket-one");
    defer a.free(total);
    try testing.expect(std.mem.indexOf(u8, total, "\"status\":\"completed\"") != null);
    try testing.expect(std.mem.indexOf(u8, total, "\"value\":\"3\"") != null);
    // A list of those records, read back as labels and as totals.
    const labels = try invocation(a, resolved, entry, "composed::bucket_labels", "buckets-two");
    defer a.free(labels);
    try testing.expect(std.mem.indexOf(u8, labels, "\"value\":[\"x\",\"y\"]") != null);
    const totals = try invocation(a, resolved, entry, "composed::totals", "buckets-two");
    defer a.free(totals);
    try testing.expect(std.mem.indexOf(u8, totals, "\"value\":[\"1\",\"5\"]") != null);
    // A result whose arms are a record and a text, in both directions.
    const hit = try invocation(a, resolved, entry, "composed::find", "lookup-hit");
    defer a.free(hit);
    try testing.expect(std.mem.indexOf(u8, hit, "\"value\":{\"case\":\"ok\",\"value\":{\"label\":\"x\",\"values\":[\"1\"]}}") != null);
    const miss = try invocation(a, resolved, entry, "composed::find", "lookup-miss");
    defer a.free(miss);
    try testing.expect(std.mem.indexOf(u8, miss, "\"value\":{\"case\":\"err\",\"value\":\"no bucket named z\"}") != null);
    // An optional scalar: present and absent are different wire shapes, and the
    // absent one carries no value at all rather than a null.
    const some = try invocation(a, resolved, entry, "composed::first_or_none", "option-some");
    defer a.free(some);
    try testing.expect(std.mem.indexOf(u8, some, "\"value\":{\"case\":\"some\",\"value\":\"7\"}") != null);
    const none = try invocation(a, resolved, entry, "composed::first_or_none", "option-none");
    defer a.free(none);
    try testing.expect(std.mem.indexOf(u8, none, "\"value\":{\"case\":\"none\"}") != null);
}

const invariant_boundary_source =
    \\module main
    \\
    \\def ordered(low: int, high: int) -> bool:
    \\    return low <= high
    \\
    \\@invariant(ordered(self.low, self.high), "range order")
    \\public record Span:
    \\    low: int
    \\    high: int
    \\
    \\public record Pair:
    \\    spans: [2]Span
    \\
    \\public def read(pair: Pair) -> int:
    \\    return pair.spans[1].high
    \\
    \\def main() -> int:
    \\    return 0
;

fn invariantLibrary(context: fs.Context, temporary: *testing.TmpDir, resolved: Tools) !runner.Prepared {
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = invariant_boundary_source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.my", context.allocator);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", context.allocator);
    const opts: options.Options = .{
        .source = entry,
        .cache = try std.fs.path.join(context.allocator, &.{ root, "cache" }),
        .toolchain = .{ .zig = resolved.zig, .qbe = resolved.qbe, .compiler = resolved.compiler },
        .mode = "Debug",
    };
    var prepared = switch (try runner.check(context, opts, .native)) {
        .ok => |value| value,
        .rejected => |diagnostics| {
            try std.Io.File.stderr().writeStreamingAll(testing.io, diagnostics);
            return error.SourceRejected;
        },
    };
    try runner.build(&prepared, "main::read");
    return prepared;
}

// spec: CONTRACT-DECODE-1
test "invariant boundary validates nested records through ordinary and codec wire entries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const resolved = try tools(a);
    var environment = try testing.environ.createMap(a);
    defer environment.deinit();
    var context = try fs.Context.init(a, testing.io, &environment);
    defer context.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const prepared = try invariantLibrary(context, &temporary, resolved);
    defer context.remove(prepared.session.temporary);
    var loaded = try std.DynLib.open(prepared.project.executor.?.library);
    defer loaded.close();
    const OrdinaryCall = *const fn ([*:0]const u8, [*]const WireNode, usize, ?[*]WireNode, usize, ?*const RunOptions, *WireResult) callconv(.c) c_int;
    const ordinary = loaded.lookup(OrdinaryCall, "mylang_native_call_values_v1") orelse return error.MissingWireEntry;
    const codec = try codecEntry(&loaded);
    var input = [_]WireNode{
        .{ .type = "main::Pair", .bits = 0, .children = 1 },
        .{ .type = "[2]main::Span", .bits = 0, .children = 2 },
        .{ .type = "main::Span", .bits = 0, .children = 2 },
        .{ .type = "i64", .bits = 0, .children = 0 },
        .{ .type = "i64", .bits = 1, .children = 0 },
        .{ .type = "main::Span", .bits = 0, .children = 2 },
        .{ .type = "i64", .bits = 2, .children = 0 },
        .{ .type = "i64", .bits = 4, .children = 0 },
    };
    const sentinel: WireNode = .{ .type = "sentinel", .bits = 0xfeed, .children = 7 };
    var output = [_]WireNode{sentinel};
    var result: WireResult = undefined;
    var encoded: CodecResult = undefined;
    try testing.expectEqual(@as(c_int, 0), ordinary("main::read", &input, input.len, &output, output.len, null, &result));
    try testing.expectEqual(@as(u64, 4), output[0].bits);
    // Only the second element breaks its clause. It must fail before the
    // target can observe it, and before any output buffer is published.
    input[6].bits = 9;
    output[0] = sentinel;
    try testing.expectEqual(@as(c_int, 1), ordinary("main::read", &input, input.len, &output, output.len, null, &result));
    try testing.expectEqualStrings("R_INVARIANT", std.mem.span(result.execution.code.?));
    try testing.expectEqual(@as(usize, 0), result.node_count);
    try testing.expectEqual(@as(u64, 0xfeed), output[0].bits);
    try testing.expectEqualStrings("@invariant:main::Span", std.mem.span(result.execution.frames[0].function.?));
    const stress: CodecOptions = .{ .run = .{ .max_steps = 0, .max_frames = 0, .providers = null, .stress = 1 }, .max_calls = 0 };
    try testing.expectEqual(@as(c_int, 1), codec("main::read", &input, input.len, &output, output.len, &stress, &encoded));
    try testing.expectEqualStrings("R_INVARIANT", std.mem.span(encoded.value.execution.code.?));
    try testing.expectEqual(@as(u64, 0xfeed), output[0].bits);
    input[6].bits = 2;
    try testing.expectEqual(@as(c_int, 0), codec("main::read", &input, input.len, &output, output.len, &stress, &encoded));
    try testing.expectEqual(@as(u64, 4), output[0].bits);
}
