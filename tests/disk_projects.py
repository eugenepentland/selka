#!/usr/bin/env python3
"""Exercise application source edits with fixed host binaries and no build tools on PATH."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def identity(path):
    return hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mtime_ns


def run(binary, project, inputs, cwd):
    return subprocess.run(
        [str(binary), "--project", str(project), *map(str, inputs)],
        cwd=cwd, env=dict(os.environ, PATH=str(cwd / "no-build-tools")),
        capture_output=True, timeout=180,
    )


def success(result):
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return result.stdout


def rejected(result, code):
    assert result.returncode != 0 and result.stdout == b"", result
    assert code.encode() in result.stderr, result.stderr


def letter_module(body):
    """The helper module the edits replace, with one statement for its body."""
    return 'module helper\n\n\n\npublic def letter() -> u8:\n    ' + body + '\n'


def module_edits(binary, directory):
    project = directory / "small guest"
    project.mkdir()
    shutil.copyfile(ROOT / "src/schematic/guest/io.my", project / "io.my")
    entry = project / "main.my"
    helper = project / "helper.my"
    entry.write_text('module main\nimport io\nimport helper\n\n\ndef main() -> i64:\n    _ = io.put(helper.letter())\n    return 0\n')
    helper.write_text(letter_module('return 65u8'))
    inputs = [directory / f"empty{i}.sexp" for i in range(3)]
    for path in inputs:
        path.write_bytes(b"")
    assert success(run(binary, project, inputs, directory)) == b"A"
    helper.write_text('module helper\nimport added\n\n\n\npublic def letter() -> u8:\n    return added.letter()\n')
    (project / "added.my").write_text('module added\n\n\n\npublic def letter() -> u8:\n    return 66u8\n')
    assert success(run(binary, project, inputs, directory)) == b"B"
    (project / "added.my").unlink()
    rejected(run(binary, project, inputs, directory), "E_MODULE_READ")
    for body in ('return True', 'return'):
        helper.write_text(letter_module(body))
        failure = run(binary, project, inputs, directory)
        rejected(failure, "E_")
        assert re.search(rb"helper.my:\d+:\d+:", failure.stderr), failure.stderr
    helper.write_text(letter_module('return 67u8'))
    assert success(run(binary, project, inputs, directory)) == b"C"
    io = project / "io.my"
    io.write_text(io.read_text().replace('value: u8', 'value: i64'))
    entry.write_text('module main\nimport io\n\n\ndef main() -> i64:\n    _ = io.put(65)\n    return 0\n')
    rejected(run(binary, project, inputs, directory), "SignatureMismatch")
    entry.unlink()
    rejected(run(binary, project, inputs, directory), "E_MODULE_READ")


def schematic_edits(binary, directory):
    original = ROOT / "src/schematic/guest"
    changed = directory / "schematic worktree"
    shutil.copytree(original, changed)
    renderer = changed / "svg.my"
    before = renderer.read_text()
    assert "#0d1117" in before
    renderer.write_text(before.replace("#0d1117", "#123abc"))
    fixtures = ROOT / "experiments/schematic/fixtures"
    manifest = json.loads((fixtures / "manifest.json").read_text())
    inputs = [fixtures / entry["file"] for entry in manifest["files"]]
    with ThreadPoolExecutor(max_workers=2) as pool:
        outputs = list(pool.map(lambda project: success(run(binary, project, inputs, directory)), (original, changed)))
    assert outputs[0] == (fixtures.parent / "straps-synth-lmx2595.svg").read_bytes()
    assert outputs[1] == outputs[0].replace(b"#0d1117", b"#123abc")


def board_edits(binary, directory):
    original = ROOT / "src/board_trial/guest"
    changed = directory / "board worktree"
    shutil.copytree(original, changed)
    policy = changed / "policy.my"
    before = policy.read_text()
    assert "return region.blocks.via and" in before
    policy.write_text(before.replace("return region.blocks.via and", "return False and"))
    cases = json.loads((ROOT / "experiments/board_trial/cases.json").read_text())
    request = directory / "requests.json"
    request.write_text(json.dumps([{key: case[key] for key in ("name", "input", "unavailable")} for case in cases]))
    rows = [json.loads(success(run(binary, project, [request], directory))) for project in (original, changed)]
    assert [r["baseline"] for r in rows[0]] == [r["baseline"] for r in rows[1]]
    assert [r["guest"] for r in rows[0]] != [r["guest"] for r in rows[1]]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--schematic-runner", type=Path, required=True)
    parser.add_argument("--board-runner", type=Path, required=True)
    args = parser.parse_args()
    binaries = [args.schematic_runner.resolve(), args.board_runner.resolve()]
    before = list(map(identity, binaries))
    with tempfile.TemporaryDirectory(prefix="mylang disk projects ") as temporary:
        directory = Path(temporary)
        module_edits(binaries[0], directory)
        schematic_edits(binaries[0], directory)
        board_edits(binaries[1], directory)
    assert list(map(identity, binaries)) == before
    print("Disk projects: imports, repairs, host contracts, isolated roots and both application edits pass with unchanged binaries and no build tools on PATH")


if __name__ == "__main__":
    main()
