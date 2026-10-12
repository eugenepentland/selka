#!/usr/bin/env python3
"""Inventory active Core ABI construction/calls; no compiler or source mutations."""
from pathlib import Path
import argparse
import io
import tarfile
import collections
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
parser = argparse.ArgumentParser()
parser.add_argument("--source-revision")
parser.add_argument("--output-dir", type=Path)
args = parser.parse_args()
HERE = args.output_dir or Path(__file__).resolve().parent
HERE.mkdir(parents=True, exist_ok=True)
APIS = {
    'build.zig': {'buildModule', 'buildRoots', 'buildModuleSource', 'buildExecutable', 'buildExecutableCached', 'buildRootsSource', 'buildRootsCached', 'coverage', 'coverageSource', 'coverageInput'},
    'emit_llvm.zig': {'emitModule', 'emitModuleWithScratch', 'emitUnitWithScratch'},
    'emit_units.zig': {'emit', 'emitWithScratch', 'emitCached'},
    'emit_release.zig': {'emit'},
    'driver.zig': {'link', 'linkWithScratch', 'wholeUnit', 'runtimeDirectory'},
    'pipeline.zig': {'build', 'emitted', 'emittedWithScratch', 'emittedCached', 'validateSource', 'verifyOwnership'},
    'test_support.zig': {'buildSource', 'runModule', 'runOwned', 'irText', 'llvmText', 'factsText', 'optimizedText', 'releaseLlvmText', 'verifyLlvmText', 'releaseLlvmTextFor', 'ownedText'},
}
TYPES = {'build.zig': {'Input'}, 'ir.zig': {'Module'}, 'pipeline.zig': {'Options', 'Codegen'}, 'emission_cache.zig': {'Artifact', 'Dependencies'}, 'test_support.zig': {'Hand'}, 'emit_release.zig': {'Parts'}, 'driver.zig': {'Request'}, 'emit_units.zig': {'Unit'}}

def mask(text):
    """Retain source offsets while excluding comments, literals and guest snippets."""
    out=list(text)
    token=re.compile(r'//[^\n]*|\\\\[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
    for hit in token.finditer(text):
        for i in range(hit.start(),hit.end()):
            if out[i]!='\n': out[i]=' '
    return ''.join(out)

def balanced(text, start):
    depth=0
    for i in range(start,len(text)):
        if text[i]=='(': depth+=1
        elif text[i]==')':
            depth-=1
            if depth==0: return i+1
    return start+1

def enclosing(text, position):
    hits=list(re.finditer(r'(?m)^\s*(?:(?:pub|inline)\s+)?fn\s+(\w+)\s*\(|^test\s+"([^"]+)"',text[:position]))
    if not hits: return None
    return hits[-1].group(1) or 'test '+hits[-1].group(2)

def classification(module, method, text):
    if module=='build.zig':
        if method in {'buildModule','buildRoots','buildModuleSource','buildRootsSource','coverage','coverageSource'}: return 'implicit build.Input defaults via wrapper'
        if re.search(r'\.zero_rc\s*=\s*false',text): return 'explicit legacy ABI request'
        if re.search(r'\.zero_rc\s*=\s*true',text): return 'explicit owned ABI request; source validation audited separately'
        if re.search(r'\.zero_rc\s*=',text): return 'forwarded ABI expression'
        if re.search(r'\.\{\s*\.program',text): return 'inline build.Input omits mode defaults'
        return 'forwarded build.Input; inspect producer'
    if module=='test_support.zig': return 'shared helper inherits build.Input or supplied ir.Module, not pipeline default'
    if module in {'emit_llvm.zig','emit_units.zig','emit_release.zig'}: return 'emission inherits supplied ir.Module ABI'
    if module=='driver.zig': return 'link/runtime ABI derives from emitted marker and dependencies'
    return 'pipeline options and supplied module must agree'

records=[]
constructors=[]
mode_sites=[]
internal_calls=[]
references=[]
files={}
if args.source_revision:
    archive=subprocess.check_output(['git','archive',args.source_revision,'src'],cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        sources={ROOT/member.name:tree.extractfile(member).read().decode() for member in tree if member.isfile() and member.name.endswith('.zig')}
else:
    sources={path:path.read_text() for path in (ROOT/'src').rglob('*.zig')}
for path,source in sorted(sources.items()):
    masked=mask(source)
    relative=str(path.relative_to(ROOT))
    imports={}
    for match in re.finditer(r'\bconst\s+(\w+)\s*=\s*@import\("([^"]+)"\)',source):
        target=(path.parent/match.group(2)).resolve()
        if target.parent==ROOT/'src/core' and target.name in set(APIS)|set(TYPES): imports[match.group(1)]=target.name
    seen=set()
    for alias,module in imports.items():
        for method in APIS.get(module,set()):
            for hit in re.finditer(r'\b'+re.escape(alias)+r'\.'+method+r'\s*\(',masked):
                end=balanced(masked,masked.index('(',hit.start()))
                text=source[hit.start():end]
                records.append({'path':relative,'line':source.count('\n',0,hit.start())+1,'module':module,'method':method,'context':enclosing(source,hit.start()),'kind':classification(module,method,text),'call':text})
                seen.add(hit.start())
        for ty in TYPES.get(module,set()):
            for hit in re.finditer(r'\b'+re.escape(alias)+r'\.'+ty+r'\b',masked):
                line=source.count('\n',0,hit.start())+1
                constructors.append({'path':relative,'line':line,'module':module,'type':ty,'context':enclosing(source,hit.start()),'source':source.splitlines()[line-1].strip()})
    # Capture any qualified API value references as well as ordinary calls.
    for alias,module in imports.items():
        for method in APIS.get(module,set()):
            for hit in re.finditer(r'\b'+re.escape(alias)+r'\.'+method+r'\b(?!\s*\()',masked):
                references.append({'path':relative,'line':source.count('\n',0,hit.start())+1,'module':module,'method':method})
    # Implementation wrappers make unqualified calls to their own public API.
    if path.parent==ROOT/'src/core' and path.name in APIS:
        for method in APIS[path.name]:
            for hit in re.finditer(r'(?<![.\w])'+method+r'\s*\(',masked):
                if re.search(r'\bfn\s+$',masked[max(0,hit.start()-12):hit.start()]): continue
                end=balanced(masked,masked.index('(',hit.start()))
                internal_calls.append({'path':relative,'line':source.count('\n',0,hit.start())+1,'method':method,'context':enclosing(source,hit.start()),'call':source[hit.start():end]})
    # Direct @import(...).method invocations cannot be found in the masked text.
    for hit in re.finditer(r'@import\("([^"]+)"\)\.(\w+)\s*\(',source):
        target=(path.parent/hit.group(1)).resolve()
        if target.parent!=ROOT/'src/core' or hit.group(2) not in APIS.get(target.name,set()): continue
        if masked[hit.start():hit.start()+7]!='@import': continue
        opening=source.index('(',hit.start()+len('@import('))
        end=balanced(masked,opening)
        text=source[hit.start():end]
        records.append({'path':relative,'line':source.count('\n',0,hit.start())+1,'module':target.name,'method':hit.group(2),'context':enclosing(source,hit.start()),'kind':classification(target.name,hit.group(2),text),'call':text})
    for hit in re.finditer(r'@import\("([^"]+)"\)\.(\w+)\b',source):
        target=(path.parent/hit.group(1)).resolve()
        if target.parent!=ROOT/'src/core' or hit.group(2) not in TYPES.get(target.name,set()): continue
        if masked[hit.start():hit.start()+7]!='@import': continue
        line=source.count('\n',0,hit.start())+1
        constructors.append({'path':relative,'line':line,'module':target.name,'type':hit.group(2),'context':enclosing(source,hit.start()),'source':source.splitlines()[line-1].strip()})
    # Include every active mode field definition/write/use, including cache encoders.
    for line_no,(line,code) in enumerate(zip(source.splitlines(),masked.splitlines()),1):
        if re.search(r'\b(single_owner|zero_rc)\b',code):
            mode_sites.append({'path':relative,'line':line_no,'source':line.strip(),'context':enclosing(source,sum(len(x)+1 for x in source.splitlines()[:line_no-1]))})
    if any(row['path']==relative for row in records+constructors+mode_sites): files[relative]=hashlib.sha256(source.encode()).hexdigest()
records.sort(key=lambda r:(r['path'],r['line'],r['method']))
internal_calls.sort(key=lambda r:(r['path'],r['line'],r['method']))
constructors.sort(key=lambda r:(r['path'],r['line'],r['module'],r['type']))
references.sort(key=lambda r:(r['path'],r['line'],r['module'],r['method']))
mode_sites.sort(key=lambda r:(r['path'],r['line']))
report={'source_revision':args.source_revision or subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'scope':'Every src/**/*.zig import-qualified invocation of listed Core APIs; all imported type references and mode-field sites. Public API references and local unqualified implementation calls are enumerated separately. This lexical inventory does not infer the dataflow provenance of module/input variables; producers are reviewed in README. Historical experiment trees excluded. No call-site is evidence of a test pass.','apis':{k:sorted(v) for k,v in APIS.items()},'file_hashes':files,'calls':records,'internal_wrapper_calls':internal_calls,'api_value_references':references,'type_references':constructors,'mode_field_sites':mode_sites,'summary':{'calls':len(records),'internal_wrapper_calls':len(internal_calls),'api_value_references':len(references),'files_with_calls':len(set(r['path'] for r in records)),'type_references':len(constructors),'mode_field_sites':len(mode_sites),'by_api':dict(sorted(collections.Counter(r['module']+'.'+r['method'] for r in records).items()))}}
(HERE/'internal-api-calls.json').write_text(json.dumps(report,indent=2)+'\n')
lines=['# Internal Core call sites','',f"Source revision: `{report['source_revision']}`. This is inventory, not qualification.",'', '| File | Calls | Required migration review |','| --- | ---: | --- |']
for path in sorted(set(row['path'] for row in records)):
    rows=[row for row in records if row['path']==path]
    kinds=sorted(set(row['kind'] for row in rows))
    lines.append(f"| `{path}` | {len(rows)} | {'; '.join(kinds)} |")
(HERE/'internal-api-calls.md').write_text('\n'.join(lines)+'\n')
print(json.dumps(report['summary'],indent=2))
