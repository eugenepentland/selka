"""Capture small syntax/semantics probes using the installed compiler only."""
import hashlib
import json
from pathlib import Path
import subprocess
import textwrap

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BINARY = ROOT / "zig-out/bin/mylang"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


CASES = {
    "unannotated_list_write": """
        def touch(values: list[int]):
            values[0] = 42
        def main() -> int:
            values = [1]
            touch(values)
            return values[0]
    """,
    "unannotated_class_write": """
        class Cursor:
            pos: int
        def advance(cursor: Cursor):
            cursor.pos = cursor.pos + 1
        def main() -> int:
            cursor = Cursor(pos=41)
            advance(cursor)
            return cursor.pos
    """,
    "declared_write_missing_marker": """
        def touch(values: list[int]) mutates(values):
            values[0] = 42
        def main() -> int:
            values = [1]
            touch(values)
            return values[0]
    """,
    "declared_write_marked": """
        def touch(values: list[int]) mutates(values):
            values[0] = 42
        def main() -> int:
            values = [1]
            touch(&values)
            return values[0]
    """,
    "option_context": """
        def payload(value: int) -> int:
            return value
        def wrapper(value: Option[int]) -> int:
            match value:
                case Some(number):
                    return number
                case None:
                    return 0
        def main() -> int:
            candidate: Option[int] = Some(21)
            if candidate is None:
                return 0
            return payload(candidate) + wrapper(candidate)
    """,
    "record_shallow_copy": """
        record Tally:
            count: int
            seen: list[int]
        def main() -> int:
            first = Tally(count=2, seen=[])
            second = first
            second.count = 40
            second.seen.append(7)
            assert first.count == 2
            assert len(first.seen) == 1
            return first.count + second.count
    """,
    "list_augmented_alias": """
        def main() -> int:
            values = [40]
            alias = values
            alias += [2]
            assert len(values) == 2
            return values[0] + values[1]
    """,
    "same_literal_different_storage": """
        def main() -> int:
            fixed: [2]int = [1, 2]
            fixed_copy = fixed
            fixed_copy = replace(fixed_copy, 0, 9)
            shared: list[int] = [1, 2]
            shared_alias = shared
            shared_alias[0] = 9
            assert fixed[0] == 1 and fixed_copy[0] == 9
            assert shared[0] == 9
            return 42
    """,
    "shadow_ok": """
        def Ok(value: int) -> int:
            return value + 1
        def main() -> int:
            return Ok(41)
    """,
    "result_discard": """
        def fail() -> Result[int, str]:
            return Err("failed")
        def main() -> int:
            _ = fail()
            return 42
    """,
}

CASES["class_field_augmented_rejected"] = CASES["unannotated_class_write"].replace(
    "cursor.pos = cursor.pos + 1", "cursor.pos += 1")
CASES["array_index_write_rejected"] = CASES["same_literal_different_storage"].replace(
    "fixed_copy = replace(fixed_copy, 0, 9)", "fixed_copy[0] = 9")
REJECTS = {
    "declared_write_missing_marker": "E_MUTATION_MARKER",
    "class_field_augmented_rejected": "E_ASSIGNMENT_TARGET",
    "array_index_write_rejected": "E_LIST_TYPE",
}


def invoke(args):
    result = subprocess.run(
        [str(BINARY), *args], cwd=ROOT, capture_output=True, text=True, timeout=60
    )
    return {"args": args, "exit": result.returncode,
            "stdout": result.stdout, "stderr": result.stderr}


def main():
    before = digest(BINARY)
    (HERE / "sources").mkdir(exist_ok=True)
    rows = []
    for name, source in CASES.items():
        path = HERE / "sources" / (name + ".my")
        path.write_text(textwrap.dedent(source).lstrip())
        relative = str(path.relative_to(ROOT))
        flags = ["--mutation-markers"] if "write" in name else []
        checked = invoke(["check", relative, *flags])
        row = {"case": name, "source_sha256": digest(path), "check": checked}
        if checked["exit"] == 0:
            row["run"] = invoke(["run", relative, "--print-result", *flags])
        if name in REJECTS:
            row["matches_expected"] = (
                checked["exit"] == 1 and REJECTS[name] in checked["stderr"])
        else:
            row["matches_expected"] = (
                checked["exit"] == 0 and row["run"]["exit"] == 42
                and row["run"]["stdout"].strip() == "42")
        rows.append(row)
        print(name, "check", checked["exit"],
              "run", row.get("run", {}).get("stdout", "skipped").strip(), flush=True)
    evidence = {
        "binary": str(BINARY), "sha256_before": before,
        "sha256_after": digest(BINARY),
        "revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "cases": rows,
    }
    (HERE / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    if before != evidence["sha256_after"] or not all(row["matches_expected"] for row in rows):
        raise SystemExit("Capture changed compiler identity or has an unexpected result")


if __name__ == "__main__":
    main()
