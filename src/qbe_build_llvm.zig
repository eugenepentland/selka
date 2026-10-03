//! The LLVM backend's QBE-to-LLVM translator, in process (LLVM-ZIG-1).
//!
//! `translate` turns one emitted QBE unit into a self-contained textual LLVM
//! module: loop versioning first (`qbe_build_llvm_sticky.zig`), then the
//! emitter's analyses and lowering (`qbe_build_llvm_emit.zig`,
//! `qbe_build_llvm_lower.zig`). It is a port of the Python adapter that used to
//! run once per unit, and produces the same bytes for the same unit, closure
//! signatures and target policy. The build driver runs it on worker threads
//! and compiles each module with the bundled clang (`qbe_build_llvm_compile.zig`).
const std = @import("std");
const il = @import("qbe_build_llvm_il.zig");
const emit = @import("qbe_build_llvm_emit.zig");
const lower = @import("qbe_build_llvm_lower.zig");
const sticky = @import("qbe_build_llvm_sticky.zig");
const runtime = @import("qbe_build_llvm_runtime.zig");

/// Translation failures: allocation, or a refusal with a diagnostic.
pub const Error = il.Error;
/// Where a refusal's message is recorded.
pub const Diagnostic = il.Diagnostic;
/// What a translation reads besides the unit.
pub const Options = emit.Options;
/// The closure's signatures, by symbol.
pub const Signatures = emit.Signatures;
/// One unit's signature as a caller sees it.
pub const CallSignature = emit.CallSignature;
/// The runtime helper registry.
pub const RuntimeTable = runtime.Table;
/// One file of the runtime tree the registry reads.
pub const RuntimeSource = runtime.Source;
/// One runtime helper's exact C signature.
pub const RuntimeSignature = runtime.Signature;

/// The version the translator's object keys carry beside the driver identity,
/// so a change to how units become LLVM IR never reuses an object built the
/// old way even under an unchanged driver source.
pub const version = "mylang-llvm-translator-v1";

/// The translator's A/B switches, each on unless its environment variable is
/// `0`: scoped alias metadata (`MYLANG_QBE_LLVM_ALIAS`), element GEPs
/// (`MYLANG_QBE_LLVM_ELEMENT_GEP`) and loop versioning (`MYLANG_QBE_LLVM_STICKY`).
pub const Toggles = struct {
    alias: bool = true,
    element_gep: bool = true,
    sticky: bool = true,

    /// The switches the build environment selects.
    pub fn read(environ: *const std.process.Environ.Map) Toggles {
        return .{ .alias = on(environ, "MYLANG_QBE_LLVM_ALIAS"), .element_gep = on(environ, "MYLANG_QBE_LLVM_ELEMENT_GEP"), .sticky = on(environ, "MYLANG_QBE_LLVM_STICKY") };
    }

    fn on(environ: *const std.process.Environ.Map, name: []const u8) bool {
        const value = environ.get(name) orelse return true;
        return !std.mem.eql(u8, value, "0");
    }

    /// The translator identity an object built under these switches is keyed
    /// by: the version, plus every switch that is off.
    pub fn identity(self: Toggles) []const u8 {
        const table = [_][]const u8{
            version,                     version ++ ";sticky=0",
            version ++ ";gep=0",         version ++ ";gep=0;sticky=0",
            version ++ ";alias=0",       version ++ ";alias=0;sticky=0",
            version ++ ";alias=0;gep=0", version ++ ";alias=0;gep=0;sticky=0",
        };
        const index = @as(usize, @intFromBool(!self.alias)) * 4 + @as(usize, @intFromBool(!self.element_gep)) * 2 + @intFromBool(!self.sticky);
        return table[index];
    }
};

/// Translate one unit's QBE IL into LLVM IR text. All memory comes from
/// `arena`; a refusal returns `TranslationFailed` with `diagnostic.message` set.
pub fn translate(arena: std.mem.Allocator, text: []const u8, options: Options, diagnostic: *Diagnostic) Error![]const u8 {
    const unit = try il.parse(arena, text, diagnostic);
    if (options.sticky) try sticky.versionLoops(arena, unit, diagnostic);
    var selected = options;
    if (unit.function.hints.no_alias_metadata) selected.alias = false;
    var emitter = try emit.Emitter.prepare(arena, unit, selected, diagnostic);
    return lower.module(&emitter);
}

/// One unit's symbol and its signature as a caller sees it.
pub const Header = struct { symbol: []const u8, signature: CallSignature };

/// The symbol, parameter letters and result letter of one unit's function,
/// read from its header without parsing its body.
pub fn header(arena: std.mem.Allocator, text: []const u8, diagnostic: *Diagnostic) Error!Header {
    const function = try il.parseHeader(arena, text, diagnostic);
    const parameters = try arena.alloc([]const u8, function.parameters.len);
    for (function.parameters, parameters) |parameter, *letter| letter.* = parameter.letter;
    return .{ .symbol = function.name, .signature = .{ .parameters = parameters, .result = function.result } };
}

/// Every `$symbol` a unit's text names, which bounds the closure signatures
/// its translation can consult (its callees, globals and `extern` symbols).
pub fn referencedSymbols(arena: std.mem.Allocator, text: []const u8, into: *std.array_hash_map.String(void)) Error!void {
    var at: usize = 0;
    while (std.mem.indexOfScalarPos(u8, text, at, '$')) |dollar| {
        var start = dollar;
        while (start < text.len and text[start] == '$') start += 1;
        var end = start;
        while (end < text.len and il.isNameChar(text[end])) end += 1;
        if (end > start) try into.put(arena, text[start..end], {});
        at = @max(end, dollar + 1);
    }
}
