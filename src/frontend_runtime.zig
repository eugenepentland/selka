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
/// Process capabilities for the independently installed frontend producers.
pub const Runtime = @import("config/component_runtime.zig").Runtime;
/// Source failures stay distinct from bounded deployment and transport failures.
pub const HostError = lex_boundary.Error || parse_boundary.Error || declaration_boundary.Error;
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
    const lex_mode = capabilities.environ.get("MYLANG_LEXER_MODE") orelse reference_mode;
    const parse_mode = capabilities.environ.get("MYLANG_PARSER_MODE") orelse reference_mode;
    const declaration_mode = capabilities.environ.get("MYLANG_DECLARATION_MODE") orelse reference_mode;
    return !std.mem.eql(u8, lex_mode, "shadow") and !std.mem.eql(u8, parse_mode, "shadow") and !std.mem.eql(u8, declaration_mode, "shadow");
}
/// Verify all producer identities before cache access. Reference performs no deployment I/O.
pub fn verify(a: std.mem.Allocator, runtime: ?Runtime) HostError!Verified {
    const capabilities = runtime orelse return .{};
    const lex_id = try lex_boundary.identity(a, capabilities);
    const parse_id = try parse_boundary.identity(a, capabilities);
    const declaration_id = try declaration_boundary.identity(a, capabilities);
    if (std.mem.eql(u8, capabilities.environ.get("MYLANG_LEXER_MODE") orelse reference_mode, reference_mode) and
        std.mem.eql(u8, capabilities.environ.get("MYLANG_PARSER_MODE") orelse reference_mode, reference_mode) and
        std.mem.eql(u8, capabilities.environ.get("MYLANG_DECLARATION_MODE") orelse reference_mode, reference_mode)) return .{};
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("frontend-boundary-v2/target-profile/module-and-trust-v1/declaration-index-v1");
    hash.update(&lex_id);
    hash.update(&parse_id);
    hash.update(&declaration_id);
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
