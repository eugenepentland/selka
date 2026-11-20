//! The ordinary functions of one check request grouped by the module that declares them (G2p part 1).
//!
//! A host that holds its answers per module (the lowering receipts, the ownership proofs) is asked once for a whole module instead of once
//! for each of its functions. The group carries what a host's record for the module must be valid for: the module's signature, a digest over
//! the dependency context and region digest of each of its functions in program order (the stable key is part of a context), and the digest
//! of the module's file, which the source proofs of its functions depend on.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const semantic_key = @import("semantic_key.zig");
const Names = @import("module_names.zig").Names;

/// The domain a module signature is taken under.
const signature_domain = "selka-module-signature-v1";

/// The input (module) of `span` in a merged source, trying the module of the previous function first: functions of a module are adjacent.
fn inputOf(src: source.Source, span: source.Span, hint: *usize) ?usize {
    if (src.origins.len == 0) return 0;
    if (hint.* < src.origins.len) {
        const origin = src.origins[hint.*];
        if (span.start >= origin.start and span.end <= origin.start + origin.original.bytes.len) return hint.*;
    }
    const original = src.originalSpan(span) catch return null;
    hint.* = original.input;
    return original.input;
}

/// Group the request's ordinary instances by module, in module order, with the members of each in program order. An instance whose module
/// cannot be told (a function of a source with no origin) is left out of every group.
pub fn group(allocator: std.mem.Allocator, prepared: *const semantic_key.Prepared, syntax: ast.Program, names: *Names) error{OutOfMemory}!semantic_key.Grouping {
    const project = names.index.project;
    project.ensureSourceDigests();
    const modules = project.modules.items;
    const count = prepared.ordinary_ast.len;
    const input_of = try allocator.alloc(u32, count);
    const sizes = try allocator.alloc(u32, modules.len);
    @memset(sizes, 0);
    var hint: usize = 0;
    for (prepared.ordinary_ast, input_of) |ast_index, *input| {
        const found = inputOf(names.src, syntax.functions[ast_index].name, &hint) orelse modules.len;
        input.* = @intCast(found);
        if (found < modules.len) sizes[found] += 1;
    }
    var groups: usize = 0;
    for (sizes) |size| groups += @intFromBool(size != 0);
    const out = try allocator.alloc(semantic_key.ModuleGroup, groups);
    const group_of = try allocator.alloc(u32, modules.len);
    const flat = try allocator.alloc(u32, count);
    var next: usize = 0;
    var at: usize = 0;
    for (sizes, 0..) |size, input| {
        if (size == 0) continue;
        group_of[input] = @intCast(next);
        out[next] = .{
            .module = modules[input].name,
            .path = modules[input].src.keyPath(),
            .file = modules[input].digest,
            .signature = undefined,
            .members = flat[at .. at + size],
        };
        at += size;
        next += 1;
    }
    const module_of = try allocator.alloc(u32, count);
    const ordinal_of = try allocator.alloc(u32, count);
    const filled = try allocator.alloc(u32, groups);
    @memset(filled, 0);
    for (input_of, 0..) |input, instance| {
        if (input >= modules.len) {
            module_of[instance] = semantic_key.no_group;
            ordinal_of[instance] = 0;
            continue;
        }
        const position = group_of[input];
        const members = @constCast(out[position].members);
        members[filled[position]] = @intCast(instance);
        module_of[instance] = position;
        ordinal_of[instance] = filled[position];
        filled[position] += 1;
    }
    for (out) |*each| each.signature = signatureOf(prepared, each.module, each.members);
    return .{ .modules = out, .module_of = module_of, .ordinal_of = ordinal_of };
}

/// The signature of a module: its name and, for each member in order, the dependency context and the region digest of the function.
pub fn signatureOf(prepared: *const semantic_key.Prepared, module: []const u8, members: []const u32) [32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update(signature_domain);
    var size: [8]u8 = undefined;
    std.mem.writeInt(u64, &size, module.len, .little);
    hash.update(&size);
    hash.update(module);
    std.mem.writeInt(u64, &size, members.len, .little);
    hash.update(&size);
    for (members) |instance| {
        const ast_index = prepared.ordinary_ast[instance];
        hash.update(&prepared.contexts[ast_index]);
        hash.update(&prepared.recalled.digests[ast_index]);
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

test "G2p a module's signature moves with a function's context or region and with the member count, and with nothing else" {
    var keys = [_][]const u8{ "a", "b" };
    var contexts = [_][32]u8{ @splat(1), @splat(2) };
    var digests = [_][32]u8{ @splat(3), @splat(4) };
    var ordinary = [_]usize{ 0, 1 };
    const prepared: semantic_key.Prepared = .{ .bodies = &.{}, .regions = &.{}, .keys = &keys, .contexts = &contexts, .ordinary_ast = &ordinary, .recalled = .{ .digests = &digests } };
    const base = signatureOf(&prepared, "m", &.{ 0, 1 });
    try std.testing.expectEqualSlices(u8, &base, &signatureOf(&prepared, "m", &.{ 0, 1 }));
    try std.testing.expect(!std.mem.eql(u8, &base, &signatureOf(&prepared, "m", &.{0})));
    try std.testing.expect(!std.mem.eql(u8, &base, &signatureOf(&prepared, "n", &.{ 0, 1 })));
    try std.testing.expect(!std.mem.eql(u8, &base, &signatureOf(&prepared, "m", &.{ 1, 0 })));
    contexts[1] = @splat(9);
    try std.testing.expect(!std.mem.eql(u8, &base, &signatureOf(&prepared, "m", &.{ 0, 1 })));
    contexts[1] = @splat(2);
    digests[0] = @splat(9);
    try std.testing.expect(!std.mem.eql(u8, &base, &signatureOf(&prepared, "m", &.{ 0, 1 })));
}
