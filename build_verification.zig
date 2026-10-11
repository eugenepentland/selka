//! Authoritative whole-action inventory for the optional developer coordinator.
//! Registration names existing gate steps; it never changes their execution.
const std = @import("std");
const test_inputs = @import("build_test_inputs.zig");

/// One independently reusable group, or an explicitly fresh action cohort.
pub const Group = struct {
    id: []const u8,
    target: []const u8,
    label: []const u8,
    inputs: []const []const u8,
    /// Null keeps all prepared artifacts; explicit labels narrow reviewed cohorts.
    artifacts: ?[]const []const u8 = null,
    cacheable: bool,
    reason: []const u8,
};
const Entry = struct { group: Group, steps: std.ArrayList(*std.Build.Step) = .empty };
/// Configuration controls that forbid turning partial/rerun requests into reuse.
pub const Controls = struct { filtered: bool = false, rerun: bool = false, optimize: []const u8 };
const InputList = struct { name: []const u8, inputs: []const []const u8 };
const Coverage = struct { required_actions: usize, registered_actions: usize, unknown_actions: []const []const u8 };
const Inventory = struct {
    version: u32 = 1,
    required_targets: []const []const u8 = &.{ "test", "fmt-check" },
    groups: []const Group,
    input_lists: []const InputList,
    configuration: Controls,
    coverage: Coverage,
};

/// Build-local registry. Its allocations have the configure graph's lifetime.
pub const Registry = struct {
    build: *std.Build,
    entries: std.ArrayList(Entry) = .empty,
    infrastructure: std.ArrayList(*std.Build.Step) = .empty,
    controls: Controls,

    /// Associate an original gate step with a named cohort and exact input recipes.
    pub fn register(self: *Registry, id: []const u8, step: *std.Build.Step, recipes: []const []const u8, cacheable: bool, reason: []const u8) void {
        for (self.entries.items) |*entry| if (std.mem.eql(u8, entry.group.id, id)) {
            if (!sameRecipes(entry.group.inputs, recipes)) @panic("verification cohort has inconsistent input recipes");
            entry.group.cacheable = entry.group.cacheable and cacheable;
            if (!cacheable) entry.group.reason = reason;
            entry.steps.append(self.build.allocator, step) catch @panic("verification allocation");
            return;
        };
        const target = self.build.fmt("verification-{s}", .{id});
        var entry: Entry = .{ .group = .{ .id = id, .target = target, .label = step.name, .inputs = recipes, .cacheable = cacheable, .reason = reason } };
        entry.steps.append(self.build.allocator, step) catch @panic("verification allocation");
        self.entries.append(self.build.allocator, entry) catch @panic("verification allocation");
    }

    /// Register a previously declared cached test-input list as one cohort.
    pub fn declared(self: *Registry, step: *std.Build.Step, list: []const u8) void {
        inline for (comptime std.meta.declarations(test_inputs)) |name| {
            if (std.mem.eql(u8, list, name)) {
                const seed = requiresQualifiedSeed(name);
                self.register(name, step, &@field(test_inputs, name), !seed, if (seed)
                    "external qualified seed receipt must be verified before reuse"
                else
                    "complete declared whole-action inputs");
                return;
            }
        }
        @panic("verification action has no declared input list");
    }

    /// Opt a reviewed whole cohort into exact prepared artifact dependencies.
    pub fn artifactDependencies(self: *Registry, id: []const u8, labels: []const []const u8) void {
        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.group.id, id)) {
                entry.group.artifacts = labels;
                return;
            }
        }
        @panic("verification artifact dependencies name an unregistered cohort");
    }

    /// Export only original test/fmt dependencies and preserve unknown checks.
    pub fn exportPlan(self: *Registry, roots: []const *std.Build.Step, preparation: []const *std.Build.Step) void {
        const a = self.build.allocator;
        const reachable = closure(a, roots);
        var prepared = closure(a, preparation);
        var infrastructure = closure(a, self.infrastructure.items).keyIterator();
        while (infrastructure.next()) |pointer| prepared.put(a, pointer.*, {}) catch @panic("verification allocation");
        var covered: std.AutoHashMapUnmanaged(*std.Build.Step, void) = .empty;
        var groups: std.ArrayList(Group) = .empty;
        for (self.entries.items) |entry| self.exportGroup(entry, reachable, &covered, &groups);
        var unknown: std.ArrayList([]const u8) = .empty;
        var required: usize = 0;
        var steps = reachable.keyIterator();
        while (steps.next()) |pointer| {
            const step = pointer.*;
            if (!isAction(step, prepared)) continue;
            required += 1;
            if (!covered.contains(step)) unknown.append(a, step.name) catch @panic("verification allocation");
        }
        if (unknown.items.len > 0) {
            const fallback = self.build.step("verification-unclassified", "Run original gates for unclassified required actions");
            for (roots) |root| fallback.dependOn(root);
            groups.append(a, .{
                .id = "unclassified",
                .target = "verification-unclassified",
                .label = "Unclassified original gate actions",
                .inputs = &.{},
                .cacheable = false,
                .reason = "unknown actions require original complete gate execution",
            }) catch @panic("verification allocation");
        }
        const inventory: Inventory = .{
            .groups = groups.items,
            .input_lists = inputLists(a),
            .configuration = self.controls,
            .coverage = .{ .required_actions = required, .registered_actions = required - unknown.items.len, .unknown_actions = unknown.items },
        };
        const bytes = std.json.Stringify.valueAlloc(a, inventory, .{ .whitespace = .indent_2 }) catch @panic("verification serialization");
        const written = self.build.addWriteFiles().add("verification-inventory.json", bytes);
        const install = self.build.addInstallFileWithDir(written, .{ .custom = "verification" }, "inventory.json");
        self.build.step("verification-plan", "Export authoritative test and format action inventory without executing gates").dependOn(&install.step);
    }

    fn exportGroup(self: *Registry, entry: Entry, reachable: std.AutoHashMapUnmanaged(*std.Build.Step, void), covered: *std.AutoHashMapUnmanaged(*std.Build.Step, void), groups: *std.ArrayList(Group)) void {
        var target: ?*std.Build.Step = null;
        for (entry.steps.items) |step| {
            if (!reachable.contains(step)) continue;
            if (target == null) target = self.build.step(entry.group.target, entry.group.label);
            target.?.dependOn(step);
            covered.put(self.build.allocator, step, {}) catch @panic("verification allocation");
        }
        if (target == null) return;
        var group = entry.group;
        if (self.controls.filtered or self.controls.rerun) {
            group.cacheable = false;
            group.reason = "filtered and explicit rerun requests require execution";
        }
        groups.append(self.build.allocator, group) catch @panic("verification allocation");
    }
};

fn requiresQualifiedSeed(list: []const u8) bool {
    for ([_][]const u8{ "pilot_lexer", "pilot_parser", "pilot_probes", "frontend_qualification", "declaration_qualification", "type_interface_qualification", "body_check_qualification", "body_library_admission", "body_entry_admission" }) |lane| {
        if (std.mem.eql(u8, list, lane)) return true;
    }
    return false;
}

test "qualified pilot seed checks stay fresh across action receipt reuse" {
    try std.testing.expect(requiresQualifiedSeed("pilot_lexer"));
    try std.testing.expect(requiresQualifiedSeed("pilot_parser"));
    try std.testing.expect(requiresQualifiedSeed("pilot_probes"));
    try std.testing.expect(requiresQualifiedSeed("frontend_qualification"));
    try std.testing.expect(requiresQualifiedSeed("declaration_qualification"));
    try std.testing.expect(requiresQualifiedSeed("type_interface_qualification"));
    try std.testing.expect(requiresQualifiedSeed("body_check_qualification"));
    try std.testing.expect(requiresQualifiedSeed("body_library_admission"));
    try std.testing.expect(requiresQualifiedSeed("body_entry_admission"));
    try std.testing.expect(!requiresQualifiedSeed("pilot_registration"));
    try std.testing.expect(!requiresQualifiedSeed("unit"));
}

fn sameRecipes(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.mem.eql(u8, a, b)) return false;
    return true;
}

/// A native executable the coordinator must identify before replaying its actions.
pub const Artifact = struct { label: []const u8, binary: *std.Build.Step.Compile };

/// Explicit developer preparation; the normal install graph runs no Python.
/// Return only explicitly identified artifact/output roots for coverage exclusion.
pub fn prepare(b: *std.Build, artifacts: []const Artifact, known_outputs: []const *std.Build.Step) []const *std.Build.Step {
    const target = b.step("verification-prepare", "Prepare exact native verification executables and installed components");
    target.dependOn(b.getInstallStep());
    var identified: std.ArrayList(*std.Build.Step) = .empty;
    identified.appendSlice(b.allocator, known_outputs) catch @panic("verification allocation");
    const run = b.addSystemCommand(&.{"python3"});
    run.addFileArg(b.path("scripts/verification_artifacts.py"));
    run.setCwd(b.path("."));
    const paths = run.addOutputFileArg("artifacts.json");
    for (artifacts) |artifact| {
        identified.append(b.allocator, &artifact.binary.step) catch @panic("verification allocation");
        run.addArg(artifact.label);
        run.addFileArg(artifact.binary.getEmittedBin());
        const installed = b.addInstallFileWithDir(artifact.binary.getEmittedBin(), .{ .custom = "verification" }, b.fmt("bin/{s}", .{artifact.label}));
        target.dependOn(&installed.step);
    }
    const installed_paths = b.addInstallFileWithDir(paths, .{ .custom = "verification" }, "artifacts.json");
    target.dependOn(&installed_paths.step);
    return identified.items;
}

fn closure(a: std.mem.Allocator, roots: []const *std.Build.Step) std.AutoHashMapUnmanaged(*std.Build.Step, void) {
    var seen: std.AutoHashMapUnmanaged(*std.Build.Step, void) = .empty;
    var pending: std.ArrayList(*std.Build.Step) = .empty;
    defer pending.deinit(a);
    pending.appendSlice(a, roots) catch @panic("verification allocation");
    while (pending.pop()) |step| {
        if ((seen.getOrPut(a, step) catch @panic("verification allocation")).found_existing) continue;
        pending.appendSlice(a, step.dependencies.items) catch @panic("verification allocation");
    }
    return seen;
}

fn isAction(step: *std.Build.Step, prepared: std.AutoHashMapUnmanaged(*std.Build.Step, void)) bool {
    return switch (step.tag) {
        .run, .fmt, .check_file, .fail => true,
        .top_level => false,
        else => !prepared.contains(step),
    };
}

fn inputLists(a: std.mem.Allocator) []const InputList {
    var lists: std.ArrayList(InputList) = .empty;
    inline for (comptime std.meta.declarations(test_inputs)) |name| {
        lists.append(a, .{ .name = name, .inputs = &@field(test_inputs, name) }) catch @panic("verification allocation");
    }
    return lists.toOwnedSlice(a) catch @panic("verification allocation");
}

/// Register recognized Guardian and compiler-identity preparations conservatively.
pub fn registerInfrastructure(registry: *Registry, roots: []const *std.Build.Step) void {
    var reachable = closure(registry.build.allocator, roots);
    var steps = reachable.keyIterator();
    while (steps.next()) |pointer| {
        const run = pointer.*.cast(std.Build.Step.Run) orelse continue;
        if (run.argv.items.len == 0) continue;
        const name = switch (run.argv.items[0]) {
            .artifact => |artifact| artifact.artifact.name,
            .bytes => |bytes| std.fs.path.basename(bytes),
            else => continue,
        };
        if (std.mem.eql(u8, name, "guardian-check")) {
            registry.register("guardian", &run.step, &.{}, false, "Guardian source, git scope and mutable policy validation require freshness");
            switch (run.argv.items[0]) {
                .artifact => |artifact| registry.infrastructure.append(registry.build.allocator, &artifact.artifact.step) catch @panic("verification allocation"),
                else => {},
            }
        } else if (std.mem.eql(u8, name, "build-identity")) {
            registry.register("identity-preparation", &run.step, &.{}, false, "generated compiler identity must be prepared and validated");
        }
    }
}

fn fixtureStep(tag: std.Build.Step.Tag) std.Build.Step {
    return .{
        .tag = tag,
        .name = "coverage fixture",
        .owner = undefined,
        .dependencies = .empty,
        .max_rss = 0,
        .debug_stack_trace = undefined,
    };
}

test "a new compile-only gate appended to install requires original-gate fallback" {
    const a = std.testing.allocator;
    var install = fixtureStep(.top_level);
    defer install.dependencies.deinit(a);
    var identified = fixtureStep(.compile);
    var added_check = fixtureStep(.compile);
    try install.dependencies.appendSlice(a, &.{ &identified, &added_check });
    var reachable = closure(a, &.{&install});
    defer reachable.deinit(a);
    var prepared = closure(a, &.{&identified});
    defer prepared.deinit(a);
    try std.testing.expect(reachable.contains(&added_check));
    try std.testing.expect(!isAction(&identified, prepared));
    try std.testing.expect(isAction(&added_check, prepared));
    try std.testing.expect(!isAction(&install, prepared));
}
