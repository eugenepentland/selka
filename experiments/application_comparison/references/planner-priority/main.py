"""Workflow planner v1: strict JSON transport and deterministic DAG planning."""

from collections import Counter
from dataclasses import dataclass
import heapq
import json
import math
import re
import sys


MAX_INPUT_BYTES = 1024 * 1024
MAX_CONTAINER_DEPTH = 64
IDENTIFIER = re.compile(r"[a-z][a-z0-9_-]{0,31}\Z", re.ASCII)


class InvalidRequest(ValueError):
    """The whole request violates the transport or envelope contract."""


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise InvalidRequest("duplicate JSON key")
        result[key] = value
    return result


def signed_integer(text):
    value = int(text)
    if not -(2**63) <= value < 2**63:
        raise InvalidRequest("integer outside signed 64-bit range")
    return value


def finite_float(text):
    value = float(text)
    if not math.isfinite(value):
        raise InvalidRequest("nonfinite number")
    return value


def reject_constant(text):
    raise InvalidRequest(f"invalid numeric constant: {text}")


def check_container_depth(text):
    """Bound parser nesting while leaving syntax validation to json.loads."""
    depth = 0
    in_string = False
    escaped = False
    for character in text:
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
        elif character == '"':
            in_string = True
        elif character in "[{":
            depth += 1
            if depth > MAX_CONTAINER_DEPTH:
                raise InvalidRequest("container nesting exceeds 64")
        elif character in "]}":
            depth -= 1


def check_unicode_scalars(value):
    """Reject unpaired surrogate escapes anywhere in decoded JSON."""
    pending = [value]
    while pending:
        item = pending.pop()
        if isinstance(item, str):
            if any(0xD800 <= ord(character) <= 0xDFFF for character in item):
                raise InvalidRequest("string contains an unpaired surrogate")
        elif isinstance(item, dict):
            pending.extend(item.keys())
            pending.extend(item.values())
        elif isinstance(item, list):
            pending.extend(item)


def parse_request(payload):
    if len(payload) > MAX_INPUT_BYTES:
        raise InvalidRequest("input too large")
    try:
        text = payload.decode("utf-8")
        check_container_depth(text)
        request = json.loads(
            text,
            object_pairs_hook=unique_object,
            parse_int=signed_integer,
            parse_float=finite_float,
            parse_constant=reject_constant,
        )
        check_unicode_scalars(request)
    except (UnicodeError, ValueError, RecursionError) as error:
        raise InvalidRequest(str(error)) from error
    if (
        not isinstance(request, dict)
        or request.keys() != {"cases"}
        or not isinstance(request["cases"], list)
        or len(request["cases"]) > 64
    ):
        raise InvalidRequest("invalid envelope")
    return request["cases"]


def is_identifier(value):
    return isinstance(value, str) and IDENTIFIER.fullmatch(value) is not None


def valid_schema(manifest):
    if (
        not isinstance(manifest, dict)
        or manifest.keys() != {"version", "jobs"}
        or type(manifest["version"]) is not int
        or manifest["version"] != 1
        or not isinstance(manifest["jobs"], list)
        or len(manifest["jobs"]) > 128
    ):
        return False
    for job in manifest["jobs"]:
        if (
            not isinstance(job, dict)
            or not {"id", "duration", "needs"} <= job.keys()
            or not job.keys() <= {"id", "duration", "needs", "priority"}
            or type(job.get("priority", 0)) is not int
            or not -1000 <= job.get("priority", 0) <= 1000
            or not is_identifier(job["id"])
            or type(job["duration"]) is not int
            or not 0 <= job["duration"] <= 1_000_000
            or not isinstance(job["needs"], list)
            or len(job["needs"]) > 128
            or not all(is_identifier(item) for item in job["needs"])
        ):
            return False
    return True


@dataclass(frozen=True)
class Job:
    id: str
    duration: int
    needs: tuple[str, ...]
    priority: int


def plan(manifest):
    """Validate complete phases in order, then plan a resolved graph."""
    if not valid_schema(manifest):
        return {"error": "invalid-manifest"}
    jobs = [Job(job["id"], job["duration"], tuple(job["needs"]), job.get("priority", 0))
            for job in manifest["jobs"]]
    repeated = sorted(key for key, count in Counter(job.id for job in jobs).items()
                      if count > 1)
    if repeated:
        return {"error": "duplicate-id", "ids": repeated}
    repeated_needs = sorted(job.id for job in jobs if len(set(job.needs)) != len(job.needs))
    if repeated_needs:
        return {"error": "duplicate-dependency", "jobs": repeated_needs}
    by_id = {job.id: job for job in jobs}
    missing = sorted({need for job in jobs for need in job.needs if need not in by_id})
    if missing:
        return {"error": "unknown-dependency", "ids": missing}
    return plan_graph(by_id)


def plan_graph(jobs):
    dependents = {key: [] for key in jobs}
    remaining = {key: len(job.needs) for key, job in jobs.items()}
    for job in jobs.values():
        for prerequisite in job.needs:
            dependents[prerequisite].append(job.id)

    ready = [(-jobs[key].priority, key) for key in jobs if remaining[key] == 0]
    heapq.heapify(ready)
    order = []
    starts, finishes, rounds = {}, {}, {}
    while ready:
        _, key = heapq.heappop(ready)
        job = jobs[key]
        order.append(key)
        starts[key] = max((finishes[need] for need in job.needs), default=0)
        finishes[key] = starts[key] + job.duration
        # Dependency depth is exactly the synchronous removal round.
        rounds[key] = max((rounds[need] + 1 for need in job.needs), default=0)
        for dependent in dependents[key]:
            remaining[dependent] -= 1
            if remaining[dependent] == 0:
                heapq.heappush(ready, (-jobs[dependent].priority, dependent))

    if len(order) != len(jobs):
        return {"error": "cycle", "blocked": sorted(key for key in jobs if remaining[key])}
    layers = [[] for _ in range(max(rounds.values(), default=-1) + 1)]
    for key in sorted(jobs):
        layers[rounds[key]].append(key)
    return {
        "order": order,
        "layers": layers,
        "timings": [{"id": key, "start": starts[key], "finish": finishes[key]}
                    for key in sorted(jobs)],
        "makespan": max(finishes.values(), default=0),
    }


def respond(payload):
    try:
        cases = parse_request(payload)
    except InvalidRequest:
        return {"error": "invalid-request"}
    return {"results": [plan(manifest) for manifest in cases]}


def main():
    # One extra byte distinguishes an over-limit request without an unbounded read.
    payload = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    json.dump(respond(payload), sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
