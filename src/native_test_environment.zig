//! Pin inherited frontend, C-driver and Python-adapter build inputs without
//! exposing their values in cache paths or receipts.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
/// Allocation and canonical environment serialization failures.
pub const Error = fs.Error;
/// Canonical compiler-input fingerprint and eligibility for persistent results.
pub const Fingerprint = struct { hash: []const u8, cacheable: bool };
const compiler_inputs = [_][]const u8{
    "CCC_OVERRIDE_OPTIONS",
    "COMPILER_PATH",
    "CPATH",
    "CPLUS_INCLUDE_PATH",
    "C_INCLUDE_PATH",
    "GCC_EXEC_PREFIX",
    "LIBRARY_PATH",
    "MYLANG_HOST_COMPILER",
    "MYLANG_LLVM_ADAPTER",
    "MYLANG_QBE_LLVM_OPT",
    "MYLANG_QBE_LLVM_UNIT",
    "MYLANG_SEMANTIC_BUDGET",
    "OBJC_INCLUDE_PATH",
    "PYTHONHASHSEED",
    "PYTHONHOME",
    "PYTHONOPTIMIZE",
    "PYTHONPATH",
    "SOURCE_DATE_EPOCH",
    "ZIG_LIBC",
    "ZIG_LIB_DIR",
};
/// Fingerprint only inherited inputs read by compiler/build children. Dynamic
/// loader overrides can read mutable external libraries, so disable reuse.
pub fn capture(context: fs.Context) Error!Fingerprint {
    var pairs: std.ArrayList([2][]const u8) = .empty;
    defer pairs.deinit(context.allocator);
    var entries = context.environ.iterator();
    var cacheable = true;
    while (entries.next()) |entry| {
        if (std.mem.startsWith(u8, entry.key_ptr.*, "LD_") and entry.value_ptr.len != 0) cacheable = false;
        for (compiler_inputs) |name| {
            if (std.mem.eql(u8, entry.key_ptr.*, name)) {
                try pairs.append(context.allocator, .{ entry.key_ptr.*, entry.value_ptr.* });
                break;
            }
        }
    }
    std.mem.sort([2][]const u8, pairs.items, {}, less);
    const bytes = try std.json.Stringify.valueAlloc(context.allocator, pairs.items, .{});
    return .{ .hash = try fs.hash(context.allocator, bytes), .cacheable = cacheable };
}
fn less(_: void, a: [2][]const u8, b: [2][]const u8) bool {
    return std.mem.lessThan(u8, a[0], b[0]);
}
// spec: NATIVE-TEST-12
test "environment fingerprints ignore unrelated variables but retain compiler inputs and loader safety" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    try environment.put("IGNORED_B", "2");
    try environment.put("MYLANG_QBE", "/tools/qbe-a");
    try environment.put("MYLANG_SEMANTIC_BUDGET", "1M");
    const first = try capture(context);
    var reordered: std.process.Environ.Map = .init(std.testing.allocator);
    defer reordered.deinit();
    try reordered.put("MYLANG_SEMANTIC_BUDGET", "1M");
    try reordered.put("IGNORED_B", "changed");
    try reordered.put("MYLANG_QBE", "/tools/qbe-b");
    context.environ = &reordered;
    try std.testing.expectEqualStrings(first.hash, (try capture(context)).hash);
    context.environ = &environment;
    try environment.put("MYLANG_SEMANTIC_BUDGET", "2M");
    try std.testing.expect(!std.mem.eql(u8, first.hash, (try capture(context)).hash));
    const compiler_changed = try capture(context);
    try environment.put("C_INCLUDE_PATH", "/headers");
    try std.testing.expect(!std.mem.eql(u8, compiler_changed.hash, (try capture(context)).hash));
    const c_changed = try capture(context);
    try environment.put("PYTHONPATH", "/adapter-modules");
    try std.testing.expect(!std.mem.eql(u8, c_changed.hash, (try capture(context)).hash));
    try environment.put("LD_LIBRARY_PATH", "/mutable");
    try std.testing.expect(!(try capture(context)).cacheable);
}
