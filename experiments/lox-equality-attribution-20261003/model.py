#!/usr/bin/env python3
"""Read frozen ELF/IL, walk explicitly chosen paths, never run guest code."""
from pathlib import Path
from collections import Counter
import gzip, hashlib, json, re, subprocess

own = Path(__file__).resolve().parents[2]
work = own / '.tmp-lox-equality-attribution-20261003'
root = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
lower = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003')
borrow = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-borrow-assert-20261003')
eq = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-vm-stack-read-20261003')
screen = root / '.tmp-lox-equal-inline-screen'
e = eq / '.tmp-lox-vm-stack-read-v2-20261003'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
digest = lambda data: hashlib.sha256(data).hexdigest()
files = lambda p: {str(f.relative_to(p)): sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
compiler = lower / '.tmp-lox-lowering/cfg-fix-release/bin/mylang'
qbe = compiler.parent / 'qbe'
source = {'baseline': root / '.tmp-lox-round3/ast', 'candidate': e / 'inline-qualified'}
before = {label: files(p) for label,p in source.items()}
assert all(len(v)==37 for v in before.values())
assert all(files(screen/label)==v for label,v in before.items())
screen_data = json.loads((screen / 'instruction-screen.json').read_text())
assert screen_data['verified_after'] and screen_data['rounds']==1
elf = {label: screen / 'bin' / (label+'-qbe') for label in source}
assert {label:sha(p) for label,p in elf.items()} == {
    'baseline':'246f21781fd58c7141dbe0992101c842e62d732d9ce47e209d55821d02b11b25',
    'candidate':'7ce55fbfe7ec390b5a5d1819f824d44ab3c874384307a4bc5575f5d655b6715e'}
assert sha(compiler)=='d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
assert sha(qbe)=='99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
cache = {'baseline':borrow / '.tmp-lox-borrow-assert-20261003/cache-fixed-qbe',
         'candidate':e / 'cache-qualified-inline-qbe-rc'}
manifests = {}; functions = {}; il = {}; assembly = {}; receipts = {}
work.mkdir(parents=True,exist_ok=True)
for label,p in cache.items():
    mp = next(p.glob('modules/*/out/vm.manifest.json'))
    manifests[label] = json.loads(mp.read_text())
    receipts[str(mp)] = sha(mp)
    functions[label] = {f['name'].split('::')[-1]:f for f in manifests[label]['functions']}
    for name in ['run']+(['equal_stack'] if label=='candidate' else []):
        f = functions[label][name]
        ip = next(p.rglob(f['il_digest']))
        # The compiler's fragment key is BLAKE3, not SHA-256;
        # preserve the independently hashed concrete file actually read here.
        data = ip.read_bytes()
        il[label+'-'+name] = data.decode(); (work/(label+'-'+name+'.ssa')).write_bytes(data)
        argv = ['objdump','-d','--no-show-raw-insn','--disassemble='+f['symbol'],str(elf[label])]
        data = subprocess.check_output(argv)
        assembly[label+'-'+name] = data.decode()
        ap = work/(label+'-'+name+'.asm'); ap.write_bytes(data)
        receipts[str(ip)] = sha(ip)
        receipts[str(ap)] = {'sha256':sha(ap),'argv':argv}
assert functions['baseline']['run']['meta']['inlines'][0]['callee']=='myl_f_393b03e6e8000a2be3bf0bb432f9197ce3fbfd4c525e561e0f9e9b1b3cc38f9b'
assert 'call $myl_f_393b' not in il['baseline-run']
assert 'call $myl_f_432edef' in il['candidate-run']
llvm_elf=screen/'bin/baseline-llvm'
assert sha(llvm_elf)=='180575c3fc2e46a16ed8dd290e289963a87603b5a7c0cf8bb0e03ba7cf794361'
llvm_argv=['objdump','-d','--no-show-raw-insn','--disassemble='+functions['baseline']['run']['symbol'],str(llvm_elf)]
llvm_asm=subprocess.check_output(llvm_argv)
(work/'baseline-llvm-run.asm').write_bytes(llvm_asm)
assert re.search(rb'1133276:\s+movq\s+\$0x1,\(%rcx,%rsi,1\)',llvm_asm)
assert re.search(rb'113327e:\s+mov\s+%rax,0x8\(%rcx,%rsi,1\)',llvm_asm)
annotation=root/'.tmp-lox-vm-annotation-20261003/ast-qbe-vm-string_equality.txt'
receipts[str(llvm_elf)]=sha(llvm_elf)
receipts[str(work/'baseline-llvm-run.asm')]={'sha256':sha(work/'baseline-llvm-run.asm'),'argv':llvm_argv}
receipts[str(annotation)]=sha(annotation)
assert '24.89 :   1132b2c:' in annotation.read_text()

def instructions(text):
    return [(int(m[1],16),m[2],m[3]) for line in text.splitlines()
            if (m:=re.match(r'\s*([0-9a-f]+):\s+(\S+)\s*(.*)',line))]

def walk(text,start,end,choices):
    ins = instructions(text); index={r[0]:i for i,r in enumerate(ins)}
    cursor=index[start]; trace=[]; branches=[]; calls=[]; used=set()
    while True:
        address,op,args=ins[cursor]; trace.append({'address':hex(address),'op':op,'args':args})
        assert op!='ud2'
        if op=='call':calls.append(args)
        if address==end or (end is None and op=='ret'):break
        if op.startswith('j'):
            if op=='jmp':taken=True;reason='unconditional'
            else:
                assert address in choices,hex(address)
                taken,reason=choices[address]; used.add(address)
            branches.append({'address':hex(address),'op':op,'taken':taken,'reason':reason})
            cursor=index[int(args.split()[0],16)] if taken else cursor+1
        else:cursor+=1
        assert len(trace)<500
    assert used==set(choices),(used^set(choices))
    return {'instructions':len(trace),'mnemonics':dict(Counter(r['op'] for r in trace)),
            'calls':calls,'branches':branches,'trace':trace,
            'path_sha256':digest(json.dumps(trace,sort_keys=True).encode())}

old = {
 0x113246b:(True,'operand slot 0 token is empty'),
 0x11324d2:(False,'operand slot 0 token remains empty'),
 0x1132545:(False,'top minus one does not overflow'),
 0x1132575:(True,'unsigned top-1 below stack length'),
 0x1132679:(True,'operand slot 0 token is empty'),
 0x11326e0:(False,'operand slot 0 token remains empty'),
 0x1132753:(False,'top minus two does not overflow'),
 0x1132783:(True,'unsigned top-2 below stack length'),
 0x113288a:(True,'operand slot 0 token is empty'),
 0x11328e9:(False,'retirement top minus one does not overflow'),
 0x1132b45:(True,'operand slot 0 token is empty'),
 0x1132b94:(True,'operand slot 0 token is empty'),
 0x1132c3b:(False,'stack receiver is non-null'),
 0x1132c6f:(False,'ordinary mutable counted stack flags'),
 0x1132c79:(True,'stack has one owner, uniqueness fast path'),
 0x1132cf4:(False,'operand slot 0 token is empty'),
 0x1132d67:(False,'write top minus one does not overflow'),
 0x1132d75:(True,'write index is nonnegative'),
 0x1132e0b:(False,'write index below stack length')}
new = {
 0x113279e:(False,'operand slot 0 token is empty'),
 0x11327ee:(False,'operand slot 1 token is empty'),
 0x11328c1:(True,'borrowed list argument has no token to release'),
 0x113296b:(True,'operand slot 0 token is empty'),
 0x11329dc:(False,'retirement top minus one does not overflow'),
 0x1132a38:(True,'operand slot 0 token is empty'),
 0x1132a87:(True,'operand slot 0 token is empty'),
 0x1132b2e:(False,'stack receiver is non-null'),
 0x1132b62:(False,'ordinary mutable counted stack flags'),
 0x1132b6c:(True,'stack has one owner, uniqueness fast path'),
 0x1132be7:(False,'operand slot 0 token is empty'),
 0x1132c5a:(False,'write top minus one does not overflow'),
 0x1132c68:(True,'write index is nonnegative'),
 0x1132cfe:(False,'write index below stack length')}
tags = {
 'nil':[(0x113293d,True),(0x1132ac4,True)],
 'boolean':[(0x113293d,False),(0x1132947,True),(0x1132a6d,False),(0x1132a73,True)],
 'number':[(0x113293d,False),(0x1132947,False),(0x1132951,True),(0x11329e6,False),(0x11329ec,False),(0x11329f2,True)],
 'object':[(0x113293d,False),(0x1132947,False),(0x1132951,False),(0x1132957,False),(0x1132976,False),(0x113297c,False),(0x1132982,False),(0x1132988,False)]}
helper_paths = json.loads((e/'qbe-static-success-paths.json').read_text())
new_caller = walk(assembly['candidate-run'],0x113278f,0x1132d33,new)
rows=[]
for name,choices in tags.items():
    old_path=walk(assembly['baseline-run'],0x113245c,0x1132e40,
                  old|{p:(v,'both values have tag '+name) for p,v in choices})
    h=next(r['v2_helper'] for r in helper_paths['rows'] if r['same_tag']=={'boolean':'boolean','number':'number','object':'obj','nil':'nil'}[name])
    helper=walk(assembly['candidate-equal_stack'],instructions(assembly['candidate-equal_stack'])[0][0],None,
                {int(r['address'],16):(r['taken'],'matching valid tags and nonnegative in-range operand indices') for r in h['branches'] if r['branch']!='jmp'})
    assert [r['address'] for r in helper['trace']]==h['instruction_addresses']
    assert not old_path['calls'] and not helper['calls'] and len(new_caller['calls'])==1
    rows.append({'same_tag':name,'baseline':old_path,'candidate_caller':new_caller,
                 'candidate_helper':helper,'baseline_total':old_path['instructions'],
                 'candidate_total':new_caller['instructions']+helper['instructions'],
                 'delta':new_caller['instructions']+helper['instructions']-old_path['instructions']})

# All 16 valid tag pairs, including mismatches used by equality.  Comparisons
# within payloads use set instructions, so true/false/NaN outcomes do not
# alter this particular chosen branch trace.
left_old=[(0x113293d,'je'),(0x1132947,'je'),(0x1132951,'je'),(0x1132957,'jne')]
left_new=[(0x1125c4c,'je'),(0x1125c60,'jne'),(0x1125c6a,'je'),(0x1125c70,'jne')]
right_old={0:[(0x1132ac4,'je'),(0x1132aca,'je'),(0x1132ad0,'je'),(0x1132ad6,'jne')],
           1:[(0x1132a6d,'je'),(0x1132a73,'je'),(0x1132a79,'je'),(0x1132a7f,'jne')],
           2:[(0x11329e6,'je'),(0x11329ec,'je'),(0x11329f2,'je'),(0x11329f8,'jne')],
           3:[(0x1132976,'je'),(0x113297c,'je'),(0x1132982,'je'),(0x1132988,'jne')]}
right_new={0:[(0x1125d7f,'je'),(0x1125d85,'je'),(0x1125d8b,'je'),(0x1125d91,'je')],
           1:[(0x1125d3e,'je'),(0x1125d44,'je'),(0x1125d4a,'je'),(0x1125d50,'jne')],
           2:[(0x1125cd5,'je'),(0x1125cdb,'je'),(0x1125ce1,'je'),(0x1125ce7,'jne')],
           3:[(0x1125c81,'je'),(0x1125c87,'je'),(0x1125c8d,'je'),(0x1125c93,'jne')]}
def tag_choices(chain,tag,description):
    result={}
    for value,(address,op) in enumerate(chain):
        # Left bool's jne tests a scalar bool produced by sete, so it is
        # taken for bool; the final jne tests invalid enum tag directly.
        taken=(tag==value) if op=='je' or value==1 else tag!=value
        result[address]=(taken,description)
        if tag==value:break
    return result
matrix=[]
for left in range(4):
    for right in range(4):
        original=walk(assembly['baseline-run'],0x113245c,0x1132e40,
                      old|tag_choices(left_old,left,'left valid tag '+str(left))|
                      tag_choices(right_old[left],right,'right valid tag '+str(right)))
        helper=walk(assembly['candidate-equal_stack'],0x1125ac0,None,
                    {0x1125ad9:(False,'top-1 cannot overflow'),0x1125af9:(True,'top-1 below length'),
                     0x1125b9b:(False,'top-2 cannot overflow'),0x1125bab:(True,'top-2 below length')}|
                    tag_choices(left_new,left,'left valid tag '+str(left))|
                    tag_choices(right_new[left],right,'right valid tag '+str(right)))
        matrix.append({'left':left,'right':right,'baseline':original,'helper':helper,
                       'baseline_total':original['instructions'],
                       'candidate_total':new_caller['instructions']+helper['instructions'],
                       'delta':new_caller['instructions']+helper['instructions']-original['instructions']})
adjacent={
 'fetch':{'baseline':walk(assembly['baseline-run'],0x112cdc0,0x112cee2,
             {0x112cded:(True,'nonnegative IP'),0x112ce50:(False,'IP below code length'),
              0x112ce69:(True,'operand token empty'),0x112ced1:(False,'IP increment no overflow')}),
          'candidate':walk(assembly['candidate-run'],0x112d110,0x112d235,
             {0x112d13d:(True,'nonnegative IP'),0x112d1a0:(False,'IP below code length'),
              0x112d1b9:(True,'operand token empty'),0x112d224:(False,'IP increment no overflow')})},
 'pop_handler':{'baseline':walk(assembly['baseline-run'],0x1135da2,0x1135e53,
                 {0x1135dbb:(False,'operand token empty'),0x1135e40:(False,'top decrement no overflow')}),
                'candidate':walk(assembly['candidate-run'],0x1135c61,0x1135d15,
                 {0x1135c7d:(False,'operand token empty'),0x1135d02:(False,'top decrement no overflow')})},
 'common_tail':{'baseline':walk(assembly['baseline-run'],0x1136f68,0x1136f79,
                 {0x1136f73:(False,'handler succeeded')}),
                'candidate':walk(assembly['candidate-run'],0x1136e33,0x1136e44,
                 {0x1136e3e:(False,'handler succeeded')})}}
for pair in adjacent.values():pair['delta']=pair['candidate']['instructions']-pair['baseline']['instructions']

def window(text,start,end):
    start='\n'+start;end='\n'+end
    return text[text.index(start)+1:text.index(end,text.index(start))]
old_eq=window(il['baseline-run'],'@i648\n','@i789\n')
new_eq=window(il['candidate-run'],'@i648\n','@i698\n')
assert 'rcg_take' not in old_eq and 'rcg_take' not in new_eq
assert 'rcg_loan' not in old_eq and 'rcg_loan' not in new_eq
il_stats={label:{'blits':len(re.findall(r'^ blit ',s,re.M)),
                 'take_sites':len(re.findall(r'call \$\w*rcg_take',s)),
                 'loan_sites':len(re.findall(r'call \$\w*rcg_loan',s)),
                 'unloan_sites':len(re.findall(r'call \$\w*rcg_unloan',s)),
                 'drop_sites':len(re.findall(r'call \$\w*rcg_drop',s)),
                 'positive_index_fast_reads':len(re.findall('QBE-POSITIVE-INDEX-1 start',s))}
          for label,s in [('baseline_opcode',old_eq),('candidate_opcode',new_eq),('candidate_helper',il['candidate-equal_stack'])]}
for label,s in [('baseline-opcode',old_eq),('candidate-opcode',new_eq)]:
    (work/(label+'.ssa')).write_text(s)
samples=screen_data['samples'];assert len(samples)==104
assert all(r['status']==0 and all(r[x+'_running_pct']==100 for x in ['instructions','cycles','branches','branch-misses']) for r in samples)
counter = {}
for case in ['vm/equality','vm/string_equality']:
    r={v['arm']:v for v in samples if v['case']==case}
    assert set(r)=={'baseline-qbe','candidate-qbe','baseline-llvm','candidate-llvm'}
    assert len({v['stdout_sha256'] for v in r.values()})==1
    counter[case]={backend:{'baseline':r['baseline-'+backend]['instructions'],
                    'candidate':r['candidate-'+backend]['instructions'],
                    'relative_delta':r['candidate-'+backend]['instructions']/r['baseline-'+backend]['instructions']-1}
                    for backend in ['llvm','qbe']}
proof_files=['src/qbe_rc_readonly_anchor.zig','src/qbe_rc_record_read_plan.zig',
             'src/qbe_rc_ops.zig','src/qbe_rc_readonly_calls.zig','src/qbe_rc_borrow.zig',
             'src/rc_readonly_body.zig','src/qbe.zig']
after={label:files(p) for label,p in source.items()};assert before==after
result={'kind':'Static full OP_EQUAL path attribution; no guest execution, timing, compiler change or qualification',
        'source37_before':before,'source37_after':after,
        'selected_compiler':str(compiler),'compiler_sha256':sha(compiler),'qbe_sha256':sha(qbe),
        'guest_elf':{label:{'path':str(p),'sha256':sha(p)} for label,p in elf.items()},
        'input_receipts':receipts,'actual_il_digest':{label:{name:f['il_digest'] for name,f in functions[label].items() if name in ['run','equal_stack']} for label in functions},
        'baseline_values_equal_inline_metadata':functions['baseline']['run']['meta']['inlines'][0],
        'path_bounds':{'baseline':['0x113245c','0x1132e40'],'candidate_caller':['0x113278f','0x1132d33'],'exclude':'opcode dispatch admission, common VM-loop tail and enclosing prologue/epilogue; include last jump to common tail and all helper entry/return instructions'},
        'successful_path_model':rows,'all16_tag_pairs':matrix,'adjacent_paths':adjacent,'actual_il_static_sites':il_stats,
        'central_instruction_screen':{'path':str(screen/'instruction-screen.json'),'sha256':sha(screen/'instruction-screen.json'),'rounds':1,'samples':104,'all_four_PMU_running_pct_100':True,'selected_case_counts':counter},
        'selected_proof_source_sha256':{str(lower/p):sha(lower/p) for p in proof_files},
        'supersedes':'The earlier four-instruction V1-helper-to-V2-helper reduction does not compare the centrally selected AST baseline; that baseline inlines values_equal.',
        'limits':['Static chosen paths are not measured opcode traces or frequency counts.','Assume operand journal slots 0/1 empty at opcode entry, nonnegative in-range top-1/top-2, non-null ordinary mutable one-owner stack and matching valid tags.','Snapshot/COW slow path, negative indexing, malformed tags, exhausted quotas, native errors and later loop cleanup are not counted by this successful-path model.','Canonical fallback normalizers, cast/bounds/overflow failures, release branches and COW uniqueness slow paths remain in both exact ILs.','Public/native correctness coverage is in the separately committed independent review; no new suite is run here.'],
        'verified_after':True}
(work/'model.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'same_tag_totals':[{k:r[k] for k in ['same_tag','baseline_total','candidate_total','delta']} for r in rows],
                  'candidate_caller':new_caller['instructions'],
                  'all16_deltas':[[r['left'],r['right'],r['delta']] for r in matrix],
                  'adjacent_deltas':{label:p['delta'] for label,p in adjacent.items()},
                  'il':il_stats,'central':counter},indent=2))
