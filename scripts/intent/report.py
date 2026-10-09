"""Resolve intent against compiler facts and bind evidence to exact project inputs."""
from pathlib import Path
from collections import defaultdict, deque
import os
import sys
import verify as legacy

import navigate
from verification import core
from . import model


def snapshot(compiler, entry, filename, verification, previous=None):
    root = entry.parent
    before = core.tree(root)
    data, records, origins = model.load(root, filename)
    changes = model.revisions(records, previous)
    manifest = model.read(model.local(root, verification))
    if not isinstance(manifest, dict) or manifest.get("version") != 2:
        raise ValueError("intent verification requires a version 2 manifest")
    core.validate(manifest, legacy)
    index, _ = navigate.load(compiler, entry)
    if not index["checked"]:
        raise ValueError("intent requires successfully checked source")
    symbols = {item["id"]: item for item in index["symbols"]}
    steps = {step["id"]: step for step in manifest["steps"]}
    diagnostics = []
    for record in records.values():
        links = record["implements"] if record["kind"] == "requirements" else record["symbols"]
        if record["status"] == "retired":
            continue
        for symbol in links:
            if symbol not in symbols:
                diagnostics.append({"code": "I_UNKNOWN_SYMBOL", "id": record["id"], "symbol": symbol})
        if record["kind"] == "requirements":
            for test in record["tests"]:
                if test not in steps or steps[test]["kind"] not in ("test", "parity", "mutation"):
                    diagnostics.append({"code": "I_UNKNOWN_TEST", "id": record["id"], "test": test})
            if not links:
                diagnostics.append({"code": "I_UNIMPLEMENTED", "id": record["id"]})
            if not record["tests"]:
                diagnostics.append({"code": "I_UNTESTED", "id": record["id"]})
    for diagnostic in diagnostics:
        record = records[diagnostic["id"]]
        diagnostic["severity"] = ("warning" if record["status"] == "proposed" and
                                  diagnostic["code"] in ("I_UNIMPLEMENTED", "I_UNTESTED") else "error")
    implementation = {p.name: core.file_hash(p) for p in Path(__file__).parent.glob("*.py")}
    implementation["trace.py"] = core.file_hash(Path(__file__).parents[1] / "trace.py")
    implementation["python"] = core.file_hash(Path(sys.executable).resolve())
    implementation["navigate.py"] = core.file_hash(Path(navigate.__file__))
    for path in (Path(core.__file__).parent).glob("*.py"):
        implementation["verification/" + path.name] = core.file_hash(path)
    implementation["verify.py"] = core.file_hash(Path(core.__file__).parents[1] / "verify.py")
    basis = {"source": index["snapshot"], "project": before, "intent": data,
             "verification": manifest, "origins": origins, "implementation": implementation,
             "tools": {name: core.tools_for(step, root) for name, step in steps.items()},
             "environment": {name: os.environ.get(name) for name in {"PATH"} | {key for step in steps.values() for key in step.get("env", [])}}}
    if core.tree(root) != before:
        raise ValueError("project changed while resolving intent; retry")
    return {"version": "intent-report-v1", "basis_sha256": core.digest(basis),
            "snapshot_sha256": index["snapshot_sha256"], "records": records,
            "changes": changes, "diagnostics": diagnostics, "claims_only": True,
            "requirements": [], "references": index["references"],
            "symbols": {key: {"kind": value["kind"], "location": value["location"]} for key, value in symbols.items()}}, basis


def attach(report, evidence=None):
    current = False
    if evidence is not None:
        if not isinstance(evidence, dict) or set(evidence) != {"receipt", "sha256"} or core.digest(evidence["receipt"]) != evidence["sha256"]:
            raise ValueError("invalid evidence checksum")
        receipt = evidence["receipt"]
        if not isinstance(receipt, dict) or receipt.get("version") != "intent-evidence-v1":
            raise ValueError("unsupported evidence version")
        verification = receipt.get("verification")
        if not isinstance(verification, dict) or verification.get("version") != 2:
            raise ValueError("invalid evidence verification report")
        if not isinstance(verification.get("steps"), list) or not isinstance(verification.get("inventory"), dict):
            raise ValueError("invalid evidence steps or inventory")
        if any(not isinstance(row, dict) or not isinstance(row.get("id"), str) for row in verification["steps"]):
            raise ValueError("invalid evidence step")
        current = receipt["basis_sha256"] == report["basis_sha256"] and receipt["verification"].get("source_unchanged") is True
    rows = {row["id"]: row for row in evidence["receipt"]["verification"]["steps"]} if current else {}
    for ident, record in report["records"].items():
        if record["kind"] != "requirements":
            continue
        problems = [d for d in report["diagnostics"] if d["id"] == ident]
        tests = record["tests"]
        verified = bool(tests) and not problems and current and all(
            rows.get(test, {}).get("passed") is True and rows[test].get("status") in ("executed", "cached")
            for test in tests)
        tracked = current and all(evidence["receipt"]["verification"]["inventory"].get(test, {}).get("complete") is True for test in tests)
        state = ("retired" if record["status"] == "retired" else "linked-tests-passed" if verified and tracked else "observed-pass-untracked-inputs" if verified else
                 "stale" if evidence is not None and not current else "failed" if current and tests else "declared")
        report["requirements"].append({"id": ident, "status": record["status"], "evidence": state,
                                       "implements": record["implements"], "tests": tests,
                                       "formally_proven": False})
    report["evidence_current"] = current
    report["acceptance_authenticated"] = False
    return report


def query(report, requirement=None, symbol=None):
    records = report["records"]
    selected = {requirement} if requirement else set(records)
    if requirement and requirement not in records:
        raise ValueError("unknown intent ID: " + requirement)
    if symbol:
        if symbol not in report["symbols"]:
            raise ValueError("unknown symbol: " + symbol)
        affected = {symbol}
        incoming = defaultdict(set)
        for edge in report["references"]:
            incoming[edge["to"]].add(edge["from"])
        pending = deque([symbol])
        while pending:
            for caller in incoming[pending.popleft()] - affected:
                affected.add(caller)
                pending.append(caller)
        selected &= {ident for ident, row in records.items()
                     if affected.intersection(row.get("implements", row.get("symbols", [])))}
    for ident in list(selected):
        if records[ident]["kind"] == "decisions":
            selected.update(records[ident]["requirements"])
    decisions = {ident for ident, row in records.items() if row["kind"] == "decisions"
                 and selected.intersection(row["requirements"])}
    selected |= decisions
    result = {**report, "records": {key: records[key] for key in sorted(selected)},
              "requirements": [r for r in report["requirements"] if r["id"] in selected],
              "diagnostics": [d for d in report["diagnostics"] if d["id"] in selected]}
    if requirement or symbol:
        linked = {name for ident in selected for name in records[ident].get("implements", records[ident].get("symbols", []))}
        if symbol:
            linked.add(symbol)
        edges = [e for e in report["references"] if e["from"] in linked or e["to"] in linked]
        names = linked | {e[key] for e in edges for key in ("from", "to")}
        result.update(partial=True, references=edges,
                      symbols={key: value for key, value in report["symbols"].items() if key in names})
    return result
