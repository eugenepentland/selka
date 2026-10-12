"""Export immutable source evidence; this does not qualify compiled deployments."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import subprocess

C0 = "fbfcaa7a923186a8e773c3760f81c10aa345a432"
PORT = "dff9304b9cd7bc72e66f9feb20f1b05281d67333"
FILES = (
    ".zigversion", "selfhost/component-seed.json", "selfhost/components.zig",
    "selfhost/component_files.zig", "selfhost/component_archive.zig",
    "selfhost/component_support_test.zig", "selfhost/test_components.py",
    "selfhost/test_component_native.py", "docs/tooling/selfhost-components.md",
    "scripts/build-slot.sh", "src/core/test_runner_directory.zig",
    "src/core/test_runner_batch.zig", "src/core/test_runner_discover.zig",
    "src/core/test_runner_work.zig",
)


def export(repository):
    """Hash exact git objects and enumerate existing coordinator regression cases."""
    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(repository), *arguments])
    snapshots = {}
    for role, ref in (("C0", C0), ("port", PORT)):
        actual = git("rev-parse", ref + "^{commit}").decode().strip()
        if actual != ref:
            raise ValueError("full frozen commit identity required")
        files = {path: git("show", ref + ":" + path) for path in FILES}
        if role == "port":
            for path in ("src/body_check_component.zig", "src/body_check_protocol.zig",
                         "src/frontend_runtime.zig", "selfhost/tests/measure_performance_ratio.py"):
                files[path] = git("show", ref + ":" + path)
        tree = ast.parse(files["selfhost/test_components.py"])
        tests = [node.name for node in ast.walk(tree)
                 if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")]
        snapshots[role] = {"commit": ref,
                           "files": {path: hashlib.sha256(data).hexdigest() for path, data in files.items()},
                           "component_coordinator_test_cases": tests,
                           "seed_pin": json.loads(files["selfhost/component-seed.json"])}
    return {"schema": "s09-frozen-source-audit-v1", "acceptance": "source inventory only",
            "snapshots": snapshots,
            "overlap_changes": [path for path in FILES
                                if snapshots["C0"]["files"][path] != snapshots["port"]["files"][path]],
            "full_bootstrap": "not qualified", "strict_performance": "not qualified"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(export(args.repository), indent=2, sort_keys=True) + "\n")
