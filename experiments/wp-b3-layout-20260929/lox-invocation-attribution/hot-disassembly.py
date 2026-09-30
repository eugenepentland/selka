import difflib,json,re
from pathlib import Path
work=Path(__file__).resolve().parent;data=json.loads((work/'exact-counts.json').read_text())
chosen=['myl_f_a0e96f299197f34d601c1a9da1cbd514090305d2a21036d06ba179b733ea6e29','myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6','myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14_rcg_loan']
for fn in chosen:
    normalized={}
    for side in ['control','candidate']:
        text=(work/side/'assembly').read_text().split('<'+fn+'>:\n',1)[1].split('\n\n',1)[0]
        ips=data[side]['instructions'][fn];rows=[];norm=[]
        for line in text.splitlines():
            match=re.match(r'\s*([0-9a-f]+):\s*(.*)',line)
            if match:
                address=int(match[1],16);ins=match[2];count=ips.get(hex(address),0)
                rows.append(f'{count:12d} {address:x}: {ins}')
                norm.append(re.sub(r'\b[0-9a-f]+ <','<',ins))
        (work/side/(fn+'.weighted-assembly.txt')).write_text('\n'.join(rows)+'\n');normalized[side]=norm
    (work/(fn+'.diff')).write_text('\n'.join(difflib.unified_diff(normalized['control'],normalized['candidate'],fromfile='control',tofile='candidate',lineterm=''))+'\n')
