//! A device build is one command (MCU-C1): `selka build F.selka -o OUT` reads the project's `target` and the device it
//! chooses (`device` in `selka.json`, or `--device NAME`) and takes from that device the target, the linker script,
//! the C files to link, their include folders and the image's form. A flag of the command line wins over each.
//! `check`, `run` and `test` read none of it: only `build` without `--run` builds for a device.
const std = @import("std");
const language = @import("selka");
const cli_args = @import("cli_args.zig");
const pipeline = @import("pipeline.zig");
const target = @import("target.zig");
const device_image = @import("device_image.zig");
const project_config = language.project_config;
const device_layout = language.device_layout;

/// Apply the project's device settings to a `selka build -o OUT` request, then refuse a linker script that does not fit
/// the target (`cli_args.linkerScriptRefusal`). Returns the line to print, with exit status 2, or null when the build may
/// go on. An entry or a configuration that does not load is left to the build, which reports it.
pub fn apply(init: std.process.Init, request: *cli_args.Request) error{OutOfMemory}!?[]const u8 {
    const allocator = init.arena.allocator();
    var ignored: std.ArrayList(u8) = .empty;
    const entry = pipeline.resolveEntry(init, request.path, &ignored) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    if (entry.configuration) |configured| {
        if (try fromConfiguration(allocator, init.io, configured, request)) |refused| return refused;
    } else if (request.device.name) |name| {
        return line(allocator, "selka: `--device {s}` names a device of the project's selka.json, and {s} has none\n", .{ name, request.path });
    }
    const codegen = request.build.show.codegen;
    if (try cli_args.linkerScriptRefusal(allocator, codegen)) |message| return line(allocator, "selka: {s}\n", .{message});
    if (codegen.target.runsHere() and codegen.device.hooks.len != 0)
        return line(allocator, "selka: the device's hooks are for a bare target; the target `{s}` has no platform hooks to bind\n", .{codegen.target.name});
    const uf2 = device_image.formOf(request.build.output, codegen.device.image) == .uf2;
    if (!codegen.target.runsHere() and uf2 and codegen.device.uf2_family == null)
        return "selka: a .uf2 image needs the family id of its device: add \"uf2_family\": \"0x...\" to the device in selka.json\n";
    return null;
}

/// Where a refusal of the configuration is reported: the configuration's path, for its `E_PROJECT_CONFIG` line.
const Place = struct { allocator: std.mem.Allocator, io: std.Io, config: []const u8 };

/// Take the configuration's `target`, and its chosen device's settings, into `request`, under the flags it already has.
fn fromConfiguration(allocator: std.mem.Allocator, io: std.Io, configured: project_config.Config, request: *cli_args.Request) error{OutOfMemory}!?[]const u8 {
    const settings = try project_config.deviceSettings(allocator, configured.bytes);
    const place: Place = .{ .allocator = allocator, .io = io, .config = configured.path };
    var target_name = settings.target;
    if (request.device.name orelse settings.device) |choice| {
        if (std.mem.indexOfScalar(u8, choice, '/') != null)
            return refusal(place, "device \"{s}\" is a package's device; build it with `selka packages build {s} --lock LOCK --command build -- -o OUT`, which reads it from the lock", .{ choice, request.path });
        const device = settings.devices.map.get(choice) orelse
            return refusal(place, "device \"{s}\" names no entry of devices; the devices are {s}", .{ choice, try deviceNames(allocator, settings) });
        if (device.target) |name| target_name = name;
        if (try useDevice(place, choice, device, request)) |refused| return refused;
    }
    if (!request.device.target_named) if (target_name) |name| {
        const named = target.byName(name) orelse
            return refusal(place, "unknown target `{s}`; the targets are {s}", .{ name, target.names });
        // `--cpu` chose a model for the command line's target; the project's replaces that target, so the model goes on to it.
        request.build.show.codegen.target = named.forCpu(request.cpu) orelse
            return line(allocator, "selka: --cpu {s} is for the hosted target; the project's target `{s}` has no CPU model to choose\n", .{ request.cpu.spelling(), name });
    };
    return null;
}

/// Take `device`'s linker script (unless the command line named one; a device that describes its `memory` has the script written
/// from it, `device_layout.generate`), C files, include folders and image into `request`. Every path is resolved against the configuration's folder and must name a file or folder there.
fn useDevice(place: Place, name: []const u8, device: project_config.Device, request: *cli_args.Request) error{OutOfMemory}!?[]const u8 {
    const settings = &request.build.show.codegen.device;
    if (settings.linker_script == null) if (device.linker_script) |script| {
        settings.linker_script = switch (try existing(place, .{ .device = name, .field = "linker_script", .relative = script })) {
            .path => |path| path,
            .refused => |line_| return line_,
        };
    };
    if (settings.linker_script == null) if (device.startup.memory != null) {
        var buffer: [384]u8 = undefined;
        switch (try device_layout.parse(place.allocator, device.startup, false, &buffer)) {
            .layout => |layout| settings.linker_text = try device_layout.generate(place.allocator, layout),
            .refused => |text| return refusal(place, "device \"{s}\": {s}", .{ name, text }),
            .absent => {},
        }
    };
    if (device.startup.hooks) |bound| {
        var hooks: std.ArrayList(pipeline.Hook) = .empty;
        for (bound.map.keys(), bound.map.values()) |hook, function|
            try hooks.append(place.allocator, .{ .name = hook, .function = function, .device = name, .config = place.config });
        settings.hooks = hooks.items;
    }
    var links: std.ArrayList([]const u8) = .empty;
    for (device.links) |link| switch (try existing(place, .{ .device = name, .field = "links", .relative = link })) {
        .path => |path| try links.append(place.allocator, path),
        .refused => |line_| return line_,
    };
    try links.appendSlice(place.allocator, request.build.links);
    request.build.links = links.items;
    var include: std.ArrayList([]const u8) = .empty;
    for (device.include) |folder| switch (try existing(place, .{ .device = name, .field = "include", .relative = folder })) {
        .path => |path| try include.append(place.allocator, path),
        .refused => |line_| return line_,
    };
    try include.appendSlice(place.allocator, settings.include);
    settings.include = include.items;
    if (device.image) |image| settings.image = std.meta.stringToEnum(device_image.Form, image) orelse .elf;
    if (device.uf2_family) |family| settings.uf2_family = project_config.uf2Family(family);
    return null;
}

/// One path of a device as the configuration spells it: the device's name, the field and the relative path.
const DevicePath = struct { device: []const u8, field: []const u8, relative: []const u8 };

/// A device path resolved: its absolute path, or the line that refuses it.
const Resolved = union(enum) { path: []const u8, refused: []const u8 };

/// The absolute path of a device's path, or its refusal: it names nothing, or its real location is outside the
/// configuration's folder (a symbolic link inside the folder that points out of it).
fn existing(place: Place, at: DevicePath) error{OutOfMemory}!Resolved {
    const folder = std.fs.path.dirname(place.config) orelse ".";
    const absolute = try std.fs.path.resolve(place.allocator, &.{ folder, at.relative });
    const cwd = std.Io.Dir.cwd();
    const real = cwd.realPathFileAlloc(place.io, absolute, place.allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .refused = (try refusal(place, "device \"{s}\": {s} entry \"{s}\" names no file ({s})", .{ at.device, at.field, at.relative, absolute })).? },
    };
    const home = cwd.realPathFileAlloc(place.io, folder, place.allocator) catch return .{ .path = absolute };
    if (!project_config.realPathInside(home, real)) return .{ .refused = (try refusal(
        place,
        "device \"{s}\": {s} entry \"{s}\" leaves the folder of this selka.json through a symbolic link (its real location is {s})",
        .{ at.device, at.field, at.relative, real },
    )).? };
    return .{ .path = absolute };
}

/// One `E_PROJECT_CONFIG` line of the configuration at `place`.
fn refusal(place: Place, comptime format: []const u8, arguments: anytype) error{OutOfMemory}!?[]const u8 {
    return line(place.allocator, "{s}: error[E_PROJECT_CONFIG]: " ++ format ++ "\n", .{place.config} ++ arguments);
}

/// One line to print, made by `format`.
fn line(allocator: std.mem.Allocator, comptime format: []const u8, arguments: anytype) error{OutOfMemory}!?[]const u8 {
    const text = try std.fmt.allocPrint(allocator, format, arguments);
    return text;
}

/// The names of the configuration's devices, for the refusal of a name that is not one ("none" when it has none).
fn deviceNames(allocator: std.mem.Allocator, settings: project_config.DeviceSettings) error{OutOfMemory}![]const u8 {
    const names = settings.devices.map.keys();
    if (names.len == 0) return "none";
    return std.mem.join(allocator, ", ", names);
}

/// After a build for a target that only builds wrote its ELF at `options.output`: replace it with the image its name, or
/// its device's `image`, asks for. Returns the line to print, with exit status 2, when the image cannot be made.
pub fn writeImage(init: std.process.Init, options: pipeline.Options) error{OutOfMemory}!?[]const u8 {
    const codegen = options.show.codegen;
    if (codegen.target.runsHere()) return null;
    const form = device_image.formOf(options.output, codegen.device.image);
    const written = device_image.rewrite(init.arena.allocator(), init.io, options.output, form, codegen.device.uf2_family);
    return imageFailure(init.arena.allocator(), .{ .form = form, .output = options.output }, written);
}

/// The image `writeImage` was writing: its form and its path.
const Written = struct { form: device_image.Form, output: []const u8 };

/// The line that says why `writeImage` could not make the image, or null when `written` succeeded.
fn imageFailure(allocator: std.mem.Allocator, image: Written, written: device_image.RewriteError!void) error{OutOfMemory}!?[]const u8 {
    written catch |err| {
        const reason = switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.TooLarge => "its loadable sections span more than 256 MiB, and a raw image fills the gaps between them",
            error.NoFamily => "the device names no uf2_family",
            else => @errorName(err),
        };
        return line(allocator, "selka: cannot write the {t} image {s}: {s}\n", .{ image.form, image.output, reason });
    };
    return null;
}

test "writeImage's refusal names the image, its form and why" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const image: Written = .{ .form = .bin, .output = "prog.bin" };
    try std.testing.expectEqual(@as(?[]const u8, null), try imageFailure(arena.allocator(), image, {}));
    const large = (try imageFailure(arena.allocator(), image, error.TooLarge)).?;
    try std.testing.expectEqualStrings("selka: cannot write the bin image prog.bin: its loadable sections span more than 256 MiB, and a raw image fills the gaps between them\n", large);
    const not_elf = (try imageFailure(arena.allocator(), image, error.NotElf32)).?;
    try std.testing.expectEqualStrings("selka: cannot write the bin image prog.bin: NotElf32\n", not_elf);
    try std.testing.expectError(error.OutOfMemory, imageFailure(arena.allocator(), image, error.OutOfMemory));
}
