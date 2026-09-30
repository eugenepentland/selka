import hashlib
import json
from pathlib import Path
import subprocess

root = Path('.tmp/plain-query/abi')
records = []

def run(command, path):
    result = subprocess.run([str(x) for x in command], text=True, capture_output=True)
    text = 'exit '+str(result.returncode)+' '+repr([str(x) for x in command])+'\n'+result.stdout+result.stderr
    path.write_text(text)
    print(text,end='',flush=True)
    assert result.returncode==0
    return result.stdout

for mode,opt,lto in [('none-o0','-O0',[]),('none-o3','-O3',[]),('full','-O3',['-flto=full']),('thin','-O3',['-flto=thin'])]:
    dest=root/mode;dest.mkdir(exist_ok=True)
    common=['zig','cc','-std=c11',opt,'-DMYL_NATIVE_RC=1','-Wall','-Wextra','-Werror','-UNDEBUG','-Isrc','-ffunction-sections','-fdata-sections']+lto
    for label,source in [('production','src/native_collections.c'),('caller',root/'probes/caller.c'),('oracle',root/'probes/oracle.c')]:
        run(common+['-c',source,'-o',dest/(label+'.o')], dest/(label+'-build.log'))
    run(common+[dest/(name+'.o') for name in ['production','caller','oracle']]+['-Wl,--gc-sections','-o',dest/'probe'],dest/'link.log')
    stdout=run([dest/'probe'],dest/'run.log')
    hot=run([dest/'probe','hot'],dest/'hot-run.log')
    symbols=run(['nm',dest/'probe'],dest/'nm.log')
    assert 'myl_rc_list_plain_ready' in symbols
    assert 'myl_rc_list_plain_ready_hot' in symbols
    if mode.startswith('none'):
        assert ' T myl_rc_list_plain_ready' in symbols
        assert ' T myl_rc_list_plain_ready_hot' in symbols
    records.append(dict(mode=mode,cases_per_alias=15,status=0,stdout=stdout,hot_stdout=hot,callable_symbol_defined=True,external_T_symbol= ' T myl_rc_list_plain_ready' in symbols,binary_sha256=hashlib.sha256((dest/'probe').read_bytes()).hexdigest()))
(root/'probe-results.json').write_text(json.dumps(records,indent=2)+'\n')
