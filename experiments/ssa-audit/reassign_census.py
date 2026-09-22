import re, sys, glob, collections
files = sorted(set(glob.glob('experiments/sexpr-port/**/*.my', recursive=True) + glob.glob('tests/lang/*.my') + glob.glob('src/schematic/guest/**/*.my', recursive=True) + glob.glob('src/stdlib/**/*.my', recursive=True)))
assign = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)(\s*:\s*[^=]+)?\s*=(?!=)')
total_fns = 0; fns_with_reassign = 0; names = 0; reassigned = 0; loop_carried = 0
for f in files:
    cur = None; counts = collections.Counter(); in_loop_assign = set()
    def flush():
        global total_fns, fns_with_reassign, names, reassigned, loop_carried
        if cur is None: return
        total_fns += 1
        names += len(counts)
        multi = [n for n, c in counts.items() if c > 1]
        reassigned += len(multi)
        if multi: fns_with_reassign += 1
        loop_carried += len([n for n in multi if n in in_loop_assign])
    loop_depth_stack = []
    for line in open(f, encoding='utf-8', errors='replace'):
        if re.match(r'^\s*(public\s+)?def\s', line):
            flush(); cur = line.strip(); counts = collections.Counter(); in_loop_assign = set(); loop_depth_stack = []
            continue
        if cur is None: continue
        indent = len(line) - len(line.lstrip(' '))
        while loop_depth_stack and indent <= loop_depth_stack[-1]: loop_depth_stack.pop()
        m = assign.match(line)
        if m and m.group(1) not in ('return','if','elif','while','for','with','match','case','assert','pass'):
            counts[m.group(1)] += 1
            if loop_depth_stack: in_loop_assign.add(m.group(1))
        if re.match(r'^\s*(for|while)\b', line): loop_depth_stack.append(indent)
    flush()
print(f'files={len(files)} functions={total_fns} functions_with_a_reassigned_local={fns_with_reassign} ({100*fns_with_reassign/max(1,total_fns):.0f}%)')
print(f'distinct_local_names={names} reassigned_names={reassigned} ({100*reassigned/max(1,names):.0f}%) reassigned_inside_a_loop={loop_carried}')
