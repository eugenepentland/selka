"""Independent collection and execution-only application checksum specification."""
MOD = 1000000007
NAMES = ('list_scan','list_append','list_filter','dict_lookup','dict_lookup_str','dict_update','dict_update_str','set_dedup','alloc_short','alloc_retained','mutate_nested','sort_int','sort_records','lox_eval')
CASES = {name: {'family': 'lox' if name == 'lox_eval' else ('library-sort' if name.startswith('sort') else name.split('_')[0]), 'level': 'application' if name == 'lox_eval' else 'micro', 'sizes': [16,256] if name == 'lox_eval' else ([64,1024] if name.startswith('alloc') or name == 'mutate_nested' else [64,4096]), 'unit': 'one complete SIZE-element dataset operation' if name != 'lox_eval' else 'one complete bytecode program execution with SIZE loop iterations', 'description': name.replace('_',' ')} for name in NAMES}

def checksum(case, size, iterations, seed):
    if case not in CASES or size < 2 or iterations < 1 or not 1 <= seed <= 1000000:
        raise ValueError('invalid fixture')
    if case.startswith('alloc_'):
        per_first = 4*size*seed + 2*size*(size-1) + 6*size
        return (iterations*per_first + 2*size*iterations*(iterations-1)) % MOD
    if case == 'lox_eval':
        # Compose the independently specified source program as an affine map.
        coefficient, offset = 1, 0
        for i in range(size):
            if i%2 == 0:
                coefficient = coefficient*3 % 1000003
                offset = (offset*3+7) % 1000003
            else:
                offset = (offset+i) % 1000003
        return sum((coefficient*(seed+b)+offset)%1000003 for b in range(iterations)) % MOD
    period = 1009 if case in ('list_scan','list_append','list_filter','sort_int','sort_records') else (size*2 if case.startswith('dict_lookup') else (max(2,size//4) if case == 'set_dedup' else iterations))
    cycles, remainder = divmod(iterations, period)
    result = 0
    values = [(seed+j*13)%1009 for j in range(size)]
    nested = [[(seed+j*13+k)%1009 for k in range(4)] for j in range(size)]
    for batch in range(min(iterations, period)):
        if case == 'list_scan':
            part = sum((v+batch)%1009 for v in values)
        elif case in ('list_append','list_filter','sort_int','sort_records'):
            xs = [(seed+batch+j*13)%1009 for j in range(size)]
            if case == 'list_filter': xs = [v for v in xs if v%3 == 0]
            if case == 'sort_int': xs.sort()
            if case == 'sort_records':
                rs = sorted(((v%17,j,v) for j,v in enumerate(xs)),key=lambda r:r[0])
                part = sum((i+1)*(v*17+j) for i,(_,j,v) in enumerate(rs))
            else: part = sum((i+1)*v for i,v in enumerate(xs))
        elif case.startswith('dict_lookup'):
            part = sum(values[k] if (k := (seed+j*17+batch)%(size*2)) < size else 17 for j in range(size))
        elif case.startswith('dict_update'):
            d = {j:values[j] for j in range(size)}
            for j in range(size*2):
                k=(seed+j*17+batch)%(size*2)
                d[k]=(d.get(k,17)+j+batch+1)%1000003
            part=sum(k+v for k,v in d.items())
        elif case == 'set_dedup': part=sum({(seed+batch+j*13)%max(2,size//4) for j in range(size)})
        elif case.startswith('alloc_'): part=sum(4*(seed+batch+j)+6 for j in range(size))
        elif case == 'mutate_nested':
            i=(seed+batch*17)%size;old=nested[i][1];nested[i][1]=(old+batch+1)%1000003;part=old+nested[i][1]
        else:
            total=seed+batch
            for i in range(size): total=(total*3+7)%1000003 if i%2==0 else (total+i)%1000003
            part=total
        weight = cycles + (1 if batch < remainder else 0)
        result=(result+part*weight)%MOD
    if case == 'mutate_nested': result=(result+sum(map(sum,nested)))%MOD
    return result
