#!/usr/bin/env python3
"""Validate compiler-bound provider settings fingerprints before audited rekeying.

The context names immutable compiler hashes/embedded identities, guest Zig path,
tool content digest and the original launch's complete keyed environment. Every
configured command must have byte-equal inputs except compiler identity. The
independent frontend_settings_hash.zig witness recomputes both reported hashes.
Unknown project configuration, module roots or changed recipes fail closed.
"""
import copy
import hashlib
import json
from pathlib import Path
import re
import struct

RECIPE_SHA = "38ccedbe6f3ccdf26e275bfcb8d4abd0b189430463e93f44f0213682e49f80ad"
PLACEMENT = {"MYLANG_JOBS", "MYLANG_CORE_RUNTIME_CACHE", "MYL_CORE_PARENT_TOOL_TICKET"}
TOOLCHAIN = {"CCC_OVERRIDE_OPTIONS", "COMPILER_PATH", "CPATH", "C_INCLUDE_PATH",
    "CPLUS_INCLUDE_PATH", "GCC_EXEC_PREFIX", "LIBRARY_PATH", "OBJC_INCLUDE_PATH",
    "SOURCE_DATE_EPOCH", "ZIG", "ZIG_LIB_DIR", "ZIG_LIBC"}


def keyed_environment(environment):
    return {name: value for name, value in environment.items() if name not in PLACEMENT
        and (name.startswith(("MYL_", "MYLANG_")) or name in TOOLCHAIN)}


def validate_context(context, reference_binary, candidate_binary, reference_source, candidate_source):
    launch = context["original_launch_receipt"]
    launch_bytes = Path(launch["path"]).read_bytes()
    assert hashlib.sha256(launch_bytes).hexdigest() == launch["sha256"], "original launch receipt changed"
    launch_argv = json.loads(launch_bytes)["command"]
    for name in ("MYLANG_SLOT_DIR", "MYLANG_TIMING_CPUS"):
        assert name + "=" + context["environment"][name] in launch_argv, "launch environment differs"
    for name, binary, source in (("reference", reference_binary, reference_source),
                                ("candidate", candidate_binary, candidate_source)):
        saved = context[name]
        assert hashlib.sha256(binary.read_bytes()).hexdigest() == saved["binary_sha256"]
        assert re.fullmatch("[0-9a-f]{64}", saved["compiler_identity"])
        assert saved["compiler_identity"].encode() in binary.read_bytes(), "identity absent from immutable binary"
        assert hashlib.sha256((source / "src/core/test_runner_receipt.zig").read_bytes()).hexdigest() == RECIPE_SHA, "settings recipe changed"
    assert re.fullmatch("[0-9a-f]{64}", context["tool_digest"])
    assert keyed_environment(context["environment"]) == context["environment"], "unkeyed context field"
    assert context["environment"]["MYL_CORE_LEAKCHECK"] == "1"


def preimage(fields):
    return b"".join(struct.pack("<Q", len(field)) + field for field in fields)


def argument(argv, flag, default=None):
    for index, value in enumerate(argv):
        if value == flag:
            return argv[index + 1]
        if value.startswith(flag + "="):
            return value[len(flag) + 1:]
    return default


def byte_count(value):
    scale = {"k": 1 << 10, "m": 1 << 20, "g": 1 << 30}
    return int(value[:-1]) * scale[value[-1].lower()] if value[-1:].lower() in scale else int(value)


def fields(argv, context, compiler_identity):
    entry = Path(argv[2]).resolve()
    for parent in entry.parents:
        assert not (parent / "mylang.json").exists(), "project configuration requires an explicit recipe extension"
    head = re.search(rb"(?m)^module\s+([^\s#]+)", entry.read_bytes())
    assert head and head.group(1).decode() == entry.stem, "unknown configured module root"
    assert argument(argv, "--cases"), "explicit configured cases required"
    cases = Path(argument(argv, "--cases")).resolve()
    environment = context["environment"]
    memory = argument(argv, "--max-memory", environment.get("MYLANG_MEMORY_LIMIT", "536870912"))
    settings = {"release": "--release" in argv,
        "facts": "verify" if "--verify-facts" in argv else "off" if "--no-facts" in argv else "on",
        "vectors": False, "frames": None, "seed": None if argument(argv, "--seed") is None else int(argument(argv, "--seed")),
        "runs": int(argument(argv, "--property-runs", "100")),
        "timeout": int(argument(argv, "--timeout-ms", "60000")),
        "steps": int(argument(argv, "--max-steps", "1000000")),
        "call_frames": int(argument(argv, "--max-frames", "1024")), "memory": byte_count(memory)}
    result = [b"core-test-settings-v4", compiler_identity.encode(), str(entry).encode(),
        str(entry.parent).encode(), context["zig_path"].encode(), bytes.fromhex(context["tool_digest"]),
        str(cases).encode(), cases.read_bytes(), json.dumps(settings, separators=(",", ":")).encode()]
    for index, value in enumerate(argv):
        if value == "--link":
            linked = Path(argv[index + 1]).resolve()
            result.extend((str(linked).encode(), linked.read_bytes()))
    result.extend((name + "=" + value).encode() for name, value in sorted(environment.items()))
    return result


def normalize(report, stdout, expected, replacement):
    """Require each derived fingerprint; change only the matching test source token."""
    assert isinstance(report, dict), "invalid configured report"
    result = copy.deepcopy(report)
    items = [(index, test["source"]) for index, test in enumerate(report["tests"]) if "source" in test]
    matches = list(re.finditer(rb'(?<!\\)"source"\s*:\s*(?P<value>"(?:[^"\\]|\\.)*")', stdout))
    assert len(items) == len(matches), "ambiguous provider source fields"
    changes, substitutions = [], []
    for (index, value), match in zip(items, matches):
        assert json.loads(match.group("value")) == value == expected, "incorrect derived settings fingerprint"
        result["tests"][index]["source"] = replacement
        substitutions.append((match.start("value"), match.end("value"), json.dumps(replacement).encode()))
        changes.append({"stream": "stdout", "field": f"tests[{index}].source", "original": value,
            "replacement": replacement, "occurrences": 1, "independently_recomputed": True})
    for begin, end, data in reversed(substitutions):
        stdout = stdout[:begin] + data + stdout[end:]
    assert json.loads(stdout) == result
    return result, stdout, changes
