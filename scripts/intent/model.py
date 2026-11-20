"""Strict project-owned intent records; declarations are claims, not approvals."""
import hashlib
import json
import re
from pathlib import Path

from verification.core import bounded_bytes, digest


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key: " + key)
        result[key] = value
    return result


def read(path, limit=1024 * 1024):
    return json.loads(bounded_bytes(path, limit), object_pairs_hook=unique)


def text(value, name):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(name + " must be nonempty text")
    return value


def strings(value, name):
    if not isinstance(value, list) or any(not isinstance(x, str) or not x for x in value):
        raise ValueError(name + " must be a text array")
    if len(set(value)) != len(value):
        raise ValueError(name + " contains duplicate links")
    return value


def local(root, relative):
    text(relative, "path")
    path = Path(relative)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError("intent paths must stay inside the project")
    full = root / path
    if full.resolve() != full.absolute():
        raise ValueError("intent paths cannot traverse symlinks")
    return full


def fields(record, required, optional=()):
    if not isinstance(record, dict) or not set(required) <= record.keys() or record.keys() - set(required) - set(optional):
        raise ValueError("invalid record fields; required: " + ", ".join(required))


def load(root, filename):
    data = read(local(root, filename))
    fields(data, ("version", "requirements", "decisions"))
    if data["version"] != "design-intent-v1":
        raise ValueError("unsupported intent version")
    records = {}
    origins = {}
    for kind in ("requirements", "decisions"):
        if not isinstance(data[kind], list) or len(data[kind]) > 10000:
            raise ValueError("intent record count exceeds 10000")
        for row in data[kind]:
            common = ("id", "revision", "status", "statement", "rationale")
            required = common + (("origin", "implements", "tests", "assumptions", "non_goals") if kind == "requirements"
                                 else ("requirements", "symbols", "alternatives", "revisit_when"))
            fields(row, required)
            ident = text(row["id"], "id")
            if not re.fullmatch(r"[A-Z][A-Z0-9_-]{0,79}", ident) or ident in records:
                raise ValueError("invalid or duplicate intent ID: " + ident)
            if type(row["revision"]) is not int or row["revision"] < 1:
                raise ValueError("revision must be a positive integer")
            if row["status"] not in ("proposed", "accepted", "retired"):
                raise ValueError("status must be proposed, accepted or retired")
            for key in ("statement", "rationale"):
                text(row[key], key)
            arrays = ("implements", "tests", "assumptions", "non_goals") if kind == "requirements" else ("requirements", "symbols", "alternatives")
            for key in arrays:
                strings(row[key], key)
            if kind == "requirements":
                origin = row["origin"]
                fields(origin, ("path", "sha256", "excerpt", "kind"), ("reference",))
                if origin["kind"] not in ("user-request", "artifact", "example"):
                    raise ValueError("invalid origin kind")
                raw = bounded_bytes(local(root, origin["path"]), 1024 * 1024)
                actual = hashlib.sha256(raw).hexdigest()
                if actual != origin["sha256"]:
                    raise ValueError("request snapshot hash mismatch: " + ident)
                if text(origin["excerpt"], "excerpt") not in raw.decode("utf-8"):
                    raise ValueError("request excerpt is absent: " + ident)
                if "reference" in origin:
                    text(origin["reference"], "reference")
                origins[origin["path"]] = actual
            else:
                text(row["revisit_when"], "revisit_when")
            records[ident] = dict(row, kind=kind)
    requirements = {x["id"] for x in data["requirements"]}
    for decision in data["decisions"]:
        if not set(decision["requirements"]) <= requirements:
            raise ValueError("decision links an unknown requirement: " + decision["id"])
    return data, records, origins


def revisions(records, previous):
    if previous is None:
        return []
    if not isinstance(previous, dict) or previous.get("version") != "intent-report-v1":
        raise ValueError("unsupported previous report")
    if previous.get("partial"):
        raise ValueError("revision history requires a complete previous report")
    old = previous.get("records", {})
    changes = []
    for ident, record in records.items():
        if ident not in old:
            changes.append({"id": ident, "change": "added"})
        elif digest(record) != digest(old[ident]):
            if record["revision"] <= old[ident]["revision"]:
                raise ValueError("changed intent needs a higher revision: " + ident)
            changes.append({"id": ident, "change": "revised"})
    for ident in old.keys() - records.keys():
        raise ValueError("retain removed intent IDs with retired status: " + ident)
    return changes
