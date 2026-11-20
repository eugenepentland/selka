"""Specification evaluator: bounded 17-phase cycles, never timed."""
import bisect
MOD = 1000000007
_NAMES = {
    'integer_math': ('scalar', 'integer multiply, add, divide, remainder'),
    'float_math': ('scalar', 'exact dyadic f64 multiply/add, scaled integer fold'),
    'branch_predictable': ('control', '15/16 true deterministic branch fixture'),
    'branch_mixed': ('control', 'approximately balanced deterministic branch fixture'),
    'record_construct': ('records', 'construct a three-scalar record and read fields'),
    'record_update': ('records', 'copy an existing record, update three fields, read fields'),
    'call_direct': ('calls', 'ordinary direct call to affine helper A'),
    'call_indirect': ('calls', 'seed-selected first-class callable A or B'),
    'option_handle': ('errors', 'native optional scalar, 3/4 present by input residue'),
    'result_propagate': ('errors', 'native result propagated through a second helper, 4/5 success'),
    'binary_search': ('search', 'checked binary search of sorted scalar keys'),
    'packet_decode': ('protocol', 'validate byte frames and decode record results'),
}
CASES = {name: dict(family=family, level='application' if name == 'packet_decode' else 'micro', sizes=[16,256] if name in ('binary_search','packet_decode') else [64,4096], unit='one complete pass over SIZE fixtures', description=description) for name,(family,description) in _NAMES.items()}


def frame(j, seed):
    identifier = (seed+j*17)%65536
    data = [(seed+j*13+k*7)%256 for k in range(4)]
    raw = [165,1,identifier//256,identifier%256,4,*data]
    raw.append(sum(raw)%256)
    if j%4 == 1: raw[0]=164
    elif j%4 == 2: raw[-1]=(raw[-1]+1)%256
    elif j%4 == 3: raw[4]=5
    return bytes(raw)


def packet(raw):
    if raw[0]!=165: return 101
    if raw[1]!=1: return 202
    if len(raw)!=raw[4]+6: return 303
    if sum(raw[:-1])%256!=raw[-1]: return 404
    return (raw[2]*256+raw[3])+sum(raw[5:-1])*3+raw[4]


def checksum(case,size,iterations,seed):
    if case not in CASES: raise ValueError(case)
    values=[(seed+j*37)%1009 for j in range(size)]
    ordered=[j*3+seed%11 for j in range(size)]
    def phase_total(phase):
        total=0
        for j,x in enumerate(values):
            if case=='integer_math': value=((x+phase)*17+23)//7%1009
            elif case=='float_math': value=int(((x/8+phase/4)*(x/16+1)+0.5)*128)
            elif case.startswith('branch_'):
                flag=j%16!=0 if case=='branch_predictable' else (x*73+j*19+seed)%101<50
                value=(x+phase)*3+1 if flag else (x+phase)*5+7
            elif case.startswith('record_'): value=x+phase+3*(x%17)+5*((x*3+phase)%101)
            elif case=='call_direct': value=(x+phase)*3+7
            elif case=='call_indirect': value=(x+phase)*(3 if seed%2==0 else 5)+(7 if seed%2==0 else 11)
            elif case=='option_handle': value=19 if x%4==0 else (x+phase)*3+1
            elif case=='result_propagate': value=7 if x%5==0 else (x+phase)*3+1
            elif case=='binary_search':
                key=(x+phase)%(size*3+3)+seed%11
                found=bisect.bisect_left(ordered,key)
                value=found+1 if found<size and ordered[found]==key else 0
            else: value=packet(frame(j,seed))
            total+=value
        return total
    cycles,remainder=divmod(iterations,17)
    sums=[phase_total(p) for p in range(17)]
    return (cycles*sum(sums)+sum(sums[:remainder]))%MOD
