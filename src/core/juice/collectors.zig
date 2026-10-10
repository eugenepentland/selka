//! Linux perf and Valgrind adapters. The report core does not import this module.
const std = @import("std");
const key_callgrind = "callgrind";
const d = @import("data.zig");
const p = @import("platform.zig");
const profiles = @import("profiles.zig");
const C = d.Context;
const V = d.Value;
/// Selected measurement tool and exact target CPU/event semantics.
pub const Collector = struct { kind: []const u8, cpu: usize, identity: V, extra: V };
fn containsCpu(text: []const u8, cpu: usize) !bool {
    var parts = std.mem.tokenizeAny(u8, text, ",\n \t");
    while (parts.next()) |part| {
        var bounds = std.mem.splitScalar(u8, part, '-');
        const low = try std.fmt.parseInt(usize, bounds.next().?, 10);
        const high = if (bounds.next()) |last| try std.fmt.parseInt(usize, last, 10) else low;
        if (low > high or bounds.next() != null) return error.InvalidExperiment;
        if (cpu >= low and cpu <= high) return true;
    }
    return false;
}
fn cpuChoice(c: *C, requested: ?usize) !usize {
    var mask: std.os.linux.cpu_set_t = undefined;
    if (std.os.linux.errno(std.os.linux.sched_getaffinity(0, @sizeOf(@TypeOf(mask)), &mask)) != .SUCCESS) return c.fail("cannot read allowed CPU affinity");
    const bytes = std.mem.asBytes(&mask);
    const reserved = c.env.get("MYLANG_TIMING_CPUS") orelse "2,3,10,11";
    var fallback: ?usize = null;
    for (0..bytes.len * 8) |i| if (bytes[i / 8] & (@as(u8, 1) << @intCast(i % 8)) != 0) {
        if (fallback == null) fallback = i;
        if (requested) |r| {
            if (r == i) return i;
        } else if (!try containsCpu(reserved, i)) return i;
    };
    if (requested != null) return c.fail("CPU is outside allowed affinity");
    return fallback orelse c.fail("no allowed CPU");
}
fn event(c: *C, cpu: usize) ![]const u8 {
    for ([_][]const u8{ "cpu_core", "cpu_atom" }) |name| {
        const path = try c.join(&.{ "/sys/bus/event_source/devices", name, "cpus" });
        const cpus = c.readBytes(path) catch continue;
        if (try containsCpu(cpus, cpu)) return std.fmt.allocPrint(c.a, "{s}/instructions/u", .{name});
    }
    return "instructions:u";
}
/// Probe tool identity and CPU availability without executing an application.
pub fn init(c: *C, kind: []const u8, cpu: ?usize, perf: []const u8, valgrind: []const u8) d.Error!Collector {
    return initImpl(c, kind, cpu, perf, valgrind) catch |err| d.failure(c, err);
}
fn initImpl(c: *C, kind: []const u8, cpu: ?usize, perf: []const u8, valgrind: []const u8) !Collector {
    try p.supported(c);
    const known_kind = std.mem.eql(u8, kind, "perf") or std.mem.eql(u8, kind, key_callgrind) or std.mem.eql(u8, kind, "cachegrind");
    if (!known_kind) return c.fail("collector must be perf, callgrind or cachegrind");
    const selected = try cpuChoice(c, cpu);
    const is_perf = std.mem.eql(u8, kind, "perf");
    var identity = try c.value(.{
        .kind = kind,
        .tool = try p.identity(c, if (is_perf) perf else valgrind),
        .event = if (is_perf) try event(c, selected) else "Ir",
        .cpu = selected,
        .scope = "user instructions; process and inherited children; whole workload",
    });
    var extra = d.object();
    if (!is_perf) if (c.env.get("VALGRIND_LIB")) |library| {
        const root = try p.real(c, library);
        try d.put(c, &extra, "VALGRIND_LIB", d.string(root));
        var engines = d.object();
        var dir = try std.Io.Dir.cwd().openDir(c.io, root, .{ .iterate = true });
        defer dir.close(c.io);
        var it = dir.iterate();
        const prefix = try std.fmt.allocPrint(c.a, "{s}-", .{kind});
        while (try it.next(c.io)) |entry| if (entry.kind == .file and std.mem.startsWith(u8, entry.name, prefix)) {
            try d.put(c, &engines, try c.a.dupe(u8, entry.name), try c.fileHash(try c.join(&.{ root, entry.name })));
        };
        if (engines.object.count() == 0) return c.fail("VALGRIND_LIB has no selected collector engine");
        try d.put(c, &identity, "engines", engines);
    };
    return .{ .kind = kind, .cpu = selected, .identity = identity, .extra = extra };
}
fn append(c: *C, argv: *std.ArrayList([]const u8), format: []const u8, value: []const u8) !void {
    try argv.append(c.a, try std.mem.concat(c.a, u8, &.{ format, value }));
}
/// Opt in to a simultaneous fixed-counter group; preserve legacy instruction records.
pub fn selectProfile(c: *C, collector: *Collector, name: []const u8) d.Error!void {
    return profileImpl(c, collector, name) catch |err| d.failure(c, err);
}
fn profileImpl(c: *C, collector: *Collector, name: []const u8) !void {
    if (std.mem.eql(u8, name, "work")) return;
    if (!std.mem.eql(u8, name, "runtime") or !std.mem.eql(u8, collector.kind, "perf")) return c.fail("runtime profile requires perf; profile must be work or runtime");
    const instruction_event = try d.str(d.get(collector.identity, "event"));
    const cycles = try std.mem.replaceOwned(u8, c.a, instruction_event, d.key_instructions, "cycles");
    const reference = try std.mem.replaceOwned(u8, c.a, instruction_event, d.key_instructions, "ref-cycles");
    try d.put(c, &collector.identity, "event_group", d.string(try std.fmt.allocPrint(c.a, "{{{s},{s},{s}}}", .{ instruction_event, cycles, reference })));
    try d.put(c, &collector.identity, "profile", d.string("runtime"));
    try d.put(c, &collector.identity, "scope", d.string("user instructions, cycles and reference cycles; process and inherited children; whole workload"));
}
/// Record one measured run and retain all raw profiles before parsing them.
pub fn collect(c: *C, collector: Collector, options: p.Run, workload: V) d.Error!V {
    return collectImpl(c, collector, options, workload) catch |err| d.failure(c, err);
}
fn collectImpl(c: *C, collector: Collector, options: p.Run, workload: V) !V {
    const raw = try c.join(&.{ options.cwd, "collector" });
    const tool = try d.str(d.get(d.get(collector.identity, "tool"), "path"));
    const is_perf = std.mem.eql(u8, collector.kind, "perf");
    const region = d.get(workload, "region");
    if (region != .null and !std.mem.eql(u8, collector.kind, key_callgrind)) return c.fail("function regions require callgrind; use a short harness with perf");
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(c.a, tool);
    if (is_perf) {
        const group = d.get(collector.identity, "event_group");
        const selected = if (group == .null) d.get(collector.identity, "event") else group;
        try argv.appendSlice(c.a, &.{ "stat", "--no-big-num", "--no-scale", "-x", ";", "-e", try d.str(selected), "-o", raw, "--" });
    } else {
        try append(c, &argv, "--tool=", collector.kind);
        try argv.appendSlice(c.a, &.{ "--trace-children=yes", "--cache-sim=no", "--branch-sim=no" });
        try append(c, &argv, "--log-file=", try std.fmt.allocPrint(c.a, "{s}.log.%p", .{raw}));
        try argv.append(c.a, try std.fmt.allocPrint(c.a, "--{s}-out-file={s}.%p", .{ collector.kind, raw }));
        if (std.mem.eql(u8, collector.kind, key_callgrind)) {
            try argv.appendSlice(c.a, &.{ "--collect-bus=yes", "--dump-line=yes", "--dump-instr=yes" });
            if (region != .null) try append(c, &argv, "--toggle-collect=", try d.str(region));
        }
    }
    try argv.appendSlice(c.a, options.argv);
    var env = try options.env.clone(c.a);
    for (try d.keys(c, collector.extra)) |key| try env.put(key, try d.str(d.get(collector.extra, key)));
    var run_options = options;
    run_options.argv = argv.items;
    run_options.env = &env;
    run_options.cpu = collector.cpu;
    var result = try p.run(c, run_options);
    try d.put(c, &result, d.key_functions, d.array(c));
    try d.put(c, &result, "lines", d.array(c));
    if (try d.num(d.get(result, "exit_code")) != 0) return c.fail("collector or program exited unsuccessfully; raw output retained");
    if (is_perf) {
        try p.copy(c, raw, try std.fmt.allocPrint(c.a, "{s}.perf", .{options.prefix}));
        const bytes = try c.readBytes(raw);
        const selected = try d.str(d.get(collector.identity, "event"));
        const measured = if (d.is(d.get(collector.identity, "profile"), "runtime")) try profiles.runtime(c, bytes, selected) else try profiles.perf(c, bytes, selected);
        try d.put(c, &result, "metrics", measured);
    } else {
        try readGrind(c, &result, options);
    }
    _ = try d.positive(d.get(d.get(result, "metrics"), d.key_instructions));
    return result;
}
fn readGrind(c: *C, result: *V, options: p.Run) !void {
    var dir = try std.Io.Dir.cwd().openDir(c.io, options.cwd, .{ .iterate = true });
    defer dir.close(c.io);
    var it = dir.iterate();
    var found: usize = 0;
    var total = d.object();
    var functions = d.get(result.*, d.key_functions);
    var lines = d.get(result.*, "lines");
    while (try it.next(c.io)) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "collector.")) continue;
        const source = try c.join(&.{ options.cwd, entry.name });
        const target = try std.fmt.allocPrint(c.a, "{s}.{s}", .{ options.prefix, entry.name });
        try p.copy(c, source, target);
        if (std.mem.startsWith(u8, entry.name, "collector.log.")) continue;
        _ = std.fmt.parseInt(u64, entry.name[10..], 10) catch continue;
        const profile = try profiles.grind(c, try c.readBytes(source));
        found += 1;
        for (try d.keys(c, d.get(profile, "metrics"))) |key| {
            const old = d.get(total, key);
            try d.put(c, &total, key, .{ .float = (if (old == .null) @as(f64, 0) else try d.num(old)) + try d.num(d.get(d.get(profile, "metrics"), key)) });
        }
        for (try d.items(d.get(profile, d.key_functions))) |row| try d.add(c, &functions, row);
        for (try d.items(d.get(profile, "lines"))) |row| try d.add(c, &lines, row);
    }
    if (found == 0) return c.fail("Valgrind wrote no complete profile");
    try d.put(c, result, "metrics", total);
    try d.put(c, result, d.key_functions, functions);
    try d.put(c, result, "lines", lines);
}
/// Relevant CPU and kernel context, excluding transient frequencies and load.
pub fn context(c: *C, collector: Collector, work: []const u8, libraries: V) d.Error!V {
    return contextImpl(c, collector, work, libraries) catch |err| d.failure(c, err);
}
fn schedulingPolicy(c: *C, cpu: usize) !V {
    var result = d.object();
    for ([_][]const u8{ "scaling_driver", "scaling_governor", "scaling_min_freq", "scaling_max_freq" }) |key| {
        const path = try std.fmt.allocPrint(c.a, "/sys/devices/system/cpu/cpu{d}/cpufreq/{s}", .{ cpu, key });
        const value = c.readBytes(path) catch "unavailable";
        try d.put(c, &result, key, d.string(std.mem.trim(u8, value, " \r\n\t")));
    }
    const scheduler = c.readBytes("/proc/self/sched") catch return result;
    var lines = std.mem.splitScalar(u8, scheduler, '\n');
    while (lines.next()) |line| if (std.mem.indexOfScalar(u8, line, ':')) |at| {
        const key = std.mem.trim(u8, line[0..at], " \t");
        for ([_][]const u8{ "policy", "prio", "uclamp.min", "uclamp.max", "effective uclamp.min", "effective uclamp.max" }) |name| {
            if (std.mem.eql(u8, key, name)) try d.put(c, &result, name, d.string(std.mem.trim(u8, line[at + 1 ..], " \t")));
        }
    };
    return result;
}
fn contextImpl(c: *C, collector: Collector, work: []const u8, libraries: V) !V {
    const text = try c.readBytes("/proc/cpuinfo");
    var blocks = std.mem.splitSequence(u8, text, "\n\n");
    var cpu = d.object();
    while (blocks.next()) |block| {
        var fields = d.object();
        var lines = std.mem.splitScalar(u8, block, '\n');
        while (lines.next()) |line| if (std.mem.indexOfScalar(u8, line, ':')) |at| {
            try d.put(c, &fields, std.mem.trim(u8, line[0..at], " \t"), d.string(std.mem.trim(u8, line[at + 1 ..], " \t")));
        };
        const processor = d.get(fields, "processor");
        if (processor == .null or (std.fmt.parseInt(usize, try d.str(processor), 10) catch continue) != collector.cpu) continue;
        for ([_][]const u8{ "vendor_id", "cpu family", "model", "model name", "stepping", "microcode", "flags" }) |key| if (d.get(fields, key) != .null) {
            try d.put(c, &cpu, key, d.get(fields, key));
        };
        break;
    }
    if (cpu.object.count() == 0) return c.fail(try std.fmt.allocPrint(c.a, "cannot identify selected CPU {d} in {d} bytes", .{ collector.cpu, text.len }));
    var result = try c.value(.{
        .system = "Linux",
        .kernel = std.mem.trim(u8, try c.readBytes("/proc/sys/kernel/osrelease"), "\r\n"),
        .machine = "x86_64",
        .cpu = cpu,
        .libraries = libraries,
        .execution_path = work,
        .collector = collector.identity,
    });
    if (d.is(d.get(collector.identity, "profile"), "runtime")) try d.put(c, &result, "scheduling_policy", try schedulingPolicy(c, collector.cpu));
    return result;
}
