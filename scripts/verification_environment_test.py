#!/usr/bin/env python3
"""ENV-IDENTITY-1 and ENV-IDENTITY-2 for the Python reader of the contract.

The golden fixture under `test/fixtures/environment-identity/` is checked by
`src/environment_identity_test.zig` too, so both implementations agree on
every classification and on the digest. Run: python3 -B scripts/verification_environment_test.py -v
"""
from __future__ import annotations

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verification_environment as environment  # noqa: E402

FIXTURE = Path(__file__).resolve().parents[1] / "test" / "fixtures" / "environment-identity"


def fixture_environment() -> dict[str, str]:
    lines = (FIXTURE / "environment.txt").read_text(encoding="utf-8").splitlines()
    pairs = [line.split("=", 1) for line in lines]
    return {name: value for name, value in pairs}


def fixture_tools() -> dict[str, str]:
    lines = (FIXTURE / "tools.txt").read_text(encoding="utf-8").splitlines()
    return dict(line.split(" ", 1) for line in lines)


class ContractTest(unittest.TestCase):
    """ENV-IDENTITY-1: classification and precedence."""

    def test_fixture_classification(self):
        expected = [line.split(" ") for line in (FIXTURE / "classification.txt").read_text(encoding="utf-8").splitlines()]
        self.assertGreaterEqual(len(expected), 200)
        self.assertEqual(set(kind for _, kind in expected), set(environment.CLASSES))
        self.assertEqual([name for name, _ in expected], list(fixture_environment()))
        for name, kind in expected:
            self.assertEqual(environment.classify(name), kind, name)

    def test_precedence(self):
        cases = {
            "MYLANG_MEMORY_LIMIT": "keyed", "MYLANG_JOBS": "placement", "MYLANG_JOBSX": "keyed",
            "MYL_CORE_PARENT_TOOL_TICKET": "placement", "MYLANG_ADMISSION_DIR": "placement",
            "MYLANG_ADMISSIONS": "keyed", "MYLANG_ZIG": "keyed", "ZIG": "keyed",
            "ZIG_LOCAL_CACHE_DIR": "placement", "ZIG_VERBOSE_LINK": "dropped", "LD_PRELOAD": "keyed",
            "LC_ALL": "host", "PYTHONPATH": "host", "LANG": "host", "LANGUAGE": "host", "TZ": "host",
            "ZERO_AR_DATE": "keyed", "SELKA_PROFILE": "keyed", "CODEX_THREAD_ID": "dropped", "TERM": "dropped", "PWD": "dropped",
            "mylang_jobs": "dropped", "": "dropped",
            "MYLANG_TEST_TELEMETRY_DIR": "placement", "SELKA_VERIFICATION_TELEMETRY_DIR": "placement",
        }
        for name, kind in cases.items():
            self.assertEqual(environment.classify(name), kind, name)
        self.assertTrue(environment.host_keyed("TZ") and environment.host_keyed("MYLANG_OPTIONS"))
        self.assertFalse(environment.host_keyed("TMPDIR") or environment.host_keyed("TERM"))

    def test_project_keeps_keyed_and_placement(self):
        env = {"MYLANG_OPTIONS": "--restrict", "LANG": "C", "TMPDIR": "/t", "PATH": "/bin", "TERM": "xterm",
               "CODEX_THREAD_ID": "x", "PWD": "/w", "SELKA_VERIFICATION_TELEMETRY_DIR": "/r"}
        self.assertEqual(environment.project(env), {
            "MYLANG_OPTIONS": "--restrict", "LANG": "C", "TMPDIR": "/t", "PATH": "/bin", "SELKA_VERIFICATION_TELEMETRY_DIR": "/r"})

    def test_contract_reader_is_strict(self):
        good = '// c\n.{ .keyed = .{ "A*", }, .host = .{"C"}, .placement = .{"B"}, .dropped = .{} }'
        self.assertEqual(environment.parse(good), {"keyed": ["A*"], "host": ["C"], "placement": ["B"], "dropped": []})
        bad = [
            '.{ .keyed = .{"A"}, .host = .{}, .placement = .{} }',
            '.{ .keyed = .{"A"}, .placement = .{}, .dropped = .{} }',
            '.{ .keyed = .{}, .host = .{"A*"}, .placement = .{}, .dropped = .{"A*"} }',
            '.{ .keyed = .{"A"}, .host = .{}, .placement = .{"A"}, .dropped = .{} }',
            '.{ .keyed = .{"A*B"}, .host = .{}, .placement = .{}, .dropped = .{} }',
            '.{ .keyed = .{"*"}, .host = .{}, .placement = .{}, .dropped = .{} }',
            '.{ .keyed = .{"A\\n"}, .host = .{}, .placement = .{}, .dropped = .{} }',
            '.{ .keyed = .{"A"} .host = .{}, .placement = .{}, .dropped = .{} }',
            '.{ .other = .{}, .keyed = .{}, .host = .{}, .placement = .{}, .dropped = .{} }',
            '.{ .keyed = .{}, .host = .{}, .placement = .{}, .dropped = .{} } extra',
        ]
        for text in bad:
            with self.assertRaises(environment.ContractError, msg=text):
                environment.parse(text)


class DigestTest(unittest.TestCase):
    """ENV-IDENTITY-2: the digest format, identical to the Zig implementation."""

    def setUp(self):
        self.env = fixture_environment()
        self.tools = fixture_tools()
        self.base = environment.digest(self.env, self.tools)
        self.host = environment.digest(self.env, self.tools, "host")

    def test_fixture_digests(self):
        self.assertEqual(self.base, (FIXTURE / "digest-guest.txt").read_text(encoding="utf-8").strip())
        self.assertEqual(self.host, (FIXTURE / "digest-host.txt").read_text(encoding="utf-8").strip())
        self.assertEqual(environment.digest(self.env, self.tools, "guest"), self.base)
        with self.assertRaises(ValueError):
            environment.digest(self.env, self.tools, "other")

    def test_launcher_and_placement_differences_are_invisible(self):
        changed = dict(self.env, CODEX_THREAD_ID="another-thread", TERM="dumb", PWD="/elsewhere",
                       TMPDIR="/other/tmp", MYLANG_TEST_TELEMETRY_DIR="/request/7")
        self.assertEqual(environment.digest(changed, self.tools), self.base)
        self.assertEqual(environment.digest(changed, self.tools, "host"), self.host)
        reordered = dict(reversed(list(self.env.items())))
        self.assertEqual(environment.digest(reordered, dict(reversed(list(self.tools.items())))), self.base)

    def test_host_variables_change_only_the_host_digest(self):
        changed = dict(self.env, PYTHONPATH="/other/site", LANG="de_DE.UTF-8")
        self.assertEqual(environment.digest(changed, self.tools), self.base)
        self.assertNotEqual(environment.digest(changed, self.tools, "host"), self.host)

    def test_keyed_and_tool_differences_change_the_digest(self):
        for scope, base in (("guest", self.base), ("host", self.host)):
            self.assertNotEqual(environment.digest(dict(self.env, MYLANG_MEMORY_LIMIT="1G"), self.tools, scope), base)
            self.assertNotEqual(environment.digest(dict(self.env, LD_PRELOAD="/lib.so"), self.tools, scope), base)
            self.assertNotEqual(environment.digest(self.env, dict(self.tools, zig="2" * 64), scope), base)

    def test_empty_digest_is_the_domain_field_alone(self):
        import hashlib
        import struct
        domain = environment.DOMAIN.encode()
        self.assertEqual(environment.digest({}, {}), hashlib.sha256(struct.pack("<Q", len(domain)) + domain).hexdigest())


if __name__ == "__main__":
    unittest.main()
