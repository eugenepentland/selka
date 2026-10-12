"""Prepare an unapplied C3 package-route patch, never a real compiler pin."""
import difflib
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--source-revision')
parser.add_argument('--output-dir', type=Path)
args = parser.parse_args()
original_base = Path(__file__).resolve().parent
root = original_base.parents[3]
base = args.output_dir or original_base
base.mkdir(parents=True, exist_ok=True)
suffix = '-' + args.source_revision[:9] if args.source_revision else ''
scratch = root / ('.tmp/memory-closeout/A10/component-retirement' + suffix)
destination = scratch / 'selfhost'
destination.mkdir(parents=True, exist_ok=True)
before = {}
after = {}


def load(path):
    before[path] = (subprocess.check_output(['git', 'show', f'{args.source_revision}:{path}'], cwd=root, text=True)
                    if args.source_revision else (root / path).read_text())
    return before[path]


def replace(source, old, new, count=1):
    assert source.count(old) == count, (old, source.count(old), count)
    return source.replace(old, new)


p = 'selfhost/components.zig'
s = load(p)
s = replace(s, 'owned_pin: ?[]const u8 = null };', 'owned_pin: []const u8 };')
s = replace(s, 'bootstrap: Bootstrap = .{},', 'bootstrap: Bootstrap,')
s = replace(s, ', owned: bool };', ' };')
s = replace(s, '/// The optional final-component compiler has a separate immutable source pin.',
            '/// The checked-default component compiler has a separate immutable source pin.')
s = replace(s, '    const recipe = try get(pin, "recipe");', '''    const selection = text(get(pin, "ownership_selection") catch
        return ctx.fail("component compiler pin requires checked-default-v1 ownership selection")) catch
        return ctx.fail("component compiler pin requires checked-default-v1 ownership selection");
    if (!std.mem.eql(u8, selection, "checked-default-v1"))
        return ctx.fail("component compiler pin requires checked-default-v1 ownership selection");
    const abi = text(get(pin, "guest_abi") catch
        return ctx.fail("component compiler pin requires mylang-checked-owned-v1 guest ABI")) catch
        return ctx.fail("component compiler pin requires mylang-checked-owned-v1 guest ABI");
    if (!std.mem.eql(u8, abi, "mylang-checked-owned-v1"))
        return ctx.fail("component compiler pin requires mylang-checked-owned-v1 guest ABI");
    const recipe = try get(pin, "recipe");''')
s = replace(s, '''    const owned = config.bootstrap.owned_pin != null;
    const pin = try ctx.metadata(config.bootstrap.owned_pin orelse try ctx.path(&.{ config.root, "selfhost", "component-seed.json" }));
    if (owned) try ownedPin(ctx, pin);''', '''    const pin = try ctx.metadata(config.bootstrap.owned_pin);
    try ownedPin(ctx, pin);''')
s = replace(s, ', .owned = owned', '', 2)
s = replace(s, 'if (owned) "seed-compiler" else "affected-compiler"', '"seed-compiler"')
s = replace(s, '    if (seed.owned) try flags.append(files.string("zero-rc-v1"));',
            '    try flags.append(files.string("zero-rc-v1"));\n    try flags.append(files.string("checked-default-v1"));\n    try flags.append(files.string("mylang-checked-owned-v1"));')
s = replace(s, '        if (seed.owned) try arguments.append(ctx.a, "--experimental-zero-rc");\n', '')
s = replace(s, 'files.string(if (seed.owned) "zero-rc-v1" else "legacy-rc")', 'files.string("zero-rc-v1")')
s = replace(s, '    try files.atomicJson(ctx.a, ctx.io, try ctx.path(&.{ config.install,',
            '    try manifest.object.put(ctx.a, "ownership_selection", files.string("checked-default-v1"));\n    try manifest.object.put(ctx.a, "guest_abi", files.string("mylang-checked-owned-v1"));\n    try files.atomicJson(ctx.a, ctx.io, try ctx.path(&.{ config.install,')
# Manifest object insertion needs a mutable Value wrapper in Zig.
s = replace(s, '    const manifest = try files.object', '    var manifest = try files.object')
s = replace(s, '[--owned-compiler-pin FILE]', '--owned-compiler-pin FILE')
s = replace(s, '    root = try cwd().realPathFileAlloc(ctx.io, root, ctx.a);',
            '    const selected_pin = owned_pin orelse return ctx.fail("--owned-compiler-pin is required; historical RC component compilation is retired");\n    root = try cwd().realPathFileAlloc(ctx.io, root, ctx.a);')
s = replace(s, '.owned_pin = if (owned_pin) |path_name| try cwd().realPathFileAlloc(ctx.io, path_name, ctx.a) else null,',
            '.owned_pin = try cwd().realPathFileAlloc(ctx.io, selected_pin, ctx.a),')
after[p] = s

p = 'selfhost/test_component_native.py'
s = load(p)
s = replace(s, 'parser.add_argument("--owned-compiler-pin", type=Path)', 'parser.add_argument("--owned-compiler-pin", type=Path, required=True)')
s = replace(s, 'pin_flags = ["--owned-compiler-pin", args.owned_compiler_pin] if args.owned_compiler_pin else []', 'pin_flags = ["--owned-compiler-pin", args.owned_compiler_pin]')
s = replace(s, '    guest_flags = ["--experimental-zero-rc"] if args.owned_compiler_pin else []\n', '')
s = replace(s, 'if args.owned_compiler_pin and manifest.get("memory_mode") != "zero-rc-v1":',
            'if manifest.get("memory_mode") != "zero-rc-v1" or manifest.get("ownership_selection") != "checked-default-v1" or manifest.get("guest_abi") != "mylang-checked-owned-v1":')
s = replace(s, ', *guest_flags', '', 2)
after[p] = s

p = 'selfhost/test_components.py'
s = load(p)
s = replace(s, '''            "case \\\" $* \\\" in *' --experimental-zero-rc '*) printf 'owned\\\\n' >> \\\"$COMPONENT_FIXTURE_LOG\\\";; esac\\n"''',
            '''            "case \\\" $* \\\" in *' --experimental-zero-rc '*|*' --experimental-single-owner '*) exit 13;; esac\\n"''')
s = replace(s, 'def invoke(self, *flags, success=True, umask=-1):', 'def invoke(self, *flags, success=True, umask=-1, no_pin=False):')
s = replace(s, '        command = [BUILDER, "--root", str(self.root),', '''        if not no_pin and "--owned-compiler-pin" not in flags:
            flags = (*flags, "--owned-compiler-pin", str(self.owned_pin()))
        command = [BUILDER, "--root", str(self.root),''')
s = replace(s, 'pin.update(memory_mode="zero-rc-v1", recipe={',
            'pin.update(memory_mode="zero-rc-v1", ownership_selection="checked-default-v1", guest_abi="mylang-checked-owned-v1", recipe={')
start = s.index('    def test_owned_route_builds_independent_compiler_and_separates_component_cache(self):')
end = s.index('    def test_owned_route_refuses_component_dependent_seed_recipe(self):', start)
s = s[:start] + '''    def test_owned_default_route_builds_independent_compiler_without_selectors(self):
        pin = self.owned_pin()
        historical_pin = self.root / "selfhost/component-seed.json"
        before = historical_pin.read_bytes()
        owned = self.invoke("--owned-compiler-pin", str(pin))
        self.assertEqual(self.calls("step:affected-compiler"), 0)
        self.assertEqual(self.calls("step:seed-compiler"), 1)
        receipt = json.loads((self.cache / "artifacts" / owned / "receipt.json").read_text())
        self.assertIn("zero-rc-v1", receipt["identity"]["flags"])
        self.assertIn("checked-default-v1", receipt["identity"]["flags"])
        self.assertIn("mylang-checked-owned-v1", receipt["identity"]["flags"])
        manifest = json.loads((self.install / "test-index.json").read_text())
        self.assertEqual(manifest["memory_mode"], "zero-rc-v1")
        self.assertEqual(manifest["ownership_selection"], "checked-default-v1")
        self.assertEqual(manifest["guest_abi"], "mylang-checked-owned-v1")
        self.assertEqual(owned, self.invoke("--owned-compiler-pin", str(pin)))
        self.assertEqual(self.calls("component"), 2)
        self.assertEqual(before, historical_pin.read_bytes())

    def test_missing_owned_pin_never_falls_back_to_historical_seed(self):
        self.assertTrue((self.root / "selfhost/component-seed.json").exists())
        self.assertIn("historical RC component compilation is retired", self.invoke(no_pin=True, success=False))
        self.assertFalse(self.log.exists())

    def test_optin_or_malformed_pin_cannot_select_an_ordinary_owned_recipe(self):
        for value in (None, "explicit-zero-rc-v1", False, 1):
            path = self.owned_pin()
            pin = json.loads(path.read_text())
            if value is None:
                del pin["ownership_selection"]
            else:
                pin["ownership_selection"] = value
            path.write_text(json.dumps(pin))
            self.assertIn("checked-default-v1", self.invoke("--owned-compiler-pin", str(path), success=False))
        self.assertFalse(self.log.exists())

    def test_missing_or_foreign_guest_abi_never_builds_a_component(self):
        for value in (None, "legacy-rc", "mylang-checked-owned-v2", False, 1):
            path = self.owned_pin()
            pin = json.loads(path.read_text())
            if value is None:
                del pin["guest_abi"]
            else:
                pin["guest_abi"] = value
            path.write_text(json.dumps(pin))
            self.assertIn("mylang-checked-owned-v1", self.invoke("--owned-compiler-pin", str(path), success=False))
        self.assertFalse(self.log.exists())

''' + s[end:]
s = replace(s, 'artifact=name, sha256=digest(artifact), memory_mode="zero-rc-v1"',
            'artifact=name, sha256=digest(artifact), memory_mode="zero-rc-v1", ownership_selection="checked-default-v1", guest_abi="mylang-checked-owned-v1"')
s = replace(s, 'self.assertIn("--experimental-zero-rc", call.args[0])',
            'self.assertNotIn("--experimental-zero-rc", call.args[0])\n                self.assertNotIn("--experimental-single-owner", call.args[0])')
s = replace(s, '            for call in executed.call_args_list:\n',
            '            for call in executed.call_args_list:\n                self.assertNotIn("--experimental-zero-rc", call.args[0])\n                self.assertNotIn("--experimental-single-owner", call.args[0])\n')
after[p] = s

patch = ''
identities = {}
for path, source in after.items():
    target = scratch / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(source)
    identities[path] = dict(original_sha256=hashlib.sha256(before[path].encode()).hexdigest(),
                            draft_sha256=hashlib.sha256(source.encode()).hexdigest())
    patch += f'diff --git a/{path} b/{path}\n'
    patch += ''.join(difflib.unified_diff(before[path].splitlines(True), source.splitlines(True), fromfile='a/' + path, tofile='b/' + path))
for path in ['selfhost/component_files.zig', 'selfhost/component_archive.zig']:
    if args.source_revision:
        (scratch / path).write_bytes(subprocess.check_output(['git', 'show', f'{args.source_revision}:{path}'], cwd=root))
    else:
        shutil.copyfile(root / path, scratch / path)
(base / 'C3-component-retirement.patch').write_text(patch)
(base / 'C3-component-retirement.json').write_text(json.dumps(dict(
    status='UNAPPLIED; root must provide actual qualified checked-default-v1 compiler pin and default build forwarding atomically',
    source_revision=args.source_revision,
    files=identities, patch_sha256=hashlib.sha256(patch.encode()).hexdigest(),
    historical_seed_unchanged=True,
    real_package_qualified=False), indent=2) + '\n')

# Keep root selection review separate; its destination file must contain a real
# qualified source/archive pin before the coordinator can apply this request.
p = 'build.zig'
root_before = load(p)
root_after = replace(root_before,
    'const component_owned_pin = b.option([]const u8, "component-owned-compiler-pin", "Independent checked-owned component compiler source pin (optional qualification route)");',
    'const component_owned_pin = b.option([]const u8, "component-owned-compiler-pin", "Qualified checked-owned component compiler source pin") orelse "selfhost/component-owned-compiler.json";')
for variable in ['component_build', 'native_component_tests']:
    root_after = replace(root_after,
        f'''    if (component_owned_pin) |pin| {{
        {variable}.addArg("--owned-compiler-pin");
        {variable}.addFileArg(if (std.fs.path.isAbsolute(pin)) b.graph.cwdRelativePath(pin) else b.path(pin));
    }}''',
        f'''    {variable}.addArg("--owned-compiler-pin");
    {variable}.addFileArg(if (std.fs.path.isAbsolute(component_owned_pin)) b.graph.cwdRelativePath(component_owned_pin) else b.path(component_owned_pin));''')
root_after = replace(root_after, 'Build and install pinned-seed Selka components without rebuilding the host',
                     'Build and install checked-owned Selka components without rebuilding the host')
(scratch / p).write_text(root_after)
request = f'diff --git a/{p} b/{p}\n' + ''.join(difflib.unified_diff(root_before.splitlines(True), root_after.splitlines(True), fromfile='a/' + p, tofile='b/' + p))
(base / 'C3-root-component-default-request.patch').write_text(request)
(base / 'C3-root-component-default-request.json').write_text(json.dumps(dict(
    status='UNAPPLIED coordinator request; actual qualified selfhost/component-owned-compiler.json is a required prerequisite, not supplied or fabricated here',
    source_revision=args.source_revision,
    base_sha256=hashlib.sha256(root_before.encode()).hexdigest(),
    draft_sha256=hashlib.sha256(root_after.encode()).hexdigest(),
    patch_sha256=hashlib.sha256(request.encode()).hexdigest(),
    input_registration='build_test_inputs.component_inputs already includes selfhost/component-*.json',
    historical_seed_unchanged=True), indent=2) + '\n')
