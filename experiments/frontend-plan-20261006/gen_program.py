import sys
n=int(sys.argv[1]); out=[]
out.append("record Acc:\n    total: int\n    count: int\n")
for i in range(n):
    prev = f"f{i-1}(k - 1)" if i else "k"
    out.append(f"""def f{i}(k: int) -> int:
    items: list[int] = []
    for j in range(k % 17 + 3):
        items.append(j * {i % 7 + 1} + k)
    acc = Acc(total=0, count=0)
    for v in items:
        if v % 3 == 0:
            acc = Acc(total=acc.total + v, count=acc.count + 1)
        else:
            acc = Acc(total=acc.total - 1, count=acc.count)
    seen: dict[int, int] = {{}}
    seen[k % 5] = acc.total
    label = "f{i}:" + str(acc.count)
    return acc.total + len(label) + seen[k % 5] + {prev} % 1000
""")
out.append(f"""def main(out: Stream) -> int:
    out.print(str(f{n-1}(40)))
    return 0
""")
open(sys.argv[2],"w").write("\n".join(out))
