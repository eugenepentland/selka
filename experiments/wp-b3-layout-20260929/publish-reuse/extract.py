from pathlib import Path
import json,re,subprocess
out=Path('.tmp/pub-proof');compiler=Path('.tmp/pub/bin/mylang').resolve()
r=subprocess.run([str(compiler),'emit-qbe',str(out/'source.my'),'--rc-runtime'],capture_output=True,text=True);(out/'emit.log').write_text(r.stderr);assert r.returncode==0,r.stderr
(out/'manifest.json').write_text(r.stdout);manifest=json.loads(r.stdout);il=next(f['il'] for f in manifest['functions'] if f['name']=='keep');(out/'keep.ssa').write_text(il)
fragments=[];receipt={};symbols={}
for name,op in [('owner','drop'),('hold','unloan')]:
 m=re.search(r' # RC-GLUE-1 '+op+r'\n (%v\d+) =l copy %heap\n (%v\d+) =l loadl (%v\d+)\n .*?\n@rcgdone\d+\n',il,re.S);assert m,name
 body=m[0];sym=re.search(r'\$(\w+_rcg_'+op+r')',body).group(1);symbols[name]=sym
 receipt[name]={'source_range':[m.start(),m.end()],'raw_body':body,'symbol':sym,'slot':m[3]}
 body=re.sub(re.escape(m[3])+r'\b','%slot',body)
 fragments.append('export function w $review_'+name+'(l %ctx, l %heap, l %slot) {\n@start\n'+body+' ret 1\n}\n')
m=re.search(r' # RC-GLUE-1 publish\n.*?\n@rcgpublished\d+\n',il,re.S);assert m,'publish'
body=m[0];call=re.search(r'\$(\w+_rcg_publish)\(l %heap, l (%v\d+), l (%v\d+), w (%v\d+), w (%v\d+)\)',body);assert call,body
symbols['publish']=call[1];receipt['publish']={'source_range':[m.start(),m.end()],'raw_body':body,'symbol':call[1],'dst':call[2],'src':call[3],'region':call[4],'mode':call[5]}
for value,param in zip(call.groups()[1:],['dst','src','region','mode']):body=re.sub(re.escape(value)+r'\b','%'+param,body)
fragments.append('export function w $review_publish(l %ctx, l %heap, l %dst, l %src, w %region, w %mode) {\n@start\n'+body+' ret 1\n@failure\n ret 0\n}\n')
(out/'fragments.ssa').write_text('\n'.join(fragments));(out/'extraction.json').write_text(json.dumps(receipt,indent=2)+'\n');(out/'symbols.h').write_text(''.join('#define '+name.upper()+'_SYMBOL "'+symbol+'"\n' for name,symbol in symbols.items()))
