//! Authenticated frontend configuration, verified before any retained result is consulted.
const std = @import("std");
const reference_mode = @import("config/component_runtime.zig").reference_mode;
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const lex_boundary = @import("lexer_component.zig");
const parse_boundary = @import("parser_component.zig");
const declaration_boundary = @import("declaration_component.zig");
const type_interface_boundary = @import("type_interface_component.zig");
const body_check_boundary = @import("body_check_component.zig");
/// Process capabilities for the independently installed frontend producers.
pub const Runtime = @import("config/component_runtime.zig").Runtime;
/// Source failures stay distinct from bounded deployment and transport failures.
pub const HostError = lex_boundary.Error || parse_boundary.Error || declaration_boundary.Error || type_interface_boundary.Error || body_check_boundary.Error;
/// Combined source and host failures for lexing and parsing.
pub const Error = diagnostic.Error || HostError;
/// Value copied into cache contexts only after deployment authentication succeeds.
pub const Verified = struct {
    identity: [32]u8 = referenceIdentity(),
    reuse: bool = true,
};
/// Stable native frontend identity; compiler build identities are folded in by cache owners.
pub fn referenceIdentity() [32]u8 {
    @setEvalBranchQuota(10000);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("frontend-boundary-v1/reference/target-profile/module-and-trust-v1", &digest, .{});
    return digest;
}
/// Shadow configuration forces comparisons on every invocation, including warm runs.
pub fn reusable(runtime: ?Runtime) bool {
    const capabilities = runtime orelse return true;
    for (mode_keys) |key| {
        if (std.mem.eql(u8, capabilities.environ.get(key) orelse reference_mode, "shadow")) return false;
    }
    return true;
}
const mode_keys = [_][]const u8{ "MYLANG_LEXER_MODE", "MYLANG_PARSER_MODE", "MYLANG_DECLARATION_MODE", "MYLANG_TYPE_INTERFACE_MODE", "MYLANG_BODY_CHECK_MODE" };
fn allReference(runtime: Runtime) bool {
    for (mode_keys) |key| {
        if (!std.mem.eql(u8, runtime.environ.get(key) orelse reference_mode, reference_mode)) return false;
    }
    return true;
}
/// Verify all producer identities before cache access. Reference performs no deployment I/O.
pub fn verify(a: std.mem.Allocator, runtime: ?Runtime) HostError!Verified {
    const capabilities = runtime orelse return .{};
    const lex_id = try lex_boundary.identity(a, capabilities);
    const parse_id = try parse_boundary.identity(a, capabilities);
    const declaration_id = try declaration_boundary.identity(a, capabilities);
    const type_interface_id = try type_interface_boundary.identity(a, capabilities);
    const body_check_id = try body_check_boundary.identity(a, capabilities);
    if (allReference(capabilities)) return .{};
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("frontend-boundary-v4/target-profile/module-and-trust-v1/type-interface-v1/body-check-v1");
    hash.update(&lex_id);
    hash.update(&parse_id);
    hash.update(&declaration_id);
    hash.update(&type_interface_id);
    hash.update(&body_check_id);
    var result: [32]u8 = undefined;
    hash.final(&result);
    return .{ .identity = result, .reuse = reusable(runtime) };
}
/// Authenticate the same producer generation immediately before result publication.
pub fn revalidate(a: std.mem.Allocator, runtime: ?Runtime, captured: Verified) HostError!void {
    const current = try verify(a, runtime);
    if (!std.mem.eql(u8, &current.identity, &captured.identity)) return error.ComponentChanged;
}
/// Lex with the selected boundary; absent runtime keeps pure native callers unchanged.
pub fn lex(a: std.mem.Allocator, src: source.Source, sink: *diagnostic.Sink, runtime: ?Runtime) Error![]lexer.Token {
    return if (runtime) |capabilities| lex_boundary.lex(a, src, sink, capabilities) else lexer.lex(a, src.bytes, sink);
}
/// Parse a whole source with explicit module and intrinsic authority from Parser.
pub fn parse(p: *parser.Parser, module: bool, runtime: ?Runtime) Error!ast.Program {
    return if (runtime) |capabilities| parse_boundary.parse(p, module, capabilities) else if (module) p.parseModule() else p.parse();
}
/// Preserve recognized host failures through callers that otherwise collapse syntax errors.
pub fn hostFailure(err: anyerror) ?HostError {
    const failures = [_]HostError{
        error.ComponentMissing,  error.ComponentManifest,       error.ComponentDigest,
        error.ComponentProtocol, error.ComponentTimeout,        error.ComponentFailed,
        error.ComponentIo,       error.ComponentShadowMismatch, error.ComponentMode,
        error.ComponentChanged,  error.ComponentProfile,
    };
    inline for (failures) |failure| if (err == failure) return failure;
    return null;
}
// spec: SELFHOST-FRONTEND-CACHE-1
test "frontend verification keeps reference free of deployment access and rejects invalid modes" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const runtime: Runtime = .{ .io = std.testing.io, .environ = &environment, .component_dir = "missing-frontend-fixture" };
    const native = try verify(std.testing.allocator, runtime);
    try std.testing.expectEqualDeep(Verified{}, native);
    try std.testing.expect(reusable(runtime));
    try environment.put("MYLANG_PARSER_MODE", "invalid");
    try std.testing.expectError(error.ComponentMode, verify(std.testing.allocator, runtime));
    try environment.put("MYLANG_PARSER_MODE", "shadow");
    try std.testing.expect(!reusable(runtime));
    try std.testing.expectError(error.ComponentMissing, verify(std.testing.allocator, runtime));
    try std.testing.expectEqual(error.ComponentDigest, hostFailure(error.ComponentDigest).?);
    try std.testing.expectEqual(@as(?HostError, null), hostFailure(error.SourceError));
}

// spec-case: SELFHOST-DECLARATION-1
test "declaration producer verification precedes cache reuse and shadow disables reuse" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const runtime: Runtime = .{ .io = std.testing.io, .environ = &environment, .component_dir = "missing-declaration-fixture" };
    try std.testing.expectEqualDeep(Verified{}, try verify(std.testing.allocator, runtime));
    try environment.put("MYLANG_DECLARATION_MODE", "invalid");
    try std.testing.expectError(error.ComponentMode, verify(std.testing.allocator, runtime));
    try environment.put("MYLANG_DECLARATION_MODE", "shadow");
    try std.testing.expect(!reusable(runtime));
    try std.testing.expectError(error.ComponentMissing, verify(std.testing.allocator, runtime));
    try environment.put("MYLANG_DECLARATION_MODE", "component");
    try std.testing.expect(reusable(runtime));
    try std.testing.expectError(error.ComponentMissing, verify(std.testing.allocator, runtime));
}

// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface verification precedes cache reuse and shadow disables reuse" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const runtime: Runtime = .{ .io = std.testing.io, .environ = &environment, .component_dir = "missing-type-interface-fixture" };
    try std.testing.expectEqualDeep(Verified{}, try verify(std.testing.allocator, runtime));
    try environment.put("MYLANG_TYPE_INTERFACE_MODE", "invalid");
    try std.testing.expectError(error.ComponentMode, verify(std.testing.allocator, runtime));
    try environment.put("MYLANG_TYPE_INTERFACE_MODE", "shadow");
    try std.testing.expect(!reusable(runtime));
    try std.testing.expectError(error.ComponentMissing, verify(std.testing.allocator, runtime));
    try environment.put("MYLANG_TYPE_INTERFACE_MODE", "component");
    try std.testing.expect(reusable(runtime));
    try std.testing.expectError(error.ComponentMissing, verify(std.testing.allocator, runtime));
}

// spec-case: SELFHOST-BODY-CHECK-1
test "body check producer identity gates reuse and shadow disables retained bodies" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const runtime: Runtime = .{ .io = std.testing.io, .environ = &environment, .component_dir = "missing-body-fixture" };
    try std.testing.expectEqualDeep(Verified{}, try verify(std.testing.allocator, runtime));
    try environment.put("MYLANG_BODY_CHECK_MODE", "shadow");
    try std.testing.expect(!reusable(runtime));
    try std.testing.expectError(error.ComponentMissing, verify(std.testing.allocator, runtime));
    try environment.put("MYLANG_BODY_CHECK_MODE", "invalid");
    try std.testing.expectError(error.ComponentMode, verify(std.testing.allocator, runtime));
}
