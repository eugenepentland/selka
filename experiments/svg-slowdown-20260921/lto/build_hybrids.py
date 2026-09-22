#!/usr/bin/env python3
import json, subprocess
from pathlib import Path
root=Path('/home/epentland/ai/canopy/mylang')
out=root/'.tmp/svg-slowdown-20260921/lto'
o3=json.loads((out/'o3-link-argv.json').read_text())
lto=json.loads((out/'lto-link-argv.json').read_text())
zig=o3[0]
source=root/'src/schematic/native_schematic.c'

def compile_provider(argv, lto_mode, output):
    include=argv[argv.index('-I')+1]
    cmd=[zig,'cc','-std=c11','-O3','-g0','-fno-ident','-fPIC','-ffunction-sections','-fdata-sections','-I',include]
    if lto_mode: cmd.append('-flto')
    cmd += ['-c',str(source),'-o',str(output)]
    subprocess.run(cmd,check=True)

def link(argv, provider_index, runtime_index, provider, runtime, output, add_lto=False):
    cmd=argv.copy()
    cmd[provider_index]=str(provider); cmd[runtime_index]=runtime
    cmd[-1]=str(output)
    if add_lto and '-flto' not in cmd: cmd.insert(16,'-flto')
    subprocess.run(cmd,check=True)

native_provider=out/'provider-native.o'; lto_provider=out/'provider-lto.o'
compile_provider(o3,False,native_provider); compile_provider(lto,True,lto_provider)
o3_runtime=o3[-5]; lto_runtime=lto[-5]
link(lto,134,135,lto_provider,o3_runtime,out/'guest-lto-runtime-native')
link(o3,133,134,native_provider,lto_runtime,out/'guest-native-runtime-lto',add_lto=True)
