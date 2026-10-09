#!/usr/bin/env python3
"""Remove capability parameters no body reads, and the arguments that fed them.

Item 2 makes an unused capability parameter an error: the signature claims an
effect the body cannot have. The fix is to delete the parameter and every
argument that supplied it, which can cascade -- a caller whose only use of its
own `host` was passing it on now has an unused parameter too.

The compiler is the driver. Each round checks every corpus module, reads the
diagnostics, and applies exactly the fix each one names:

  E_UNUSED_CAPABILITY  delete the parameter declaration
  E_DERIVED_EFFECTS    delete the clause (its effects can no longer be supplied)
  W_DERIVED_EFFECTS    delete the clause (it restates the derived ceiling)
  E_ARITY              delete the argument the removed parameter used to take

Fixes within one file are applied from the highest source offset down, so an
edit never invalidates a span reported for the same run.

Usage: python3 scripts/migrate_unused_capability.py --compiler PATH [--apply] ROOT ...
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = "module scan_tmp_{stem}\nimport {stem}\n\n\ndef main() -> int:\n    return 0\n"
DIAGNOSTIC = re.compile(r"^(.+?\.selka):(\d+):(\d+): (error|warning)\[(\w+)\]: (.*)$")
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*")
CLAUSE = re.compile(r"effects\s*\(|noalloc\b|noio\b")


def match_close(text: str, open_index: int) -> int:
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = [text[open_index]]
    for i in range(open_index + 1, len(text)):
        if text[i] in pairs:
            stack.append(text[i])
        elif text[i] in ")]}":
            if not stack or pairs[stack[-1]] != text[i]:
                return -1
            stack.pop()
            if not stack:
                return i
    return -1


def split_spans(text: str, start: int, end: int) -> list[tuple[int, int]]:
    """Bracket-aware (start, end) of every top-level comma-separated segment."""
    spans, depth, current = [], 0, start
    for i in range(start, end):
        ch = text[i]
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        elif ch == "," and depth == 0:
            spans.append((current, i))
            current = i + 1
    spans.append((current, end))
    trimmed = []
    for s, e in spans:
        while s < e and text[s] in " \t\n":
            s += 1
        while e > s and text[e - 1] in " \t\n":
            e -= 1
        if e > s:
            trimmed.append((s, e))
    return trimmed


def remove_segment(text: str, spans: list[tuple[int, int]], index: int) -> str:
    """Delete one comma-separated segment, taking its neighbouring comma."""
    start, end = spans[index]
    if index + 1 < len(spans):
        return text[:start] + text[spans[index + 1][0] :]
    if index > 0:
        return text[: spans[index - 1][1]] + text[end:]
    return text[:start] + text[end:]


def enclosing_parameters(text: str, offset: int):
    """(function name, parameter index, list spans) for the decl at `offset`."""
    head = text.rfind("def ", 0, offset)
    if head < 0:
        return None
    name = NAME.match(text, head + 4)
    open_paren = text.find("(", name.end() if name else head + 4)
    if open_paren < 0 or open_paren > offset:
        return None
    close = match_close(text, open_paren)
    if close < offset:
        return None
    spans = split_spans(text, open_paren + 1, close)
    for index, (start, end) in enumerate(spans):
        if start <= offset <= end:
            return (name.group(0), index, spans)
    return None


def line_offset(text: str, line: int, column: int) -> int:
    return sum(len(part) + 1 for part in text.split("\n")[: line - 1]) + column - 1


def check(compiler: Path, entry: Path):
    result = subprocess.run([str(compiler), "check", str(entry)], capture_output=True, text=True, cwd=ROOT, timeout=600)
    found = []
    for line in result.stderr.splitlines():
        match = DIAGNOSTIC.match(line.strip())
        if match and not match.group(1).startswith("scan_tmp_"):
            found.append(match.groups())
    return found


def resolve(directory: Path, name: str):
    if name.startswith("@stdlib/"):
        return ROOT / "src" / "stdlib" / name[len("@stdlib/") :]
    candidate = (directory / name).resolve()
    return candidate if candidate.exists() else None


DECLARATION = re.compile(r"^[ \t]*(?:(?:public|export|restricted|conversion)[ \t]+)*def[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*(\[[^\]]*\])?[ \t]*\(", re.MULTILINE)


def declaration_index(files):
    """Every declared function's parameter names, keyed by local name."""
    index: dict = {}
    for path in files:
        text = path.read_text(encoding="utf-8")
        for match in DECLARATION.finditer(text):
            open_paren = match.end() - 1
            close = match_close(text, open_paren)
            if close < 0:
                continue
            names = []
            for start, end in split_spans(text, open_paren + 1, close):
                head = text[start:end].split(":", 1)[0].split("=", 1)[0].strip()
                names.append(head)
            index.setdefault(match.group(1), []).append(names)
    return index


def capability_parameters(text: str, offset: int) -> set:
    """Names of the enclosing declaration's capability parameters."""
    head = text.rfind("def ", 0, offset)
    if head < 0:
        return set()
    name = NAME.match(text, head + 4)
    open_paren = text.find("(", name.end() if name else head + 4)
    if open_paren < 0:
        return set()
    close = match_close(text, open_paren)
    if close < 0:
        return set()
    spans = split_spans(text, open_paren + 1, close)
    names = set()
    for start, end in spans:
        declared = text[start:end]
        head, separator, rest = declared.partition(":")
        if not separator:
            continue
        base = rest.split("=", 1)[0].strip().removeprefix("mut ").split("[", 1)[0].strip()
        if base in ("Host", "Stream", "Filesystem", "Network", "Clock", "Entropy", "Environment"):
            names.add(head.strip())
    return names


def infer_removed_argument(text: str, offset: int, arguments, index):
    """Index of the extra argument a callee that lost a parameter no longer takes.

    The recorded registry is authoritative; this fallback reads the callee's
    declaration instead, and accepts only an argument count one larger than the
    declaration, a removal that keeps every other argument aligned with a
    declared parameter name, and an argument named by one of the caller's own
    capability parameters.
    """
    match = NAME.match(text[offset : offset + 64])
    if not match:
        return None
    candidates = index.get(match.group(0).rsplit(".", 1)[-1])
    if not candidates:
        return None
    caller_capabilities = capability_parameters(text, offset)
    best, best_score = None, 0
    for parameters in candidates:
        if len(arguments) != len(parameters) + 1:
            continue
        for position in range(len(arguments)):
            remaining = [text[s:e] for i, (s, e) in enumerate(arguments) if i != position]
            score = sum(1 for value, name in zip(remaining, parameters) if value == name)
            weighted = score + (1 if remaining and text[arguments[position][0] : arguments[position][1]] in caller_capabilities else 0)
            if weighted > best_score:
                best, best_score = position, weighted
    return best


def arguments_of(text: str, call_offset: int):
    open_paren = text.find("(", call_offset)
    if open_paren < 0:
        return None
    close = match_close(text, open_paren)
    if close < 0:
        return None
    return split_spans(text, open_paren + 1, close)


def plan_round(compiler: Path, files, registry, index):
    """Collect one fix per diagnostic. Returns (plans, leftover)."""
    plans: dict[Path, list] = {}
    seen: set = set()
    leftover = []
    for path in files:
        tmp = None
        entry = path
        try:
            if "\ndef main(" not in path.read_text(encoding="utf-8"):
                tmp = path.parent / f"scan_tmp_{path.stem}.selka"
                tmp.write_text(WRAPPER.format(stem=path.stem), encoding="utf-8")
                entry = tmp
            diagnostics = check(compiler, entry)
        except subprocess.TimeoutExpired:
            leftover.append(f"{path}: check timed out")
            continue
        finally:
            if tmp is not None:
                tmp.unlink(missing_ok=True)
        for name, line, column, _, code, message in diagnostics:
            target = resolve(path.parent, name)
            if target is None:
                leftover.append(f"{name}:{line}:{column}: {code} (unresolved path)")
                continue
            text = target.read_text(encoding="utf-8")
            offset = line_offset(text, int(line), int(column))
            if code == "E_UNUSED_CAPABILITY":
                located = enclosing_parameters(text, offset)
                if located is None:
                    leftover.append(f"{name}:{line}:{column}: {code} (no enclosing parameter)")
                    continue
                function, index, _ = located
                if (target, "parameter", offset) in seen:
                    continue
                seen.add((target, "parameter", offset))
                plans.setdefault(target, []).append(("parameter", offset, function, index, None))
            elif code in ("W_DERIVED_EFFECTS", "E_DERIVED_EFFECTS"):
                if not CLAUSE.match(text, offset):
                    leftover.append(f"{name}:{line}:{column}: {code} (no clause at span)")
                    continue
                if (target, "clause", offset) in seen:
                    continue
                seen.add((target, "clause", offset))
                plans.setdefault(target, []).append(("clause", offset, None, None, None))
            elif code == "E_ARITY":
                match = NAME.match(text[offset : offset + 64])
                if not match:
                    leftover.append(f"{name}:{line}:{column}: {code} (no callee name)")
                    continue
                local = match.group(0).rsplit(".", 1)[-1]
                arguments = arguments_of(text, offset)
                if arguments is None:
                    leftover.append(f"{name}:{line}:{column}: {code} (no argument list)")
                    continue
                removed = registry.get(local)
                position, parameter_name = None, None
                if removed:
                    candidate, parameter_name = removed[-1]
                    if candidate < len(arguments) and text[arguments[candidate][0] : arguments[candidate][1]] == parameter_name:
                        position = candidate
                if position is None:
                    position = infer_removed_argument(text, offset, arguments, index)
                    parameter_name = text[arguments[position][0] : arguments[position][1]] if position is not None else None
                if position is None:
                    leftover.append(f"{name}:{line}:{column}: {code} (cannot tell which argument to drop: {message})")
                    continue
                if (target, "argument", offset) in seen:
                    continue
                seen.add((target, "argument", offset))
                plans.setdefault(target, []).append(("argument", offset, local, position, parameter_name))
            else:
                leftover.append(f"{name}:{line}:{column}: {code}: {message}")
    return plans, leftover


def apply_plans(plans, registry):
    edits = 0
    for target, items in plans.items():
        text = target.read_text(encoding="utf-8")
        for kind, offset, function, index, parameter_name in sorted(items, key=lambda item: -item[1]):
            if kind == "parameter":
                located = enclosing_parameters(text, offset)
                if located is None:
                    continue
                _, position, spans = located
                name_text = text[spans[position][0] : spans[position][1]]
                declared_name = name_text.split(":", 1)[0].strip()
                text = remove_segment(text, spans, position)
                registry.setdefault(function, []).append((position, declared_name))
            elif kind == "clause":
                match = CLAUSE.match(text, offset)
                if not match:
                    continue
                if match.group(0).startswith("effects"):
                    end = match_close(text, match.end() - 1) + 1
                else:
                    end = match.end()
                text = text[:offset].rstrip() + text[end:]
            elif kind == "argument":
                arguments = arguments_of(text, offset)
                if arguments is None or index >= len(arguments):
                    continue
                text = remove_segment(text, arguments, index)
            edits += 1
        target.write_text(text, encoding="utf-8")
    return edits


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--rounds", type=int, default=12)
    parser.add_argument("roots", nargs="+")
    arguments = parser.parse_args(argv[1:])
    files = []
    for root in arguments.roots:
        path = Path(root)
        files.extend(sorted(path.rglob("*.selka")) if path.is_dir() else [path])
    registry: dict = {}
    index = declaration_index(files)
    leftover = []
    for round_number in range(1, arguments.rounds + 1):
        plans, leftover = plan_round(arguments.compiler, files, registry, index)
        edits = apply_plans(plans, registry) if arguments.apply else sum(len(v) for v in plans.values())
        print(f"round {round_number}: {edits} edit(s), {len(leftover)} unfixed", flush=True)
        if not arguments.apply or edits == 0:
            break
    print("== unfixed diagnostics ==")
    for item in leftover:
        print(item)
    print(f"== {sum(len(v) for v in registry.values())} parameter(s) removed ==")
    for function in sorted(registry):
        print(f"  {function}: {registry[function]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
