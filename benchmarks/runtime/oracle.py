"""Independent, deliberately simple specification evaluator (never timed)."""
MOD = 1000000007
CASES = ('record_reads', 'tagged_stack', 'mutate_unique', 'mutate_shared')
def checksum(case, size, iterations, seed):
    if case == 'record_reads':
        records = [((seed+j*17)%1009, (seed*3+j*7)%257, [j+seed+k for k in range(4)]) for j in range(size)]
        index, total = seed % size, 0
        for _ in range(iterations):
            code, bias, payload = records[index]
            value = code + bias + payload[0]
            total = (total + value) % MOD
            index = (index + 2 * seed + 1) % size
        return total
    if case == 'tagged_stack':
        ops = [(j+seed)%4 for j in range(size)]
        stack = [('int', seed), ('bool', False)]
        for step in range(iterations):
            kind, top = stack.pop()
            op = ops[step % size]
            delta = ((3 if top else 1) if op == 0 else (7,11,13)[op-1]) if kind == 'bool' else top % (5,7,11,13)[op]
            base = (stack[0][1]+delta+op+1)%1000003
            stack[0] = ('int', base)
            stack.append(('bool', base%2 == 0) if op in (0,2) else ('int', base%97))
        return stack[0][1]*101 + int(stack[1][1])
    if case not in CASES:
        raise ValueError(case)
    values = [(seed+j*13)%1009 for j in range(size)]
    total = 0
    for batch in range(iterations):
        index = (seed+batch*17)%size
        before = values.copy() if case == 'mutate_shared' else None
        values[index] = (values[index]+batch+1)%1000003
        total = (total+values[index]+(before[index] if before is not None else 0))%MOD
    return (total+sum(values))%MOD
