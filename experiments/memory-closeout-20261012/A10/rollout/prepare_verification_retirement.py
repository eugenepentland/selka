#!/usr/bin/env python3
"""Coordinator-owned verification package proof, emitted only as an unapplied patch."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--source-revision', required=True)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[4]
scratch = root / '.tmp/memory-closeout/A10' / ('verification-retirement-' + args.source_revision[:9])
before = {}
after = {}


def load(path):
    before[path] = subprocess.check_output(['git', 'show', f'{args.source_revision}:{path}'], cwd=root, text=True)
    return before[path]


def replace(source, old, new, count=1):
    assert source.count(old) == count, (old, source.count(old), count)
    return source.replace(old, new)


p = 'scripts/verify_cache.py'
s = load(p)
helper = '''def component_manifest(root: Path, name: str) -> tuple[Path, dict]:
    """Bind the installed checked-owned package before snapshot/replay admission."""
    path = root / "zig-out/libexec/mylang/components" / (name + ".json")
    manifest = read_record(path)
    version = 2 if name == "cache-plan" else 1
    if (not manifest or manifest.get("format") != 1 or manifest.get("component") != name
            or manifest.get("protocol") != version or manifest.get("schema") != version
            or manifest.get("memory_mode") != "zero-rc-v1"
            or manifest.get("ownership_selection") != "checked-default-v1"
            or manifest.get("guest_abi") != "mylang-checked-owned-v1"):
        raise VerificationError("component manifest does not select checked ownership: " + name)
    artifact = manifest.get("artifact")
    expected = manifest.get("sha256")
    if (not isinstance(artifact, str) or not artifact or artifact in (".", "..")
            or "/" in artifact or "\\\\" in artifact
            or not isinstance(expected, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", expected)):
        raise VerificationError("invalid component artifact identity: " + name)
    try:
        with (path.parent / artifact).open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
    except OSError as error:
        raise VerificationError("component artifact is unavailable: " + name) from error
    if actual != expected.lower():
        raise VerificationError("component artifact differs from manifest: " + name)
    return path, manifest


'''
s = replace(s, 'def artifact_paths(root: Path) -> list[Path]:\n', helper + 'def artifact_paths(root: Path) -> list[Path]:\n')
s = replace(s, '''        path = root / "zig-out/libexec/mylang/components" / (name + ".json")
        manifest = read_record(path)
        if not manifest or not isinstance(manifest.get("artifact"), str) or Path(manifest["artifact"]).name != manifest["artifact"]:
            raise VerificationError("invalid component manifest: " + name)
''', '''        path, manifest = component_manifest(root, name)
''')
s = replace(s, '''        manifest_path = root / "zig-out/libexec/mylang/components" / (name + ".json")
        manifest = read_record(manifest_path)
        if not manifest or not isinstance(manifest.get("artifact"), str):
            raise VerificationError("component manifest changed during provider selection")
''', '''        manifest_path, manifest = component_manifest(root, name)
''')
after[p] = s

p = 'scripts/verify_cache_test.py'
s = load(p)
s = replace(s, 'import contextlib\n', 'import contextlib\nimport hashlib\n')
s = replace(s, 'import json,sys\n', 'import hashlib,json,sys\n')
s = replace(s, "        (package/(name+'.json')).write_text(json.dumps({{'artifact':name}}))", '''        version = 2 if name == 'cache-plan' else 1
        (package/(name+'.json')).write_text(json.dumps({{'format':1,'component':name,'protocol':version,'schema':version,
            'artifact':name,'sha256':hashlib.sha256((package/name).read_bytes()).hexdigest(),
            'memory_mode':'zero-rc-v1','ownership_selection':'checked-default-v1','guest_abi':'mylang-checked-owned-v1'}}))''')
tests = '''class CheckedComponentPackage(unittest.TestCase):
    """Synthetic manifest admission tests; real component ABI needs native proof."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.directory = self.root / "zig-out/libexec/mylang/components"
        self.directory.mkdir(parents=True)
        self.manifests = {}
        for name in ("test-index", "cache-plan"):
            contents = ("fixture:" + name).encode()
            (self.directory / name).write_bytes(contents)
            version = 2 if name == "cache-plan" else 1
            self.manifests[name] = dict(format=1, component=name, protocol=version, schema=version,
                artifact=name, sha256=hashlib.sha256(contents).hexdigest(),
                memory_mode="zero-rc-v1", ownership_selection="checked-default-v1", guest_abi="mylang-checked-owned-v1")
            self.write(name, self.manifests[name])

    def write(self, name, value):
        (self.directory / (name + ".json")).write_text(json.dumps(value))

    def test_owned_manifests_bind_both_component_artifacts(self):
        for name in self.manifests:
            path, manifest = coordinator.component_manifest(self.root, name)
            self.assertEqual(path, self.directory / (name + ".json"))
            self.assertEqual(manifest, self.manifests[name])

    def test_missing_legacy_optin_and_malformed_ownership_markers_refuse(self):
        for name, valid in self.manifests.items():
            for field, value in (("memory_mode", None), ("ownership_selection", None),
                    ("memory_mode", "legacy-rc"), ("memory_mode", False),
                    ("ownership_selection", "explicit-zero-rc-v1"), ("guest_abi", None),
                    ("guest_abi", "mylang-checked-owned-v2"), ("guest_abi", 0)):
                with self.subTest(name=name, field=field, value=value):
                    bad = dict(valid)
                    if value is None:
                        del bad[field]
                    else:
                        bad[field] = value
                    self.write(name, bad)
                    with self.assertRaisesRegex(coordinator.VerificationError, "checked ownership"):
                        coordinator.component_manifest(self.root, name)
            self.write(name, valid)

    def test_owned_marker_does_not_authorize_foreign_protocol_or_bad_binary(self):
        for name, valid in self.manifests.items():
            for field, value in (("protocol", 99), ("artifact", "../escape"), ("sha256", "0" * 64)):
                with self.subTest(name=name, field=field):
                    self.write(name, dict(valid, **{field: value}))
                    with self.assertRaises(coordinator.VerificationError):
                        coordinator.component_manifest(self.root, name)
            self.write(name, valid)
            (self.directory / name).write_bytes(b"replaced")
            with self.assertRaisesRegex(coordinator.VerificationError, "differs from manifest"):
                coordinator.component_manifest(self.root, name)


'''
s = replace(s, 'REAL_ADMISSION = coordinator.run_admitted\n', tests + 'REAL_ADMISSION = coordinator.run_admitted\n')
after[p] = s

patch = ''
for path, value in after.items():
    target = scratch / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(value)
    patch += f'diff --git a/{path} b/{path}\n'
    patch += ''.join(difflib.unified_diff(before[path].splitlines(True), value.splitlines(True), fromfile='a/' + path, tofile='b/' + path))
args.output_dir.mkdir(parents=True, exist_ok=True)
(args.output_dir / 'C3-verification-package-request.patch').write_text(patch)
(args.output_dir / 'C3-verification-package-request.json').write_text(json.dumps({
    'status': 'UNAPPLIED shared-file request; root owns verification coordinator and must requalify its complete input contract',
    'source_revision': args.source_revision,
    'patch_sha256': hashlib.sha256(patch.encode()).hexdigest(),
    'files': {path: {'base_sha256': hashlib.sha256(before[path].encode()).hexdigest(),
                     'draft_sha256': hashlib.sha256(value.encode()).hexdigest()} for path, value in after.items()},
}, indent=2) + '\n')
print(scratch)
