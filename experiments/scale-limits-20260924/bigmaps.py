"""Summarize strace -k output: mmap/mremap calls of at least N MB with their stacks."""
import re
import sys

path, floor = sys.argv[1], int(sys.argv[2]) * 1024 * 1024
lines = open(path).read().split("\n")
i = 0
calls = []
while i < len(lines):
    line = lines[i]
    m = re.search(r"(mmap\((?:NULL|0x[0-9a-f]+), (\d+)|mremap\(0x[0-9a-f]+, (\d+), (\d+))", line)
    if m:
        size = int(m.group(2) or m.group(4))
        old = int(m.group(3)) if m.group(3) else 0
        stack = []
        j = i + 1
        while j < len(lines) and lines[j].startswith(" > "):
            frame = lines[j]
            n = re.search(r"\(([^)+]+)\+0x", frame)
            if n and not n.group(1).startswith(("heap.", "mem.Allocator", "array_list", "posix", "os.linux", "Io.", "heap_")):
                stack.append(n.group(1))
            j += 1
        if size >= floor:
            calls.append((size, old, "mremap" if old else "mmap", stack[:6]))
        i = j
        continue
    i += 1
for size, old, kind, stack in calls:
    print(f"{kind:6} {size // 2**20:6} MB (from {old // 2**20} MB)  " + " < ".join(stack))
