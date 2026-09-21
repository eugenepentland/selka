"""Counterfactual IL patcher: drop the manual 128-bit overflow computation after every 64-bit `mul`.
Diagnostic only: the patched program no longer traps on multiply overflow."""
import json, re, sys
d = json.load(open(sys.argv[1])); removed = 0
for f in d["functions"]:
    lines = f["il"].split("\n"); out = []; i = 0
    while i < len(lines):
        L = lines[i]
        if re.match(r" %v(\d+) =l mul %v(\d+), %v(\d+)$", L):
            out.append(L); i += 1; j = i
            while j < len(lines) and not re.match(r" jnz %v\d+, @overflow(\d+), @checked(\d+)$", lines[j]): j += 1
            if j < len(lines) and j - i < 40:
                mm = re.match(r" jnz %v\d+, @overflow(\d+), @checked(\d+)$", lines[j])
                out.append(f" jmp @checked{mm.group(2)}"); removed += j - i; i = j + 1; continue
        out.append(L); i += 1
    f["il"] = "\n".join(out)
json.dump(d, open(sys.argv[2], "w")); print("removed", removed, "lines")
