#!/usr/bin/env python3
"""Blackbox tests of the native component coordinator; Python is test-only."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import shlex
import stat
import subprocess
import tarfile
import tempfile
import unittest

BUILDER = None
ZIG = None


def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


class ComponentCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="native-components-test-")
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.root = self.workspace / "project"
        self.sources = self.root / "selfhost/components/test_index"
        self.sources.mkdir(parents=True)
        (self.sources / "main.my").write_text("func main() -> int:\n    return 0\n")
        self.planner_sources = self.root / "selfhost/components/cache_plan"
        self.planner_sources.mkdir(parents=True)
        (self.planner_sources / "main.my").write_text("func main() -> int:\n    return 0\n")
        lexer_sources = self.root / "selfhost/components/lexer_pilot"
        lexer_sources.mkdir(parents=True)
        (lexer_sources / "main.my").write_text("func main() -> int:\n    return 0\n")
        parser_sources = self.root / "selfhost/components/parser_pilot"
        parser_sources.mkdir(parents=True)
        (parser_sources / "full_adapter.my").write_text("func main() -> int:\n    return 0\n")
        self.declaration_sources = self.root / "selfhost/components/declaration_index"
        self.declaration_sources.mkdir(parents=True)
        (self.declaration_sources / "main.my").write_text("func main() -> int:\n    return 0\n")
        self.type_sources = self.root / "selfhost/components/type_interface"
        self.type_sources.mkdir(parents=True)
        (self.type_sources / "main.my").write_text("func main() -> int:\n    return 0\n")
        self.body_sources = self.root / "selfhost/components/body_check"
        self.body_sources.mkdir(parents=True)
        (self.body_sources / "main.my").write_text("func main() -> int:\n    return 0\n")
        self.cache = self.workspace / "cache"
        self.install = self.workspace / "installed"
        (self.workspace / "guardian-zig").mkdir()
        self.archive_source = self.workspace / "archive-source"
        (self.archive_source / "src").mkdir(parents=True)
        self.version = subprocess.check_output([ZIG, "version"], text=True).strip()
        (self.archive_source / ".zigversion").write_text(self.version + "\n")
        (self.archive_source / "src/runtime.c").write_text("pinned-runtime")
        self.seed_script = (
            "#!/bin/sh\n"
            "test \"$1\" = build && test -f \"$2\" || exit 13\n"
            "case \"$ZIG_GLOBAL_CACHE_DIR\" in */cache/zig-global) ;; *) exit 12;; esac\n"
            "printf 'component\\n' >> \"$COMPONENT_FIXTURE_LOG\"\n"
            "printf '%s\\n' \"$*\" >> \"$COMPONENT_FIXTURE_ARGS\"\n"
            "test \"${COMPONENT_FIXTURE_FAIL:-0}\" = 0 || exit 7\n"
            "while test $# -gt 0; do\n"
            "  if test \"$1\" = -o; then shift; printf '%s' \"${COMPONENT_FIXTURE_OUTPUT:-native-component}\" > \"$1\"; exit 0; fi\n"
            "  shift\n"
            "done\nexit 8\n"
        )
        self.write_archive()
        library = self.workspace / "lib"
        library.mkdir()
        (library / "runtime.h").write_text("pinned-library")
        self.zig = self.workspace / "fake-zig"
        self.zig.write_text(
            "#!/bin/sh\ncase \"$1\" in\n"
            f"version) printf '%s\\n' {shlex.quote(self.version)};;\n"
            f"env) printf '%s\\n' {shlex.quote(f'.lib_dir = "{library}", .target = "test-native"')};;\n"
            "build) printf 'seed\\n' >> \"$COMPONENT_FIXTURE_LOG\"; "
            "test ! -e abandoned || exit 9; test \"$(cat src/runtime.c)\" = pinned-runtime || exit 10; "
            "mkdir -p zig-out/focus; cp src/fake-seed zig-out/focus/mylang; chmod 755 zig-out/focus/mylang;;\n"
            "*) exit 11;;\nesac\n"
        )
        self.zig.chmod(0o755)
        self.log = self.workspace / "calls.log"
        self.arguments_log = self.workspace / "arguments.log"
        self.environment = {name: value for name, value in os.environ.items()
                            if not name.startswith("MYLANG_") and name != "ZIG"}
        self.environment["COMPONENT_FIXTURE_LOG"] = str(self.log)
        self.environment["COMPONENT_FIXTURE_ARGS"] = str(self.arguments_log)

    def write_archive(self):
        (self.archive_source / "src/fake-seed").write_text(self.seed_script)
        (self.archive_source / "src/fake-seed").chmod(0o755)
        self.archive = self.workspace / "pinned.tar"
        with tarfile.open(self.archive, "w") as bundle:
            bundle.add(self.archive_source / ".zigversion", arcname=".zigversion")
            bundle.add(self.archive_source / "src", arcname="src")
        pin = {"zig": self.version, "commit": "immutable-commit", "archive_sha256": digest(self.archive)}
        (self.root / "selfhost/component-seed.json").write_text(json.dumps(pin))

    def invoke(self, *flags, success=True, umask=-1):
        command = [BUILDER, "--root", str(self.root), "--zig", str(self.zig),
                   "--cache-dir", str(self.cache), "--install-dir", str(self.install),
                   "--seed-source", str(self.archive), *flags]
        result = subprocess.run(command, env=self.environment, capture_output=True, text=True, timeout=30, umask=umask)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.strip().splitlines()[0]
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(result.stderr.startswith("components: "), result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertNotIn("stack trace", result.stderr.lower())
        return result.stderr

    def calls(self, kind="component"):
        return self.log.read_text().splitlines().count(kind)

    def artifact(self, key):
        return self.cache / "artifacts" / key / "test-index"

    def test_unchanged_cache_and_source_change(self):
        first = self.invoke()
        self.assertEqual(first, self.invoke())
        self.assertEqual(self.calls(), 7)
        self.assertEqual(self.calls("seed"), 1)
        receipt = json.loads((self.cache / "artifacts" / first / "receipt.json").read_text())
        if platform.system() == "Linux":
            cpu = receipt["identity"]["target"]["cpu"]
            self.assertTrue(cpu, "native cache identity omitted Linux CPU metadata")
            machine = platform.machine().lower()
            if machine in {"x86_64", "amd64", "i386", "i686"}:
                self.assertTrue(cpu.get("model name", "").strip(), "missing CPU model")
                self.assertTrue(cpu.get("flags", "").strip(), "missing CPU feature flags")
            elif machine in {"aarch64", "arm64"} or machine.startswith("arm"):
                self.assertTrue(cpu.get("Features", "").strip(), "missing ARM CPU features")
        (self.sources / "graph.my").write_text("# new module\n")
        self.assertNotEqual(first, self.invoke())
        self.assertEqual(self.calls(), 8)

    def test_planner_change_is_independent_of_test_index(self):
        index_key = self.invoke()
        before = json.loads((self.install / "cache-plan.json").read_text())
        self.assertEqual(before["component"], "cache-plan")
        (self.planner_sources / "graph.my").write_text("# planner-only edit\n")
        self.assertEqual(index_key, self.invoke())
        after = json.loads((self.install / "cache-plan.json").read_text())
        self.assertNotEqual(before["key"], after["key"])
        self.assertEqual(self.calls(), 8)
        self.assertEqual(self.calls("seed"), 1)

    def test_declaration_change_preserves_other_component_receipts(self):
        self.invoke()
        packages = ("test-index", "cache-plan", "lexer-pilot", "parser-pilot", "declaration-index", "type-interface", "body-check")
        before = {name: (self.install / (name + ".json")).read_bytes() for name in packages}
        (self.declaration_sources / "indexing.my").write_text("# declaration-only edit\n")
        self.invoke()
        after = {name: (self.install / (name + ".json")).read_bytes() for name in packages}
        for name in packages:
            if name == "declaration-index":
                continue
            self.assertEqual(before[name], after[name])
        self.assertNotEqual(json.loads(before["declaration-index"])["key"],
                            json.loads(after["declaration-index"])["key"])
        self.assertEqual(self.calls(), 8)
        self.assertEqual(self.calls("seed"), 1)

    def test_type_interface_change_preserves_other_component_receipts(self):
        self.invoke()
        names = ("test-index", "cache-plan", "lexer-pilot", "parser-pilot", "declaration-index", "type-interface", "body-check")
        before = {name: (self.install / (name + ".json")).read_bytes() for name in names}
        (self.type_sources / "checking.my").write_text("# type-interface-only edit\n")
        self.invoke()
        after = {name: (self.install / (name + ".json")).read_bytes() for name in names}
        for name in names:
            if name != "type-interface":
                self.assertEqual(before[name], after[name])
        self.assertNotEqual(json.loads(before["type-interface"])["key"], json.loads(after["type-interface"])["key"])
        self.assertEqual(self.calls(), 8)
        self.assertEqual(self.calls("seed"), 1)

    def test_body_change_preserves_other_component_receipts(self):
        self.invoke()
        names = ("test-index", "cache-plan", "lexer-pilot", "parser-pilot", "declaration-index", "type-interface", "body-check")
        before = {name: (self.install / (name + ".json")).read_bytes() for name in names}
        (self.body_sources / "checking.my").write_text("# body-only edit\n")
        self.invoke()
        after = {name: (self.install / (name + ".json")).read_bytes() for name in names}
        for name in names:
            if name != "body-check":
                self.assertEqual(before[name], after[name])
        self.assertNotEqual(json.loads(before["body-check"])["key"], json.loads(after["body-check"])["key"])
        self.assertEqual(self.calls(), 8)
        self.assertEqual(self.calls("seed"), 1)

    def test_frontend_profile_is_versioned_in_manifest_and_build_receipt(self):
        self.invoke()
        for name, protocol, schema in (("test-index", 1, 1), ("cache-plan", 2, 2),
                                      ("lexer-pilot", 1, 2), ("parser-pilot", 1, 2), ("declaration-index", 1, 1), ("type-interface", 1, 1), ("body-check", 1, 7)):
            manifest = json.loads((self.install / (name + ".json")).read_text())
            receipt = json.loads((self.cache / "artifacts" / manifest["key"] / "receipt.json").read_text())
            self.assertEqual((manifest["protocol"], manifest["schema"]), (protocol, schema))
            self.assertEqual((receipt["identity"]["protocol"], receipt["identity"]["schema"]),
                             (protocol, schema))
        self.invoke()
        self.assertEqual(self.calls(), 7)

    def test_only_body_guest_uses_release_and_receipt_binds_exact_flags(self):
        self.invoke()
        arguments = [shlex.split(line) for line in self.arguments_log.read_text().splitlines()]
        self.assertEqual(len(arguments), 7)
        self.assertEqual(["--release" in argv for argv in arguments], [False] * 6 + [True])
        names = ("test-index", "cache-plan", "lexer-pilot", "parser-pilot",
                 "declaration-index", "type-interface", "body-check")
        for name in names:
            manifest = json.loads((self.install / (name + ".json")).read_text())
            receipt = json.loads((self.cache / "artifacts" / manifest["key"] / "receipt.json").read_text())
            flags = receipt["identity"]["flags"]
            self.assertEqual("--release" in flags, name == "body-check")
            self.assertEqual(flags[0], "release" if name == "body-check" else "default-debug")
        self.invoke("--uncached")
        self.assertEqual(self.calls(), 14)

    def test_body_receipt_with_default_guest_flags_cannot_be_reused(self):
        self.invoke()
        manifest = json.loads((self.install / "body-check.json").read_text())
        receipt_path = self.cache / "artifacts" / manifest["key"] / "receipt.json"
        receipt = json.loads(receipt_path.read_text())
        receipt["identity"]["flags"] = ["default-debug", "fresh-private-cache",
                                        "private-zig-global-v1"]
        receipt_path.write_text(json.dumps(receipt))
        self.invoke(success=False)
        self.assertEqual(self.calls(), 7)

    def test_identity_covers_embedded_input_bytes(self):
        (self.sources / "schema.json").write_text('{"version":1}')
        first = self.invoke()
        (self.sources / "schema.json").write_text('{"version":2}')
        self.assertNotEqual(first, self.invoke())

    def test_parser_identity_tracks_shared_lexer_source_through_file_link(self):
        lexical = self.root / "selfhost/components/lexer_pilot/lexer.my"
        lexical.write_text("# shared scanner version one\n")
        link = self.root / "selfhost/components/parser_pilot/lexer.my"
        link.symlink_to("../lexer_pilot/lexer.my")
        index_key = self.invoke()
        before = {name: json.loads((self.install / (name + ".json")).read_text())["key"]
                  for name in ("lexer-pilot", "parser-pilot")}
        lexical.write_text("# shared scanner version two\n")
        self.assertEqual(index_key, self.invoke())
        for name, key in before.items():
            self.assertNotEqual(key, json.loads((self.install / (name + ".json")).read_text())["key"])
        self.assertEqual(self.calls(), 9)
        self.assertEqual(self.calls("seed"), 1)

    def test_toolchain_library_change_requalifies_seed(self):
        first = self.invoke()
        (self.workspace / "lib/runtime.h").write_text("changed-library")
        self.assertNotEqual(first, self.invoke())
        self.assertEqual(self.calls("seed"), 2)

    def test_seed_qualification_changes_key(self):
        first = self.invoke()
        self.seed_script += "# changed qualified seed\n"
        self.write_archive()
        self.assertNotEqual(first, self.invoke())
        self.assertEqual(self.calls("seed"), 2)

    @unittest.skipUnless(os.name == "posix", "POSIX installation modes")
    def test_installed_resources_readable_and_receipt_private(self):
        key = self.invoke(umask=0o077)
        manifest_path = self.install / "test-index.json"
        manifest = json.loads(manifest_path.read_text())
        self.assertEqual(stat.S_IMODE(manifest_path.stat().st_mode), 0o644)
        self.assertEqual(stat.S_IMODE((self.install / manifest["artifact"]).stat().st_mode), 0o555)
        self.assertEqual(stat.S_IMODE((self.cache / "artifacts" / key / "receipt.json").stat().st_mode), 0o600)
        self.assertEqual(digest(self.install / manifest["artifact"]), manifest["sha256"])

    def test_corrupt_artifact_rejected_including_uncached(self):
        key = self.invoke()
        self.artifact(key).write_bytes(b"corrupt")
        self.invoke(success=False)
        self.invoke("--uncached", success=False)
        self.assertEqual(self.calls(), 7)

    def test_missing_artifact_rejected_including_uncached(self):
        key = self.invoke()
        self.artifact(key).unlink()
        self.invoke(success=False)
        self.invoke("--uncached", success=False)
        self.assertEqual(self.calls(), 7)

    def test_installed_artifact_corruption_does_not_replace_selection(self):
        self.invoke()
        manifest_path = self.install / "test-index.json"
        before = manifest_path.read_bytes()
        manifest = json.loads(before)
        installed = self.install / manifest["artifact"]
        installed.chmod(0o755)
        installed.write_bytes(b"corrupt installation")
        self.invoke(success=False)
        self.assertEqual(manifest_path.read_bytes(), before)

    def test_failed_build_preserves_selected_installation(self):
        self.invoke()
        before = (self.install / "test-index.json").read_bytes()
        (self.sources / "main.my").write_text("changed")
        self.environment["COMPONENT_FIXTURE_FAIL"] = "1"
        self.invoke(success=False)
        self.assertEqual(before, (self.install / "test-index.json").read_bytes())
        self.assertFalse(list((self.cache / "artifacts").glob("*.build")))

    def test_failed_planner_build_preserves_each_selected_installation(self):
        self.invoke()
        before_index = (self.install / "test-index.json").read_bytes()
        before_planner = (self.install / "cache-plan.json").read_bytes()
        (self.planner_sources / "main.my").write_text("changed planner")
        self.environment["COMPONENT_FIXTURE_FAIL"] = "1"
        self.invoke(success=False)
        self.assertEqual(before_index, (self.install / "test-index.json").read_bytes())
        self.assertEqual(before_planner, (self.install / "cache-plan.json").read_bytes())
        self.assertFalse(list((self.cache / "artifacts").glob("*.build")))

    def test_caller_zig_global_cache_does_not_reach_component_builds(self):
        self.environment["ZIG_GLOBAL_CACHE_DIR"] = str(self.workspace / "caller-zig-global")
        first = self.invoke()
        identity = json.loads((self.cache / "artifacts" / first / "receipt.json").read_text())["identity"]
        self.assertEqual(identity["build_cache_root"], str(self.cache))
        self.assertIn("private-zig-global-v1", identity["flags"])
        self.environment["ZIG_GLOBAL_CACHE_DIR"] = str(self.workspace / "different-zig-global")
        self.assertEqual(first, self.invoke("--uncached"))
        self.assertEqual(self.calls(), 14)
        self.assertFalse((self.workspace / "caller-zig-global").exists())
        self.assertFalse((self.workspace / "different-zig-global").exists())

    def test_uncached_build_checks_reproducibility(self):
        first = self.invoke()
        self.assertEqual(first, self.invoke("--uncached"))
        self.assertEqual(self.calls(), 14)
        self.environment["COMPONENT_FIXTURE_OUTPUT"] = "different"
        self.invoke("--uncached", success=False)
        self.assertEqual(self.artifact(first).read_bytes(), b"native-component")

    def test_abandoned_seed_recovers_and_requalifies(self):
        binary = Path(self.invoke("--seed-only"))
        directory = binary.parents[3]
        receipt = directory / "receipt.json"
        first = json.loads(receipt.read_text())
        receipt.unlink()
        (directory / "source/abandoned").write_text("interrupted build")
        binary.write_bytes(b"partial compiler")
        self.assertEqual(Path(self.invoke("--seed-only")), binary)
        self.assertEqual(json.loads(receipt.read_text()), first)
        self.assertEqual(digest(binary), first["sha256"])
        self.assertEqual(self.calls("seed"), 2)
        self.invoke("--seed-only")
        self.assertEqual(self.calls("seed"), 2)

    def test_malformed_component_receipt_fails_concisely(self):
        key = self.invoke()
        (self.cache / "artifacts" / key / "receipt.json").write_text("{")
        self.invoke(success=False)
        self.assertEqual(self.calls(), 7)

    def test_seed_archive_digest_mismatch_fails_concisely(self):
        self.archive.write_bytes(b"corrupt archive")
        self.invoke("--seed-only", success=False)
        self.assertFalse(list(self.cache.glob("seeds/*/receipt.json")))

    def test_malformed_seed_receipt_fails_concisely(self):
        binary = Path(self.invoke("--seed-only"))
        (binary.parents[3] / "receipt.json").write_text("{")
        self.invoke("--seed-only", success=False)
        self.assertEqual(self.calls("seed"), 1)

    def test_qualified_seed_digest_mismatch_fails_concisely(self):
        binary = Path(self.invoke("--seed-only"))
        binary.write_bytes(b"corrupt seed")
        self.invoke("--seed-only", success=False)
        self.assertEqual(self.calls("seed"), 1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builder", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    args, remaining = parser.parse_known_args()
    BUILDER = str(args.builder.resolve())
    ZIG = str(args.zig.resolve())
    unittest.main(argv=[__file__, *remaining])
