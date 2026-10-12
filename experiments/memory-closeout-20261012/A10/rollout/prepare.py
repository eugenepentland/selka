from pathlib import Path
import difflib, hashlib, json, subprocess
root=Path.cwd()
evidence=root/'experiments/memory-closeout-20261012/A10/rollout'
scratch=root/'.tmp/memory-closeout/A10/rollout-draft'
base={}
def get(path):
    if path not in base: base[path]=(root/path).read_text()
    return base[path]
def replace(s,old,new,count=1):
    actual=s.count(old)
    if actual!=count: raise ValueError((old[:90],actual,count))
    return s.replace(old,new)
def patch(before,after,name):
    result=''
    for path in sorted(after):
        if before[path]!=after[path]:
            result+=f'diff --git a/{path} b/{path}\n'
            result+=''.join(difflib.unified_diff(before[path].splitlines(True),after[path].splitlines(True),fromfile='a/'+path,tofile='b/'+path))
    (evidence/name).write_text(result)
    return sorted(path for path in after if before[path]!=after[path])
files=['src/core/pipeline.zig','src/core/check_command.zig','src/core/main.zig','src/main.zig','src/core/cli.zig','src/core/cli_args.zig','src/core/test_runner_directory.zig','src/doctest_command.zig','src/core/cost_command.zig']
for file in files: get(file)
c2=dict(base)
for path,n in [('src/core/pipeline.zig',1),('src/core/check_command.zig',1)]:
    c2[path]=replace(c2[path],'single_owner: bool = false,','single_owner: bool = true,',n)
    c2[path]=replace(c2[path],'zero_rc: bool = false,','zero_rc: bool = true,',n)
c2['src/main.zig']=replace(c2['src/main.zig'],'''    var parser: ArgumentParser = .{ .command = command, .allocator = allocator };''','''    const checked_ownership = switch (command) {
        .check, .@"check-project", .@"check-module", .@"check-session", .lint => true,
        else => false,
    };
    var parser: ArgumentParser = .{ .command = command, .allocator = allocator, .single_owner = checked_ownership, .zero_rc = checked_ownership };''')
c2['src/core/pipeline.zig']=replace(c2['src/core/pipeline.zig'],'/// Compilation choices controlling experimental semantics and generated code.','/// Compilation choices controlling checked ownership and generated code.')
c2['src/core/pipeline.zig']=replace(c2['src/core/pipeline.zig'],'/// Validate the experimental single-owner source contract before code generation.','/// Validate checked source ownership before code generation.')
c2['src/core/main.zig']=replace(c2['src/core/main.zig'],'var single_owner = false;','var single_owner = true;')
c2['src/core/main.zig']=replace(c2['src/core/main.zig'],'var zero_rc = false;','var zero_rc = true;')
c2['src/core/main.zig']=replace(c2['src/core/main.zig'],'    \\\\Experimental: --experimental-single-owner or --experimental-zero-rc on build, run, check and dump-ir.\n    \\\\              --experimental-zero-rc also applies to test.','    \\\\Checked ownership is the default: assignments move, parameters borrow, and .copy() duplicates storage.')
c2['src/core/main.zig']=replace(c2['src/core/main.zig'],'    \\\\  --experimental-zero-rc                checked moves and borrows, direct destruction\n','')
c2['src/core/cli.zig']=replace(c2['src/core/cli.zig'],'one-count reference counting is the only memory model','checked ownership is the default memory model')
c2['src/core/cli.zig']=replace(c2['src/core/cli.zig'],'    \\\\       [--experimental-single-owner]    prototype: lists move; calls borrow; .copy() duplicates\n    \\\\                                        .snapshot() opts a list family into copy-on-write\n    \\\\       [--experimental-zero-rc]         prototype: strings/bytes also move; no sharing or RC','    \\\\Checked ownership is the default: assignments move, parameters borrow, and .copy() duplicates storage.')
c2files=patch(base,c2,'C2-default.patch')
c3=dict(c2)
# Refuse selectors at both public dispatch boundaries, including early profiling check.
p='src/core/main.zig'
c3[p]=replace(c3[p],'const zero_rc_flag = @import("mylang").zero_rc_flag;\n','')
c3[p]=replace(c3[p],'const single_owner_flag = "--experimental-single-owner";\n','')
needle='/// Dispatch one command; the process exit status is its result.\n'
helper='''/// A retired ownership selector before the guest argument separator.
pub fn retiredOwnershipFlag(args: []const []const u8) ?[]const u8 {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--")) return null;
        const name = arg[0 .. std.mem.indexOfScalar(u8, arg, '=') orelse arg.len];
        if (std.mem.eql(u8, name, "--experimental-single-owner") or std.mem.eql(u8, name, "--experimental-zero-rc")) return name;
    }
    return null;
}

/// The command-line explanation for retired ownership selectors.
pub const ownership_retired = "{s} was retired; checked ownership is the default; drop the flag";

// spec-case: NEW-CORE-ZERO-RC-TEST-1
test "retired ownership selectors preserve guest arguments after separator" {
    try std.testing.expectEqualStrings("--experimental-zero-rc", retiredOwnershipFlag(&.{"--experimental-zero-rc"}).?);
    try std.testing.expectEqualStrings("--experimental-single-owner", retiredOwnershipFlag(&.{"--experimental-single-owner=true"}).?);
    try std.testing.expect(retiredOwnershipFlag(&.{ "--", "--experimental-zero-rc" }) == null);
}

'''
c3[p]=replace(c3[p],needle,helper+needle)
c3[p]=replace(c3[p],'    const args = try init.minimal.args.toSlice(allocator);\n','    const args = try init.minimal.args.toSlice(allocator);\n    if (args.len >= 2) if (retiredOwnershipFlag(args[2..])) |flag| {\n        const message = try std.fmt.allocPrint(allocator, "mylang: " ++ ownership_retired ++ "\\n", .{flag});\n        try std.Io.File.stderr().writeStreamingAll(init.io, message);\n        return 2;\n    };\n')
c3[p]=replace(c3[p],'        var single_owner = true;\n        var zero_rc = true;\n','')
c3[p]=replace(c3[p],'            } else if (std.mem.eql(u8, arg, single_owner_flag)) {\n                single_owner = true;\n            } else if (std.mem.eql(u8, arg, zero_rc_flag)) {\n                single_owner = true;\n                zero_rc = true;\n','')
c3[p]=replace(c3[p],'return dumpIr(init, args[2], with_facts, single_owner, zero_rc);','return dumpIr(init, args[2], with_facts, true, true);')
c3[p]=replace(c3[p],'        } else if (std.mem.eql(u8, arg, single_owner_flag)) {\n            options.show.codegen.single_owner = true;\n        } else if (std.mem.eql(u8, arg, zero_rc_flag)) {\n            options.show.codegen.single_owner = true;\n            options.show.codegen.zero_rc = true;\n','')
c3[p]=replace(c3[p],'    } else if (std.mem.eql(u8, arg, zero_rc_flag)) {\n        options.build.show.codegen.single_owner = true;\n        options.build.show.codegen.zero_rc = true;\n','')
p='src/core/cli.zig'
c3[p]=replace(c3[p],'    const command = args[1];\n','    const command = args[1];\n    if (core_main.retiredOwnershipFlag(args[2..])) |flag| {\n        return try refuse(init, command, try std.fmt.allocPrint(init.arena.allocator(), core_main.ownership_retired, .{flag}));\n    }\n')
p='src/core/cli_args.zig'
c3[p]=replace(c3[p],'        } else if (eql(arg, "--experimental-single-owner")) {\n            build.show.codegen.single_owner = true;\n        } else if (eql(arg, "--experimental-zero-rc")) {\n            build.show.codegen.single_owner = true;\n            build.show.codegen.zero_rc = true;\n','')
p='src/core/check_command.zig'
c3[p]=replace(c3[p],'        } else if (std.mem.eql(u8, arg, "--experimental-single-owner")) {\n            options.single_owner = true;\n        } else if (std.mem.eql(u8, arg, "--experimental-zero-rc")) {\n            options.single_owner = true;\n            options.zero_rc = true;\n','')
p='src/main.zig'
c3[p]=replace(c3[p],'''        if (std.mem.eql(u8, arg, "--experimental-single-owner") or std.mem.eql(u8, arg, "--experimental-zero-rc")) {
            switch (command) {
                .check, .@"check-project", .@"check-module", .@"check-session", .lint => {},
                else => return error.Usage,
            }
            parser.single_owner = true;
            parser.zero_rc = parser.zero_rc or std.mem.eql(u8, arg, "--experimental-zero-rc");
            continue;
        }
''','')
p='src/core/cost_command.zig'
c3[p]=replace(c3[p],'const zero_rc_flag = @import("mylang").zero_rc_flag;\n','')
c3[p]=replace(c3[p],' or std.mem.eql(u8, arg, zero_rc_flag)','')
c3[p]=replace(c3[p],'            } else if (std.mem.eql(u8, args[index], zero_rc_flag)) {\n                options.codegen.single_owner = true;\n                options.codegen.zero_rc = true;\n','')
c3[p]=replace(c3[p],'const arguments = [_][]const u8{ "cost.my", zero_rc_flag };','const arguments = [_][]const u8{"cost.my"};')
p='src/core/test_runner_directory.zig'
c3[p]=replace(c3[p],'    if (opts.build.show.codegen.zero_rc) try arguments.append(a, "--experimental-zero-rc");\n','')
c3[p]=replace(c3[p],'test "zero RC directory children preserve the requested ownership ABI"','test "zero RC directory children inherit checked ownership without a selector"')
start=c3[p].index('test "zero RC directory children inherit')
end=c3[p].index('\nfn argumentCount(',start)
part=c3[p][start:end]
part=replace(part,'var fanout: Fanout','const fanout: Fanout')
part=replace(part,'''    fanout.controls.build.show.codegen.single_owner = true;
    fanout.controls.build.show.codegen.zero_rc = true;
    const owned = try argv(a, fanout, "suite/main.my");
    try std.testing.expectEqual(@as(usize, 1), argumentCount(owned, "--experimental-zero-rc"));''','''    try std.testing.expect(fanout.controls.build.show.codegen.single_owner);
    try std.testing.expect(fanout.controls.build.show.codegen.zero_rc);''')
c3[p]=c3[p][:start]+part+c3[p][end:]
p='src/doctest_command.zig'
c3[p]=replace(c3[p],'const zero_rc_flag = @import("compiler_root").compiler_language.zero_rc_flag;\n','')
c3[p]=replace(c3[p],'    zero_rc: bool = false,\n','',2)
c3[p]=replace(c3[p],'        } else if (std.mem.eql(u8, arg, zero_rc_flag)) {\n            options.zero_rc = true;\n','')
c3[p]=replace(c3[p],'        .zero_rc = options.zero_rc,\n','')
c3[p]=replace(c3[p],'options: []const []const u8, zero_rc: bool','options: []const []const u8')
c3[p]=replace(c3[p],'    if (zero_rc) try kept.append(allocator, zero_rc_flag);\n','')
c3[p]=replace(c3[p],'session.fixtures), session.zero_rc);','session.fixtures));')
c3[p]=replace(c3[p],'''test "zero RC doctest preserves ownership selection through command options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const options = try parseOptions(&.{ zero_rc_flag, "--jobs", "2" });
    try std.testing.expect(options.zero_rc);
    const forwarded = try invokedOptions(arena.allocator(), &.{"--value-semantics"}, options.zero_rc);
    try std.testing.expectEqual(@as(usize, 1), forwarded.len);
    try std.testing.expectEqualStrings(zero_rc_flag, forwarded[0]);
}''','''test "zero RC doctest inherits the ordinary checked command contract" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.Usage, parseOptions(&.{"--experimental-zero-rc"}));
    const forwarded = try invokedOptions(arena.allocator(), &.{"--value-semantics"});
    try std.testing.expectEqual(@as(usize, 0), forwarded.len);
}''')
p='src/core/main.zig'
c3[p]=replace(c3[p],'''    var codegen: pipeline.Codegen = .{};
    var paths: usize = 0;
    for (arguments) |arg| {
        if (std.mem.eql(u8, arg, zero_rc_flag)) {
            codegen.single_owner = true;
            codegen.zero_rc = true;
        } else if (std.mem.eql(u8, arg, single_owner_flag)) {
            codegen.single_owner = true;
        } else if (std.mem.startsWith(u8, arg, "--")) return 2 else paths += 1;
    }
    if (paths == 0) return 2;''','''    const codegen: pipeline.Codegen = .{};
    if (arguments.len == 0) return 2;
    for (arguments) |arg| if (std.mem.startsWith(u8, arg, "--")) return 2;''')
c3files=patch(c2,c3,'C3-cli-selector-retirement.patch')
for stage,mapping in [('base',base),('C2',c2),('C3',c3)]:
    for path,contents in mapping.items():
        dest=scratch/stage/path
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_text(contents)
(evidence/'draft-identities.json').write_text(json.dumps({'status':'UNAPPLIED; no default/retirement qualification claimed','source_revision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'source_files':{path:hashlib.sha256(contents.encode()).hexdigest() for path,contents in base.items()},'C2_files':c2files,'C3_files':c3files,'patch_hashes':{name:hashlib.sha256((evidence/name).read_bytes()).hexdigest() for name in ['C2-default.patch','C3-cli-selector-retirement.patch']}},indent=2)+'\n')
print(json.dumps({'C2_files':c2files,'C3_files':c3files}))
