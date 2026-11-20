//! The standard library's `builtin func` declarations and what supplies each one (W10).
//!
//! A `builtin func` has no body on the page: the compiler supplies its calls. This file is the one answer to "what
//! supplies it": a retired-method home lowers to the buffer operation its method spelling built (`retired_methods`), a
//! `simd` lane operation is checked by `sema_simd.zig`, a scalar text helper by `scalar_text_helpers.zig`, the
//! `parallel.map` family, `parallel.threads` and `parallel.cpus` are built by `core/build_parallel.zig` and the two `testing` counter readers by
//! `core/build_testing.zig`. A declaration whose name no supplier answers is refused (`E_BUILTIN_SUPPLIER`), so a
//! declaration cannot claim an operation the compiler does not have.
//!
//! Every call of a supplied function is the operation, however it is spelled: the module's own name, an import alias, a
//! re-export, keyword arguments or explicit type arguments (`sema_calls.zig`, `routeSupplied`). A non-generic home is
//! also a function value; its body is the parser's one-line call of itself, which the checker supplies in the same way,
//! so the value runs the operation too. A `simd` operation or a scalar text helper is not a function value
//! (`E_BUILTIN_FUNCTION_VALUE`): each one is checked against its arguments, which a value's one signature cannot say.
const std = @import("std");
const product = @import("product.zig");
const retired_methods = @import("retired_methods.zig");
const scalar_text_helpers = @import("scalar_text_helpers.zig");
const standard_library = @import("standard_library.zig");

/// The code for a `builtin func` whose name no supplier answers.
pub const supplier_code = "E_BUILTIN_SUPPLIER";
/// The code for a supplied operation used as a function value.
pub const function_value_code = "E_BUILTIN_FUNCTION_VALUE";
/// The code for a `builtin func` whose declared result is not what its operation answers.
pub const signature_code = "E_BUILTIN_SIGNATURE";

/// The `simd` lane operations, by the name a call spells after `simd.`.
pub const LaneOperation = enum { splat, load, store, select, sum, min, max, fma, sqrt };

/// What supplies one `builtin func`.
pub const Supplier = union(enum) {
    /// A retired method's function home: the call is the method's buffer operation.
    home: retired_methods.Retirement,
    /// A `simd` lane operation, checked against its operands and expected type.
    lane: LaneOperation,
    /// A scalar text helper (`strings.char_count`) or `lists.stride`.
    scalar: scalar_text_helpers.ScalarHelper,
    /// A member of the `parallel.map` family, or `parallel.threads` or `parallel.cpus`, whose body the Core builder writes.
    parallel,
    /// One of the `testing` counter readers, whose body the Core builder writes.
    testing,
    /// `json.encode` or `json.decode`, whose body for each concrete type the Core builder writes (`core/build_json.zig`).
    json,
    /// A `registers` operation (`read32`, `write32`, `simulated`, ...) or a `cpu` one (`send_event`, `barrier`, ...), whose
    /// body the Core builder writes as one call of the runtime's simulated bank (`core/build_registers.zig`).
    registers,

    /// Whether a function value of the declaration runs the operation: only a home's body is its operation.
    pub fn valueRuns(self: Supplier) bool {
        return self == .home;
    }
};

/// The `parallel.map` family, `parallel.threads` and `parallel.cpus`, whose bodies `core/build_parallel.zig` writes.
pub const parallel_functions = [_][]const u8{ "map", "map_results", "map_with1", "map_with2", "map_with3", "map_with4", "map_with5", "threads", "cpus" };
/// The `testing` counter readers, whose bodies `core/build_testing.zig` writes.
pub const testing_functions = [_][]const u8{ "__test_blocks", "__test_allocations" };
/// The derived codec functions of `json`, whose bodies `core/build_json.zig` writes for each concrete type.
pub const json_functions = [_][]const u8{ "encode", "decode" };
/// The `registers` operations, whose bodies `core/build_registers.zig` writes.
pub const registers_functions = [_][]const u8{
    "simulated",   "read8",       "read16",        "read32",      "write8",      "write16",  "write32",
    "poke32",      "write_count", "write_address", "write_value", "write_width", "script32", "pin32",
    "start_core1",
};
/// The `cpu` operations (MCU-NOC1), whose bodies `core/build_registers.zig` writes as the registers operations' are.
pub const cpu_functions = [_][]const u8{
    "wait_for_event",       "wait_for_interrupt",     "send_event",  "barrier",      "breakpoint",
    "__interrupts_disable", "__interrupts_set",       "event_count", "__event_kind", "event_writes_before",
    "__interrupts_now",     "__write_interrupts_off",
};

/// The supplier of `module.name` declared with `parameters` parameters, or null when the compiler supplies no such
/// function. `module` is the embedded module's name (`strings`).
pub fn supplier(module: []const u8, name: []const u8, parameters: usize) ?Supplier {
    if (home(module, name, parameters)) |row| return .{ .home = row };
    if (std.mem.eql(u8, module, "simd")) if (std.meta.stringToEnum(LaneOperation, name)) |operation| return .{ .lane = operation };
    if (scalar_text_helpers.named(module, name)) |candidate| return .{ .scalar = candidate };
    if (std.mem.eql(u8, module, "parallel")) for (parallel_functions) |member| if (std.mem.eql(u8, member, name)) return .parallel;
    if (std.mem.eql(u8, module, "testing")) for (testing_functions) |member| if (std.mem.eql(u8, member, name)) return .testing;
    if (std.mem.eql(u8, module, "json")) for (json_functions) |member| if (std.mem.eql(u8, member, name)) return .json;
    if (std.mem.eql(u8, module, "registers")) for (registers_functions) |member| if (std.mem.eql(u8, member, name)) return .registers;
    if (std.mem.eql(u8, module, "cpu")) for (cpu_functions) |member| if (std.mem.eql(u8, member, name)) return .registers;
    return null;
}

/// The retired-method home `module.name` with `parameters` parameters supplies, or a library-only home
/// (`strings.find_offset`), or null. An option home (`strings.find`) is a real function with a body, not a supplied one.
pub fn home(module: []const u8, name: []const u8, parameters: usize) ?retired_methods.Retirement {
    const row = retired_methods.home(module, name, parameters) orelse retired_methods.libraryHome(module, name, parameters) orelse return null;
    if (row.home.absence == .option) return null;
    return row;
}

/// The embedded module a checked source path names (`@stdlib/strings.selka` is `strings`), or null for any other source.
pub fn embeddedModule(path: []const u8) ?[]const u8 {
    const prefix = "@stdlib/";
    if (!std.mem.startsWith(u8, path, prefix) or !product.isSource(path)) return null;
    const file = path[prefix.len..];
    if (standard_library.source(file) == null) return null;
    return product.sourceStem(file);
}

/// The supplied functions whose declared result is not what a call answers, and why. The signature test exempts them.
pub const unsigned_results = [_]struct { module: []const u8, name: []const u8, reason: []const u8 }{
    .{ .module = "dicts", .name = "keys", .reason = "a call answers a live view of the keys, which no signature can name; `-> K[]` is the snapshot `list(...)` makes of it" },
    .{ .module = "dicts", .name = "values", .reason = "a call answers a live view of the values, which no signature can name; `-> V[]` is the snapshot `list(...)` makes of it" },
    .{ .module = "dicts", .name = "items", .reason = "a call answers a live view of the entries, which no signature can name; `-> DictItem[K, V][]` is the snapshot `list(...)` makes of it" },
    .{ .module = "strings", .name = "chars", .reason = "a call is a loop source only (`for c in strings.chars(text):`); `-> str[]` names what one loop pass reads" },
    .{ .module = "strings", .name = "bytes", .reason = "a call is a loop source only (`for b in strings.bytes(text):`); `-> int[]` names what one loop pass reads" },
};

/// Whether `module.name` answers something other than its declared result (`unsigned_results`).
pub fn unsignedResult(module: []const u8, name: []const u8) bool {
    for (unsigned_results) |entry| if (std.mem.eql(u8, entry.module, module) and std.mem.eql(u8, entry.name, name)) return true;
    return false;
}
