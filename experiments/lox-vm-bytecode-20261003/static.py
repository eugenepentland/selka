#!/usr/bin/env python3
"""Recheck bytecode source/emission/actual ELF diagnostics without measurements."""
from pathlib import Path
from collections import Counter
import hashlib,json,re,subprocess
lane=Path(__file__).resolve().parents[2]
work=lane/'.tmp-lox-vm-bytecode-20261003'
root=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
labels=['control','octets-v1','octets-v2','octets-shape-v3']
result={}
for label in labels:
    emission=work/(label+'-emission.json')
    document=json.loads(emission.read_text())
    functions={f['name']:f for f in document['functions']}
    entry={'emission_sha256':sha(emission),'functions':{},'actual_vm_run':{}}
    for name in ['vm::run','vm::read_byte','vm::read_short','vm::read_constant','chunk::write_byte']:
        function=functions[name];il=function['il'];calls=Counter(re.findall(r'call \$([\w]+)',il))
        normalized=Counter()
        for symbol,count in calls.items():
            key='rc-glue-'+symbol.rsplit('_rcg_',1)[1] if '_rcg_' in symbol else symbol
            normalized[key]+=count
        entry['functions'][name]={'symbol':function['symbol'],'il_sha256':hashlib.sha256(il.encode()).hexdigest(),
            'lines':len(il.splitlines()),'calls':dict(normalized),
            'positive_index_sites':il.count('# QBE-POSITIVE-INDEX-1'),
            'u8_list_take_sites':calls['myl_t_abc546e4d9157545598aaa0ab1373c7cb072a1ae6e3d370ba28044545a9a7482_rcg_take'],
            'casts':calls['myl_qbe_fail_cast'],'bounds':calls['myl_qbe_fail_normalized_index_bounds'],
            'overflows':calls['myl_qbe_fail_overflow_op']}
    for backend in ['llvm','qbe']:
        binary=root/('.tmp-lox-next/bin/combined-'+backend) if label=='control' else work/(label+'-'+backend)
        symbol=functions['vm::run']['symbol'];argv=['objdump','-d','--no-show-raw-insn','--disassemble='+symbol,str(binary)]
        assembly=subprocess.check_output(argv,text=True)
        instructions=re.findall(r'^\s*[0-9a-f]+:\s+([^\n]+)',assembly,re.M)
        entry['actual_vm_run'][backend]={'argv':argv,'binary':str(binary),'binary_sha256':sha(binary),
            'assembly_sha256':hashlib.sha256(assembly.encode()).hexdigest(),
            'instructions':len(instructions),'calls':sum(x.startswith('call') for x in instructions),
            'byte_loads_movzb':sum('movzb' in x for x in instructions)}
    result[label]=entry
output=work/'static-final.json'
assert not output.exists()
output.write_text(json.dumps(result,indent=2)+'\n')
for label in labels:
    print(label, {b:(r['instructions'],r['calls']) for b,r in result[label]['actual_vm_run'].items()})
