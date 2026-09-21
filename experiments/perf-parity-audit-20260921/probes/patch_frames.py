"""Counterfactual IL patcher: strip the per-call frame protocol from every function's IL.
Modes: F = frame record link/unlink + stack-floor check; T = sticky trap test after calls; P = position stores.
Diagnostic only: a patched program cannot report traps correctly."""
import json, re, sys
src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(src))
removed = 0
for f in d["functions"]:
    lines = f["il"].split("\n"); out = []
    rec = None; act = None; pos_slot = None; skip_until = None
    for L in lines:
        m = re.match(r" %v(\d+) =l alloc8 32$", L)
        if m and rec is None: rec = m.group(1)
        m = re.match(r" %v(\d+) =l add %ctx, 48$", L)
        if m: act = m.group(1)
        if rec and (m := re.match(rf" %v(\d+) =l add %v{rec}, 16$", L)): pos_slot = m.group(1)
        if "F" in mode:
            if skip_until:
                if L.startswith(skip_until): skip_until = None; out.append(L)
                removed += 1; continue
            if re.match(r" %v\d+ =l add %ctx, 64$", L):  # stack floor check: skip through @stackadmitN label
                skip_until = "@stackadmit"; removed += 1; continue
            if act and re.match(rf" %v\d+ =l loadl %v{act}$", L): removed += 1; continue
            if act and rec and re.match(rf" storel %v\d+, %v{rec}$", L): removed += 1; continue
            if re.match(r" storel extern \$\S+_meta, %v\d+$", L): removed += 1; continue
            if pos_slot and L == f" storel 0, %v{pos_slot}": removed += 1; continue
            if act and rec and L == f" storel %v{rec}, %v{act}": removed += 1; continue
            if act and re.match(rf" storel %v\d+, %v{act}$", L): removed += 1; continue
            if rec and re.match(rf" %v\d+ =l loadl %v{rec}$", L): removed += 1; continue
        if "T" in mode:
            if re.match(r" %v\d+ =l loadl %trap$", L): removed += 1; continue
            if (m := re.match(r" jnz %v\d+, @failure, @ok(\d+)$", L)): out.append(f" jmp @ok{m.group(1)}"); removed += 1; continue
        if "P" in mode and re.match(r" storel \d+, %position$", L): removed += 1; continue
        out.append(L)
    f["il"] = "\n".join(out)
json.dump(d, open(dst, "w"))
print(f"{mode}: removed {removed} lines")
