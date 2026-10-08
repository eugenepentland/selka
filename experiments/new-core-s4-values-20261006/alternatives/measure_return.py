#!/usr/bin/env python3
"""Measure the alternate return ABI through the inherited strict five-arm tool."""
import importlib.util
from pathlib import Path
root=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('s4measure',root/'experiments/new-core-s4-20261006/integration/measure_all46.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
original=module.rows.configurations
binary=root/'.mylang-cache/s4-v/union-find-cheaper-return'
def configs(args,row):
    result=original(args,row)
    result['new core release']=lambda size,iterations:[str(binary),str(size),str(iterations),str(module.rows.SEED)]
    return result
module.rows.configurations=configs
raise SystemExit(module.main())
