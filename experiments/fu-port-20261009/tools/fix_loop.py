#!/usr/bin/env python3
"""FU-PORT: run `mylang fix DIR` until it is clean. Each E_BINDING_SCOPE_MIGRATION it reports
for a plain `name = value` statement (a local the old function scope shared between sibling
branches) becomes `mut name = value` in that branch, and fix runs again. Adding the declaration
cannot change a program that still checks: a branch-local binding read where it is not in scope
is a check error, never a different value. Anything else stops the loop and is printed.
usage: fix_loop.py MYLANG DIR CACHE"""
import pathlib, re, subprocess, sys

mylang, root, cache = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3]
DIAG = re.compile(r"^(?P<path>[^:\s]+\.my):(?P<line>\d+):(?P<col>\d+): error\[(?P<code>[A-Z_]+)\]", re.M)
total = 0
for round_ in range(200):
    done = subprocess.run([mylang, "fix", f"--cache-dir={cache}", "."], cwd=root, capture_output=True, text=True)
    text = done.stdout + done.stderr
    edits = sum(int(x) for x in re.findall(r"^fix: (\d+) edits", text, re.M))
    total += edits
    for line in text.splitlines():
        if line.startswith("fixed "):
            print(f"round {round_}: {line}")
    diags = list(DIAG.finditer(text))
    if done.returncode == 0 and not diags:
        print(f"clean after {round_ + 1} fix runs; fix edits {total}")
        sys.exit(0)
    progressed = False
    for d in diags:
        if d["code"] != "E_BINDING_SCOPE_MIGRATION":
            continue
        path = root / d["path"] if not pathlib.Path(d["path"]).is_absolute() else pathlib.Path(d["path"])
        lines = path.read_text().split("\n")
        i, col = int(d["line"]) - 1, int(d["col"]) - 1
        src = lines[i]
        if re.match(r"^\s*[A-Za-z_][A-Za-z_0-9]*(\s*:\s*[^=]+)?\s*=[^=]", src[col:]) and src[:col].strip() == "":
            lines[i] = src[:col] + "mut " + src[col:]
            path.write_text("\n".join(lines))
            print(f"hand: {d['path']}:{d['line']}: mut {src.strip()}")
            progressed = True
    for d in diags:
        if d["code"] != "E_TRY_POSITION":
            continue
        path = root / d["path"] if not pathlib.Path(d["path"]).is_absolute() else pathlib.Path(d["path"])
        lines = path.read_text().split("\n")
        i = int(d["line"]) - 1
        src = lines[i]
        # `target = Some(CALL?)` and `receiver.append(CALL?)`: the call becomes a `try`
        # declaration just before the statement, which then uses the new name. The call ran
        # first before as well (the wrapper and the receiver have no effects of their own).
        m = re.match(r"^(\s*)([\w.]+) = Some\((.*)\?\)$", src) or re.match(r"^(\s*)([\w.]+)\.append\((.*)\?\)$", src)
        field = re.match(r"^(\s*)(\w+(?:\.\w+)+) = (.*)\?$", src)
        if field and not m and "?" not in field.group(3):
            base, k, text = field.group(2).split(".")[-1] + "_value", 1, "\n".join(lines)
            name = base
            while re.search(rf"\b{name}\b", text):
                k += 1
                name = f"{base}{k}"
            lines[i:i + 1] = [f"{field.group(1)}mut {name} = try {field.group(3)}", f"{field.group(1)}{field.group(2)} = {name}"]
            path.write_text("\n".join(lines))
            print(f"hand: {d['path']}:{d['line']}: {src.strip()} -> mut {name} = try ...; {field.group(2)} = {name}")
            progressed = True
            break
        if not m or "?" in m.group(3):
            # General form: a call `f(args)?` inside a one-line statement whose text before the
            # call makes no call of its own (only reads of names and literals), whose arguments
            # carry no `mut` and no other `?`, and which is not an `elif`, loop or `match`
            # header: the call moves into a `try` declaration just before the statement. It ran
            # first among the statement's effects before as well, so the order is unchanged.
            col = int(d["col"]) - 1
            call = re.match(r"[A-Za-z_][\w.]*\(", src[col:])
            head = src[:col]
            stripped = head.strip()
            if call is None or re.search(r"[A-Za-z_][\w.]*\(", head) or re.match(r"(elif|while|for|match|case|else)\b", stripped):
                continue
            depth, end = 0, None
            for k in range(col + call.end() - 1, len(src)):
                depth += {"(": 1, ")": -1}.get(src[k], 0)
                if depth == 0:
                    end = k
                    break
            if end is None or end + 1 >= len(src) or src[end + 1] != "?" or "mut " in src[col:end] or "?" in src[col:end]:
                continue
            k, text = 1, "\n".join(lines)
            while re.search(rf"\btry_value{k}\b", text):
                k += 1
            name = f"try_value{k}"
            indent = re.match(r"\s*", src).group(0)
            lines[i:i + 1] = [f"{indent}mut {name} = try {src[col:end + 1]}", src[:col] + name + src[end + 2:]]
            path.write_text("\n".join(lines))
            print(f"hand: {d['path']}:{d['line']}: {src.strip()} -> mut {name} = try {src[col:end + 1]}; ...{name}...")
            progressed = True
            break
        base = m.group(2).split(".")[-1] + ("_value" if " = Some(" in src else "_item")
        name, k, text = base, 1, "\n".join(lines)
        while re.search(rf"\b{name}\b", text):
            k += 1
            name = f"{base}{k}"
        use = f"{m.group(2)} = Some({name})" if " = Some(" in src else f"{m.group(2)}.append({name})"
        lines[i:i + 1] = [f"{m.group(1)}mut {name} = try {m.group(3)}", f"{m.group(1)}{use}"]
        path.write_text("\n".join(lines))
        print(f"hand: {d['path']}:{d['line']}: {src.strip()} -> mut {name} = try ...; {use}")
        progressed = True
        break
    if not progressed:
        print(text)
        print(f"STOP: no mechanical step left; fix edits {total}")
        sys.exit(1)
