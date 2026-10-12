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
const Member = struct { label: []const u8, original_label: []const u8, kind: []const u8 };
const ActionMetadata = struct { id: []const u8, steps: []const Member, identity_scope: []const u8 = "group-local-v1" };
const Entry = struct { group: Group, steps: std.ArrayList(*std.Build.Step) = .empty, members: std.ArrayList(Member) = .empty };
/// Configuration controls that forbid turning partial/rerun requests into reuse.
pub const Controls = struct { filtered: bool = false, rerun: bool = false, optimize: []const u8 };
const InputList = struct { name: []const u8, inputs: []const []const u8 };
const Coverage = struct { required_actions: usize, registered_actions: usize, unknown_actions: []const []const u8 };
const Inventory = struct {
    version: u32 = 2,
    required_targets: []const []const u8 = &.{ "test", "fmt-check" },
    groups: []const Group,
    input_lists: []const InputList,
    configuration: Controls,
    coverage: Coverage,
    action_metadata: []const ActionMetadata,
};

/// Build-local registry. Its allocations have the configure graph's lifetime.
pub const Registry = struct {
    build: *std.Build,
    entries: std.ArrayList(Entry) = .empty,
    infrastructure: std.ArrayList(*std.Build.Step) = .empty,
    controls: Controls,

    /// Associate an original gate step with a named cohort and exact input recipes.
    pub fn register(self: *Registry, id: []const u8, step: *std.Build.Step, recipes: []const []const u8, cacheable: bool, reason: []const u8) void {
        for (self.entries.items) |*entry| {
            for (entry.steps.items) |existing| {
                if (existing != step) continue;
                if (!std.mem.eql(u8, entry.group.id, id)) @panic("verification action belongs to multiple cohorts");
                if (!sameRecipes(entry.group.inputs, recipes)) @panic("verification cohort has inconsistent input recipes");
                entry.group.cacheable = entry.group.cacheable and cacheable;
                if (!cacheable) entry.group.reason = reason;
                return; // An explicit freshness refinement retains one member.
            }
        }
        for (self.entries.items) |*entry| if (std.mem.eql(u8, entry.group.id, id)) {
            if (!sameRecipes(entry.group.inputs, recipes)) @panic("verification cohort has inconsistent input recipes");
            entry.group.cacheable = entry.group.cacheable and cacheable;
            if (!cacheable) entry.group.reason = reason;
            self.addMember(entry, step);
            return;
        };
        const target = self.build.fmt("verification-{s}", .{id});
        var entry: Entry = .{ .group = .{ .id = id, .target = target, .label = step.name, .inputs = recipes, .cacheable = cacheable, .reason = reason } };
        self.addMember(&entry, step);
        self.entries.append(self.build.allocator, entry) catch @panic("verification allocation");
    }

    fn addMember(self: *Registry, entry: *Entry, step: *std.Build.Step) void {
        const original = step.name;
        const label = self.build.fmt("verification action {s} member {d}", .{ entry.group.id, entry.steps.items.len });
        entry.steps.append(self.build.allocator, step) catch @panic("verification allocation");
        entry.members.append(self.build.allocator, .{ .label = label, .original_label = original, .kind = @tagName(step.tag) }) catch @panic("verification allocation");
    }

    /// Register a previously declared cached test-input list as one cohort.
    pub fn declared(self: *Registry, step: *std.Build.Step, list: []const u8) void {
        inline for (comptime std.meta.declarations(test_inputs)) |name| {
            if (std.mem.eql(u8, list, name)) {
                self.register(name, step, &@field(test_inputs, name), true, "complete declared whole-action inputs");
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
        var metadata: std.ArrayList(ActionMetadata) = .empty;
        for (self.entries.items) |entry| {
            self.exportGroup(entry, reachable, &covered, &groups);
            var members: std.ArrayList(Member) = .empty;
            for (entry.steps.items, entry.members.items) |step, registered_member| {
                if (!reachable.contains(step)) continue;
                var member = registered_member;
                member.original_label = step.name;
                member.label = self.build.fmt("verification action {s} member {d}", .{ entry.group.id, members.items.len });
                self.observeNative(step, entry.group.id, members.items.len);
                step.name = member.label;
                members.append(a, member) catch @panic("verification allocation");
            }
            if (members.items.len > 0) metadata.append(a, .{ .id = entry.group.id, .steps = members.items }) catch @panic("verification allocation");
        }
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
        if (unknown.items.len > 0) metadata.append(a, .{ .id = "unclassified", .steps = &.{} }) catch @panic("verification allocation");
        const inventory: Inventory = .{
            .groups = groups.items,
            .action_metadata = metadata.items,
            .input_lists = inputLists(a),
            .configuration = self.controls,
            .coverage = .{ .required_actions = required, .registered_actions = required - unknown.items.len, .unknown_actions = unknown.items },
        };
        const bytes = std.json.Stringify.valueAlloc(a, inventory, .{ .whitespace = .indent_2 }) catch @panic("verification serialization");
        const written = self.build.addWriteFiles().add("verification-inventory.json", bytes);
        const install = self.build.addInstallFileWithDir(written, .{ .custom = "verification" }, "inventory.json");
        self.build.step("verification-plan", "Export authoritative test and format action inventory without executing gates").dependOn(&install.step);
    }

    fn observeNative(self: *Registry, step: *std.Build.Step, id: []const u8, member: usize) void {
        const run = step.cast(std.Build.Step.Run) orelse return;
        if (!run.test_runner_mode) return;
        const producer = run.producer orelse return;
        const root = producer.root_module.root_source_file orelse return;
        const b = self.build;
        const prefix = [_][]const u8{
            "python3",  "scripts/verification_native_telemetry.py", "--action-id", id,
            "--member", b.fmt("{d}", .{member}),                    "--root-id",   b.fmt("{f}", .{root}),
            "--",
        };
        const args = b.graph.arena.alloc(std.Build.Step.Run.Arg, prefix.len) catch @panic("verification allocation");
        for (args, prefix) |*arg, word| arg.* = .{ .bytes = b.graph.dupeString(word) };
        run.argv.insertSlice(b.graph.arena, 0, args) catch @panic("verification allocation");
        run.addFileInput(b.path("scripts/verification_native_telemetry.py"));
        run.addFileInput(b.path("scripts/verification_telemetry.py"));
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

fn sameRecipes(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.mem.eql(u8, a, b)) return false;
    return true;
}

/// A native executable the coordinator must identify before replaying its actions.
pub const Artifact = struct { label: []const u8, binary: *std.Build.Step.Compile };

/// One artifact's producer in `artifacts.json` version 3: root-relative
/// recipes (`dir/`, `base/**/*SUFFIX`, `base/*SUFFIX` or an exact path) that
/// bound every compile-time input of the binary, and the settings, toolchain
/// and test runner that turn them into bytes. The coordinator identifies the
/// artifact by the content the recipes select instead of by its bytes, which
/// embed the tree's path in their debug information.
const Producer = struct { recipes: []const []const u8, optimize: []const u8, zig_version: []const u8, test_runner: TestRunner };
/// What links the artifact's test runner. A Zig test root links Guardian's
/// runner from the `guardian` path dependency (`build.zig.zon`), whose sources
/// the root's recipes select; an executable links none. Relative, so two
/// worktrees agree.
const TestRunner = struct { kind: []const u8, dependency: ?[]const u8 = null, location: ?[]const u8 = null, runner: ?[]const u8 = null };
const LabeledProducer = struct { label: []const u8, producer: Producer };
/// The build scripts and configuration every artifact's build reads.
const build_files = [_][]const u8{ "./*.zig", "build.zig.zon", ".zigversion", "guardian.toml" };
/// The Guardian sources a test root's runner and diagnostics compile from.
const guardian_sources = [_][]const u8{ "../guardian-zig/build.zig", "../guardian-zig/build.zig.zon", "../guardian-zig/src/" };
const guardian_runner: TestRunner = .{ .kind = "guardian", .dependency = "guardian", .location = "../guardian-zig", .runner = "src/test_runner.zig" };

/// The compile-time input recipes of one prepared artifact besides the build
/// files and the test runner's sources. A label without recipes is a
/// configuration error: a new artifact must say what it is built from.
fn sourcesFor(b: *std.Build, label: []const u8) []const []const u8 {
    const user_docs = @import("src/user_docs.zig");
    var docs: [user_docs.topics.len][]const u8 = undefined;
    for (&docs, user_docs.topics) |*path, topic| path.* = topic.path;
    // The compiler and the unit root embed the user guides `src/user_docs.zig` names.
    if (std.mem.eql(u8, label, "mylang")) return concat(b, &.{ &.{"src/"}, &docs });
    if (std.mem.eql(u8, label, "units")) return concat(b, &.{ &.{ "src/", "test/fixtures/environment-identity/" }, &docs });
    if (std.mem.eql(u8, label, "core")) return &.{"src/"};
    if (std.mem.eql(u8, label, "cli") or std.mem.eql(u8, label, "golden")) return &.{ "test/", "src/core/test_paths.zig" };
    if (std.mem.eql(u8, label, "tooling-units")) return compiled(b, &test_inputs.tooling_unit);
    if (std.mem.eql(u8, label, "text-scalar-units")) return compiled(b, &test_inputs.text_scalar_unit);
    if (std.mem.eql(u8, label, "memory-budget")) return &.{"src/memory_budget.zig"};
    if (std.mem.eql(u8, label, "component-support")) return &.{"selfhost/"};
    if (std.mem.eql(u8, label, "component-builder")) return &.{"selfhost/*.zig"};
    std.debug.panic("verification artifact {s} has no producer recipe", .{label});
}

/// The entries of a declared test-input list the root compiles: its `src/`
/// files, without the scripts and environment contract its run reads.
fn compiled(b: *std.Build, list: []const []const u8) []const []const u8 {
    var kept: std.ArrayList([]const u8) = .empty;
    for (list) |entry| {
        if (!std.mem.startsWith(u8, entry, "src/")) continue;
        if (listed(entry, &test_inputs.environment_contract)) continue;
        kept.append(b.allocator, entry) catch @panic("verification allocation");
    }
    return kept.items;
}

fn listed(entry: []const u8, list: []const []const u8) bool {
    for (list) |item| if (std.mem.eql(u8, item, entry)) return true;
    return false;
}

fn concat(b: *std.Build, parts: []const []const []const u8) []const []const u8 {
    return std.mem.concat(b.allocator, []const u8, parts) catch @panic("verification allocation");
}

/// The `artifact_producers` file `scripts/verification_artifacts.py` merges into
/// `artifacts.json`: each artifact's recipes, optimize mode, Zig version and,
/// for a test root, its test runner.
fn producers(b: *std.Build, artifacts: []const Artifact) std.Build.LazyPath {
    const entries = b.allocator.alloc(LabeledProducer, artifacts.len) catch @panic("verification allocation");
    for (entries, artifacts) |*entry, artifact| {
        const tested = artifact.binary.kind == .@"test";
        entry.* = .{ .label = artifact.label, .producer = .{
            .recipes = concat(b, &.{ &build_files, sourcesFor(b, artifact.label), if (tested) &guardian_sources else &.{} }),
            .optimize = @tagName(artifact.binary.root_module.optimize.?),
            .zig_version = @import("builtin").zig_version_string,
            .test_runner = if (tested) guardian_runner else .{ .kind = "none" },
        } };
    }
    const bytes = std.json.Stringify.valueAlloc(b.allocator, entries, .{ .whitespace = .indent_2, .emit_null_optional_fields = false }) catch @panic("verification serialization");
    return b.addWriteFiles().add("artifact-producers.json", bytes);
}

/// Explicit developer preparation; the normal install graph runs no Python.
/// Return only explicitly identified artifact/output roots for coverage exclusion.
pub fn prepare(b: *std.Build, artifacts: []const Artifact, known_outputs: []const *std.Build.Step) []const *std.Build.Step {
    const target = b.step("verification-prepare", "Prepare exact native verification executables and installed components");
    target.dependOn(b.getInstallStep());
    var identified: std.ArrayList(*std.Build.Step) = .empty;
    identified.appendSlice(b.allocator, known_outputs) catch @panic("verification allocation");
    const run = b.addSystemCommand(&.{"python3"});
    run.addFileArg(b.path("scripts/verification_artifacts.py"));
    run.addFileInput(b.path("scripts/verification_producers.py"));
    run.addFileInput(b.path("scripts/verification_snapshot.py"));
    run.addFileInput(b.path("scripts/verification_code_identity.py"));
    run.setCwd(b.path("."));
    const paths = run.addOutputFileArg("artifacts.json");
    run.addArg("--producers");
    run.addFileArg(producers(b, artifacts));
    for (artifacts) |artifact| {
        if (std.mem.eql(u8, artifact.label, "tooling-units") or std.mem.eql(u8, artifact.label, "text-scalar-units")) {
            run.addArgs(&.{ "--qualify", artifact.label, @tagName(artifact.binary.root_module.optimize.?) });
            const inputs: []const []const u8 = if (std.mem.eql(u8, artifact.label, "tooling-units")) &test_inputs.tooling_unit else &test_inputs.text_scalar_unit;
            for (inputs) |input| run.addFileInput(b.path(input));
        }
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

test "same-cohort freshness refinement retains one original member" {
    var step = fixtureStep(.run);
    var pointers = [_]*std.Build.Step{&step};
    var members = [_]Member{.{ .label = "verification action juice member 0", .original_label = "run test", .kind = "run" }};
    var entries = [_]Entry{.{
        .group = .{ .id = "juice", .target = "verification-juice", .label = "run test", .inputs = &.{"src/"}, .cacheable = true, .reason = "declared" },
        .steps = .{ .items = &pointers, .capacity = 1 },
        .members = .{ .items = &members, .capacity = 1 },
    }};
    var registry: Registry = .{ .build = undefined, .entries = .{ .items = &entries, .capacity = 1 }, .controls = .{ .optimize = "Debug" } };
    registry.register("juice", &step, &.{"src/"}, false, "requires freshness");
    registry.register("juice", &step, &.{"src/"}, true, "declared again");
    try std.testing.expectEqual(@as(usize, 1), registry.entries.items.len);
    try std.testing.expectEqual(@as(usize, 1), registry.entries.items[0].steps.items.len);
    try std.testing.expectEqual(@as(usize, 1), registry.entries.items[0].members.items.len);
    try std.testing.expect(!registry.entries.items[0].group.cacheable);
    try std.testing.expectEqualStrings("requires freshness", registry.entries.items[0].group.reason);
}
