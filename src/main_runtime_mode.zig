//! Experimental native runtime selection, settled after value semantics and
//! before any compiler, test or native artifact lookup.
const std = @import("std");
const language = @import("mylang");
const contract = @import("runtime_contract");
const restart = @import("main_mode_restart.zig");
const options = @import("main_runtime_flags.zig");

/// Allocation and diagnostic output errors during command normalization.
pub const Error = restart.Error;

/// Normalized command arguments or an already diagnosed refusal/restart status.
pub const Settled = union(enum) { run: []const [:0]const u8, status: u8 };

/// Select the ownership ABI, preserving the legacy GC model when RC is inherited.
pub fn settle(process: std.process.Init, args: []const [:0]const u8, values: bool) Error!Settled {
    const parsed = options.parse(process.arena.allocator(), args) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidRuntimeOption => return refuse(process, "choose exactly one of --gc-runtime, --rc-runtime, --rc-runtime=stats or --rc-runtime=sites"),
    };
    if (parsed.explicit != null and !accepts(args[1])) return refuse(process, "runtime selection applies to commands that check, emit, build or run programs");
    const environment = process.environ_map.get(contract.variable);
    const requested = parsed.explicit orelse (contract.parse(environment) catch return refuse(process, "MYLANG_RUNTIME must be gc-v1, rc-v3, rc-v3-counting or rc-v3-sites"));
    const selected = contract.resolve(requested, values, parsed.explicit != null) catch return refuse(process, "explicit RC requires value semantics; --legacy-sharing uses GC");
    if (environment == null or !std.mem.eql(u8, environment.?, selected.identity())) {
        return .{ .status = try restart.replace(process, parsed.args, contract.variable, selected.identity()) };
    }
    language.runtime_mode.set(selected);
    return .{ .run = parsed.args };
}

/// Ignore runtime flags only during project discovery; the real normalization
/// later reports invalid or duplicate selections without losing their explicitness.
pub fn discoveryArgs(a: std.mem.Allocator, args: []const [:0]const u8) std.mem.Allocator.Error![]const [:0]const u8 {
    const parsed = options.parse(a, args) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidRuntimeOption => return args,
    };
    return parsed.args;
}

fn accepts(command: []const u8) bool {
    for ([_][]const u8{ "check", "check-module", "check-project", "build", "run", "run-project", "test", "emit-qbe", "emit-project-qbe", "dump-bytecode", "fix", "invoke", "emit-runtime" }) |name| {
        if (std.mem.eql(u8, name, command)) return true;
    }
    return false;
}

fn refuse(process: std.process.Init, message: []const u8) Error!Settled {
    const text = try std.fmt.allocPrint(process.arena.allocator(), "mylang: {s}\n", .{message});
    try std.Io.File.stderr().writeStreamingAll(process.io, text);
    return .{ .status = 2 };
}
