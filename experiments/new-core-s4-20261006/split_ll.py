#!/usr/bin/env python3
"""S4 spike 2/3: split one emitted `.ll` into per-source-file codegen units.

This simulates S4-1's emission in text, to measure it before building it:
- a function `my.<file>::<name>` belongs to unit <file>; other definitions (the
  inlined runtime helpers) are copied, internal, into every unit that uses them;
- a function called from another unit becomes `hidden` (external) and is declared
  where it is called; everything else keeps its linkage;
- private constants are copied into the units that use them; other global
  definitions belong to unit `main` and are declared elsewhere;
- each unit gets the transitive closure of the metadata it references.
With `--normalize`, every unit renumbers its private constants and metadata in order
of first use, as S4's unit-local naming would; the unit text is then independent of
what other units contain.
Writes DIR/<unit>.ll and prints JSON {unit: sha256} to stdout.
"""
import argparse
import hashlib
import json
import os
import re

GLOBAL_REF = re.compile(r'@("[^"]+"|[A-Za-z_.$][A-Za-z0-9_.$]*)')
META_REF = re.compile(r"!(\d+)\b")
DEFINE_NAME = re.compile(r'^define\s[^@]*@("[^"]+"|[A-Za-z_.$][A-Za-z0-9_.$]*)\(')
GLOBAL_NAME = re.compile(r'^@("[^"]+"|[A-Za-z_.$][A-Za-z0-9_.$]*)\s*=')
UNIT_OF = re.compile(r'^"?my\.([A-Za-z0-9_]+)::')


def parse(text):
    header, defines, globals_, declares, attributes, metadata, named = [], {}, {}, {}, [], {}, []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("define "):
            name = DEFINE_NAME.match(line).group(1)
            body = [line]
            while lines[i] != "}":
                i += 1
                body.append(lines[i])
            defines[name] = "\n".join(body)
        elif line.startswith("declare "):
            name = GLOBAL_REF.search(line[line.index("@"):]).group(1)
            declares[name] = line
        elif line.startswith("@"):
            globals_[GLOBAL_NAME.match(line).group(1)] = line
        elif line.startswith("attributes "):
            attributes.append(line)
        elif re.match(r"^!\d+ = ", line):
            metadata[int(line[1:line.index(" ")])] = line
        elif line.startswith("!"):
            named.append(line)
        elif line.strip():
            header.append(line)
        i += 1
    return header, defines, globals_, declares, attributes, metadata, named


def unit_of(name):
    m = UNIT_OF.match(name)
    return m.group(1) if m else None


def signature(define):
    """`declare` text for a definition: its return type, name and parameter types."""
    first = define.split("\n", 1)[0]
    head, rest = first.split("@", 1)
    words = [w for w in head.split()[1:] if w not in ("internal", "private", "hidden", "dso_local")]
    name_end = rest.index("(")
    params, depth, j = [], 0, name_end
    for j in range(name_end, len(rest)):
        if rest[j] == "(":
            depth += 1
        elif rest[j] == ")":
            depth -= 1
            if depth == 0:
                break
    inner = rest[name_end + 1:j]
    for p in split_top(inner):
        p = p.strip()
        if p:
            params.append(re.sub(r"\s+%[A-Za-z0-9_.]+$", "", p))
    return f"declare {' '.join(words)} @{rest[:name_end]}({', '.join(params)})"


def split_top(text):
    out, depth, start = [], 0, 0
    for k, c in enumerate(text):
        if c in "({[<":
            depth += 1
        elif c in ")}]>":
            depth -= 1
        elif c == "," and depth == 0:
            out.append(text[start:k])
            start = k + 1
    out.append(text[start:])
    return out


def normalize(text):
    """Renumber private constants (`@myl.<kind>.<n>`) and metadata ids by first use."""
    consts, metas = {}, {}

    def const(m):
        key = m.group(0)
        if key not in consts:
            consts[key] = f"@myl.{m.group(1)}.u{len(consts)}"
        return consts[key]

    text = re.sub(r"@myl\.([a-z]+)\.(\d+)\b", const, text)
    # Unit-local trap sites: S4 gives each unit its own site table, so a site's number
    # (and the table) no longer depends on other units.
    sites = {}

    def site(m):
        sites.setdefault(m.group(1), len(sites))
        return f"@myl_core_trap(i32 {sites[m.group(1)]},"

    text = re.sub(r"@myl_core_trap\(i32 (\d+),", site, text)
    text = "\n".join(l for l in text.split("\n") if not l.startswith(("@myl_core_sites ", "@myl_core_site_count ")))

    def meta(m):
        key = m.group(1)
        if key not in metas:
            metas[key] = f"!{len(metas)}"
        return metas[key]

    return re.sub(r"!(\d+)\b", meta, text)


def split(text, normalized):
    header, defines, globals_, declares, attributes, metadata, named = parse(text)
    owner = {name: unit_of(name.strip('"')) for name in defines}
    for name, body in defines.items():  # `@main` and other external definitions belong to `main`
        if owner[name] is None and not body.startswith(("define internal", "define private")):
            owner[name] = "main"
    units = sorted({u for u in owner.values() if u})
    refs = {name: set(GLOBAL_REF.findall(body)) - {name} for name, body in defines.items()}
    cross = set()
    for name, targets in refs.items():
        for t in targets:
            if owner.get(t) and owner.get(name) and owner[t] != owner[name]:
                cross.add(t)
    out = {}
    for unit in units:
        mine = [n for n in defines if owner[n] == unit]
        # Shared helper definitions this unit reaches, transitively.
        needed, work = set(mine), list(mine)
        while work:
            for t in refs[work.pop()]:
                if t in defines and owner[t] is None and t not in needed:
                    needed.add(t)
                    work.append(t)
        used = set().union(*(refs[n] for n in needed))
        body = []
        for n in defines:
            if n not in needed:
                continue
            d = defines[n]
            if n in cross:
                d = d.replace("define internal ", "define hidden ", 1)
            body.append(d)
        decls = [signature(defines[t]).replace("declare ", "declare hidden ", 1) for t in sorted(used) if t in defines and owner[t] and owner[t] != unit]
        decls += [declares[t] for t in sorted(used) if t in declares]
        globs = []
        shared = {g for g, line in globals_.items() if " private " not in line and " external " not in line}
        if normalized:  # per-unit site tables: the global table and its strings are not main's
            shared -= {"myl_core_sites", "myl_core_site_count"}
        wanted = used | (shared if unit == "main" else set())
        work = [g for g in wanted if g in globals_]
        while work:  # constants that reference other constants
            for r in GLOBAL_REF.findall(globals_[work.pop()].split("=", 1)[1]):
                if r in globals_ and r not in wanted:
                    wanted.add(r)
                    work.append(r)
        for t in sorted(wanted):
            if t not in globals_:
                continue
            line = globals_[t]
            if " private " in line or " external " in line or unit == "main":
                globs.append(line)
            else:  # a shared definition owned by `main`, declared here
                ty = line.split(" constant ", 1)[1].split(" c\"", 1)[0] if " constant " in line else line.split(" global ", 1)[1].split()[0]
                globs.append(f"@{t} = external constant {ty}")
        chunk = "\n".join(globs + decls + body + named)
        roots = set(int(x) for x in META_REF.findall(chunk))
        seen, work = set(), list(roots)
        while work:
            k = work.pop()
            if k in seen or k not in metadata:
                continue
            seen.add(k)
            work.extend(int(x) for x in META_REF.findall(metadata[k].split(" = ", 1)[1]))
        meta = [metadata[k] for k in sorted(seen)]
        unit_text = "\n".join(header + globs + decls + [""] + body + [""] + attributes + named + meta) + "\n"
        if normalized:
            unit_text = normalize(unit_text)
        out[unit] = unit_text
    return out


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ll")
    parser.add_argument("directory")
    parser.add_argument("--normalize", action="store_true")
    args = parser.parse_args()
    units = split(open(args.ll).read(), args.normalize)
    os.makedirs(args.directory, exist_ok=True)
    hashes = {}
    for unit, text in units.items():
        with open(os.path.join(args.directory, f"{unit}.ll"), "w") as handle:
            handle.write(text)
        hashes[unit] = hashlib.sha256(text.encode()).hexdigest()
    print(json.dumps(hashes))
