# Counterfactual IL rewrites over an `emit-project-qbe` manifest (upper bounds, not landings):
#   python3 strip_checks.py in.json out.json overflow    # drop every add/sub overflow test
#   python3 strip_checks.py in.json out.json position    # drop every hot-path `storel N, %position`
# Build with `mylang build main.my --manifest-file=out.json -o bin --mode ReleaseFast`.
import json, sys, re
src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(src)); n = 0
for f in d["functions"]:
    lines = f["il"].split("\n"); out = []; i = 0
    while i < len(lines):
        l = lines[i]
        if mode == "position" and re.match(r" storel \d+, %position$", l): n += 1; i += 1; continue
        m = re.match(r" jnz (%v\d+), @overflow(\d+), @checked(\d+)$", l) if mode == "overflow" else None
        if m:
            v, _, b = m.groups(); j = len(out) - 1
            while j >= 0 and not out[j].startswith(f" {v} =l "): j -= 1
            if j >= 0 and re.match(r" %v\d+ =l cs[gl]tl ", out[j]): del out[j]; n += 1
            out.append(f" jmp @checked{b}"); i += 1; continue
        out.append(l); i += 1
    f["il"] = "\n".join(out)
json.dump(d, open(dst, "w")); print(mode, "sites rewritten:", n)
