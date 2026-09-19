import json, sys, re
src, dst = sys.argv[1], sys.argv[2]
d = json.load(open(src))
n_rewritten = n_memset = 0; k = 0
for f in d["functions"]:
    lines = f["il"].split("\n"); out = []
    i = 0
    while i < len(lines):
        l = lines[i]
        l = re.sub(r"^ (%root\d+) =l alloc8 24$", r" \1 =l alloc8 32", l)
        m_add = re.match(r" (%v\d+) =l add (%root\d+), 8$", l)
        if m_add and i + 1 < len(lines):
            m_st = re.match(r" storel (%[ls]\d+), (%v\d+)$", lines[i+1])
            if m_st and m_st.group(2) == m_add.group(1):
                at, root = m_add.groups(); slot = m_st.group(1); k += 1
                out.append(l)
                out.append(f" %cfx{k} =l loadl {slot}\n %cfy{k} =l add {root}, 24\n storel %cfx{k}, %cfy{k}\n storel %cfy{k}, {at}")
                n_rewritten += 1; i += 2; continue
        m_ms = re.match(r" call \$memset\(l (%l\d+), w 0, l 8\)$", l)
        if m_ms:
            out.append(f" storel 0, {m_ms.group(1)}"); n_memset += 1; i += 1; continue
        out.append(l); i += 1
    f["il"] = "\n".join(out)
json.dump(d, open(dst, "w"))
print(f"{src.split('/')[-1]}: root pushes rewritten to hold values: {n_rewritten}; 8-byte memsets replaced: {n_memset}")
