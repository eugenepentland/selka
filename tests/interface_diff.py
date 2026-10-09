#!/usr/bin/env python3
"""Seeded mutation harness for module interface hashes (MODULE-INTERFACE-2).

Each step copies the fixture project (`tests/fixtures/interfaces/`), applies one
mutation from a labelled catalog, and runs `selka interfaces emit` on it. A
mutation is either *body-only* (an edit to a body the interface replaces by
`pass`, a comment or blank lines between declarations, a private declaration
nothing exported reaches) or *interface-visible* (a signature, visibility,
deprecation, record, union or enum shape, fact, template, inlined, constant or
evaluated body). The harness asserts:

- body-only: every module's interface hash is unchanged, and only the edited
  module's implementation hash changes;
- interface-visible: the edited module's interface hash changes, every module
  whose interface lists a shape the mutation changed changes too (the
  24 September false-clean case: `reach` sees `shapes.Inner` only through
  `list[...]`, `dict[...]`, `Option[...]`, a class field and a union payload),
  and every direct importer's implementation hash changes.

After every accepted step it also runs `selka interfaces oracle` on the mutated
project, which must find every module's check against its imports' interfaces
equal to the whole-program check. A mutation that makes the project fail to
check is counted as rejected and skipped.

usage: interface_diff.py [--steps N] [--seed S] [--project DIR] [--keep DIR] COMPILER

Exits 0 when every step holds, 1 on a violation, 2 on a harness error.
"""
import argparse
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DEF = re.compile(r"^(public )?func (\w+)(\[[^\]]*\])?\((.*)\)( -> [^:]+)?:$", re.M)
SHOW_FUNCTION = re.compile(r"^  (\S+)::(\S+) (declared|template|constant|conversion|foreign|inlined|evaluated)( exported)? effects=\{([^}]*)\}")
LITERAL = re.compile(r"(?<![\w.])(\d+)(?![\w.])")


def run(cmd, cwd=None):
    env = dict(os.environ)
    env.setdefault("TMPDIR", tempfile.gettempdir())
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, env=env)


def emit(compiler, project, out):
    proc = run([compiler, "interfaces", "emit", str(project / "main.selka"), f"--out={out}"])
    if proc.returncode == 1:
        return None
    if proc.returncode != 0:
        raise SystemExit(f"harness error: emit exited {proc.returncode}: {proc.stderr[-400:]}")
    index = json.loads(proc.stdout)
    return {row["module"]: row for row in index["modules"]}


def show(compiler, path):
    proc = run([compiler, "interfaces", "show", str(path)])
    if proc.returncode != 0:
        raise SystemExit(f"harness error: show exited {proc.returncode}: {proc.stderr[-400:]}")
    roles, shapes, section = {}, set(), None
    for line in proc.stdout.splitlines():
        if not line.startswith("  "):
            section = line.split()[0] if line else None
            continue
        if section == "functions":
            m = SHOW_FUNCTION.match(line)
            if m:
                roles[m.group(2)] = (m.group(3), m.group(5))
        elif section == "shapes":
            shapes.add(line.split()[0])
    return roles, shapes


def body_range(text, name):
    """Start and end offsets of the indented body of top-level func `name`."""
    m = re.search(rf"^(public )?func {re.escape(name)}(\[[^\]]*\])?\(.*\)( -> [^:]+)?:\n", text, re.M)
    if not m:
        return None
    start = m.end()
    end = start
    for line in text[start:].splitlines(keepends=True):
        if line.strip() and not line.startswith(" "):
            break
        end += len(line)
    return m.start(), start, end


def with_literal_changed(text, start, end, rng):
    literals = [m for m in LITERAL.finditer(text, start, end)]
    if not literals:
        return None
    m = rng.choice(literals)
    return text[: m.start()] + str(int(m.group(1)) + 7) + text[m.end():]


def catalog(sources, roles, rng):
    """Every candidate mutation: (label, expectation, module, new_text, changed_shape)."""
    out = []
    for module, text in sources.items():
        module_roles = roles.get(module, {})
        for m in DEF.finditer(text):
            name, public = m.group(2), bool(m.group(1))
            role, effects = module_roles.get(name, (None, ""))
            found = body_range(text, name)
            if found is None:
                continue
            header_start, body_start, body_end = found
            if role == "declared":
                changed = with_literal_changed(text, body_start, body_end, rng)
                if changed:
                    out.append(("body literal", "same", module, changed, None))
                out.append(("body no-op", "same", module, text[:body_start] + "    const zz_ok = 1\n" + text[body_start:], None))
                if public and "managed_allocation" not in effects:
                    fact = text[:body_start] + "    const zz_fresh: int[] = [1]\n" + text[body_start:]
                    out.append(("fact: allocation", "changed", module, fact, None))
            elif role in ("template", "inlined", "evaluated"):
                changed = with_literal_changed(text, body_start, body_end, rng)
                if changed:
                    out.append((f"{role} body", "changed", module, changed, None))
            line = m.group(0)
            if public and role == "declared" and m.group(4):
                out.append(("signature: defaulted parameter", "changed", module, text.replace(line, line.replace(")", ", zz_extra: int = 0)", 1), 1), None))
            if public:
                out.append(("signature: rename", "changed", module, text.replace(line, line.replace(f"func {name}", f"func {name}_renamed", 1), 1), None))
                out.append(("visibility: unpublic", "changed", module, text.replace(line, line[len("public "):], 1), None))
            if "mut " in line:
                out.append(("signature: drop mut", "changed", module, text.replace(line, line.replace("mut ", "", 1), 1), None))
            if text[max(0, header_start - 2):header_start] == "\n\n":
                out.append(("comment between declarations", "same", module, text[:header_start] + "# zz note\n\n\n" + text[header_start:], None))
        out.append(("private addition", "same", module, text.rstrip("\n") + '\n\n\nfunc zz_private(n: int) -> int:\n    return n + 1\n', None))
        out.append(("public addition", "changed", module, text.rstrip("\n") + '\n\n\npublic func zz_public(n: int) -> int:\n    return n + 1\n', None))
        for c in re.finditer(r"^const (\w+): int = (\d+)$", text, re.M):
            out.append(("constant value", "changed", module, text[: c.start(2)] + str(int(c.group(2)) + 1) + text[c.end(2):], None))
        for d in re.finditer(r'^@deprecated\("([^"]*)"\)$', text, re.M):
            out.append(("deprecation reason", "changed", module, text[: d.start(1)] + d.group(1) + " soon" + text[d.end(1):], None))
    shapes = sources.get("shapes", "")
    if shapes:
        # `Inner` is reached by `reach` only through composite types.
        out.append(("shape: field added", "changed", "shapes", shapes.replace("    z: int = 0\n", "    z: int = 0\n    zz: int = 0\n", 1), "shapes::Inner"))
        out.append(("shape: field retyped", "changed", "shapes", shapes.replace("    z: int = 0\n", "    z: bool = False\n", 1), "shapes::Inner"))
        out.append(("shape: field renamed", "changed", "shapes", shapes.replace("    z: int = 0\n", "    z_renamed: int = 0\n", 1), "shapes::Inner"))
        out.append(("shape: used field retyped", "changed", "shapes", shapes.replace("    y: int\n", "    y: i32\n", 1), "shapes::Inner"))
        out.append(("shape: enum case added", "changed", "shapes", shapes.replace("    blue\n", "    blue\n    cyan\n", 1), "shapes::Color"))
        out.append(("shape: union case renamed", "changed", "shapes", shapes.replace("    idle\n", "    idle_renamed\n", 1), "shapes::Event"))
        out.append(("shape: union payload retyped", "changed", "shapes", shapes.replace("steps: int)", "steps: i32)", 1), "shapes::Event"))
        out.append(("shape: union case payload retyped", "changed", "shapes", shapes.replace("    tagged(value: Inner)\n", "    tagged(value: Color)\n", 1), "shapes::Event"))
        out.append(("shape: list element retyped", "changed", "shapes", shapes.replace("items: Inner[]", "items: Color[]", 1), "shapes::Holder"))
        out.append(("private record edit", "same", "shapes", shapes.replace("    secret: int\n", "    secret: bool\n", 1), None))
    lib = sources.get("lib", "")
    if lib:
        out.append(("private record edit", "same", "lib", lib.replace("    note: int\n", "    note: bool\n", 1), None))
    return out


def imports(sources):
    return {module: set(re.findall(r"^import (\w+)", text, re.M)) for module, text in sources.items()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("compiler")
    parser.add_argument("--steps", type=int, default=60)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--project", default=str(Path(__file__).resolve().parent / "fixtures" / "interfaces"))
    parser.add_argument("--keep", default=None)
    args = parser.parse_args()
    compiler = str(Path(args.compiler).resolve())
    project = Path(args.project)
    rng = random.Random(args.seed)
    sources = {p.stem: p.read_text() for p in sorted(project.glob("*.selka"))}
    importers = imports(sources)
    work = Path(tempfile.mkdtemp(prefix="interface-diff-"))
    violations, accepted, rejected, kinds = [], 0, 0, {}
    try:
        base_dir = work / "base"
        shutil.copytree(project, base_dir)
        base = emit(compiler, base_dir, work / "base-out")
        if base is None:
            raise SystemExit("harness error: the unmutated fixture does not check")
        # The hashes name no path or time: the same sources under another
        # directory, emitted again, give the same interfaces byte for byte.
        elsewhere = work / "elsewhere" / "nested" / "copy"
        shutil.copytree(project, elsewhere)
        again = emit(compiler, elsewhere, work / "elsewhere-out")
        for module, row in base.items():
            other = again.get(module) if again else None
            if other is None or (row["interface_hash"], row["implementation_hash"]) != (other["interface_hash"], other["implementation_hash"]):
                violations.append({"step": -1, "mutation": "none (moved and re-emitted)", "module": module, "problems": ["hashes differ between two directories"]})
            elif (work / "base-out" / f"{module}.selkai").read_bytes() != (work / "elsewhere-out" / f"{module}.selkai").read_bytes():
                violations.append({"step": -1, "mutation": "none (moved and re-emitted)", "module": module, "problems": ["artifact bytes differ between two directories"]})
        roles, shapes_of = {}, {}
        for module in base:
            roles[module], shapes_of[module] = show(compiler, work / "base-out" / f"{module}.selkai")
        by_label = {}
        for candidate in catalog(sources, roles, rng):
            by_label.setdefault(candidate[0], []).append(candidate)
        labels = sorted(by_label)
        for step in range(args.steps):
            # Pick the class first, so rare classes are drawn as often as common ones.
            label, expect, module, text, shape = rng.choice(by_label[rng.choice(labels)])
            step_dir = work / f"step-{step}"
            shutil.copytree(project, step_dir)
            (step_dir / f"{module}.selka").write_text(text)
            after = emit(compiler, step_dir, step_dir / "out")
            if after is None:
                rejected += 1
                shutil.rmtree(step_dir)
                continue
            accepted += 1
            kinds[label] = kinds.get(label, 0) + 1
            problems = []
            same = {m for m in base if m in after and base[m]["interface_hash"] == after[m]["interface_hash"]}
            if expect == "same":
                if set(base) != same:
                    problems.append(f"interface hash changed for {sorted(set(base) - same)}")
                impl_changed = {m for m in base if m in after and base[m]["implementation_hash"] != after[m]["implementation_hash"]}
                if impl_changed != {module}:
                    problems.append(f"implementation hash changed for {sorted(impl_changed)}, expected only {module}")
            else:
                if module in same:
                    problems.append(f"interface hash of {module} unchanged")
                if shape:
                    reachers = {m for m, reached in shapes_of.items() if shape in reached}
                    if shape == "shapes::Inner" and "reach" not in reachers:
                        problems.append("reach's interface does not list shapes::Inner")
                    stale = sorted(reachers & same)
                    if stale:
                        problems.append(f"{shape} changed but the interface hash of {stale} did not")
                if module not in same:
                    stale_impl = sorted(m for m, imported in importers.items() if module in imported and m in after and base[m]["implementation_hash"] == after[m]["implementation_hash"])
                    if stale_impl:
                        problems.append(f"importers {stale_impl} kept their implementation hash")
                if label == "fact: allocation":
                    new_roles, _ = show(compiler, step_dir / "out" / f"{module}.selkai")
                    if not any("managed_allocation" in eff for _, eff in new_roles.values()):
                        problems.append("the allocation fact did not reach the interface")
            oracle = run([compiler, "interfaces", "oracle", str(step_dir / "main.selka")])
            if oracle.returncode != 0:
                problems.append(f"oracle differs (exit {oracle.returncode}): {oracle.stdout[-600:]}{oracle.stderr[-300:]}")
            if problems:
                violations.append({"step": step, "mutation": label, "module": module, "problems": problems})
                if args.keep:
                    target = Path(args.keep) / f"violation-{step}"
                    shutil.rmtree(target, ignore_errors=True)
                    shutil.copytree(step_dir, target)
            shutil.rmtree(step_dir)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print(json.dumps({"steps": args.steps, "seed": args.seed, "accepted": accepted, "rejected": rejected,
                      "mutations": dict(sorted(kinds.items())), "violations": violations}, indent=1))
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
