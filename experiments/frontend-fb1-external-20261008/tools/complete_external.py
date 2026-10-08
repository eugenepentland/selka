#!/usr/bin/env python3
"""Complete one admitted external gate batch; every phase has its own receipt."""
from pathlib import Path
import json
import os
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
worktree = root.parents[1]
timer = root / "tools/time-command.py"
refs = Path("/home/epentland/ai/canopy/mylang-worktrees/codex-frontend-integration/experiments/frontend-current-lang-oracle-20261008")
integration = refs.parents[1]
compiler_source = Path("/home/epentland/ai/canopy/mylang-worktrees/codex-frontend-fb1")
compiler = compiler_source / "zig-out/bin/mylang"
scratch = worktree / ".mylang-cache/frontend-fb1-external"
identities = json.loads((root / "input-identities.json").read_text())
env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")


def phase(label, *argv):
    print("starting " + label, flush=True)
    done = subprocess.run([sys.executable, str(timer), label, "--", *map(str, argv)], cwd=worktree, env=env)
    if done.returncode:
        raise SystemExit(done.returncode)
    print("passed " + label, flush=True)


phase("fb1-eda-native-goldens", sys.executable, root / "tools/frontend_external_oracle.py", "eda",
    "--source", identities["corpora"]["eda"]["root"], "--binary", scratch / "bin/eda-release",
    "--output", scratch / "native-results/eda", "--against",
    integration / "experiments/frontend-integration-20261008/external/eda-s5-release/answers.json")
for corpus, count in (("lox", 65), ("eda", 310)):
    identity_path = refs / corpus / "identity.json"
    phase("fb1-" + corpus + "-mode-suite", sys.executable, worktree / "scripts/frontend_compare_frozen_tests.py",
        "--source", compiler_source, "--compiler", compiler, "--compiler-sha256", identities["compiler"]["sha256"],
        "--source-commit", "889943fa81a7c0c69a6452b0ab6c076b42b728cc",
        "--against", refs / corpus, "--against-identity-sha256", identities["references"][str(identity_path)]["sha256"],
        "--output", root / (corpus + "-tests"), "--cache", scratch / "test-cache" / corpus,
        "--expected-tests", str(count))
    phase("audit-fb1-" + corpus + "-mode-results", sys.executable, root / "tools/audit_frozen.py",
        root / (corpus + "-tests"), "--output", root / ("fb1-" + corpus + "-mode-audit.json"))
for corpus, count in (("lox", 974), ("eda", 34)):
    phase("archive-fb1-" + corpus + "-native-evidence", sys.executable, root / "tools/archive-native-evidence.py",
        "--area", scratch / "native-results" / corpus, "--output", root / ("native-" + corpus),
        "--cases", str(count))
print("all external phases passed", flush=True)
